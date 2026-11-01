#!/usr/bin/env bash
# designlabsrvr: kernel traces (rocprofv3 --kernel-trace) + allocation logs for 6 Kindi launches on the x16 MI25.
# Each launch is classified fast/slow from its rep-1 decode speed; compare one of each afterwards.
# Also 2 launches WITHOUT the profiler, to check that tracing does not change the state mix or the speed.
cd ~/kindi/logs || exit 1
D=~/kindi/logs/prof; mkdir -p $D; DATA=$HOME/mi25/models/kindi
GA=(--device /dev/kfd --device /dev/dri --security-opt seccomp=unconfined --group-add "$(getent group video | cut -d: -f3)" --group-add "$(getent group render | cut -d: -f3)")
run() {   # tag, use_profiler(0/1)
  local C=(python3 /work/prof_bench.py "$1" 512 64)
  [ "$2" = 1 ] && C=(rocprofv3 --kernel-trace --output-format csv -d "/out/$1" -o trace -- "${C[@]}")
  docker run --rm "${GA[@]}" -u "$(id -u):$(id -g)" -e HOME=/tmp -v "$DATA:/data" -v "$HOME/kindi/logs:/work:ro" \
    -v "$HOME/kindi/kindi:/opt/kindi/kindi:ro" -v "$D:/out" \
    -e HIP_VISIBLE_DEVICES=0 -e ROCR_VISIBLE_DEVICES=0 -e KINDI_PACK=/data/pack27b -e KINDI_STATE_DIR=/data/state \
    -e KINDI_HEAD=exact -e KINDI_CARDS=1 -e KINDI_BLOCKING_SYNC=0 -e KINDI_REPEAT_STOP=1 -e PYTHONPATH=/opt/kindi \
    --entrypoint "${C[0]}" kindi-rocm:mi25 "${C[@]:1}" 2>&1 \
    | grep '^rep 1'
}
{
  echo "### prof $(date)"
  for i in 1 2 3 4 5 6; do echo "launch p$i (profiled): $(run p$i 1)"; done
  for i in 1 2; do echo "launch n$i (no profiler): $(run n$i 0)"; done
  echo "### done $(date)"
} > prof.log 2>&1
