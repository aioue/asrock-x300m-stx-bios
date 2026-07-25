# Applied production power settings (P2.20B)

Canonical record of what Study Proxmox is running after the July 2026 idle-power campaign.
Use this after a BIOS flash or CMOS clear to restore the intentional profile.

**Live read-back:** [`analysis/p2.20b/live-readback-2026-07-25.md`](analysis/p2.20b/live-readback-2026-07-25.md)  
**CSV measurements:** [`results/power-tuning.csv`](results/power-tuning.csv)  
**Offsets / IFR:** [`bios-power-settings-p2.20b.md`](bios-power-settings-p2.20b.md)

## Settled idle result

| Metric | Value |
|--------|-------|
| Plug (IKEA / z2m, `loadavg < 1`) | **~23–26 W** with VM 101 + 102 + LXC 200 |
| Credible delta vs scripted baseline | **~2–3 W** (not the earlier 45–50 W glance) |
| Deepest cpuidle | **C3** (no CC6) |
| BIOS | P2.20B (2026-03-03) |

## BIOS / NVRAM (applied and retained)

Restore with `scripts/nvram-write-byte.sh` (one byte + reboot each) or re-check with `read-live-bios-settings.py`.

| VarStore | Offset | Setting | Applied | Notes |
|----------|--------|---------|---------|-------|
| `AmdSetup` | `0x024` | Global C-state Control | `0x01` Enabled | Already correct |
| `AmdSetup` | `0x13E` | DF Cstates | `0x01` Enabled | Was Auto `0xFF` |
| `AmdSetup` | `0x145` | CPPC CTRL | `0x01` Enabled | Was Auto `0x0F` |
| `AmdSetup` | `0x0F9` | HD Audio Enable | `0x00` Disabled | Headless |
| `AMD_PBS_SETUP` | `0x014` | WLAN Enable | `0x00` Disabled | Ethernet only |
| `AMD_PBS_SETUP` | `0x015` | Blue Tooth Enable | `0x01` Enabled | **Keep on** (used) |
| `AMD_PBS_SETUP` | `0x025` | PM L1 SS | `0x03` L1.1_L1.2 | Applied; **no endpoint ASPM** on M.2/NIC bridges, so ~0 W at plug |

### Explicitly not changed / deferred

| Setting | Offset | Live | Why |
|---------|--------|------|-----|
| Power Supply Idle Control | `AmdSetup` `0x0FC` | `0xFF` INVALID | Do not script; USB boot risk; needs physical recovery |
| S3 / Modern Standby | `AMD_PBS_SETUP` `0x016` | Modern Standby | Always-on server; leave default |
| CPPC Preferred Cores | `AmdSetup` `0x1AB` | Auto | Optional; left alone |
| SATA DevSleep | `0x0DD` / `0x0DE` | Auto | Not staged |
| `Setup-*` offsets | — | efivar missing | Not writable on this host |

## Linux / Proxmox (Ansible: `roles/proxmox-host`)

| Item | Value | Where |
|------|-------|-------|
| Kernel cmdline | `pcie_aspm=force` (+ `amd_iommu=on iommu=pt`) | `grub_cmdline_extra` / `initial-setup.yml` |
| ASPM policy | `powersupersave` | `power-management.yml` tmpfiles |
| CPU governor / EPP | `powersave` / `balance_power` | `power-management.yml` |
| USB autosuspend | on, with exclusions for NIC / ZFS / Zigbee | udev rules in `power-management.yml` |
| PCI runtime PM | `auto` | udev |
| SATA ALPM | `med_power_with_dipm` | tmpfiles |
| NMI watchdog | off | sysctl |
| Audio codec | `snd_hda_intel power_save=10` | modprobe.d |

**ASPM reality check:** Renoir GPP bridges to M.2 and NIC advertise `ASPM not supported`. Endpoint ASPM stays Disabled despite `pcie_aspm=force`. Documented in `RESEARCH.md`.

## Guests (Ansible)

| Guest | Setting | Value | Where |
|-------|---------|-------|-------|
| VM 102 ubuntu-cloud | cores | **4** | `power-management.yml` |
| VM 102 | memory | 4096 | `power-management.yml` |
| VM 102 | balloon floor | 512 | `power-management.yml` |
| VM 102 | onboot | 1 | `power-management.yml` |
| VM 101 homeassistant | balloon floor | 512 | `power-management.yml` |
| LXC 200 tank | cores | **2** | `lxc_tank` defaults + `power-management.yml` |
| LXC 200 | memory | **512** | same |

## After a BIOS update

1. Confirm BIOS version (`dmidecode -s bios-version`). Re-validate offsets with IFR if major version change.
2. `python3 -s < read-live-bios-settings.py` — compare to this file.
3. Re-apply only the **BIOS / NVRAM** rows above (not PSI, not Setup).
4. Re-run Ansible `configure.yml --tags power` for Linux + guest sizes.
5. Spot-check plug at `loadavg < 1` (expect ~23–26 W range).
