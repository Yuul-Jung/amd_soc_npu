import argparse
import random
import sys
from pathlib import Path
root=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(root/'ch07/reference'));sys.path.insert(0,str(root/'ch05/reference'))
from dot_reference import dot,compare
from fixed_reference import quantize


def dense(x,weights,biases,dw=16,aw=40,shift=0):
    values=[];mask=0
    for i,(w,bias) in enumerate(zip(weights,biases)):
        raw=max(0,dot(x,w,aw)+bias)
        q,ov=quantize(raw,dw,shift,1,1)
        values.append(q);mask|=ov<<i
    return values,mask


def generate(dw,aw,out):
    assert dense([1],[[2],[-2],[0],[1]],[-3,0,7,-1],dw,aw)[0]==[0,0,7,0]
    rng=random.Random(309);sizes=[0,1,2,4,16,64]+[rng.randrange(65) for _ in range(40)]
    with (out/'vectors.txt').open('w') as vf,(out/'expected.txt').open('w') as ef:
        for c,n in enumerate(sizes,1):
            x=[rng.randint(-64,63) for _ in range(n)]
            w=[[rng.randint(-16,15) for _ in range(n)] for _ in range(4)]
            bias=[rng.randint(-1000,1000) for _ in range(4)]
            if c==1:bias=[-7,7,-(1<<(aw-1)),(1<<(aw-1))-1]
            vals,mask=dense(x,w,bias,dw,aw)
            vf.write(' '.join(map(str,(n,*bias,*vals,mask)))+'\n')
            for k in range(n):vf.write(' '.join(map(str,(x[k],*(w[i][k] for i in range(4)))))+'\n')
            ef.write(' '.join(map(str,(c,*vals,mask)))+'\n')
    print(f'PYTHON_DENSE_SELF_TEST_PASS INT{dw}/{aw} cases={len(sizes)} seed=309')


if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--dw',type=int,default=16);p.add_argument('--aw',type=int,default=40)
    p.add_argument('--out',type=Path);p.add_argument('--actual',type=Path);a=p.parse_args()
    if a.actual:compare(a.out/'expected.txt',a.actual)
    else:generate(a.dw,a.aw,a.out)
