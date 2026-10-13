#!/usr/bin/env python3
"""Profession leveling plans 1-300 for Data/Professions.lua.

Inputs (made by the extraction scripts next to this one):
  al.json   AtlasLootClassic recipe table (tools/parse_atlasloot_prof.py): skill levels, reagents, product
  vdb.json  VMaNGOS world dump (tools/sqldump.py): spell_template (teach spells), npc_trainer(_template), npc_vendor(_template)
  cdb.json  CMaNGOS classic-db (tools/sqldump.py): item_template (prices), creature_template (trainer titles), npc_vendor

For each crafting profession the cheapest way up is chosen skill point by skill point: the recipe with the lowest
expected cost per point (material cost minus what the product sells for to a vendor, divided by the chance of a
skill-up: 100 % while orange, then (grey - skill) / (grey - yellow)).  Only recipes taught by the normal trainers
or sold without limit by vendors are used, so every step can be done by anyone.  Material cost: the vendor price
for what vendors sell, otherwise the game's own item value (about four times the vendor sell price, which follows
the auction house closely enough to compare materials of the same tier); smelted bars and materials the profession
makes itself cost what their own materials cost.

Usage: build_professions.py al.json vdb.json cdb.json out.lua
"""
import collections
import json
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import forever_db as F   # Questie's WoW Forever NPC data: which side a vendor serves and where it stands

AL, VDB, CDB, OUT = sys.argv[1:5]
a = json.load(open(AL))
v = json.load(open(VDB))
c = json.load(open(CDB))

RECIPES = {int(k): x for k, x in a['prof'].items()}
RECIPE_ITEM = {int(k): x for k, x in a['recipe_item_of_spell'].items()}
ITEMS = {r['entry']: r for r in c['item_template']}

# AtlasLoot profession number -> (key, skill line, max skill)
PROFS = {
    4: ('alchemy', 171), 2: ('blacksmithing', 164), 10: ('enchanting', 333), 9: ('engineering', 202),
    3: ('leatherworking', 165), 8: ('tailoring', 197), 6: ('cooking', 185), 1: ('firstaid', 129),
}
MINING = 7

# -- which recipes can anyone learn ------------------------------------------------------------------------------
spells = {}
for r in v['spell_template']:
    spells[r['entry']] = r
teach = {}
for sid, r in spells.items():
    for e, t in ((r['effect1'], r['effectTriggerSpell1']), (r['effect2'], r['effectTriggerSpell2'])):
        if e == 36 and t:
            teach[sid] = t
creatures = {r['Entry']: r for r in c['creature_template']}
template_users = collections.defaultdict(list)
for r in c['creature_template']:
    if r['TrainerTemplateId']:
        template_users[r['TrainerTemplateId']].append(r['Entry'])
SPECIALIST = ('Goblin', 'Gnome', 'Shadoweave', 'Weapon', 'Armor', 'smith', 'Dragonscale', 'Tribal', 'Elemental')
NORMAL_SUB = ('Blacksmith',)  # "Master Blacksmith" contains "smith" but teaches everyone


def specialist(sub):
    if not sub:
        return False
    if any(sub.endswith(n) or sub == 'Expert ' + n or sub.startswith(('Journeyman', 'Master', 'Artisan', 'Expert')) and sub.split(' ', 1)[1] == n
           for n in NORMAL_SUB):
        return False
    return any(k in sub for k in SPECIALIST)


trainable = {}
for table, kind in (('npc_trainer', 'npc'), ('npc_trainer_template', 'tpl')):
    for r in v[table]:
        t = teach.get(r['spell'], r['spell'])
        ents = [r['entry']] if kind == 'npc' else template_users.get(r['entry'], [])
        subs = [creatures[e]['SubName'] for e in ents if e in creatures] or [None]
        if any(not specialist(s) for s in subs):
            trainable[t] = min(trainable.get(t, 1 << 30), r['spellcost'])

vendor_items = {}
templ_vendor = collections.defaultdict(list)
for r in c.get('npc_vendor_template', []):
    templ_vendor[r['entry']].append(r)
for r in c['npc_vendor']:
    if not r['maxcount']:
        vendor_items.setdefault(r['item'], set()).add(r['entry'])
for cr in c['creature_template']:
    for r in templ_vendor.get(cr['VendorTemplateId'] or -1, []):
        if not r['maxcount']:
            vendor_items.setdefault(r['item'], set()).add(cr['Entry'])


auto = {r['spell_id'] for r in v['skill_line_ability'] if r['learn_on_get_skill'] == 1}
NPCS = F.load('Npc')


def recipe_vendors(sid, side):
    """Vendors that sell the recipe of this spell without limit to this side ('A' or 'H'), as Questie NPC rows."""
    out = []
    for e in sorted(vendor_items.get(RECIPE_ITEM.get(sid), ())):
        n = NPCS.get(str(e))
        if n and side in (F.L(n, 13) or '') and F.L(n, 7):
            out.append((e, n))
    return out


COOLDOWN = {r['entry'] for r in v['spell_template'] if (r.get('recoveryTime') or 0) + (r.get('categoryRecoveryTime') or 0) >= 3600000}


def learnable(sid, side=None):
    if sid in COOLDOWN:
        return None
    if sid in trainable or sid in auto:
        return 'trainer'
    item = RECIPE_ITEM.get(sid)
    if item and ITEMS.get(item, {}).get('RequiredReputationFaction'):
        return None   # needs a reputation first
    if item and item in vendor_items and (side is None or recipe_vendors(sid, side)):
        return 'vendor'
    # a pattern that drops in the world (common or uncommon): bought at the auction house, as a last resort
    if item and item in ITEMS and ITEMS[item]['Quality'] <= 2 and ITEMS[item].get('bonding') != 1 and side is not None:
        return 'ah'
    return None


# -- material costs ---------------------------------------------------------------------------------------------
def base_price(item):
    it = ITEMS.get(item)
    if not it:
        return 10000
    if it['BuyPrice']:
        return it['BuyPrice'] / max(1, it['BuyCount'])
    return max(1, it['SellPrice']) * 4 or 5 * it['ItemLevel'] ** 2


makers = collections.defaultdict(list)   # item -> recipes of profession p (or mining) that make it
for sid, r in RECIPES.items():
    if r['item'] and (learnable(sid) or r['prof'] == MINING):
        makers[r['item']].append(sid)

_price = {}


def price(item, prof, depth=0):
    key = (item, prof)
    if key in _price:
        return _price[key]
    best = base_price(item)
    if depth < 4 and item not in vendor_items:
        for sid in makers.get(item, []):
            r = RECIPES[sid]
            if r['prof'] not in (prof, MINING):
                continue
            cost = sum(price(g, prof, depth + 1) * n for g, n in zip(r['reag'], r['cnt'])) / max(1, r['n'])
            best = min(best, cost)
    _price[key] = best
    return best


# Materials that only drop (elementals, gems, scales...) cost more than their item value says: fewer of them on the
# auction house and nobody gathers them.
RARE = 3
RARE_WORDS = ('Heart of', 'Core of', 'Globe of', 'Breath of', 'Essence of', 'Elemental', 'Ichor', 'Scale', 'Pearl', 'Orb',
              'Shadowgem', 'Moss Agate', 'Moonstone', 'Jade', 'Citrine', 'Aquamarine', 'Star Ruby', 'Tigerseye', 'Malachite',
              'Diamond', 'Sapphire', 'Opal', 'Emerald', 'Arcanite', 'Transformer', 'Enchanted', 'Spider', 'Fang', 'Venom',
              'Blood', 'Mooncloth', 'Felcloth', 'Iridescent', 'Shard', 'Feather', 'Gizzard', 'Claw', 'Sac', 'Pelt', 'Tooth', 'Morrowgrain', 'Power Crystal')


def rare(item):
    name = ITEMS.get(item, {}).get('name', '')
    return item not in vendor_items and any(w in name for w in RARE_WORDS)


FISH_WORDS = ('Snapper', 'Eel', 'Blackmouth', 'Catfish', 'Raw ', 'Trout', 'Yellowtail', 'Salmon', 'Lobster', 'Mackerel', 'Smallfish')


def fish(item):
    return any(w in ITEMS.get(item, {}).get('name', '') for w in FISH_WORDS)


def recipe_cost(sid, prof):
    r = RECIPES[sid]
    cost = sum(price(g, prof) * n * (RARE if rare(g) else 2 * RARE if prof != 6 and fish(g) else 1) for g, n in zip(r['reag'], r['cnt']))
    if learnable(sid, 'A') == 'ah':
        cost += base_price(RECIPE_ITEM[sid]) * RARE / 10 + 20000   # the pattern, shared over the crafts; hard to find
    return max(cost, 1)


def chance(r, skill):
    if skill >= r['high']:
        return 0
    if skill < r['low']:
        return 1
    return (r['high'] - skill) / max(1, r['high'] - r['low'])


# -- the plans ----------------------------------------------------------------------------------------------------
def plan(prof, side):
    pool = [sid for sid, r in RECIPES.items() if r['prof'] == prof and learnable(sid, side)
            and r['high'] > r['low'] >= r['min'] > 0 and r['reag']]
    steps = []
    cur = None
    skill = 1
    while skill < 300:
        options = []
        for sid in pool:
            r = RECIPES[sid]
            if r['min'] > skill:
                continue
            ch = chance(r, skill)
            if ch <= 0:
                continue
            options.append((recipe_cost(sid, prof) / ch, sid))
        if not options:
            break
        best = min(options)
        # keep the current recipe unless another one is clearly cheaper (fewer recipe changes)
        if cur is not None:
            mine = [o for o in options if o[1] == cur]
            if mine and mine[0][0] <= best[0] * 1.25:
                best = mine[0]
        sid = best[1]
        crafts = 1 / chance(RECIPES[sid], skill)
        if steps and steps[-1]['spell'] == sid:
            steps[-1]['to'] = skill + 1
            steps[-1]['crafts'] += crafts
        else:
            steps.append({'from': skill, 'to': skill + 1, 'spell': sid, 'crafts': crafts})
        cur = sid
        skill += 1
    out = []
    for s in steps:
        r = RECIPES[s['spell']]
        n = math.ceil(s['crafts'] - 0.15)
        out.append({'from': s['from'], 'to': s['to'], 'spell': s['spell'], 'item': r['item'], 'n': n,
                    'reag': [[g, k * n] for g, k in zip(r['reag'], r['cnt'])],
                    'vendor': RECIPE_ITEM.get(s['spell']) if learnable(s['spell'], side) == 'vendor' else None,
                    'ah': RECIPE_ITEM.get(s['spell']) if learnable(s['spell'], side) == 'ah' else None,
                    'cost': round(recipe_cost(s['spell'], prof) * n)})
    return out, skill


def lua(v):
    if v is None:
        return 'nil'
    if isinstance(v, bool):
        return 'true' if v else 'false'
    if isinstance(v, (int, float)):
        return str(int(v)) if float(v).is_integer() else repr(v)
    if isinstance(v, str):
        return '"' + v.replace('\\', '\\\\').replace('"', '\\"') + '"'
    if isinstance(v, list):
        return '{' + ','.join(lua(x) for x in v) + '}'
    raise TypeError(v)


def where(npc_id, n):
    spawns = F.L(n, 7) or {}
    for zone, pts in sorted(spawns.items(), key=lambda kv: -len(F.lst(kv[1]))):
        pts = [p for p in F.lst(pts) if p]
        if pts:
            p = F.lst(pts[0])
            return [npc_id, int(zone), round(p[0], 1), round(p[1], 1), F.L(n, 1, '')]
    return [npc_id, 0, 0, 0, F.L(n, 1, '')]


lines = ['-- ForeverCompanion: profession leveling plans 1-300 (generated by tools/build_professions.py, do not edit by hand).',
         '-- Recipes, skill levels and materials from AtlasLootClassic (GPL) and the CMaNGOS / VMaNGOS databases (GPL), vendors from',
         '-- Questie (GPL v3): the cheapest recipe per skill point among those taught by the normal trainers or sold by vendors.',
         '-- Step: { from, to, recipe spell, product item, crafts, { {material, count}, ... }, recipe item to buy from a vendor (negative: pattern from the auction house) or 0, cost in copper }',
         '-- Vendors: [recipe item] = { Alliance = {npcID, areaID, x, y, name}, Horde = {...} }',
         'local _, ns = ...',
         'ns.ProfessionPlans = {']
report = []
vendors_used = {}
for prof, (key, line) in PROFS.items():
    lines.append('\t%s = { skill = %d,' % (key, line))
    for side, sname in (('A', 'Alliance'), ('H', 'Horde')):
        steps, reached = plan(prof, side)
        total = sum(s['cost'] for s in steps)
        report.append('%-15s %s %3d steps, reaches %d, about %s gold' % (key, side, len(steps), reached, round(total / 10000, 1)))
        lines.append('\t\t%s = {' % sname)
        for s in steps:
            lines.append('\t\t\t{%d,%d,%d,%s,%d,%s,%d,%d},' % (s['from'], s['to'], s['spell'], s['item'] or 0, s['n'], lua(s['reag']),
                                                               s['vendor'] or s['ah'] and -s['ah'] or 0, s['cost']))
            if s['vendor']:
                e, n = recipe_vendors(s['spell'], side)[0]
                vendors_used.setdefault(s['vendor'], {})[sname] = where(e, n)
        lines.append('\t\t},')
    lines.append('\t},')
lines.append('}')
lines.append('ns.ProfessionVendors = {')
for item, sides in sorted(vendors_used.items()):
    lines.append('\t[%d] = { %s },' % (item, ', '.join('%s = %s' % (k, lua(x)) for k, x in sorted(sides.items()))))
lines.append('}')
open(OUT, 'w').write('\n'.join(lines) + '\n')
print('\n'.join(report))
