#!/usr/bin/env python3
"""Read ASRock X300M-STX P2.20B BIOS setting bytes from efivarfs.

This is intentionally read-only. It reads the named UEFI variables from
`/sys/firmware/efi/efivars`, subtracts the 4-byte efivarfs attribute header,
and reports selected offsets validated from the P2.20B IFR analysis.
"""

from __future__ import annotations

import argparse
import subprocess
from pathlib import Path


ATTR_BYTES = 4

EFIVARS = Path("/sys/firmware/efi/efivars")

VARSTORES = {
    "Setup": {
        "file": "Setup-ec87d643-eba4-4bb5-a1e5-3f3e36b20da9",
        "expected_size": 589,
    },
    "AmdSetup": {
        "file": "AmdSetup-3a997502-647a-4c82-998e-52ef9486a247",
        # CBS RN IFR says 1448 bytes; CBS RV IFR says 1447 bytes.
        "expected_min_size": 1447,
    },
    "AMD_PBS_SETUP": {
        "file": "AMD_PBS_SETUP-a339d746-f678-49b3-9fc7-54ce0f9df226",
        "expected_size": 128,
    },
    "AOD_SETUP": {
        "file": "AOD_SETUP-5ed15dc0-edef-4161-9151-6014c4cc630c",
        "expected_size": 1020,
    },
}

VALUE_NAMES = {
    "Restore on AC/Power Loss": {0x01: "Power On", 0x02: "Power Off"},
    "Power Supply Idle Control (CBS RV)": {
        0x00: "Typical Current Idle",
        0x01: "Low Current Idle",
        0x0F: "Auto",
    },
    "PM L1 SS": {
        0x00: "Disabled",
        0x01: "L1.1",
        0x02: "L1.2",
        0x03: "L1.1_L1.2",
    },
    "S3/Modern Standby Support": {
        0x00: "Disabled",
        0x01: "Modern Standby",
        0x03: "S3",
    },
    "System Configuration AM4": {
        0x00: "65W",
        0x01: "35W",
        0x02: "45W",
        0x0F: "Auto",
    },
    "ECO Mode": {
        0x00: "Disabled",
        0x01: "Eco-Mode 45W",
        0x02: "Eco-Mode 65W",
    },
}

SETTINGS = [
    ("Setup", 0x090, "Fusion Message C State", 0x01, [0x00, 0x01]),
    ("Setup", 0x08F, "Fusion Message C Multi-Core", 0x01, [0x00, 0x01]),
    ("Setup", 0x22C, "Deep Sleep", 0x01, [0x00, 0x01]),
    ("Setup", 0x0B4, "Restore on AC/Power Loss", 0x01, [0x01, 0x02]),
    ("Setup", 0x226, "WAN Device", 0x00, [0x00, 0x01]),
    ("Setup", 0x229, "Onboard LAN", 0x01, [0x00, 0x01]),
    ("AmdSetup", 0x024, "Global C-state Control (CBS RN)", 0x01, [0x00, 0x01, 0x03]),
    ("AmdSetup", 0x023, "Core Performance Boost (CBS RN)", 0x01, [0x00, 0x01]),
    ("AmdSetup", 0x13E, "DF Cstates (CBS RN)", 0x01, [0x00, 0x01, 0xFF]),
    ("AmdSetup", 0x145, "CPPC CTRL (CBS RN)", 0x01, [0x00, 0x01, 0x0F]),
    ("AmdSetup", 0x1AB, "CPPC Preferred Cores (CBS RN)", 0x01, [0x00, 0x01, 0x0F]),
    ("AmdSetup", 0x0DD, "Aggr SATA DevSleep Port 0 (CBS RN)", 0x01, [0x00, 0x01, 0x0F]),
    ("AmdSetup", 0x0DE, "Aggr SATA DevSleep Port 1 (CBS RN)", 0x01, [0x00, 0x01, 0x0F]),
    ("AmdSetup", 0x0F2, "ACS Enable (CBS RV)", 0x01, [0x00, 0x01, 0x0F]),
    ("AmdSetup", 0x0F3, "PCIe ARI Support (CBS RV)", 0x01, [0x00, 0x01, 0x0F]),
    ("AmdSetup", 0x0FC, "Power Supply Idle Control (CBS RV)", 0x01, [0x00, 0x01, 0x0F]),
    ("AmdSetup", 0x0F9, "HD Audio Enable (CBS RV)", 0x00, [0x00, 0x01, 0x0F]),
    ("AmdSetup", 0x0C9, "IOMMU (CBS RN)", 0x01, [0x00, 0x01, 0x0F]),
    ("AmdSetup", 0x14D, "PCIe ARI Support (CBS RN)", 0x01, [0x00, 0x01, 0x0F]),
    ("AmdSetup", 0x1A7, "PCIe ARI Enumeration (CBS RN)", 0x01, [0x00, 0x01, 0x0F]),
    ("AmdSetup", 0x1A6, "System Configuration AM4", None, [0x00, 0x01, 0x02, 0x0F]),
    ("AMD_PBS_SETUP", 0x016, "S3/Modern Standby Support", 0x01, [0x00, 0x01, 0x03]),
    ("AMD_PBS_SETUP", 0x025, "PM L1 SS", 0x03, [0x00, 0x01, 0x02, 0x03]),
    ("AMD_PBS_SETUP", 0x014, "WLAN Enable", 0x00, [0x00, 0x01]),
    ("AMD_PBS_SETUP", 0x015, "Blue Tooth Enable", 0x01, [0x00, 0x01]),
    ("AOD_SETUP", 0x153, "ECO Mode", None, [0x00, 0x01, 0x02]),
]


def read_text(path: Path) -> str:
    try:
        return path.read_text(errors="replace").strip()
    except OSError as exc:
        return f"ERROR: {exc}"


def run(command: list[str]) -> str:
    try:
        result = subprocess.run(
            command,
            check=False,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            timeout=15,
        )
    except OSError as exc:
        return f"ERROR: {exc}"
    except subprocess.TimeoutExpired:
        return "ERROR: command timed out"
    return result.stdout.strip()


def read_varstore(store: str, efivars: Path) -> bytes:
    path = efivars / VARSTORES[store]["file"]
    return path.read_bytes()[ATTR_BYTES:]


def format_value(setting: str, value: int) -> str:
    formatted = f"0x{value:02X}"
    if setting in VALUE_NAMES and value in VALUE_NAMES[setting]:
        formatted += f" ({VALUE_NAMES[setting][value]})"
    return formatted


def print_host_identity() -> None:
    print("## Host Identity")
    dmi = Path("/sys/class/dmi/id")
    for name in [
        "sys_vendor",
        "product_name",
        "board_vendor",
        "board_name",
        "bios_vendor",
        "bios_version",
        "bios_date",
    ]:
        print(f"- {name}: `{read_text(dmi / name)}`")
    print(f"- kernel: `{run(['uname', '-a'])}`")
    print(f"- cmdline: `{read_text(Path('/proc/cmdline'))}`")
    print()


def print_varstore_sizes(efivars: Path) -> dict[str, bytes]:
    print("## EFI Variable Sizes")
    data_by_store = {}
    for store, metadata in VARSTORES.items():
        path = efivars / metadata["file"]
        if not path.exists():
            print(f"- `{store}`: missing `{metadata['file']}`")
            continue

        data = read_varstore(store, efivars)
        data_by_store[store] = data
        expected = metadata.get("expected_size")
        expected_min = metadata.get("expected_min_size")
        if expected is not None:
            status = "OK" if len(data) == expected else "MISMATCH"
            expectation = f"expected {expected}"
        else:
            status = "OK" if len(data) >= expected_min else "MISMATCH"
            expectation = f"expected >= {expected_min}"
        print(f"- `{store}`: {len(data)} bytes ({expectation}) - {status}")
    print()
    return data_by_store


def print_setting_table(data_by_store: dict[str, bytes]) -> None:
    print("## Selected BIOS Setting Read-Back")
    print("| Store | Offset | Setting | Current | Desired | Valid | Status |")
    print("| --- | ---: | --- | --- | --- | --- | --- |")
    for store, offset, setting, desired, valid_values in SETTINGS:
        if store not in data_by_store:
            print(f"| {store} | 0x{offset:03X} | {setting} | missing store | | | read_failed |")
            continue
        data = data_by_store[store]
        if offset >= len(data):
            print(f"| {store} | 0x{offset:03X} | {setting} | out of range | | | read_failed |")
            continue

        current = data[offset]
        valid = " ".join(f"0x{value:02X}" for value in valid_values)
        desired_text = "n/a" if desired is None else format_value(setting, desired)
        if current not in valid_values:
            status = "INVALID_FOR_IFR"
        elif desired is None:
            status = "observed"
        elif current == desired:
            status = "matches_recommendation"
        else:
            status = "differs_from_recommendation"

        print(
            f"| {store} | 0x{offset:03X} | {setting} | "
            f"{format_value(setting, current)} | {desired_text} | {valid} | {status} |"
        )
    print()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--efivars",
        type=Path,
        default=EFIVARS,
        help="Path to efivarfs mount, default: /sys/firmware/efi/efivars",
    )
    args = parser.parse_args()

    print("# ASRock X300M-STX P2.20B Live BIOS Read-Back")
    print()
    print_host_identity()
    data_by_store = print_varstore_sizes(args.efivars)
    print_setting_table(data_by_store)
    print("## Notes")
    print("- This script is read-only and does not write efivarfs.")
    print("- Values are only safe to patch after current values, desired values, and rollback are reviewed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
