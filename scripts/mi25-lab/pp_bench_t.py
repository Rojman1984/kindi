"""pp_bench with wall-clock marks: prints the epoch time at the start/end of the measured prefill and decode windows,
so a background clock sampler can be cut to those windows. Usage: python3 /work/pp_bench_t.py [N=2048] [decode=64]"""
import os, sys, time
import numpy as np
import cupy as cp
from kindi.engine import make_engine
N = int(sys.argv[1]) if len(sys.argv) > 1 else 2048
G = int(sys.argv[2]) if len(sys.argv) > 2 else 64
eng = make_engine(os.environ["KINDI_PACK"], ctx=max(N + G + 256, 2048), log=lambda *a: None)   # Kindi needs ctx >= 1024
rng = np.random.default_rng(0)
toks = [int(t) for t in rng.integers(1000, 100000, N)]
for rep in range(2):
    eng.reset(); cp.cuda.Device().synchronize(); t0 = time.time()
    eng.feed_batch(toks[:-1], 0); cp.cuda.Device().synchronize(); t1 = time.time()
    tok, pos = toks[-1], N - 1
    for i in range(G):
        tok = int(eng.step(tok, pos)); pos += 1
    cp.cuda.Device().synchronize(); t2 = time.time()
    print("rep %d prefill_tps %.2f decode_tps %.3f pf_win %.3f %.3f dc_win %.3f %.3f"
          % (rep, (N - 1) / (t1 - t0), G / (t2 - t1), t0, t1, t1, t2), flush=True)
