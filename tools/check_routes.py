#!/usr/bin/env python3
"""Checks every built-in route of Data/RoutesAuto.lua against the quest database (Data/QuestDB.lua via questdb.json):
  * every quest fits the route's class, race(s) and faction,
  * accept comes before objectives and turn-in, and a quest is never turned in without being accepted,
  * the quests a quest needs are turned in before it is accepted (all of pre_all, one of pre_any),
  * every quest step has a position, dungeon steps name a known instance,
  * the routes of a start and class follow each other from level 1 to 60.
Usage: python3 check_routes.py   (exit code 1 when a problem is found)"""
import json, os, re, sys, collections
HERE = os.path.dirname(os.path.abspath(__file__))
ADDON = os.path.join(HERE, '..', 'ForeverCompanion')
QDB = {int(k): v for k, v in json.load(open(os.path.join(os.environ.get('FDB_DIR', '/tmp/claude-0/fdb'), 'questdb.json'))).items()}
CLASS_BIT = dict(WARRIOR=1, PALADIN=2, HUNTER=4, ROGUE=8, PRIEST=16, SHAMAN=64, MAGE=128, WARLOCK=256, DRUID=1024)
RACE_BIT = dict(Human=1, Orc=2, Dwarf=4, NightElf=8, Scourge=16, Tauren=32, Gnome=64, Troll=128, Skyborne=3 << 32)
SKY = dict(Alliance=1 << 32, Horde=1 << 33)
txt = open(os.path.join(ADDON, 'Data/RoutesAuto.lua')).read()
keys = set(re.findall(r'key = "([^"]+)"', open(os.path.join(ADDON, 'Data/InstanceDB.lua')).read() + open(os.path.join(ADDON, 'Data/ForeverDungeons.lua')).read()))
routes = collections.defaultdict(list)
for m in re.finditer(r'^R\("auto-(.+?)-(\w+)-(\d+)", \d+, "(\w+)", \{ ([^}]*) \}, "(\w+)", (\d+), (\d+), "([^"]*)"\)$', txt, re.M):
    start, cls_l, n, faction, races, cls, lo, hi, packed = m.groups()
    routes[(start, cls)].append((int(n), faction, re.findall(r'"(\w+)"', races), int(lo), int(hi), packed.split()))
problems = collections.Counter(); examples = collections.defaultdict(list)
def bad(kind, msg):
    problems[kind] += 1
    if len(examples[kind]) < 5: examples[kind].append(msg)
for (start, cls), parts in sorted(routes.items()):
    parts.sort()
    prev_hi = 0
    for n, faction, races, lo, hi, _ in parts:
        if lo > prev_hi + 1: bad('level gap', '%s %s: %d-%d after %d' % (start, cls, lo, hi, prev_hi))
        prev_hi = max(prev_hi, hi)
    if prev_hi < 60: bad('ends before 60', '%s %s: %d' % (start, cls, prev_hi))
    faction, races = parts[0][1], parts[0][2]
    rbits = 0
    for r in races: rbits |= RACE_BIT[r] if r != 'Skyborne' else SKY[faction]
    cbit = CLASS_BIT[cls]
    accepted, turned = set(), set()
    for n, _, _, lo, hi, tokens in parts:
        for t in tokens:
            k, rest = t[0], t[1:]
            if k in 'actx':
                qid = int(rest.split('@')[0]); q = QDB.get(qid)
                where = '%s %s %s' % (start, cls, t)
                if not q: bad('unknown quest', where); continue
                if q['classes'] and not q['classes'] & cbit: bad('other class', where + ' ' + q['title'])
                if q['races'] and not q['races'] & rbits: bad('other race', where + ' ' + q['title'])
                if q['side'] and q['side'] != (1 if faction == 'Alliance' else 2): bad('other faction', where + ' ' + q['title'])
                if k == 'a':
                    if qid in accepted: bad('accepted twice', where)
                    miss = [p for p in q.get('pre_all', []) if p in QDB and p not in turned]
                    pa = [p for p in q.get('pre_any', []) if p in QDB]
                    if miss or (pa and not any(p in turned for p in pa)): bad('prerequisite missing', where + ' ' + q['title'] + ' needs ' + str(miss or pa))
                    if not q.get('s'): bad('no position', where)
                    accepted.add(qid)
                elif k in 'ct':
                    if qid not in accepted: bad('not accepted first', where + ' ' + q['title'])
                    if k == 't':
                        if qid in turned: bad('turned in twice', where)
                        turned.add(qid)
                elif k == 'x':
                    accepted.discard(qid)
            elif k == 'd':
                key = rest.split('@')[0]
                if key not in keys: bad('unknown dungeon', '%s %s %s' % (start, cls, key))
print('%d routes (%d start x class), %d steps' % (sum(len(v) for v in routes.values()), len(routes), sum(len(p[5]) for v in routes.values() for p in v)))
for k, v in problems.most_common():
    print('%-22s %5d   e.g. %s' % (k, v, ' | '.join(examples[k][:3])))
    if '-v' in sys.argv: print('\n'.join('   ' + e for e in examples[k]))
sys.exit(1 if problems else 0)
