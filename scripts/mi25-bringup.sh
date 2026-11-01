#!/usr/bin/env bash
# Kindi on the MI25 (gfx900, wave64): staged bring-up for designlabsrvr. Each stage is safe to re-run.
#
#   scripts/mi25-bringup.sh check            # read-only: KFD nodes, PCIe atomics, links, Docker
#   scripts/mi25-bringup.sh build            # kindi-rocm:mi25 image (ROCm 6.3.3 + CuPy built for gfx900)
#   scripts/mi25-bringup.sh models           # download 2B + 27B (sha256-checked) and convert both packs
#   scripts/mi25-bringup.sh verify BUS [2b|27b]   # token-exact check vs llama.cpp on one card  <- the real gate
#   scripts/mi25-bringup.sh bench  BUS [2b|27b]   # decode / prefill speed
#   scripts/mi25-bringup.sh serve  BUS [27b] [PORT]   # OpenAI API on 127.0.0.1:PORT (default 8094)
#
# BUS is the card's PCI address as `check` prints it (e.g. 0000:0b:00.0). Stop llama-swap's model on that card first
# (e.g. `model stop qwen3.8-27b`): Kindi sizes its context to the FREE card memory.
set -euo pipefail

REPO=$(cd "$(dirname "$0")/.." && pwd)
DATA=${KINDI_DATA:-$HOME/mi25/models/kindi}          # on the NVMe
IMAGE=${KINDI_IMAGE:-kindi-rocm:mi25}
HF=https://huggingface.co/prism-ml
declare -A GGUF SHA
GGUF[2b]=Ternary-Bonsai-2-2B-PTQ1_0.gguf;   SHA[2b]=36061ad406df8a4903a6db005be350c50fabfaf717f9ef0acf4b76adcd9929fa
GGUF[27b]=Ternary-Bonsai-2-27B-PTQ1_0.gguf; SHA[27b]=53107f530aa52eb00912263ab1ee29bd199261c87cd7b4ad4ca1318c1fe33ee3

say() { printf '\n== %s\n' "$*"; }

# ROCr numbers GPU agents in KFD topology order (CPU nodes skipped). The 4600G iGPU (gfx90c) is one of them, so the
# index is resolved from the bus address every time, never assumed.
gpu_table() {
  local i=0 p g gfx r dv bus
  for p in $(ls -d /sys/class/kfd/kfd/topology/nodes/* | sort -t/ -k8 -n); do
    g=$(awk '$1=="gfx_target_version"{print $2}' "$p/properties"); [ "${g:-0}" -gt 0 ] || continue
    gfx=$(printf 'gfx%d%d%x' $((g / 10000)) $((g / 100 % 100)) $((g % 100)))
    r=$(awk '$1=="drm_render_minor"{print $2}' "$p/properties"); dv=/sys/class/drm/renderD$r/device
    bus=$(basename "$(readlink -f "$dv")")
    echo "$i $bus $gfx $(( $(cat "$dv/mem_info_vram_total" 2>/dev/null || echo 0) / 1048576 ))"
    i=$((i + 1))
  done
}
idx_of() {
  local row; row=$(gpu_table | awk -v b="$1" '$2==b') || true
  [ -n "$row" ] || { echo "no ROCm GPU at $1 (run: $0 check)" >&2; exit 1; }
  [ "$(echo "$row" | awk '{print $3}')" = gfx900 ] || { echo "$1 is not a gfx900 card: $row" >&2; exit 1; }
  echo "$row" | awk '{print $1}'
}

drun() {   # drun IDX [docker args...] -- kindi args...
  local idx=$1; shift
  local g; GA=(--device /dev/kfd --device /dev/dri --security-opt seccomp=unconfined)
  for g in video render; do gid=$(getent group $g | cut -d: -f3 || true); [ -z "$gid" ] || GA+=(--group-add "$gid"); done
  docker run --rm "${GA[@]}" -u "$(id -u):$(id -g)" -e HOME=/tmp -v "$DATA:/data" \
    -e HIP_VISIBLE_DEVICES=0 -e ROCR_VISIBLE_DEVICES="$idx" \
    -e KINDI_STATE_DIR=/data/state -e KINDI_HEAD=exact -e KINDI_REPEAT_STOP=1 -e KINDI_CARDS=1 \
    -e KINDI_BLOCKING_SYNC=0 "$@"
}

case "${1:-check}" in
check)
  say "ROCm GPU agents (index bus gfx VRAM-MiB)"; gpu_table
  say "Cards that KFD skipped (Vega 10 needs PCIe atomics; chipset/x1 paths may refuse them)"
  { sudo -n dmesg 2>/dev/null || journalctl -k -b --no-pager 2>/dev/null; } | grep -i -E 'kfd.*(skipped|atomic)|rejects atomics' \
    || echo "none reported (or kernel log not readable without sudo)"
  say "PCIe link of each AMD GPU (current / max)"
  for d in $(lspci -D -d 1002: | awk '/VGA|Display|3D|Processing/{print $1}'); do
    s=/sys/bus/pci/devices/$d
    echo "$d $(cat $s/current_link_speed) x$(cat $s/current_link_width) / $(cat $s/max_link_speed) x$(cat $s/max_link_width)  $(lspci -s "$d" | cut -d: -f3- | cut -c1-60)"
  done
  say "amdgpu / docker"; uname -r; docker --version; ls -l /dev/kfd
  ;;
build)
  say "building $IMAGE (ROCm 6.3.3 base, CuPy compiled for gfx900; ~6 GB download, 30-45 min)"
  docker build -t "$IMAGE" --build-arg AMDGPU_TARGETS=gfx900 -f "$REPO/docker/Dockerfile.rocm" "$REPO"
  ;;
models)
  mkdir -p "$DATA/state"
  for m in 2b 27b; do
    f=$DATA/${GGUF[$m]}
    if [ ! -f "$f.sha256-ok" ]; then
      say "download ${GGUF[$m]}"; curl -fL --retry 3 -C - -o "$f.part" "$HF/Ternary-Bonsai-2-${m^^}-gguf/resolve/main/${GGUF[$m]}"
      [ "$(sha256sum "$f.part" | cut -d' ' -f1)" = "${SHA[$m]}" ] || { echo "sha256 mismatch: $f.part"; exit 1; }
      mv "$f.part" "$f"; touch "$f.sha256-ok"
    fi
    [ -f "$DATA/pack$m/manifest.json" ] || { say "convert $m"; docker run --rm -u "$(id -u):$(id -g)" -e HOME=/tmp \
      -v "$DATA:/data" "$IMAGE" convert "/data/${GGUF[$m]}" --out "/data/pack$m"; }
  done
  ;;
verify|bench)
  idx=$(idx_of "${2:?BUS}"); m=${3:-2b}
  say "$1 $m on ${2} (ROCm agent $idx)"
  drun "$idx" -e KINDI_PACK="/data/pack$m" -e KINDI_CTX=8192 "$IMAGE" "$1"
  ;;
serve)
  idx=$(idx_of "${2:?BUS}"); m=${3:-27b}; port=${4:-8094}
  docker rm -f "kindi-$m" >/dev/null 2>&1 || true
  GA=(--device /dev/kfd --device /dev/dri --security-opt seccomp=unconfined)
  for g in video render; do gid=$(getent group $g | cut -d: -f3 || true); [ -z "$gid" ] || GA+=(--group-add "$gid"); done
  docker run -d --name "kindi-$m" --restart unless-stopped "${GA[@]}" -u "$(id -u):$(id -g)" -e HOME=/tmp \
    -v "$DATA:/data" -p "127.0.0.1:$port:8093" -e HIP_VISIBLE_DEVICES=0 -e ROCR_VISIBLE_DEVICES="$idx" \
    -e KINDI_PACK="/data/pack$m" -e KINDI_STATE_DIR=/data/state -e KINDI_HEAD=exact -e KINDI_REPEAT_STOP=1 \
    -e KINDI_CARDS=1 -e KINDI_BLOCKING_SYNC=0 -e KINDI_CTX=65536 -e KINDI_MAX_TOKENS=65536 "$IMAGE"
  echo "kindi-$m starting on 127.0.0.1:$port (first start compiles kernels for gfx900; watch: docker logs -f kindi-$m)"
  ;;
*) sed -n 2,12p "$0"; exit 1 ;;
esac
