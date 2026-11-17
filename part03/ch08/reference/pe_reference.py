import argparse
import random
import sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[2]/'ch07/reference'))
from dot_reference import dot,compare


def generate(dw,aw,out):
    rng=random.Random(308);lo,hi=-(1<<(dw-1)),(1<<(dw-1))-1
    sizes=[0,1,4,16,64,256]+[rng.randrange(65) for _ in range(20)]
    with (out/'vectors.txt').open('w') as vf,(out/'expected.txt').open('w') as ef:
        for c,n in enumerate(sizes,1):
            a=[[rng.randint(lo,hi) for _ in range(n)] for _ in range(4)]
            b=[[rng.randint(lo,hi) for _ in range(n)] for _ in range(4)]
            if c==2:
                a=[[lo],[lo],[hi],[0]];b=[[lo],[hi],[hi],[lo]]
            pe=[dot(x,y,aw) for x,y in zip(a,b)];ans=sum(pe)
            vf.write(' '.join(map(str,(n,*pe,ans)))+'\n')
            for k in range(n):vf.write(' '.join(str(v) for i in range(4) for v in (a[i][k],b[i][k]))+'\n')
            ef.write(' '.join(map(str,(c,*pe,ans)))+'\n')
    assert dot([1,-2],[3,4],aw)==-5
    print(f'PYTHON_PE_SELF_TEST_PASS INT{dw}/{aw} cases={len(sizes)} seed=308')


if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--dw',type=int,default=16);p.add_argument('--aw',type=int,default=40)
    p.add_argument('--out',type=Path);p.add_argument('--actual',type=Path);a=p.parse_args()
    if a.actual:compare(a.out/'expected.txt',a.actual)
    else:generate(a.dw,a.aw,a.out)
