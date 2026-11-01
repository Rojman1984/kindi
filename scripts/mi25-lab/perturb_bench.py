"""Allocation-perturbation launch: optionally allocate (and zero) a DUMMY_MB buffer BEFORE the engine loads and keep it
alive to the end; log the weight buffer's VA (first allocation >= 1 GiB after the dummy); run the usual workload
(N-token prompt, G decode, 2 reps). Usage: perturb_bench.py TAG DUMMY_MB [N=512] [G=64]"""
import os, sys, time
import numpy as np
import cupy as cp
TAG, DMB = sys.argv[1], int(sys.argv[2])
N = int(sys.argv[3]) if len(sys.argv) > 3 else 512; G = int(sys.argv[4]) if len(sys.argv) > 4 else 64
pool = cp.get_default_memory_pool(); rec = []
def alloc(sz):
    m = pool.malloc(sz)
    if sz >= 1 << 20:
        rec.append((m.ptr, sz))
    return m
cp.cuda.set_allocator(alloc)
dummy = None
if DMB > 0:
    dummy = cp.zeros(DMB << 20, dtype=cp.uint8); cp.cuda.Device().synchronize()   # held until exit
from kindi.engine import make_engine
eng = make_engine(os.environ["KINDI_PACK"], ctx=max(N + G + 256, 2048), log=lambda *a: None)
rng = np.random.default_rng(0)
toks = [int(t) for t in rng.integers(1000, 100000, N)]
for rep in range(2):
    eng.reset(); cp.cuda.Device().synchronize(); t0 = time.time()
    eng.feed_batch(toks[:-1], 0); cp.cuda.Device().synchronize(); t1 = time.time()
    tok, pos = toks[-1], N - 1
    for i in range(G):
        tok = int(eng.step(tok, pos)); pos += 1
    cp.cuda.Device().synchronize(); t2 = time.time()
    if rep == 1:
        w = [p for p, s in rec if s > (4 << 30)]
        d = [p for p, s in rec if s == (DMB << 20)]
        print("RESULT %s dummy_mb %d prefill_tps %.2f decode_tps %.3f weights_va 0x%x dummy_va %s" % (
            TAG, DMB, (N - 1) / (t1 - t0), G / (t2 - t1), w[0] if w else 0, ("0x%x" % d[0]) if d else "-"), flush=True)
del dummy
