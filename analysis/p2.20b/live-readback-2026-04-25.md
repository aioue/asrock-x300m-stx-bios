# P2.20B Live Read-Back 2026-04-25

Host: `pve` / `192.168.1.10`

Collection was read-only. No NVRAM writes were attempted.

## Host Identity

```text
board_vendor: ASRock
board_name: X300M-STX
bios_vendor: American Megatrends International, LLC.
bios_version: P2.20B
bios_date: 03/03/2026
kernel: Linux pve 6.17.9-1-pve
cmdline: BOOT_IMAGE=/vmlinuz-6.17.9-1-pve root=ZFS=/ROOT/pve-1 ro root=ZFS=rpool/ROOT/pve-1 boot=zfs amd_iommu=on iommu=pt quiet
```

## Efivarfs Availability

```text
AMD_PBS_SETUP-a339d746-f678-49b3-9fc7-54ce0f9df226: 128 bytes
AOD_SETUP-5ed15dc0-edef-4161-9151-6014c4cc630c: 1020 bytes
AmdSetup-3a997502-647a-4c82-998e-52ef9486a247: 1448 bytes
HideSetupOption-ec87d643-eba4-4bb5-a1e5-3f3e36b20da9: 1 byte
```

Important discovery: the expected `Setup-ec87d643-eba4-4bb5-a1e5-3f3e36b20da9` variable is not exposed on the live system. The only live efivar with that GUID is `HideSetupOption`, size 1 byte. Any script path that requires `Setup-*` must therefore fail preflight on this host unless another way to expose/read the AMI `Setup` VarStore is found.

## Live Setting Values

```text
AmdSetup 0x024 Global C-state Control: 0x01
AmdSetup 0x023 Core Performance Boost: 0x01
AmdSetup 0x13E DF Cstates: 0xFF
AmdSetup 0x145 CPPC CTRL: 0x0F
AmdSetup 0x1AB CPPC Preferred Cores: 0x0F
AmdSetup 0x0DD Aggr SATA DevSleep Port 0: 0x0F
AmdSetup 0x0DE Aggr SATA DevSleep Port 1: 0x0F
AmdSetup 0x0F2 ACS Enable (CBS RV): 0x00
AmdSetup 0x0F3 PCIe ARI Support (CBS RV): 0x0F
AmdSetup 0x0FC Power Supply Idle Control (CBS RV): 0xFF
AmdSetup 0x0F9 HD Audio Enable (CBS RV): 0x0F
AmdSetup 0x0C9 IOMMU (CBS RN): 0x0F
AmdSetup 0x14D PCIe ARI Support (CBS RN): 0x01
AmdSetup 0x1A7 PCIe ARI Enumeration (CBS RN): 0x01
AmdSetup 0x1A6 System Configuration AM4: 0x0F
AMD_PBS_SETUP 0x016 S3/Modern Standby Support: 0x01
AMD_PBS_SETUP 0x025 PM L1 SS: 0x00
AMD_PBS_SETUP 0x014 WLAN Enable: 0x01
AMD_PBS_SETUP 0x015 Blue Tooth Enable: 0x01
AOD_SETUP 0x153 ECO Mode: 0x00
```

Interpretation:

- `P2.20B` and the expected board are confirmed live.
- `Global C-state Control`, `Core Performance Boost`, RN `PCIe ARI Support`, and RN `PCIe ARI Enumeration` already match the conservative recommendation.
- `DF Cstates`, `CPPC CTRL`, `CPPC Preferred Cores`, `IOMMU`, SATA DevSleep, HD Audio, S3/Modern Standby, PM L1 SS, WLAN, and Bluetooth are currently on firmware defaults/auto or enabled states rather than the more explicit power-saving recommendations.
- `AmdSetup` offset `0x0FC` reads `0xFF`, which is not in the `CbsSetupDxeRV` IFR option set for `Power Supply Idle Control` (`0x00`, `0x01`, `0x0F`). Treat this offset as unsafe for live writes on this Cezanne host until further evidence explains the mismatch.
- `ECO Mode` is disabled, which is fine for idle-power work; it only caps load behavior.

## IOMMU Groups

The live kernel has IOMMU enabled with passthrough domains:

```text
amd_iommu=on iommu=pt
iommu: Default domain type: Passthrough
```

The group split is good for this board:

```text
Group 11: 01:00.0 Micron/Crucial P2/P3 NVMe
Group 12: 02:00.0 Micron/Crucial P2/P3 NVMe
Group 13: 03:00.0 Realtek RTL8111/8168/8211/8411 LAN
Group 14: 04:00.0 Intel Wi-Fi 6 AX200
Group 15: 05:00.0 AMD Cezanne VGA
Group 16: 05:00.1 AMD HDMI/DP Audio
Group 17: 05:00.2 AMD Platform Security Processor
Group 18: 05:00.3 AMD USB 3.1
Group 19: 05:00.4 AMD USB 3.1
Group 20: 05:00.5 AMD Audio Coprocessor
Group 21: 06:00.0 AMD FCH SATA Controller
```

No `pcie_acs_override` is present on the kernel command line. `P2.20B` appears to be doing the useful ACS/ARI job it was installed for.

## PCIe ASPM Snapshot

External/downstream links currently show ASPM disabled even when endpoints support it:

```text
01:00.0 NVMe: ASPM Disabled
02:00.0 NVMe: ASPM Disabled
03:00.0 Realtek LAN: ASPM Disabled
04:00.0 Intel AX200: ASPM Disabled
```

Internal Cezanne/iGPU/USB/SATA functions show `ASPM L0s L1 Enabled`.

This supports keeping `PM L1 SS` as a staged opt-in change. If enabled later, test both NVMe drives, Realtek LAN, AX200, USB devices, and passthrough behavior after a cold boot.

## Follow-Up

1. Update or split `apply-bios-settings.sh` before any `--apply` run, because the live host does not expose the expected `Setup-*` efivar.
2. Do not write `AmdSetup` offset `0x0FC` for `Power Supply Idle Control` unless the `0xFF` live value is explained.
3. Prefer an explicit read-only report first after each BIOS UI change: `ssh -o ControlMaster=no root@192.168.1.10 'python3 -s' < read-live-bios-settings.py`.
4. Keep ACS/ARI/IOMMU settings conservative; the live group split is already good without kernel ACS override.

## Follow-up 2026-07-22

- Shallow idle confirmed again: max cpuidle state **C3** (no CC6) on kernel `6.17.9-1-pve`.
- Ansible OS tuning is largely applied (governor, EPP, tmpfiles, udev) but **`pcie_aspm=force` is missing** from kernel cmdline — downstream PCIe ASPM remains Disabled.
- See `RESEARCH.md` and `POWER-TUNING-RUNBOOK.md` for community references, Proxmox quirks, and staged test plan.
