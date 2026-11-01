"""prof_bench workload, then HOLD the buffers: writes /out/hold-TAG.ready and sleeps until /out/hold-TAG.go exists
(max 60 s), so the host can dump debugfs while this launch's weight buffer is live. Usage: hold_bench.py TAG [N] [G]"""
import os, sys, time
import numpy as np
import cupy as cp
TAG = sys.argv[1]; N = int(sys.argv[2]) if len(sys.argv) > 2 else 512; G = int(sys.argv[3]) if len(sys.argv) > 3 else 64
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
    print("rep %d prefill_tps %.2f decode_tps %.3f" % (rep, (N - 1) / (t1 - t0), G / (t2 - t1)), flush=True)
open("/out/hold-%s.ready" % TAG, "w").close()
for _ in range(600):
    if os.path.exists("/out/hold-%s.go" % TAG):
        break
    time.sleep(0.1)
