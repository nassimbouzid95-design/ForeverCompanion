import json, collections, sys
al = json.load(open('/tmp/claude-0/data/al.json'))
rates = json.load(open('/tmp/claude-0/data/rates.json'))
cm = json.load(open('/tmp/claude-0/data/cmangos.json'))
def table(name):
    t = cm[name]; c = t['cols']
    return [dict(zip(c, r)) for r in t['rows']]
ct = {int(r['Entry']): r for r in table('creature_template')}
items = {int(r['entry']): r for r in table('item_template')}
spawns = collections.defaultdict(set)
for r in table('creature'):
    spawns[int(r['map'])].add(int(r['id']))
def loot_index(name):
    d = collections.defaultdict(list)
    for r in table(name):
        d[int(r['entry'])].append((int(r['item']), float(r['ChanceOrQuestChance']), int(r['groupid']), int(r['mincountOrRef'])))
    return d
clt = loot_index('creature_loot_template'); rlt = loot_index('reference_loot_template')

def chances(entries, factor=1.0, depth=0, out=None):
    out = out if out is not None else collections.defaultdict(float)
    groups = collections.defaultdict(list)
    for e in entries: groups[e[2]].append(e)
    for gid, es in groups.items():
        if gid == 0:
            for item, ch, _, ref in es:
                p = abs(ch) / 100.0
                if ref < 0:
                    if depth < 4: chances(rlt.get(-ref, []), factor * p, depth + 1, out)
                else:
                    out[item] = 1 - (1 - out[item]) * (1 - factor * p)
        else:
            explicit = sum(abs(e[1]) for e in es if e[1] != 0)
            zeros = [e for e in es if e[1] == 0]
            share = max(0.0, 100 - explicit) / len(zeros) if zeros else 0
            for item, ch, _, ref in es:
                p = (abs(ch) if ch != 0 else share) / 100.0
                if ref < 0:
                    if depth < 4: chances(rlt.get(-ref, []), factor * p, depth + 1, out)
                else:
                    out[item] = 1 - (1 - out[item]) * (1 - factor * p)
    return out

def npc_loot(npc):
    t = ct.get(npc)
    if not t: return {}
    lid = int(t['LootId'] or 0)
    if not lid: return {}
    return {k: v * 100 for k, v in chances(clt.get(lid, [])).items()}

RANK = {0: '', 1: 'elite', 2: 'rareelite', 3: 'boss', 4: 'rare'}
def npc_info(npc):
    t = ct.get(npc)
    if not t: return {}
    lo, hi = int(t['MinLevel']), int(t['MaxLevel'])
    return {'level': (str(lo) if lo == hi else f"{lo}-{hi}") if int(t['Rank']) != 3 else '??',
            'hp': int(t['MaxLevelHealth']), 'name': t['Name'], 'rank': int(t['Rank'])}

SIZE = {'Dungeons': 5, '20 Raids': 20, '40 Raids': 40}
FIX_ID = {'DireMaulEast': 429, 'DireMaulWest': 429, 'DireMaulNorth': 429}
LBRS = {'UpperBlackrockSpire': 10}
out = []
allbossnpcs = set()
for inst in al:
    for b in inst['bosses']:
        n = b['npcID']
        for x in (n if isinstance(n, list) else [n] if n else []): allbossnpcs.add(x)

def lua_str(s): return '"' + str(s).replace('\\', '\\\\').replace('"', '\\"') + '"'

lines = ["-- ForeverCompanion: dungeon & raid database (generated, do not edit by hand).",
         "-- Bosses, loot lists and boss drop rates: AtlasLootClassic (GPL v2, https://github.com/Hoizame/AtlasLootClassic).",
         "-- Creature health, levels, trash creatures and trash drop chances: CMaNGOS classic-db (https://github.com/cmangos/classic-db).",
         "-- Format: { key, id = instanceMapID, name, kind, size, enter, min, max, bosses = { boss }, trash = { mob } }",
         "--   boss = { name, npc = id, level, hp, loot = { itemID, rate, itemID, rate, ... } }  (rate -1 = unknown)",
         "local _, ns = ...", "", "ns.InstanceDB = {"]
stats = collections.Counter()
for inst in al:
    key = inst['key']
    iid = inst['instanceID'] or FIX_ID.get(key)
    kind = 'world' if key == 'WorldBosses' else ('raid' if 'Raid' in inst['content'] else 'dungeon')
    size = LBRS.get(key, SIZE.get(inst['content'], 40))
    if key == 'LowerBlackrockSpire': size = 5
    lv = inst.get('levels') or [60, 60, 60]
    name = inst['name'] if inst['name'] and not inst['name'].startswith('Area') else None
    if inst['name'].startswith('Area796'):
        name = 'Scarlet Monastery - ' + inst['name'].split(' - ')[1]
    lines.append("\t{")
    lines.append(f"\t\tkey = {lua_str(key)}, id = {iid or 'nil'}, name = {lua_str(name) if name else 'nil'}, kind = {lua_str(kind)}, size = {size}, enter = {lv[0]}, min = {lv[1]}, max = {lv[2]},")
    lines.append("\t\tbosses = {")
    for b in inst['bosses']:
        npc = b['npcID']
        npcs = npc if isinstance(npc, list) else ([npc] if npc else [])
        main = npcs[0] if npcs else None
        info = npc_info(main) if main else {}
        loot = []
        seen = set()
        cml = {}
        for n in npcs: cml.update(npc_loot(n))
        for slot, item, diff in sorted(b['loot']):
            if item in seen: continue
            seen.add(item)
            r = None
            for n in npcs:
                r = rates['rates'].get(str(n), {}).get(str(item), r)
            if r is None: r = rates['override'].get(str(item))
            if r is None and item in cml: r = round(cml[item], 2); stats['cmangos_rate'] += 1
            if r is None: stats['norate'] += 1
            else: stats['rate'] += 1
            loot.append(f"{item}, {r if r is not None else -1}")
        kindb = 'extra' if b['extra'] else ('rare' if b['special'] == 'rare' else 'boss')
        lvl = b['level'] or info.get('level', '')
        parts = [f"name = {lua_str(b['name'])}"]
        if main: parts.append(f"npc = {main}")
        if lvl: parts.append(f"level = {lua_str(lvl)}")
        if info.get('hp'): parts.append(f"hp = {info['hp']}")
        if kindb != 'boss': parts.append(f"type = {lua_str(kindb)}")
        lines.append("\t\t\t{ " + ", ".join(parts) + ", loot = { " + ", ".join(loot) + " } },")
    lines.append("\t\t},")
    # trash creatures spawned in this instance with notable drops
    trash = []
    if iid and kind != 'world' and key not in ('ScarletMonasteryLibrary', 'ScarletMonasteryArmory', 'ScarletMonasteryCathedral', 'DireMaulWest', 'DireMaulNorth', 'UpperBlackrockSpire'):
        for npc in sorted(spawns.get(iid, [])):
            if npc in allbossnpcs: continue
            info = npc_info(npc)
            if not info or info['rank'] in (3,) : continue
            loot = npc_loot(npc)
            notable = []
            for item, r in loot.items():
                it = items.get(item)
                if not it: continue
                q = int(it['Quality'])
                if (q >= 3 and r >= 0.05) or (q == 2 and r >= 1.0):
                    notable.append((r, item))
            notable.sort(reverse=True)
            notable = notable[:12]
            if not notable: continue
            trash.append((npc, info, notable))
            stats['trash_items'] += len(notable)
    lines.append("\t\ttrash = {")
    for npc, info, notable in trash:
        lt = ", ".join(f"{i}, {round(r, 2)}" for r, i in notable)
        lines.append(f"\t\t\t{{ name = {lua_str(info['name'])}, npc = {npc}, level = {lua_str(info['level'])}, hp = {info['hp']}, loot = {{ {lt} }} }},")
    lines.append("\t\t},")
    lines.append("\t},")
lines.append("}")
open(sys.argv[1], 'w').write("\n".join(lines) + "\n")
print(stats)
