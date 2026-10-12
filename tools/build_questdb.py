#!/usr/bin/env python3
"""Generate ForeverCompanion/Data/QuestDB.lua from the WoW Forever quest database (QuestieDB, see forever_db.py).

[questID] = { level, minLevel, raceMask, classMask, prevQuest, side, title, giver cont, x, y, turn-in cont, x, y,
              { objective cont, x, y, ... }, exclusiveGroup }
Positions: world coordinates (continent 0 / 1) or, in the new Forever zones, -uiMapID and map fraction * 10000.
Left out: quests Questie blacklists for Classic-era content, holiday quests, quests with no giver and no turn-in.
"""
import os, sys, json, math, collections
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import forever_db as F

ALLI = 77 | 4294967296          # classic Alliance races + Skyborne (Alliance)
HORDE = 178 | 8589934592        # classic Horde races + Skyborne (Horde)
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'ForeverCompanion', 'Data', 'QuestDB.lua')


def excluded():
    bl = set(int(x) for x in open(os.path.join(F.FDB_DIR, 'blacklist.txt')).read().strip().split(',') if x)
    ev = set(int(x) for x in open(os.path.join(F.FDB_DIR, 'events.txt')).read().split())
    return bl | ev


def spread(points, k=4):
    """Up to k representative points: the first, then each time the one farthest from those already chosen."""
    pts = [p for p in points if p]
    if not pts: return []
    # most common continent only
    cont = collections.Counter(p[0] for p in pts).most_common(1)[0][0]
    pts = [p for p in pts if p[0] == cont]
    # start from the densest point (median-ish)
    cx = sorted(p[1] for p in pts)[len(pts) // 2]; cy = sorted(p[2] for p in pts)[len(pts) // 2]
    first = min(pts, key=lambda p: (p[1] - cx) ** 2 + (p[2] - cy) ** 2)
    out = [first]
    while len(out) < k and len(out) < len(pts):
        far = max(pts, key=lambda p: min((p[1] - q[1]) ** 2 + (p[2] - q[2]) ** 2 for q in out))
        if min((far[1] - q[1]) ** 2 + (far[2] - q[2]) ** 2 for q in out) < 60 ** 2: break
        out.append(far)
    return out


def item_sources(item_id, depth=0):
    """Where an item comes from: NPCs that drop it, objects that contain it, or items it is taken from."""
    it = F.load('Item').get(str(item_id))
    if not it or depth > 2: return []
    pts = []
    for n in F.lst(F.L(it, 2)) or []:
        if n: pts += F.npc_points(n)
    for o in F.lst(F.L(it, 3)) or []:
        if o: pts += F.object_points(o)
    if not pts:
        for i in F.lst(F.L(it, 4)) or []:
            if i: pts += item_sources(i, depth + 1)
    return pts


def starter_points(q):
    s = F.L(q, 2) or {}
    pts = []
    for n in F.lst(s.get('1')): 
        if n: pts += F.npc_points(n)
    for o in F.lst(s.get('2')):
        if o: pts += F.object_points(o)
    for i in F.lst(s.get('3')):
        if i: pts += item_sources(i)
    return pts


def ender_points(q):
    s = F.L(q, 3) or {}
    pts = []
    for n in F.lst(s.get('1')):
        if n: pts += F.npc_points(n)
    for o in F.lst(s.get('2')):
        if o: pts += F.object_points(o)
    return pts


def objective_points(q):
    o = F.L(q, 10) or {}
    pts = []
    for e in F.lst(o.get('1')):              # creatures
        e = F.lst(e)
        if e and e[0]: pts.append(spread(F.npc_points(e[0]), 3))
    for e in F.lst(o.get('2')):              # objects
        e = F.lst(e)
        if e and e[0]: pts.append(spread(F.object_points(e[0]), 3))
    for e in F.lst(o.get('3')):              # items
        e = F.lst(e)
        if e and e[0]: pts.append(spread(item_sources(e[0]), 3))
    for e in F.lst(o.get('5')):              # kill credit {{ids}, base}
        e = F.lst(e)
        if e and len(e) > 1 and e[1]: pts.append(spread(F.npc_points(e[1]), 3))
    te = F.lst(F.L(q, 9))                    # trigger end {text, {[zone] = {{x, y}}}}
    if len(te) > 1 and te[1]:
        for z, ps in te[1].items():
            for p in F.lst(ps):
                p = F.lst(p)
                if p and p[0] is not None and p[0] >= 0:
                    w = F.to_world(z, p[0], p[1])
                    if w: pts.append([w])
    flat = []
    for group in pts:
        for p in group:
            if p not in flat: flat.append(p)
    return flat[:8]


def side_of(q, starter_npcs, races=None):
    races = F.L(q, 6) or 0 if races is None else races
    if races:
        a, h = races & ALLI, races & HORDE
        if a and not h: return 1
        if h and not a: return 2
        if a and h: return 0
    # no race restriction: the faction the quest giver serves
    for n in starter_npcs:
        npc = F.load('Npc').get(str(n))
        f = npc and F.L(npc, 13)
        if f == 'A': return 1
        if f == 'H': return 2
    return 0


def who(rel):
    """Name of the first NPC, object or item of a startedBy / finishedBy relation."""
    rel = rel or {}
    for key, db in (('1', 'Npc'), ('2', 'Object'), ('3', 'Item')):
        for x in F.lst(rel.get(key)):
            row = x and F.load(db).get(str(x))
            if row and F.L(row, 1): return F.L(row, 1)
    return ''


def first(v):
    v = [x for x in F.lst(v) if x]
    return v[0] if v else 0


def build():
    Q = F.load('Quest')
    skip = excluded()
    rows = {}
    stats = collections.Counter()
    for k, q in Q.items():
        qid = int(k)
        if qid in skip: stats['excluded'] += 1; continue
        s = starter_points(q); e = ender_points(q)
        if not s and not e: stats['no position'] += 1; continue
        s = spread(s, 1); e = spread(e, 1)
        s = s[0] if s else None; e = e[0] if e else None
        starter_npcs = [n for n in F.lst((F.L(q, 2) or {}).get('1')) if n]
        pre = F.lst(F.L(q, 13)) or []
        group = F.lst(F.L(q, 12)) or []
        prev = 0
        if group: prev = max(x for x in group if x)          # all of them: the last one of the chain
        elif pre:
            alts = [x for x in pre if x]
            prev = alts[0] if len(alts) == 1 else 0   # one of several (often one per faction): not a single prerequisite
        races = F.L(q, 6, 0) or 0
        # Questie gives some Zephras Isle quests the Alliance Skyborne bit only while Horde Skyborne need them for their
        # chains (both factions share the island): a mask of Skyborne bits only means both Skyborne.
        if races in (1 << 32, 1 << 33): races = 3 << 32
        rows[qid] = dict(lvl=F.L(q, 5, 0) or 0, min=F.L(q, 4, 0) or 0, races=races, classes=F.L(q, 7, 0) or 0,
                         prev=prev, side=side_of(q, starter_npcs, races), title=F.L(q, 1, ''), s=s or e, e=e or s,
                         o=objective_points(q), excl=first(F.L(q, 16)),
                         pre_all=[x for x in group if x], pre_any=[x for x in pre if x],
                         gn=who(F.L(q, 2)), en=who(F.L(q, 3)))
        stats['quests'] += 1
        if (s or e)[0] < 0: stats['map coordinates (new zones)'] += 1
    print(dict(stats), file=sys.stderr)
    return rows


def lua_str(s): return '"' + s.replace('\\', '\\\\').replace('"', '\\"').replace('\n', ' ') + '"'


def write(rows, path=OUT):
    L = ['-- ForeverCompanion: quest database of WoW Forever (generated by tools/build_questdb.py, do not edit by hand).',
         '-- Source: QuestieDB, Forever data (https://github.com/Questie/QuestieDB, GPL v3): quests, givers, turn-ins and',
         '-- objective areas.  Holiday quests and quests not in the game are left out.',
         '-- [questID] = { level, minLevel, raceMask, classMask, prevQuest, side (0 both, 1 Alliance, 2 Horde), title,',
         '--   giver continent, x, y, turn-in continent, x, y, { objective continent, x, y, ... }, exclusiveGroup }',
         '-- Coordinates are world coordinates (continent 0 = Eastern Kingdoms, 1 = Kalimdor).  In the new Forever zones',
         '-- (no world reference yet) continent is -uiMapID and x, y are the map position * 10000: ns.ResolveNewZones()',
         '-- converts them in game.',
         'local _, ns = ...', '', 'ns.QuestDB = {']
    for qid in sorted(rows):
        r = rows[qid]
        o = ', '.join('%d, %d, %d' % p for p in r['o'])
        L.append('\t[%d] = { %d, %d, %d, %d, %d, %d, %s, %d, %d, %d, %d, %d, %d, { %s }, %d },' % (
            qid, r['lvl'], r['min'], r['races'], r['classes'], r['prev'], r['side'], lua_str(r['title']),
            r['s'][0], r['s'][1], r['s'][2], r['e'][0], r['e'][1], r['e'][2], o, r['excl']))
    L.append('}')
    # quest giver / turn-in names, shown by the leveling routes: ns.QuestNPCs[questID] = { giver index, turn-in index }
    names = []; index = {}
    def ix(n):
        if not n: return 0
        if n not in index: names.append(n); index[n] = len(names)
        return index[n]
    pairs = [(qid, ix(rows[qid]['gn']), ix(rows[qid]['en'])) for qid in sorted(rows)]
    L.append('ns.QuestNPCNames = { ' + ', '.join(lua_str(n) for n in names) + ' }')
    L.append('ns.QuestNPCs = {')
    for i in range(0, len(pairs), 8):
        L.append('\t' + ' '.join('[%d] = { %d, %d },' % p for p in pairs[i:i + 8]))
    L.append('}')
    open(path, 'w').write('\n'.join(L) + '\n')
    print('wrote', path, os.path.getsize(path), file=sys.stderr)


if __name__ == '__main__':
    rows = build()
    json.dump({str(k): v for k, v in rows.items()}, open(os.path.join(F.FDB_DIR, 'questdb.json'), 'w'))
    write(rows)
