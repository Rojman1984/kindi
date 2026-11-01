"""Prompt (prefill) and decode speed through the engine's real paths: feed_batch for an N-token prompt (the chunk path
when it is on), then greedy steps. Usage (in the image): python3 /work/pp_bench.py [N=2048] [decode=64]"""
import os, sys, time
import numpy as np
import cupy as cp
from kindi.engine import make_engine
N = int(sys.argv[1]) if len(sys.argv) > 1 else 2048
G = int(sys.argv[2]) if len(sys.argv) > 2 else 64
eng = make_engine(os.environ["KINDI_PACK"], ctx=N + G + 256, log=lambda *a: print(*a, flush=True))
print("chunk path:", getattr(eng, "chunk_ok", False), "| g5l:", [getattr(s, "g5l", None) for s in getattr(eng, "cards", [])],
      "| dp4a:", [getattr(s, "dp4a", None) for s in getattr(eng, "cards", [])], flush=True)
rng = np.random.default_rng(0)
toks = [int(t) for t in rng.integers(1000, 100000, N)]
for rep in range(2):                         # rep 0 warms up (kernel loads)
    eng.reset(); cp.cuda.Device().synchronize(); t0 = time.time()
    eng.feed_batch(toks[:-1], 0); cp.cuda.Device().synchronize(); tp = time.time() - t0
    t0 = time.time(); tok, pos = toks[-1], N - 1
    for i in range(G):
        tok = int(eng.step(tok, pos)); pos += 1
    cp.cuda.Device().synchronize(); td = time.time() - t0
    print("rep %d: prefill %d tok %.1f tok/s | decode %d tok %.2f tok/s" % (rep, N - 1, (N - 1) / tp, G, G / td), flush=True)
