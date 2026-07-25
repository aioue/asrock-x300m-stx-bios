# Power tuning research — ASRock X300M-STX / DeskMini

Collected references, skepticism notes, Proxmox-specific quirks, and hypotheses for the Study Proxmox DeskMini (P2.20B, Ryzen 5 PRO 5650G). Measurement workflow and scripts: see [POWER-TUNING-RUNBOOK.md](POWER-TUNING-RUNBOOK.md).

**Attribution:** Literature review and live-host audit compiled with [Cursor](https://cursor.com) (Composer 2.5), April–July 2026.

---

## Community BIOS / DeskMini / DeskMeet tuning

| Source | Platform | Claim / approach | Skepticism / notes |
|--------|----------|------------------|-------------------|
| [ASRock forum — "only C3 C-state"](https://forum.asrock.com/forum_posts.asp?TID=32927) | B550M + 4750G Pro server | ~18–19W idle bare; only C3 in powertop; suggests Global C-state + **Typical** Power Supply Idle | **Conflicts** with [Arch Wiki Ryzen](https://wiki.archlinux.org/title/Ryzen) (Typical *limits* deep idle; Low Current enables CC6). Same "C3 only" symptom as our host. AMISCE hidden-BIOS unlock mentioned — **not recommended** (brick risk). |
| [ASRock forum — DeskMini X300 cTDP](https://forum.asrock.com/forum_posts.asp?TID=17374) | DeskMini X300 | CBS/cTDP menus missing on early X300 BIOS; beta BIOS rumoured | X300 firmware historically **gimped** vs A300 for CBS options. P2.20B on our board exposes CBS via IFR; cTDP is load-cap only. |
| [ASRock forum — DeskMini X300 CPU boost voltage](https://forum.asrock.com/forum_posts.asp?TID=26242) | X300 + 5700G | High idle voltage/temp; disabling CPB drops idle temp | Load/idle voltage behaviour — not a substitute for C-state/ASPM tuning. |
| [FreeBSD drm-kmod #318](https://github.com/freebsd/drm-kmod/issues/318) | **DeskMini X300** + 5600G | Global C-state caused iGPU flicker; `machdep.idle=mwait` workaround | Relevant to **C-state + amdgpu** interaction on X300; headless Proxmox may still hit shallow idle without iGPU symptoms. |
| [SmallFormFactor — P2.10 X300 BIOS thread](https://smallformfactor.net/forum/threads/28-04-2025-asrock-deskmini-a-x300-bios-p2-10-sl02-curve-optimizer-fixed-native-s3-p2-10b-acs-p2-10-for-x300-agesav2-pi-1-2-0-e.18423/) | DeskMini A/X300 | Community BIOS **P2.10B** (ACS), **P2.10.SL02** (S3) | Our **P2.20B** is the ACS/ARI line (same intent as P2.10B). S3 variants irrelevant for 24/7 server. |
| [SmallFormFactor — P2.20 X300 BIOS thread](https://smallformfactor.net/forum/threads/06-05-2026-asrock-deskmini-a-x300-bios-p2-20-final-p2-20-sl01-native-s3-p2-20a-ss-disabled-p2-20b-acs-on-agesav2-pi-1-2-0-10.18423/) | DeskMini A/X300 P2.20 line | **P2.20** (final), **P2.20.SL01** (native S3), **P2.20A** (SS off), **P2.20B** (ACS on) | We run **P2.20B**. [Post #295578](https://smallformfactor.net/forum/threads/06-05-2026-asrock-deskmini-a-x300-bios-p2-20-final-p2-20-sl01-native-s3-p2-20a-ss-disabled-p2-20b-acs-on-agesav2-pi-1-2-0-10.18423/page-16#post-295578) = **our** obrida P2.20B ACS zip. Optional follow-up: IFR decompile + live read-back vs thread S3/Modern Standby claims — see [FORUM-REPLY-NOTES.md](FORUM-REPLY-NOTES.md). **We will not install P2.20.SL01.** |
| [Lorenz Brun — S3 on X300](https://lorenz.brun.one/enabling-s3-sleep-on-x300/) | DeskMini X300 | S3 blocked in ACPI DSDT; override via custom DSDT | Interesting firmware quirk; not used for always-on Proxmox. |
| [aioue.net — deconstructing X300 BIOS](https://aioue.net/2026/04/25/deconstructing-asrock-x300-bios-power-options/) | X300M-STX P2.20B | IFR extraction, live efivar read-back, conservative staged tuning | **Primary source** for this repo. Live `Setup-*` missing; `0x0FC` reads `0xFF`. |
| [NVRAM-ALTERING.md](NVRAM-ALTERING.md) | X300 P2.20B | Community tools, headless constraints, efivarfs ladder | **Execution policy** for online BIOS changes (July 2026). |
| [Reddit r/Amd — C6 / power supply idle](https://www.reddit.com/r/Amd/comments/8yzvxz/ryzen_c6_state_sleep_power_supply_common_current/) | Ryzen AM4 (linked from ASRock forum) | PSS Support / power supply idle paths | Old thread; naming differs on modern CBS. Cross-check with IFR, not forum labels alone. |

**DeskMeet:** No strong DeskMeet-specific power threads found in this pass. DeskMeet shares the same STX/X300 family patterns; treat DeskMini X300 research as applicable unless board-specific IFR differs.

### P2.20 variant line (June 2026 thread)

Community-maintained BIOS drops on [SFF.Network thread 18423 (P2.20)](https://smallformfactor.net/forum/threads/06-05-2026-asrock-deskmini-a-x300-bios-p2-20-final-p2-20-sl01-native-s3-p2-20a-ss-disabled-p2-20b-acs-on-agesav2-pi-1-2-0-10.18423/):

| Variant | Intent | Our use |
|---------|--------|---------|
| **P2.20** | ASRock "final" AGESAv2 1.2.0.10 | — |
| **P2.20.SL01** | Native **S3** ACPI (sleep) restored | **Not installing** — see below |
| **P2.20A** | Spread spectrum disabled | Optional curiosity only |
| **P2.20B** | ACS enabled by default (IOMMU groups) | **Installed** on Study Proxmox |

Historical pattern (same thread family back to P1.80): ASRock support periodically ships **`.SLxx`** test BIOS builds that fix broken ACPI sleep tables while "final" builds omit S3 again ([1.80E had S3, 1.80F removed it](https://smallformfactor.net/forum/threads/28-04-2025-asrock-deskmini-a-x300-bios-p2-10-sl02-curve-optimizer-fixed-native-s3-p2-10b-acs-p2-10-for-x300-agesav2-pi-1-2-0-e.18423/); [gollum.name notes S3 variants caused other problems](https://gollum.name/posts/mini-pc/)). [Lorenz Brun](https://lorenz.brun.one/enabling-s3-sleep-on-x300/) documents a DSDT typo (`XS3` vs `_S3`) on X300 — firmware ACPI bug, not a Linux driver issue.

**Skepticism on "install SL01 for idle power":** S3 is **suspend-to-RAM** (machine asleep). It does **not** automatically fix **runtime** package idle (CC6) on an always-on server. Some forum posts conflate "power states" / ACPI bugs with shallow **C3-only** idle — treat as **hypothesis**, not proven for P2.20B. Our path stays CBS tuning (DF Cstates, Power Supply Idle) + `pcie_aspm=force`, not a BIOS variant swap.

---

## ACPI sleep vs runtime idle states

**Live audit — Study Proxmox (192.168.1.10), 2026-07-22, BIOS P2.20B:**

**Host uptime (verified 21:06):** boot **2026-07-22 20:32**; `uptime` **~34 min** (prior session **39+ days** until 20:29). Fresh reboot — good baseline window for Phase 0.

| Layer | States available | Evidence | Notes |
|-------|------------------|----------|-------|
| **ACPI sleep** (`/sys/power/state`) | `freeze`, `mem` only | `cat /sys/power/state` | No `disk` (hibernate). |
| **Suspend flavour** (`mem_sleep`) | **`[s2idle]`** only | `cat /sys/power/mem_sleep` | Modern Standby / ACPI s2idle path — **not** classic S3 STR. Matches BIOS `S3/Modern Standby Support` = Modern Standby (`0x01`), not S3 (`0x03`) from prior read-back. |
| **DSDT sleep table** | **`XS3` present, `_S3` absent** | `acpidump` + `iasl -d dsdt.dat` on P2.20B (2026-07-22): `Name (XS3, Package` at line 3806; **0** `_S3` symbols | Confirms [Lorenz Brun DSDT typo](https://lorenz.brun.one/enabling-s3-sleep-on-x300/) on **our** firmware. P2.20.SL01 would fix this for suspend — we are not installing it. |
| **Runtime CPU idle** (`cpuidle` / `cpupower idle-info`) | **POLL, C1, C2, C3** — **no CC6/C6** | All CPUs; driver `acpi_idle` | Shallow idle — main plug-power gap vs tuned Ryzen hosts. |
| **turbostat (8s idle sample)** | **~90% C3**, **PkgWatt ~14.1W** | `turbostat` with guests running; Busy% ~1.2% | Package power ≠ wall plug (~45–50W with disks/VMs). **No C6/CC6 columns populated.** |
| **PCIe ASPM** | Root ports: **ASPM Disabled**; one downstream link L0s L1 enabled | `lspci -vv` | Confirms need for `pcie_aspm=force`. |
| **EPP / governor** | `amd-pstate-epp`, `powersave`, `balance_power` | sysfs | OS side OK; does not create CC6 if firmware blocks it. |

**Tools used (CLI only, no daemons):** `linux-cpupower` (`turbostat`, `cpupower`), `acpica-tools` (`acpidump`, `iasl`). Left installed on pve for tuning phases — remove with `apt purge linux-cpupower acpica-tools` if undesired.

**SFF thread post [#295578](https://smallformfactor.net/forum/threads/06-05-2026-asrock-deskmini-a-x300-bios-p2-20-final-p2-20-sl01-native-s3-p2-20a-ss-disabled-p2-20b-acs-on-agesav2-pi-1-2-0-10.18423/page-16#post-295578) (page 16, obrida = us, 2026):** Our **X3MSTX_2.20B.zip** share (ACS for IOMMU). Nearby posts discuss **S3** (2z0; Televisor / JZ **2.20JZ** vs **2.20 noS3**), **P2.20A**, Aleo on **Modern Standby** in BIOS. Follow-up posts should cite **IFR decompile + live P2.20B measurements** only where they confirm or disprove those claims — see [FORUM-REPLY-NOTES.md](FORUM-REPLY-NOTES.md).

**What we reach today:** The host uses **C3 as deepest runtime idle** and **s2idle** if suspend were invoked — it does **not** expose S3 STR or CC6. That aligns with "final" (non-SL) X300 BIOS behaviour and matches [ASRock forum "only C3"](https://forum.asrock.com/forum_posts.asp?TID=32927) reports.

**Re-check after each BIOS change** (add to measurement script / Phase 0):

```bash
cat /sys/power/state /sys/power/mem_sleep
for s in /sys/devices/system/cpu/cpu0/cpuidle/state*/name; do cat "$s"; done
# Optional: powertop Idle stats tab, or turbostat C6%/CC6% if installed
```

**Decision:** Do **not** flash **P2.20.SL01** for this project. Optional obrida forum follow-up with decompile/live evidence on S3 posts (not advocacy for SL01).

---

## Proxmox / Linux tuning — applied vs actually effective

Live audit on **pve** (192.168.1.10), 2026-07-22, kernel `6.17.9-1-pve`.

### What Ansible *has* applied (confirmed on host)

| Setting | Expected | Observed | Source in proxmox-setup |
|---------|----------|----------|-------------------------|
| CPU governor `powersave` | On | **Yes** | `roles/proxmox-host/tasks/power-management.yml` |
| EPP `balance_power` | On | **Yes** (cpu-epp oneshot ran at boot) | same |
| `amd-pstate-epp` driver | Active | **Yes** | kernel default on 6.x |
| PCIe ASPM **policy** `powersupersave` | On | **Yes** (sysfs) | tmpfiles.d `pcie-aspm.conf` |
| SATA ALPM `med_power_with_dipm` | On | **Yes** (host0) | tmpfiles.d `sata-alpm.conf` |
| USB autosuspend + exclusions | On | **Yes** (udev rules present) | `60-usb-powersave.rules` |
| PCI runtime PM udev | On | **Yes** | `60-pci-powersave.rules` |
| HD Audio `power_save=10` | modprobe | **Yes** | `audio-powersave.conf` |
| NMI watchdog off | sysctl | **Yes** | `60-power-save.conf` |
| KSM/ksmtuned | Tuned | **Yes** | `ksmtuned.conf` |
| powertop package | Installed | **Yes** (v2.15) | `main.yml` apt |

### What is configured but **not effective** (tuning "invisible" at the plug)

| Gap | Evidence | Why plug power stays high |
|-----|----------|---------------------------|
| **`pcie_aspm=force` missing from kernel cmdline** | `/proc/cmdline` has only `amd_iommu=on iommu=pt`; `/etc/kernel/cmdline` has no ASPM; downstream `lspci` shows **ASPM Disabled** on NVMe/LAN/WiFi | Sysfs `powersupersave` cannot enable ASPM when firmware disabled link PM ([kernel Kconfig](https://github.com/torvalds/linux/blob/master/drivers/pci/pcie/Kconfig), [RHEL ASPM guide](https://docs.redhat.com/en/documentation/red_hat_enterprise_linux/7/html/power_management_guide/aspm)). Gated behind `proxmox_initial_setup_enabled: false` in Ansible. |
| **Shallow CPU idle (max C3, no CC6)** | `cpuidle` only POLL/C1/C2/C3 | Firmware/PSI issue (`AmdSetup 0x0FC` = `0xFF`), not governor. OS cannot fix without BIOS. |
| **High cpufreq at idle** | cpu0 ~3.5 GHz despite powersave | KVM guests + shallow C-states; EPP allows burst. |
| **`amd_pstate=active` not in cmdline** | Not in `/proc/cmdline` | Driver still loads as `amd-pstate-epp` on this kernel — **low priority** to add. |
| **powertop `--auto-tune` not persisted** | No `powertop.service` | Most tunables already hand-rolled in Ansible; see [Powertop](#powertop) below. |

### Proxmox-specific threads (online)

| Thread | Takeaway | Relevance here |
|--------|----------|----------------|
| [PVE idle higher than Windows](https://forum.proxmox.com/threads/idle-power-usage-on-bare-metal-higher-with-fresh-proxmox-ve-8-install-than-windows-11.164229/) | PVE defaults to performance mindset; C-states + ASPM in GRUB + powertop suggested | Same playbook we're using; tuned-adm saved only ~4W for one user |
| [Since PVE 7.3 higher power](https://forum.proxmox.com/threads/since-proxmox-7-3-higher-power-usage.124869/) | Kernel/driver change (r8169 vs r8168) left ASPM broken → **stuck at C3** | Analogous failure mode: **wrong driver or ASPM off looks like "Linux tuning failed"**. Our Realtek is PCIe `r8169` + separate USB 5G NIC. |
| [powertop on PVE](https://forum.proxmox.com/threads/powertop.89251/) | OK for many tunables; **avoid** CPU freq scaling with Ceph; use external meter | Stability-first; measure at plug |
| [HA PSA — Proxmox lower power](https://community.home-assistant.io/t/psa-how-to-configure-proxmox-for-lower-power-usage/323731) | Governor to powersave — **already done** | |
| [Technologie Hub — Proxmox powersaving](https://technologiehub.at/project-posts/tutorial/guide-for-proxmox-powersaving/) | cpupower, tuned, powertop, disk spindown | `tuned` **inactive** on our host (good — we use custom tmpfiles/udev) |

---

## Hypotheses (including operator ideas)

| # | Hypothesis | Evidence for | Evidence against | Safe test |
|---|------------|--------------|------------------|-----------|
| H1 | **Ansible OS tuning is applied but PCIe ASPM never engaged** | sysfs policy set; links ASPM Disabled; no `pcie_aspm=force` | — | Add kernel param; `lspci -vv`; plug measure |
| H2 | **BIOS blocks deep idle (CC6)** — Linux looks "broken" | C3 max; `0x0FC` = `0xFF`; matches ASRock forum C3-only reports | Global C-state already Enabled | BIOS UI: DF Cstates, then PSI last; watch cpuidle names |
| H3 | **USB storage chain adds watts** (boot NVMe adapter, backup HDD when attached) | RTL9210 boot; WD60 +4–7W spinning ([WD white paper](https://documents.westerndigital.com/content/dam/doc-library/en_us/assets/public/western-digital/collateral/white-paper/white-paper-storage-power-efficiency-improvement-with-hdd-idle-modes.pdf)) | Backup disk not attached 2026-07-22 | Log `hdparm -C` + `zpool list` every sample |
| H4 | **VMs prevent package idle** — 15W impossible with current workload | 12 vCPUs allocated, HA 5GB RAM | Bare-metal test can isolate | One measurement with VMs stopped |
| H5 | **Proxmox/KVM timer interrupts keep CPU shallow** | Common on hypervisors | Still should improve with ASPM/BIOS | Compare host metrics before/after |
| H6 | **powertop --auto-tune would help** | Not all tunables hand-applied | USB host already has curated udev; auto-tune may **override** exclusions ([Kirsle wiki](https://www.kirsle.net/wiki/PowerTOP-and-USB-Autosuspend), [Arch Wiki powertop](https://wiki.archlinux.org/title/Powertop)) | **Report only** (`powertop --html`); do not enable auto-tune on USB-critical host without exclusions |
| H7 | **~15W target was bare-metal minimal** | [5700G 16–18W](https://sebastianharnisch.de/amd-ryzen-7-5700g-as-a-home-server/) with NVMe, no VMs | 3 guests + multi-disk today | Document floor vs operational target |
| H8 | **P2.20 ACPI "powerstate bugs" (SFF thread) explain C3-only idle** | Long X300 history of broken sleep ACPI; SL variants fix `_S3` | S3 fix ≠ proven CC6 fix; we run P2.20B + Modern Standby, not SL01 | Log cpuidle names before/after BIOS; **do not** flash SL01 |
| H9 | **VM 102 `cpu: host` + 8 vCPUs** block package idle | 8/12 threads in guest; live config verified 2026-07-22 | Phase 5a: cores 8→4, plug measure |
| H10 | **VM 101 balloon not reclaiming** | KVM RSS ~5.1 GiB; QMP `actual=5120`; host 16 GiB free | **Configured correctly** — PVE won't inflate balloon without host pressure; use static RAM cut (Phase 5) not balloon for power |
| H11 | **5 always-on drives + zrepl** set storage floor | rpool USB NVMe + fast/slow mirrors; zrepl active | Bare-metal vs operational comparison |

---

## Memory balloon (Proxmox / HA)

Live check 2026-07-22 — see [live-audit-2026-07-22.md](analysis/p2.20b/live-audit-2026-07-22.md).

| Component | Status |
|-----------|--------|
| `balloon: 512` on VM 101/102 | **Set** |
| `virtio-balloon-pci` + `free-page-reporting=on` | **Present** |
| HA `virtio_balloon` module | **Loaded** |
| QMP `actual` | **Full allocation** (no reclaim) |

`balloon: 512` is the **minimum floor** when PVE inflates the balloon under **host memory pressure** — not automatic guest RAM trim. With **16 GiB host free**, expect **no reclaim**. Fix misleading Ansible “auto-deflation” comment on execute.

---

## Risk / reward execution order (headless)

Study Proxmox is **headless** — no routine keyboard/monitor. Prefer **SSH-reversible** changes; defer anything that needs BIOS UI or UEFI shell for recovery. Full policy: [NVRAM-ALTERING.md](NVRAM-ALTERING.md).

One change → reboot (if needed) → settle → plug median. **Never combine BIOS + GRUB + VM changes in one cycle.** **VM 101 must stay running** for automated plug reads.

| Pri | Step | Est. Δ | Risk | Reboot | Headless rollback |
|-----|------|--------|------|--------|-------------------|
| 0 | Baseline + NVRAM read + efivarfs probe | — | None | No | N/A |
| 1 | `pcie_aspm=force` | 2–5 W | **Low** | Host | Ansible / GRUB revert |
| 2 | VM102 cores 8→4 | 1–3 W? | **Low** | VM restart | `qm set` revert |
| 3 | VM102 RAM 4096→3072 (optional) | Low | **Low** | VM restart | `qm set` revert |
| 4 | Powertop HTML (read-only) | — | None | No | N/A |
| 5a | NVRAM: HD Audio off (`0x0F9`) | Low | **Low** | Host | VarStore backup restore |
| 5b | NVRAM: WLAN off, BT on (`0x014`) | Low | Low | Host | backup restore |
| 5c | NVRAM: CPPC on (`0x145`) | Low | Low | Host | backup restore |
| 5d | NVRAM: DF Cstates on (`0x13E`) | Med | **Med** | Host | backup restore |
| 5e | NVRAM: PM L1 SS (`0x025`) | Med | **Med** | Host | backup restore; **skip if SSH flaky post-reboot** |
| **skip** | Power Supply Idle (`0x0FC` / BIOS UI) | 3–8 W | **High** | Host | Needs physical access if USB boot fails — **not headless** |
| 6 | 48h soak | — | — | End | — |

**Never:** P2.20.SL01, bulk `apply-bios-settings.sh --apply`, script `0x0FC` while live=`0xFF`, `powertop --auto-tune`, BIOS Setup UI (no display), `setup_var.efi`. **Defer:** balloon (already OK); PSI until physical-access window. Forum: [FORUM-REPLY-NOTES.md](FORUM-REPLY-NOTES.md).

**NVRAM writes:** one offset per reboot; full VarStore backup before each write; skip if live byte not in IFR valid set. No UI-offset calibration unless user schedules local access.

---

| Topic | Guidance | Source |
|-------|----------|--------|
| What it does | Reports wakeups, idle stats, tunables; `--auto-tune` sets all "Good" | [Arch Wiki — Powertop](https://wiki.archlinux.org/title/Powertop) |
| Persistence | **Not persistent** across reboot unless systemd service | [Ask Ubuntu — permanent powertop](https://askubuntu.com/questions/112705/how-do-i-make-powertop-changes-permanent) |
| USB risk | Auto-tune sets USB `auto` suspend — mice/storage disconnect | [Kirsle — PowerTOP and USB Autosuspend](https://www.kirsle.net/wiki/PowerTOP-and-USB-Autosuspend) |
| Server caution | PVE forum: skip aggressive CPU freq scaling on storage clusters | [Proxmox forum — powertop](https://forum.proxmox.com/threads/powertop.89251/) |
| This host | powertop **installed**, Ansible already implements selective tunables + USB denylist | Live audit 2026-07-22 |

**Recommended use here:** `powertop --html=/tmp/powertop.html` (or `--csv`) as a **read-only baseline** before/after changes. **Do not** deploy `powertop --auto-tune` as a service without `ExecStartPost` re-applying USB `power/control=on` for `0bda:9210`, `174c:5106`, `0bda:8157`, `1a86:55d4` ([sherbibv/proxmox-setup example](https://github.com/sherbibv/proxmox-setup)).

---

## BIOS changes and reboot

| Change type | Reboot required? | Source |
|-------------|------------------|--------|
| BIOS UI / NVRAM | **Yes** — next platform reset | [UEFI 2.10 Boot Manager](https://uefi.org/specs/UEFI/2.10/03_Boot_Manager.html) |
| GRUB / `proxmox-boot-tool` kernel cmdline | **Yes** | boot-time only |
| sysfs / tmpfiles / udev | Immediate (re-applied early boot) | — |

**Do not use fixed post-reboot wait times.** Prefer `measure-idle-power.sh --quick` (waits for `loadavg < QUICK_LOAD_MAX`, default 1.0) or full `--wait-settle` (load + plug spread). See runbook.

---

## PCIe ASPM audit (July 2026)

`pcie_aspm=force` is in the kernel cmdline and sysfs policy is `powersupersave`, but **endpoint ASPM remains disabled** on the links that matter for idle power:

| BDF | Device | Bridge parent | Bridge `LnkCap` ASPM | Endpoint `LnkCtl` |
|-----|--------|---------------|----------------------|-------------------|
| `01:00.0` | Micron NVMe | `00:01.1` | **not supported** | ASPM Disabled |
| `02:00.0` | Micron NVMe | `00:02.1` | **not supported** | ASPM Disabled |
| `03:00.0` | RTL8111 NIC | `00:02.3` | **not supported** | ASPM Disabled |
| `04:00.0` | AX200 (vfio → HA) | `00:02.4` | **not supported** | ASPM Disabled |
| `05:00.x` | iGPU / USB / PSP | `00:08.1` | L0s L1 | **ASPM L0s L1 Enabled** |
| `06:00.0` | SATA AHCI | `00:08.2` | L0s L1 | **ASPM L0s L1 Enabled** |

**Root cause:** Renoir/Cezanne **GPP bridges** to the M.2 and NIC slots advertise `ASPM not supported` in `LnkCap`. Linux will not enable ASPM on downstream endpoints when the upstream port does not participate — `pcie_aspm=force` only overrides the *global* ACPI disable bit, not missing bridge capability.

**PM L1 SS (NVRAM `0x025 = 0x03`):** BIOS byte applies (`matches_recommendation`) but `L1SubCtl1` stays all `-` on NVMe/NIC/AX200 because **L1 substates require ASPM L1 on the link first**. No measurable plug delta at settled idle (23.0 W → 24.2 W, noise). Left enabled after retry — no harm observed.

**Not fixable from OS alone** without firmware/ACPI changes or risky bridge quirks. `Power Supply Idle Control` (`0x0FC`) remains the larger firmware lever but is deferred (USB boot risk, headless recovery).

**Drivers:** `r8169` has no ASPM module param; AX200 is `vfio-pci` passthrough to VM 101 (Wi-Fi disabled in NVRAM but device still bound). iwlwifi would keep the radio alive if loaded — blacklist is a separate ~0.5 W experiment.

---

## Incremental savings vs absolute watts (correction)

The table in `bios-power-settings-p2.20.md` lists impacts like "10–25W idle reduction" for Global C-state — that means **recovery from a disabled C-state baseline**, not "machine will draw 10W". With VMs and storage, realistic operational targets are in [POWER-TUNING-RUNBOOK.md](POWER-TUNING-RUNBOOK.md).
