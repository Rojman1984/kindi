#!/usr/bin/env bash
# designlabsrvr: same-model comparison on the x16 MI25 - Bonsai 27B PTQ1_0 in Prism llama.cpp (Vulkan) vs Kindi.
# llama-bench: pp 512/2048/8192 and tg64 at depth 0 and 2048, 5 reps; q8_0 K/V + flash attention (Kindi's K/V is q8_0);
# load-mode none (no mmap, as production). Then Kindi at 512 / 8192 (2048 is in sweep.csv / twostate.csv), 3 launches each.
cd ~/kindi/logs || exit 1
OUT=prism-bench.log; BUS=12; P=~/mi25/llama.cpp-prism; M=~/mi25/models/kindi/Ternary-Bonsai-2-27B-PTQ1_0.gguf
# Vulkan index of PCI bus 0x12, from vulkaninfo's VK_EXT_pci_bus_info (as gpu-launch does)
VK=$(vulkaninfo 2>/dev/null | awk '/^GPU[0-9]+:/ {g=substr($1,4,length($1)-4)} /^[ \t]*pciBus/ {if ($3 == strtonum("0x'$BUS'")) print g}' | head -1)
{
  echo "### prism bench $(date)"
  echo "commit: $(cd $P && git rev-parse --short HEAD) $(cd $P && git describe --tags --always)"
  echo "card: 0000:$BUS:00.0 -> Vulkan index $VK (GGML_VK_VISIBLE_DEVICES=$VK, so it is Vulkan0 inside llama-bench)"
  export GGML_VK_VISIBLE_DEVICES=$VK
  $P/build/bin/llama-bench --list-devices 2>&1 | grep Vulkan
  $P/build/bin/llama-bench -m $M -dev Vulkan0 -ngl 99 -fa on -ctk q8_0 -ctv q8_0 -lm none -p 512,2048,8192 -n 64 -r 5 2>&1 | grep -v -e '^load_backend' -e '^ggml_vulkan'
  echo "### decode at depth 2048 (matches Kindi's measurement point)"
  $P/build/bin/llama-bench -m $M -dev Vulkan0 -ngl 99 -fa on -ctk q8_0 -ctv q8_0 -lm none -p 0 -n 64 -d 2048 -r 5 2>&1 | grep -v -e '^load_backend' -e '^ggml_vulkan'
  unset GGML_VK_VISIBLE_DEVICES
  echo "### kindi (gfx900 defaults, fbc0525) $(date +%T)"
  for n in 512 8192; do for i in 1 2 3; do
    echo "kindi N=$n launch $i: $(SRC=$HOME/kindi bash kpy.sh pp_bench_t.py $n 64 2>&1 | grep '^rep 1' | cut -d' ' -f3-6)"
  done; done
  echo "### done $(date)"
} > $OUT 2>&1
