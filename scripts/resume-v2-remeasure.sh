#!/usr/bin/env bash
# Resume v2 remeasurement from last good state (5a-5d applied).
# Remaining: 5e PM L1 SS, Order 3 VM102 RAM 3072.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NVRAM="${SCRIPT_DIR}/nvram-write-byte.sh"
MEASURE="${SCRIPT_DIR}/measure-idle-power.sh"
PVE="${PVE_HOST:-192.168.1.10}"
LOG="${SCRIPT_DIR}/../results/resume-v2-$(date +%Y%m%d).log"

export PLUG_SOURCE=z2m PLUG_SAMPLES=10 PLUG_INTERVAL=15
export QUICK_LOAD_MAX=1.0 QUICK_LOAD_CHECKS=2 QUICK_LOAD_INTERVAL=30

exec > >(tee -a "${LOG}") 2>&1

pve() { ssh -o ControlMaster=no "root@${PVE}" "$@"; }

nvram_reboot_measure() {
  local store="$1" off="$2" val="$3" slug="$4" label="$5" note="$6"
  echo "========== ${label} =========="
  pve 'bash -s' "$store" "$off" "$val" "$slug" < "$NVRAM"
  "$MEASURE" --measure --reboot --quick --label "$label" --note "$note"
}

echo "[$(date)] Resume v2 remeasurement starting"

pm_l1="$(pve "od -An -tx1 -j \$((4+0x025)) -N1 /sys/firmware/efi/efivars/AMD_PBS_SETUP-a339d746-f678-49b3-9fc7-54ce0f9df226" | tr -d ' ')"
if [[ "${pm_l1}" != "03" ]]; then
  nvram_reboot_measure AMD_PBS_SETUP 0x025 0x03 apply-5e "order5e-pm-l1ss-v2" "PM L1 SS on; load+ZFS gated"
else
  echo "PM L1 SS already 0x03; measuring only"
  "$MEASURE" --measure --wait-idle --label order5e-pm-l1ss-v2 --note "PM L1 SS already on; measure only"
fi

ram="$(pve "qm config 102 | awk -F': ' '/^memory:/{print \$2}'")"
if [[ "${ram}" != "3072" ]]; then
  echo "========== order3-vm102-ram-3072-v2 =========="
  pve 'qm set 102 --memory 3072 && qm reboot 102'
  "$MEASURE" --measure --wait-idle --label order3-vm102-ram-3072-v2 --note "RAM 4096 to 3072; load+ZFS gated"
else
  echo "VM102 already 3072 MiB; measuring only"
  "$MEASURE" --measure --wait-idle --label order3-vm102-ram-3072-v2 --note "RAM already 3072; measure only"
fi

echo "[$(date)] Done. CSV tail:"
tail -5 "${SCRIPT_DIR}/../results/power-tuning.csv"
