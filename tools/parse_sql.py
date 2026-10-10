# Stream the cmangos SQL dump and extract the tables we need into JSON.
import gzip, json, re, sys
path = sys.argv[1]
want = {"creature_template": ["Entry","Name","SubName","MinLevel","MaxLevel","Rank","MinLevelHealth","MaxLevelHealth","LootId","Faction","NpcFlags"],
        "creature": ["id","map","position_x","position_y"],
        "gameobject": ["id","map","position_x","position_y"],
        "gameobject_template": ["entry","type","name"],
        "creature_questrelation": ["id","quest"], "creature_involvedrelation": ["id","quest"],
        "gameobject_questrelation": ["id","quest"], "gameobject_involvedrelation": ["id","quest"],
        "quest_template": ["entry","ZoneOrSort","MinLevel","QuestLevel","Type","RequiredClasses","RequiredRaces","RequiredSkill","PrevQuestId","NextQuestId","ExclusiveGroup","NextQuestInChain","SrcItemId","Title","Objectives","ReqItemId1","ReqItemId2","ReqItemId3","ReqItemId4","ReqCreatureOrGOId1","ReqCreatureOrGOId2","ReqCreatureOrGOId3","ReqCreatureOrGOId4","PointMapId","PointX","PointY","QuestFlags","SpecialFlags"],
        "creature_loot_template": None, "reference_loot_template": None,
        "item_template": ["entry","name","Quality"]}
cols = {}
rows = {k: [] for k in want}

def parse_values(s, i):
    # parse a sequence of (...),(...); starting at s[i]; yields tuples
    n = len(s)
    out = []
    while i < n:
        while i < n and s[i] in " ,\n\r\t": i += 1
        if i >= n or s[i] == ';': break
        assert s[i] == '(', s[i:i+50]
        i += 1
        vals = []; cur = []; inq = False
        while True:
            c = s[i]
            if inq:
                if c == '\\': cur.append(s[i+1]); i += 2; continue
                if c == "'":
                    if i+1 < n and s[i+1] == "'": cur.append("'"); i += 2; continue
                    inq = False; i += 1; continue
                cur.append(c); i += 1; continue
            if c == "'": inq = True; isstr = True; i += 1; continue
            if c == ',': vals.append(''.join(cur)); cur = []; i += 1; continue
            if c == ')': vals.append(''.join(cur)); i += 1; break
            cur.append(c); i += 1
        out.append(vals)
    return out

text = gzip.open(path, 'rt', encoding='utf-8', errors='replace').read()
for m in re.finditer(r"CREATE TABLE `(\w+)` \((.*?)\n\)", text, re.S):
    t = m.group(1)
    if t in want:
        cols[t] = re.findall(r"^\s*`(\w+)`", m.group(2), re.M)
for m in re.finditer(r"INSERT INTO `(\w+)` VALUES\s*", text):
    t = m.group(1)
    if t not in want: continue
    for vals in parse_values(text, m.end()):
        rows[t].append(vals)
res = {}
for t in want:
    c = cols[t]
    keep = want[t] or c
    idx = [c.index(k) for k in keep]
    res[t] = {"cols": keep, "rows": [[r[j] for j in idx] for r in rows[t]]}
    print(t, len(rows[t]), c[:12], file=sys.stderr)
json.dump(res, open(sys.argv[2], "w"))
