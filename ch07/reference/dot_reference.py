import argparse
import random
import sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[2]/'ch01/reference'))
from mac_reference import wrap,compare


def dot(a,b,width):
    if len(a)!=len(b): raise ValueError('Vector lengths differ')
    return wrap(sum(x*y for x,y in zip(a,b)),width)


def generate(dw,aw,out):
    assert dot([3,-2],[4,5],aw)==2
    assert dot([],[],aw)==0
    rng=random.Random(307);lo,hi=-(1<<(dw-1)),(1<<(dw-1))-1
    cases=[]
    for n in (0,1,2,4,16,256):
        cases += [([lo]*n,[lo]*n),([lo]*n,[hi]*n),([0]*n,[hi]*n)]
    for _ in range(60):
        n=rng.randrange(257)
        cases.append(([rng.randint(lo,hi) for _ in range(n)],[rng.randint(lo,hi) for _ in range(n)]))
    with (out/'vectors.txt').open('w') as vf,(out/'expected.txt').open('w') as ef:
        for c,(a,b) in enumerate(cases,1):
            ans=dot(a,b,aw);vf.write(f'{len(a)} {ans}\n')
            for x,y in zip(a,b):vf.write(f'{x} {y}\n')
            ef.write(f'{c} {ans}\n')
    print(f'PYTHON_DOT_SELF_TEST_PASS cases={len(cases)} INT{dw}/{aw} seed=307')


if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--dw',type=int,default=16);p.add_argument('--aw',type=int,default=40)
    p.add_argument('--out',type=Path);p.add_argument('--actual',type=Path);a=p.parse_args()
    if a.actual:compare(a.out/'expected.txt',a.actual)
    else:generate(a.dw,a.aw,a.out)
