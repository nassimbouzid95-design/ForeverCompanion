#!/usr/bin/env python3
"""Forever corrections for the dungeon database -> Data/InstanceForever.lua (+ v2-data/instances_forever.json).

Data/InstanceDB.lua comes from AtlasLootClassic, which leaves out the bosses that had no loot of their own in
Classic (Oggleflint and Bazzalan in Ragefire Chasm, four of the Stockade bosses...).  WoW Forever gave many of them
new loot and added new items to most low-level bosses.  This step reads the Forever database (QuestieDB, see
forever_db.py) and:
  * adds the missing bosses at their place in the instance (ROSTER below),
  * adds every new Forever item (ID >= 200000, weapon or armour) to the boss that drops it,
  * adds new Forever items dropped by an instance's trash to its "Trash" entry,
  * fills the loot of the new Forever dungeons from the same data when the scraped list missed an item.
Drop rates of these additions are unknown (-1); the drop collector measures them in game.

Usage: lua5.1 dumpidb.lua idb.json (from the addon folder), then python3 build_instfix.py idb.json
"""
import sys, os, json, collections
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from forever_db import load, L, lst

ADDON = '/mnt/project-files/addon/ForeverCompanion'
OUT = os.path.join(ADDON, 'Data/InstanceForever.lua')
OUT_JSON = '/mnt/project-files/addon/v2-data/instances_forever.json'

# Bosses missing from AtlasLoot, with the boss they follow in the instance (None = first).
ROSTER = {
    'Ragefire': [(11517, None), (11519, 11518)],                      # Oggleflint first, Bazzalan after Jergosh
    'BlackfathomDeeps': [(12902, 6243)],                              # Lorgus Jett after Gelihast
    'TheStockade': [(1696, None), (1717, 1666), (1716, 1717), (1663, 1716)],  # Targorr, Kam, Hamhock, Bazil, Dextren
    'RazorfenKraul': [(6168, None)],                                  # Roogug
}

NEW_ID = 200000


def lua_str(s):
    return '"' + s.replace('\\', '\\\\').replace('"', '\\"') + '"'


# Dungeon quests: Forever removed some Classic ones and added new ones; AtlasLoot/CMaNGOS missed a few Horde ones.
DQ_ADD = {
    'Ragefire': [5723],
    'TheDeadmines': [92753],
    'BlackfathomDeeps': [6564, 6565, 6922, 95042],
    'ScarletMonasteryLibrary': [1160, 96800],
}
DQ_REMOVE = {
    'Gnomeregan': [4601, 4602, 4603, 4604, 4605, 4606],   # Sparklematic 5200: not in Forever
}
ALLI, HORDE = 77 | 1 << 32, 178 | 1 << 33


def dungeon_quests(d):
    """Lua lines adding/removing dungeon quests, with their DungeonQuestInfo built from the Forever database."""
    import re
    Q, N, I, O = load('Quest'), load('Npc'), load('Item'), load('Object')
    qdb = json.load(open(os.path.join(os.environ.get('FDB_DIR', '/tmp/claude-0/fdb'), 'questdb.json')))
    bl = set(int(x) for x in re.findall(r'\d+', open(os.path.join(os.environ.get('FDB_DIR', '/tmp/claude-0/fdb'), 'blacklist.txt')).read()))
    rewards = collections.defaultdict(list)
    for iid, it in I.items():
        for q in lst(L(it, 6)):
            if q: rewards[int(q)].append(int(iid))
    lines = ['', '-- Dungeon quests: removed in Forever, then added (Forever data)',
             'local REMOVE = { ' + ', '.join('[%s] = { %s }' % (lua_str(k), ', '.join(map(str, v))) for k, v in DQ_REMOVE.items()) + ' }',
             'for key, ids in pairs(REMOVE) do',
             '\tlocal l, drop = ns.DungeonQuests[key] or {}, {}',
             '\tfor _, id in ipairs(ids) do drop[id] = true end',
             '\tfor i = #l, 1, -1 do if drop[l[i]] then table.remove(l, i) end end',
             'end']
    for key, qs in DQ_ADD.items():
        for q in qs:
            if q in bl: raise SystemExit('blacklisted quest %d' % q)
            r = Q[str(q)]
            info = qdb.get(str(q))
            races = L(r, 6, 0) or 0
            side = 1 if races and not races & HORDE else 2 if races and not races & ALLI else 0
            st = lst(L(r, 2) or {}) + [None, None, None]
            def who(lst3, pos):
                npcs = [n for n in lst(lst3[0]) if n] if lst3[0] else []
                objs = [n for n in lst(lst3[1]) if n] if lst3[1] else []
                items = [n for n in lst(lst3[2]) if n] if len(lst3) > 2 and lst3[2] else []
                if npcs:
                    name = L(N[str(npcs[0])], 1)
                elif objs:
                    name = L(O[str(objs[0])], 1)
                elif items:
                    return '{ %s, nil, nil, nil, 1, %d }' % (lua_str(L(I[str(items[0])], 1)), items[0])
                else:
                    return 'nil'
                if pos and pos[0] >= 0:
                    return '{ %s, %d, %d, %d, 0 }' % (lua_str(name), pos[0], pos[1], pos[2])
                if pos:
                    return '{ %s, %d, %d, %d, 0 }' % (lua_str(name), pos[0], pos[1], pos[2])
                return '{ %s }' % lua_str(name)
            giver = who(st, info and info.get('s'))
            fin = lst(L(r, 3) or {}) + [None, None]
            turnin = who(fin, info and info.get('e'))
            obj = L(r, 10) or {}
            kills = []
            for c in lst(obj.get('1')):
                c = lst(c)
                if c and str(c[0]) in N:
                    name = L(N[str(c[0])], 1)
                    m = re.search(r'(\d+)\s+' + re.escape(name), ' '.join(x for x in lst(L(r, 8)) if x))
                    kills += [lua_str(name), m.group(1) if m else '1']
            items = []
            for c in lst(obj.get('3')):
                c = lst(c)
                if c and c[0]: items += [str(c[0]), str(c[1] if len(c) > 1 and c[1] else 1)]
            text = ' '.join(x for x in lst(L(r, 8)) if x)
            rw = sorted(rewards.get(q, []))
            parts = [lua_str(L(r, 1)), str(L(r, 5) or 0), str(L(r, 4) or 0), str(side), str(races), str(L(r, 7, 0) or 0),
                     str(max(lst(L(r, 12)) or [0]) or (lst(L(r, 13)) or [0])[0] or 0),
                     'giver = ' + giver, 'turnin = ' + turnin, 'objectives = ' + lua_str(text)]
            if items: parts.append('items = { %s }' % ', '.join(items))
            if kills: parts.append('kills = { %s }' % ', '.join(kills))
            if rw: parts.append('%s = { %s }' % ('choice' if len(rw) > 1 else 'reward', ', '.join('%d, 1' % i for i in rw)))
            lines.append('ns.DungeonQuestInfo[%d] = { %s }' % (q, ', '.join(parts)))
        lines.append('do local l = ns.DungeonQuests[%s] if l then for _, id in ipairs({ %s }) do if not tContains(l, id) then l[#l + 1] = id end end end end'
                     % (lua_str(key), ', '.join(map(str, qs))))
    return lines + ['']


def main(dump):
    d = json.load(open(dump))
    N, I = load('Npc'), load('Item')
    db = d['db']
    drops = collections.defaultdict(list)
    for iid, it in I.items():
        if L(it, 12) not in (2, 4): continue
        for n in lst(L(it, 2)):
            if n: drops[int(n)].append(int(iid))
    byname = collections.defaultdict(list)
    for k, n in N.items(): byname[L(n, 1)].append(int(k))

    def boss_npcs(b):
        if b.get('npc'): return [b['npc']]
        if b.get('type') == 'extra': return []
        return byname.get(b['name'], [])

    # which instance entry / boss owns each NPC
    owner = {}
    for e in db:
        for b in e['bosses']:
            for n in boss_npcs(b): owner.setdefault(n, (e['key'], 'boss'))
    for e in db:
        for k, extra in ROSTER.items():
            if e['key'] == k:
                for npc, _ in extra: owner[npc] = (k, 'boss')
    for e in db:
        for t in e.get('trash', []):
            if t.get('npc'): owner.setdefault(t['npc'], (e['key'], 'trash'))
    # trash of the new Forever dungeons is not listed: NPCs sharing the bosses' area, or dropping their trash items
    # (Ruins of Lordaeron trash: Rotmender's set, Sword of the Fallen) are matched by area below.
    areas = {}
    for e in db:
        za = collections.Counter()
        for b in e['bosses']:
            for n in boss_npcs(b):
                if str(n) in N: za.update(int(z) for z in (L(N[str(n)], 7) or {}))
        areas[e['key']] = {a for a, c in za.items()}

    fix = collections.OrderedDict()
    def F(key):
        return fix.setdefault(key, {'add': [], 'loot': collections.OrderedDict(), 'trash': []})

    for key, extra in ROSTER.items():
        for npc, after in extra:
            n = N[str(npc)]
            hp = L(n, 3) or L(n, 2)
            lv = (L(n, 4), L(n, 5))
            level = str(lv[1]) if lv[0] == lv[1] else '%s-%s' % lv
            F(key)['add'].append({'name': L(n, 1), 'npc': npc, 'level': level, 'hp': hp, 'after': after, 'loot': []})

    entry = {e['key']: e for e in db}
    for npc, items in drops.items():
        own = owner.get(npc)
        new = sorted(i for i in items if i >= NEW_ID)
        if not new: continue
        if not own:
            # trash of a new Forever dungeon?  Its NPCs have no spawn data; match the item names of the dungeon set
            continue
        key, kind = own
        e = entry[key]
        have = set()
        for b in e['bosses']: have |= set(x for x in b.get('loot', [])[0::2])
        if kind == 'boss':
            added = [a for a in F(key)['add'] if a['npc'] == npc]
            if added:
                added[0]['loot'] += [i for i in new if i not in added[0]['loot']]
            else:
                bl = [i for i in new if i not in have]
                if bl: F(key)['loot'].setdefault(npc, []).extend(bl)
        else:
            tl = [i for i in new if i not in have and i not in F(key)['trash']]
            # an item shared by many dungeon bosses is not a trash drop
            F(key)['trash'] += [i for i in tl if all(owner.get(int(x), (0, 'trash'))[1] == 'trash' for x in lst(L(I[str(i)], 2)) if x)]

    # Ruins of Lordaeron trash (QuestieDB lists its NPCs without spawns): items dropped only by NPCs that have no
    # spawn and whose IDs sit in the dungeon's NPC range, and that the dungeon bosses do not drop.
    rol = entry.get('RuinsOfLordaeron')
    if rol:
        bossn = [n for b in rol['bosses'] for n in boss_npcs(b)]
        lo, hi = min(bossn) - 1000, max(bossn) + 1000
        for npc, items in drops.items():
            if npc in owner or not (lo <= npc <= hi) or str(npc) not in N: continue
            n = N[str(npc)]
            if L(n, 7) or L(n, 9): continue
            for i in items:
                it = I[str(i)]
                if i >= NEW_ID and all(not L(N.get(str(x), {}), 7) for x in lst(L(it, 2)) if x) and i not in F('RuinsOfLordaeron')['trash']:
                    F('RuinsOfLordaeron')['trash'].append(i)

    for k in [k for k, v in fix.items() if not (v['add'] or v['loot'] or v['trash'])]: del fix[k]
    dq_lines = dungeon_quests(d)

    out = ['-- ForeverCompanion: WoW Forever corrections to the dungeon database (generated by tools/build_instfix.py, do not edit by hand).',
           '-- Source: QuestieDB Forever data (GPL v3, https://github.com/Questie/QuestieDB).  Adds the bosses AtlasLoot leaves out',
           '-- (no Classic loot), the new Forever items each boss drops and the new trash drops.  Rates unknown (-1) until measured.',
           'local _, ns = ...', '',
           'local function Entry(key)',
           '\tfor _, e in ipairs(ns.InstanceDB or {}) do if e.key == key then return e end end',
           'end', '',
           'local function Boss(e, npc)',
           '\tfor i, b in ipairs(e.bosses) do if b.npc == npc then return b, i end end',
           'end', '',
           'local function AddLoot(b, items)',
           '\tb.loot = b.loot or {}',
           '\tlocal have = {}',
           '\tfor i = 1, #b.loot, 2 do have[b.loot[i]] = true end',
           '\tfor _, id in ipairs(items) do',
           '\t\tif not have[id] then b.loot[#b.loot + 1] = id; b.loot[#b.loot + 1] = -1; have[id] = true end',
           '\tend',
           'end', '',
           'local FIX = {']
    for key, v in fix.items():
        out.append('\t[%s] = {' % lua_str(key))
        if v['add']:
            out.append('\t\tadd = {')
            for a in v['add']:
                out.append('\t\t\t{ name = %s, npc = %d, level = %s, hp = %d, after = %s, loot = { %s } },' % (
                    lua_str(a['name']), a['npc'], lua_str(a['level']), a['hp'] or 0, a['after'] or 'nil', ', '.join(map(str, a['loot']))))
            out.append('\t\t},')
        if v['loot']:
            out.append('\t\tloot = { ' + ', '.join('[%d] = { %s }' % (n, ', '.join(map(str, l))) for n, l in v['loot'].items()) + ' },')
        if v['trash']:
            out.append('\t\ttrash = { ' + ', '.join(map(str, v['trash'])) + ' },')
        out.append('\t},')
    out += ['}', '',
            'for key, fix in pairs(FIX) do',
            '\tlocal e = Entry(key)',
            '\tif e then',
            '\t\tfor _, a in ipairs(fix.add or {}) do',
            '\t\t\tif not Boss(e, a.npc) then',
            '\t\t\t\tlocal pos = 1',
            '\t\t\t\tif a.after then local _, i = Boss(e, a.after); pos = (i or #e.bosses) + 1 end',
            '\t\t\t\tlocal loot = {}',
            '\t\t\t\tfor _, id in ipairs(a.loot) do loot[#loot + 1] = id; loot[#loot + 1] = -1 end',
            '\t\t\t\ttable.insert(e.bosses, pos, { name = a.name, npc = a.npc, level = a.level, hp = a.hp, loot = loot })',
            '\t\t\t\tfor i = #(e.trash or {}), 1, -1 do if e.trash[i].npc == a.npc then table.remove(e.trash, i) end end',
            '\t\t\tend',
            '\t\tend',
            '\t\tfor npc, items in pairs(fix.loot or {}) do',
            '\t\t\tlocal b = Boss(e, npc)',
            '\t\t\tif b then AddLoot(b, items) end',
            '\t\tend',
            '\t\tif fix.trash then',
            '\t\t\tlocal t',
            '\t\t\tfor _, b in ipairs(e.bosses) do if b.type == "extra" and (b.name == "Trash" or b.name == "Trash Mobs") then t = b end end',
            '\t\t\tif not t then',
            '\t\t\t\tt = { name = "Trash", type = "extra", loot = {} }',
            '\t\t\t\ttable.insert(e.bosses, t)',
            '\t\t\tend',
            '\t\t\tAddLoot(t, fix.trash)',
            '\t\tend',
            '\tend',
            'end', '',
            '-- Wings of the instances listed several times (Scarlet Monastery, Dire Maul, Blackrock Spire)',
            'local WINGS = { ScarletMonasteryGraveyard = "Graveyard", ScarletMonasteryLibrary = "Library", ScarletMonasteryArmory = "Armory",',
            '\tScarletMonasteryCathedral = "Cathedral", DireMaulEast = "East", DireMaulWest = "West", DireMaulNorth = "North",',
            '\tLowerBlackrockSpire = "Lower", UpperBlackrockSpire = "Upper" }',
            'for _, e in ipairs(ns.InstanceDB or {}) do e.wing = e.wing or WINGS[e.key] end', ''] + dq_lines
    open(OUT, 'w').write('\n'.join(out))
    json.dump(fix, open(OUT_JSON, 'w'), indent=1)
    for k, v in fix.items():
        print(k, 'add', [(a['name'], len(a['loot'])) for a in v['add']], 'loot+', sum(len(x) for x in v['loot'].values()), 'trash+', len(v['trash']))


if __name__ == '__main__':
    main(sys.argv[1] if len(sys.argv) > 1 else '/tmp/claude-0/idb.json')
