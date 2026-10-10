# Extract event-only spawns and event quests from the cmangos dump.
import gzip, json, re, sys
sys.path.insert(0, '/tmp/claude-0/data')
text = gzip.open(sys.argv[1], 'rt', encoding='utf-8', errors='replace').read()
def cols(t):
    m = re.search(r"CREATE TABLE `%s` \((.*?)\n\)" % t, text, re.S)
    return re.findall(r"^\s*`(\w+)`", m.group(1), re.M)
def rows(t):
    out = []
    for m in re.finditer(r"INSERT INTO `%s` VALUES\s*(.*?);\n" % t, text, re.S):
        for r in re.findall(r"\(([^()]*)\)", m.group(1)):
            out.append([v.strip().strip("'") for v in r.split(',')])
    return out
res = {}
for t, keep in [("creature", ["guid", "id"]), ("gameobject", ["guid", "id"]), ("game_event_creature", ["guid", "event"]),
                ("game_event_gameobject", ["guid", "event"]), ("game_event_quest", ["quest", "event"])]:
    c = cols(t); idx = [c.index(k) for k in keep]
    res[t] = [[int(float(r[i])) for i in idx] for r in rows(t) if len(r) == len(c)]
    print(t, len(res[t]), file=sys.stderr)
json.dump(res, open('/tmp/claude-0/data/events.json', 'w'))
