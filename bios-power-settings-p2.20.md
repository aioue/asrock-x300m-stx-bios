# ASRock X300M-STX BIOS Power Settings (P2.20)

BIOS settings for low idle power on an always-on Proxmox VE server with AMD Ryzen 5 PRO 5650G (Cezanne/Zen 3).

Extracted from firmware ROM `bios-files/firmware/stock-2.20/X3MSTX_2.20` using `./analyze-bios-rom.sh`.
To re-extract after a BIOS update: `./analyze-bios-rom.sh <new-rom-file> <output-dir>`

OS-side power tuning is in `roles/proxmox-host/tasks/power-management.yml`.

## Programmatic Application

`./apply-bios-settings.sh` reads and writes UEFI NVRAM variables via `efivarfs` to apply
these settings from a running Proxmox system (no manual BIOS UI or UEFI Shell needed).

```bash
# Dry run -- shows what would change, writes nothing
sudo ./apply-bios-settings.sh

# Apply -- reads, validates, writes, verifies each byte
sudo ./apply-bios-settings.sh --apply
```

Safety mechanisms:
- Validates NVRAM variable sizes match BIOS v2.20 (detects version mismatch)
- Checks each byte against the set of IFR-defined valid values before writing
- Skips settings already at the desired value (idempotent)
- Read-modify-write: reads entire variable, patches one byte, writes back
- Post-write verification read
- All operations logged to `/var/log/bios-settings-*.log`

### NVRAM Variables

| VarStore Name | GUID | Size | Used By |
|---------------|------|------|---------|
| Setup | `ec87d643-eba4-4bb5-a1e5-3f3e36b20da9` | 589 B | Main BIOS UI settings |
| AmdSetup | `3a997502-647a-4c82-998e-52ef9486a247` | 1447-1448 B | AMD CBS RN + RV settings |
| AMD_PBS_SETUP | `a339d746-f678-49b3-9fc7-54ce0f9df226` | 128 B | AMD Platform BIOS Settings |

---

## Settings Summary

| Priority | Setting | Location | Recommended | Impact |
|----------|---------|----------|-------------|--------|
| Critical | Global C-state Control | CBS RN / Setup | Enabled | 10-25W idle reduction |
| Critical | Power Supply Idle Control | CBS RV | Low Current Idle | 3-8W idle reduction |
| Critical | CPPC CTRL | CBS RN | Enabled | Enables amd-pstate-epp |
| High | Core Performance Boost | CBS RN | Auto | Keep boost available |
| High | DF Cstates | CBS RN > DF Common | Enabled | ~1-2W idle reduction |
| High | CC6 memory region encryption | CBS RN > DF Common | Auto | CC6 works without perf cost |
| High | S3/Modern Standby Support | AMD PBS | S3 Enable | Enables suspend-to-RAM |
| High | Deep Sleep | Setup | Enabled | Deeper S5 power savings |
| Medium | PM L1 SS | AMD PBS | L1.1_L1.2 | PCIe link power savings |
| Medium | ECO Mode | AOD | Eco-Mode (45W or 65W) | Caps sustained power |
| Medium | STAPM Control | CBS RN > SMU | Auto/Enabled | Thermal/power budgeting |
| Medium | Fan Control | CBS RN > SMU | Manual low curve | Less fan power at idle |
| Medium | AMD Fan Policy | AMD PBS | Air Cooling | Default, appropriate |
| Low | Restore on AC/Power Loss | Setup | Power On | Always-on server |
| Low | Onboard LAN | Setup | Enabled | Needed for network |
| Low | WLAN/BT Enable | AMD PBS | Disabled | Save ~0.5W if unused |
| Low | HD Audio Enable | CBS RV | Disabled | Save ~0.3W on headless |
| Low | Audio IOs | CBS RN/RV | Auto | No disable option; HD Audio master switch above handles this |
| Low | Aggressive SATA Device Sleep | CBS RN > FCH | Enabled (per port) | ~0.5W per port |
| Info | PPT/TDC/EDC Limits | CBS RN / AOD | Default or lower | Cap max power draw |

---

## Detailed Settings

### 1. C-States

#### Global C-state Control
- **Location**: AMD CBS (CbsSetupDxeRN) + Main Setup
- **CBS RN Variable**: 0x24 in VarStore 0x50
- **Setup Variable**: 0x170 in VarStore 0x01
- **Options**: Disabled (0x0), Enabled (0x1, default), Auto (0x3)
- **Recommended**: **Enabled**
- **Why**: Allows the CPU to enter deep idle states (CC1, CC6). This is the single most impactful setting for idle power. Without it, cores stay in C0 even when idle.
- **Caveats**: Enabled by default on this board. If you see instability, test with Auto first.
- **Kernel**: Works with `amd-pstate-epp` driver (set via `amd_pstate=active` kernel param).

#### DF Cstates (Data Fabric C-states)
- **Location**: AMD CBS (CbsSetupDxeRN) > DF Common Options
- **Variable**: 0x13E in VarStore 0x50
- **Options**: Disabled (0x0), Enabled (0x1), Auto (0xFF, default)
- **Recommended**: **Enabled**
- **Why**: Allows the Data Fabric (interconnect between CPU cores, memory controller, I/O) to enter low-power states when idle. Saves 1-2W at idle.
- **Caveats**: Auto should enable this on Cezanne, but explicit Enabled ensures it.

#### CC6 Memory Region Encryption
- **Location**: AMD CBS (CbsSetupDxeRN) > DF Common Options
- **Variable**: 0x43 in VarStore 0x50
- **Options**: Disabled (0x0), Enabled (0x1), Auto (0x3, default)
- **Recommended**: **Auto**
- **Why**: CC6 saves core state to a memory region when entering deep sleep. Encryption protects this data. Auto lets the firmware decide based on SEV/SME status.
- **Caveats**: Disabling encryption doesn't affect power; leave at Auto.

#### Fusion Message C State
- **Location**: Main Setup (hidden in SB DEBUG section)
- **Variable**: 0x90 in VarStore 0x01
- **Options**: Disabled (0x0, default), Enabled (0x1)
- **Recommended**: **Enabled**
- **Why**: Enables FCH (Fusion Controller Hub) C-state messaging, allowing the SoC to coordinate deeper idle states.
- **Visibility**: Likely hidden in standard BIOS UI (under SB FCH DEBUG Configuration).

#### Fusion Message C Multi-Core
- **Location**: Main Setup (hidden in SB DEBUG section)
- **Variable**: 0x8F in VarStore 0x01
- **Options**: Disabled (0x0, default), Enabled (0x1)
- **Recommended**: **Enabled**
- **Why**: Multi-core variant of the above. Coordinates C-state entry across cores.
- **Visibility**: Likely hidden.

### 2. CPPC / P-State / Performance

#### CPPC CTRL
- **Location**: AMD CBS (CbsSetupDxeRN) > CPPC
- **Variable**: 0x145 in VarStore 0x50
- **Options**: Auto (0xF, default), Enabled (0x1), Disabled (0x0)
- **Recommended**: **Enabled** (or Auto)
- **Why**: CPPC (Collaborative Processor Performance Control) is required for `amd-pstate-epp` to work properly. It allows the OS to communicate desired performance levels to the CPU firmware.
- **Caveats**: Auto should enable CPPC on Cezanne. Explicit Enabled guarantees it.
- **Kernel**: Requires `amd_pstate=active` kernel parameter.

#### CPPC Preferred Cores
- **Location**: AMD CBS (CbsSetupDxeRN) > CPPC
- **Variable**: 0x1AB in VarStore 0x50
- **Options**: Disabled (0x0), Enabled (0x1), Auto (0xF, default)
- **Recommended**: **Auto** or **Enabled**
- **Why**: Tells the OS which cores can boost highest. Helps the scheduler place latency-sensitive work on the fastest cores.
- **Caveats**: Suppressed in some BIOS versions (behind a Suppress If on family check). Not critical for power but improves efficiency.

#### Core Performance Boost (CPB)
- **Location**: AMD CBS (CbsSetupDxeRN)
- **Variable**: 0x23 in VarStore 0x50
- **Options**: Disabled (0x0), Auto (0x1, default)
- **Recommended**: **Auto** (keep enabled)
- **Why**: CPB allows cores to boost above base frequency when thermal/power headroom exists. With `amd-pstate-epp` + powersave governor, boost only engages when needed. Disabling saves no idle power but caps peak performance.

#### Precision Boost Overdrive (PBO)
- **Location**: AMD CBS (CbsSetupDxeRN) + AOD
- **CBS Variable**: 0x100 in VarStore 0x50
- **Options**: Auto (0xF, default), Enabled, Disabled, various advanced modes
- **Recommended**: **Disabled** or **Auto**
- **Why**: PBO extends boost limits beyond stock. For a power-optimized server, stock limits are sufficient. Disabling PBO keeps power consumption predictable.
- **Caveats**: Only affects boost behavior under load, not idle power.

#### ECO Mode
- **Location**: AOD (AodSetupDxe)
- **Variable**: 0x153 in VarStore 0xF0
- **Options**: Default (disabled), Eco-Mode 45W (0x1), Eco-Mode 65W (0x2)
- **Recommended**: **Eco-Mode (45W)** for lowest power, or skip if you need full burst performance
- **Why**: Caps the PPT (Package Power Tracking) limit, reducing sustained power draw. The 5650G stock PPT is 65W; Eco-Mode 45W caps it there.
- **Caveats**: Reduces sustained multi-threaded performance. Single-threaded burst is unaffected. Does not affect idle power.

### 3. Power Supply Idle Control

#### Power Supply Idle Control
- **Location**: AMD CBS (CbsSetupDxeRV -- Raven Ridge variant, but applies to Cezanne on this board)
- **Variable**: 0xFC in VarStore 0x50
- **Options**: Low Current Idle (0x1), Typical Current Idle (0x0), Auto (0xF, default)
- **Recommended**: **Low Current Idle**
- **Why**: Switches the VRM to a low-power operating mode when the CPU is idle. This is one of the highest-impact settings for idle power (3-8W reduction). "Typical Current Idle" keeps the VRM at normal operating current even when the CPU draws very little.
- **Caveats**: On some boards, Low Current Idle can cause USB disconnect issues at very low loads. Test stability after enabling. If you experience USB drops, revert to Typical Current Idle.
- **Note**: This setting is in the CbsSetupDxeRV module because the X300M-STX firmware includes both RV (Raven Ridge) and RN (Renoir/Cezanne) CBS paths.

### 4. Sleep / Suspend / ErP

#### S3/Modern Standby Support
- **Location**: AMD PBS (AmdPbsSetupDxe)
- **Variable**: 0x16 in VarStore 0x01
- **Options**: Disabled (0x0), Modern Standby Enable (0x1, default), S3 Enable (0x3)
- **Recommended**: **S3 Enable**
- **Why**: Traditional S3 (suspend-to-RAM) draws ~2-5W vs full idle power. Modern Standby (S0ix) can be problematic on Linux/Proxmox.
- **Caveats**: Proxmox supports S3 but you likely won't use suspend on an always-on server. Still, having S3 available is useful for maintenance.
- **Kernel**: May need `mem_sleep_default=deep` to prefer S3 over s2idle.

#### Modern Standby Type (if Modern Standby enabled)
- **Location**: AMD PBS (AmdPbsSetupDxe)
- **Variable**: 0x18 in VarStore 0x01
- **Options**: Modern Standby + S0i2 (0x0), Modern Standby + S0i3 (0x1, default), Modern Standby + S0i2 + S0i3 (0x2)
- **Recommended**: Not applicable if using S3 (see above).

#### Suspend to RAM
- **Location**: Main Setup
- **Variable**: 0x32 in VarStore 0x01
- **Options**: Disabled (0x0), Auto (0x2, default)
- **Recommended**: **Auto**
- **Why**: Allows the system to use suspend-to-RAM. Leave at Auto.

#### Deep Sleep
- **Location**: Main Setup
- **Variable**: 0x22C in VarStore 0x01
- **Options**: Disabled (0x0, default), Enabled (0x1)
- **Recommended**: **Enabled**
- **Why**: Allows deeper power states in S4/S5 (hibernate/shutdown). Reduces standby power when the system is off.
- **Caveats**: May disable Wake-on-LAN when the system is fully powered off. If you need WoL from a powered-off state, leave disabled. If the server is always running, this doesn't matter.

#### Restore on AC/Power Loss
- **Location**: Main Setup
- **Variable**: 0xB4 in VarStore 0x01
- **Options**: Power On (0x1), Power Off (0x2, default)
- **Recommended**: **Power On**
- **Why**: Essential for always-on servers -- automatically boots after a power outage.

### 5. PCIe Power Management

#### PM L1 SS (L1 Sub-States)
- **Location**: AMD PBS (AmdPbsSetupDxe)
- **Variable**: 0x25 in VarStore 0x01
- **Options**: Disabled (0x0, default), L1.1 (0x1), L1.2 (0x2), L1.1_L1.2 (0x3)
- **Recommended**: **L1.1_L1.2**
- **Why**: Enables PCIe L1 sub-states (L1.1 and L1.2) which allow PCIe links to reach the deepest idle power states. Saves 1-3W depending on the number of PCIe devices.
- **Caveats**: Some PCIe devices may not support L1 sub-states and could become unstable. If a specific device misbehaves, keep this at Disabled and rely on OS-level ASPM policy instead.
- **Visibility**: Suppressed unless certain PCIe lane configurations are active. May need to be set via `setup_var` in UEFI shell.
- **OS complement**: The `pcie_aspm=force` kernel param + `powersupersave` policy (already in power-management.yml) works with this.

### 6. SMU Power Limits (PPT/TDC/EDC)

These set the maximum power the CPU can draw. Lowering them reduces peak power but doesn't directly reduce idle power.

#### PPT Limit (Package Power Tracking)
- **Location**: AMD CBS (CbsSetupDxeRN) > SMU Common Options + AOD
- **CBS Variable**: 0x106 in VarStore 0x50
- **Options**: Numeric, 0-65535 mW (0 = auto/stock)
- **Stock value**: 65W (65000 mW) for 5650G
- **Recommended**: Leave at stock or set to 45000 for eco operation
- **Why**: Caps total package power draw under sustained load.

#### TDC Limit (Thermal Design Current)
- **Location**: AMD CBS (CbsSetupDxeRN) > SMU Common Options
- **CBS Variable**: 0x10A in VarStore 0x50
- **Options**: Numeric, 0-65535 mA

#### EDC Limit (Electrical Design Current)
- **Location**: AMD CBS (CbsSetupDxeRN) > SMU Common Options
- **CBS Variable**: 0x10E in VarStore 0x50
- **Options**: Numeric, 0-65535 mA

#### STAPM Control
- **Location**: AMD CBS (CbsSetupDxeRN) > SMU Common Options > STAPM Control
- **Variable**: 0xF2 in VarStore 0x50
- **Options**: Auto (0x0, default), Manual (0x1)
- **Recommended**: **Auto**
- **Why**: STAPM (Skin Temperature Aware Power Management) manages power budget based on thermal constraints. Useful for SFF cases. Leave at Auto.

#### STAPM Boost
- **Location**: AMD CBS (CbsSetupDxeRN) > SMU > STAPM Control
- **Variable**: 0xF3 in VarStore 0x50
- **Options**: Auto (0xF, default), various
- **Recommended**: **Auto**

### 7. Fan Control

#### Fan Control (SMU)
- **Location**: AMD CBS (CbsSetupDxeRN) > SMU Common Options > Fan Control
- **Variable**: 0xCB in VarStore 0x50
- **Options**: Auto (0x0, default), Manual (0x1)
- **Recommended**: **Manual** with conservative curve for a quiet, always-on server
- **Why**: Manual fan control lets you set a low minimum fan speed for idle. The stock auto curve may keep fans spinning faster than needed.

#### Fan Table Control
- **Variable**: 0xCE, with temperature points 0xCF-0xD2 and duty percentages
- **Recommended**: Set low idle temperatures (40-50°C) to ~20-30% duty, ramp up from 60°C.

#### AMD Fan Policy
- **Location**: AMD PBS
- **Variable**: 0xE in VarStore 0x01
- **Options**: Air Cooling (0x0, default), Water Cooling (0x1)
- **Recommended**: **Air Cooling** (unless using an AIO)
- **Why**: Water Cooling profile allows higher temps before throttling.

#### CPU Fan Setting (BIOS setup)
- **Location**: Main Setup (H/W Monitor section)
- **Variable**: 0xBD (Fan 1), 0xCB (Fan 2) in VarStore 0x01
- **Options**: Full on (0x0), Manual (0x1), Custom Curve (0x4), etc.
- **Recommended**: Custom curve with low minimum speed

### 8. Onboard Devices

#### Onboard LAN
- **Location**: Main Setup
- **Variable**: 0x229 in VarStore 0x01
- **Options**: Disabled (0x0), Enabled (0x1, default)
- **Recommended**: **Enabled** (needed for Proxmox networking)

#### LAN Power Enable
- **Location**: AMD PBS
- **Variable**: 0x13 in VarStore 0x01
- **Options**: Disabled (0x0), Enabled (0x1, default)
- **Recommended**: **Enabled**

#### WLAN Enable
- **Location**: AMD PBS
- **Variable**: 0x14 in VarStore 0x01
- **Options**: Disabled (0x0), Enabled (0x1, default)
- **Recommended**: **Disabled** (if no WiFi card installed, saves power on the M.2 slot)

#### Blue Tooth Enable
- **Location**: AMD PBS
- **Variable**: 0x15 in VarStore 0x01
- **Options**: Disabled (0x0), Enabled (0x1, default)
- **Recommended**: **Disabled** (not needed on a server)

#### HD Audio Enable
- **Location**: AMD CBS (CbsSetupDxeRV)
- **Variable**: 0xF9 in VarStore 0x50
- **Options**: Disabled, Enabled, Auto (default)
- **Recommended**: **Disabled** on headless server
- **Why**: Saves ~0.3-0.5W by powering down the HD Audio controller entirely.
- **Note**: OS-level `snd_hda_intel power_save=10` (already in power-management.yml) is a softer alternative.

#### Audio IOs
- **Location**: AMD CBS (CbsSetupDxeRN and RV)
- **CBS RN Variable**: 0xBF in VarStore 0x50
- **Options**: Auto (0xF, default), Azalia (0x0), Azalia mHDA (0x1), Azalia+SoundWire (0x2), SoundWire (0x3), I2STDM+I2SBT (0x4), Azalia+I2SBT (0x5), SoundWire+I2SBT (0x6)
- **Recommended**: **Auto** -- there is no "disable" option here. Use **HD Audio Enable = Disabled** (above) to fully power down audio.

#### WAN Device
- **Location**: Main Setup
- **Variable**: 0x226 in VarStore 0x01
- **Options**: Disabled (0x0), Enabled (0x1, default)
- **Recommended**: **Disabled** if no WAN/WWAN card installed

### 9. SATA Power Management

#### SATA Controller
- **Location**: AMD CBS (CbsSetupDxeRN) > FCH Common Options > SATA Configuration
- **Variable**: 0xD9 in VarStore 0x50
- **Options**: Auto (0xF), Enabled, Disabled
- **Recommended**: **Enabled** if using SATA devices, **Disabled** if NVMe-only
- **Why**: Disabling unused SATA controller saves ~0.5W.

#### Aggressive SATA Device Sleep Port 0/1
- **Location**: AMD CBS (CbsSetupDxeRN) > FCH > SATA Configuration
- **Port 0 Variable**: 0xDD, **Port 1 Variable**: 0xDE in VarStore 0x50
- **Options**: Auto (0xF, default), Enabled (0x1), Disabled (0x0)
- **Recommended**: **Enabled** for ports with non-critical drives
- **Why**: Allows SATA ports to enter DevSlp (device sleep), saving ~0.5W per port.
- **Caveats**: Some drives don't support DevSlp and may cause I/O hangs. Test with your specific drives.
- **OS complement**: `med_power_with_dipm` ALPM policy (already in power-management.yml).

#### SATA Auto Shutdown
- **Location**: AMD CBS (CbsSetupDxeRN) > FCH > SATA Configuration
- **Variable**: 0x144 in VarStore 0x50
- **Options**: Auto (0xF), Enabled, Disabled
- **Recommended**: **Auto**

### 10. Wake Control

#### Wake on PME
- **Location**: AMD PBS
- **Variable**: 0x19 in VarStore 0x01
- **Options**: Disabled (0x0), Enabled (0x1, default)
- **Recommended**: **Enabled** (allows Wake-on-LAN from S3/S5)

#### Wake From Onboard LAN
- **Location**: Main Setup
- **Variable**: 0x163 in VarStore 0x01
- **Options**: Disabled (0x0, default), Enabled (0x1)
- **Recommended**: **Enabled** if you want remote wake capability

#### RTC Alarm Power On
- **Location**: Main Setup
- **Variable**: 0x164 in VarStore 0x01
- **Options**: Disabled (0x0), Enabled (0x1), By OS (0x2, default)
- **Recommended**: **By OS** -- lets Proxmox handle scheduled wake-ups

### 11. Hidden/Suppressed Settings

The following settings exist in the firmware but are suppressed (hidden) in the default BIOS UI via `Suppress If` opcodes. They can be set via:
- **Recommended**: `./apply-bios-settings.sh --apply` (from running Linux, uses `efivarfs`)
- UEFI Shell: `setup_var <offset> <value>` (using `grub-setup-var` or UEFI Shell with `H2OUVE`)
- GRUB: `setup_var_3` command with appropriate GUID

Key hidden settings:
- **Fusion Message C State** (Variable 0x90 in Setup): Hidden in SB DEBUG section
- **Fusion Message C Multi-Core** (Variable 0x8F in Setup): Hidden in SB DEBUG section
- **PM L1 SS** (Variable 0x25 in PBS): Suppressed unless specific PCIe lane config active
- **Many AMD CBS options**: The entire CBS menu tree has ~300+ Suppress If conditions, gating options by CPU family/stepping. The Renoir (RN) CBS path is the active one for Cezanne.

The CbsSetupDxeRV module contains Raven Ridge-specific options. Even though this is a Cezanne system, some RV options (like Power Supply Idle Control) are still functional because the FCH (Fusion Controller Hub) is shared between RV and RN silicon.

---

## Recommended BIOS Configuration Checklist

### Must-change (highest idle power impact)
- [ ] Global C-state Control: **Enabled**
- [ ] Power Supply Idle Control: **Low Current Idle**
- [ ] CPPC CTRL: **Enabled**
- [ ] Deep Sleep: **Enabled**
- [ ] Restore on AC/Power Loss: **Power On**

### Should-change (moderate impact)
- [ ] S3/Modern Standby Support: **S3 Enable**
- [ ] DF Cstates: **Enabled**
- [ ] PM L1 SS: **L1.1_L1.2**
- [ ] HD Audio Enable: **Disabled** (headless)
- [ ] WLAN Enable: **Disabled** (if unused)
- [ ] Blue Tooth Enable: **Disabled**
- [ ] WAN Device: **Disabled** (if unused)
- [ ] Fusion Message C State: **Enabled** (hidden in BIOS UI)
- [ ] Fusion Message C Multi-Core: **Enabled** (hidden in BIOS UI)

### Optional (minor impact or situational)
- [ ] ECO Mode: **45W** (if you want to cap sustained power)
- [ ] Aggressive SATA Device Sleep: **Enabled** (per port, if drives support it)
- [ ] Fan curve: Custom low-speed profile

All settings in the must-change and should-change lists (except ECO Mode) are applied by
`./apply-bios-settings.sh`. Run with `--apply` after verifying the dry-run output.

### Do not change
- Core Performance Boost: Leave at **Auto** (no idle impact, needed for burst)
- PBO: Leave at **Auto** or **Disabled** (no idle impact)
- STAPM: Leave at **Auto**
- PPT/TDC/EDC: Leave at stock unless you specifically want to cap power

---

## Expected Idle Power

With all recommended settings applied (BIOS + OS-level tuning from power-management.yml):
- **Idle (no VMs active)**: ~8-12W at the wall
- **Idle (light VM workload)**: ~12-18W
- **Stock defaults (no tuning)**: ~20-35W idle

The biggest gains come from: Global C-state + Power Supply Idle Control + ASPM.
