#!/usr/bin/env bash
# designlabsrvr (run with sudo): pin or release the HBM memory clock of ONE MI25, for the decode two-state A/B test.
#   sudo bash mclk-pin.sh pin  [0000:12:00.0]   -> manual DPM, mclk level 3 (945 MHz = the card's stock maximum, not an overclock)
#   sudo bash mclk-pin.sh auto [0000:12:00.0]   -> back to auto (the production setting)
#   bash mclk-pin.sh show [bus]                 -> current state (no sudo needed)
# Touches only power_dpm_force_performance_level and pp_dpm_mclk. Power cap, core clocks and voltages are left alone.
# A reboot also returns the card to auto.
set -e
cmd=${1:-show}; D=/sys/bus/pci/devices/${2:-0000:12:00.0}
[ -e "$D/pp_dpm_mclk" ] || { echo "no amdgpu DPM controls at $D"; exit 1; }
case "$cmd" in
  pin)  echo manual > "$D/power_dpm_force_performance_level"; echo 3 > "$D/pp_dpm_mclk" ;;
  auto) echo auto > "$D/power_dpm_force_performance_level" ;;
  show) ;;
  *) echo "usage: $0 pin|auto|show [bus]"; exit 1 ;;
esac
echo "$(basename $D): level=$(cat $D/power_dpm_force_performance_level)  mclk=$(grep '\*' $D/pp_dpm_mclk | awk '{print $2}')  sclk=$(grep '\*' $D/pp_dpm_sclk | awk '{print $2}')"
