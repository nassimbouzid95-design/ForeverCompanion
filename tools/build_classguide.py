#!/usr/bin/env python3
# Build Data/ClassGuide.lua from the CMaNGOS classic DB dump.
# usage: build_classguide.py <dump.sql.gz> <out ClassGuide.lua> [cache dir]
import gzip, json, os, re, sys

DUMP = sys.argv[1] if len(sys.argv) > 1 else "/home/claude/cmangos/classic-db/Full_DB/ClassicDB_1_12_1_z2815.sql.gz"
OUT = sys.argv[2] if len(sys.argv) > 2 else os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "ForeverCompanion", "Data", "ClassGuide.lua"))
CACHE = sys.argv[3] if len(sys.argv) > 3 else "/tmp/claude-0/classguide"

WANT = {
    "npc_trainer": ["entry", "spell", "spellcost", "reqskill", "reqlevel"],
    "npc_trainer_template": ["entry", "spell", "spellcost", "reqskill", "reqlevel"],
    "creature_template": ["Entry", "Name", "SubName", "TrainerType", "TrainerClass", "TrainerTemplateId", "NpcFlags"],
    "spell_template": ["Id", "SpellName", "Rank1", "SpellLevel", "BaseLevel", "Effect1", "Effect2", "Effect3",
                       "EffectTriggerSpell1", "EffectTriggerSpell2", "EffectTriggerSpell3", "SpellFamilyName", "Attributes"],
    "spell_chain": ["spell_id", "prev_spell", "first_spell", "rank"],
    "playercreateinfo_spell": ["race", "class", "Spell"],
    "quest_template": ["entry", "Title", "RequiredClasses", "MinLevel", "RewSpell", "RewSpellCast"],
}

# ---------------------------------------------------------------- SQL parsing
def parse_values(s, i):
    n = len(s); out = []
    while i < n:
        while i < n and s[i] in " ,\n\r\t": i += 1
        if i >= n or s[i] == ';': break
        assert s[i] == '(', s[i:i + 50]
        i += 1; vals = []; cur = []; inq = False
        while True:
            c = s[i]
            if inq:
                if c == '\\': cur.append(s[i + 1]); i += 2; continue
                if c == "'":
                    if i + 1 < n and s[i + 1] == "'": cur.append("'"); i += 2; continue
                    inq = False; i += 1; continue
                cur.append(c); i += 1; continue
            if c == "'": inq = True; i += 1; continue
            if c == ',': vals.append(''.join(cur)); cur = []; i += 1; continue
            if c == ')': vals.append(''.join(cur)); i += 1; break
            cur.append(c); i += 1
        out.append(vals)
    return out

def load_db():
    cache = os.path.join(CACHE, "db.json")
    if os.path.exists(cache):
        return json.load(open(cache))
    text = gzip.open(DUMP, 'rt', encoding='utf-8', errors='replace').read()
    cols, rows = {}, {k: [] for k in WANT}
    for m in re.finditer(r"CREATE TABLE `(\w+)` \((.*?)\n\)", text, re.S):
        if m.group(1) in WANT:
            cols[m.group(1)] = re.findall(r"^\s*`(\w+)`", m.group(2), re.M)
    for m in re.finditer(r"INSERT INTO `(\w+)` VALUES\s*", text):
        if m.group(1) in WANT:
            rows[m.group(1)].extend(parse_values(text, m.end()))
    res = {}
    for t, keep in WANT.items():
        idx = [cols[t].index(k) for k in keep]
        res[t] = [dict(zip(keep, [r[j] for j in idx])) for r in rows[t]]
    os.makedirs(CACHE, exist_ok=True)
    json.dump(res, open(cache, "w"))
    return res

db = load_db()

# ------------------------------------------------------------------ helpers
SPELL = {int(r["Id"]): r for r in db["spell_template"]}
CLASSES = ["WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID"]
CLASS_ID = {"WARRIOR": 1, "PALADIN": 2, "HUNTER": 3, "ROGUE": 4, "PRIEST": 5, "SHAMAN": 7, "MAGE": 8, "WARLOCK": 9, "DRUID": 11}
CLASS_FAMILY = {"WARRIOR": 4, "PALADIN": 10, "HUNTER": 9, "ROGUE": 8, "PRIEST": 6, "SHAMAN": 11, "MAGE": 3, "WARLOCK": 5, "DRUID": 7}
EFFECT_LEARN_SPELL = 36

def name(sid): return SPELL[sid]["SpellName"]

def rank_of(sid):
    m = re.match(r"Rank (\d+)", SPELL[sid]["Rank1"])
    return int(m.group(1)) if m else 1

def learned(sid):
    """Trainer/quest 'teach' spell -> the spell the player ends up with."""
    s = SPELL.get(sid)
    if s and s["Effect1"] == str(EFFECT_LEARN_SPELL) and int(s["EffectTriggerSpell1"]):
        return int(s["EffectTriggerSpell1"])
    return sid

# Trainer entries that are not real class abilities.
SPELL_BLACKLIST_NAMES = re.compile(r"^zzOLD|^Elemental Fury$|^Beast Training$|^Teleport to Azshara Tower$")

# Spells granted automatically with a quest-learned spell (from SkillLineAbility.dbc,
# which is not part of the world DB): {quest spell learned: [(spellID, level)]}.
AUTO_LEARN = {
    71:   [355, 7386],          # Defensive Stance quest -> Taunt, Sunder Armor (Rank 1)
    2458: [20252],              # Berserker Stance quest -> Intercept (Rank 1)
    1515: [883, 2641, 982, 6991],  # Tame Beast quest -> Call Pet, Dismiss Pet, Revive Pet, Feed Pet
    5487: [6795, 6807],         # Bear Form quest -> Growl, Maul (Rank 1)
}

def build_spells(cls):
    cid = str(CLASS_ID[cls])
    out = {}  # learned spellID -> (level, rank, cost)
    def add(sid, lvl, cost):
        if sid not in SPELL or SPELL_BLACKLIST_NAMES.search(name(sid)):
            return
        old = out.get(sid)
        if old is None or (lvl, cost) < (old[0], old[2]):
            out[sid] = (lvl, rank_of(sid), cost)
    # 1) class trainers (TrainerType 0) of this class: their template + own list
    tmpl = {}
    for r in db["npc_trainer_template"]:
        tmpl.setdefault(r["entry"], []).append(r)
    own = {}
    for r in db["npc_trainer"]:
        own.setdefault(r["entry"], []).append(r)
    for c in db["creature_template"]:
        if c["TrainerType"] != "0" or c["TrainerClass"] != cid:
            continue
        for r in tmpl.get(c["TrainerTemplateId"], []) + own.get(c["Entry"], []):
            sid = learned(int(r["spell"]))
            lvl = int(r["reqlevel"]) or int(SPELL.get(sid, {}).get("SpellLevel", 0) or 1)  # a few rows have reqlevel 0
            add(sid, lvl, int(r["spellcost"]))
    trained_names = {name(s) for s in out}
    # 2) starting spells: class abilities only (no racials, weapon/armor/language skills)
    for r in db["playercreateinfo_spell"]:
        if r["class"] != cid:
            continue
        sid = int(r["Spell"]); s = SPELL.get(sid)
        if not s or "Racial" in s["Rank1"] or sid == 2764:  # Throw
            continue
        if int(s["SpellFamilyName"]) == CLASS_FAMILY[cls] or s["SpellName"] in trained_names or sid in (2457, 75) \
                or (sid == 5019 and cls in ("PRIEST", "MAGE", "WARLOCK")):  # Battle Stance, Auto Shot, Shoot (wand)
            add(sid, 1, 0)
    # 3) class quests that teach a spell (learn effect only, not buffs cast on the player)
    for q in db["quest_template"]:
        if not int(q["RequiredClasses"]) & (1 << (int(cid) - 1)):
            continue
        for col in ("RewSpellCast", "RewSpell"):
            t = int(q[col])
            if t and t in SPELL and SPELL[t]["Effect1"] == str(EFFECT_LEARN_SPELL):
                sid = learned(t)
                lvl = max(1, int(q["MinLevel"]))
                add(sid, lvl, 0)
                for extra in AUTO_LEARN.get(sid, []):
                    add(extra, lvl, 0)
    return sorted(([lvl, sid, rk, cost] for sid, (lvl, rk, cost) in out.items()), key=lambda x: (x[0], name(x[1]), x[2], x[1]))

# ------------------------------------------------------------------ talents
# Per class: tree names (game order), the talents used:
#   name: (tree 1-3, tier 1-7, max rank, prerequisite talent or None, rank-1 spellID hint or None)
# and the build as an ordered list of (talent, points); expanded to one point per level 10..60.
# The hint only disambiguates talents whose name exists several times in spell_template
# (same talent name in several classes); it is checked against the name.
T = {}
T["WARRIOR"] = dict(spec="Arms", trees=["Arms", "Fury", "Protection"], talents={
    "Improved Heroic Strike": (1, 1, 3, None, None),
    "Deflection": (1, 1, 5, None, 16462),
    "Improved Rend": (1, 1, 3, None, None),
    "Tactical Mastery": (1, 2, 5, None, None),
    "Anger Management": (1, 3, 1, None, None),
    "Deep Wounds": (1, 3, 3, "Improved Rend", 12834),
    "Two-Handed Weapon Specialization": (1, 4, 5, None, None),
    "Impale": (1, 4, 2, "Deep Wounds", None),
    "Sweeping Strikes": (1, 5, 1, None, 12292),
    "Sword Specialization": (1, 5, 5, None, 12281),
    "Mortal Strike": (1, 7, 1, "Sweeping Strikes", 12294),
    "Cruelty": (2, 1, 5, None, None),
    "Unbridled Wrath": (2, 2, 5, None, None),
    "Piercing Howl": (2, 3, 1, None, 12323),
    "Blood Craze": (2, 3, 3, None, None),
    "Improved Battle Shout": (2, 3, 5, None, None),
    "Enrage": (2, 4, 5, None, 12317),
}, build=[("Improved Heroic Strike", 3), ("Deflection", 2), ("Improved Rend", 3), ("Tactical Mastery", 2),
          ("Deep Wounds", 3), ("Anger Management", 1), ("Tactical Mastery", 1), ("Two-Handed Weapon Specialization", 5),
          ("Sweeping Strikes", 1), ("Impale", 2), ("Tactical Mastery", 2), ("Sword Specialization", 5), ("Mortal Strike", 1),
          ("Cruelty", 5), ("Unbridled Wrath", 5), ("Piercing Howl", 1), ("Blood Craze", 3), ("Improved Battle Shout", 1),
          ("Enrage", 5)])

T["PALADIN"] = dict(spec="Retribution", trees=["Holy", "Protection", "Retribution"], talents={
    "Divine Strength": (1, 1, 5, None, None),
    "Divine Intellect": (1, 1, 5, None, None),
    "Improved Seal of Righteousness": (1, 2, 5, None, None),
    "Consecration": (1, 3, 1, None, None),
    "Healing Light": (1, 3, 3, None, None),
    "Unyielding Faith": (1, 3, 2, None, None),
    "Benediction": (3, 1, 5, None, None),
    "Improved Judgement": (3, 2, 2, None, None),
    "Deflection": (3, 2, 5, None, 20060),
    "Vindication": (3, 3, 3, None, None),
    "Conviction": (3, 3, 5, None, None),
    "Seal of Command": (3, 4, 1, None, 20375),
    "Pursuit of Justice": (3, 4, 2, None, None),
    "Eye for an Eye": (3, 5, 2, None, None),
    "Vengeance": (3, 6, 5, "Conviction", 20049),
    "Repentance": (3, 7, 1, None, None),
}, build=[("Benediction", 5), ("Deflection", 5), ("Conviction", 5), ("Seal of Command", 1), ("Pursuit of Justice", 2),
          ("Vindication", 3), ("Improved Judgement", 2), ("Eye for an Eye", 2), ("Vengeance", 5), ("Repentance", 1),
          ("Divine Strength", 5), ("Divine Intellect", 5), ("Improved Seal of Righteousness", 5), ("Consecration", 1),
          ("Healing Light", 3), ("Unyielding Faith", 1)])

T["HUNTER"] = dict(spec="Beast Mastery", trees=["Beast Mastery", "Marksmanship", "Survival"], talents={
    "Improved Aspect of the Hawk": (1, 1, 5, None, None),
    "Thick Hide": (1, 2, 3, None, 19609),
    "Improved Aspect of the Monkey": (1, 2, 5, None, None),
    "Unleashed Fury": (1, 3, 5, None, None),
    "Ferocity": (1, 4, 5, None, 19598),
    "Intimidation": (1, 5, 1, None, 19577),
    "Bestial Discipline": (1, 5, 2, None, None),
    "Spirit Bond": (1, 5, 2, None, None),
    "Frenzy": (1, 6, 5, "Ferocity", None),
    "Bestial Wrath": (1, 7, 1, "Intimidation", 19574),
    "Efficiency": (2, 1, 5, None, None),
    "Lethal Shots": (2, 2, 5, None, None),
    "Aimed Shot": (2, 3, 1, None, 19434),
    "Hawk Eye": (2, 3, 3, None, None),
    "Improved Arcane Shot": (2, 3, 5, None, None),
    "Mortal Shots": (2, 4, 5, None, None),
}, build=[("Improved Aspect of the Hawk", 5), ("Thick Hide", 3), ("Improved Aspect of the Monkey", 2), ("Unleashed Fury", 5),
          ("Ferocity", 5), ("Intimidation", 1), ("Bestial Discipline", 2), ("Spirit Bond", 2), ("Frenzy", 5), ("Bestial Wrath", 1),
          ("Efficiency", 5), ("Lethal Shots", 5), ("Aimed Shot", 1), ("Hawk Eye", 3), ("Improved Arcane Shot", 1), ("Mortal Shots", 5)])

T["ROGUE"] = dict(spec="Combat", trees=["Assassination", "Combat", "Subtlety"], talents={
    "Improved Sinister Strike": (2, 1, 2, None, None),
    "Lightning Reflexes": (2, 1, 5, None, 13712),
    "Precision": (2, 2, 5, None, 13705),
    "Deflection": (2, 2, 5, None, 13713),
    "Dual Wield Specialization": (2, 4, 5, "Precision", 13715),
    "Blade Flurry": (2, 5, 1, None, 13877),
    "Sword Specialization": (2, 5, 5, None, 13960),
    "Weapon Expertise": (2, 6, 2, "Blade Flurry", None),
    "Aggression": (2, 6, 3, None, None),
    "Adrenaline Rush": (2, 7, 1, None, 13750),
    "Malice": (1, 1, 5, None, None),
    "Improved Eviscerate": (1, 1, 3, None, None),
    "Remorseless Attacks": (1, 1, 2, None, None),
    "Ruthlessness": (1, 2, 3, None, None),
    "Murder": (1, 2, 2, None, None),
    "Relentless Strikes": (1, 3, 1, None, None),
    "Lethality": (1, 3, 5, "Malice", None),
}, build=[("Improved Sinister Strike", 2), ("Lightning Reflexes", 3), ("Precision", 5), ("Lightning Reflexes", 2), ("Deflection", 3),
          ("Dual Wield Specialization", 5), ("Blade Flurry", 1), ("Sword Specialization", 5), ("Weapon Expertise", 2),
          ("Aggression", 2), ("Adrenaline Rush", 1),
          ("Malice", 5), ("Ruthlessness", 3), ("Murder", 2), ("Relentless Strikes", 1), ("Lethality", 5),
          ("Improved Eviscerate", 3), ("Remorseless Attacks", 1)])

T["PRIEST"] = dict(spec="Shadow", trees=["Discipline", "Holy", "Shadow"], talents={
    "Spirit Tap": (3, 1, 5, None, None),
    "Blackout": (3, 1, 5, None, None),
    "Improved Shadow Word: Pain": (3, 2, 2, None, None),
    "Shadow Focus": (3, 2, 5, None, None),
    "Improved Mind Blast": (3, 3, 5, None, None),
    "Mind Flay": (3, 3, 1, None, 15407),
    "Shadow Reach": (3, 4, 3, None, None),
    "Vampiric Embrace": (3, 5, 1, None, 15286),
    "Improved Vampiric Embrace": (3, 5, 2, "Vampiric Embrace", None),
    "Darkness": (3, 6, 5, None, None),
    "Shadowform": (3, 7, 1, "Vampiric Embrace", 15473),
    "Unbreakable Will": (1, 1, 5, None, None),
    "Wand Specialization": (1, 1, 5, None, 14524),
    "Improved Power Word: Shield": (1, 2, 3, None, None),
    "Improved Power Word: Fortitude": (1, 2, 2, None, None),
    "Inner Focus": (1, 3, 1, None, 14751),
    "Meditation": (1, 3, 3, None, 14521),
    "Mental Agility": (1, 4, 5, None, None),
}, build=[("Spirit Tap", 5), ("Improved Shadow Word: Pain", 2), ("Shadow Focus", 3), ("Mind Flay", 1), ("Improved Mind Blast", 5),
          ("Shadow Focus", 2), ("Blackout", 2), ("Vampiric Embrace", 1), ("Improved Vampiric Embrace", 2), ("Shadow Reach", 2),
          ("Darkness", 5), ("Shadowform", 1),
          ("Wand Specialization", 5), ("Improved Power Word: Shield", 3), ("Improved Power Word: Fortitude", 2),
          ("Inner Focus", 1), ("Meditation", 3), ("Unbreakable Will", 1), ("Mental Agility", 5)])

T["SHAMAN"] = dict(spec="Enhancement", trees=["Elemental", "Enhancement", "Restoration"], talents={
    "Ancestral Knowledge": (2, 1, 5, None, None),
    "Thundering Strikes": (2, 2, 5, None, None),
    "Improved Ghost Wolf": (2, 2, 2, None, None),
    "Two-Handed Axes and Maces": (2, 3, 1, None, [16269]),
    "Enhancing Totems": (2, 3, 2, None, None),
    "Flurry": (2, 4, 5, "Thundering Strikes", 16256),
    "Parry": (2, 5, 1, None, 16268),
    "Elemental Weapons": (2, 5, 3, None, None),
    "Improved Weapon Totems": (2, 5, 2, None, None),
    "Weapon Mastery": (2, 6, 5, None, None),
    "Stormstrike": (2, 7, 1, None, 17364),
    "Tidal Focus": (3, 1, 5, None, None),
    "Totemic Focus": (3, 2, 5, None, None),
    "Ancestral Healing": (3, 2, 3, None, None),
    "Nature's Guidance": (3, 3, 3, None, None),
    "Tidal Mastery": (3, 4, 5, None, None),
}, build=[("Ancestral Knowledge", 5), ("Thundering Strikes", 5), ("Two-Handed Axes and Maces", 1), ("Improved Ghost Wolf", 2),
          ("Enhancing Totems", 2), ("Flurry", 5), ("Parry", 1), ("Elemental Weapons", 3), ("Improved Weapon Totems", 1),
          ("Weapon Mastery", 5), ("Stormstrike", 1),
          ("Tidal Focus", 5), ("Totemic Focus", 5), ("Nature's Guidance", 3), ("Ancestral Healing", 2), ("Tidal Mastery", 5)])

T["MAGE"] = dict(spec="Frost", trees=["Arcane", "Fire", "Frost"], talents={
    "Improved Frostbolt": (3, 1, 5, None, None),
    "Ice Shards": (3, 2, 5, None, 11207),
    "Improved Frost Nova": (3, 2, 2, None, None),
    "Piercing Ice": (3, 3, 3, None, None),
    "Cold Snap": (3, 3, 1, None, None),
    "Improved Blizzard": (3, 3, 3, None, None),
    "Arctic Reach": (3, 4, 2, None, None),
    "Frost Channeling": (3, 4, 3, None, None),
    "Shatter": (3, 4, 5, "Improved Frost Nova", None),
    "Ice Block": (3, 5, 1, None, 11958),
    "Ice Barrier": (3, 7, 1, "Ice Block", 11426),
    "Arcane Subtlety": (1, 1, 2, None, None),
    "Arcane Focus": (1, 1, 5, None, None),
    "Arcane Concentration": (1, 2, 5, None, None),
    "Magic Absorption": (1, 2, 5, None, None),
    "Wand Specialization": (1, 2, 2, None, 6057),
    "Arcane Resilience": (1, 3, 1, None, None),
    "Improved Mana Shield": (1, 3, 2, None, None),
    "Arcane Meditation": (1, 4, 3, None, None),
}, build=[("Improved Frostbolt", 5), ("Ice Shards", 5), ("Piercing Ice", 3), ("Improved Frost Nova", 2), ("Shatter", 5),
          ("Ice Block", 1), ("Cold Snap", 1), ("Frost Channeling", 3), ("Improved Blizzard", 3), ("Arctic Reach", 2), ("Ice Barrier", 1),
          ("Arcane Subtlety", 2), ("Arcane Focus", 3), ("Arcane Concentration", 5), ("Wand Specialization", 2),
          ("Arcane Resilience", 1), ("Improved Mana Shield", 2), ("Arcane Meditation", 3), ("Magic Absorption", 2)])

T["WARLOCK"] = dict(spec="Affliction", trees=["Affliction", "Demonology", "Destruction"], talents={
    "Suppression": (1, 1, 5, None, None),
    "Improved Corruption": (1, 1, 5, None, None),
    "Improved Life Tap": (1, 2, 2, None, None),
    "Improved Drain Soul": (1, 2, 2, None, None),
    "Amplify Curse": (1, 3, 1, None, None),
    "Improved Curse of Agony": (1, 3, 3, None, None),
    "Fel Concentration": (1, 3, 5, None, None),
    "Nightfall": (1, 4, 2, None, None),
    "Grim Reach": (1, 4, 2, None, None),
    "Siphon Life": (1, 5, 1, None, 18265),
    "Shadow Mastery": (1, 6, 5, "Siphon Life", None),
    "Dark Pact": (1, 7, 1, None, 18220),
    "Demonic Embrace": (2, 1, 5, None, None),
    "Improved Voidwalker": (2, 2, 3, None, None),
    "Improved Health Funnel": (2, 2, 2, None, None),
    "Fel Domination": (2, 3, 1, None, None),
    "Fel Stamina": (2, 3, 5, None, None),
    "Unholy Power": (2, 4, 5, None, None),
}, build=[("Improved Corruption", 5), ("Improved Life Tap", 2), ("Suppression", 3), ("Amplify Curse", 1),
          ("Improved Curse of Agony", 3), ("Improved Drain Soul", 1), ("Nightfall", 2), ("Grim Reach", 2), ("Fel Concentration", 1),
          ("Siphon Life", 1), ("Fel Concentration", 4), ("Shadow Mastery", 5), ("Dark Pact", 1),
          ("Demonic Embrace", 5), ("Improved Voidwalker", 3), ("Improved Health Funnel", 2), ("Fel Domination", 1),
          ("Fel Stamina", 5), ("Unholy Power", 4)])

T["DRUID"] = dict(spec="Feral Combat", trees=["Balance", "Feral Combat", "Restoration"], talents={
    "Furor": (3, 1, 5, None, None),
    "Ferocity": (2, 1, 5, None, 16934),
    "Feral Instinct": (2, 2, 5, None, None),
    "Brutal Impact": (2, 2, 2, None, None),
    "Sharpened Claws": (2, 3, 3, None, None),
    "Feline Swiftness": (2, 3, 2, None, [17002, 24866]),
    "Feral Charge": (2, 3, 1, None, None),
    "Predatory Strikes": (2, 4, 3, None, None),
    "Blood Frenzy": (2, 4, 2, "Sharpened Claws", None),
    "Primal Fury": (2, 4, 2, "Sharpened Claws", None),
    "Improved Shred": (2, 4, 2, None, None),
    "Savage Fury": (2, 5, 2, None, None),
    "Faerie Fire (Feral)": (2, 5, 1, None, 16857),
    "Heart of the Wild": (2, 6, 5, "Predatory Strikes", None),
    "Leader of the Pack": (2, 7, 1, None, None),
    "Nature's Grasp": (1, 1, 1, None, 16689),
    "Improved Nature's Grasp": (1, 1, 4, "Nature's Grasp", None),
    "Natural Weapons": (1, 2, 5, None, None),
    "Omen of Clarity": (1, 3, 1, None, None),
}, build=[("Furor", 5), ("Ferocity", 5), ("Feral Instinct", 5), ("Sharpened Claws", 3), ("Feline Swiftness", 2),
          ("Predatory Strikes", 3), ("Blood Frenzy", 2), ("Savage Fury", 2), ("Faerie Fire (Feral)", 1), ("Primal Fury", 2),
          ("Heart of the Wild", 5), ("Leader of the Pack", 1),
          ("Nature's Grasp", 1), ("Improved Nature's Grasp", 4), ("Natural Weapons", 5), ("Omen of Clarity", 1),
          ("Feral Charge", 1), ("Improved Shred", 2), ("Brutal Impact", 1)])

BY_NAME = {}
for r in db["spell_template"]:
    BY_NAME.setdefault(r["SpellName"], []).append(int(r["Id"]))

def talent_rank_ids(cls, tname, maxrank, hint):
    """Return [rank1 id, ..., rankN id] (0 when not found) and a note for the report."""
    cands = sorted(BY_NAME.get(tname, []))
    def rk(i):
        r = SPELL[i]["Rank1"]
        m = re.match(r"Rank (\d+)$", r)
        return int(m.group(1)) if m else (1 if r == "" else None)
    def chain_from(first):
        ids = [first]
        for r in range(2, maxrank + 1):
            nxt = [i for i in cands if rk(i) == r and SPELL[i]["Attributes"] == SPELL[first]["Attributes"]]
            nxt = nxt or [i for i in cands if rk(i) == r and abs(i - ids[-1]) < 5000]
            if not nxt:
                return None
            ids.append(min(nxt, key=lambda i: abs(i - ids[-1])))
        return ids
    if isinstance(hint, list):  # explicit IDs for talents whose ranks carry no "Rank N" text
        bad = [i for i in hint if i not in SPELL or name(i) != tname]
        return (hint, None) if not bad and len(hint) == maxrank else ([0] * maxrank, f"explicit ids {hint} do not match")
    if hint:
        if hint not in SPELL or name(hint) != tname:
            return [0] * maxrank, f"hint {hint} is not '{tname}'"
        ids = chain_from(hint)
        return (ids, None) if ids else ([0] * maxrank, f"ranks of {hint} not found")
    firsts = [i for i in cands if rk(i) == 1 and SPELL[i]["Effect1"] != str(EFFECT_LEARN_SPELL)]
    chains = [c for c in (chain_from(f) for f in firsts) if c]
    if maxrank > 1:  # a talent rank 1 has a matching rank 2; spells learned from trainers are not talents
        chains = [c for c in chains if not (SPELL[c[0]]["Attributes"] != SPELL[c[1]]["Attributes"])]
    passive = [c for c in chains if int(SPELL[c[0]]["Attributes"]) & 0x40]
    if len(chains) > 1 and len(passive) == 1:
        chains = passive
    if len(chains) == 1:
        return chains[0], None
    if not chains:
        return [0] * maxrank, "not found"
    return [0] * maxrank, "ambiguous: " + ", ".join(str(c[0]) for c in chains)

# ------------------------------------------------------------------ rotations
CONDITIONS = ["opener", "pull", "keep_up", "on_cooldown", "spam", "filler", "execute", "low_health", "low_mana", "combo_5",
              "proc", "interrupt", "aoe", "before_combat", "pet_attack", "finisher", "kite", "heal_self", "drink"]

# Pet spells allowed in rotations (cast by the pet, not in the player's spell list): name -> spellID
PET_SPELLS = {"WARLOCK": {"Firebolt": 3110, "Torment": 3716}, "HUNTER": {"Growl": 2649}}

# Steps are (spell name, condition); names resolve to the rank-1 ID of the class spell or talent.
# "pet:Name" resolves through PET_SPELLS.
R = {}
R["WARRIOR"] = [
    (1, 3, [("Battle Stance", "before_combat"), ("Battle Shout", "keep_up"), ("Heroic Strike", "spam")]),
    (4, 11, [("Battle Shout", "before_combat"), ("Charge", "opener"), ("Rend", "keep_up"), ("Heroic Strike", "filler"),
             ("Thunder Clap", "aoe"), ("Hamstring", "kite")]),
    (12, 19, [("Bloodrage", "before_combat"), ("Charge", "opener"), ("Rend", "keep_up"), ("Overpower", "proc"),
              ("Heroic Strike", "filler"), ("Thunder Clap", "aoe")]),
    (20, 23, [("Bloodrage", "before_combat"), ("Charge", "opener"), ("Rend", "keep_up"), ("Overpower", "proc"),
              ("Heroic Strike", "filler"), ("Cleave", "aoe")]),
    (24, 29, [("Bloodrage", "before_combat"), ("Charge", "opener"), ("Rend", "keep_up"), ("Overpower", "proc"),
              ("Execute", "execute"), ("Heroic Strike", "filler"), ("Cleave", "aoe")]),
    (30, 39, [("Battle Shout", "before_combat"), ("Charge", "opener"), ("Sweeping Strikes", "aoe"), ("Overpower", "proc"),
              ("Execute", "execute"), ("Rend", "keep_up"), ("Heroic Strike", "filler")]),
    (40, 60, [("Battle Shout", "before_combat"), ("Charge", "opener"), ("Mortal Strike", "on_cooldown"), ("Overpower", "proc"),
              ("Execute", "execute"), ("Sweeping Strikes", "aoe"), ("Heroic Strike", "filler")]),
]
R["PALADIN"] = [
    (1, 3, [("Devotion Aura", "before_combat"), ("Seal of Righteousness", "keep_up"), ("Holy Light", "heal_self")]),
    (4, 9, [("Blessing of Might", "before_combat"), ("Seal of Righteousness", "keep_up"), ("Judgement", "on_cooldown"),
            ("Holy Light", "heal_self")]),
    (10, 24, [("Blessing of Might", "before_combat"), ("Seal of the Crusader", "opener"), ("Judgement", "on_cooldown"),
              ("Seal of Righteousness", "keep_up"), ("Hammer of Justice", "interrupt"), ("Holy Light", "heal_self"),
              ("Lay on Hands", "low_health")]),
    (25, 39, [("Blessing of Might", "before_combat"), ("Seal of the Crusader", "opener"), ("Judgement", "on_cooldown"),
              ("Seal of Command", "keep_up"), ("Hammer of Justice", "interrupt"), ("Holy Light", "heal_self"),
              ("Lay on Hands", "low_health")]),
    (40, 43, [("Blessing of Might", "before_combat"), ("Seal of the Crusader", "opener"), ("Judgement", "on_cooldown"),
              ("Seal of Command", "keep_up"), ("Repentance", "interrupt"), ("Holy Light", "heal_self"),
              ("Lay on Hands", "low_health")]),
    (44, 60, [("Blessing of Might", "before_combat"), ("Seal of the Crusader", "opener"), ("Judgement", "on_cooldown"),
              ("Seal of Command", "keep_up"), ("Hammer of Wrath", "execute"), ("Repentance", "interrupt"),
              ("Holy Light", "heal_self")]),
]
R["HUNTER"] = [
    (1, 9, [("Aspect of the Monkey", "before_combat"), ("Serpent Sting", "opener"), ("Auto Shot", "spam"),
            ("Arcane Shot", "filler"), ("Raptor Strike", "filler")]),
    (10, 29, [("Call Pet", "before_combat"), ("Aspect of the Hawk", "before_combat"), ("pet:Growl", "pet_attack"),
              ("Hunter's Mark", "opener"), ("Serpent Sting", "keep_up"), ("Arcane Shot", "filler"), ("Wing Clip", "kite")]),
    (30, 39, [("pet:Growl", "pet_attack"), ("Hunter's Mark", "opener"), ("Serpent Sting", "keep_up"),
              ("Intimidation", "interrupt"), ("Arcane Shot", "filler"), ("Multi-Shot", "aoe"), ("Wing Clip", "kite")]),
    (40, 50, [("pet:Growl", "pet_attack"), ("Hunter's Mark", "opener"), ("Bestial Wrath", "on_cooldown"),
              ("Rapid Fire", "on_cooldown"), ("Serpent Sting", "keep_up"), ("Arcane Shot", "filler"), ("Multi-Shot", "filler")]),
    (51, 60, [("pet:Growl", "pet_attack"), ("Aimed Shot", "opener"), ("Bestial Wrath", "on_cooldown"),
              ("Rapid Fire", "on_cooldown"), ("Serpent Sting", "keep_up"), ("Arcane Shot", "filler"), ("Multi-Shot", "filler")]),
]
R["ROGUE"] = [
    (1, 9, [("Stealth", "before_combat"), ("Sinister Strike", "spam"), ("Eviscerate", "combo_5"), ("Evasion", "low_health")]),
    (10, 25, [("Stealth", "before_combat"), ("Slice and Dice", "finisher"), ("Sinister Strike", "spam"),
              ("Eviscerate", "combo_5"), ("Kick", "interrupt"), ("Evasion", "low_health")]),
    (26, 29, [("Stealth", "before_combat"), ("Cheap Shot", "opener"), ("Slice and Dice", "finisher"),
              ("Sinister Strike", "spam"), ("Eviscerate", "combo_5"), ("Kick", "interrupt"), ("Evasion", "low_health")]),
    (30, 39, [("Stealth", "before_combat"), ("Cheap Shot", "opener"), ("Slice and Dice", "finisher"),
              ("Sinister Strike", "spam"), ("Eviscerate", "combo_5"), ("Blade Flurry", "aoe"), ("Kick", "interrupt")]),
    (40, 60, [("Cheap Shot", "opener"), ("Slice and Dice", "finisher"), ("Sinister Strike", "spam"),
              ("Eviscerate", "combo_5"), ("Blade Flurry", "aoe"), ("Adrenaline Rush", "on_cooldown"), ("Kick", "interrupt")]),
]
R["PRIEST"] = [
    (1, 3, [("Power Word: Fortitude", "before_combat"), ("Smite", "spam"), ("Shoot", "filler"), ("Lesser Heal", "heal_self")]),
    (4, 9, [("Power Word: Fortitude", "before_combat"), ("Power Word: Shield", "pull"), ("Shadow Word: Pain", "opener"),
            ("Smite", "filler"), ("Shoot", "spam"), ("Renew", "heal_self")]),
    (10, 19, [("Power Word: Shield", "pull"), ("Mind Blast", "opener"), ("Shadow Word: Pain", "keep_up"),
              ("Shoot", "spam"), ("Renew", "heal_self"), ("Psychic Scream", "low_health")]),
    (20, 29, [("Power Word: Shield", "pull"), ("Mind Blast", "opener"), ("Shadow Word: Pain", "keep_up"),
              ("Mind Flay", "filler"), ("Shoot", "spam"), ("Psychic Scream", "low_health")]),
    (30, 39, [("Power Word: Shield", "pull"), ("Mind Blast", "opener"), ("Vampiric Embrace", "keep_up"),
              ("Shadow Word: Pain", "keep_up"), ("Mind Flay", "filler"), ("Shoot", "spam"), ("Psychic Scream", "low_health")]),
    (40, 60, [("Shadowform", "before_combat"), ("Power Word: Shield", "pull"), ("Mind Blast", "opener"),
              ("Vampiric Embrace", "keep_up"), ("Shadow Word: Pain", "keep_up"), ("Mind Flay", "filler"), ("Shoot", "spam")]),
]
R["SHAMAN"] = [
    (1, 3, [("Rockbiter Weapon", "before_combat"), ("Lightning Bolt", "pull"), ("Healing Wave", "heal_self")]),
    (4, 9, [("Rockbiter Weapon", "before_combat"), ("Lightning Shield", "keep_up"), ("Lightning Bolt", "pull"),
            ("Earth Shock", "interrupt"), ("Healing Wave", "heal_self")]),
    (10, 29, [("Rockbiter Weapon", "before_combat"), ("Lightning Shield", "keep_up"), ("Lightning Bolt", "pull"),
              ("Searing Totem", "aoe"), ("Flame Shock", "opener"), ("Earth Shock", "interrupt"), ("Healing Wave", "heal_self")]),
    (30, 39, [("Windfury Weapon", "before_combat"), ("Lightning Shield", "keep_up"), ("Lightning Bolt", "pull"),
              ("Flame Shock", "opener"), ("Earth Shock", "interrupt"), ("Healing Wave", "heal_self")]),
    (40, 60, [("Windfury Weapon", "before_combat"), ("Lightning Shield", "keep_up"), ("Lightning Bolt", "pull"),
              ("Stormstrike", "on_cooldown"), ("Earth Shock", "interrupt"), ("Flame Shock", "filler"), ("Healing Wave", "heal_self")]),
]
R["MAGE"] = [
    (1, 3, [("Frost Armor", "before_combat"), ("Arcane Intellect", "before_combat"), ("Fireball", "spam")]),
    (4, 9, [("Frost Armor", "before_combat"), ("Frostbolt", "spam"), ("Fire Blast", "finisher"), ("Shoot", "low_mana"),
            ("Conjure Water", "drink")]),
    (10, 19, [("Frost Armor", "before_combat"), ("Frostbolt", "opener"), ("Frost Nova", "kite"), ("Frostbolt", "spam"),
              ("Fire Blast", "finisher"), ("Shoot", "low_mana"), ("Conjure Water", "drink")]),
    (20, 29, [("Frostbolt", "opener"), ("Frost Nova", "kite"), ("Frostbolt", "spam"), ("Fire Blast", "finisher"),
              ("Blizzard", "aoe"), ("Shoot", "low_mana"), ("Conjure Water", "drink")]),
    (30, 39, [("Frostbolt", "opener"), ("Frost Nova", "kite"), ("Frostbolt", "spam"), ("Cone of Cold", "aoe"),
              ("Blizzard", "aoe"), ("Ice Block", "low_health"), ("Evocation", "low_mana")]),
    (40, 60, [("Ice Barrier", "keep_up"), ("Frostbolt", "opener"), ("Frost Nova", "kite"), ("Frostbolt", "spam"),
              ("Cone of Cold", "aoe"), ("Blizzard", "aoe"), ("Evocation", "low_mana")]),
]
R["WARLOCK"] = [
    (1, 3, [("Summon Imp", "before_combat"), ("Demon Skin", "keep_up"), ("pet:Firebolt", "pet_attack"),
            ("Immolate", "opener"), ("Shadow Bolt", "spam")]),
    (4, 9, [("Summon Imp", "before_combat"), ("pet:Firebolt", "pet_attack"), ("Corruption", "keep_up"),
            ("Curse of Agony", "keep_up"), ("Shoot", "filler"), ("Life Tap", "low_mana")]),
    (10, 29, [("Summon Voidwalker", "before_combat"), ("pet:Torment", "pet_attack"), ("Corruption", "keep_up"),
              ("Curse of Agony", "keep_up"), ("Drain Life", "heal_self"), ("Drain Soul", "execute"), ("Life Tap", "low_mana")]),
    (30, 39, [("pet:Torment", "pet_attack"), ("Corruption", "keep_up"), ("Curse of Agony", "keep_up"),
              ("Siphon Life", "keep_up"), ("Drain Life", "heal_self"), ("Shoot", "filler"), ("Life Tap", "low_mana")]),
    (40, 60, [("pet:Torment", "pet_attack"), ("Corruption", "keep_up"), ("Curse of Agony", "keep_up"),
              ("Siphon Life", "keep_up"), ("Drain Life", "heal_self"), ("Dark Pact", "low_mana"), ("Life Tap", "low_mana")]),
]
R["DRUID"] = [
    (1, 9, [("Mark of the Wild", "before_combat"), ("Wrath", "pull"), ("Moonfire", "opener"), ("Wrath", "spam"),
            ("Rejuvenation", "heal_self"), ("Healing Touch", "low_health")]),
    (10, 19, [("Thorns", "before_combat"), ("Moonfire", "pull"), ("Bear Form", "opener"), ("Demoralizing Roar", "keep_up"),
              ("Maul", "spam"), ("Healing Touch", "heal_self")]),
    (20, 23, [("Cat Form", "before_combat"), ("Prowl", "before_combat"), ("Claw", "spam"),
              ("Rip", "combo_5"), ("Bear Form", "low_health")]),
    (24, 31, [("Cat Form", "before_combat"), ("Prowl", "before_combat"), ("Tiger's Fury", "before_combat"), ("Rake", "opener"),
              ("Claw", "spam"), ("Rip", "combo_5"), ("Bear Form", "low_health")]),
    (32, 36, [("Prowl", "before_combat"), ("Tiger's Fury", "before_combat"), ("Ravage", "opener"), ("Rake", "keep_up"),
              ("Claw", "spam"), ("Ferocious Bite", "combo_5"), ("Bear Form", "low_health")]),
    (37, 60, [("Prowl", "before_combat"), ("Ravage", "opener"), ("Faerie Fire (Feral)", "keep_up"), ("Claw", "spam"),
              ("Rip", "finisher"), ("Ferocious Bite", "combo_5"), ("Tiger's Fury", "before_combat")]),
]

# Tip keys: the addon translates them. English sentence for each key.
TIPS = {
    "pull_one": "Pull one enemy at a time and avoid adds.",
    "first_aid": "Learn First Aid and bandage between fights to cut downtime.",
    "weapon_upgrade": "Upgrade your weapon whenever you can: most of your damage comes from it.",
    "battle_stance": "Stay in Battle Stance while leveling: Charge, Overpower and Mortal Strike need it.",
    "rage_dump": "Use Heroic Strike only when you have spare rage.",
    "seal_judge": "Judge the Seal of the Crusader, then keep a damage Seal up and judge again on cooldown.",
    "two_hander": "Use the slowest, strongest two-handed weapon you can find.",
    "pet_tank": "Send your pet in first and let it build threat before you shoot.",
    "feed_pet": "Keep your pet happy: feed it often so it deals full damage.",
    "ammo": "Carry plenty of ammunition and use the best quiver or ammo pouch you have.",
    "dead_zone": "Stay out of the dead zone: either at range or in melee, never in between.",
    "poisons": "Apply poisons on both weapons from level 20.",
    "stealth_opener": "Open from Stealth when you can for a free first strike.",
    "swords": "Use swords to profit from Sword Specialization; a slow main hand and a fast off hand.",
    "spirit_tap": "Spirit Tap boosts regeneration after a kill: chain pulls instead of drinking.",
    "wand_finish": "Finish enemies with your wand to save mana.",
    "weapon_imbue": "Keep a weapon imbue on your weapon: Rockbiter early, Windfury from level 30.",
    "totems_long_fights": "Drop totems only for long or group fights; they cost a lot of mana.",
    "conjure_food": "Conjure your own food and water to save money.",
    "frost_aoe": "From the 30s, group several enemies, Frost Nova them and Blizzard or Cone of Cold them down.",
    "life_tap": "Use Life Tap to turn health into mana, then get the health back with Drain Life.",
    "multi_dot": "Spread DoTs on several enemies and let your demon tank.",
    "soul_shards": "Keep a few Soul Shards: finish enemies with Drain Soul.",
    "cat_leveling": "Level in Cat Form; switch to Bear Form when several enemies attack you.",
    "shift_heal": "Leave your form to heal yourself, then shift back.",
}
CLASS_TIPS = {
    "WARRIOR": ["battle_stance", "rage_dump", "two_hander", "first_aid", "pull_one"],
    "PALADIN": ["seal_judge", "two_hander", "pull_one", "first_aid"],
    "HUNTER": ["pet_tank", "feed_pet", "ammo", "dead_zone"],
    "ROGUE": ["stealth_opener", "poisons", "swords", "first_aid", "pull_one"],
    "PRIEST": ["spirit_tap", "wand_finish", "pull_one"],
    "SHAMAN": ["weapon_imbue", "two_hander", "totems_long_fights", "first_aid"],
    "MAGE": ["conjure_food", "frost_aoe", "wand_finish"],
    "WARLOCK": ["life_tap", "multi_dot", "soul_shards", "wand_finish"],
    "DRUID": ["cat_leveling", "shift_heal", "first_aid", "pull_one"],
}

# ------------------------------------------------------------------ build + checks
problems = []   # reported, not fatal
errors = []     # fatal

def expand_build(cls):
    td = T[cls]
    seq = []
    for tname, n in td["build"]:
        seq += [tname] * n
    if len(seq) != 51:
        errors.append(f"{cls}: build has {len(seq)} points, not 51")
    ranks, per_tree, out = {}, [0, 0, 0], []
    ids_cache = {}
    for i, tname in enumerate(seq):
        lvl = 10 + i
        if tname not in td["talents"]:
            errors.append(f"{cls}: '{tname}' not in talent table"); continue
        tree, tier, maxrank, prereq, hint = td["talents"][tname]
        # tier rule: (tier-1)*5 points already spent in that tree
        if per_tree[tree - 1] < (tier - 1) * 5:
            errors.append(f"{cls} L{lvl}: {tname} tier {tier} needs {(tier-1)*5} points in tree {tree}, has {per_tree[tree-1]}")
        if prereq:
            ptree, ptier, pmax = td["talents"][prereq][:3]
            if ranks.get(prereq, 0) < pmax:
                errors.append(f"{cls} L{lvl}: {tname} needs {prereq} {pmax}/{pmax}")
            if ptree != tree or ptier > tier:  # same-tier prerequisites (side arrows) exist
                errors.append(f"{cls}: prerequisite {prereq} must be in the same tree, same or lower tier")
        ranks[tname] = ranks.get(tname, 0) + 1
        if ranks[tname] > maxrank:
            errors.append(f"{cls} L{lvl}: {tname} over max rank {maxrank}")
        per_tree[tree - 1] += 1
        if tname not in ids_cache:
            ids, note = talent_rank_ids(cls, tname, maxrank, hint)
            ids_cache[tname] = ids
            if note:
                problems.append(f"{cls} talent {tname}: {note}")
        sid = ids_cache[tname][ranks[tname] - 1] if ranks[tname] <= maxrank else 0
        out.append([lvl, tree, tname, sid])
    return out, ids_cache, per_tree

def build_class(cls):
    spells = build_spells(cls)
    talents, tids, per_tree = expand_build(cls)
    first = {}
    for lvl, sid, rk, cost in spells:
        n = name(sid)
        if n not in first or rk < first[n][1]:
            first[n] = (sid, rk, lvl)
    known_ids = {s[1] for s in spells} | {t[3] for t in talents}
    rotations = []
    prev_max = 0
    for lo, hi, steps in R[cls]:
        if lo != prev_max + 1 or hi < lo:
            errors.append(f"{cls}: band {lo}-{hi} does not follow {prev_max}")
        prev_max = hi
        if not 3 <= len(steps) <= 7:
            errors.append(f"{cls} band {lo}-{hi}: {len(steps)} steps")
        out = []
        for sname, cond in steps:
            if cond not in CONDITIONS:
                errors.append(f"{cls}: unknown condition {cond}")
            if sname.startswith("pet:"):
                sid = PET_SPELLS.get(cls, {}).get(sname[4:], 0)
                if not sid or name(sid) != sname[4:]:
                    errors.append(f"{cls}: pet spell {sname} unresolved")
                avail = 1
            elif sname in tids:        # talent: rank 1 comes from the talent
                sid = tids[sname][0]
                avail = next(t[0] for t in talents if t[2] == sname)
            elif sname in first:
                sid, _, avail = first[sname]
            else:
                errors.append(f"{cls}: rotation spell '{sname}' is neither a class spell nor a talent of the build"); sid, avail = 0, 99
            if sid and not sname.startswith("pet:") and sid not in known_ids:
                errors.append(f"{cls}: rotation spell {sname} ({sid}) not in spells/talents")
            if avail > hi:
                errors.append(f"{cls} band {lo}-{hi}: {sname} only available at {avail}")
            elif avail > lo:
                problems.append(f"{cls} band {lo}-{hi}: {sname} arrives at {avail} (inside the band)")
            out.append([sid, cond])
        rotations.append([lo, hi, out])
    if prev_max != 60:
        errors.append(f"{cls}: rotations stop at {prev_max}")
    for k in CLASS_TIPS[cls]:
        if k not in TIPS:
            errors.append(f"{cls}: unknown tip {k}")
    for s in spells:
        if s[1] == 0:
            problems.append(f"{cls}: spell id 0")
    return dict(spec=T[cls]["spec"], spells=spells, talents=talents, rotations=rotations, tips=CLASS_TIPS[cls], per_tree=per_tree)

def lua_str(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'

def emit(data):
    L = []
    L.append("-- Generated by tools/build_classguide.py from the CMaNGOS classic world DB (z2815). Do not edit by hand.")
    L.append("-- Per class: leveling spec, trainer/quest spells, one talent point per level 10-60, rotations per level band.")
    L.append("-- spells   = { level, spellID, rank, cost in copper }  (spellID = the spell the player learns)")
    L.append("-- talents  = { level, tree (1-3, game order), talent name (English), spellID of that rank }")
    L.append("-- rotations= { minLevel, maxLevel, { { spellID, condition }, ... } }  (rank-1 IDs; priority order)")
    L.append("--")
    L.append("-- Condition keys: " + ", ".join(CONDITIONS))
    L.append("--")
    L.append("-- Tip keys (English text to translate):")
    for k in sorted({k for d in data.values() for k in d["tips"]}):
        L.append(f"--   {k} = {TIPS[k]}")
    L.append("")
    L.append("local _, ns = ...")
    L.append("")
    L.append("ns.ClassGuide = {")
    for cls in CLASSES:
        d = data[cls]
        L.append(f"  {cls} = {{")
        L.append(f"    spec = {lua_str(d['spec'])},")
        L.append(f"    trees = {{ {', '.join(lua_str(t) for t in T[cls]['trees'])} }},")
        L.append("    spells = {")
        for lvl, sid, rk, cost in d["spells"]:
            L.append(f"      {{ {lvl}, {sid}, {rk}, {cost} }}, -- {name(sid)}")
        L.append("    },")
        L.append("    talents = {")
        for lvl, tree, tn, sid in d["talents"]:
            L.append(f"      {{ {lvl}, {tree}, {lua_str(tn)}, {sid} }},")
        L.append("    },")
        L.append("    rotations = {")
        for lo, hi, steps in d["rotations"]:
            st = ", ".join(f'{{ {sid}, "{c}" }}' for sid, c in steps)
            names = ", ".join(name(sid) for sid, c in steps)
            L.append(f"      {{ {lo}, {hi}, {{ {st} }} }}, -- {names}")
        L.append("    },")
        L.append(f"    tips = {{ {', '.join(lua_str(t) for t in d['tips'])} }},")
        L.append("  },")
    L.append("}")
    return "\n".join(L) + "\n"

if __name__ == "__main__":
    data = {cls: build_class(cls) for cls in CLASSES}
    if errors:
        print("ERRORS:", *errors, sep="\n  ")
        sys.exit(1)
    os.makedirs(os.path.dirname(os.path.abspath(OUT)), exist_ok=True)
    open(OUT, "w").write(emit(data))
    for cls in CLASSES:
        d = data[cls]
        print(f"{cls:8} {d['spec']:13} spells={len(d['spells']):3} talents={len(d['talents'])} split={'/'.join(map(str, d['per_tree']))} bands={len(d['rotations'])}")
    for p in problems:
        print("note:", p)
    print("wrote", OUT)
