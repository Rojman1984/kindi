#!/usr/bin/env bash
# designlabsrvr: run a python file from ~/kindi/logs inside kindi-rocm:mi25 on ROCm agent ${AGENT:-0}.
#   bash kpy.sh probe.py [args]      (extra env: KENV="A=1 B=2"; code: SRC=~/kindi mounts the repo's kindi/ over the image's)
f=$1; shift
DATA=$HOME/mi25/models/kindi
GA=(--device /dev/kfd --device /dev/dri --security-opt seccomp=unconfined --group-add "$(getent group video | cut -d: -f3)" --group-add "$(getent group render | cut -d: -f3)")
E=(); for e in $KENV; do E+=(-e "$e"); done
M=(); [ -n "$SRC" ] && M=(-v "$SRC/kindi:/opt/kindi/kindi:ro")
docker run --rm "${GA[@]}" -u "$(id -u):$(id -g)" -e HOME=/tmp -v "$DATA:/data" -v "$HOME/kindi/logs:/work:ro" "${M[@]}" \
  -e HIP_VISIBLE_DEVICES=0 -e ROCR_VISIBLE_DEVICES=${AGENT:-0} -e KINDI_PACK=${PACK:-/data/pack27b} -e KINDI_STATE_DIR=/data/state \
  -e KINDI_HEAD=exact -e KINDI_CARDS=1 -e KINDI_BLOCKING_SYNC=0 -e KINDI_REPEAT_STOP=1 -e PYTHONPATH=/opt/kindi "${E[@]}" \
  --entrypoint python3 kindi-rocm:mi25 "/work/$f" "$@"
