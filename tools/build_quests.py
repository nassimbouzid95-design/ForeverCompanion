import json, collections, sys
cm = json.load(open('/tmp/claude-0/data/cmangos.json'))
def table(name):
    t = cm[name]; c = t['cols']
    return [dict(zip(c, r)) for r in t['rows']]
ct = {int(r['Entry']): r for r in table('creature_template')}
quests = {int(r['entry']): r for r in table('quest_template')}
cspawn = collections.defaultdict(list); gspawn = collections.defaultdict(list)
for r in table('creature'):
    m = int(r['map'])
    if m in (0, 1): cspawn[int(r['id'])].append((m, float(r['position_x']), float(r['position_y'])))
for r in table('gameobject'):
    m = int(r['map'])
    if m in (0, 1): gspawn[int(r['id'])].append((m, float(r['position_x']), float(r['position_y'])))
starters = collections.defaultdict(list); enders = collections.defaultdict(list)
for r in table('creature_questrelation'): starters[int(r['quest'])].append(('c', int(r['id'])))
for r in table('gameobject_questrelation'): starters[int(r['quest'])].append(('g', int(r['id'])))
for r in table('creature_involvedrelation'): enders[int(r['quest'])].append(('c', int(r['id'])))
for r in table('gameobject_involvedrelation'): enders[int(r['quest'])].append(('g', int(r['id'])))
# quest item droppers
droppers = collections.defaultdict(list)
for r in table('creature_loot_template'):
    droppers[int(r['item'])].append((int(r['entry']), abs(float(r['ChanceOrQuestChance']))))
lootid_to_npcs = collections.defaultdict(list)
for e, t in ct.items():
    lid = int(t['LootId'] or 0)
    if lid: lootid_to_npcs[lid].append(e)

def spawns_of(kind, i):
    return (cspawn if kind == 'c' else gspawn).get(i, [])

def clusters(points, k=3, cell=250.0):
    if not points: return []
    cont = collections.Counter(p[0] for p in points).most_common(1)[0][0]
    pts = [p for p in points if p[0] == cont]
    cells = collections.defaultdict(list)
    for p in pts: cells[(int(p[1] // cell), int(p[2] // cell))].append(p)
    best = sorted(cells.values(), key=len, reverse=True)[:k]
    out = []
    for grp in best:
        mx = sum(p[1] for p in grp) / len(grp); my = sum(p[2] for p in grp) / len(grp)
        # snap to the real spawn closest to the centre
        q = min(grp, key=lambda p: (p[1]-mx)**2 + (p[2]-my)**2)
        out.append((cont, round(q[1]), round(q[2])))
    return out

def one_pos(lst):
    pts = []
    for kind, i in lst: pts += spawns_of(kind, i)
    c = clusters(pts, 1)
    return c[0] if c else None

ALLI, HORDE = 77, 178
# learn faction templates from race-restricted quests
side_votes = collections.defaultdict(collections.Counter)
for qid, q in quests.items():
    races = int(q['RequiredRaces'])
    side = 1 if races and not races & HORDE else 2 if races and not races & ALLI else 0
    if not side: continue
    for kind, i in starters.get(qid, []) + enders.get(qid, []):
        if kind == 'c' and i in ct: side_votes[int(ct[i]['Faction'])][side] += 1
fside = {}
for f, v in side_votes.items():
    a, h = v[1], v[2]
    if a >= 3 * max(h, 1) or (a and not h): fside[f] = 1
    elif h >= 3 * max(a, 1) or (h and not a): fside[f] = 2

ev = json.load(open('/tmp/claude-0/data/events.json'))
event_quests = {q for q, e in ev['game_event_quest']}
ev_c = {g for g, e in ev['game_event_creature'] if e > 0}
ev_g = {g for g, e in ev['game_event_gameobject'] if e > 0}
c_guids = collections.defaultdict(list); g_guids = collections.defaultdict(list)
for g, i in ev['creature']: c_guids[i].append(g)
for g, i in ev['gameobject']: g_guids[i].append(g)
def event_only(kind, i):
    guids, evs = (c_guids, ev_c) if kind == 'c' else (g_guids, ev_g)
    lst = guids.get(i, [])
    return bool(lst) and all(g in evs for g in lst)

out = {}
stats = collections.Counter()
for qid, q in quests.items():
    st = starters.get(qid); en = enders.get(qid)
    if not st or not en: stats['no_npc'] += 1; continue
    if int(q['RequiredSkill']): stats['skill'] += 1; continue
    if qid in event_quests or all(event_only(k, i) for k, i in st): stats['event'] += 1; continue
    if int(q['SpecialFlags']) & 1: stats['repeatable'] += 1; continue
    s = one_pos(st); e = one_pos(en)
    if not s or not e: stats['no_pos'] += 1; continue
    races = int(q['RequiredRaces']); side = 0
    if races and not races & HORDE: side = 1
    elif races and not races & ALLI: side = 2
    else:
        for kind, i in st:
            if kind == 'c' and i in ct and int(ct[i]['Faction']) in fside: side = fside[int(ct[i]['Faction'])]; break
    objs = []
    for n in range(1, 5):
        oid = int(q[f'ReqCreatureOrGOId{n}'])
        if oid > 0: objs += clusters(cspawn.get(oid, []), 2)
        elif oid < 0: objs += clusters(gspawn.get(-oid, []), 2)
        iid = int(q[f'ReqItemId{n}'])
        if iid:
            ds = sorted(droppers.get(iid, []), key=lambda d: -d[1])[:3]
            pts = []
            for lid, ch in ds:
                for npc in lootid_to_npcs.get(lid, []): pts += cspawn.get(npc, [])
            objs += clusters(pts, 2)
    if not objs and int(q['PointMapId']) in (0, 1) and float(q['PointX']):
        objs.append((int(q['PointMapId']), round(float(q['PointX'])), round(float(q['PointY']))))
    # keep objectives on the same continent as the quest giver, max 4
    seen = []; 
    for o in objs:
        if o[0] == s[0] and o not in seen: seen.append(o)
    objs = seen[:4]
    out[qid] = dict(lvl=int(q['QuestLevel']), min=int(q['MinLevel']), races=races, classes=int(q['RequiredClasses']),
                    prev=int(q['PrevQuestId']), excl=int(q['ExclusiveGroup']), side=side, title=q['Title'], s=s, e=e, o=objs)
    stats['ok'] += 1
# Neutral-looking quests: take the side of the quest givers around them, when they all agree.
known = [(o['s'], o['side']) for o in out.values() if o['side']]
for qid, o in out.items():
    if o['side'] or o['races']: continue
    votes = collections.Counter()
    for (c, x, y), side in known:
        if c == o['s'][0] and abs(x - o['s'][1]) < 120 and abs(y - o['s'][2]) < 120: votes[side] += 1
    if len(votes) == 1 and sum(votes.values()) >= 2:
        o['side'] = next(iter(votes)); stats['side_by_neighbours'] += 1
print(stats, len(fside), file=sys.stderr)

def ls(s): return '"' + s.replace('\\', '\\\\').replace('"', '\\"') + '"'
lines = ["-- ForeverCompanion: quest database (generated, do not edit by hand).",
         "-- Source: CMaNGOS classic-db (https://github.com/cmangos/classic-db): quest givers, turn-ins and objective areas.",
         "-- [questID] = { level, minLevel, raceMask, classMask, prevQuest, side (0 both, 1 Alliance, 2 Horde), title,",
         "--   giver continent, x, y, turn-in continent, x, y, { objective continent, x, y, ... }, exclusiveGroup }",
         "-- Coordinates are world coordinates (continent 0 = Eastern Kingdoms, 1 = Kalimdor).",
         "local _, ns = ...", "", "ns.QuestDB = {"]
for qid in sorted(out):
    d = out[qid]
    o = ", ".join(f"{c}, {x}, {y}" for c, x, y in d['o'])
    lines.append(f"\t[{qid}] = {{ {d['lvl']}, {d['min']}, {d['races']}, {d['classes']}, {d['prev']}, {d['side']}, {ls(d['title'])}, "
                 f"{d['s'][0]}, {d['s'][1]}, {d['s'][2]}, {d['e'][0]}, {d['e'][1]}, {d['e'][2]}, {{ {o} }}, {d['excl']} }},")
lines.append("}")
open(sys.argv[1], 'w').write("\n".join(lines) + "\n")
