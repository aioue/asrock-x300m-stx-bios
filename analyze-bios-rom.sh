#!/usr/bin/env bash
#
# Analyze an AMI UEFI BIOS ROM for power management settings.
#
# Extracts firmware sections, parses IFR (Internal Forms Representation) from
# Setup/AMD CBS/AMD PBS DXE modules, and searches for power-related options
# including hidden (suppressed) settings not shown in the default BIOS UI.
#
# Usage:
#   ./analyze-bios-rom.sh <rom-file> [output-dir]
#
# Examples:
#   ./analyze-bios-rom.sh bios-files/firmware/stock-2.20/X3MSTX_2.20
#   ./analyze-bios-rom.sh bios-files/firmware/asrock-acs-ari-2.20b/X3MSTX_2.20B analysis/p2.20b
#
# The rom-file can be a raw ROM image or a .zip containing one.
# Output goes to <output-dir> (default: ./bios-analysis-<basename>/).
#
# Tools (built from source on first run, cached in ~/.local/bin/):
#   - UEFIExtract (LongSoft/UEFITool, new_engine branch)
#   - ifrextract  (Universal-IFR-Extractor-Linux)
#
# Works on both x86_64 and aarch64 (builds natively).

set -euo pipefail

TOOL_DIR="${HOME}/.local/bin"
BUILD_DIR="${HOME}/.cache/bios-tools-build"

# Power-related search terms (case-insensitive grep pattern)
POWER_KEYWORDS=(
    "power" "idle" "sleep" "suspend" "c-state" "cstate" "c state"
    "cppc" "pstate" "p-state" "p state" "aspm"
    "erp" "s3" "s4" "s5" "wake" "standby" "hibernate"
    "thermal" "fan" "cool" "boost" "turbo"
    "frequency" "voltage" "tdp" "ppt" "tdc" "edc"
    "smu" "dpm" "efficiency" "eco" "energy"
    "low.power" "package" "deep" "aggressive" "alpm" "selective"
    "cc6" "pc6" "cpb" "df.c" "amd.cbs" "amd.pbs"
    "supply.idle" "soft.off" "soft off"
    "acpi" "alib" "bapm" "stapm" "prochot" "cldo"
    "nbi" "nbio" "xgbe" "xhci" "sata" "ahci"
    "spread.spectrum" "clock.spread"
)

log() { echo "==> $*" >&2; }
warn() { echo "WARNING: $*" >&2; }
die() { echo "ERROR: $*" >&2; exit 1; }

build_uefiextract() {
    if [[ -x "${TOOL_DIR}/uefiextract" ]]; then
        log "UEFIExtract already built at ${TOOL_DIR}/uefiextract"
        return 0
    fi

    log "Building UEFIExtract from source..."
    mkdir -p "${BUILD_DIR}" "${TOOL_DIR}"

    if [[ ! -d "${BUILD_DIR}/UEFITool" ]]; then
        git clone --depth 1 -b new_engine \
            https://github.com/LongSoft/UEFITool.git \
            "${BUILD_DIR}/UEFITool"
    fi

    cmake -S "${BUILD_DIR}/UEFITool/UEFIExtract" \
          -B "${BUILD_DIR}/UEFITool/UEFIExtract/build" \
          -DCMAKE_BUILD_TYPE=Release

    cmake --build "${BUILD_DIR}/UEFITool/UEFIExtract/build" \
          -j "$(nproc)"

    cp "${BUILD_DIR}/UEFITool/UEFIExtract/build/uefiextract" "${TOOL_DIR}/"
    log "UEFIExtract installed to ${TOOL_DIR}/uefiextract"
}

build_ifrextract() {
    if [[ -x "${TOOL_DIR}/ifrextractor" ]]; then
        log "ifrextractor already built at ${TOOL_DIR}/ifrextractor"
        return 0
    fi

    log "Building ifrextract from source..."
    mkdir -p "${BUILD_DIR}" "${TOOL_DIR}"

    if [[ ! -d "${BUILD_DIR}/Universal-IFR-Extractor-Linux" ]]; then
        git clone --depth 1 \
            https://github.com/therealgudv1n/Universal-IFR-Extractor-Linux.git \
            "${BUILD_DIR}/Universal-IFR-Extractor-Linux"
    fi

    make -C "${BUILD_DIR}/Universal-IFR-Extractor-Linux" -j "$(nproc)"
    cp "${BUILD_DIR}/Universal-IFR-Extractor-Linux/build/ifrextractor" "${TOOL_DIR}/"
    log "ifrextractor installed to ${TOOL_DIR}/ifrextractor"
}

ensure_dependencies() {
    local missing=()
    command -v cmake &>/dev/null || missing+=(cmake)
    command -v g++ &>/dev/null   || missing+=(g++)
    command -v make &>/dev/null  || missing+=(make)
    command -v git &>/dev/null   || missing+=(git)

    if [[ ${#missing[@]} -gt 0 ]]; then
        log "Installing missing build dependencies: ${missing[*]}"
        sudo apt-get update -qq
        sudo apt-get install -y -qq "${missing[@]}"
    fi

    export PATH="${TOOL_DIR}:${PATH}"
    build_uefiextract
    build_ifrextract
}

extract_rom() {
    local rom_file="$1"
    local dump_dir="${rom_file}.dump"

    if [[ -d "${dump_dir}" ]]; then
        log "ROM already extracted at ${dump_dir}"
    else
        log "Extracting ROM with UEFIExtract..."
        if ! uefiextract "${rom_file}" all; then
            warn "  UEFIExtract 'all' returned non-zero; checking for dump output"
        fi

        # Recent UEFIExtract builds can generate only the report/GUID files for
        # some AMD images in "all" mode. The legacy unpack mode still creates
        # the tree layout that the IFR scanner expects.
        if [[ ! -d "${dump_dir}" ]]; then
            log "Retrying extraction with UEFIExtract legacy unpack mode..."
            if ! uefiextract "${rom_file}" unpack; then
                if [[ -d "${dump_dir}" ]]; then
                    warn "  UEFIExtract unpack returned non-zero but created ${dump_dir}"
                else
                    die "UEFIExtract did not create ${dump_dir}"
                fi
            fi
        fi
    fi

    echo "${dump_dir}"
}

# Walk the UEFIExtract dump tree and find DXE modules matching Setup/CBS/PBS.
# UEFIExtract names directories like "100 Setup", "79 CbsSetupDxeRN", etc.
# Outputs paths to PE32/TE section body.bin files, one per line.
find_setup_modules() {
    local dump_dir="$1"

    # Module name patterns to match in directory paths
    local dir_pattern="[0-9]+ (Setup|CbsSetup|CbsBase|AmdPbs|AmiCbs|AsrockAmd|AodSetup|AMITSE)(/|[A-Z])"

    log "Searching for Setup/CBS/PBS modules in dump..."

    # Find body.bin files inside PE32/TE sections whose path contains a matching module
    find "${dump_dir}" -name "body.bin" \( -path "*PE32*" -o -path "*TE image*" \) -print0 2>/dev/null \
        | while IFS= read -r -d '' body; do
            if echo "${body}" | grep -qiE "${dir_pattern}"; then
                log "  Found: ${body}"
                echo "${body}"
            fi
        done \
        | sort -u
}

run_ifrextract() {
    local body_file="$1"
    local output_file="$2"

    log "Extracting IFR from ${body_file}..."

    # ifrextractor always writes to ifrdump.txt in CWD
    rm -f "ifrdump.txt"
    ifrextractor "${body_file}" 2>/dev/null || true

    if [[ -f "ifrdump.txt" ]] && [[ -s "ifrdump.txt" ]]; then
        mv "ifrdump.txt" "${output_file}"
        log "  IFR output: ${output_file} ($(wc -l < "${output_file}") lines)"
        return 0
    fi

    warn "  No IFR data found in ${body_file}"
    rm -f "${output_file}" "ifrdump.txt"
    return 1
}

search_power_settings() {
    local output_dir="$1"
    shift
    local -a ifr_files=("$@")

    local power_file="${output_dir}/power-settings.txt"
    local pattern
    pattern="$(IFS='|'; echo "${POWER_KEYWORDS[*]}")"

    log "Searching for power-related settings..."

    {
        echo "================================================================"
        echo "POWER-RELATED BIOS SETTINGS"
        echo "Generated: $(date -Iseconds)"
        echo "Search pattern: ${pattern}"
        echo "================================================================"
        echo ""

        for ifr_file in "${ifr_files[@]}"; do
            if [[ -f "${ifr_file}" ]]; then
                local matches
                matches="$(grep -inE "${pattern}" "${ifr_file}" 2>/dev/null | head -5000)" || true
                if [[ -n "${matches}" ]]; then
                    echo "--- ${ifr_file} ---"
                    echo "${matches}"
                    echo ""
                fi
            fi
        done

        # Also search the ROM strings file if present
        local strings_file="${output_dir}/rom-strings.txt"
        if [[ -f "${strings_file}" ]]; then
            echo "--- ROM Strings (filtered) ---"
            grep -inE "${pattern}" "${strings_file}" 2>/dev/null | head -3000 || true
            echo ""
        fi
    } > "${power_file}"

    local count
    count="$(grep -c '' "${power_file}" 2>/dev/null || echo 0)"
    log "Power settings output: ${power_file} (${count} lines)"
}

extract_rom_strings() {
    local rom_file="$1"
    local output_file="$2"

    log "Extracting printable strings from ROM..."
    strings -n 6 "${rom_file}" | sort -u > "${output_file}"
    log "  ROM strings: ${output_file} ($(wc -l < "${output_file}") unique strings)"
}

main() {
    if [[ $# -lt 1 ]]; then
        echo "Usage: $0 <rom-file> [output-dir]" >&2
        echo "" >&2
        echo "Analyze an AMI UEFI BIOS ROM for power management settings." >&2
        echo "Builds required tools (UEFIExtract, ifrextract) on first run." >&2
        exit 1
    fi

    local input="$1"
    local rom_file

    # Handle zip files
    if [[ "${input}" == *.zip ]]; then
        log "Extracting ROM from zip: ${input}"
        local tmpdir
        tmpdir="$(mktemp -d)"
        unzip -o "${input}" -d "${tmpdir}" >/dev/null
        rom_file="$(find "${tmpdir}" -type f ! -name "*.zip" -size +1M | head -1)"
        if [[ -z "${rom_file}" ]]; then
            die "No ROM file found in zip archive"
        fi
        log "Using ROM: ${rom_file}"
    else
        rom_file="${input}"
    fi

    if [[ ! -f "${rom_file}" ]]; then
        die "ROM file not found: ${rom_file}"
    fi

    local rom_basename
    rom_basename="$(basename "${rom_file}")"
    local output_dir="${2:-./bios-analysis-${rom_basename}}"
    mkdir -p "${output_dir}"

    log "ROM file: ${rom_file} ($(stat -c%s "${rom_file}" 2>/dev/null || stat -f%z "${rom_file}") bytes)"
    log "Output directory: ${output_dir}"

    # Step 1: Ensure tools are available
    ensure_dependencies

    # Step 2: Extract ROM
    local dump_dir
    dump_dir="$(extract_rom "${rom_file}")"

    # Step 3: Extract ROM strings
    extract_rom_strings "${rom_file}" "${output_dir}/rom-strings.txt"

    # Step 4: Find setup modules
    local -a module_bodies=()
    while IFS= read -r body_path; do
        [[ -n "${body_path}" ]] && module_bodies+=("${body_path}")
    done < <(find_setup_modules "${dump_dir}")

    if [[ ${#module_bodies[@]} -eq 0 ]]; then
        warn "No Setup/CBS/PBS modules found via name matching."
        warn "Falling back to scanning all PE32/TE sections for IFR data..."

        while IFS= read -r -d '' body; do
            local section_dir
            section_dir="$(basename "$(dirname "${body}")")"
            if [[ "${section_dir}" == *"PE32"* ]] || [[ "${section_dir}" == *"TE image"* ]]; then
                module_bodies+=("${body}")
            fi
        done < <(find "${dump_dir}" -name "body.bin" -print0 2>/dev/null)
        log "Found ${#module_bodies[@]} PE32/TE sections to scan"
    fi

    # Step 5: Extract IFR from each module
    local -a ifr_files=()
    local ifr_count=0
    for body in "${module_bodies[@]}"; do
        local ifr_output="${output_dir}/ifr-$(printf '%03d' ${ifr_count})-$(basename "$(dirname "$(dirname "${body}")")").txt"
        if run_ifrextract "${body}" "${ifr_output}"; then
            ifr_files+=("${ifr_output}")
        fi
        ((ifr_count++)) || true
    done

    if [[ ${#ifr_files[@]} -eq 0 ]]; then
        warn "No IFR data extracted from any module."
        warn "The ROM may use a non-standard format. Check rom-strings.txt for manual analysis."
    fi

    # Step 6: Search for power settings
    search_power_settings "${output_dir}" "${ifr_files[@]}"

    # Summary
    echo ""
    log "Analysis complete. Output files:"
    ls -lh "${output_dir}"/ 2>/dev/null
    echo ""
    log "Key files:"
    log "  Power settings: ${output_dir}/power-settings.txt"
    for f in "${ifr_files[@]}"; do
        log "  IFR dump: ${f}"
    done
    log "  ROM strings: ${output_dir}/rom-strings.txt"
}

main "$@"
