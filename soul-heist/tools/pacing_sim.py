# Pacing simulator for Steal a Soul. Mirrors EconomyConfig/PetConfig/BiomeConfig numbers.
# Run: python3 tools/pacing_sim.py   (re-sync the constants below if you retune the configs)
import random, math
R=[("Common",60,1,10,.10),("Uncommon",25,3,20,.15),("Rare",10,8,40,.20),("Epic",4,25,75,.28),("Legendary",.9,80,150,.36),("Mythic",.09,300,300,.45),("Secret",.01,1500,600,.55)]
B=[("Meadow",16,1,1.0),("Ember",22,3,1.15),("Frost",30,9,1.3),("Crypt",40,25,1.45),("Storm",52,70,1.6),("Void",66,200,1.8),("Celestial",82,600,2.0),("Abyssal",100,2000,2.3)]
TREAD=[(30,0),(45,1500),(60,15000),(80,250000),(100,5e6),(130,1e8),(160,5e9)]
def speedcost(s): return math.floor(25*1.18**(s-16))
def pedcost(n): return math.floor(500*1.9**(n+1-4))
def carrycost(l): return math.floor(150*2**l)
def rebirthcost(r): return math.floor(1e7*3.2**r)
print("Avg income per orb by biome (base, no mutation):")
avg=sum(w*i for _,w,i,_,_ in R)/sum(w for _,w,*_ in R)
for b in B: print(f"  {b[0]:10s} {avg*b[2]:10.1f}/s")
print("Cumulative speed cost from 16 to each biome req:")
for b in B:
    print(f"  {b[0]:10s} speed {b[1]:3d}  cost {sum(speedcost(s) for s in range(16,b[1])):,.0f}")
print("Pedestal costs:", [(n+1, pedcost(n)) for n in range(3,20)])
print("Carry costs:", [carrycost(l) for l in range(15)], "total", sum(carrycost(l) for l in range(15)))
print("Rebirth costs:", [f"{rebirthcost(r):.3g}" for r in range(11)])

def run(seed, rebirths=0, mult=1.0, verbose=False):
    rng=random.Random(seed)
    t=0; ess=50; speed=16; tier=0; ped=3; carry=0
    pets=[]  # incomes
    incub=[] # (end, income)
    milestones={}
    def bestbiome():
        bi=0
        for i,b in enumerate(B):
            if speed>=b[1]: bi=i
        return bi
    while t<6*3600:
        bi=bestbiome(); b=B[bi]
        name=b[0]
        if name not in milestones: milestones[name]=t
        # one steal attempt
        z=130+140*bi+70  # biome centre
        dist=(z+60)*2
        # roll rarity
        x=rng.random()*100; acc=0
        for r in R:
            acc+=r[1]
            if x<=acc: break
        heav=r[4]*(1-0.04*carry)
        trip=dist/ (speed*(1-heav*0.5)) + r[3]*0+ 8
        fail = rng.random() < 0.25
        income_rate = sum(pets)*mult
        t+=trip; ess+=income_rate*trip
        # hatch progress
        for e in list(incub):
            if e[0]<=t: incub.remove(e); pets.append(e[1])
        if not fail:
            inc=r[2]*b[2]*(1.12)
            if len(pets)+len(incub)<ped:
                incub.append((t+r[3]*b[3], inc))
            else:
                if pets and min(pets)<inc:
                    pets.remove(min(pets)); incub.append((t+r[3]*b[3],inc))
        # spend: priority next biome speed, then pedestals, carry
        changed=True
        while changed:
            changed=False
            cap=TREAD[tier][0]
            nb = B[bi+1] if bi+1<len(B) else None
            if nb and speed<nb[1]:
                if speed>=cap and tier+1<len(TREAD) and (tier+1<5 or rebirths>=1) and ess>=TREAD[tier+1][1]:
                    ess-=TREAD[tier+1][1]; tier+=1; changed=True; continue
                if speed<cap and ess>=speedcost(speed):
                    ess-=speedcost(speed); speed+=1; changed=True; continue
            if ped<20 and ess>=pedcost(ped) and pedcost(ped) < max(1,income_rate)*300:
                ess-=pedcost(ped); ped+=1; changed=True; continue
            if carry<15 and ess>=carrycost(carry) and carrycost(carry) < max(1,income_rate)*120:
                ess-=carrycost(carry); carry+=1; changed=True; continue
        if 'reb' not in milestones and ess>=rebirthcost(rebirths): milestones['reb']=t
    return milestones, sum(pets)*mult, ped, speed
import statistics
res=[run(s) for s in range(20)]
keys=[b[0] for b in B]+['reb']
print("Median minutes to unlock (free player, no boosts):")
for k in keys:
    v=[r[0][k]/60 for r in res if k in r[0]]
    print(f"  {k:10s} {statistics.median(v) if v else float('nan'):7.1f} min  (reached by {len(v)}/20)")
print("Income after 6h:", statistics.median([r[1] for r in res]))
res2=[run(s, mult=4.0) for s in range(20)]
print("Median minutes, 2x pass + 2x potion (x4):")
for k in keys:
    v=[r[0][k]/60 for r in res2 if k in r[0]]
    print(f"  {k:10s} {statistics.median(v) if v else float('nan'):7.1f} min  (reached by {len(v)}/20)")
