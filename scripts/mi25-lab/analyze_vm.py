#!/usr/bin/env python3
"""Fast vs slow Kindi launches vs amdgpu VRAM state (run in ~/kindi/logs/vm). For each launch vN: decode speed, the
before/held free lists per buddy order, clear_free, and the large BOs (>= 64 MiB) from amdgpu_vm_info with flags."""
import glob, re


def dump(path):
    d = {"orders": {}, "bos": []}
    for l in open(path, errors="replace"):
        m = re.search(r"free: (\d+)MiB, clear_free: (\d+)MiB", l)
        if m:
            d["free"], d["clear"] = int(m.group(1)), int(m.group(2))
        m = re.match(r"order-\s*(\d+) free:\s+(\d+) (KiB|MiB), blocks: (\d+)", l)
        if m:
            d["orders"][int(m.group(1))] = int(m.group(4))
        m = re.search(r"^\s+0x[0-9a-f]+:\s+(\d+) byte (.*)", l)
        if m and int(m.group(1)) >= 64 << 20:
            d["bos"].append((int(m.group(1)), m.group(2).strip()))
    return d


rows = []
for run in sorted(glob.glob("v*-run.txt"), key=lambda p: int(re.findall(r"\d+", p)[0])):
    t = run.split("-")[0]
    dec = None
    for l in open(run):
        if l.startswith("rep 1"):
            dec = float(l.split()[5])
    b, h = dump(t + "-before.txt"), dump(t + "-held.txt")
    rows.append((t, dec, b, h))

print("tag  decode  state | before: free clear o20 o19 o18 o17 | held: free clear o20 o19 o18 o17 | consumed o20..o17 (before-held)")
for t, dec, b, h in rows:
    st = "FAST" if dec and dec > 14.6 else "slow"
    o = lambda d, k: d["orders"].get(k, 0)
    print("%-4s %6.3f %s | %5d %5d %3d %3d %3d %3d | %5d %5d %3d %3d %3d %3d | %s" % (
        t, dec or 0, st, b.get("free", 0), b.get("clear", 0), o(b, 20), o(b, 19), o(b, 18), o(b, 17),
        h.get("free", 0), h.get("clear", 0), o(h, 20), o(h, 19), o(h, 18), o(h, 17),
        " ".join("%+d" % (o(b, k) - o(h, k)) for k in (20, 19, 18, 17))))
print("\nlarge BOs (>= 64 MiB) while held:")
for t, dec, b, h in rows:
    print(t, "%.3f" % (dec or 0), "; ".join("%.1f MiB [%s]" % (s / 2 ** 20, f) for s, f in h["bos"]) or "(none listed)")
