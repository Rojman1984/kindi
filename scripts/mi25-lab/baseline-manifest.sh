#!/usr/bin/env bash
# designlabsrvr: write the reproducibility manifest for the gfx900 baseline (read-only).
cd ~/kindi || exit 1
D=$HOME/mi25/models/kindi; H=/sys/bus/pci/devices/0000:12:00.0; hw=$(ls -d $H/hwmon/hwmon* | head -1)
{
echo "# Baseline manifest: mi25-gfx900-bonsai27b-baseline-2026-11-01"
echo "date: $(date -Is)"
echo "commit: $(git rev-parse HEAD) ($(git log -1 --format=%s))"
echo "image: kindi-rocm:mi25 $(docker image inspect kindi-rocm:mi25 --format '{{.Id}} created {{.Created}}')"
echo "image_code_note: image holds pre-fbc0525 Python; baseline runs mount the repo's kindi/ (SRC=\$HOME/kindi)"
echo "rocm: $(docker run --rm --entrypoint cat kindi-rocm:mi25 /opt/rocm/.info/version 2>/dev/null)"
echo "cupy: $(docker run --rm --entrypoint python3 kindi-rocm:mi25 -c 'import cupy; print(cupy.__version__)' 2>/dev/null)"
echo "host: $(hostname) kernel $(uname -r); $(lscpu | sed -n 's/^Model name: *//p'); RAM $(free -g | awk '/Mem:/{print $2}') GiB"
echo "gguf_sha256:"; for f in $D/*.gguf; do echo "  $(sha256sum $f | cut -c1-64)  $(basename $f)"; done
echo "pack27b_sha256 (sorted file hashes, then hashed):"
echo "  $(cd $D/pack27b && find . -type f ! -name '*.lock' -print0 | sort -z | xargs -0 sha256sum | sha256sum | cut -c1-64)  ($(du -sh $D/pack27b | cut -f1), $(find $D/pack27b -type f | wc -l) files)"
echo "env (gfx900 defaults, no flags needed at fbc0525): KINDI_G5L=1 KINDI_CHUNK_Q8=0 KINDI_DP4A=default(1) KINDI_HEAD=exact KINDI_CARDS=1 KINDI_BLOCKING_SYNC=0"
echo "card: 0000:12:00.0 (CPU x16 slot, ROCm agent 0) unique_id=$(cat $H/unique_id 2>/dev/null) vbios=$(cat $H/vbios_version 2>/dev/null)"
echo "power_cap_w: $(awk '{print $1/1e6}' $hw/power1_cap 2>/dev/null)  dpm_level: $(cat $H/power_dpm_force_performance_level)"
echo "pcie_path:"; p=$(readlink -f $H); while [ "$(basename $p)" != pci0000:00 ]; do b=$(basename $p); [ -f $p/current_link_width ] && echo "  $b x$(cat $p/current_link_width) $(cat $p/current_link_speed)"; p=$(dirname $p); done
echo "other_gpus: 0000:24:00.0, 0000:27:00.0 (MI25, chipset x1); 0000:30:00.0 (4600G iGPU, gfx90c, unused)"
echo "verify: 27B 4/4 token-exact (logs/defaults.log); 2B 4/4 (logs/verify.log)"
echo "bench: 2,048-token prompt + 64 decode, 5 rounds x 6 configs rotated: logs/sweep.csv"
} > logs/baseline-manifest.txt 2>&1
cat logs/baseline-manifest.txt
