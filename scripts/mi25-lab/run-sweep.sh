#!/usr/bin/env bash
# designlabsrvr: 5 rounds x 6 configs, order rotated each round; 27B, 2,048-token prompt + 64 decode, repo code (fbc0525).
# One line per run in logs/sweep.csv with the card's power / temps / clocks sampled right after the run.
cd ~/kindi/logs || exit 1
OUT=sweep.csv; H=/sys/bus/pci/devices/0000:12:00.0
hw=$(ls -d $H/hwmon/hwmon* | head -1)
names=(A_upstream B_g5l C_default D_g5l_nodp4a E_nodp4a F_default_nodp4a)
envs=("KINDI_G5L=0 KINDI_CHUNK_Q8=1" "KINDI_G5L=1 KINDI_CHUNK_Q8=1" "" "KINDI_G5L=1 KINDI_CHUNK_Q8=1 KINDI_DP4A=0" "KINDI_G5L=0 KINDI_CHUNK_Q8=1 KINDI_DP4A=0" "KINDI_DP4A=0")
echo "round,order,config,prefill_tps,decode_tps,power_w,edge_c,junction_c,mem_c,sclk,mclk,load1,time" > $OUT
for r in 1 2 3 4 5; do
  for k in 0 1 2 3 4 5; do
    i=$(( (k + r - 1) % 6 ))
    res=$(KENV="${envs[$i]}" SRC=$HOME/kindi bash kpy.sh pp_bench.py 2048 64 2>&1 | grep '^rep 1')
    pf=$(echo "$res" | sed -n 's/.*prefill [0-9]* tok \([0-9.]*\) tok\/s.*/\1/p')
    dc=$(echo "$res" | sed -n 's/.*decode [0-9]* tok \([0-9.]*\) tok\/s.*/\1/p')
    pw=$(awk '{printf "%.1f", $1/1e6}' $hw/power1_average 2>/dev/null)
    t1=$(( $(cat $hw/temp1_input 2>/dev/null || echo 0) / 1000 )); t2=$(( $(cat $hw/temp2_input 2>/dev/null || echo 0) / 1000 )); t3=$(( $(cat $hw/temp3_input 2>/dev/null || echo 0) / 1000 ))
    sc=$(grep '\*' $H/pp_dpm_sclk | awk '{print $2}'); mc=$(grep '\*' $H/pp_dpm_mclk | awk '{print $2}')
    echo "$r,$k,${names[$i]},$pf,$dc,$pw,$t1,$t2,$t3,$sc,$mc,$(cut -d' ' -f1 /proc/loadavg),$(date +%T)" >> $OUT
  done
done
echo "# done $(date)" >> $OUT
