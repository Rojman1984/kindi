# MI25 lab scripts

The scripts behind `docs/MI25.md` and `docs/mi25-results/`. They were written for one machine (designlabsrvr: Ubuntu,
Docker, the `kindi-rocm:mi25` image, models in `~/mi25/models/kindi`, the x16 MI25 at `0000:12:00.0`) and run from
`~/kindi/logs`: copy this folder there (`cp scripts/mi25-lab/* ~/kindi/logs/`) and adjust the paths for another host.

Run long steps detached (`setsid nohup bash run-....sh >/dev/null 2>&1 </dev/null &`) and read their logs. Never run two
benchmarks, or a benchmark and a build, at the same time.

| Script | What it does |
|---|---|
| `kpy.sh FILE.py [args]` | Runs a Python file from `~/kindi/logs` inside the image on ROCm agent `$AGENT` (default 0). `SRC=~/kindi` mounts the repo's `kindi/` over the image's copy, `KENV="A=1 B=2"` adds environment. |
| `pp_bench_t.py N G` | Prefill (`feed_batch`, the chunk path) and decode speed, with epoch-time marks of both windows. |
| `run-sweep.sh` | 5 rounds × 6 configurations, order rotated: the variance sweep (`sweep.csv`). |
| `run-twostate.sh` | 10 launches with clocks on auto, 10 with the HBM clock pinned; a 100 ms clock/power sampler cut to each decode window. Needs `mclk-pin`. |
| `mclk-pin.sh` | Pin/release the HBM clock of one card (stock 945 MHz, not an overclock). Install root-owned as `/usr/local/sbin/mclk-pin` with a narrow sudo rule. |
| `prof_bench.py`, `run-prof.sh`, `analyze_prof.py` | rocprofv3 kernel traces + allocation logs of several launches; per-kernel fast-vs-slow comparison. |
| `gpu-vmdump.sh` | Read-only dump of `amdgpu_vram_mm`, `amdgpu_gem_info`, `amdgpu_vm_info` for one card from debugfs. Install root-owned as `/usr/local/sbin/gpu-vmdump` with a narrow sudo rule. |
| `hold_bench.py`, `run-vmdump.sh`, `analyze_vm.py` | Dump debugfs before each launch and while it holds its weights. |
| `perturb_bench.py`, `run-perturb.sh`, `run-perturb2.sh`, `analyze_perturb.py` | Allocation-perturbation experiment: a dummy buffer (0 / 2 MiB / 12 MiB / 1 GiB / 4 GiB) held while the weights load; idle-checked launches. |
| `build-prism.sh`, `run-prism-bench.sh`, `run-prism-followup.sh` | Build PrismML-Eng/llama.cpp (Vulkan) and run the same-model comparison; the card is chosen by PCI bus through `vulkaninfo`. |
| `baseline-manifest.sh` | Writes the reproducibility manifest (commit, image, ROCm, hashes, card IDs, PCIe path). |

Shells on Windows: PowerShell strips the backslash from `sed 's/\r$//'` when it is passed over ssh, which turns it into
`s/r$//` and deletes a trailing `r` from every line. Copy LF files and do not "fix" line endings that way.
