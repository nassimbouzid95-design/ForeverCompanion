# Builds Data/DungeonQuests.lua: the quests of every dungeon and raid, with giver, turn-in, objectives and rewards.
import json, collections, re
cm = json.load(open('cmangos.json')); qf = json.load(open('dq/quests_full.json'))['quest_template']
it = json.load(open('dq/items.json'))
def table(t, src=cm): c = src[t]['cols']; return [dict(zip(c, r)) for r in src[t]['rows']]
Q = {int(r[0]): dict(zip(qf['cols'], r)) for r in qf['rows']}
items = {int(r['entry']): r for r in table('item_template', it)}
gotpl = {int(r['entry']): r for r in table('gameobject_template', it)}
ct = {int(r['Entry']): r for r in table('creature_template')}
db = open('/mnt/project-files/addon/ForeverCompanion/Data/InstanceDB.lua').read()
# instance blocks: key, map id, npc ids of the wing
blocks = re.split(r'\n\t\{\n', db)
inst = []
for b in blocks:
    m = re.search(r'key = "([^"]+)", id = (\d+)', b)
    if m: inst.append((m.group(1), int(m.group(2)), {int(x) for x in re.findall(r'npc = (\d+)', b)}))
AREAS = {389: [2437], 43: [718], 36: [1581], 33: [209], 48: [719], 34: [717], 90: [133, 721], 47: [1717, 491],
         189: [796], 129: [722], 70: [1517, 1337], 209: [978, 1176], 349: [2100], 109: [1417, 1477], 230: [1584],
         229: [1583], 429: [2557], 289: [2057], 329: [2017], 409: [2717], 249: [2159], 309: [1977], 469: [2677],
         509: [3429], 531: [3428], 533: [3456]}
maps = set(AREAS)
cspawn = collections.defaultdict(list); gspawn = collections.defaultdict(list)
for r in table('creature'): cspawn[int(r['id'])].append((int(r['map']), float(r['position_x']), float(r['position_y'])))
for r in table('gameobject'): gspawn[int(r['id'])].append((int(r['map']), float(r['position_x']), float(r['position_y'])))
lootid = collections.defaultdict(list)
for e, t in ct.items():
    l = int(t['LootId'] or 0)
    if l: lootid[l].append(e)
droppers = collections.defaultdict(set)
for r in table('creature_loot_template'):
    for e in lootid.get(int(r['entry']), []): droppers[int(r['item'])].add(e)
starters = collections.defaultdict(list); enders = collections.defaultdict(list)
for r in table('creature_questrelation'): starters[int(r['quest'])].append(('c', int(r['id'])))
for r in table('gameobject_questrelation'): starters[int(r['quest'])].append(('g', int(r['id'])))
for r in table('creature_involvedrelation'): enders[int(r['quest'])].append(('c', int(r['id'])))
for r in table('gameobject_involvedrelation'): enders[int(r['quest'])].append(('g', int(r['id'])))
itemstart = collections.defaultdict(list)
for e, r in items.items():
    s = int(r['startquest'] or 0)
    if s: itemstart[s].append(e)
side_of = {}
for qid, s in re.findall(r'\[(\d+)\] = \{ [-\d]+, [-\d]+, [-\d]+, [-\d]+, [-\d]+, (\d)', open('/mnt/project-files/addon/ForeverCompanion/Data/QuestDB.lua').read()):
    side_of[int(qid)] = int(s)
ALLI, HORDE = 77, 178
def spawns(kind, i): return (cspawn if kind == 'c' else gspawn).get(i, [])
def mapsof(kind, i): return {s[0] for s in spawns(kind, i)}
BAD = re.compile(r'UNUSED|DEPRECATED|<NYI>|\[PH\]|<TXT>|TEST|zzOLD|OLD ', re.I)

ev = json.load(open('events.json'))
event_quests = {q for q, e in ev['game_event_quest']}
ev_c = {g for g, e in ev['game_event_creature'] if e > 0}
c_guids = collections.defaultdict(list)
for g, i in ev['creature']: c_guids[i].append(g)
def event_only(kind, i):
    lst = c_guids.get(i, []) if kind == 'c' else []
    return bool(lst) and all(g in ev_c for g in lst)
area_map = {a: m for m, l in AREAS.items() for a in l}
link = collections.defaultdict(set)
objnpcs = {}
for qid, q in Q.items():
    if BAD.search(q['Title']): continue
    if not starters.get(qid) and not itemstart.get(qid): continue
    if qid in event_quests or any(event_only(k, i) for k, i in starters.get(qid, [])): continue
    hit = set(); npcs = set()
    for n in range(1, 5):
        v = int(q['ReqCreatureOrGOId%d' % n])
        if v > 0: hit |= mapsof('c', v) & maps; npcs.add(v)
        elif v < 0: hit |= mapsof('g', -v) & maps
        iid = int(q['ReqItemId%d' % n])
        if iid and iid in items and int(items[iid]['class']) == 12:
            ms = collections.Counter()
            for d in droppers.get(iid, ()):
                for m in mapsof('c', d): ms[m] += 1
            tot = sum(ms.values())
            for m, c in ms.items():
                if m in maps and c * 2 >= tot: hit.add(m); npcs |= {d for d in droppers[iid] if m in mapsof('c', d)}
    for kind, i in starters.get(qid, []): hit |= mapsof(kind, i) & maps
    z = int(q['ZoneOrSort'])
    if z in area_map:
        # the quest belongs to a dungeon: keep only that one (plus where it starts)
        hit = {area_map[z]} | {m for k, i in starters.get(qid, []) for m in mapsof(k, i) & maps}
        if z == 3428:
            # Ahn'Qiraj quests share one zone: keep the instance where every required item drops
            common = None
            for n in range(1, 5):
                iid = int(q['ReqItemId%d' % n])
                if iid:
                    ms = {m for d in droppers.get(iid, ()) for m in mapsof('c', d)} & {509, 531}
                    if ms: common = ms if common is None else common & ms
            if common: hit = common
    for m in hit: link[m].add(qid)
    objnpcs[qid] = npcs

out = collections.OrderedDict(); used = set()
for key, m, wnpcs in inst:
    if m not in link: continue
    wings = [w for w in inst if w[1] == m]
    chosen = []
    for qid in link[m]:
        if len(wings) > 1:
            mine = objnpcs[qid] & wnpcs
            other = any(objnpcs[qid] & w[2] for w in wings if w[0] != key)
            if not mine and other: continue
        chosen.append(qid)
    chosen.sort(key=lambda x: (int(Q[x]['QuestLevel']), Q[x]['Title'], x))
    out[key] = chosen; used |= set(chosen)

def pos(lst):
    pts = []
    for kind, i in lst: pts += spawns(kind, i)
    outside = [p for p in pts if p[0] in (0, 1)]
    if outside:
        p = outside[0]; return (p[0], round(p[1]), round(p[2]), 0)
    if pts: return (pts[0][0], 0, 0, 1)
    return None
def name(kind, i):
    if kind == 'c': return ct[i]['Name'] if i in ct else '?'
    return gotpl[i]['name'] if i in gotpl else '?'
def lua(s): return '"' + s.replace('\\', '\\\\').replace('"', '\\"').replace('\r', '').replace('\n', '\\n').replace('$B', '\\n').replace('$b', '\\n') + '"'
def textclean(s):
    s = re.sub(r'\$[Nn]', '<name>', s); s = re.sub(r'\$[Cc]', '<class>', s); s = re.sub(r'\$[Rr]', '<race>', s)
    s = re.sub(r'\$[Gg]([^:;]*):([^;]*);', r'\1', s)
    return s.strip()

lines = []
lines.append('-- ForeverCompanion: quests of every dungeon and raid (generated, do not edit by hand).')
lines.append('-- Source: CMaNGOS classic-db (https://github.com/cmangos/classic-db).')
lines.append('-- ns.DungeonQuests[instanceKey] = { questID, ... }  (sorted by level)')
lines.append('-- ns.DungeonQuestInfo[questID] = { title, level, minLevel, side (0 both, 1 Alliance, 2 Horde), raceMask, classMask, prevQuest,')
lines.append('--   giver = { name, continent, x, y, inside (1 = in the instance), item (quest starts from this item) },')
lines.append('--   turnin = { name, continent, x, y, inside }, objectives, items = { itemID, count, ... }, kills = { name, count, ... },')
lines.append('--   choice = { itemID, count, ... }, reward = { itemID, count, ... }, money (copper), group (suggested players) }')
lines.append('-- Coordinates are world coordinates (continent 0 = Eastern Kingdoms, 1 = Kalimdor).')
lines.append('local _, ns = ...')
lines.append('')
lines.append('ns.DungeonQuests = {')
for key, l in out.items():
    lines.append('\t[%s] = { %s },' % (lua(key), ', '.join(map(str, l))))
lines.append('}')
lines.append('')
lines.append('ns.DungeonQuestInfo = {')
prevs = set()
for qid in sorted(used):
    q = Q[qid]
    races = int(q['RequiredRaces'])
    side = side_of.get(qid)
    if side is None: side = 1 if races and not races & HORDE else 2 if races and not races & ALLI else 0
    prev = int(q['PrevQuestId'])
    if prev > 0: prevs.add(prev)
    parts = [lua(q['Title']), q['QuestLevel'], q['MinLevel'], str(side), str(races), q['RequiredClasses'], str(max(prev, 0))]
    g = pos(starters.get(qid, []))
    if starters.get(qid):
        k, i = starters[qid][0]
        gs = 'giver = { %s, %d, %d, %d, %d }' % ((lua(name(k, i)),) + (g if g else (0, 0, 0, 1)))
    else:
        iid = itemstart[qid][0]
        gs = 'giver = { %s, 0, 0, 0, 1, %d }' % (lua(items[iid]['name']), iid)
    e = pos(enders.get(qid, []))
    if enders.get(qid):
        k, i = enders[qid][0]
        es = 'turnin = { %s, %d, %d, %d, %d }' % ((lua(name(k, i)),) + (e if e else (0, 0, 0, 1)))
    else: es = 'turnin = nil'
    fields = [gs, es, 'objectives = ' + lua(textclean(q['Objectives'] or ''))]
    req = []; kills = []
    for n in range(1, 5):
        iid = int(q['ReqItemId%d' % n]); c = int(q['ReqItemCount%d' % n])
        if iid: req += [iid, c]
        v = int(q['ReqCreatureOrGOId%d' % n]); c = int(q['ReqCreatureOrGOCount%d' % n])
        if v: kills += [lua(name('c' if v > 0 else 'g', abs(v))), str(c)]
    if req: fields.append('items = { %s }' % ', '.join(map(str, req)))
    if kills: fields.append('kills = { %s }' % ', '.join(kills))
    ch = []; rw = []
    for n in range(1, 7):
        iid = int(q['RewChoiceItemId%d' % n])
        if iid: ch += [iid, int(q['RewChoiceItemCount%d' % n])]
    for n in range(1, 5):
        iid = int(q['RewItemId%d' % n])
        if iid: rw += [iid, int(q['RewItemCount%d' % n])]
    if ch: fields.append('choice = { %s }' % ', '.join(map(str, ch)))
    if rw: fields.append('reward = { %s }' % ', '.join(map(str, rw)))
    money = int(q['RewOrReqMoney'])
    if money > 0: fields.append('money = %d' % money)
    sp = int(q['SuggestedPlayers'] or 0)
    if sp > 1: fields.append('group = %d' % sp)
    lines.append('\t[%d] = { %s, %s },' % (qid, ', '.join(parts), ', '.join(fields)))
lines.append('}')
lines.append('')
lines.append('-- Titles of prerequisite quests that are not dungeon quests themselves.')
lines.append('ns.DungeonQuestPrev = {')
for p in sorted(prevs - used):
    if p in Q: lines.append('\t[%d] = %s,' % (p, lua(Q[p]['Title'])))
lines.append('}')
open('/mnt/project-files/addon/ForeverCompanion/Data/DungeonQuests.lua', 'w').write('\n'.join(lines) + '\n')
for k, l in out.items(): print(k, len(l), '|', '; '.join(Q[x]['Title'] for x in l)[:220])
print('total', len(used))

import sys
for t in sys.argv[1:]:
    for qid, q in Q.items():
        if q['Title'] == t:
            print(qid, 'zone', q['ZoneOrSort'], 'starters', [(k, i, mapsof(k, i)) for k, i in starters.get(qid, [])], 'objs', [(q['ReqCreatureOrGOId%d' % n], q['ReqItemId%d' % n]) for n in range(1, 5)], [m for m in link if qid in link[m]])
