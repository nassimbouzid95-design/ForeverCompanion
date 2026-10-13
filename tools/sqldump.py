import gzip, re, json, sys
WANT = set(sys.argv[3].split(','))
cols = {}
rows = {t: [] for t in WANT}


def parse_values(s, i):
    out = []
    n = len(s)
    while i < n:
        while i < n and s[i] in ' ,\n\r\t':
            i += 1
        if i >= n or s[i] == ';':
            break
        assert s[i] == '(', s[i:i + 50]
        i += 1
        row = []
        while True:
            while s[i] in ' \t\n\r':
                i += 1
            c = s[i]
            if c == "'":
                j = i + 1
                buf = []
                while True:
                    if s[j] == '\\':
                        buf.append(s[j + 1]); j += 2; continue
                    if s[j] == "'":
                        if s[j + 1] == "'":
                            buf.append("'"); j += 2; continue
                        break
                    buf.append(s[j]); j += 1
                row.append(''.join(buf))
                i = j + 1
            else:
                j = i
                while s[j] not in ',)':
                    j += 1
                v = s[i:j].strip()
                if v == 'NULL':
                    row.append(None)
                elif re.match(r'^-?\d+$', v):
                    row.append(int(v))
                elif re.match(r'^-?[\d.]+(e-?\d+)?$', v):
                    row.append(float(v))
                else:
                    row.append(v)
                i = j
            if s[i] == ',':
                i += 1; continue
            if s[i] == ')':
                i += 1; break
        out.append(row)
    return out


cur = None
pend = None
for line in (gzip.open if sys.argv[1].endswith('.gz') else open)(sys.argv[1], 'rt', encoding='utf8', errors='replace'):
    m = re.match(r"CREATE TABLE (?:IF NOT EXISTS )?`(\w+)`", line)
    if m:
        cur = m.group(1) if m.group(1) in WANT else None
        if cur:
            cols[cur] = []
        continue
    if cur and line.startswith('  `'):
        cols[cur].append(line.split('`')[1])
    if line.startswith(')'):
        cur = None
    if pend is not None:
        buf.append(line)
        if line.rstrip().endswith(';'):
            st = ''.join(buf); rows[pend].extend(parse_values(st, st.index('VALUES') + 6)); pend = None
        continue
    m = re.match(r"INSERT INTO `(\w+)` (?:\([^)]*\) )?VALUES", line)
    if m and m.group(1) in WANT:
        pend, buf = m.group(1), [line]
        if line.rstrip().endswith(';'):
            rows[pend].extend(parse_values(line, line.index('VALUES') + 6)); pend = None

keep = {'item_template': ['entry', 'class', 'subclass', 'name', 'Quality', 'BuyCount', 'BuyPrice', 'SellPrice', 'ItemLevel',
                          'RequiredSkill', 'RequiredSkillRank', 'spellid_1', 'spellid_2', 'RequiredReputationFaction', 'RequiredReputationRank', 'bonding', 'Bonding'],
        'spell_template': ['entry', 'build', 'name', 'recoveryTime', 'categoryRecoveryTime', 'effect1', 'effect2', 'effectTriggerSpell1', 'effectTriggerSpell2', 'effectItemType1', 'reagent1'],
        'creature_template': ['Entry', 'Name', 'SubName', 'TrainerType', 'TrainerSpell', 'TrainerTemplateId', 'VendorTemplateId', 'NpcFlags']}
res = {}
for t in WANT:
    c = cols[t]
    k = keep.get(t, c)
    idx = [c.index(x) for x in k if x in c]
    res[t] = [dict(zip([c[i] for i in idx], [r[i] for i in idx])) for r in rows[t]]
    print(t, len(res[t]), [c[i] for i in idx][:14])
json.dump(res, open(sys.argv[2], 'w'))
