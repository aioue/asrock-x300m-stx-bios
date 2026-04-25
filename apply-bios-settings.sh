#!/usr/bin/env bash
#
# Safely apply BIOS NVRAM settings from a running Linux system.
#
# Reads UEFI NVRAM variables via efivarfs, validates that byte offsets contain
# expected values (proving the IFR layout matches), then writes desired values
# with read-modify-write. Aborts on any mismatch.
#
# Usage:
#   ./apply-bios-settings.sh [--apply]
#
# Without --apply, runs in dry-run mode (read-only).
# Requires root and a UEFI-booted system with efivarfs mounted.
#
# Target: ASRock X300M-STX, BIOS P2.20B (X3MSTX_2.20B)
# CPU: AMD Ryzen 5 PRO 5650G (Cezanne / Zen 3)
#
# Safety status:
#   Live P2.20B read-back on 2026-04-25 found that the expected Setup efivar is
#   not exposed and AmdSetup offset 0x0FC reads 0xFF, outside the IFR values for
#   Power Supply Idle Control. Keep --apply disabled until this script is split
#   or reworked around those live findings.

set -euo pipefail

# --- NVRAM variable identifiers ---
# Each UEFI NVRAM variable is a file under /sys/firmware/efi/efivars/
# named: <VarName>-<GUID>
# The file contains 4 bytes of EFI attributes followed by the variable data.
ATTR_BYTES=4
TARGET_BIOS="P2.20B"

SETUP_VAR="Setup-ec87d643-eba4-4bb5-a1e5-3f3e36b20da9"
SETUP_SIZE=589

AMDSETUP_VAR="AmdSetup-3a997502-647a-4c82-998e-52ef9486a247"
AMDSETUP_SIZE_MIN=1447  # RV uses 1447, RN uses 1448

PBS_VAR="AMD_PBS_SETUP-a339d746-f678-49b3-9fc7-54ce0f9df226"
PBS_SIZE=128

EFIVARS="/sys/firmware/efi/efivars"
APPLY=false
LOG_FILE="/var/log/bios-settings-$(date +%Y%m%d-%H%M%S).log"

# --- Desired settings ---
# Format: VARFILE OFFSET SETTING_NAME DESIRED_VALUE VALID_VALUES(space-separated)
#
# VALID_VALUES is the set of values IFR says are legal at this offset.
# Before writing, the script checks the current value is in this set.
# If not, the offset layout has changed and we abort.

SETTINGS=(
    # === Setup variable (EC87D643) ===
    # Fusion Message C State: 0=Disabled(default), 1=Enabled
    "${SETUP_VAR}|0x090|Fusion Message C State|0x01|0x00 0x01"

    # Fusion Message C Multi-Core: 0=Disabled(default), 1=Enabled
    "${SETUP_VAR}|0x08F|Fusion Message C Multi-Core|0x01|0x00 0x01"

    # Deep Sleep: 0=Disabled(default), 1=Enabled
    "${SETUP_VAR}|0x22C|Deep Sleep|0x01|0x00 0x01"

    # Restore on AC/Power Loss: 1=Power On, 2=Power Off(default)
    "${SETUP_VAR}|0x0B4|Restore on AC/Power Loss|0x01|0x01 0x02"

    # WAN Device: 0=Disabled, 1=Enabled(default)
    "${SETUP_VAR}|0x226|WAN Device|0x00|0x00 0x01"

    # Onboard LAN: 0=Disabled, 1=Enabled(default) -- keep enabled
    "${SETUP_VAR}|0x229|Onboard LAN|0x01|0x00 0x01"

    # === AmdSetup variable (CBS RN offsets, 3A997502) ===
    # Global C-state Control: 0=Disabled, 1=Enabled(default), 3=Auto
    "${AMDSETUP_VAR}|0x024|Global C-state Control (CBS RN)|0x01|0x00 0x01 0x03"

    # Core Performance Boost: 0=Disabled, 1=Auto(default)
    "${AMDSETUP_VAR}|0x023|Core Performance Boost (CBS RN)|0x01|0x00 0x01"

    # DF Cstates: 0=Disabled, 1=Enabled, 0xFF=Auto(default)
    "${AMDSETUP_VAR}|0x13E|DF Cstates (CBS RN)|0x01|0x00 0x01 0xFF"

    # CPPC CTRL: 0=Disabled, 1=Enabled, 0xF=Auto(default)
    "${AMDSETUP_VAR}|0x145|CPPC CTRL (CBS RN)|0x01|0x00 0x01 0x0F"

    # CPPC Preferred Cores: 0=Disabled, 1=Enabled, 0xF=Auto(default)
    "${AMDSETUP_VAR}|0x1AB|CPPC Preferred Cores (CBS RN)|0x01|0x00 0x01 0x0F"

    # Aggressive SATA Device Sleep Port 0: 0=Disabled, 1=Enabled, 0xF=Auto(default)
    "${AMDSETUP_VAR}|0x0DD|Aggr SATA DevSleep Port 0 (CBS RN)|0x01|0x00 0x01 0x0F"

    # Aggressive SATA Device Sleep Port 1: 0=Disabled, 1=Enabled, 0xF=Auto(default)
    "${AMDSETUP_VAR}|0x0DE|Aggr SATA DevSleep Port 1 (CBS RN)|0x01|0x00 0x01 0x0F"

    # === AmdSetup variable (CBS RV offsets -- shared FCH, still functional on Cezanne) ===
    # Power Supply Idle Control: 0=Typical, 1=Low Current Idle, 0xF=Auto(default)
    "${AMDSETUP_VAR}|0x0FC|Power Supply Idle Control (CBS RV)|0x01|0x00 0x01 0x0F"

    # HD Audio Enable: 0=Disabled, 1=Enabled, 0xF=Auto(default)
    "${AMDSETUP_VAR}|0x0F9|HD Audio Enable (CBS RV)|0x00|0x00 0x01 0x0F"

    # === AMD_PBS_SETUP variable (A339D746) ===
    # S3/Modern Standby Support: 0=Disabled, 1=Modern Standby(default), 3=S3
    "${PBS_VAR}|0x016|S3/Modern Standby Support|0x03|0x00 0x01 0x03"

    # PM L1 SS: 0=Disabled(default), 1=L1.1, 2=L1.2, 3=L1.1_L1.2
    "${PBS_VAR}|0x025|PM L1 SS|0x03|0x00 0x01 0x02 0x03"

    # WLAN Enable: 0=Disabled, 1=Enabled(default)
    "${PBS_VAR}|0x014|WLAN Enable|0x00|0x00 0x01"

    # Blue Tooth Enable: 0=Disabled, 1=Enabled(default)
    "${PBS_VAR}|0x015|Blue Tooth Enable|0x00|0x00 0x01"
)

# --- Logging ---
log() { echo "[$(date '+%H:%M:%S')] $*" | tee -a "${LOG_FILE}"; }
warn() { echo "[$(date '+%H:%M:%S')] WARNING: $*" | tee -a "${LOG_FILE}" >&2; }
die() { echo "[$(date '+%H:%M:%S')] FATAL: $*" | tee -a "${LOG_FILE}" >&2; exit 1; }

# --- Helpers ---

# Read a single byte from a NVRAM variable file at a given data offset.
# The file has 4 attribute bytes then the data, so file offset = ATTR_BYTES + data_offset.
read_byte() {
    local varfile="$1"
    local data_offset="$2"
    local file_offset=$((ATTR_BYTES + data_offset))
    od -An -tx1 -j "${file_offset}" -N 1 "${EFIVARS}/${varfile}" 2>/dev/null | tr -d ' \n'
}

# Write a single byte to a NVRAM variable file using read-modify-write.
# 1. Read the entire variable (attributes + data)
# 2. Modify the target byte
# 3. Write the entire blob back
write_byte() {
    local varfile="$1"
    local data_offset="$2"
    local new_value="$3"
    local filepath="${EFIVARS}/${varfile}"
    local file_offset=$((ATTR_BYTES + data_offset))

    local tmpfile
    tmpfile="$(mktemp)"
    trap "rm -f '${tmpfile}'" RETURN

    # Read current contents
    cp "${filepath}" "${tmpfile}"

    # Modify the target byte using printf + dd
    printf "\\x$(printf '%02x' "${new_value}")" | \
        dd of="${tmpfile}" bs=1 seek="${file_offset}" count=1 conv=notrunc 2>/dev/null

    # efivarfs files are immutable by default; remove the flag before writing
    chattr -i "${filepath}" 2>/dev/null || true

    # Write back the modified blob
    cp "${tmpfile}" "${filepath}"

    rm -f "${tmpfile}"
    trap - RETURN
}

# Check if a value is in a space-separated list
value_in_list() {
    local needle="$1"
    shift
    for v in "$@"; do
        [[ "${v}" == "${needle}" ]] && return 0
    done
    return 1
}

# Parse a hex string like "0x0FC" to a decimal number
hex_to_dec() {
    printf '%d' "$1"
}

# --- Preflight checks ---
preflight() {
    if [[ $EUID -ne 0 ]]; then
        die "Must run as root"
    fi

    if [[ ! -d "${EFIVARS}" ]]; then
        die "efivarfs not found at ${EFIVARS} -- is this a UEFI-booted system?"
    fi

    # Check that our target variables exist
    for varfile in "${SETUP_VAR}" "${AMDSETUP_VAR}" "${PBS_VAR}"; do
        if [[ ! -f "${EFIVARS}/${varfile}" ]]; then
            die "NVRAM variable not found: ${varfile}"
        fi
    done

    # Validate variable sizes as a sanity check
    local setup_file_size amd_file_size pbs_file_size
    setup_file_size=$(stat -c%s "${EFIVARS}/${SETUP_VAR}")
    amd_file_size=$(stat -c%s "${EFIVARS}/${AMDSETUP_VAR}")
    pbs_file_size=$(stat -c%s "${EFIVARS}/${PBS_VAR}")

    local setup_data_size=$((setup_file_size - ATTR_BYTES))
    local amd_data_size=$((amd_file_size - ATTR_BYTES))
    local pbs_data_size=$((pbs_file_size - ATTR_BYTES))

    if [[ ${setup_data_size} -ne ${SETUP_SIZE} ]]; then
        die "Setup variable size mismatch: expected ${SETUP_SIZE}, got ${setup_data_size}. BIOS version may differ from ${TARGET_BIOS}."
    fi
    if [[ ${amd_data_size} -lt ${AMDSETUP_SIZE_MIN} ]]; then
        die "AmdSetup variable size too small: expected >=${AMDSETUP_SIZE_MIN}, got ${amd_data_size}. BIOS version may differ from ${TARGET_BIOS}."
    fi
    if [[ ${pbs_data_size} -ne ${PBS_SIZE} ]]; then
        die "AMD_PBS_SETUP variable size mismatch: expected ${PBS_SIZE}, got ${pbs_data_size}. BIOS version may differ from ${TARGET_BIOS}."
    fi

    log "Preflight OK for ${TARGET_BIOS}: all NVRAM variables found with expected sizes"
    log "  Setup: ${setup_data_size} bytes"
    log "  AmdSetup: ${amd_data_size} bytes"
    log "  AMD_PBS_SETUP: ${pbs_data_size} bytes"
}

# --- Main logic ---
main() {
    if [[ "${1:-}" == "--apply" ]]; then
        APPLY=true
    fi

    if ${APPLY}; then
        die "--apply is disabled pending P2.20B live rework. Use read-live-bios-settings.py and analysis/p2.20b/live-readback-2026-04-25.md first."
    fi

    mkdir -p "$(dirname "${LOG_FILE}")"
    log "=== BIOS NVRAM Settings ${TARGET_BIOS} $(if ${APPLY}; then echo 'APPLY'; else echo 'DRY RUN'; fi) ==="
    log "Log file: ${LOG_FILE}"

    preflight

    local total=0 skipped=0 changed=0 failed=0

    for entry in "${SETTINGS[@]}"; do
        IFS='|' read -r varfile offset_hex name desired_hex valid_list <<< "${entry}"
        local offset
        offset=$(hex_to_dec "${offset_hex}")
        local desired
        desired=$(hex_to_dec "${desired_hex}")

        # Read current value
        local current_hex
        current_hex="$(read_byte "${varfile}" "${offset}")"
        if [[ -z "${current_hex}" ]]; then
            warn "SKIP ${name}: failed to read offset ${offset_hex} from ${varfile}"
            ((failed++)) || true
            ((total++)) || true
            continue
        fi
        local current
        current=$((16#${current_hex}))
        local current_fmt
        current_fmt="$(printf '0x%02X' "${current}")"

        # Validate: is the current value in the expected valid set?
        local -a valid_values
        read -ra valid_values <<< "${valid_list}"
        if ! value_in_list "${current_fmt}" "${valid_values[@]}"; then
            warn "ABORT ${name}: current value ${current_fmt} at offset ${offset_hex} is NOT in expected set {${valid_list}}"
            warn "  This means the NVRAM layout doesn't match BIOS ${TARGET_BIOS}. Refusing to modify."
            ((failed++)) || true
            ((total++)) || true
            continue
        fi

        # Check if already set to desired value
        if [[ ${current} -eq ${desired} ]]; then
            log "  OK   ${name} = ${desired_hex} (already set)"
            ((skipped++)) || true
            ((total++)) || true
            continue
        fi

        # Apply or report
        if ${APPLY}; then
            log "  SET  ${name}: ${current_fmt} -> ${desired_hex}"
            if write_byte "${varfile}" "${offset}" "${desired}"; then
                # Verify the write
                local verify_hex
                verify_hex="$(read_byte "${varfile}" "${offset}")"
                local verify
                verify=$((16#${verify_hex}))
                if [[ ${verify} -eq ${desired} ]]; then
                    log "       Verified OK"
                    ((changed++)) || true
                else
                    warn "       VERIFY FAILED: read back $(printf '0x%02X' "${verify}") instead of ${desired_hex}"
                    ((failed++)) || true
                fi
            else
                warn "       WRITE FAILED for ${name}"
                ((failed++)) || true
            fi
        else
            log "  WANT ${name}: ${current_fmt} -> ${desired_hex} (dry run, no change)"
            ((changed++)) || true
        fi

        ((total++)) || true
    done

    echo ""
    log "=== Summary ==="
    log "  Total settings: ${total}"
    log "  Already correct: ${skipped}"
    if ${APPLY}; then
        log "  Changed: ${changed}"
    else
        log "  Would change: ${changed}"
    fi
    log "  Failed/skipped: ${failed}"

    if [[ ${failed} -gt 0 ]]; then
        warn "Some settings failed validation. Check if BIOS version matches ${TARGET_BIOS}."
        return 1
    fi

    if ${APPLY} && [[ ${changed} -gt 0 ]]; then
        echo ""
        log "Changes applied. Reboot for new settings to take effect."
        log "If the BIOS resets to defaults on next boot, re-enter BIOS setup and save."
    fi

    if ! ${APPLY} && [[ ${changed} -gt 0 ]]; then
        echo ""
        log "Dry-run complete. Review the P2.20B analysis, live values, and recovery plan before any --apply run."
    fi
}

main "$@"
