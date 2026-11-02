#!/usr/bin/env bash
# designlabsrvr: does an in-process rebuild flip a SLOW start? 10 processes x 4 builds each; hold 64 MiB in processes
# 1-5 and 1024 MiB in 6-10 during each rebuild. Each process line shows the state sequence of its builds.
cd ~/kindi/logs || exit 1
OUT=selfcheck-probe2.log; : > $OUT
for p in $(seq 1 10); do
  h=64; [ $p -gt 5 ] && h=1024
  w=0; while [ $(cat /sys/bus/pci/devices/0000:12:00.0/mem_info_vram_used) -gt $((64 << 20)) ] && [ $w -lt 60 ]; do sleep 1; w=$((w+1)); done
  echo "### process $p hold ${h} MiB $(date +%T)" >> $OUT
  SRC=$HOME/kindi bash kpy.sh selfcheck_probe.py 4 $h 2>&1 | grep '^build' >> $OUT
done
echo "### done $(date)" >> $OUT
