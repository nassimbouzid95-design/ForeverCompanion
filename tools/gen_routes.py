# Generates Data/RoutesAuto.lua: leveling routes 1-60 for each starting area, simulated from the quest database.
# A greedy "nearest next action" walk through the classic leveling path of each faction, with quest XP
# (RewMoneyMaxLevel / 0.6, minus the grey-quest penalty) and estimated kill XP, cut into one route per zone visit.
import json, re, math, collections, sys, os
D = '/tmp/claude-0/data/'
cm = json.load(open(D + 'cmangos.json'))
qf = json.load(open(D + 'dq/quests_full.json'))['quest_template']
it = json.load(open(D + 'dq/items.json'))
def table(t, src=cm): c = src[t]['cols']; return [dict(zip(c, r)) for r in src[t]['rows']]
QT = {int(r[0]): dict(zip(qf['cols'], r)) for r in qf['rows']}
ct = {int(r['Entry']): r for r in table('creature_template')}
gotpl = {int(r['entry']): r for r in table('gameobject_template', it)}
items = {int(r['entry']): r for r in table('item_template', it)}
starters = collections.defaultdict(list); enders = collections.defaultdict(list)
for r in table('creature_questrelation'): starters[int(r['quest'])].append(('c', int(r['id'])))
for r in table('gameobject_questrelation'): starters[int(r['quest'])].append(('g', int(r['id'])))
for r in table('creature_involvedrelation'): enders[int(r['quest'])].append(('c', int(r['id'])))
for r in table('gameobject_involvedrelation'): enders[int(r['quest'])].append(('g', int(r['id'])))

QDB = {}
pat = re.compile(r'\[(\d+)\] = \{ (-?\d+), (-?\d+), (-?\d+), (-?\d+), (-?\d+), (\d), "((?:[^"\\]|\\.)*)", (\d), (-?\d+), (-?\d+), (\d), (-?\d+), (-?\d+), \{ ([^}]*) \}, (-?\d+) \}')
for m in pat.finditer(open('/mnt/project-files/addon/ForeverCompanion/Data/QuestDB.lua').read()):
    g = m.groups()
    objs = [int(v) for v in g[14].replace(' ', '').split(',') if v]
    QDB[int(g[0])] = dict(lvl=int(g[1]), min=int(g[2]), races=int(g[3]), classes=int(g[4]), prev=int(g[5]), side=int(g[6]),
        title=g[7], s=(int(g[8]), int(g[9]), int(g[10])), e=(int(g[11]), int(g[12]), int(g[13])),
        o=[tuple(objs[i:i + 3]) for i in range(0, len(objs), 3)], excl=int(g[15]))
print('quests', len(QDB), file=sys.stderr)

def dist(a, b):
    if a[0] != b[0]: return 1e7
    return math.hypot(a[1] - b[1], a[2] - b[2])

XP_TO_LEVEL = [0, 400, 900, 1400, 2100, 2800, 3600, 4500, 5400, 6500, 7600, 8800, 10100, 11400, 12900, 14400, 16000, 17700,
    19400, 21300, 23200, 25200, 27300, 29400, 31700, 34000, 36400, 38900, 41400, 44300, 47400, 50800, 54500, 58600, 62800,
    67100, 71600, 76100, 80800, 85700, 90700, 95800, 101000, 106300, 111800, 117500, 123200, 129100, 135100, 141200,
    147500, 153900, 160400, 167100, 173900, 180800, 187900, 195000, 202300, 209800]

RACES = {'Human': 1, 'Orc': 2, 'Dwarf': 3, 'NightElf': 4, 'Scourge': 5, 'Tauren': 6, 'Gnome': 7, 'Troll': 8}
C = dict(Elwynn=[12, 9], Stormwind=[1519], DunMorogh=[1, 132], Ironforge=[1537], Teldrassil=[141, 188], Darnassus=[1657], Westfall=[40],
    LochModan=[38], Redridge=[44], Darkshore=[148], Ashenvale=[331], Wetlands=[11], Duskwood=[10], Hillsbrad=[267, 36],
    Arathi=[45], STV=[33], Needles=[400], Desolace=[405], Dustwallow=[15], Badlands=[3], Swamp=[8], Tanaris=[440],
    Feralas=[357], Hinterlands=[47], Searing=[51], Felwood=[361], Ungoro=[490], Azshara=[16], Burning=[46],
    Winterspring=[618], WPL=[28], EPL=[139], Silithus=[1377], Durotar=[14, 363], Orgrimmar=[1637], Mulgore=[215, 220],
    ThunderBluff=[1638], Tirisfal=[85, 154], Undercity=[1497], Silverpine=[130], Barrens=[17], Stonetalon=[406], Blasted=[4])
NAMES = dict(Elwynn='Elwynn Forest', DunMorogh='Dun Morogh', Teldrassil='Teldrassil', Westfall='Westfall', LochModan='Loch Modan',
    Redridge='Redridge Mountains', Darkshore='Darkshore', Ashenvale='Ashenvale', Wetlands='Wetlands', Duskwood='Duskwood',
    Hillsbrad='Hillsbrad Foothills', Arathi='Arathi Highlands', STV='Stranglethorn Vale', Needles='Thousand Needles',
    Desolace='Desolace', Dustwallow='Dustwallow Marsh', Badlands='Badlands', Swamp='Swamp of Sorrows', Tanaris='Tanaris',
    Feralas='Feralas', Hinterlands='The Hinterlands', Searing='Searing Gorge', Felwood='Felwood', Ungoro="Un'Goro Crater",
    Azshara='Azshara', Burning='Burning Steppes', Winterspring='Winterspring', WPL='Western Plaguelands',
    EPL='Eastern Plaguelands', Silithus='Silithus', Durotar='Durotar', Mulgore='Mulgore', Tirisfal='Tirisfal Glades',
    Silverpine='Silverpine Forest', Barrens='The Barrens', Stonetalon='Stonetalon Mountains', Blasted='Blasted Lands')
# (zones, extra areas whose quests also count, level to reach before leaving)
ALLI_END = [('Redridge', 20), ('Darkshore', 21), ('Ashenvale', 23), ('Wetlands', 25), ('Duskwood', 28), ('Wetlands', 29),
    ('Hillsbrad', 31), ('Arathi', 33), ('STV', 36), ('Desolace', 38), ('Dustwallow', 40), ('Badlands', 41), ('Swamp', 42),
    ('STV', 44), ('Tanaris', 46), ('Feralas', 47), ('Hinterlands', 49), ('Searing', 50), ('Felwood', 52), ('Ungoro', 54),
    ('Azshara', 54), ('Burning', 56), ('Winterspring', 57), ('Felwood', 57), ('WPL', 58), ('EPL', 59), ('Silithus', 60), ('WPL', 60), ('EPL', 60)]
HORDE_END = [('Barrens', 20), ('Stonetalon', 22), ('Barrens', 24), ('Ashenvale', 26), ('Hillsbrad', 28), ('Needles', 30),
    ('Hillsbrad', 31), ('Arathi', 33), ('STV', 36), ('Desolace', 38), ('Dustwallow', 40), ('Badlands', 41), ('Swamp', 42),
    ('STV', 44), ('Tanaris', 46), ('Feralas', 47), ('Hinterlands', 49), ('Searing', 50), ('Felwood', 52), ('Ungoro', 54),
    ('Azshara', 54), ('Burning', 56), ('Winterspring', 57), ('Felwood', 57), ('WPL', 58), ('EPL', 59), ('Silithus', 60), ('WPL', 60), ('EPL', 60)]
STARTS = [
    ('human', 'Alliance', ['Human'], [('Elwynn', 10, ['Stormwind']), ('Westfall', 14), ('LochModan', 16), ('Westfall', 17)] + ALLI_END),
    ('dwarf', 'Alliance', ['Dwarf', 'Gnome'], [('DunMorogh', 11, ['Ironforge']), ('LochModan', 15), ('Westfall', 17)] + ALLI_END),
    ('nightelf', 'Alliance', ['NightElf'], [('Teldrassil', 11, ['Darnassus']), ('Darkshore', 17), ('Westfall', 18)] + ALLI_END),
    ('orc', 'Horde', ['Orc', 'Troll'], [('Durotar', 11, ['Orgrimmar']), ('Barrens', 16)] + HORDE_END),
    ('tauren', 'Horde', ['Tauren'], [('Mulgore', 11, ['ThunderBluff']), ('Barrens', 16)] + HORDE_END),
    ('undead', 'Horde', ['Scourge'], [('Tirisfal', 11, ['Undercity']), ('Silverpine', 15), ('Barrens', 17)] + HORDE_END),
]

def has(mask, bit): return mask & bit

def quest_xp(qid, level):
    q = QT.get(qid)
    if not q: return 0
    xp = int(q['RewMoneyMaxLevel']) / 0.6
    diff = level - int(q['QuestLevel'])
    if diff >= 10: xp *= 0.1
    elif diff >= 6: xp *= {6: 0.8, 7: 0.6, 8: 0.4, 9: 0.2}[diff]
    return int(xp)
AMBIENT = float(sys.argv[2]) if len(sys.argv) > 2 else 2.0
LEAD = int(sys.argv[3]) if len(sys.argv) > 3 else 4
def mob_xp(level):
    return 45 + 5 * level

def kills_for(qid):
    q = QT[qid]; n = 0
    for i in range(1, 5):
        if int(q['ReqCreatureOrGOId%d' % i]) > 0: n += int(q['ReqCreatureOrGOCount%d' % i])
        if int(q['ReqItemId%d' % i]): n += int(int(q['ReqItemCount%d' % i]) * 1.6)
    return min(n, 40)

def nm(kind, i):
    if kind == 'c': return ct[i]['Name'] if i in ct else None
    return gotpl[i]['name'] if i in gotpl else None
def objective_text(qid):
    q = QT[qid]; parts = []
    for i in range(1, 5):
        v = int(q['ReqCreatureOrGOId%d' % i]); c = int(q['ReqCreatureOrGOCount%d' % i])
        if v > 0 and v in ct: parts.append('%s x%d' % (ct[v]['Name'], c) if c > 1 else ct[v]['Name'])
        iid = int(q['ReqItemId%d' % i]); c = int(q['ReqItemCount%d' % i])
        if iid and iid in items: parts.append('%s x%d' % (items[iid]['name'], c) if c > 1 else items[iid]['name'])
    return ', '.join(parts)

zone_of = {qid: int(QT[qid]['ZoneOrSort']) for qid in QDB if qid in QT}
# Quests sorted under a sub-zone (Northshire, Valley of Trials...) or a sort: take the zone of the nearest quest givers.
KNOWN = {a for l in C.values() for a in l}
anchors = [(q['s'], zone_of[qid]) for qid, q in QDB.items() if zone_of.get(qid) in KNOWN]
fixed = 0
for qid, q in QDB.items():
    if zone_of.get(qid) not in KNOWN:
        near = sorted((dist(q['s'], p), z) for p, z in anchors if p[0] == q['s'][0])[:5]
        if near and near[0][0] < 1500:
            zone_of[qid] = collections.Counter(z for d, z in near).most_common(1)[0][0]; fixed += 1
print('zones fixed by neighbours', fixed, file=sys.stderr)

ALLI_POOL = ['Westfall', 'LochModan', 'Redridge', 'Darkshore', 'Ashenvale', 'Wetlands', 'Duskwood', 'Hillsbrad', 'Arathi', 'STV',
    'Needles', 'Desolace', 'Dustwallow', 'Badlands', 'Swamp', 'Tanaris', 'Feralas', 'Hinterlands', 'Searing', 'Felwood',
    'Ungoro', 'Azshara', 'Burning', 'Winterspring', 'WPL', 'EPL', 'Silithus', 'Blasted', 'Stonetalon']
HORDE_POOL = ['Silverpine', 'Barrens', 'Stonetalon', 'Ashenvale', 'Hillsbrad', 'Needles', 'Arathi', 'STV', 'Desolace',
    'Dustwallow', 'Badlands', 'Swamp', 'Tanaris', 'Feralas', 'Hinterlands', 'Searing', 'Felwood', 'Ungoro', 'Azshara',
    'Burning', 'Winterspring', 'WPL', 'EPL', 'Silithus', 'Blasted']
CITY = dict(Elwynn='Stormwind', DunMorogh='Ironforge', Teldrassil='Darnassus', Durotar='Orgrimmar', Mulgore='ThunderBluff', Tirisfal='Undercity')
START_POS = dict(Elwynn=(0, -8949, -132), DunMorogh=(0, -6240, 331), Teldrassil=(1, 10311, 832), Durotar=(1, -618, -4251),
    Mulgore=(1, -2917, -257), Tirisfal=(0, 1676, 1677))
STARTS = [
    ('human', 'Alliance', ['Human'], ['Elwynn']),
    ('dwarf', 'Alliance', ['Dwarf', 'Gnome'], ['DunMorogh']),
    ('nightelf', 'Alliance', ['NightElf'], ['Teldrassil']),
    ('orc', 'Horde', ['Orc', 'Troll'], ['Durotar']),
    ('tauren', 'Horde', ['Tauren'], ['Mulgore']),
    ('undead', 'Horde', ['Scourge'], ['Tirisfal']),
]
MIN_SCORE = 0.30   # a zone is worth going to when its quests give at least 30% of the current level

def simulate(key, faction, races, home):
    side = 1 if faction == 'Alliance' else 2
    rbits = 0
    for r in races: rbits |= 1 << (RACES[r] - 1)
    level, xp = 1, 0
    turned, log, done_obj, excl_used = set(), {}, set(), set()
    pos = START_POS[home[0]]
    routes = []
    grind = [0]
    pool = home + (ALLI_POOL if side == 1 else HORDE_POOL)
    def areas_of(z):
        a = set(C[z])
        if z in CITY: a |= set(C[CITY[z]])
        return a
    def gain(amount):
        nonlocal level, xp
        xp += amount
        while level < 60 and xp >= XP_TO_LEVEL[level]:
            xp -= XP_TO_LEVEL[level]; level += 1
    def eligible(qid, q, areas):
        if qid in turned or qid in log: return False
        if zone_of.get(qid) not in areas: return False
        if q['side'] not in (0, side) or not (q['races'] == 0 or q['races'] & rbits): return False
        if q['classes']: return False
        if q['min'] > level: return False
        ql = q['lvl'] if q['lvl'] > 0 else level
        if ql > level + (2 if level < 10 else LEAD): return False
        if ql < level - 6: return False
        if q['prev'] > 0 and q['prev'] in QDB and q['prev'] not in turned: return False
        if q['prev'] < 0 and -q['prev'] in QDB and -q['prev'] not in log and -q['prev'] not in turned: return False
        if q['excl'] > 0 and q['excl'] in excl_used: return False
        if q['s'][0] != q['e'][0]: return False
        return True
    def zone_score(z):
        areas = areas_of(z); total = 0; pts = []
        for qid, q in QDB.items():
            if eligible(qid, q, areas):
                total += quest_xp(qid, level) + kills_for(qid) * AMBIENT * mob_xp(max(1, q['lvl'])); pts.append(q['s'])
        if not pts: return 0, None
        c = pts[0][0]
        same = [p for p in pts if p[0] == c]
        centre = (c, sum(p[1] for p in same) / len(same), sum(p[2] for p in same) / len(same))
        need = XP_TO_LEVEL[level] if level < 60 else 1
        score = total / need
        if pos is not None:
            d = dist(pos, centre)
            score = score * (0.6 if d >= 1e6 else 1 / (1 + d / 4000))
        return score, centre
    chapter = 0
    visited = collections.Counter()
    while level < 60 and chapter < 80:
        if chapter == 0:
            zname = home[0]
        else:
            best = max(((zone_score(z)[0], z) for z in pool if not (z in home and level > 14)), default=(0, None))
            if best[0] < MIN_SCORE:
                # nothing worth the trip yet: grind one level where you are
                if routes and routes[-1]['steps'] and routes[-1]['steps'][-1][0] == 'level':
                    routes[-1]['steps'].pop()
                need = XP_TO_LEVEL[level] - xp
                grind[0] += need; gain(need)
                routes[-1]['steps'].append(('level', level)); routes[-1]['max'] = level
                continue
            zname = best[1]
        chapter += 1
        visited[zname] += 1
        areas = areas_of(zname)
        steps = []; start_level = level; travelled = False
        while True:
            acts = []
            for qid, q in QDB.items():
                if len(log) < 20 and eligible(qid, q, areas): acts.append(('accept', qid, q['s']))
            for qid in log:
                q = QDB[qid]
                if q['o'] and qid not in done_obj:
                    o = min(q['o'], key=lambda p: dist(pos, p) if pos else 0)
                    acts.append(('complete', qid, o))
                else:
                    acts.append(('turnin', qid, q['e']))
            if not acts or level >= 60: break
            if pos is None: pos = acts[0][2]
            a = min(acts, key=lambda a: dist(pos, a[2]) + (0 if a[0] != 'accept' else 5))
            if not travelled:
                travelled = True
                if dist(pos, a[2]) > 400 or chapter == 1:
                    steps.append(('goto', a[2], NAMES.get(zname, zname), dist(pos, a[2]) >= 1e6))
            kind, qid, p = a
            q = QDB[qid]
            if kind == 'accept':
                log[qid] = True
                if q['excl'] > 0: excl_used.add(q['excl'])
            elif kind == 'complete':
                done_obj.add(qid)
                gain(int(kills_for(qid) * AMBIENT) * mob_xp(max(1, q['lvl'] if q['lvl'] > 0 else level)))
            else:
                del log[qid]; turned.add(qid)
                gain(quest_xp(qid, level))
            steps.append((kind, qid, p, level))
            pos = p
        for qid in list(log):
            steps.append(('abandon', qid)); del log[qid]
        name = NAMES.get(zname, zname)
        routes.append(dict(id='auto-%s-%02d' % (key, chapter), zone=zname, name=name, min=start_level, max=level, steps=steps))
    print(key, 'grind xp', int(grind[0]), 'final level', level, 'zones', ' '.join('%s%d-%d' % (r['zone'], r['min'], r['max']) for r in routes), file=sys.stderr)
    return routes, level, len(turned)

def lua(s): return '"' + s.replace('\\', '\\\\').replace('"', '\\"') + '"'
out = ['-- ForeverCompanion: leveling routes 1-60, generated from the quest database (do not edit by hand).',
       '-- Each starting area gets a chain of zone routes simulated with quest and kill experience.',
       '-- Built by tools/gen_routes.py from CMaNGOS classic-db. Not hand-tested: please report wrong steps.',
       'local _, ns = ...', 'local R = ns.RegisterRoute', '']
report = []
for key, faction, races, home in STARTS:
    routes, lv, n = simulate(key, faction, races, home)
    report.append('%s: %d zone routes, level %d, %d quests, %d steps' % (key, len(routes), lv, n, sum(len(r['steps']) for r in routes)))
    for r in routes:
        lines = []
        for s in r['steps']:
            if s[0] == 'goto':
                lines.append('{ "goto", cont = %d, wx = %d, wy = %d, zone = %s%s }' % (s[1][0], s[1][1], s[1][2], lua(s[2]), ', ship = true' if s[3] else ''))
            elif s[0] == 'level':
                lines.append('{ "level", level = %d }' % s[1])
            elif s[0] == 'abandon':
                lines.append('{ "note", quest = %d, abandon = true }' % s[1])
            else:
                kind, qid, p, lvl = s
                extra = ''
                if kind == 'accept' and starters.get(qid):
                    n = nm(*starters[qid][0])
                    if n: extra = ', npc = ' + lua(n)
                elif kind == 'turnin' and enders.get(qid):
                    n = nm(*enders[qid][0])
                    if n: extra = ', npc = ' + lua(n)
                elif kind == 'complete':
                    t = objective_text(qid)
                    if t: extra = ', text = ' + lua(t)
                lines.append('{ "%s", quest = %d, cont = %d, wx = %d, wy = %d, lvl = %d%s }' % (kind, qid, p[0], p[1], p[2], lvl, extra))
        out.append('R({ id = %s, name = %s, faction = %s, races = { %s }, minLevel = %d, maxLevel = %d, auto = true, steps = {' % (
            lua(r['id']), lua(r['name']), lua(faction), ', '.join(lua(x) for x in races), r['min'], max(r['max'], r['min'])))
        out += ['\t' + l + ',' for l in lines]
        out.append('} })')
open('/mnt/project-files/addon/ForeverCompanion/Data/RoutesAuto.lua', 'w').write('\n'.join(out) + '\n')
print('\n'.join(report))
