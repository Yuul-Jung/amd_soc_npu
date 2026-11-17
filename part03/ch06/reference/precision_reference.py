import argparse
import csv
import random
import sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[2]/'ch05/reference'))
from fixed_reference import quantize, self_test, compare


def generate(out):
    assert quantize(4096,8,8)[0]*16 == quantize(4096,16,4)[0]
    assert quantize(128,8,8)[0]*16 != quantize(128,16,4)[0]
    xs=[0,4096,-4096,127,128,129,-127,-128,-129,32767,32768,-32768,-32769,
        524279,524280,524288,-524288,-524289,2147483647,-2147483648]
    rng=random.Random(306)
    xs += [rng.randint(-1000000,1000000) for _ in range(2000)]
    state=[0]*8
    with (out/'vectors.txt').open('w') as vf,(out/'expected.txt').open('w') as ef,(out/'comparison.csv').open('w') as cf:
        csvout=csv.writer(cf,lineterminator='\n')
        csvout.writerow(['cycle','x_q12','sat','q8_q4','q16_q8','err8_q12','err16_q12','class'])
        for c,x in enumerate(xs,1):
            rn=int(c%97!=0); vi=int(c%7!=0); ev=rn and vi
            if not rn: state=[0]*8
            elif vi:
                state=[]
                for sat in (0,1):
                    q8,o8=quantize(x,8,8,1,sat); q16,o16=quantize(x,16,4,1,sat)
                    state += [q8,q16,o8,o16]
                    e8,e16=q8*256-x,q16*16-x
                    kind='range' if o8 or o16 else ('exact' if e8==e16==0 else 'quantized')
                    csvout.writerow([c,x,sat,q8,q16,e8,e16,kind])
            vf.write(' '.join(map(str,(rn,vi,x,*state,int(ev))))+'\n')
            ef.write(' '.join(map(str,(c,*state,int(ev))))+'\n')
    print(f'PYTHON_VECTORS PRECISION cycles={len(xs)} seed=306')


if __name__=='__main__':
    p=argparse.ArgumentParser(); p.add_argument('--out',type=Path); p.add_argument('--actual',type=Path)
    a=p.parse_args(); self_test()
    if a.actual: compare(a.out/'expected.txt',a.actual)
    else: generate(a.out)
