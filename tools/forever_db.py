#!/usr/bin/env python3
"""Shared loader for the WoW Forever database (QuestieDB, Forever flavour) used by the generators.

Source: https://github.com/Questie/QuestieDB (GPL v3) -- data/Forever + Forever corrections, merged with its own
tools/export-forever.lua --include-authored, then converted to JSON by tools/questie_tojson.lua into FDB_DIR.

Questie stores positions as zone-map percentages per AreaID (Forever client maps).  The addon works in world
coordinates (continent, x, y), so every zone gets a linear transform fitted on NPCs whose world position is known
from CMaNGOS classic-db (same NPC ID, one spawn in both).  Zones with no such anchor (the new Forever zones) keep
map coordinates, written as continent = -uiMapID and x, y = map fraction * 10000; the addon converts them in game
with C_Map.GetWorldPosFromMapPos.
"""
import json, os, collections, statistics

FDB_DIR = os.environ.get('FDB_DIR', '/tmp/claude-0/fdb')
CM_JSON = '/tmp/claude-0/data/cmangos.json'
QDB_REPO = os.environ.get('QUESTIEDB', '/tmp/claude-0/questiedb')

_cache = {}


def load(name):
    if name not in _cache:
        _cache[name] = json.load(open(os.path.join(FDB_DIR, name + '.json')))
    return _cache[name]


def L(row, i, default=None):
    """Positional field i (1-based, as in the Questie schema) of an exported row."""
    v = row.get(str(i)) if isinstance(row, dict) else None
    return default if v is None else v


def lst(v):
    """Questie tables exported as JSON objects with "1", "2"... keys -> python list (holes become None)."""
    if v is None: return []
    if isinstance(v, list): return v
    n = max((int(k) for k in v), default=0)
    return [v.get(str(i)) for i in range(1, n + 1)]


def area_to_uimap():
    """AreaID -> uiMapID from QuestieDB support/Forever/Zones/areaIdToUiMapId.lua."""
    if 'a2m' in _cache: return _cache['a2m']
    import re
    out = {}
    for m in re.finditer(r'\[(\d+)\]\s*=\s*(\d+)', open(os.path.join(QDB_REPO, 'support/Forever/Zones/areaIdToUiMapId.lua')).read()):
        out[int(m.group(1))] = int(m.group(2))
    _cache['a2m'] = out
    return out


def zone_transforms():
    """AreaID -> (continent, a, b, c, d) with world x = a * mapY + b, world y = c * mapX + d (map in percent)."""
    if 'zt' in _cache: return _cache['zt']
    N = load('Npc')
    cm = json.load(open(CM_JSON))
    cols = cm['creature']['cols']
    sp = collections.defaultdict(list)
    for r in cm['creature']['rows']:
        d = dict(zip(cols, r))
        sp[int(d['id'])].append((int(d['map']), float(d['position_x']), float(d['position_y'])))
    pairs = collections.defaultdict(list)
    for k, n in N.items():
        world = sp.get(int(k), [])
        if len(world) != 1 or world[0][0] not in (0, 1): continue
        for z, pts in (L(n, 7) or {}).items():
            pts = [p for p in lst(pts) if p and lst(p)[0] not in (-1, None)]
            if len(pts) == 1:
                px, py = lst(pts[0])[:2]
                pairs[int(z)].append((px, py) + world[0])
    out = {}
    for z, P in pairs.items():
        cont = collections.Counter(p[2] for p in P).most_common(1)[0][0]
        P = [p for p in P if p[2] == cont]
        if len(P) < 4: continue
        def fit(xs, ys):
            # robust line fit: least squares, drop points off by more than 3 median residuals, refit
            pts = list(zip(xs, ys))
            for _ in range(3):
                n = len(pts); mx = sum(p[0] for p in pts) / n; my = sum(p[1] for p in pts) / n
                sxx = sum((p[0] - mx) ** 2 for p in pts)
                if sxx == 0: return None
                a = sum((p[0] - mx) * (p[1] - my) for p in pts) / sxx; b = my - a * mx
                res = [abs(p[1] - (a * p[0] + b)) for p in pts]
                med = statistics.median(res) or 1
                keep = [p for p, r in zip(pts, res) if r <= max(3 * med, 5)]
                if len(keep) == len(pts) or len(keep) < 4: break
                pts = keep
            return a, b, statistics.median(res), len(pts)
        fx = fit([p[1] for p in P], [p[3] for p in P])   # world x from map y
        fy = fit([p[0] for p in P], [p[4] for p in P])   # world y from map x
        if not fx or not fy: continue
        # sanity: world x decreases going south (map y up), world y decreases going east (map x up)
        if fx[0] >= 0 or fy[0] >= 0: continue
        out[z] = (cont, fx[0], fx[1], fy[0], fy[1], max(fx[2], fy[2]), min(fx[3], fy[3]))
    _cache['zt'] = out
    return out


def to_world(zone, x, y):
    """(continent, wx, wy) for a Questie point; (-uiMapID, x*100, y*100) for zones without transform; None if unknown."""
    if x is None or x < 0: return None
    t = zone_transforms().get(int(zone))
    if t:
        return (t[0], round(t[1] * y + t[2]), round(t[3] * x + t[4]))
    m = area_to_uimap().get(int(zone))
    if m: return (-m, round(x * 100), round(y * 100))
    return None


def npc_points(npc_id):
    n = load('Npc').get(str(npc_id))
    out = []
    if not n: return out
    for z, pts in (L(n, 7) or {}).items():
        for p in lst(pts):
            p = lst(p)
            if p and p[0] is not None and p[0] >= 0:
                w = to_world(z, p[0], p[1])
                if w: out.append(w)
    return out


def object_points(obj_id):
    o = load('Object').get(str(obj_id))
    out = []
    if not o: return out
    for z, pts in (L(o, 4) or {}).items():
        for p in lst(pts):
            p = lst(p)
            if p and p[0] is not None and p[0] >= 0:
                w = to_world(z, p[0], p[1])
                if w: out.append(w)
    return out


if __name__ == '__main__':
    zt = zone_transforms()
    print(len(zt), 'zones fitted')
    for z, t in sorted(zt.items(), key=lambda kv: -kv[1][5])[:12]:
        print(z, 'cont', t[0], 'resid', round(t[5], 1), 'n', t[6])
