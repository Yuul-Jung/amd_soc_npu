import argparse
import random
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[2]/'ch01/reference'))
from mac_reference import compare


class Memory:
    def __init__(self):
        self.mem = {}
        self.data = 0

    def tick(self, rn, wr, wa, wd, rd, ra):
        if not rn:
            self.data = 0
            return 0, 0
        if wr and rd and wa == ra:
            raise ValueError('COLLISION')
        if rd:
            if ra not in self.mem:
                raise ValueError('UNINITIALIZED_READ')
            self.data = self.mem[ra]
        if wr:
            self.mem[wa] = wd
        return self.data, rd


def self_test():
    m = Memory()
    for args, error in (((1,1,0,3,1,0),'COLLISION'), ((1,0,0,0,1,0),'UNINITIALIZED_READ')):
        try:
            m.tick(*args)
        except ValueError as exc:
            assert str(exc) == error
        else:
            raise AssertionError('Missing rejection')
    m.tick(1,1,0,-7,0,0)
    m.tick(0,1,0,99,1,0)
    assert m.tick(1,0,0,0,1,0) == (-7,1)
    print('PYTHON_SELF_TEST_PASS reset_retention,collision,uninitialized')


def generate(dw, ab, dest):
    depth = 1 << ab
    lo, hi = -(1 << (dw-1)), (1 << (dw-1))-1
    models = [Memory(), Memory()]
    rows = [(0, *(0,0,0,0,0)*2)]
    # 각 주소를 서로 다른 signed 패턴으로 초기화하고 독립성을 확인한다.
    for addr in range(depth):
        rows.append((1,1,addr,lo+addr,0,0,1,addr,hi-addr,0,0))
    for addr in range(depth):
        rows.append((1,0,0,0,1,addr,0,0,0,1,addr))
    rows += [(0,1,0,9,1,0,1,depth-1,9,1,depth-1),
             (1,0,0,0,1,0,0,0,0,1,depth-1), (1,*(0,0,0,0,0)*2)]
    rng = random.Random(304)
    for _ in range(500):
        values = [int(rng.randrange(31)!=0)]
        for _ in range(2):
            wa = rng.randrange(depth)
            ra = (wa + rng.randrange(1,depth)) % depth
            values += [rng.randrange(2),wa,rng.randint(lo,hi),rng.randrange(2),ra]
        rows.append(tuple(values))
    with (dest/'vectors.txt').open('w') as vf, (dest/'expected.txt').open('w') as ef:
        for cycle, row in enumerate(rows,1):
            out = []
            for i,m in enumerate(models):
                out.extend(m.tick(row[0],*row[1+5*i:6+5*i]))
            vf.write(' '.join(map(str,(*row,*out)))+'\n')
            ef.write(' '.join(map(str,(cycle,*out)))+'\n')
    print(f'PYTHON_VECTORS width={dw} depth={depth} cycles={len(rows)} seed=304')


if __name__ == '__main__':
    p=argparse.ArgumentParser()
    p.add_argument('--width',type=int,default=16); p.add_argument('--addr',type=int,default=8)
    p.add_argument('--out',type=Path); p.add_argument('--actual',type=Path)
    a=p.parse_args(); self_test()
    if a.actual: compare(a.out/'expected.txt',a.actual)
    else: generate(a.width,a.addr,a.out)
