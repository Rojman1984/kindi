#!/usr/bin/env bash
# designlabsrvr: after run-prism-bench.sh - (1) Kindi at 512 (ctx floor fixed), 3 launches; (2) Prism decode at depth
# 2048 in 8 SEPARATE launches, to see whether llama.cpp also has launch-level fast/slow states (llama-bench's -r reps
# all run in one process, so they cannot show it).
cd ~/kindi/logs || exit 1
until grep -q '^### done' prism-bench.log; do sleep 15; done
OUT=prism-followup.log; P=~/mi25/llama.cpp-prism; M=~/mi25/models/kindi/Ternary-Bonsai-2-27B-PTQ1_0.gguf
VK=$(vulkaninfo 2>/dev/null | awk '/^GPU[0-9]+:/ {g=substr($1,4,length($1)-4)} /^[ \t]*pciBus/ {if ($3 == strtonum("0x12")) print g}' | head -1)
{
  echo "### kindi N=512 $(date +%T)"
  for i in 1 2 3; do echo "kindi N=512 launch $i: $(SRC=$HOME/kindi bash kpy.sh pp_bench_t.py 512 64 2>&1 | grep '^rep 1' | cut -d' ' -f3-6)"; done
  echo "### prism tg64 @ d2048, separate launches (Vulkan index $VK = 0000:12:00.0) $(date +%T)"
  for i in 1 2 3 4 5 6 7 8; do
    r=$(GGML_VK_VISIBLE_DEVICES=$VK $P/build/bin/llama-bench -m $M -dev Vulkan0 -ngl 99 -fa on -ctk q8_0 -ctv q8_0 -lm none \
        -p 0 -n 64 -d 2048 -r 2 -o csv 2>/dev/null | tail -1 | awk -F, '{print $(NF-1)}' | tr -d '"')
    echo "prism launch $i: tg64@d2048 $r tok/s"
  done
  echo "### done $(date)"
} > $OUT 2>&1
