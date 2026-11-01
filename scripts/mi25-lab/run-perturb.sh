#!/usr/bin/env bash
# designlabsrvr: allocation-perturbation experiment. 10 rounds x 3 conditions (A: no dummy, B: 1 GiB, C: 4 GiB dummy held
# through the run), order rotated each round (ABC, BCA, CAB, ...). Before each launch: wait until the card's VRAM use is
# back to idle (< 64 MiB, max 60 s; time recorded) and take a read-only debugfs dump (free, clear_free, largest free block).
cd ~/kindi/logs || exit 1
D=~/kindi/logs/perturb; mkdir -p $D; DATA=$HOME/mi25/models/kindi; BUS=0000:12:00.0; H=/sys/bus/pci/devices/$BUS
GA=(--device /dev/kfd --device /dev/dri --security-opt seccomp=unconfined --group-add "$(getent group video | cut -d: -f3)" --group-add "$(getent group render | cut -d: -f3)")
OUT=$D/results.csv
echo "round,order,cond,dummy_mb,release_wait_s,used_mib_at_start,free_mib,clear_free_mib,largest_free_order,decode_tps,prefill_tps,weights_va,dummy_va,time" > $OUT
conds=(A B C); mb=(0 1024 4096)
for r in $(seq 1 10); do
  for k in 0 1 2; do
    i=$(( (k + r - 1) % 3 )); c=${conds[$i]}; t=r${r}$c
    w=0; while [ $(cat $H/mem_info_vram_used) -gt $((64 << 20)) ] && [ $w -lt 60 ]; do sleep 1; w=$((w + 1)); done
    used=$(( $(cat $H/mem_info_vram_used) >> 20 ))
    sudo -n /usr/local/sbin/gpu-vmdump $BUS > $D/$t-before.txt 2>&1
    fr=$(grep -o 'free: [0-9]*MiB, clear_free: [0-9]*MiB' $D/$t-before.txt | tr -dc '0-9 ' | awk '{print $1","$2}')
    lo=$(grep -E '^order-' $D/$t-before.txt | awk '$NF > 0 {sub(/order-/, "", $1); sub(/:$/, "", $1); print $1 + 0; exit}')
    res=$(docker run --rm "${GA[@]}" -u "$(id -u):$(id -g)" -e HOME=/tmp -v "$DATA:/data" -v "$HOME/kindi/logs:/work:ro" \
      -v "$HOME/kindi/kindi:/opt/kindi/kindi:ro" \
      -e HIP_VISIBLE_DEVICES=0 -e ROCR_VISIBLE_DEVICES=0 -e KINDI_PACK=/data/pack27b -e KINDI_STATE_DIR=/data/state \
      -e KINDI_HEAD=exact -e KINDI_CARDS=1 -e KINDI_BLOCKING_SYNC=0 -e KINDI_REPEAT_STOP=1 -e PYTHONPATH=/opt/kindi \
      --entrypoint python3 kindi-rocm:mi25 /work/perturb_bench.py $t ${mb[$i]} 512 64 2>&1 | grep '^RESULT')
    set -- $res
    echo "$r,$k,$c,${mb[$i]},$w,$used,$fr,$lo,${8},${6},${10},${12},$(date +%T)" >> $OUT
  done
done
echo "# done $(date)" >> $OUT
