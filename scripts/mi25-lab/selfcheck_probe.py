"""In one process: build the engine BUILDS times, each time measuring the self-check decode rate (from position 0) and the
decode after a 512-token prompt, then free it (as selfcheck.checked does). Answers: does a rebuild inside one process
draw the fast/slow state again, where should the threshold sit, and is all memory given back between builds.
Usage (in the image, repo mounted): python3 /work/selfcheck_probe.py [BUILDS=8] [HOLD_MB=64]"""
import gc, os, sys, time
import numpy as np
import cupy as cp
from kindi.engine import make_engine
from kindi import selfcheck
B = int(sys.argv[1]) if len(sys.argv) > 1 else 8
HOLD = int(sys.argv[2]) if len(sys.argv) > 2 else 64
pool = cp.get_default_memory_pool()
rng = np.random.default_rng(0)
toks = [int(t) for t in rng.integers(1000, 100000, 512)]
for b in range(1, B + 1):
    free0 = cp.cuda.runtime.memGetInfo()[0] >> 20
    t0 = time.time()
    eng = make_engine(os.environ["KINDI_PACK"], ctx=65536, log=lambda *a: None)
    load = time.time() - t0
    sc = selfcheck._rate(eng, 48)
    eng.reset(); eng.feed_batch(toks[:-1], 0); cp.cuda.Device().synchronize()
    tok, pos = toks[-1], 511
    t1 = time.time()
    for i in range(64):
        tok = int(eng.step(tok, pos)); pos += 1
    cp.cuda.Device().synchronize()
    d512 = 64 / (time.time() - t1)
    print("build %d: load %.1fs  selfcheck(pos0) %.2f  decode@512 %.3f  free before build %d MiB" % (b, load, sc, d512, free0), flush=True)
    del eng; gc.collect(); pool.free_all_blocks()
    hold = cp.zeros(HOLD << 20, dtype=cp.uint8) if HOLD else None
    cp.cuda.Device().synchronize()
print("free at end %d MiB" % (cp.cuda.runtime.memGetInfo()[0] >> 20))
