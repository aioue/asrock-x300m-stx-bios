# DeskMini power tuning runbook

Operational procedure for Study Proxmox (ASRock X300M-STX, P2.20B, Ryzen 5 PRO 5650G). Background: [RESEARCH.md](RESEARCH.md). BIOS offsets: [bios-power-settings-p2.20b.md](bios-power-settings-p2.20b.md).

**Attribution:** Runbook drafted with [Cursor](https://cursor.com) (Composer 2.5).

---

## Power measurement

### Home Assistant

| Item | Value |
|------|-------|
| Entity | `sensor.plug2_ikea_energy_power` (W) |
| Zigbee2MQTT friendly name | `plug2_ikea_energy` (label: DeskMini) |
| Also useful | `_voltage`, `_current`, `_energy` |

```bash
# Token from vault — see proxmox-setup .cursor/rules/home-assistant.mdc
curl -s -H "Authorization: Bearer $HA_TOKEN" \
  "http://192.168.1.240:8123/api/states/sensor.plug2_ikea_energy_power"
```

### MQTT (preferred for automated sampling)

| Item | Value |
|------|-------|
| Topic | `zigbee2mqtt/plug2_ikea_energy` |
| JSON field | `.power` |
| Broker | Mosquitto on HA (`core-mosquitto:1883` from add-ons) |

```bash
mosquitto_sub -h 192.168.1.240 -u addons -P "$MQTT_PASSWORD" \
  -t 'zigbee2mqtt/plug2_ikea_energy' -C 5 | jq -r '.power'
```

Credentials: HA add-on config — **never commit passwords**; use env vars in scripts.

### Always log with plug readings

```bash
ssh -o ControlMaster=no root@192.168.1.10 '
  zpool list 2>/dev/null
  hdparm -C /dev/sdc 2>/dev/null   # USB boot NVMe
  ls /dev/disk/by-id/ | grep -i wd60 || echo "no WD60 backup disk"
'
```

---

## Absolute power budget (not incremental BIOS table numbers)

| Scenario | Realistic plug (W) | Source |
|----------|-------------------|--------|
| 5700G/5650G Proxmox, NVMe, **no VMs**, tuned | 16–18 | [Sebastian Harnisch](https://sebastianharnisch.de/amd-ryzen-7-5700g-as-a-home-server/) |
| Same + idle VMs | 25–30 | same |
| **This host settled idle** (3 guests, July 2026 campaign) | **~23–26** | HA plug + load-gated CSV |
| USB 3.5" HDD spinning (when attached) | +4–7 | [WD idle modes PDF](https://documents.westerndigital.com/content/dam/doc-library/en_us/assets/public/western-digital/collateral/white-paper/white-paper-storage-power-efficiency-improvement-with-hdd-idle-modes.pdf) |

**Campaign closed July 2026.** Applied profile: [FINAL-APPLIED-SETTINGS.md](FINAL-APPLIED-SETTINGS.md). Credible savings vs first good baseline: ~2–3 W. ASPM on M.2/NIC blocked by GPP bridges (`ASPM not supported`). Power Supply Idle (`0x0FC`) deferred.

**~15W at the plug with HA + ubuntu-cloud + tank running is not a realistic target** on this hardware.

**Headless host** — no routine keyboard/monitor. Execution order and NVRAM policy: [RESEARCH.md — Risk / reward (headless)](RESEARCH.md#risk--reward-execution-order-headless) and [NVRAM-ALTERING.md](NVRAM-ALTERING.md).

---

## Headless constraints

| Allowed remotely | Not without physical access |
|------------------|----------------------------|
| GRUB / Ansible kernel params | BIOS Setup UI changes |
| `qm set` / `pct set` | `setup_var.efi` / UEFI shell |
| `read-live-bios-settings.py` | CMOS clear recovery |
| Single-byte efivarfs + **VarStore backup** restore | Power Supply Idle (deferred) |

If SSH does not return after a reboot, recovery requires local access — treat that as **unacceptable** for routine tuning. Software-first ordering maximizes wins before any NVRAM write.

---

## Memory balloon

| VM | `balloon` floor | QMP `actual` (2026-07-22) | Reclaiming? |
|----|-----------------|---------------------------|-------------|
| 101 homeassistant | 512 MiB | 5120 (= max) | No — host has free RAM |
| 102 ubuntu-cloud | 512 MiB | 4096 (= max) | No |

Proxmox + virtio balloon are **configured**. Reclaim requires **host memory pressure** or **lower static `memory:`**. Do not count balloon for plug savings on this host today. Details: [live-audit-2026-07-22.md](analysis/p2.20b/live-audit-2026-07-22.md).

---

## Guest inventory (live 2026-07-22)

| ID | Name | Status | RAM | vCPU | IP | Power notes |
|----|------|--------|-----|------|-----|-------------|
| 101 | homeassistant | running | 5120 MiB (RSS ~5.1G) | 4 | 192.168.1.240 | Zigbee plug + AX200 + dongle passthrough |
| 102 | ubuntu-cloud | running | 4096 MiB (RSS ~1.3G) | 8, `cpu: host` | 192.168.1.83 | Docker (Caddy/Dagu/n8n/…); top idle suspect |
| 200 | tank | running | 512 MiB | 2 | 192.168.1.148 | Samba; ZFS bind mounts |

**No PBS VM (100).** vCPU total 14 on 12 host threads. Primary LAN is PCIe RTL8168 (`enp3s0`); USB 5G not attached this boot.

### Measurement constraint

Automated plug reads require **VM 101 running** (Zigbee2MQTT + Mosquitto). For bare-metal floor tests, capture watts manually before stopping VM 101.

---

## USB devices (evaluate every change)

| Device | Role | udev exclusion |
|--------|------|----------------|
| RTL9210 `0bda:9210` | Boot / `rpool` | **Yes** — must stay `on` |
| ASMedia `174c:5106` | ZFS USB SATA (when attached) | **Yes** |
| Realtek 5G `0bda:8157` | Alternate NIC (if used) | **Yes** — not present on 2026-07-22 boot; primary LAN is PCIe RTL8168 |
| Zigbee `1a86:55d4` | HA dongle (passthrough to VM 101) | **Yes** on host if not passed through |
| WD60PURX | Backup rotation | hdparm spindown; may not work through USB bridge |

---

## Reboot and settle detection

**All BIOS and kernel cmdline changes require reboot.** ([UEFI spec](https://uefi.org/specs/UEFI/2.10/03_Boot_Manager.html))

Do **not** wait a fixed 10 minutes. Record:

- `time_to_ssh_s` — reboot command → SSH responds
- `time_to_settled_s` — reboot → settle criteria met

**Settled** when **all** true for **3 checks, 60s apart**:

1. SSH to pve OK
2. `qm status 101` and `102` == running
3. `pct status 200` == running
4. `loadavg[0] < 2.0`
5. Plug power: last 3 samples within 3W (MQTT or HA API)
6. HA API returns `sensor.plug2_ikea_energy_power` (entity not `unavailable`)

Then take **5 plug samples** (median = result).

---

## Safe test plan (48h soak **only at the end**)

### Phase 0 — Document baseline (no changes)

1. Run `read-live-bios-settings.py` on pve (read-only); save to `analysis/p2.20b/live-readback-YYYY-MM-DD.md`.
2. Check efivarfs health: `ls /sys/firmware/efi/efivars/dump-* 2>/dev/null` (delete `dump-*` only if present and [Arch Wiki](https://wiki.archlinux.org/title/Unified_Extensible_Firmware_Interface#Userspace_tools_are_unable_to_modify_UEFI_variable_data) applies).
3. Note whether ASRock **UEFI Variables Protection** / runtime write lock is documented (often not visible without local BIOS).
4. Capture: cmdline, governor, ASPM policy + `lspci` link ASPM, cpuidle names, powertop HTML (read-only).
5. **Power-state audit** (record in CSV `notes`):
   - `cat /sys/power/state /sys/power/mem_sleep`
   - `cpuidle` state names on cpu0
   - `dmidecode -s bios-version` (expect P2.20B)
6. `measure-idle-power.sh --baseline` (when script exists) or manual HA/MQTT median.
7. Optional: bare-metal floor — manual plug read before stopping VM 101.

### Phase 1 — GRUB (fully remote)

| Step | Action | Reboot? |
|------|--------|---------|
| 1.1 | Add `pcie_aspm=force` via `proxmox-boot-tool` / `/etc/kernel/cmdline` | **Yes** |
| 1.2 | Verify downstream ASPM in `lspci -vv` | after reboot |
| 1.3 | Measure plug delta vs Phase 0 | after settle |

**Rollback:** remove param, `proxmox-boot-tool refresh`, reboot.

### Phase 2 — VM tuning (fully remote, before NVRAM)

| Step | Action | Reboot? |
|------|--------|---------|
| 2.1 | VM 102 cores 8→4 (one change) | VM restart |
| 2.2 | Measure after settle | — |
| 2.3 | VM 102 RAM 4096→3072 (optional, separate cycle) | VM restart |

**Rollback:** `qm set 102 --cores 8` / `--memory 4096`.

### Phase 3 — Powertop audit (read-only)

```bash
powertop --html=/root/powertop-$(date +%F).html
```

Compare to Ansible udev/tmpfiles. **Do not** `powertop --auto-tune`. On AC-powered desktops PowerTOP has no total-watt reading — use the IKEA plug for deltas.

**Post-reboot measurement:** prefer `measure-idle-power.sh --quick` — waits for **QUICK_LOAD_CHECKS** consecutive idle samples (default 2, 30 s apart): `loadavg < QUICK_LOAD_MAX` (default 1.0) **and** no ZFS scrub/send/recv, systemd `scrub@`/`zfs-*` jobs, or active zrepl replication/snapshot. Prefer over full `--wait-settle` plug-spread loops on this plug.

### Phase 4 — NVRAM (efivarfs, one byte per reboot)

**Headless only** — no BIOS UI. See [NVRAM-ALTERING.md](NVRAM-ALTERING.md).

Before first write:

1. Backup full VarStore blobs to `/root/nvram-backup/DATE/`.
2. Confirm target offset: live value in IFR valid set, not `0xFF`.
3. Skip if already at recommendation.

Order (safest first):

| Step | Setting | VarStore | Offset |
|------|---------|----------|--------|
| 4a | HD Audio → Disabled | `AmdSetup` | `0x0F9` |
| 4b | WLAN → Disabled (keep BT on) | `AMD_PBS_SETUP` | `0x014` |
| 4c | CPPC → Enabled | `AmdSetup` | `0x145` |
| 4d | DF Cstates → Enabled | `AmdSetup` | `0x13E` |
| 4e | PM L1 SS → L1.1_L1.2 (optional) | `AMD_PBS_SETUP` | `0x025` |

After each: `read-live-bios-settings.py`, settle, plug median, `zpool status`, `dmesg` tail.

**Rollback:** restore backed-up efivar file over SSH (`chattr -i` then `cp`).

**Do not script:** `AmdSetup 0x0FC` (Power Supply Idle), any `Setup` offset, bulk `apply-bios-settings.sh --apply`.

### Phase 5 — Power Supply Idle — **deferred (not headless)**

Highest reward but highest USB-boot risk. Requires BIOS UI or validated `0x0FC` write **and** physical recovery if SSH fails. **Out of scope** until user schedules local access.

### Phase 6 — **48h soak (end only)**

Run **after** all intended changes are applied and short-term measurements look good:

- Monitor USB boot pool, LAN, ZFS, `dmesg` for USB resets
- Spot-check plug power daily
- Only then call tuning "production ready"

---

## Results log

Append rows to `results/power-tuning.csv`:

```csv
timestamp,label,plug_w_median,loadavg1,time_to_settled_s,cc6_visible,aspm_downstream,disk_state,mem_sleep,cpuidle_max,notes
```

---

## Scripts

| Script | Purpose |
|--------|---------|
| `read-live-bios-settings.py` | Read-only NVRAM |
| `scripts/measure-idle-power.sh` | HA/z2m plug sampling, settle detection, CSV log |
| `scripts/nvram-write-byte.sh` | Single-byte efivarfs write with backup (headless) |
| `NVRAM-ALTERING.md` | Community guidance + headless efivarfs policy |
| `apply-bios-settings.sh` | **Dry-run only**; `--apply` disabled |
