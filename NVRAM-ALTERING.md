# Online BIOS / NVRAM altering — community guidance

How others change AMI BIOS settings from the OS or pre-boot environment, and how that applies to **Study Proxmox** (DeskMini X300M-STX, P2.20B, headless).

Operational ordering: [POWER-TUNING-RUNBOOK.md](POWER-TUNING-RUNBOOK.md). IFR offsets: [bios-power-settings-p2.20b.md](bios-power-settings-p2.20b.md).

**Attribution:** Compiled with [Cursor](https://cursor.com) (Composer 2.5), July 2026.

---

## Headless constraint (Study Proxmox)

The host has **no IPMI and no routine keyboard/monitor**. Recovery via BIOS menus, UEFI shell, or CMOS jumper is **not acceptable** for routine tuning.

| Method | Headless? | Remote rollback? | Use on this host |
|--------|-----------|------------------|------------------|
| GRUB / kernel cmdline (`pcie_aspm=force`) | Yes | Yes (Ansible + reboot) | **Primary** |
| VM/LXC sizing (`qm set`, `pct set`) | Yes | Yes | **Primary** |
| `read-live-bios-settings.py` (efivarfs read) | Yes | N/A | **Always** |
| Single-byte efivarfs write + **full VarStore backup** | Yes | Yes (restore blob over SSH) | **Conditional** — after write probe + gates |
| BIOS Setup UI | No | No | **Avoid** — requires local display |
| `setup_var.efi` / modGRUB from UEFI shell | No | No | **Not planned** |
| Bulk `apply-bios-settings.sh --apply` | Partial | Partial | **Never** (disabled; wrong targets) |
| Power Supply Idle (`0x0FC`) | Maybe | Maybe | **Deferred** — high USB-boot risk; offset unvalidated (`0xFF` in April read) |

**Recovery without keyboard:** only paths that work over SSH after POST — revert GRUB, restore NVRAM backup files, `qm set` rollback. If the host does not reach SSH, recovery needs **scheduled physical access** (out of scope for this runbook).

---

## Standard community workflow

1. Extract IFR from BIOS ROM — [UEFITool](https://github.com/LongSoft/UEFITool) + [Universal IFR Extractor](https://github.com/LongSoft/Universal-IFR-Extractor) (our `analyze-bios-rom.sh`).
2. Map setting → **VarStore name** + **offset** + legal values.
3. Read live byte from `/sys/firmware/efi/efivars/` (`read-live-bios-settings.py`).
4. Validate — UI toggle + read-back, or read from `setup_var.efi` (needs display).
5. Write one byte; reboot; verify.

**IFR offset alone is not proof** on live firmware. Prefer read-back showing a **known legal value** before writing.

---

## Tools and precedents

| Resource | Role |
|----------|------|
| [datasone/setup_var.efi](https://github.com/datasone/setup_var.efi) | Read/write `Setup`/`AmdSetup` from **UEFI shell**; batch configs |
| [EnumC/grub-mod-amd-cbs-setup_var](https://github.com/EnumC/grub-mod-amd-cbs-setup_var) | GRUB mod targeting **`AmdSetup`** for AMD CBS |
| [Baker76 — X300 IOMMU](https://www.baker76.com/2021/08/26/asrock-deskmini-x300-iommu/) | DeskMini: two `AmdSetup` modules (**RN** ~1448 B, **RV** ~1447 B); offsets **BIOS-version-specific** (documented for 1.70) |
| [Win-Raid X300 owners thread](https://winraid.level1techs.com/t/asrock-deskmini-x300-owners-thread/36422) | X300 CBS / hidden menus / RN vs RV |
| [linuxboot/uefisettings](https://github.com/linuxboot/uefisettings) | Rust HII parser — optional read-only probe if HiiDB exposed |
| [SCEHUB — ASRock](https://github.com/ab3lkaizen/SCEHUB#asrock) | **Runtime variable write protection**; may need "Password protection of Runtime Variables" disabled (often hidden) |
| [Arch Wiki — efivarfs](https://wiki.archlinux.org/title/Unified_Extensible_Firmware_Interface#Userspace_tools_are_unable_to_modify_UEFI_variable_data) | Delete `dump-*`, `chattr -i`; avoid `efi_no_storage_paranoia` |
| [Lorenz Brun — S3 on X300](https://lorenz.brun.one/enabling-s3-sleep-on-x300/) | ACPI `XS3` typo — **DSDT override**, not NVRAM power-idle tuning |

---

## X300 / P2.20B specifics

- **`AmdSetup` RN vs RV:** RN holds most CBS power options; **RV** holds FCH options including **Power Supply Idle** (`0x0FC`). Disambiguate by efivar **data size** (see Baker76).
- **`0xFF` / `0x0F`:** Usually Auto / uninitialized — do not treat as a valid write target.
- **April 2026 live read:** `Setup-*` efivar missing; `0x0FC` = `0xFF` — bulk apply script correctly disabled.
- **P2.20B** includes ACS/ARI in firmware (community build we run); do not touch IOMMU/ACS/ARI offsets.

---

## Write safety (from-host)

| Outcome | Typical recovery |
|---------|------------------|
| Wrong setting, SSH OK | Restore VarStore backup over SSH or write original byte |
| OS won't boot, POST OK | Needs BIOS UI or CMOS clear — **not headless** |
| NVRAM corrupt | USB BIOS flash or SPI — **not headless** |

Our script uses read-modify-write on the **entire** efivar file. Always backup the full blob before any write:

```bash
mkdir -p /root/nvram-backup/$(date +%F)
cp /sys/firmware/efi/efivars/AmdSetup-3a997502-647a-4c82-998e-52ef9486a247 \
   /root/nvram-backup/$(date +%F)/
# repeat for AMD_PBS_SETUP-... etc.
```

**Pre-write probe (headless):** attempt a no-op or read-only write test only after confirming efivarfs accepts writes (see Phase 0 in runbook).

---

## Headless execution ladder

1. **Software only** — `pcie_aspm=force`, VM 102 cores/RAM (fully remote revert).
2. **Read-only audit** — `read-live-bios-settings.py`, `dump-*` check, optional `uefisettings` list.
3. **Low-risk NVRAM** — HD Audio (`0x0F9`), WLAN (`0x014`) if gates pass + backup.
4. **Medium-risk NVRAM** — CPPC (`0x145`), DF Cstates (`0x13E`) — one per reboot, backup each time.
5. **Higher-risk NVRAM** — PM L1 SS (`0x025`) — only if steps 1–4 stable and SSH returns reliably after reboot.
6. **Skip without physical access window** — Power Supply Idle (`0x0FC`), BIOS UI-only changes, `setup_var.efi`.

---

## What we will not do

- Bulk `apply-bios-settings.sh --apply` (disabled; includes wrong targets e.g. BT off, S3 on).
- Script `0x0FC` while live byte is `0xFF` or unknown.
- `efi_no_storage_paranoia`, AMISCE bulk import, Fusion Message C State, SATA DevSleep, ECO/cTDP.
- Any change without VarStore backup when writing from SSH.
