import argparse
import random
import sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[2]/'ch09/reference'))
from dense_reference import dense,compare


def infer(x_mem,w_mem,length,bias,dw,aw):
    # 주소 순으로 읽은 이미지를 전체 층 모델에 전달한다. 미적재 주소는 KeyError다.
    x=[x_mem[k] for k in range(length)]
    w=[[w_mem[i,k] for k in range(length)] for i in range(4)]
    return dense(x,w,bias,dw,aw)


def generate(dw,aw,out):
    assert infer({0:2},{(i,0):i-2 for i in range(4)},1,[0]*4,dw,aw)[0]==[0,0,0,2]
    rng=random.Random(310);sizes=[0,1,4,16,64]+[rng.randrange(65) for _ in range(17)]
    with (out/'vectors.txt').open('w') as vf,(out/'expected.txt').open('w') as ef:
        for c,n in enumerate(sizes,1):
            xm={k:rng.randint(-64,63) for k in range(n)}
            wm={(i,k):rng.randint(-16,15) for i in range(4) for k in range(n)}
            bias=[rng.randint(-1000,1000) for _ in range(4)]
            if c==1:bias=[-7,7,-(1<<(aw-1)),(1<<(aw-1))-1]
            vals,mask=infer(xm,wm,n,bias,dw,aw)
            vf.write(' '.join(map(str,(n,*bias,*vals,mask)))+'\n')
            for k in range(n):vf.write(' '.join(map(str,(xm[k],*(wm[i,k] for i in range(4)))))+'\n')
            for run in (1,2):ef.write(' '.join(map(str,(c,run,*vals,mask)))+'\n')
    print(f'PYTHON_NPU_SELF_TEST_PASS INT{dw}/{aw} datasets={len(sizes)} inferences={len(sizes)*2} seed=310')


if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--dw',type=int,default=16);p.add_argument('--aw',type=int,default=40)
    p.add_argument('--out',type=Path);p.add_argument('--actual',type=Path);a=p.parse_args()
    if a.actual:compare(a.out/'expected.txt',a.actual)
    else:generate(a.dw,a.aw,a.out)
