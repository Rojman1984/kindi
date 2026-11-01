"""Profiling launch: pp_bench_t's workload (N-token prompt, G decode tokens, 2 reps) with every CuPy allocation of 1 MiB
or more logged (pointer, size, order) to /out/allocs-<tag>.txt, plus roctx-free wall-clock marks for the windows.
Run under rocprofv3 --kernel-trace. Usage: python3 /work/prof_bench.py TAG [N=512] [G=64]"""
import os, sys, time
import numpy as np
import cupy as cp
TAG = sys.argv[1]; N = int(sys.argv[2]) if len(sys.argv) > 2 else 512; G = int(sys.argv[3]) if len(sys.argv) > 3 else 64
pool = cp.get_default_memory_pool(); rec = []
def alloc(sz):
    m = pool.malloc(sz)
    if sz >= 1 << 20:
        rec.append((len(rec), m.ptr, sz))
    return m
cp.cuda.set_allocator(alloc)
from kindi.engine import make_engine
eng = make_engine(os.environ["KINDI_PACK"], ctx=max(N + G + 256, 2048), log=lambda *a: None)
rng = np.random.default_rng(0)
toks = [int(t) for t in rng.integers(1000, 100000, N)]
out = []
for rep in range(2):
    eng.reset(); cp.cuda.Device().synchronize(); t0 = time.time()
    eng.feed_batch(toks[:-1], 0); cp.cuda.Device().synchronize(); t1 = time.time()
    tok, pos = toks[-1], N - 1
    for i in range(G):
        tok = int(eng.step(tok, pos)); pos += 1
    cp.cuda.Device().synchronize(); t2 = time.time()
    out.append("rep %d prefill_tps %.2f decode_tps %.3f pf_win %.6f %.6f dc_win %.6f %.6f" % (rep, (N - 1) / (t1 - t0), G / (t2 - t1), t0, t1, t1, t2))
    print(out[-1], flush=True)
with open("/out/allocs-%s.txt" % TAG, "w") as f:
    f.write("\n".join(out) + "\n# order ptr_hex size_bytes ptr%2MiB ptr%64KiB\n")
    for i, p, s in rec:
        f.write("%d 0x%x %d %d %d\n" % (i, p, s, p % (2 << 20), p % (64 << 10)))
    tot = cp.cuda.runtime.memGetInfo()
    f.write("# pool used %d total %d | memGetInfo free %d total %d\n" % (pool.used_bytes(), pool.total_bytes(), tot[0], tot[1]))
