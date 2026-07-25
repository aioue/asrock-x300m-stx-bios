# ASRock X300M-STX P2.20B Live BIOS Read-Back

## Host Identity
- sys_vendor: `To Be Filled By O.E.M.`
- product_name: `To Be Filled By O.E.M.`
- board_vendor: `ASRock`
- board_name: `X300M-STX`
- bios_vendor: `American Megatrends International, LLC.`
- bios_version: `P2.20B`
- bios_date: `03/03/2026`
- kernel: `Linux pve 6.17.9-1-pve #1 SMP PREEMPT_DYNAMIC PMX 6.17.9-1 (2026-01-12T16:25Z) x86_64 GNU/Linux`
- cmdline: `BOOT_IMAGE=/vmlinuz-6.17.9-1-pve root=ZFS=/ROOT/pve-1 ro root=ZFS=rpool/ROOT/pve-1 boot=zfs amd_iommu=on iommu=pt quiet`

## EFI Variable Sizes
- `Setup`: missing `Setup-ec87d643-eba4-4bb5-a1e5-3f3e36b20da9`
- `AmdSetup`: 1448 bytes (expected >= 1447) - OK
- `AMD_PBS_SETUP`: 128 bytes (expected 128) - OK
- `AOD_SETUP`: 1020 bytes (expected 1020) - OK

## Selected BIOS Setting Read-Back
| Store | Offset | Setting | Current | Desired | Valid | Status |
| --- | ---: | --- | --- | --- | --- | --- |
| Setup | 0x090 | Fusion Message C State | missing store | | | read_failed |
| Setup | 0x08F | Fusion Message C Multi-Core | missing store | | | read_failed |
| Setup | 0x22C | Deep Sleep | missing store | | | read_failed |
| Setup | 0x0B4 | Restore on AC/Power Loss | missing store | | | read_failed |
| Setup | 0x226 | WAN Device | missing store | | | read_failed |
| Setup | 0x229 | Onboard LAN | missing store | | | read_failed |
| AmdSetup | 0x024 | Global C-state Control (CBS RN) | 0x01 | 0x01 | 0x00 0x01 0x03 | matches_recommendation |
| AmdSetup | 0x023 | Core Performance Boost (CBS RN) | 0x01 | 0x01 | 0x00 0x01 | matches_recommendation |
| AmdSetup | 0x13E | DF Cstates (CBS RN) | 0xFF | 0x01 | 0x00 0x01 0xFF | differs_from_recommendation |
| AmdSetup | 0x145 | CPPC CTRL (CBS RN) | 0x0F | 0x01 | 0x00 0x01 0x0F | differs_from_recommendation |
| AmdSetup | 0x1AB | CPPC Preferred Cores (CBS RN) | 0x0F | 0x01 | 0x00 0x01 0x0F | differs_from_recommendation |
| AmdSetup | 0x0DD | Aggr SATA DevSleep Port 0 (CBS RN) | 0x0F | 0x01 | 0x00 0x01 0x0F | differs_from_recommendation |
| AmdSetup | 0x0DE | Aggr SATA DevSleep Port 1 (CBS RN) | 0x0F | 0x01 | 0x00 0x01 0x0F | differs_from_recommendation |
| AmdSetup | 0x0F2 | ACS Enable (CBS RV) | 0x00 | 0x01 | 0x00 0x01 0x0F | differs_from_recommendation |
| AmdSetup | 0x0F3 | PCIe ARI Support (CBS RV) | 0x0F | 0x01 | 0x00 0x01 0x0F | differs_from_recommendation |
| AmdSetup | 0x0FC | Power Supply Idle Control (CBS RV) | 0xFF | 0x01 (Low Current Idle) | 0x00 0x01 0x0F | INVALID_FOR_IFR |
| AmdSetup | 0x0F9 | HD Audio Enable (CBS RV) | 0x0F | 0x00 | 0x00 0x01 0x0F | differs_from_recommendation |
| AmdSetup | 0x0C9 | IOMMU (CBS RN) | 0x0F | 0x01 | 0x00 0x01 0x0F | differs_from_recommendation |
| AmdSetup | 0x14D | PCIe ARI Support (CBS RN) | 0x01 | 0x01 | 0x00 0x01 0x0F | matches_recommendation |
| AmdSetup | 0x1A7 | PCIe ARI Enumeration (CBS RN) | 0x01 | 0x01 | 0x00 0x01 0x0F | matches_recommendation |
| AmdSetup | 0x1A6 | System Configuration AM4 | 0x0F (Auto) | n/a | 0x00 0x01 0x02 0x0F | observed |
| AMD_PBS_SETUP | 0x016 | S3/Modern Standby Support | 0x01 (Modern Standby) | 0x03 (S3) | 0x00 0x01 0x03 | differs_from_recommendation |
| AMD_PBS_SETUP | 0x025 | PM L1 SS | 0x00 (Disabled) | 0x03 (L1.1_L1.2) | 0x00 0x01 0x02 0x03 | differs_from_recommendation |
| AMD_PBS_SETUP | 0x014 | WLAN Enable | 0x01 | 0x00 | 0x00 0x01 | differs_from_recommendation |
| AMD_PBS_SETUP | 0x015 | Blue Tooth Enable | 0x01 | 0x00 | 0x00 0x01 | differs_from_recommendation |
| AOD_SETUP | 0x153 | ECO Mode | 0x00 (Disabled) | n/a | 0x00 0x01 0x02 | observed |

## Notes
- This script is read-only and does not write efivarfs.
- Values are only safe to patch after current values, desired values, and rollback are reviewed.
