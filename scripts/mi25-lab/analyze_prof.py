#!/usr/bin/env python3
"""Compare a fast and a slow profiled Kindi launch: per-kernel GPU time inside the rep-1 decode window, and the
allocation layouts. rocprofv3 timestamps are on the GPU/monotonic clock, not time.time(), so the decode window is
taken as the last (64 / decode_tps) seconds before the final kernel ends (nothing is launched after rep 1's decode).
Usage: python3 analyze_prof.py FAST_TAG SLOW_TAG   (in ~/kindi/logs/prof)"""
import csv, re, sys, collections
F, S = sys.argv[1], sys.argv[2]


def tps(tag):
    for l in open("allocs-%s.txt" % tag):
        if l.startswith("rep 1"):
            return float(l.split()[5])


def window(tag):
    rows = list(csv.DictReader(open("%s/trace_kernel_trace.csv" % tag)))
    for r in rows:
        r["s"], r["e"] = int(r["Start_Timestamp"]), int(r["End_Timestamp"])
    end = max(r["e"] for r in rows)
    w = 64 / tps(tag) * 1e9
    k = [r for r in rows if r["s"] >= end - w]
    busy = sum(r["e"] - r["s"] for r in k)
    agg = collections.defaultdict(lambda: [0, 0, set()])
    for r in k:
        a = agg[r["Kernel_Name"][:60]]
        a[0] += 1; a[1] += r["e"] - r["s"]
        a[2].add("%sx%s/%s" % (r["Grid_Size_X"], r["Grid_Size_Y"], r["Workgroup_Size_X"]))
    return agg, busy, w, len(k)


af, bf, wf, nf = window(F)
as_, bs, ws, ns = window(S)
print("FAST %s: %.3f tok/s, window %.1f ms, %d kernels, GPU busy %.1f ms (%.1f%%)" % (F, tps(F), wf / 1e6, nf, bf / 1e6, 100 * bf / wf))
print("SLOW %s: %.3f tok/s, window %.1f ms, %d kernels, GPU busy %.1f ms (%.1f%%)" % (S, tps(S), ws / 1e6, ns, bs / 1e6, 100 * bs / ws))
print("idle (window - busy): fast %.1f ms, slow %.1f ms\n" % ((wf - bf) / 1e6, (ws - bs) / 1e6))
print("%-60s %6s %6s %10s %10s %8s %7s  %s" % ("kernel", "n_f", "n_s", "fast_ms", "slow_ms", "d_ms", "ratio", "grid/block"))
names = sorted(set(af) | set(as_), key=lambda n: -(as_.get(n, [0, 0])[1] - af.get(n, [0, 0])[1]))
for n in names:
    a, b = af.get(n, [0, 0, set()]), as_.get(n, [0, 0, set()])
    if max(a[1], b[1]) < 0.2e6:
        continue
    print("%-60s %6d %6d %10.2f %10.2f %8.2f %7.3f  %s" % (n, a[0], b[0], a[1] / 1e6, b[1] / 1e6, (b[1] - a[1]) / 1e6,
          (b[1] / a[1]) if a[1] else 0, ",".join(sorted(a[2] | b[2]))[:40]))


def allocs(tag):
    out = []
    for l in open("allocs-%s.txt" % tag):
        if re.match(r"^\d", l):
            i, p, s, m2, m64 = l.split()
            out.append((int(i), int(p, 16), int(s), int(m2), int(m64)))
    return out


print("\nallocations >= 1 MiB: order, size, ptr%2MiB (MiB), ptr%64KiB, and ptr delta vs first allocation")
for tag in sys.argv[1:]:
    A = allocs(tag)
    if not A:
        continue
    base = A[0][1]
    big = [a for a in A if a[2] >= 64 << 20]
    print("%s (%.3f tok/s): %d allocs, %.0f MiB; >=64MiB: %d; not 2MiB-aligned: %d of %d; base 0x%x" % (
        tag, tps(tag), len(A), sum(a[2] for a in A) / 2 ** 20, len(big), sum(1 for a in A if a[3]), len(A), base))
    for a in big[:12]:
        print("   #%-4d %9.1f MiB  off2M %6.3f  off64K %6d  +0x%x" % (a[0], a[2] / 2 ** 20, a[3] / 2 ** 20, a[4], a[1] - base))
