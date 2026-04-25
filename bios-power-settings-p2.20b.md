# ASRock X300M-STX BIOS Power Settings (P2.20B)

BIOS settings for low idle power on an always-on Proxmox VE host with ASRock X300M-STX and AMD Ryzen 5 PRO 5650G (Cezanne / Zen 3).

Extracted from `bios-files/firmware/asrock-acs-ari-2.20b/X3MSTX_2.20B` using `./analyze-bios-rom.sh`.

`P2.20B` is the active firmware baseline because ASRock enabled ACS / ARI behavior for better IOMMU group separation. Treat stock `2.20` offsets as historical context only, even though the important VarStores and offsets below match in this analysis.

## Programmatic Application

`./read-live-bios-settings.py` is the current preferred live validation path for `P2.20B`; it reads efivarfs and writes nothing.

`./apply-bios-settings.sh --apply` is disabled pending rework. Live read-back on 2026-04-25 found that the expected `Setup-*` efivar is not exposed, and `AmdSetup` offset `0x0FC` reads `0xFF`, outside the `CbsSetupDxeRV` IFR values for `Power Supply Idle Control`.

```bash
# Read-only live comparison over SSH
ssh -o ControlMaster=no root@192.168.1.10 'python3 -s' < read-live-bios-settings.py
```

The older dry-run path is still useful only as a fail-safe preflight demonstration; on the current live host it is expected to stop because `Setup-*` is missing.

```bash
sudo ./apply-bios-settings.sh
```

Do not run `--apply` until the live system values, desired values, recovery plan, and physical recovery access have been reviewed.

## P2.20B VarStores

| VarStore name | GUID | IFR size | Notes |
| --- | --- | ---: | --- |
| `Setup` | `ec87d643-eba4-4bb5-a1e5-3f3e36b20da9` | 589 B | Main ASRock/AMI setup settings |
| `AmdSetup` RN | `3a997502-647a-4c82-998e-52ef9486a247` | 1448 B | Cezanne/Renoir AMD CBS path |
| `AmdSetup` RV | `3a997502-647a-4c82-998e-52ef9486a247` | 1447 B | Raven/RV CBS path; some FCH options still appear here |
| `AMD_PBS_SETUP` | `a339d746-f678-49b3-9fc7-54ce0f9df226` | 128 B | AMD PBS / board platform settings |
| `AOD_SETUP` | `5ed15dc0-edef-4161-9151-6014c4cc630c` | 1020 B | AMD Overclocking / ECO mode |

These match stock `2.20` for the offsets used by the existing script. That is not enough by itself to justify live writes; it only clears the first layout-safety check.

## Conservative Recommendation

Use the conservative profile for this Proxmox host:

- Keep ACS / ARI / IOMMU enabled for passthrough and avoid `pcie_acs_override` unless there is no firmware-supported alternative.
- Prefer CPU idle stability over maximum savings. Enable C-states and CPPC, but stage PCIe L1 substates and SATA DevSleep separately.
- Keep onboard LAN enabled. Disable unused Wi-Fi/Bluetooth/audio only if the hardware is not needed.
- Treat cTDP/ECO mode as load-power tuning, not an idle-power fix.

## Settings Summary

| Priority | Setting | P2.20B location | Offset | Conservative recommendation |
| --- | --- | --- | --- | --- |
| Critical | Global C-state Control | `AmdSetup` RN | `0x024` | Enabled |
| Critical | CPPC CTRL | `AmdSetup` RN | `0x145` | Enabled or Auto; use Enabled for deterministic `amd-pstate` support |
| Critical | Power Supply Idle Control | `AmdSetup` RV | `0x0FC` | Low Current Idle, with USB/network stability testing |
| High | DF Cstates | `AmdSetup` RN | `0x13E` | Enabled |
| High | Restore on AC/Power Loss | `Setup` | `0x0B4` | Power On |
| High | IOMMU | `AmdSetup` RN/RV | `0x0C9` RN, `0x10A` RV | Enabled |
| High | PCIe ARI Support | `AmdSetup` RN/RV | `0x14D` RN, `0x0F3` RV | Enabled or firmware default if ACS groups are correct |
| High | PCIe ARI Enumeration | `AmdSetup` RN | `0x1A7` | Enabled or firmware default if ACS groups are correct |
| Medium | S3/Modern Standby Support | `AMD_PBS_SETUP` | `0x016` | S3 Enable if suspend-to-RAM is wanted; otherwise leave stable default |
| Medium | PM L1 SS | `AMD_PBS_SETUP` | `0x025` | Opt-in only; test PCIe devices after enabling |
| Medium | WLAN Enable | `AMD_PBS_SETUP` | `0x014` | Disabled if no Wi-Fi card is used |
| Medium | Blue Tooth Enable | `AMD_PBS_SETUP` | `0x015` | Disabled if unused |
| Medium | HD Audio Enable | `AmdSetup` RV | `0x0F9` | Disabled on a headless server |
| Medium | System Configuration AM4 | `AmdSetup` RN | `0x1A6` | Optional 45W/35W load cap; do not expect idle gains |
| Optional | ECO Mode | `AOD_SETUP` | `0x153` | Optional load cap only |
| Opt-in | Aggressive SATA Device Sleep | `AmdSetup` RN | `0x0DD`, `0x0DE` | Only if attached SATA devices support DevSleep reliably |
| Opt-in | Fusion Message C State / Multi-Core | `Setup` | `0x090`, `0x08F` | Hidden/debug-adjacent; dry-run/read-back before considering writes |

## Detailed Notes

### C-states and CPPC

`P2.20B` keeps the stock `2.20` AMD CBS RN offsets:

- `Global C-state Control`: `AmdSetup` `0x024`, values `0x00` Disabled, `0x01` Enabled, `0x03` Auto.
- `DF Cstates`: `AmdSetup` `0x13E`, values `0x00` Disabled, `0x01` Enabled, `0xFF` Auto.
- `CPPC CTRL`: `AmdSetup` `0x145`, values `0x00` Disabled, `0x01` Enabled, `0x0F` Auto.
- `CPPC Preferred Cores`: `AmdSetup` `0x1AB`, values `0x00` Disabled, `0x01` Enabled, `0x0F` Auto.

Recommendation: enable Global C-state Control, DF Cstates, and CPPC CTRL. Leave CPPC Preferred Cores on Auto or Enabled; it is efficiency/performance scheduling, not an idle-power requirement.

### Power Supply Idle Control

`Power Supply Idle Control` is present in `CbsSetupDxeRV` at `AmdSetup` offset `0x0FC`, with values:

- `0x01`: Low Current Idle
- `0x00`: Typical Current Idle
- `0x0F`: Auto

Recommendation: Low Current Idle is still the main idle-power candidate, but test USB, storage, and network stability after reboot. If the system shows low-load instability or USB disconnects, revert to Typical Current Idle or Auto.

Live note: on the 2026-04-25 Proxmox read-back, `AmdSetup` offset `0x0FC` was `0xFF`, which is not one of the IFR options above. Do not write this offset unless the mismatch is explained.

### PCIe, ACS, ARI, IOMMU

`P2.20B` exposes the same relevant IFR settings as stock `2.20`, including:

- `ACS Enable`: `AmdSetup` RV `0x0F2`, values `0x00`, `0x01`, `0x0F`.
- `PCIe ARI Support`: `AmdSetup` RN `0x14D`; RV `0x0F3`.
- `PCIe ARI Enumeration`: `AmdSetup` RN `0x1A7`.
- `IOMMU`: `AmdSetup` RN `0x0C9`; RV `0x10A`.
- `SR-IOV Support`: `Setup` `0x005`.

Because `P2.20B` was supplied specifically for ACS / ARI behavior, first verify Linux IOMMU groups on the running Proxmox host before changing these values. A good result is usable group separation without `pcie_acs_override`.

### PCIe ASPM and L1 Substates

`PM L1 SS` is in `AMD_PBS_SETUP` at offset `0x025`:

- `0x00`: Disabled
- `0x01`: L1.1
- `0x02`: L1.2
- `0x03`: L1.1_L1.2

The saved `P2.20B_customised.BIN` profile appears to include `PM L1 SS = 0x03`, based on the profile byte diff at `0x0418` when mapped against the PBS data region. That mapping should be confirmed with live `efivarfs` read-back before writing anything.

Recommendation: keep this as an opt-in stage. After enabling, verify each PCIe link with `lspci -vv` and check kernel ASPM messages. Do not force unsupported ASPM modes on storage, NICs, or passthrough devices without a cold-boot recovery plan.

### Sleep and Wake

`S3/Modern Standby Support` is in `AMD_PBS_SETUP` at `0x016`:

- `0x00`: Disabled
- `0x01`: Modern Standby Enable
- `0x03`: S3 Enable

For an always-on Proxmox host, S3 is not critical for normal operation. Prefer stability unless suspend-to-RAM is a real maintenance requirement.

`Restore on AC/Power Loss` remains in `Setup` at `0x0B4`, with `0x01` Power On and `0x02` Power Off. For an always-on server, Power On is recommended.

### Onboard Devices

Disable unused devices only when you are sure they are not needed:

- `WLAN Enable`: `AMD_PBS_SETUP` `0x014`, set `0x00` if unused.
- `Blue Tooth Enable`: `AMD_PBS_SETUP` `0x015`, set `0x00` if unused.
- `HD Audio Enable`: `AmdSetup` RV `0x0F9`, set `0x00` on a headless server.
- `Onboard LAN`: `Setup` `0x229`, keep `0x01` enabled.

### cTDP and ECO Mode

`System Configuration AM4` is present in `AmdSetup` RN at `0x1A6`:

- `0x01`: 35W System Config 1
- `0x02`: 45W System Config 2
- `0x00`: 65W
- `0x0F`: Auto

`ECO Mode` is in `AOD_SETUP` at `0x153`, with 45W and 65W options.

These settings cap load behavior. They are useful for thermal and adapter limits but should not be counted as idle-power wins.

## Saved Profile Diff

`P2.20B_defaults.BIN` and `P2.20B_customised.BIN` are both 61,525 bytes and differ at 16 byte offsets:

```text
0x0039: 0xF7 -> 0xDA
0x0081: 0x00 -> 0x04
0x010D: 0x02 -> 0x01
0x0195: 0x01 -> 0x00
0x01C7: 0x00 -> 0x01
0x0216: 0x00 -> 0x30
0x02A4: 0xB0 -> 0x46
0x02A5: 0x04 -> 0x05
0x031F: 0x01 -> 0x00
0x0370: 0xFF -> 0x20
0x03CA: 0x00 -> 0x01
0x0418: 0x00 -> 0x03
0x044C: 0x00 -> 0x3C
0x044D: 0x00 -> 0x0F
0x0484: 0x0F -> 0x01
0x04DE: 0x0F -> 0x01
```

The profile format does not include plain `Setup`, `AmdSetup`, `AMD_PBS_SETUP`, or `AOD_SETUP` names, so it should not be treated as a direct concatenation of efivar data. The `0x0418` diff is likely `PM L1 SS` moving from Disabled to `L1.1_L1.2`. Other differences look like a mix of setup choices, numeric limits, and checksums, but should be confirmed from live NVRAM before claiming exact setting names.

## Live Validation Checklist

Before any live patching:

1. Confirm firmware version is `P2.20B`.
2. Read live `Setup`, `AmdSetup`, and `AMD_PBS_SETUP` sizes from `efivarfs`.
3. Read every target byte and verify it is in the IFR-valid value set.
4. Record current values and desired values.
5. Apply only one risk group at a time, with reboot/testing between groups.
6. Keep a rollback plan: BIOS setup access, saved profile restore, CMOS clear, and physical access.

## References and Evidence

- IFR generated in `analysis/p2.20b/`.
- Stock comparison from `analysis/stock-2.20/bios-analysis-X3MSTX_2.20/`.
- Saved profile comparison from `bios-files/settings/p2.20b/`.
- Live read-back workflow and current SSH blocker notes in `analysis/p2.20b/live-readback-notes.md`.
- Live host read-back from 2026-04-25 in `analysis/p2.20b/live-readback-2026-04-25.md`.
- Community references used only as cross-checks: Baker76 X300M-STX IOMMU notes, SFF.Network ACS BIOS threads, ASRock cTDP forum posts, Proxmox ASPM discussions, `linuxboot/uefisettings`, and `setup_var.efi`.
