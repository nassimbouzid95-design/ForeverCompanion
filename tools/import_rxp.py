#!/usr/bin/env python3
"""Leveling steps of the RestedXP Forever guides (RXPGuides addon, by RestedXP, CC BY-NC-SA 4.0,
https://github.com/RestedXP/RXPGuides) -> v2-data/rxp_scripts.json: for each start and class, the ordered list of
(accept / complete / turnin, questID) steps of its guides, levels 1 to about 22.  gen_routes.py plays these steps first,
then goes on with its own simulation.

Usage: python3 tools/import_rxp.py <path of RXPGuides/Guides>"""
import json, os, re, sys

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'v2-data', 'rxp_scripts.json')
CLASSES = ['WARRIOR', 'PALADIN', 'HUNTER', 'ROGUE', 'PRIEST', 'SHAMAN', 'MAGE', 'WARLOCK', 'DRUID']
CLASS_WORDS = {c.capitalize(): c for c in CLASSES}
RACE_WORDS = {'Human', 'Dwarf', 'Gnome', 'NightElf', 'Orc', 'Troll', 'Tauren', 'Undead', 'Scourge', 'Skyborne'}
# start key -> faction, races (RXP words)
STARTS = {'human': ('Alliance', ['Human']), 'dwarf': ('Alliance', ['Dwarf', 'Gnome']), 'nightelf': ('Alliance', ['NightElf']),
          'skyborne-a': ('Alliance', ['Skyborne']), 'orc': ('Horde', ['Orc', 'Troll']), 'tauren': ('Horde', ['Tauren']),
          'undead': ('Horde', ['Undead']), 'skyborne-h': ('Horde', ['Skyborne'])}


def chain(start, cls):
    """Guide sections in order, as the guides' #next lines send each race and class."""
    hunter, shaman = cls == 'HUNTER', cls == 'SHAMAN'
    a_tail = ['16-19 Darkshore'] + (['19-21 Darkshore/Ashenvale'] if hunter else ['19-20 Redridge', '20-21 Darkshore/Ashenvale'])
    h_tail = ['12-17 The Barrens', '17-22 Stonetalon/Barrens/Ashenvale']
    if start == 'human':
        return ['1-6 Northshire', '6-11 Elwynn Forest', '11-13 Loch Modan'] + ([] if hunter else ['13-15 Westfall']) + ['14-16 Darkshore'] + a_tail
    if start == 'dwarf':
        if hunter:
            return ['1-5 Coldridge Valley', '5-11 Dun Morogh', '11-13 Loch Modan (Hunter)', '14-16 Darkshore'] + a_tail
        return ['1-5 Coldridge Valley', '5-11 Dun Morogh', '11-12 Elwynn (Dwarf/Gnome)', '12-14 Loch Modan (Dwarf/Gnome)', '13-15 Westfall', '14-16 Darkshore'] + a_tail
    if start == 'nightelf':
        return ['1-6 Shadowglen', '6-11 Teldrassil', '14-16 Darkshore'] + a_tail
    if start == 'skyborne-a':
        return ['1-14 Zephras Isle'] + ([] if hunter else ['13-15 Westfall']) + ['14-16 Darkshore'] + a_tail
    if start == 'orc':
        if hunter or shaman:
            return ['1-6 Durotar', '6-10 Durotar', '10-12 Durotar'] + h_tail
        return ['1-6 Durotar', '6-10 Durotar', '10-12 Durotar', '10-12 Tirisfal (Orc/Troll)', '12-14 Silverpine Forest'] + h_tail
    if start == 'tauren':
        return ['1-6 Mulgore', '6-12 Mulgore'] + h_tail
    if start == 'undead':
        return ['1-6 Tirisfal Glades', '6-12 Tirisfal Glades', '12-14 Silverpine Forest'] + h_tail
    if start == 'skyborne-h':
        return ['1-14 Zephras Isle'] + ([] if hunter else ['12-14 Silverpine Forest']) + h_tail


def fits(tag, cls, races, faction):
    """RXP condition after '<<': words of one group are ANDed by category, '/' separates alternatives."""
    if not tag: return True
    for alt in tag.split('/'):
        words = alt.split()
        ok = True
        pc = [w for w in words if w in CLASS_WORDS]; pr = [w for w in words if w in RACE_WORDS]
        pf = [w for w in words if w in ('Alliance', 'Horde')]
        nc = [w[1:] for w in words if w.startswith('!') and w[1:] in CLASS_WORDS]
        nr = [w[1:] for w in words if w.startswith('!') and w[1:] in RACE_WORDS]
        nf = [w[1:] for w in words if w.startswith('!') and w[1:] in ('Alliance', 'Horde')]
        if pc and cls.capitalize() not in pc: ok = False
        if cls.capitalize() in nc: ok = False
        if pr and not any(r in pr for r in races): ok = False
        if nr and all(r in nr for r in races): ok = False
        if pf and faction not in pf: ok = False
        if faction in nf: ok = False
        if ok: return True
    return False


def parse(folder):
    sections = {}
    for f in sorted(os.listdir(os.path.join(folder, 'Forever'))):
        if not f.endswith('.lua'): continue
        text = open(os.path.join(folder, 'Forever', f), encoding='utf-8', errors='replace').read()
        cur = None; steptag = ''
        for line in text.split('\n'):
            m = re.match(r'^#name (.*)$', line)
            if m:
                cur = sections.setdefault(m.group(1).strip(), []); steptag = ''; continue
            if cur is None: continue
            if re.match(r'^\s*step\b', line):
                t = re.search(r'<<\s*(.*)$', line); steptag = t.group(1).strip() if t else ''
                continue
            m = re.match(r'^\s*\.(accept|turnin|complete)\s+(\d+)', line)
            if m:
                t = re.search(r'<<\s*([^>]*)$', line)
                cur.append((m.group(1), int(m.group(2)), steptag, t.group(1).strip() if t else ''))
    return sections


def main():
    sections = parse(sys.argv[1])
    out = {}
    for start, (faction, races) in STARTS.items():
        for cls in CLASSES:
            steps = []; last = None
            for name in chain(start, cls):
                for kind, qid, steptag, linetag in sections.get(name, []):
                    if not (fits(steptag, cls, races, faction) and fits(linetag, cls, races, faction)): continue
                    if (kind, qid) == last: continue
                    steps.append([kind, qid]); last = (kind, qid)
            out['%s-%s' % (start, cls)] = steps
    json.dump(out, open(OUT, 'w'))
    print('wrote', OUT, {k: len(v) for k, v in list(out.items())[:6]}, '...')


if __name__ == '__main__':
    main()
