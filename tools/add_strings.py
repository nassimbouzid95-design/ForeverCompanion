# Appends new strings to the locale files. Usage: python3 add_strings.py strings.json [section]
# strings.json: { "English text": { "frFR": "...", "deDE": "...", ... }, ... }  (missing locales are skipped)
import json, sys, os, re
base = '/mnt/project-files/addon/ForeverCompanion/Locales/'
data = json.load(open(sys.argv[1]))
section = sys.argv[2] if len(sys.argv) > 2 else 'new'
def esc(x): return x.replace('\\', '\\\\').replace('"', '\\"').replace('\n', '\\n')
def have(path):
    return set(re.findall(r'^L\["((?:[^"\\]|\\.)*)"\]', open(path).read(), re.M)) if os.path.exists(path) else set()
en = base + 'enUS.lua'
known = have(en)
new = [k for k in data if esc(k) not in known]
if new:
    with open(en, 'a') as f:
        f.write('\n-- ' + section + '\n' + ''.join('L["%s"] = true\n' % esc(k) for k in new))
for fn in os.listdir(base):
    loc = fn[:-4]
    if loc == 'enUS': continue
    k_have = have(base + fn)
    lines = ['L["%s"] = "%s"\n' % (esc(k), esc(v[loc])) for k, v in data.items() if isinstance(v, dict) and loc in v and esc(k) not in k_have]
    if lines:
        with open(base + fn, 'a') as f: f.write('\n-- ' + section + '\n' + ''.join(lines))
print('added', len(new), 'keys')
