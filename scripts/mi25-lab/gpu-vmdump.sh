#!/usr/bin/env bash
# designlabsrvr (run with sudo; READ-ONLY): dump amdgpu memory-manager state for ONE GPU from debugfs, to compare the
# physical VRAM placement of Kindi's weight buffer in a fast vs a slow launch.
#   sudo gpu-vmdump [0000:12:00.0]
# Reads only: amdgpu_vram_mm (drm_buddy free/used blocks), amdgpu_gem_info (buffers per process), amdgpu_vm_info (if
# present). Writes nothing anywhere; output goes to stdout.
set -e
BUS=${1:-0000:12:00.0}
case "$BUS" in [0-9a-f][0-9a-f][0-9a-f][0-9a-f]:[0-9a-f][0-9a-f]:[0-9a-f][0-9a-f].[0-7]) ;; *) echo "bad PCI address"; exit 1 ;; esac
mountpoint -q /sys/kernel/debug || { echo "debugfs not mounted"; exit 1; }
for d in /sys/kernel/debug/dri/[0-9]*; do
  if grep -q "$BUS" "$d/name" 2>/dev/null; then
    echo "### $d ($(cat $d/name))  $(date -Is)"
    for f in amdgpu_vram_mm amdgpu_gem_info amdgpu_vm_info; do
      [ -r "$d/$f" ] && { echo "### $f"; cat "$d/$f"; }
    done
    exit 0
  fi
done
echo "no debugfs dri node for $BUS"; exit 1
