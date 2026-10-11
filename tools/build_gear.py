#!/usr/bin/env python3
"""Generate ForeverCompanion/Data/GearGuide.lua: leveling "best in slot" gear per class, faction and
5-level bracket (10..60), with where every item comes from.

Usage:  python3 build_gear.py [--dump ClassicDB.sql.gz] [--out GearGuide.lua]

Sources
  * CMaNGOS classic-db dump (item_template, spell_template, quest_template, npc_vendor(_template),
    npc_trainer(_template), creature_template, creature, *_questrelation, creature_loot_template,
    reference_loot_template).  Extracted once to a JSON cache in /tmp/claude-0/gear/.
  * The addon's own data: Data/InstanceDB.lua (dungeon bosses + loot + rates), Data/QuestDB.lua and
    Data/DungeonQuests.lua (quest side: 0 both, 1 Alliance, 2 Horde).

Item is eligible for bracket L when RequiredLevel <= L and it is obtainable by then:
  * quest reward (RewChoiceItemId / RewItemId) with MinLevel <= L and QuestLevel <= L + 2, a quest giver
    and a turn-in in the DB, no profession / event / PvP / raid objective, right side, race and class;
  * boss drop (InstanceDB, kind "dungeon", min level <= L; type "extra" rows such as keys/trash skipped;
    drops with a known rate under 3 % skipped);
  * vendor item (quality <= green, not from a PvP quartermaster, item level - 10 <= L) sold by a spawned NPC on Kalimdor / Eastern Kingdoms of the right side (score x0.97 so
    it only wins when it is a real upgrade);
  * crafted item (item level - 10 <= L; spell_template "create item" effect taught by a trainer or a recipe), Bind on Equip
    only (so it can also be bought), no raid reagents (score x0.9 below 60).
Left out: world random drops, raid / world-boss loot, PvP (honor rank, battleground factions), items
gated behind honored+ reputation, random-enchant "of the ..." items.

Leveling specs and stat weights (points per 1 stat; "dps" = weapon DPS; % = 1 % chance).  These are the
usual leveling weights used by Pawn-style leveling profiles: 1 Str = 2 AP for plate/mail melee, ~14 AP per
weapon DPS point, so weapon DPS ~= 7 Str for a melee whose main ability scales off weapon damage.
"""
import gzip, json, os, re, sys, collections, argparse

HERE = os.path.dirname(os.path.abspath(__file__))
ADDON = os.path.join(HERE, '..', 'ForeverCompanion')
DATA = os.path.join(ADDON, 'Data')
CACHE_DIR = '/tmp/claude-0/gear'
DEFAULT_DUMP = '/home/claude/cmangos/classic-db/Full_DB/ClassicDB_1_12_1_z2815.sql.gz'
CM_JSON = '/tmp/claude-0/data/cmangos.json'
QUESTS_JSON = '/tmp/claude-0/data/dq/quests_full.json'

BRACKETS = list(range(10, 61, 5))
ALLI, HORDE = 77, 178
FACTION_MASK = {1: ALLI, 2: HORDE}
CLASS_BIT = dict(WARRIOR=1, PALADIN=2, HUNTER=4, ROGUE=8, PRIEST=16, SHAMAN=64, MAGE=128, WARLOCK=256, DRUID=1024)
# races (bit) able to play each class in 1.12
RACE_CLASS = {1: 'WARRIOR PALADIN ROGUE PRIEST MAGE WARLOCK', 2: 'WARRIOR HUNTER ROGUE SHAMAN WARLOCK',
              4: 'WARRIOR PALADIN HUNTER ROGUE PRIEST', 8: 'WARRIOR HUNTER ROGUE PRIEST DRUID',
              16: 'WARRIOR ROGUE PRIEST MAGE WARLOCK', 32: 'WARRIOR HUNTER SHAMAN DRUID',
              64: 'WARRIOR ROGUE MAGE WARLOCK', 128: 'WARRIOR HUNTER ROGUE PRIEST SHAMAN MAGE'}

# ---------------------------------------------------------------- weights
# keys: str agi sta int spi ap rap crit hit spell (all-school spell damage) shadow frost fire holy nature arcane
#       scrit shit mp5 heal armor block hp mana dps (main hand / 2h), ohdps (off hand), rdps (ranged), wanddps,
#       wskill (weapon skill point), defense
W = {
    # Arms warrior, two-hander.  Str 1 = 2 AP; Agi = crit (20 Agi per 1 %); hit is capped low while leveling.
    'WARRIOR': dict(str=1.0, agi=0.65, sta=0.5, ap=0.5, crit=14, hit=12, armor=0.02, block=0.05, hp=0.05,
                    dps=7.0, ohdps=0.0, rdps=0.5, wskill=1.5, defense=0.1),
    # Retribution paladin, two-hander, a bit of Int for Seal/Judgement/heals.
    'PALADIN': dict(str=1.0, agi=0.5, sta=0.6, int=0.4, spi=0.1, ap=0.5, crit=10, hit=10, spell=0.25, holy=0.25,
                    mp5=0.8, heal=0.05, armor=0.02, block=0.05, hp=0.05, mana=0.02, dps=6.5, wskill=1.2, defense=0.1),
    # Beast Mastery hunter: Agi (1 Agi = 2 RAP + crit), ranged weapon DPS is king; melee weapon = stat stick.
    'HUNTER': dict(str=0.1, agi=1.0, sta=0.5, int=0.3, spi=0.1, ap=0.1, rap=0.5, crit=10, hit=10, mp5=0.6,
                   armor=0.01, hp=0.05, mana=0.02, dps=0.5, ohdps=0.25, rdps=6.0, wskill=0.3),
    # Combat rogue: Agi (1 AP + crit), Str (1 AP); main-hand DPS matters most, off hand about half.
    'ROGUE': dict(str=0.55, agi=1.0, sta=0.4, ap=0.5, crit=12, hit=14, armor=0.01, hp=0.04,
                  dps=7.0, ohdps=3.5, rdps=0.3, wskill=1.5, defense=0.05),
    # Shadow priest: spell damage (shadow), Spirit (Spirit Tap / regen), Int, Sta; wand for finishing.
    'PRIEST': dict(sta=0.6, int=0.6, spi=0.8, spell=1.0, shadow=1.0, scrit=6, shit=8, mp5=1.0, heal=0.1,
                   armor=0.005, hp=0.05, mana=0.04, wanddps=3.0),
    # Enhancement shaman: two-hander (talent at 20), Str/Agi, Int for shocks, mail from 40.
    'SHAMAN': dict(str=1.0, agi=0.6, sta=0.5, int=0.4, spi=0.1, ap=0.5, crit=10, hit=10, spell=0.2, nature=0.2,
                   fire=0.1, frost=0.1, mp5=0.8, heal=0.05, armor=0.015, block=0.05, hp=0.05, mana=0.02,
                   dps=7.0, wskill=1.2),
    # Frost mage: Int, Spi, Sta, frost / spell damage, wand.
    'MAGE': dict(sta=0.6, int=0.8, spi=0.4, spell=1.0, frost=1.0, scrit=8, shit=8, mp5=1.0,
                 armor=0.005, hp=0.05, mana=0.04, wanddps=3.0),
    # Affliction warlock: Sta (Life Tap / survival) first, then Int/Spi, shadow / spell damage, wand.
    'WARLOCK': dict(sta=0.8, int=0.6, spi=0.6, spell=1.0, shadow=1.0, scrit=3, shit=8, mp5=0.8,
                    armor=0.005, hp=0.06, mana=0.03, wanddps=3.0),
    # Feral druid (cat): Str 2 AP in cat, Agi = 1 AP + crit; weapon DPS does nothing in forms.
    'DRUID': dict(str=1.0, agi=0.9, sta=0.6, int=0.2, spi=0.1, ap=0.5, crit=10, hit=10, mp5=0.3,
                  armor=0.02, hp=0.05, mana=0.01, dps=0.0, wskill=0.0),
}
SPEC = dict(WARRIOR='Arms', PALADIN='Retribution', HUNTER='Beast Mastery', ROGUE='Combat', PRIEST='Shadow',
            SHAMAN='Enhancement', MAGE='Frost', WARLOCK='Affliction', DRUID='Feral')
CASTERS = {'PRIEST', 'MAGE', 'WARLOCK'}

# ---------------------------------------------------------------- equipment rules (1.12)
# armor subclass: 1 cloth 2 leather 3 mail 4 plate 6 shield 7 libram 8 idol 9 totem
def max_armor(cls, lvl):
    if cls in ('WARRIOR', 'PALADIN'): return 4 if lvl >= 40 else 3
    if cls in ('HUNTER', 'SHAMAN'): return 3 if lvl >= 40 else 2
    if cls in ('ROGUE', 'DRUID'): return 2
    return 1
SHIELD = {'WARRIOR', 'PALADIN', 'SHAMAN'}
RELIC = {'PALADIN': 7, 'DRUID': 8, 'SHAMAN': 9}
# weapon subclass: 0 axe 1 axe2h 2 bow 3 gun 4 mace 5 mace2h 6 polearm 7 sword 8 sword2h 10 staff 13 fist
#                  15 dagger 16 thrown 18 crossbow 19 wand
WEAPONS = {
    'WARRIOR': {0, 1, 2, 3, 4, 5, 6, 7, 8, 10, 13, 15, 16, 18},
    'PALADIN': {0, 1, 4, 5, 6, 7, 8},
    'HUNTER': {0, 1, 2, 3, 6, 7, 8, 10, 13, 15, 16, 18},
    'ROGUE': {2, 3, 4, 7, 13, 15, 16, 18},
    'PRIEST': {4, 10, 15, 19},
    'SHAMAN': {0, 1, 4, 5, 10, 13, 15},
    'MAGE': {7, 10, 15, 19},
    'WARLOCK': {7, 10, 15, 19},
    'DRUID': {4, 5, 10, 13, 15},
}
RANGED_SUB = {2, 3, 16, 18, 19}
# Dual wield: rogues from 1, hunters from 20 (trainer).  Shaman 2h axes/maces: Enhancement talent (level 20).
def can_dual(cls, lvl): return cls == 'ROGUE' or (cls == 'HUNTER' and lvl >= 20)
# weapon configurations considered per class (2h, 1h + shield/held item, dual wield)
CONFIGS = {
    'WARRIOR': ('2h', 'shield'), 'PALADIN': ('2h', 'shield'), 'SHAMAN': ('2h', 'shield'),
    'HUNTER': ('2h', 'dual', 'holdable'), 'ROGUE': ('dual',), 'DRUID': ('2h', 'holdable'),
    'PRIEST': ('2h', 'holdable'), 'MAGE': ('2h', 'holdable'), 'WARLOCK': ('2h', 'holdable'),
}

SLOT_OF_INV = {1: 'head', 2: 'neck', 3: 'shoulder', 5: 'chest', 20: 'chest', 6: 'waist', 7: 'legs', 8: 'feet',
               9: 'wrist', 10: 'hands', 11: 'finger', 12: 'trinket', 16: 'back'}
SLOTS = ['head', 'neck', 'shoulder', 'back', 'chest', 'wrist', 'hands', 'waist', 'legs', 'feet',
         'finger1', 'finger2', 'trinket1', 'trinket2', 'mainhand', 'offhand', 'ranged']

RAID_KINDS = {'raid', 'world'}
BG_FACTIONS = {509, 510, 729, 730, 889, 890}
BG_ZONES = {3277, 3358, 2597}
RAID_MAPS = {409, 249, 309, 469, 509, 531, 533}
RAID_ZONES = {2717, 2159, 1977, 2677, 3429, 3428, 3456}
RAID_REP = {910}  # Brood of Nozdormu (AQ40)
PROF = {164: 'Blacksmithing', 165: 'Leatherworking', 197: 'Tailoring', 202: 'Engineering', 171: 'Alchemy',
        333: 'Enchanting', 186: 'Mining', 182: 'Herbalism', 185: 'Cooking', 129: 'First Aid'}
BAD_NAME = re.compile(r'(^Monster - |^Test |\bTEST\b|\(OLD\)|\bOLD\b|[Dd]eprecated|^\[PH\]|DEBUG|QA |Unused|zzOLD|NPC Equip)')

# ---------------------------------------------------------------- SQL extraction
TABLES = {
    'item_template': None, 'npc_vendor': None, 'npc_vendor_template': None, 'npc_trainer': None,
    'npc_trainer_template': None,
    'creature_template': ['Entry', 'Name', 'Faction', 'NpcFlags', 'VendorTemplateId', 'TrainerTemplateId', 'LootId'],
    'spell_template': ['Id', 'Effect1', 'Effect2', 'Effect3', 'EffectBasePoints1', 'EffectBasePoints2',
                       'EffectBasePoints3', 'EffectBaseDice1', 'EffectBaseDice2', 'EffectBaseDice3',
                       'EffectDieSides1', 'EffectDieSides2', 'EffectDieSides3',
                       'EffectApplyAuraName1', 'EffectApplyAuraName2', 'EffectApplyAuraName3',
                       'EffectMiscValue1', 'EffectMiscValue2', 'EffectMiscValue3', 'EffectItemType1',
                       'EffectItemType2', 'EffectItemType3', 'EffectTriggerSpell1', 'EffectTriggerSpell2',
                       'EffectTriggerSpell3', 'Stances', 'SpellName', 'Reagent1', 'Reagent2', 'Reagent3',
                       'Reagent4', 'Reagent5', 'Reagent6', 'Reagent7', 'Reagent8'],
}
ITEM_COLS = ['entry', 'class', 'subclass', 'name', 'Quality', 'Flags', 'InventoryType', 'AllowableClass',
             'AllowableRace', 'ItemLevel', 'RequiredLevel', 'RequiredSkill', 'requiredhonorrank',
             'RequiredReputationFaction', 'RequiredReputationRank', 'maxcount', 'armor', 'block', 'delay',
             'bonding', 'startquest', 'RandomProperty'] + \
            [f'stat_type{i}' for i in range(1, 11)] + [f'stat_value{i}' for i in range(1, 11)] + \
            [f'dmg_{a}{i}' for i in range(1, 6) for a in ('min', 'max')] + \
            [f'spellid_{i}' for i in range(1, 6)] + [f'spelltrigger_{i}' for i in range(1, 6)]


def parse_values(s, i):
    n = len(s); out = []
    while i < n:
        while i < n and s[i] in ' ,\n\r\t': i += 1
        if i >= n or s[i] == ';': break
        i += 1
        vals = []; cur = []; inq = False
        while True:
            c = s[i]
            if inq:
                if c == '\\': cur.append(s[i + 1]); i += 2; continue
                if c == "'":
                    if s[i + 1] == "'": cur.append("'"); i += 2; continue
                    inq = False; i += 1; continue
                cur.append(c); i += 1; continue
            if c == "'": inq = True; i += 1; continue
            if c == ',': vals.append(''.join(cur)); cur = []; i += 1; continue
            if c == ')': vals.append(''.join(cur)); i += 1; break
            cur.append(c); i += 1
        out.append(vals)
    return out, i


def extract(dump):
    cache = os.path.join(CACHE_DIR, 'extract.json')
    if os.path.exists(cache): return json.load(open(cache))
    text = gzip.open(dump, 'rt', encoding='utf-8', errors='replace').read()
    cols = {}
    for m in re.finditer(r"CREATE TABLE `(\w+)` \((.*?)\n\)", text, re.S):
        if m.group(1) in TABLES: cols[m.group(1)] = re.findall(r"^\s*`(\w+)`", m.group(2), re.M)
    keep = dict(TABLES); keep['item_template'] = ITEM_COLS
    rows = {t: [] for t in TABLES}
    for m in re.finditer(r"INSERT INTO `(\w+)` VALUES\s*", text):
        t = m.group(1)
        if t not in TABLES: continue
        vals, _ = parse_values(text, m.end())
        c = cols[t]; want = keep[t]
        idx = [c.index(k) for k in want] if want else list(range(len(c)))
        if t == 'spell_template':  # only spells that matter: auras / create item / learn spell
            for v in vals:
                effs = (v[c.index('Effect1')], v[c.index('Effect2')], v[c.index('Effect3')])
                if any(e in ('6', '24', '36', '35') for e in effs):
                    rows[t].append([v[j] for j in idx])
        else:
            for v in vals: rows[t].append([v[j] for j in idx])
    out = {t: {'cols': keep[t] or cols[t], 'rows': rows[t]} for t in TABLES}
    os.makedirs(CACHE_DIR, exist_ok=True)
    json.dump(out, open(cache, 'w'))
    return out


def table(db, name):
    t = db[name]; c = t['cols']
    return [dict(zip(c, r)) for r in t['rows']]

# ---------------------------------------------------------------- addon Lua data
LSTR = r'"((?:[^"\\]|\\.)*)"'

def load_instances():
    inst = []; cur = None; section = None
    for line in open(os.path.join(DATA, 'InstanceDB.lua'), encoding='utf-8'):
        m = re.search(r'key = ' + LSTR + r'.*?kind = "(\w+)".*?min = (\d+)', line)
        if m:
            cur = dict(key=m.group(1), kind=m.group(2), min=int(m.group(3)), bosses=[]); inst.append(cur)
            section = None; continue
        if 'bosses = {' in line: section = 'b'; continue
        if 'trash = {' in line: section = 't'; continue
        if cur and section == 'b':
            m = re.search(r'\{ name = ' + LSTR + r'(.*?)loot = \{([^}]*)\}', line)
            if m:
                typ = re.search(r'type = "(\w+)"', m.group(2))
                npc = re.search(r'npc = (\d+)', m.group(2))
                nums = [x.strip() for x in m.group(3).split(',') if x.strip()]
                loot = [(int(nums[k]), float(nums[k + 1])) for k in range(0, len(nums) - 1, 2)]
                cur['bosses'].append(dict(name=m.group(1).replace('\\"', '"'), type=typ.group(1) if typ else None,
                                          npc=int(npc.group(1)) if npc else 0, loot=loot))
    return inst


def load_quest_sides():
    side = {}
    for line in open(os.path.join(DATA, 'DungeonQuests.lua'), encoding='utf-8'):
        m = re.match(r'\s*\[(\d+)\] = \{ ' + LSTR + r', (-?\d+), (-?\d+), (\d), ', line)
        if m: side[int(m.group(1))] = int(m.group(5))
    qdb = set()
    for line in open(os.path.join(DATA, 'QuestDB.lua'), encoding='utf-8'):
        m = re.match(r'\s*\[(\d+)\] = \{ (-?\d+), (-?\d+), (\d+), (\d+), (\d+), (\d), ', line)
        if m: side[int(m.group(1))] = int(m.group(7)); qdb.add(int(m.group(1)))
    return side, qdb

# ---------------------------------------------------------------- item scoring
STAT_KEY = {0: 'mana', 1: 'hp', 3: 'agi', 4: 'str', 5: 'int', 6: 'spi', 7: 'sta'}
MODSTAT_KEY = {0: 'str', 1: 'agi', 2: 'sta', 3: 'int', 4: 'spi'}
SCHOOL_KEY = {2: 'holy', 4: 'fire', 8: 'nature', 16: 'frost', 32: 'shadow', 64: 'arcane'}


def spell_amount(sp, k):
    bp = int(sp[f'EffectBasePoints{k}']); dice = int(sp[f'EffectBaseDice{k}'] or 0); sides = int(sp[f'EffectDieSides{k}'] or 0)
    return bp + (max(dice, 1) if sides <= 1 else (dice + sides) / 2)


def spell_stats(sp, cls):
    """Translate an aura spell into stat points."""
    out = collections.Counter()
    for k in (1, 2, 3):
        if sp[f'Effect{k}'] not in ('6', '35'): continue
        aura = int(sp[f'EffectApplyAuraName{k}']); misc = int(sp[f'EffectMiscValue{k}']); v = spell_amount(sp, k)
        if aura == 13:  # spell damage
            if misc & 126 == 126: out['spell'] += v
            else:
                for bit, key in SCHOOL_KEY.items():
                    if misc & bit: out[key] += v
        elif aura == 135: out['heal'] += v
        elif aura == 52: out['crit'] += v
        elif aura in (57, 71): out['scrit'] += v
        elif aura == 54: out['hit'] += v
        elif aura == 55: out['shit'] += v
        elif aura == 99:
            if int(sp['Stances']) and cls != 'DRUID': continue  # "in Cat, Bear forms"
            out['ap'] += v
        elif aura == 124: out['rap'] += v
        elif aura == 85 and misc == 0: out['mp5'] += v
        elif aura == 29:
            if misc == -1:
                for key in MODSTAT_KEY.values(): out[key] += v
            elif misc in MODSTAT_KEY: out[MODSTAT_KEY[misc]] += v
        elif aura == 34: out['hp'] += v
        elif aura == 22 and misc & 1: out['armor'] += v
        elif aura == 30:
            if misc == 95: out['defense'] += v
            elif misc in (43, 44, 45, 46, 54, 55, 160, 172, 173, 176, 226, 136, 95, 162): out['wskill'] += v
    return out


class Items:
    def __init__(self, db):
        self.it = {}
        for r in table(db, 'item_template'):
            self.it[int(r['entry'])] = r
        self.spells = {int(r['Id']): r for r in table(db, 'spell_template')}

    def stats(self, iid, cls):
        r = self.it[iid]; s = collections.Counter()
        for k in range(1, 11):
            t = int(r[f'stat_type{k}']); v = int(r[f'stat_value{k}'])
            if v and t in STAT_KEY: s[STAT_KEY[t]] += v
        s['armor'] += int(r['armor']); s['block'] += int(r['block'])
        for k in range(1, 6):
            sid = int(r[f'spellid_{k}']); trig = int(r[f'spelltrigger_{k}'])
            if not sid or sid not in self.spells: continue
            if trig == 1: s.update(spell_stats(self.spells[sid], cls))
            elif trig == 0:  # on-use effect (mostly trinkets): count a quarter of it
                for key, v in spell_stats(self.spells[sid], cls).items(): s[key] += v * 0.25
            elif trig == 2:  # chance on hit
                s['proc'] += 1
        delay = int(r['delay'])
        if delay and int(r['class']) == 2:
            dmg = sum((float(r[f'dmg_min{k}']) + float(r[f'dmg_max{k}'])) / 2 for k in range(1, 6))
            s['wdps'] = dmg / (delay / 1000.0)
        return s

    def score(self, iid, cls, role=None):
        """role: 'mh', 'oh', '2h', 'ranged' for weapons; None for armor/jewelry."""
        w = W[cls]; s = self.stats(iid, cls); r = self.it[iid]
        sc = sum(w.get(k, 0) * v for k, v in s.items() if k not in ('wdps', 'proc'))
        # spell damage of the right school only counts once: all-school + the spec's school
        dps = s.get('wdps', 0)
        sub = int(r['subclass'])
        if role in ('mh', '2h'): sc += w.get('dps', 0) * dps
        elif role == 'oh': sc += w.get('ohdps', 0) * dps
        elif role == 'ranged':
            sc += (w.get('wanddps', 0) if sub == 19 else w.get('rdps', 0)) * dps
        # spec school damage counts on top of all-school damage (weights above); healing-only gear is ignored
        if s.get('proc') and cls not in CASTERS and role in ('mh', '2h', 'oh'):
            sc += 0.15 * int(r['ItemLevel']) * (0.5 if role == 'oh' else 1)
        if cls == 'ROGUE' and role in ('mh', 'oh') and sub == 7: sc *= 1.03  # Combat: Sword Specialization
        return sc

# ---------------------------------------------------------------- main build
def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--dump', default=DEFAULT_DUMP)
    ap.add_argument('--out', default=os.path.join(DATA, 'GearGuide.lua'))
    args = ap.parse_args()
    db = extract(args.dump)
    cm = json.load(open(CM_JSON))
    quests = {int(q['entry']): q for q in table(json.load(open(QUESTS_JSON)), 'quest_template')}
    items = Items(db)
    IT = items.it
    inst = load_instances()
    qside, qdb = load_quest_sides()

    ct = {int(r['Entry']): r for r in table(db, 'creature_template')}
    spawns = collections.defaultdict(list)
    for r in table(cm, 'creature'):
        spawns[int(r['id'])].append((int(r['map']), float(r['position_x']), float(r['position_y'])))
    starters = collections.defaultdict(list); enders = collections.defaultdict(set)
    for t in ('creature_questrelation', 'gameobject_questrelation'):
        for r in table(cm, t): starters[int(r['quest'])].append((t[0], int(r['id'])))
    for t in ('creature_involvedrelation', 'gameobject_involvedrelation'):
        for r in table(cm, t): enders[int(r['quest'])].add(int(r['id']))
    for iid, r in IT.items():
        if int(r['startquest']): starters[int(r['startquest'])].append(('i', iid))

    # faction template -> side, learned from race-restricted quests (same method as build_quests.py)
    votes = collections.defaultdict(collections.Counter)
    for qid, q in quests.items():
        races = int(q['RequiredRaces'])
        side = 1 if races and not races & HORDE else 2 if races and not races & ALLI else 0
        if not side: continue
        for kind, i in starters.get(qid, []):
            if kind == 'c' and i in ct: votes[int(ct[i]['Faction'])][side] += 1
        for i in enders.get(qid, ()):
            if i in ct: votes[int(ct[i]['Faction'])][side] += 1
    fside = {}
    for f, v in votes.items():
        a, h = v[1], v[2]
        if a >= 3 * max(h, 1) or (a and not h): fside[f] = 1
        elif h >= 3 * max(a, 1) or (h and not a): fside[f] = 2

    # ---- raid items (anything dropped in a raid / by a world boss) to keep raid gear and raid reagents out
    raid_items = set()
    for i in inst:
        if i['kind'] in RAID_KINDS:
            for b in i['bosses']:
                for iid, _ in b['loot']: raid_items.add(iid)
    loot = collections.defaultdict(list)
    for r in table(cm, 'creature_loot_template'): loot[int(r['entry'])].append(r)
    ref = collections.defaultdict(list)
    for r in table(cm, 'reference_loot_template'): ref[int(r['entry'])].append(r)
    def loot_items(entries, depth=0):
        out = set()
        for r in entries:
            m = int(r['mincountOrRef'])
            if m < 0 and depth < 4: out |= loot_items(ref.get(-m, []), depth + 1)
            else: out.add(int(r['item']))
        return out
    raid_npcs = {i for i, sp in spawns.items() if i and any(m in RAID_MAPS for m, _, _ in sp)}
    raid_npcs |= {b['npc'] for i in inst if i['kind'] in RAID_KINDS for b in i['bosses'] if b['npc']}
    for npc in raid_npcs:
        if npc in ct and int(ct[npc]['LootId']): raid_items |= loot_items(loot.get(int(ct[npc]['LootId']), []))
    # only items that are raid-exclusive: drop in a raid and nowhere else (cloth, ores... stay allowed)
    nonraid = set()
    for npc, c in ct.items():
        if npc in raid_npcs or not int(c['LootId']) or npc not in spawns: continue
        nonraid |= loot_items(loot.get(int(c['LootId']), []))
    for i in inst:
        if i['kind'] == 'dungeon':
            for b in i['bosses']: nonraid |= {x for x, _ in b['loot']}
    raid_items -= nonraid
    raid_items_strict = raid_items

    def item_ok(iid):
        r = IT.get(iid)
        if not r: return False
        if int(r['Quality']) < 1 or int(r['Quality']) > 4: return False
        if BAD_NAME.search(r['name']): return False
        if int(r['requiredhonorrank']) or int(r['RequiredReputationFaction']) in BG_FACTIONS: return False
        if int(r['RequiredReputationFaction']) and int(r['RequiredReputationRank']) >= 5: return False
        if int(r['RandomProperty']): return False
        if int(r['RequiredSkill']): return False
        c = int(r['class']); inv = int(r['InventoryType'])
        if c == 4 and (inv in SLOT_OF_INV or inv in (14, 23, 28)): return True
        if c == 2 and inv in (13, 17, 21, 22, 15, 25, 26): return True
        return False

    # ---- sources: item -> list of (kind, info, minlevel, side(0/1/2), extra)
    sources = collections.defaultdict(list)
    stats = collections.Counter()

    def raid_quest(q):
        if int(q['ZoneOrSort']) in BG_ZONES | RAID_ZONES: return True
        if int(q['RequiredMinRepFaction']) in RAID_REP: return True
        reqs = [int(q[f'ReqItemId{k}']) for k in range(1, 5)] + [int(q[f'ReqSourceId{k}']) for k in range(1, 5)]
        if any(x in raid_items for x in reqs if x): return True
        return any(int(q[f'ReqCreatureOrGOId{k}']) in raid_npcs for k in range(1, 5))
    chain_memo = {}
    def raid_chain(qid, depth=0):
        # a quest is raid content when it or any quest before it needs raid kills / raid drops
        if qid in chain_memo: return chain_memo[qid]
        q = quests.get(qid)
        res = False
        if q and depth < 30:
            res = raid_quest(q)
            if not res and int(q['PrevQuestId']): res = raid_chain(abs(int(q['PrevQuestId'])), depth + 1)
            if not res:  # quests whose NextQuestId points here are prerequisites too
                res = any(raid_chain(p, depth + 1) for p in prev_of.get(qid, ()))
        chain_memo[qid] = res
        return res
    prev_of = collections.defaultdict(set)
    for qid, q in quests.items():
        if int(q['NextQuestId']) > 0: prev_of[int(q['NextQuestId'])].add(qid)

    # quests
    for qid, q in quests.items():
        if qid not in starters or qid not in enders: continue
        if int(q['RequiredSkill']) or int(q['SpecialFlags']) & 1: continue
        if int(q['RequiredMinRepFaction']) in BG_FACTIONS: continue
        if int(q['RequiredMinRepFaction']) and int(q['RequiredMinRepValue']) >= 9000: continue
        if raid_chain(qid): stats['raid_quest'] += 1; continue
        if 'Title' in q and BAD_NAME.search(q['Title'] or ''): continue
        races = int(q['RequiredRaces']); classes = int(q['RequiredClasses'])
        if qid in qside: side = qside[qid]
        elif races and not races & HORDE: side = 1
        elif races and not races & ALLI: side = 2
        else:
            side = 0
            for kind, i in starters[qid]:
                if kind == 'c' and i in ct and int(ct[i]['Faction']) in fside: side = fside[int(ct[i]['Faction'])]; break
        choice = [int(q[f'RewChoiceItemId{k}']) for k in range(1, 7) if int(q[f'RewChoiceItemId{k}'])]
        fixed = [int(q[f'RewItemId{k}']) for k in range(1, 5) if int(q[f'RewItemId{k}'])]
        lvl = max(int(q['MinLevel']), int(q['QuestLevel']) - 2)
        for iid in choice + fixed:
            if item_ok(iid):
                sources[iid].append(dict(kind='quest', id=qid, lvl=lvl, side=side, races=races, classes=classes,
                                         choice=qid if iid in choice and len(choice) > 1 else None,
                                         indb=qid in qdb, rank=0))
                stats['quest_src'] += 1

    # dungeon boss drops
    for order, i in enumerate(inst):
        if i['kind'] != 'dungeon': continue
        for b in i['bosses']:
            if b['type'] == 'extra': continue
            for iid, rate in b['loot']:
                if 0 <= rate < 3: continue
                if item_ok(iid):
                    sources[iid].append(dict(kind='drop', inst=i['key'], boss=b['name'], rate=rate, lvl=i['min'],
                                             side=0, races=0, classes=0, rank=1))
                    stats['drop_src'] += 1

    # vendors
    vt = collections.defaultdict(list)
    for r in table(db, 'npc_vendor_template'): vt[int(r['entry'])].append(int(r['item']))
    sells = collections.defaultdict(set)
    for r in table(db, 'npc_vendor'): sells[int(r['entry'])].add(int(r['item']))
    for e, c in ct.items():
        if int(c['VendorTemplateId']): sells[e] |= set(vt.get(int(c['VendorTemplateId']), []))
    grid = collections.defaultdict(list)
    for npc, sp in spawns.items():
        if npc in ct and int(ct[npc]['Faction']) in fside:
            for m, x, y in sp:
                if m in (0, 1): grid[(m, int(x // 100), int(y // 100))].append((x, y, fside[int(ct[npc]['Faction'])]))
    def neighbour_side(pos):
        # side of an NPC whose faction template is unknown: the sides of known NPCs within 120 yards
        m, x, y = pos; v = collections.Counter()
        for gx in range(int(x // 100) - 2, int(x // 100) + 3):
            for gy in range(int(y // 100) - 2, int(y // 100) + 3):
                for px, py, sd in grid.get((m, gx, gy), ()):
                    if (px - x) ** 2 + (py - y) ** 2 < 120 ** 2: v[sd] += 1
        if not v: return 0
        sd, n = v.most_common(1)[0]
        return sd if n >= 0.8 * sum(v.values()) else 0
    def pvp_item(iid):
        r = IT.get(iid)
        return bool(r) and (int(r['requiredhonorrank']) > 0 or int(r['RequiredReputationFaction']) in BG_FACTIONS)
    for npc, its in sells.items():
        sp = [s for s in spawns.get(npc, []) if s[0] in (0, 1)]
        if not sp or npc not in ct: continue
        if any(pvp_item(i) for i in its): continue  # PvP quartermaster
        side = fside.get(int(ct[npc]['Faction']), 0) or neighbour_side(sp[0])
        for iid in its:
            if item_ok(iid) and iid not in raid_items and int(IT[iid]['Quality']) <= 2:
                lvl = max(int(IT[iid]['RequiredLevel']), int(IT[iid]['ItemLevel']) - 10)
                sources[iid].append(dict(kind='vendor', npc=ct[npc]['Name'], pos=sp[0], lvl=lvl, side=side,
                                         races=0, classes=0, rank=2))
                stats['vendor_src'] += 1

    # crafted (spell "create item" learnt from a trainer or a recipe)
    learnt = {}
    for t in ('npc_trainer', 'npc_trainer_template'):
        for r in table(db, t):
            if int(r['reqskill']) in PROF: learnt[int(r['spell'])] = int(r['reqskill'])
    for iid, r in IT.items():
        if r['class'] == '9' and int(r['RequiredSkill']) in PROF and iid not in raid_items:
            for k in range(1, 6):
                sid = int(r[f'spellid_{k}'])
                if sid and sid != 483: learnt.setdefault(sid, int(r['RequiredSkill']))
    for sid, skill in learnt.items():
        sp = items.spells.get(sid)
        if not sp: continue
        # trainer spells can be "learn" wrappers (effect 36) around the craft spell
        if sp['Effect1'] == '36' and int(sp['EffectTriggerSpell1']) in items.spells:
            sp = items.spells[int(sp['EffectTriggerSpell1'])]
        if sp['Effect1'] != '24': continue
        iid = int(sp['EffectItemType1'])
        reag = [int(sp[f'Reagent{k}']) for k in range(1, 9) if int(sp[f'Reagent{k}'] or 0) > 0]
        if any(x in raid_items for x in reag): continue
        if item_ok(iid) and int(IT[iid]['bonding']) == 2:
            # no-level crafted items (e.g. engineering boots) still need the crafter's skill: item level - 10
            sources[iid].append(dict(kind='crafted', prof=PROF[skill],
                                     lvl=max(int(IT[iid]['RequiredLevel']), int(IT[iid]['ItemLevel']) - 10),
                                     side=0, races=0, classes=0, rank=3))
            stats['crafted_src'] += 1

    print(dict(stats), "items with sources:", len(sources), "raid-only items:", len(raid_items), "raid npcs:", len(raid_npcs), file=sys.stderr)

    # ---------------------------------------------------------------- selection
    def races_ok(mask, cls, faction):
        if not mask or mask & 255 == 255 or mask == -1: return True
        need = 0
        for bit, cl in RACE_CLASS.items():
            if bit & FACTION_MASK[faction] and cls in cl.split(): need |= bit
        return mask & need == need

    def src_ok(s, cls, faction, L):
        if s['lvl'] > L: return False
        if s['side'] and s['side'] != faction: return False
        if s['races'] and not races_ok(s['races'], cls, faction): return False
        if s['classes'] and not s['classes'] & CLASS_BIT[cls]: return False
        return True

    def usable(iid, cls, faction, L):
        r = IT[iid]
        if int(r['RequiredLevel']) > L: return False
        ac = int(r['AllowableClass'])
        if ac not in (-1, 0) and (ac & 1535) != 1535 and not ac & CLASS_BIT[cls]: return False
        ar = int(r['AllowableRace'])
        if ar not in (-1, 0) and not races_ok(ar, cls, faction): return False
        c = int(r['class']); sub = int(r['subclass']); inv = int(r['InventoryType'])
        if c == 4:
            if inv == 14: return cls in SHIELD and sub == 6
            if inv == 28: return RELIC.get(cls) == sub
            if inv == 23: return True
            if sub in (1, 2, 3, 4): return sub <= max_armor(cls, L)
            return sub == 0
        if c == 2:
            if sub not in WEAPONS[cls]: return False
            if cls == 'SHAMAN' and sub in (1, 5) and L < 20: return False
            if cls == 'HUNTER' and sub == 16: return False  # hunter shots need a bow, gun or crossbow
            return True
        return False

    def roles(iid, cls, L):
        r = IT[iid]; c = int(r['class']); inv = int(r['InventoryType']); sub = int(r['subclass'])
        if c == 4:
            if inv in SLOT_OF_INV: return [SLOT_OF_INV[inv]]
            if inv == 14: return ['shield']
            if inv == 23: return ['holdable']
            if inv == 28: return ['ranged']
        if c == 2:
            if inv == 17: return ['2h']
            if inv in (15, 25, 26) or sub in RANGED_SUB: return ['ranged']
            if inv == 21: return ['mh']
            if inv == 22: return ['oh'] if can_dual(cls, L) else []
            if inv == 13: return ['mh', 'oh'] if can_dual(cls, L) else ['mh']
        return []

    FACTORS = dict(quest=1.0, drop=1.0, vendor=0.97, crafted=0.9)

    def best_source(iid, cls, faction, L):
        ok = [s for s in sources[iid] if src_ok(s, cls, faction, L)]
        if not ok: return None
        # guaranteed quest first, then easiest dungeon (lowest min level, best rate), vendor, crafted
        ok.sort(key=lambda s: (s['rank'], s['lvl'], -(s.get('rate') or 100), not s.get('indb', True)))
        return ok[0]

    guide = {}; used_src = {}; per_faction_src = collections.defaultdict(dict)
    for cls in W:
        guide[cls] = {}
        for faction in (1, 2):
            guide[cls][faction] = {}
            taken_choice = {}  # quest -> item already chosen from its choice rewards
            for L in BRACKETS:
                cand = collections.defaultdict(list)  # role -> [(score, iid, src)]
                for iid in sources:
                    if not usable(iid, cls, faction, L): continue
                    src = best_source(iid, cls, faction, L)
                    if not src: continue
                    if src.get('choice') and taken_choice.get(src['choice'], iid) != iid:
                        # another reward of this quest was already taken; look for another source
                        alt = [s for s in sources[iid] if src_ok(s, cls, faction, L) and s.get('choice') != src['choice']]
                        if not alt: continue
                        src = sorted(alt, key=lambda s: (s['rank'], s['lvl']))[0]
                    f = FACTORS[src['kind']] if L < 60 or src['kind'] == 'vendor' else 1.0
                    for role in roles(iid, cls, L):
                        sc = items.score(iid, cls, role if role in ('mh', 'oh', '2h', 'ranged') else None) * f
                        if sc > 0: cand[role].append((sc, iid, src))
                for v in cand.values(): v.sort(key=lambda x: (-x[0], x[2]['rank'], x[2]['lvl']))
                pick = choose(cand, cls, L, IT)
                # one choice reward per quest
                pick = fix_choices(pick, cand, cls, L, IT, taken_choice)
                for slot, (sc, iid, src) in pick.items():
                    if src.get('choice'): taken_choice[src['choice']] = iid
                    per_faction_src[iid][faction] = src
                    used_src.setdefault(iid, {})
                    key = (src['kind'], src.get('id') or src.get('inst') or src.get('npc') or src.get('prof'), src.get('boss'), src['side'])
                    used_src[iid].setdefault(key, src)
                guide[cls][faction][L] = {slot: iid for slot, (sc, iid, src) in pick.items()}
    write_lua(args.out, guide, used_src, IT, inst)


def choose(cand, cls, L, IT):
    pick = {}
    def take(role, n=1, exclude=()):
        out = []; seen = set(exclude)
        for sc, iid, src in cand.get(role, []):
            if iid in seen: continue
            out.append((sc, iid, src)); seen.add(iid)
            if len(out) == n: break
        return out
    for slot in ('head', 'neck', 'shoulder', 'back', 'chest', 'wrist', 'hands', 'waist', 'legs', 'feet'):
        t = take(slot)
        if t: pick[slot] = t[0]
    for base in ('finger', 'trinket'):
        t = take(base, 2)
        for k, x in enumerate(t): pick[f'{base}{k + 1}'] = x
    r = take('ranged')
    if r: pick['ranged'] = r[0]
    # weapons: compare configurations
    best = None
    for conf in CONFIGS[cls]:
        if conf == 'dual' and not can_dual(cls, L): continue
        if conf == '2h':
            t = take('2h')
            if not t: continue
            combo = {'mainhand': t[0]}
        else:
            m = take('mh')
            if not m: continue
            combo = {'mainhand': m[0]}
            if conf == 'shield': o = take('shield')
            elif conf == 'holdable': o = take('holdable')
            else:
                o = take('oh', exclude=(m[0][1],))  # never the same item in both hands
            if o: combo['offhand'] = o[0]
        total = sum(x[0] for x in combo.values())
        if best is None or total > best[0]: best = (total, combo)
    if best: pick.update(best[1])
    return pick


def fix_choices(pick, cand, cls, L, IT, taken):
    """Keep at most one item per quest choice list; the other slot falls back to its next candidate."""
    for _ in range(10):
        byq = collections.defaultdict(list)
        for slot, (sc, iid, src) in pick.items():
            if src.get('choice'): byq[src['choice']].append(slot)
        clash = [(q, sl) for q, sl in byq.items() if len({pick[s][1] for s in sl}) > 1]
        if not clash: return pick
        q, sl = clash[0]
        # keep the slot with the biggest margin over its alternative
        def alt(slot):
            role = {'finger1': 'finger', 'finger2': 'finger', 'trinket1': 'trinket', 'trinket2': 'trinket'}.get(slot, slot)
            if slot == 'mainhand': role = '2h' if int(IT[pick[slot][1]]['InventoryType']) == 17 else 'mh'
            if slot == 'offhand':
                inv = int(IT[pick[slot][1]]['InventoryType'])
                role = 'shield' if inv == 14 else 'holdable' if inv == 23 else 'oh'
            others = {pick[s][1] for s in pick if s != slot}
            for x in cand.get(role, []):
                if x[2].get('choice') != q and x[1] not in others: return x
            return None
        margins = []
        for s in sl:
            a = alt(s); margins.append((pick[s][0] - (a[0] if a else 0), s, a))
        margins.sort(reverse=True)
        for _, s, a in margins[1:]:
            if a: pick[s] = a
            else: del pick[s]
    return pick


def lua_str(s): return '"' + s.replace('\\', '\\\\').replace('"', '\\"') + '"'


def write_lua(path, guide, used_src, IT, inst):
    L = ["-- ForeverCompanion: leveling best-in-slot gear per class, faction and level bracket (generated by",
         "-- tools/build_gear.py, do not edit by hand).  Source: CMaNGOS classic-db + Data/InstanceDB.lua.",
         "-- Specs and stat weights (points per stat; crit/hit per 1 %; dps = weapon DPS):"]
    for cls, w in W.items():
        L.append(f"--   {cls} ({SPEC[cls]}): " + ", ".join(f"{k} {v:g}" for k, v in w.items() if v))
    L += ["-- Bracket L: RequiredLevel <= L and obtainable by L (quest MinLevel <= L, dungeon min level <= L).",
          "-- No world random drops, raid or PvP items.  Two-hand weapon: mainhand only, offhand empty.",
          "-- ns.GearGuide[CLASS][faction 1 Alliance / 2 Horde][bracket] = { slot = itemID, ... }",
          "local _, ns = ...", "", "ns.GearGuide = {"]
    for cls in guide:
        L.append(f"\t{cls} = {{")
        for fac in (1, 2):
            L.append(f"\t\t[{fac}] = {{ -- {'Alliance' if fac == 1 else 'Horde'}")
            for br in BRACKETS:
                g = guide[cls][fac].get(br, {})
                body = ", ".join(f"{s} = {g[s]}" for s in SLOTS if s in g)
                L.append(f"\t\t\t[{br}] = {{ {body} }},")
            L.append("\t\t},")
        L.append("\t},")
    L.append("}")
    L += ["", "-- Where each item comes from:",
          '--   { "quest", questID }  { "drop", instanceKey, boss, rate% (-1 unknown) }',
          '--   { "vendor", npc, continent (0 Eastern Kingdoms, 1 Kalimdor), worldX, worldY }  { "crafted", profession }',
          "-- When Alliance and Horde get the item from different quests, the Horde one is in field h.",
          "ns.GearSources = {"]
    def fmt(s):
        if s['kind'] == 'quest': return f'"quest", {s["id"]}'
        if s['kind'] == 'drop': return f'"drop", {lua_str(s["inst"])}, {lua_str(s["boss"])}, {s["rate"]:g}'
        if s['kind'] == 'vendor':
            m, x, y = s['pos']; return f'"vendor", {lua_str(s["npc"])}, {m}, {round(x)}, {round(y)}'
        return f'"crafted", {lua_str(s["prof"])}'
    for iid in sorted(used_src):
        srcs = list(used_src[iid].values())
        srcs.sort(key=lambda s: (s['rank'], s['side'] == 2, s['lvl']))
        main = srcs[0]
        line = f"\t[{iid}] = {{ {fmt(main)}"
        if main['side'] == 1:
            h = [s for s in srcs if s['side'] in (0, 2)]
            if h: line += f", h = {{ {fmt(h[0])} }}"
        line += f" }}, -- {IT[iid]['name']}"
        L.append(line)
    L.append("}")
    open(path, 'w').write("\n".join(L) + "\n")
    print('wrote', path, os.path.getsize(path), 'bytes', file=sys.stderr)


if __name__ == '__main__':
    main()
