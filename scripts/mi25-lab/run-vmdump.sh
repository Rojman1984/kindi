#!/usr/bin/env bash
# designlabsrvr: for 10 Kindi launches on the x16 MI25, dump amdgpu debugfs (read-only, sudo gpu-vmdump) BEFORE the
# launch and WHILE it holds its weights; record the launch's decode speed. Then compare fast vs slow layouts.
cd ~/kindi/logs || exit 1
D=~/kindi/logs/vm; mkdir -p $D; DATA=$HOME/mi25/models/kindi; BUS=0000:12:00.0
GA=(--device /dev/kfd --device /dev/dri --security-opt seccomp=unconfined --group-add "$(getent group video | cut -d: -f3)" --group-add "$(getent group render | cut -d: -f3)")
echo "tag,decode_tps,prefill_tps" > $D/runs.csv
for i in $(seq 1 10); do
  t=v$i; rm -f $D/hold-$t.*
  sudo -n /usr/local/sbin/gpu-vmdump $BUS > $D/$t-before.txt 2>&1
  docker run --rm "${GA[@]}" -u "$(id -u):$(id -g)" -e HOME=/tmp -v "$DATA:/data" -v "$HOME/kindi/logs:/work:ro" \
    -v "$HOME/kindi/kindi:/opt/kindi/kindi:ro" -v "$D:/out" \
    -e HIP_VISIBLE_DEVICES=0 -e ROCR_VISIBLE_DEVICES=0 -e KINDI_PACK=/data/pack27b -e KINDI_STATE_DIR=/data/state \
    -e KINDI_HEAD=exact -e KINDI_CARDS=1 -e KINDI_BLOCKING_SYNC=0 -e KINDI_REPEAT_STOP=1 -e PYTHONPATH=/opt/kindi \
    --entrypoint python3 kindi-rocm:mi25 /work/hold_bench.py $t 512 64 > $D/$t-run.txt 2>&1 &
  pid=$!
  for k in $(seq 1 600); do [ -e $D/hold-$t.ready ] && break; sleep 0.2; done
  sudo -n /usr/local/sbin/gpu-vmdump $BUS > $D/$t-held.txt 2>&1
  touch $D/hold-$t.go; wait $pid
  r=$(grep '^rep 1' $D/$t-run.txt)
  echo "$t,$(echo $r | cut -d' ' -f5),$(echo $r | cut -d' ' -f3)" >> $D/runs.csv
done
echo "# done $(date)" >> $D/runs.csv
