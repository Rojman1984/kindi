#!/usr/bin/env bash
# designlabsrvr: is the decode two-state (13.9 vs 15.1 tok/s) the HBM clock? 10 launches on auto, 10 with mclk pinned
# at 945 MHz (stock max), then back to auto. A 100 ms sampler logs clocks/power/temps; per launch the decode window's
# samples are summarised. Runs after the Prism build finishes. Default config (fbc0525), 27B, x16 card.
cd ~/kindi/logs || exit 1
BUS=0000:12:00.0; H=/sys/bus/pci/devices/$BUS; hw=$(ls -d $H/hwmon/hwmon* | head -1)
OUT=twostate.csv; S=twostate-samples.txt
until grep -q '^### done' build-prism.log 2>/dev/null; do sleep 30; done
trap 'sudo -n /usr/local/sbin/mclk-pin auto >/dev/null 2>&1' EXIT
sample() { while :; do
  echo "$(date +%s.%N | cut -c1-14) $(grep '\*' $H/pp_dpm_mclk | awk '{print $2}') $(grep '\*' $H/pp_dpm_sclk | awk '{print $2}') $(cat $hw/power1_input) $(cat $hw/temp2_input)"
  sleep 0.1; done; }
summ() {   # window start, end -> "mclk-modes sclk-modes avg_power_w max_junction_c n"
  awk -v a=$1 -v b=$2 '$1>=a && $1<=b {m[$2]++; s[$3]++; p+=$4; if($5>t)t=$5; n++}
    END {for(k in m) mm=mm k":"m[k]" "; for(k in s) ss=ss k":"s[k]" "; printf "%s| %s| %.1f W | %d C | n=%d", mm, ss, p/n/1e6, t/1000, n}' $S; }
echo "phase,launch,prefill_tps,decode_tps,decode_window_mclk,decode_window_sclk,avg_power,max_junction,samples,time" > $OUT
: > $S; sample >> $S & SP=$!
for phase in auto pinned; do
  if [ $phase = pinned ]; then sudo -n /usr/local/sbin/mclk-pin pin >> $OUT.log; else sudo -n /usr/local/sbin/mclk-pin auto >> $OUT.log; fi
  for i in $(seq 1 10); do
    r=$(SRC=$HOME/kindi bash kpy.sh pp_bench_t.py 2048 64 2>&1 | grep '^rep 1')
    set -- $r
    s=$(summ ${11} ${12} | tr ',' ';')   # fields: rep 1 prefill_tps $4 decode_tps $6 pf_win $8 $9 dc_win $11 $12
    echo "$phase,$i,$4,$6,$(echo "$s" | cut -d'|' -f1),$(echo "$s" | cut -d'|' -f2),$(echo "$s" | cut -d'|' -f3),$(echo "$s" | cut -d'|' -f4),$(echo "$s" | cut -d'|' -f5),$(date +%T)" >> $OUT
  done
done
kill $SP
sudo -n /usr/local/sbin/mclk-pin auto >> $OUT.log
echo "# done $(date)" >> $OUT
