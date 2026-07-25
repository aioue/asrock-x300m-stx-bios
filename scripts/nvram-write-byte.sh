#!/usr/bin/env bash
# Write one byte to a UEFI VarStore on P2.20B after backup and validation.
# Usage: nvram-write-byte.sh AmdSetup 0x0F9 0x00 "HD Audio off"
set -euo pipefail

VARSTORE="${1:?varstore}"
OFFSET_HEX="${2:?offset}"
VALUE_HEX="${3:?value}"
LABEL="${4:-unnamed}"

ATTR_BYTES=4
BACKUP_DIR="/root/nvram-backup/$(date +%Y%m%d-%H%M%S)-${LABEL// /_}"
EFIVARS="/sys/firmware/efi/efivars"

declare -A FILES=(
  [AmdSetup]="AmdSetup-3a997502-647a-4c82-998e-52ef9486a247"
  [AMD_PBS_SETUP]="AMD_PBS_SETUP-a339d746-f678-49b3-9fc7-54ce0f9df226"
)

FILE="${FILES[$VARSTORE]:-}"
[[ -n "${FILE}" ]] || { echo "Unsupported varstore: ${VARSTORE}" >&2; exit 1; }

OFFSET=$((OFFSET_HEX))
VALUE=$((VALUE_HEX))
VARFILE="${EFIVARS}/${FILE}"

backup_var() {
  local src="$1" dest="$2"
  dd if="${src}" of="${dest}" bs=4096 count=1 status=none
}

mkdir -p "${BACKUP_DIR}"
backup_var "${VARFILE}" "${BACKUP_DIR}/${FILE}"
echo "Backup: ${BACKUP_DIR}/${FILE}"

CURRENT_HEX="$(od -An -tx1 -j $((ATTR_BYTES + OFFSET)) -N 1 "${VARFILE}" | tr -d ' \n')"
CURRENT=$((16#${CURRENT_HEX}))
echo "Current ${VARSTORE} ${OFFSET_HEX} = 0x$(printf '%02X' "${CURRENT}")"

if [[ "${CURRENT}" -eq "${VALUE}" ]]; then
  echo "Already 0x$(printf '%02X' "${VALUE}") — no write"
  exit 0
fi

chattr -i "${VARFILE}" 2>/dev/null || true
TMP="$(mktemp)"
backup_var "${VARFILE}" "${TMP}"
printf "\\x$(printf '%02x' "${VALUE}")" | dd of="${TMP}" bs=1 seek=$((ATTR_BYTES + OFFSET)) count=1 conv=notrunc status=none
dd if="${TMP}" of="${VARFILE}" bs=4096 count=1 status=none
rm -f "${TMP}"

VERIFY_HEX="$(od -An -tx1 -j $((ATTR_BYTES + OFFSET)) -N 1 "${VARFILE}" | tr -d ' \n')"
VERIFY=$((16#${VERIFY_HEX}))
if [[ "${VERIFY}" -ne "${VALUE}" ]]; then
  echo "VERIFY FAILED: got 0x$(printf '%02X' "${VERIFY}")" >&2
  exit 1
fi

echo "Wrote ${VARSTORE} ${OFFSET_HEX}: 0x$(printf '%02X' "${CURRENT}") -> 0x$(printf '%02X' "${VALUE}")"
echo "Reboot required for BIOS to apply."
