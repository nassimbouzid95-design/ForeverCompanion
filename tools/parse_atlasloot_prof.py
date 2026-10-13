import re, json, sys
src = open(sys.argv[1]).read()
blk = src[src.index('PROFESSION_DATA.CLASSIC = {'):src.index('PROFESSION_DATA.BCC')]
P = {}
for m in re.finditer(r'\[(\d+)\]\s*=\s*\{(nil|\d+),(\d+),(\d+),(\d+),(\d+),\{([\d,]*)\},\{([\d,]*)\}(?:,(\d+))?\}', blk):
    sid, cr, prof, mn, lo, hi, rg, rc, n = m.groups()
    P[int(sid)] = dict(item=None if cr == 'nil' else int(cr), prof=int(prof), min=int(mn), low=int(lo), high=int(hi),
                       reag=[int(x) for x in rg.split(',') if x], cnt=[int(x) for x in rc.split(',') if x], n=int(n) if n else 1)
rsrc = open(sys.argv[2]).read()
rblk = rsrc[rsrc.index('RECIPE_DATA.CLASSIC = {'):]
rblk = rblk[:rblk.index('\n}')]
R = {}
for m in re.finditer(r'\[(\d+)\]\s*=\s*\{(\d+),(\d+),(\d+)\}', rblk):
    R[int(m.group(4))] = int(m.group(1))
json.dump({'prof': P, 'recipe_item_of_spell': R}, open(sys.argv[3], 'w'))
print(len(P), len(R))
