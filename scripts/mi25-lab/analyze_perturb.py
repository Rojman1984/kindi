#!/usr/bin/env python3
"""Allocation-perturbation results: fast/slow per condition, Fisher exact tests vs the no-dummy control, and the weight
buffer's VA alignment vs state. Pure Python (no scipy). Usage: analyze_perturb.py results.csv [results2.csv ...]
A launch is fast when decode > 14.6 tok/s (the two states are 15.1 and 13.9 on the MI25 27B)."""
import csv, sys
from math import comb


def fisher(a, b, c, d):
    """two-sided Fisher exact p for [[a, b], [c, d]]"""
    n, r1, c1 = a + b + c + d, a + b, a + c
    p = lambda x: comb(r1, x) * comb(n - r1, c1 - x) / comb(n, c1)
    p0 = p(a)
    return min(1.0, sum(p(x) for x in range(max(0, c1 - (n - r1)), min(r1, c1) + 1) if p(x) <= p0 * (1 + 1e-9)))


rows = []
for f in sys.argv[1:]:
    for r in csv.DictReader(l for l in open(f) if not l.startswith("#")):
        if r.get("decode_tps"):
            rows.append((r["cond"], float(r["decode_tps"]) > 14.6, int(r["weights_va"], 16), f))
conds = sorted({c for c, _, _, _ in rows}, key=lambda c: (c != "A", c))
tal = {c: (sum(1 for x in rows if x[0] == c and x[1]), sum(1 for x in rows if x[0] == c and not x[1])) for c in conds}
print("condition  fast  slow  fast%   p vs A")
for c in conds:
    f, s = tal[c]
    pv = "" if c == "A" or "A" not in tal else "%.3f" % fisher(*tal["A"], f, s)
    print("%-9s %5d %5d  %4.0f%%   %s" % (c, f, s, 100 * f / (f + s), pv))
d = [x for x in rows if x[0] != "A"]
if "A" in tal and d:
    df = sum(x[1] for x in d)
    print("any dummy %5d %5d  %4.0f%%   %.3f" % (df, len(d) - df, 100 * df / len(d), fisher(*tal["A"], df, len(d) - df)))
print("\nweight VA alignment vs state")
for m in (32, 64, 128, 256, 1024):
    al = [x for x in rows if x[2] % (m << 20) == 0]
    na = [x for x in rows if x[2] % (m << 20)]
    fa, fn = sum(x[1] for x in al), sum(x[1] for x in na)
    print("  %4d MiB-aligned: fast %d/%d | not aligned: fast %d/%d | p=%.3f" % (
        m, fa, len(al), fn, len(na), fisher(fa, len(al) - fa, fn, len(na) - fn)))
