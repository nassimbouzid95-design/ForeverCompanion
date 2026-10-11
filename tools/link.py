import json, collections, re
cm = json.load(open('cmangos.json')); qf = json.load(open('dq/quests_full.json'))['quest_template']
def table(t): c=cm[t]['cols']; return [dict(zip(c,r)) for r in cm[t]['rows']]
Q = {int(r[0]): dict(zip(qf['cols'], r)) for r in qf['rows']}
db = open('/mnt/project-files/addon/ForeverCompanion/Data/InstanceDB.lua').read()
inst = [(k,int(i)) for k,i in re.findall(r'key = "(\w+)", id = (\d+)', db)]
maps = {i for _,i in inst}
cmap = collections.defaultdict(set); gmap = collections.defaultdict(set)
for r in table('creature'): cmap[int(r['id'])].add(int(r['map']))
for r in table('gameobject'): gmap[int(r['id'])].add(int(r['map']))
ct = {int(r['Entry']): r for r in table('creature_template')}
lootid = collections.defaultdict(list)
for e,t in ct.items():
    l=int(t['LootId'] or 0)
    if l: lootid[l].append(e)
droppers = collections.defaultdict(set)
for r in table('creature_loot_template'):
    for e in lootid.get(int(r['entry']),[]): droppers[int(r['item'])].add(e)
starters = collections.defaultdict(list)
for r in table('creature_questrelation'): starters[int(r['quest'])].append(('c',int(r['id'])))
for r in table('gameobject_questrelation'): starters[int(r['quest'])].append(('g',int(r['id'])))
def inmaps(kind,i): return (cmap if kind=='c' else gmap).get(i,set()) & maps
link = collections.defaultdict(set); zones = collections.defaultdict(collections.Counter)
for qid,q in Q.items():
    hits = collections.Counter()
    for n in range(1,5):
        v=int(q['ReqCreatureOrGOId%d'%n])
        if v>0: hits.update(inmaps('c',v))
        elif v<0: hits.update(inmaps('g',-v))
        it=int(q['ReqItemId%d'%n])
        if it:
            ds=droppers.get(it,set())
            ms=collections.Counter()
            for d in ds:
                for m in cmap.get(d,()): ms[m]+=1
            tot=sum(ms.values())
            for m,c in ms.items():
                if m in maps and c*2>=tot: hits[m]+=1
    for kind,i in starters.get(qid,[]): hits.update(inmaps(kind,i))
    for m in hits: link[m].add(qid); zones[m][int(q['ZoneOrSort'])]+=1
area = {m: zones[m].most_common(1)[0][0] for m in zones if zones[m]}
for qid,q in Q.items():
    z=int(q['ZoneOrSort'])
    for m,a in area.items():
        if a==z and a>0: link[m].add(qid)
json.dump({str(m): sorted(v) for m,v in link.items()}, open('dq/link.json','w'))
for k,i in inst:
    s=link.get(i,set())
    print(k,i,area.get(i),len(s),'|',', '.join(Q[x]['Title'] for x in sorted(s))[:300])
