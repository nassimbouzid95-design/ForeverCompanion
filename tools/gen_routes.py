#!/usr/bin/env python3
"""Generates Data/RoutesAuto.lua: WoW Forever leveling routes 1-60 for every starting area and class.

Data: the Forever quest database (QuestieDB Forever flavour, see forever_db.py and build_questdb.py) with the
new and changed Forever quests, Questie's quest XP table (estimated from the quest level for the new quests),
Wowhead quest-item drop rates, and the dungeon database of the addon.

The simulator plays the character: it walks (or rides from level 40) from action to action, accepts quests,
kills what the objectives need, turns quests in and runs dungeons, and keeps the clock.  At each moment it takes
the cheapest worthwhile action: quests whose experience per hour falls below a fraction of what grinding gives
are skipped, a dungeon is run when its experience per hour (group kills + its quests) beats questing.
tune() searches the parameters for each start and class and keeps the fastest simulated 1-60.

Usage: python3 gen_routes.py [--tune]      (FDB_DIR = folder of the JSON export, see forever_db.py)
"""
import json, math, re, os, sys, collections, itertools
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from forever_db import load, L, lst, to_world, area_to_uimap, QDB_REPO, FDB_DIR

ADDON = '/mnt/project-files/addon/ForeverCompanion'
OUT = os.path.join(ADDON, 'Data/RoutesAuto.lua')
REPORT = '/mnt/project-files/addon/v2-data/routes_report.json'
TUNED = '/mnt/project-files/addon/v2-data/routes_params.json'   # parameters found by --tune, reused by plain runs

XP_TO_LEVEL = [0, 400, 900, 1400, 2100, 2800, 3600, 4500, 5400, 6500, 7600, 8800, 10100, 11400, 12900, 14400, 16000, 17700,
    19400, 21300, 23200, 25200, 27300, 29400, 31700, 34000, 36400, 38900, 41400, 44300, 47400, 50800, 54500, 58600, 62800,
    67100, 71600, 76100, 80800, 85700, 90700, 95800, 101000, 106300, 111800, 117500, 123200, 129100, 135100, 141200,
    147500, 153900, 160400, 167100, 173900, 180800, 187900, 195000, 202300, 209800]

CLASS_BIT = dict(WARRIOR=1, PALADIN=2, HUNTER=4, ROGUE=8, PRIEST=16, SHAMAN=64, MAGE=128, WARLOCK=256, DRUID=1024)
RACE_BIT = dict(Human=1, Orc=2, Dwarf=4, NightElf=8, Scourge=16, Tauren=32, Gnome=64, Troll=128,
                SkyborneA=1 << 32, SkyborneH=1 << 33)
# key, faction, race file names (UnitRace 2nd return), race bits, start position
STARTS = [
    ('human', 'Alliance', ['Human'], ['Human'], (0, -8949, -132)),
    ('dwarf', 'Alliance', ['Dwarf', 'Gnome'], ['Dwarf', 'Gnome'], (0, -6240, 331)),
    ('nightelf', 'Alliance', ['NightElf'], ['NightElf'], (1, 10311, 832)),
    ('skyborne-a', 'Alliance', ['Skyborne'], ['SkyborneA'], None),
    ('orc', 'Horde', ['Orc', 'Troll'], ['Orc', 'Troll'], (1, -618, -4251)),
    ('tauren', 'Horde', ['Tauren'], ['Tauren'], (1, -2917, -257)),
    ('undead', 'Horde', ['Scourge'], ['Scourge'], (0, 1676, 1677)),
    ('skyborne-h', 'Horde', ['Skyborne'], ['SkyborneH'], None),
]
CLASSES = list(CLASS_BIT)

# ---------------------------------------------------------------------------------------------------------------
# data
Q = load('Quest'); N = load('Npc'); I = load('Item'); O = load('Object')
QDB = {int(k): v for k, v in json.load(open(os.path.join(FDB_DIR, 'questdb.json'))).items()}
ALL_Q = set(QDB)   # quests left out of the simulation below still block the quests that need them

XPDB = {int(a): (int(b), int(c)) for a, b, c in re.findall(r'\[(\d+)\]\s*=\s*\{(\d+),\s*(\d+)\}',
        open(os.path.join(QDB_REPO, 'support/Forever/QuestXP/xpDB-classic.lua')).read())}
by_level = collections.defaultdict(list)
for q, (lv, xp) in XPDB.items():
    if q in QDB and xp > 0: by_level[lv].append(xp)
MEDIAN_XP = {lv: sorted(v)[len(v) // 2] for lv, v in by_level.items() if len(v) >= 5}

def base_xp(qid):
    if qid in XPDB: return XPDB[qid][1]
    lv = QDB[qid]['lvl']
    if lv <= 0: return 0
    near = [MEDIAN_XP[l] for l in range(lv - 2, lv + 3) if l in MEDIAN_XP]
    return sorted(near)[len(near) // 2] if near else 0

def quest_xp(qid, level):
    xp = base_xp(qid)
    ql = QDB[qid]['lvl'] if QDB[qid]['lvl'] > 0 else level
    diff = level - ql
    if diff >= 10: return int(xp * 0.1)
    if diff >= 6: return int(xp * {6: 0.8, 7: 0.6, 8: 0.4, 9: 0.2}[diff])
    return xp

# quest item drop rates (Wowhead, via Questie): item -> {npc: percent}
DROPS = {}
src = open(os.path.join(QDB_REPO, 'support/Forever/DropTables/classicItemDrops.lua')).read()
for m in re.finditer(r'\[(\d+)\] = \{[^\n]*\n((?:\s+\[\d+\] = [\d.]+,\n)+)', src):
    DROPS[int(m.group(1))] = {int(a): float(b) for a, b in re.findall(r'\[(\d+)\] = ([\d.]+)', m.group(2))}

def mob_xp(level): return 45 + 5 * level

NUM = re.compile(r'\b(\d{1,2})\b')
def work(qid):
    """(number of kills, number of interactions, elite?) needed by the quest objectives."""
    r = Q.get(str(qid))
    if not r: return 0, 0, False
    text = ' '.join(x for x in lst(L(r, 8)) if x)
    nums = [int(n) for n in NUM.findall(text) if 1 <= int(n) <= 30]
    obj = L(r, 10) or {}
    kills = inter = 0; elite = False; i = 0
    def count():
        nonlocal i
        c = nums[i] if i < len(nums) else 1
        i += 1
        return c
    for c in lst(obj.get('1')):
        c = lst(c)
        if not c or not c[0]: continue
        n = N.get(str(c[0]))
        if n and (L(n, 6) or 0) in (1, 2) and (L(n, 5) or 0) > 10: elite = True
        kills += count()
    for c in lst(obj.get('2')):
        if c: inter += count()
    for c in lst(obj.get('3')):
        c = lst(c)
        if not c or not c[0]: continue
        k = count()
        it = I.get(str(c[0]))
        rates = DROPS.get(c[0])
        if it and lst(L(it, 3)) and not lst(L(it, 2)):
            inter += k                                     # picked up from objects
        elif rates:
            rate = sorted(rates.values())[len(rates) // 2] / 100
            kills += k / max(rate, 0.15)
        elif it and lst(L(it, 2)):
            kills += k / 0.45
        else:
            inter += k
    for c in lst(obj.get('5')):
        if c: kills += count()
    return min(kills, 60), min(inter, 20), elite

# dungeons: key -> instance step id, entrance (world), levels to run, side
def dungeon_quests():
    """Instance key -> quest IDs, as the addon ends up with them (InstanceForever.lua rewrites the Classic lists)."""
    dq = collections.defaultdict(list)
    for path in ('Data/DungeonQuests.lua', 'Data/ForeverDungeons.lua'):
        txt = open(os.path.join(ADDON, path)).read()
        for m in re.finditer(r'\["([^"]+)"\] = \{ ([\d, ]+) \}', txt):
            dq[m.group(1)] += [int(x) for x in m.group(2).split(',')]
        for m in re.finditer(r'DungeonQuests\["([^"]+)"\] if l then for _, id in ipairs\(\{ ([\d, ]+) \}\)', txt):
            dq[m.group(1)] += [int(x) for x in m.group(2).split(',')]
    for m in re.finditer(r'ns\.DungeonQuests\["([^"]+)"\] = \{ ([\d, ]+) \}', open(os.path.join(ADDON, 'Data/InstanceForever.lua')).read()):
        dq[m.group(1)] = [int(x) for x in m.group(2).split(',')]
    return dq
DQ = dungeon_quests()

ENTRANCES = {}; DUNGEON_PARENT = {}
for m in re.finditer(r'\[(\d+)\] = \{"([^"]+)",[^,]*(?:\{[^}]*\})?[^,]*,(\d+),\{\{(\d+), ([\d.]+), ([\d.]+)\}',
                     open(os.path.join(QDB_REPO, 'support/Forever/Zones/dungeons.lua')).read()):
    DUNGEON_PARENT[int(m.group(1))] = int(m.group(3))
    ENTRANCES[int(m.group(1))] = to_world(int(m.group(4)), float(m.group(5)), float(m.group(6)))
UIMAP_AREA = {int(a): int(b) for a, b in re.findall(r'\[(\d+)\]\s*=\s*(\d+)', open(os.path.join(QDB_REPO, 'support/Forever/Zones/uiMapIdToAreaId.lua')).read())}

# key, step instance (mapID or key), dungeon area, levels (from, to), side (0 both, 1 A, 2 H), bosses (run length)
DUNGEONS = [
    ('Ragefire', 389, 2437, (13, 17), 2, 4), ('WailingCaverns', 43, 718, (17, 22), 0, 8),
    ('TheDeadmines', 36, 1581, (18, 23), 1, 8), ('ShadowfangKeep', 33, 209, (22, 26), 0, 9),
    ('BlackfathomDeeps', 48, 719, (24, 28), 0, 8), ('TheStockade', 34, 717, (24, 28), 1, 6),
    ('Gnomeregan', 90, 721, (29, 33), 0, 6), ('RazorfenKraul', 47, 491, (29, 33), 0, 8),
    ('ScarletMonasteryGraveyard', 189, 796, (30, 33), 0, 3), ('ScarletMonasteryLibrary', 189, 796, (33, 37), 0, 2),
    ('ScarletMonasteryArmory', 189, 796, (36, 40), 0, 1), ('ScarletMonasteryCathedral', 189, 796, (38, 42), 0, 3),
    ('RazorfenDowns', 129, 722, (37, 41), 0, 5), ('Uldaman', 70, 1337, (42, 46), 0, 9),
    ("Zul'Farrak", 209, 1176, (44, 48), 0, 8), ('Maraudon', 349, 2100, (46, 50), 0, 8),
    ("TheTempleOfAtal'Hakkar", 109, 1477, (50, 54), 0, 8), ('BlackrockDepths', 230, 1584, (52, 57), 0, 14),
]

def forever_dungeons():
    """The new Forever dungeons from Data/ForeverDungeons.lua (entrance from `where`)."""
    out = []
    txt = open(os.path.join(ADDON, 'Data/ForeverDungeons.lua')).read()
    for m in re.finditer(r'key = "([^"]+)", name = "[^"]+", kind = "dungeon", size = 5, enter = (\d+), min = (\d+), max = (\d+)[^\n]*\n\s*where = \{ zone = (\d+), x = ([\d.]+), y = ([\d.]+)', txt):
        key, enter, lo, hi, zone, x, y = m.groups()
        area = UIMAP_AREA.get(int(zone))
        pos = to_world(area, float(x) * 100, float(y) * 100) if area else None
        nb = len(re.findall(r'\{ name = ', txt[m.end():txt.find('table.insert', m.end()) if txt.find('table.insert', m.end()) > 0 else len(txt)]))
        if pos:
            lo, hi = int(lo), int(hi)
            out.append((key, key, None, (lo + 1, max(lo + 2, hi - 2)), 0, max(nb, 3), pos))
    return out

DUNGEON_LIST = [(k, inst, ENTRANCES.get(area), lv, side, nb) for k, inst, area, lv, side, nb in DUNGEONS] + \
               [(k, inst, pos, lv, side, nb) for k, inst, _a, lv, side, nb, pos in forever_dungeons()]
DUNGEON_BY_KEY = {d[0]: d for d in DUNGEON_LIST}
DUNGEON_AREA = {k: area for k, inst, area, lv, side, nb in DUNGEONS}
DQ_OF = {}
for k, *_ in DUNGEON_LIST:
    for q in DQ.get(k, []): DQ_OF.setdefault(q, k)
# quests whose objectives are only inside a dungeon: done in that dungeon, never solo at its entrance
_AREA_KEY = {}
for k, inst, area, lv, side, nb in DUNGEONS: _AREA_KEY.setdefault(area, k)
_ALT = {}
for m in re.finditer(r'\[(\d+)\] = \{"[^"]+",\{([\d,]*)\}', open(os.path.join(QDB_REPO, 'support/Forever/Zones/dungeons.lua')).read()):
    for a in re.findall(r'\d+', m.group(2)): _ALT[int(a)] = int(m.group(1))
for qid, q in list(QDB.items()):
    dz = q.get('dz')
    if not dz or qid in DQ_OF: continue
    key = _AREA_KEY.get(_ALT.get(dz, dz))
    if key and key in DUNGEON_BY_KEY: DQ_OF[qid] = key
    else: del QDB[qid]

# ---------------------------------------------------------------------------------------------------------------
# movement
RUN, MOUNT, MOUNT_LEVEL = 7.0, 11.2, 40
SHIP = 700           # seconds to change continent (boat / zeppelin and waiting)
PORTAL = 150         # into / out of a separate map (Zephras Isle, Shen'dralas...)
SEPARATE_SCALE = 0.35  # yards per map unit (map fraction * 10000) in the new Forever zones
DETOUR = 1.25        # paths are not straight lines
FLIGHT = 28.0        # yards per second on a flight path, plus FLIGHT_WAIT
FLIGHT_WAIT = 50

OPEN_MAPS = {1: (-2652,)}
CLOSED_MAPS = {-2521}   # Shen'dralas is entered from Desolace

def travel(a, b, level):
    if a is None or b is None: return 0
    if a[0] != b[0]:
        if a[0] in CLOSED_MAPS: return 1e6                                 # Zephras Isle: left by its last quest
        if b[0] < 0 and b[0] not in OPEN_MAPS.get(a[0], ()): return 1e6   # cannot walk to Zephras Isle
        return PORTAL if a[0] < 0 or b[0] < 0 else SHIP
    d = math.hypot(a[1] - b[1], a[2] - b[2]) * (SEPARATE_SCALE if a[0] < 0 else 1)
    speed = MOUNT if level >= MOUNT_LEVEL else RUN
    walk = d * DETOUR / speed
    if level >= 10 and a[0] >= 0 and d > 1500:
        walk = min(walk, FLIGHT_WAIT + d * 1.15 / FLIGHT + 120 / speed * 7)
    return walk

def kill_time(level): return 26 + level * 0.3    # seconds per kill, rest included
def grind_rate(level): return mob_xp(level) / kill_time(level)

# ---------------------------------------------------------------------------------------------------------------
# not for leveling: battlegrounds, raids, world PvP, war effort, profession quests
SKIP_ZONES = {2597, 3277, 3358, 1977, 2717, 2677, 3428, 3429, 3456, 2159, 16606, 16941, -365, -367, -368, -344, -1}
for qid in [q for q in QDB if L(Q.get(str(q), {}), 17) in SKIP_ZONES or L(Q.get(str(q), {}), 18)]:
    del QDB[qid]
TRANSIT = {qid for qid, q in QDB.items() if q['s'][0] in CLOSED_MAPS and q['e'][0] != q['s'][0]}
QINFO = {}
for qid, q in QDB.items():
    k, it, el = work(qid)
    QINFO[qid] = dict(kills=k, inter=it, elite=el)
CHILDREN = collections.defaultdict(list)
for qid, q in QDB.items():
    for p in set(q.get('pre_all', []) + q.get('pre_any', [])): CHILDREN[p].append(qid)


class Sim:
    def __init__(self, start, cls, P):
        self.key, self.faction, self.race_names, races, self.start_pos = start
        self.cls = cls
        self.P = P
        self.side = 1 if self.faction == 'Alliance' else 2
        self.rbits = 0
        for r in races: self.rbits |= RACE_BIT[r]
        self.cbit = CLASS_BIT[cls]
        self.level, self.xp, self.time = 1, 0, 0.0
        self.turned, self.log, self.done_obj, self.excl = set(), {}, set(), set()
        self.dungeons_done = set()
        self.dropped = set()
        self.steps = []
        self.pool = [qid for qid, q in QDB.items() if q['side'] in (0, self.side) and (not q['races'] or q['races'] & self.rbits)
                     and (not q['classes'] or q['classes'] & self.cbit)]
        self.pos = self.start_pos
        self.quest_time = 0.0; self.quest_xp = 0.0
        self.grind_xp = 0

    # -- rules -----------------------------------------------------------------------------------------------
    def available(self, qid, q):
        if qid in self.turned or qid in self.log or qid in self.dropped: return False
        if q['side'] not in (0, self.side): return False
        if q['races'] and not q['races'] & self.rbits: return False
        if q['classes'] and not q['classes'] & self.cbit: return False
        if q['min'] > self.level: return False
        if q['excl'] > 0 and q['excl'] in self.excl: return False
        if any(p in ALL_Q and p not in self.turned for p in q.get('pre_all', ())): return False
        pa = [p for p in q.get('pre_any', ()) if p in ALL_Q]
        if pa and not any(p in self.turned for p in pa): return False
        if q['prev'] < 0 and -q['prev'] in ALL_Q and -q['prev'] not in self.log and -q['prev'] not in self.turned: return False
        return True

    def value(self, qid, level=None):
        level = level or self.level
        qi = QINFO[qid]
        ql = QDB[qid]['lvl'] if QDB[qid]['lvl'] > 0 else level
        xp = quest_xp(qid, level) + qi['kills'] * mob_xp(min(ql, level))
        xp += self.P['chain'] * self.chain_xp(qid, level, 3)
        return xp

    def chain_xp(self, qid, level, depth):
        out = 0
        for c in CHILDREN.get(qid, ()):
            if c in QDB and c not in self.turned and (not QDB[c]['races'] or QDB[c]['races'] & self.rbits) and (not QDB[c]['classes'] or QDB[c]['classes'] & self.cbit):
                out += quest_xp(c, level) + (0.7 * self.chain_xp(c, level, depth - 1) if depth > 1 else 0)
        return out

    def cost(self, qid):
        q = QDB[qid]; qi = QINFO[qid]
        t = 16 + qi['kills'] * kill_time(self.level) + qi['inter'] * 8
        if q['o']:
            c = q['o'][0]
            t += travel(q['s'], c, self.level) + travel(c, q['e'], self.level)
            t += len(q['o']) * 15
        elif qid in TRANSIT:
            t += PORTAL
        else:
            t += travel(q['s'], q['e'], self.level)
        return t

    def worthwhile(self, qid):
        q = QDB[qid]; qi = QINFO[qid]
        if q['classes'] or qid in TRANSIT or q['s'][0] in CLOSED_MAPS: return True   # the start island is done entirely                                  # class quests: spells, pets, forms
        if qi['elite']: return False
        if qid in DQ_OF:
            d = DUNGEON_BY_KEY.get(DQ_OF[qid])
            if not (self.P['dungeons'] and d and d[2] and DQ_OF[qid] not in self.dungeons_done and d[4] in (0, self.side)): return False
            lo, hi = d[3]
            if sum(1 for x in self.log if x in DQ_OF) >= 8: return False
            return lo - 4 <= self.level <= hi and quest_xp(qid, hi) > 0
        ql = q['lvl'] if q['lvl'] > 0 else self.level
        if ql > self.level + (2 if self.level < 10 else self.P['lead']): return False
        if ql < self.level - self.P['grey']: return False
        rate = self.value(qid) / max(self.cost(qid), 1)
        return rate >= self.P['min_rate'] * grind_rate(self.level)

    # -- experience --------------------------------------------------------------------------------------------
    def gain(self, amount):
        self.xp += amount
        while self.level < 60 and self.xp >= XP_TO_LEVEL[self.level]:
            self.xp -= XP_TO_LEVEL[self.level]; self.level += 1

    def move(self, p):
        t = travel(self.pos, p, self.level)
        if t >= 1e6: t = PORTAL
        ship = self.pos is not None and p is not None and self.pos[0] != p[0]
        self.time += t
        if self.pos is None or ship or t > self.P['goto']:
            self.steps.append(('goto', p, ship))
        self.pos = p
        return t

    # -- dungeons ----------------------------------------------------------------------------------------------
    def dungeon_candidates(self):
        for d in DUNGEON_LIST:
            key, inst, pos, (lo, hi), side, nb = d
            if key in self.dungeons_done or not pos: continue
            if side not in (0, self.side): continue
            if lo <= self.level <= hi: yield d

    def dungeon_rate(self, d):
        key, inst, pos, lv, side, nb = d
        run = self.P['run_base'] + nb * self.P['run_boss']
        kills = 20 + nb * 9                       # trash and bosses, per member, in normal-mob experience
        xp = kills * mob_xp(self.level) * self.P['group_xp']
        qx = sum(quest_xp(q, self.level) for q in self.log if DQ_OF.get(q) == key)
        t = run + travel(self.pos, pos, self.level) + self.P['lfg']
        return (xp + qx) / t, run, xp

    def run_dungeon(self, d):
        key, inst, pos, lv, side, nb = d
        rate, run, xp = self.dungeon_rate(d)
        self.move(pos)
        self.time += run + self.P['lfg']
        lvl0 = self.level
        self.gain(xp)
        for q in list(self.log):
            if DQ_OF.get(q) == key: self.done_obj.add(q)
        self.steps.append(('dungeon', inst, key, lvl0))
        self.dungeons_done.add(key)

    # -- main loop ---------------------------------------------------------------------------------------------
    def run(self):
        P = self.P
        if self.pos is None:
            first = [qid for qid, q in QDB.items() if q['lvl'] <= 1 and q['s'][0] < 0 and self.available(qid, q)]
            self.pos = QDB[min(first)]['s'] if first else (0, 0, 0)
        guard = 0
        while self.level < 60 and guard < 20000:
            guard += 1
            acts = []
            for qid, q in self.log.items():
                if qid in self.done_obj or not QDB[qid]['o'] and qid not in DQ_OF and not QINFO[qid]['kills'] and not QINFO[qid]['inter']:
                    e = QDB[qid]['e']
                    t = PORTAL if self.pos and self.pos[0] in CLOSED_MAPS and e[0] != self.pos[0] and QDB[qid]['s'][0] == self.pos[0] else travel(self.pos, e, self.level)
                    # far turn-ins wait (tw > 1): the objectives nearby get done first, then everything is handed in together
                    acts.append((t - 30 if t < 150 else t * P['tw'] - 30, 'turnin', qid, e))
                elif qid not in DQ_OF:
                    o = min(QDB[qid]['o'] or [QDB[qid]['s']], key=lambda p: travel(self.pos, p, self.level))
                    acts.append((travel(self.pos, o, self.level), 'complete', qid, o))
            if len(self.log) < 20:
                for qid in self.pool:
                    q = QDB[qid]
                    if q['min'] <= self.level and self.available(qid, q) and self.worthwhile(qid):
                        acts.append((travel(self.pos, q['s'], self.level) + 5, 'accept', qid, q['s']))
            # a dungeon now?
            if P['dungeons']:
                qrate = (self.quest_xp / self.quest_time) if self.quest_time > 1800 else grind_rate(self.level) * 1.5
                best = max(self.dungeon_candidates(), key=lambda d: self.dungeon_rate(d)[0], default=None)
                if best and self.dungeon_rate(best)[0] >= P['dungeon_factor'] * qrate:
                    pend = [qid for qid in QDB if DQ_OF.get(qid) == best[0] and self.available(qid, QDB[qid])
                            and travel(self.pos, QDB[qid]['s'], self.level) < 400]
                    if not pend:
                        self.run_dungeon(best)
                        continue
            acts = [a for a in acts if a[0] < 1e5]
            if not acts and len(self.log) >= 20:
                worst = min((x for x in self.log if x not in self.done_obj), key=lambda x: self.value(x), default=None)
                if worst:
                    del self.log[worst]; self.dropped.add(worst); self.steps.append(('abandon', worst))
                    continue
            if not acts:
                need = XP_TO_LEVEL[self.level] - self.xp
                self.time += need / grind_rate(self.level)
                self.grind_xp += need
                self.gain(need)
                if self.steps and self.steps[-1][0] == 'level': self.steps.pop()
                self.steps.append(('level', self.level))
                continue
            acts.sort(key=lambda a: a[0])
            _, kind, qid, p = acts[0]
            t0, x0, l0 = self.time, self.level * 1e6 + self.xp, self.level
            self.move(p)
            q = QDB[qid]; qi = QINFO[qid]
            if kind == 'accept':
                self.log[qid] = True
                self.time += 5
                if q['excl'] > 0: self.excl.add(q['excl'])
            elif kind == 'complete':
                self.done_obj.add(qid)
                self.time += qi['kills'] * kill_time(self.level) + qi['inter'] * 8 + max(0, len(q['o']) - 1) * 15
                ql = q['lvl'] if q['lvl'] > 0 else self.level
                self.gain(int(qi['kills'] * mob_xp(min(ql, self.level))))
            else:
                del self.log[qid]; self.turned.add(qid)
                self.time += 8
                self.gain(quest_xp(qid, self.level))
            self.steps.append((kind, qid, p, l0))
            self.quest_time = self.quest_time * 0.995 + (self.time - t0)
            self.quest_xp = self.quest_xp * 0.995 + (self.level * 1e6 + self.xp - x0 if self.level == l0 else XP_TO_LEVEL[l0] - (x0 - l0 * 1e6) + self.xp)
            # drop quests that went grey and are not worth finishing
            for qid in [x for x in self.log if x not in self.done_obj and (QDB[x]['lvl'] > 0 and QDB[x]['lvl'] < self.level - P['grey'] - 1
                        or x in DQ_OF and (DQ_OF[x] in self.dungeons_done or self.level > DUNGEON_BY_KEY[DQ_OF[x]][3][1]))]:
                del self.log[qid]; self.dropped.add(qid)
                self.steps.append(('abandon', qid))
        return self


# dungeon_factor: a dungeon goes in the route when it levels at least 75 % as fast as questing at that point; its
# loot (best-in-slot items of that level) and its quests make up for the rest, so it is not tuned away.
DEFAULT = dict(lead=3, grey=5, min_rate=0.6, chain=0.5, tw=1.0, goto=240, dungeons=True, dungeon_factor=0.75,
               run_base=1500, run_boss=240, group_xp=1.0, lfg=600)


def simulate(start, cls, P):
    return Sim(start, cls, P).run()


def tune(start, cls, base=DEFAULT):
    """Coordinate search on the route parameters: keeps any change that shortens the simulated 1-60."""
    best_p = dict(base)
    best = simulate(start, cls, best_p)
    grid = dict(lead=[2, 3, 4, 5, 6], grey=[3, 4, 5, 6, 7, 8], min_rate=[0.3, 0.45, 0.6, 0.8, 1.0, 1.3], chain=[0, 0.5, 1, 1.5], tw=[1.0, 1.5, 2.0, 3.0, 5.0])
    tried = 1
    for _round in range(3):
        improved = False
        for k, values in grid.items():
            for v in values:
                if v == best_p[k]: continue
                p = dict(best_p, **{k: v})
                s = simulate(start, cls, p); tried += 1
                if s.level >= best.level and s.time < best.time - 60:
                    best, best_p, improved = s, p, True
        if not improved: break
    return best, best_p, tried

# ---------------------------------------------------------------------------------------------------------------
# output: one route per (start, class), steps packed in a string expanded by the addon (Data/Routes.lua).
AREA_NAMES = {}
for a, m, name in re.findall(r'\[(\d+)\]\s*=\s*(\d+),\s*--\s*(.+)', open(os.path.join(QDB_REPO, 'support/Forever/Zones/areaIdToUiMapId.lua')).read()):
    AREA_NAMES[int(a)] = name.split("->")[-1].strip()

def zone_name(qid):
    z = L(Q.get(str(qid), {}), 17)
    z = DUNGEON_PARENT.get(z, z)
    if z and z > 0 and z in AREA_NAMES:
        NAME_AREA[AREA_NAMES[z]] = z
        return AREA_NAMES[z]
    return None

ZONES = []

NAME_AREA = {}

def zone_index(name):
    """Index in ns.RouteZones = { { uiMapID, English name } } (the addon shows the client's localised map name)."""
    if name not in ZONES: ZONES.append(name)
    return ZONES.index(name) + 1


def pack(sim):
    """Steps -> list of chapters (name, min, max, packed)."""
    chapters = []
    dest = {}
    nxt = None
    for i in range(len(sim.steps) - 1, -1, -1):
        s = sim.steps[i]
        if s[0] in ('accept', 'complete', 'turnin'): nxt = zone_name(s[1]) or nxt
        elif s[0] == 'dungeon': nxt = AREA_NAMES.get(DUNGEON_PARENT.get(DUNGEON_AREA.get(s[2])), nxt) if DUNGEON_AREA.get(s[2]) else nxt
        elif s[0] == 'goto': dest[i] = nxt
    cur = None
    names = collections.Counter()
    def flush():
        if cur and cur['tokens']:
            chapters.append(cur)
    for si, s in enumerate(sim.steps):
        kind = s[0]
        if kind == 'goto':
            p, ship = s[1], s[2]
            # a new chapter at each long trip
            flush()
            cur = dict(tokens=[], min=None, max=None, names=collections.Counter())
            cur['tokens'].append('g%d,%d,%d,%d%s' % (p[0], p[1], p[2], zone_index(dest.get(si) or 'Leveling'), ',s' if ship else ''))
            continue
        if cur is None: cur = dict(tokens=[], min=None, max=None, names=collections.Counter())
        if kind in ('accept', 'complete', 'turnin'):
            qid, p, lv = s[1], s[2], s[3]
            tok = {'accept': 'a', 'complete': 'c', 'turnin': 't'}[kind] + str(qid)
            if kind == 'complete' and QDB[qid]['o'] and tuple(p) != tuple(QDB[qid]['o'][0]):
                tok += '@%d' % [tuple(x) for x in QDB[qid]['o']].index(tuple(p))
            cur['tokens'].append(tok)
            cur['min'] = lv if cur['min'] is None else min(cur['min'], lv)
            cur['max'] = lv if cur['max'] is None else max(cur['max'], lv)
            n = zone_name(qid)
            if n: cur['names'][n] += 1
        elif kind == 'level':
            cur['tokens'].append('l%d' % s[1])
            cur['max'] = s[1] if cur['max'] is None else max(cur['max'], s[1])
        elif kind == 'dungeon':
            inst, key, lv = s[1], s[2], s[3]
            cur['tokens'].append('d%s@%d,%d' % (key, lv, DUNGEON_BY_KEY[key][3][1] + 3))
            cur['min'] = lv if cur['min'] is None else min(cur['min'], lv)
        elif kind == 'abandon':
            cur['tokens'].append('x%d' % s[1])
    flush()
    # merge tiny chapters into the previous one
    for c in chapters:
        c['name'] = c['names'].most_common(1)[0][0] if c['names'] else None
    merged = []
    for c in chapters:
        if merged and (len(c['tokens']) < 15 or c['min'] is None or c['name'] in (None, merged[-1]['name'])):
            m = merged[-1]
            m['tokens'] += c['tokens']; m['names'] += c['names']
            if c['max'] is not None: m['max'] = max(m['max'] or 0, c['max'])
        else:
            merged.append(c)
    lv = 1
    for c in merged:
        c['min'] = c['min'] if c['min'] is not None else lv
        c['max'] = max(c['max'] or c['min'], c['min'])
        lv = c['max']
        c['name'] = c['names'].most_common(1)[0][0] if c['names'] else 'Leveling'
    out = []
    for c in merged:   # names can match again after merging
        if out and out[-1]['name'] == c['name']:
            out[-1]['tokens'] += c['tokens']; out[-1]['max'] = max(out[-1]['max'], c['max'])
        else:
            out.append(c)
    merged = out
    if merged and sim.level >= 60: merged[-1]['max'] = 60
    return merged


def lua(s): return '"' + s.replace('\\', '\\\\').replace('"', '\\"') + '"'


def job(args):
    start, cls, P = args
    return start, cls, simulate(start, cls, P), P, 1


def tune_job(args):
    start, cls, base = args
    sim, P, tried = tune(start, cls, base)
    print('tuned %-11s %-8s %.1f h (%d runs) %s' % (start[0], cls, sim.time / 3600, tried, P), flush=True)
    return '%s-%s' % (start[0], cls), P, tried


def main():
    import multiprocessing
    do_tune = '--tune' in sys.argv
    only = [a for a in sys.argv[1:] if not a.startswith('--')]
    out = ['-- ForeverCompanion: leveling routes 1-60 for each starting area and class (generated, do not edit by hand).',
           '-- Built by tools/gen_routes.py from the WoW Forever quest database (QuestieDB Forever data, GPL v3): new and',
           '-- changed Forever quests included, simulated with walking/riding time, kill time, quest and kill experience,',
           '-- dungeons when they level at least 75 % as fast as questing (their loot makes up for the rest).  Steps are packed (format in Data/Routes.lua).',
           'local _, ns = ...', 'local R = ns.RegisterPackedRoute', '']
    report = {}
    starts = [st for st in STARTS if not only or st[0] in only]
    # parameters per start and class ("human-WARRIOR"); older files were per start only
    saved = json.load(open(TUNED)) if os.path.exists(TUNED) else {}
    def base(st, cls):
        P = dict(DEFAULT); P.update(saved.get(st[0], {})); P.update(saved.get('%s-%s' % (st[0], cls), {}))
        P['dungeon_factor'] = DEFAULT['dungeon_factor']
        return P
    params = {'%s-%s' % (st[0], cls): base(st, cls) for st in starts for cls in CLASSES}
    with multiprocessing.Pool(4) as pool:
        if do_tune:
            for key, P, tried in pool.imap_unordered(tune_job, [(st, cls, base(st, cls)) for st in starts for cls in CLASSES]):
                params[key] = P
            saved.update(params)
            json.dump({k: v for k, v in saved.items() if '-' in k and k.split('-')[-1] in CLASSES}, open(TUNED, 'w'), indent=1)
        jobs = [(start, cls, params['%s-%s' % (start[0], cls)]) for start in starts for cls in CLASSES]
        results = pool.map(job, jobs, chunksize=1)
    for start, cls, sim, P, tried in results:
        hours = sim.time / 3600
        report['%s-%s' % (start[0], cls)] = dict(hours=round(hours, 1), level=sim.level, quests=len(sim.turned),
            dungeons=sorted(sim.dungeons_done), grind_xp=int(sim.grind_xp), params=P, tried=tried)
        print('%-11s %-8s level %d in %.1f h, %d quests, %d dungeons, grind %d xp (%d runs)' % (
            start[0], cls, sim.level, hours, len(sim.turned), len(sim.dungeons_done), sim.grind_xp, tried), flush=True)
        for i, c in enumerate(pack(sim)):
            out.append('R(%s, %d, %s, %s, %s, %d, %d, %s)' % (
                lua('auto-%s-%s-%02d' % (start[0], cls.lower(), i + 1)), zone_index(c['name']), lua(start[1]),
                '{ ' + ', '.join(lua(r) for r in start[2]) + ' }', lua(cls), c['min'], c['max'], lua(' '.join(c['tokens']))))
    a2m = area_to_uimap()
    out.insert(5, 'ns.RouteZones = { ' + ', '.join('{ %d, %s }' % (a2m.get(NAME_AREA.get(z), 0), lua(z)) for z in ZONES) + ' }')
    open(OUT, 'w').write('\n'.join(out) + '\n')
    json.dump(report, open(REPORT, 'w'), indent=1)


if __name__ == '__main__':
    main()
