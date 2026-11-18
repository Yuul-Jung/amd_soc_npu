import argparse
import random
import sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[2]/'ch01/reference'))
from mac_reference import wrap, compare


def quantize(x, width, shift, rounding=1, saturate=1):
    # Python 정수 나눗셈을 사용하여 RTL의 시프트 구현과 독립적으로 계산한다.
    if rounding and shift:
        mag=(abs(x)+(1<<(shift-1)))//(1<<shift)
        y=-mag if x<0 else mag
    else: y=x//(1<<shift)
    lo,hi=-(1<<(width-1)),(1<<(width-1))-1
    ov=int(y<lo or y>hi)
    return (min(hi,max(lo,y)) if saturate else wrap(y,width)),ov


def self_test():
    assert quantize(-3,8,1,0)==(-2,0)
    assert quantize(-3,8,1,1)==(-2,0)
    assert quantize(-1,8,1,0)==(-1,0)
    assert quantize(-1,8,1,1)==(-1,0)
    assert quantize(1,8,1,1)==(1,0)
    assert quantize(256,8,0,1,1)==(127,1)
    assert quantize(256,8,0,1,0)==(0,1)
    print('PYTHON_FIXED_SELF_TEST_PASS')


def generate(iw,ow,shift,out):
    lo,hi=-(1<<(iw-1)),(1<<(iw-1))-1
    half=1<<(max(shift-1,0))
    xs=[lo,hi,0,1,-1]
    for anchor in (0,1,-1,(1<<(ow-1))-1,-(1<<(ow-1))):
        for delta in (-half-1,-half,-half+1,half-1,half,half+1):
            x=anchor*(1<<shift)+delta
            if lo<=x<=hi: xs.append(x)
    rng=random.Random(305)
    xs += [rng.randint(lo,hi) for _ in range(2000)]
    state=[(0,0)]*4
    with (out/'vectors.txt').open('w') as vf,(out/'expected.txt').open('w') as ef:
        for c,x in enumerate(xs,1):
            # TB 초기 Reset 이후 첫 최솟값도 실제 수락시켜 경계 검사를 생략하지 않는다.
            rn=int(c%97!=0); vi=int(c%7!=0)
            ev=rn and vi
            for k in range(4):
                if not rn: state[k]=(0,0)
                elif vi: state[k]=quantize(x,ow,shift,k//2,k%2)
            results=[v for pair in state for v in pair]+[int(ev)]
            vf.write(' '.join(map(str,(rn,vi,x,*results)))+'\n')
            ef.write(' '.join(map(str,(c,*results)))+'\n')
    print(f'PYTHON_VECTORS IN={iw} OUT={ow} SHIFT={shift} cycles={len(xs)} seed=305')


if __name__=='__main__':
    p=argparse.ArgumentParser(); p.add_argument('--in-width',type=int,default=32)
    p.add_argument('--out-width',type=int,default=8); p.add_argument('--shift',type=int,default=8)
    p.add_argument('--out',type=Path); p.add_argument('--actual',type=Path)
    a=p.parse_args(); self_test()
    if a.actual: compare(a.out/'expected.txt',a.actual)
    else: generate(a.in_width,a.out_width,a.shift,a.out)
