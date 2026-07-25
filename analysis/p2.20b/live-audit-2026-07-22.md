# Live host audit — 2026-07-22

Study Proxmox (`pve` @ 192.168.1.10), BIOS **P2.20B**, Ryzen 5 PRO 5650G.

**Attribution:** Captured with [Cursor](https://cursor.com) (Composer 2.5).

---

## Session context

| Item | Value |
|------|-------|
| Boot time | **2026-07-22 20:32** |
| Uptime at audit | **~34 min** (prior session 39+ days) |
| Kernel | 6.17.9-1-pve |
| Tools installed (CLI, no daemons) | `linux-cpupower`, `acpica-tools` |
| Audit artifact | `/tmp/power-audit-20260722-210628/report.txt` on pve |

---

## Guests (running)

| ID | Name | RAM alloc | KVM RSS | vCPU | IP | Notes |
|----|------|-----------|---------|------|-----|-------|
| 101 | homeassistant | 5120 MiB | ~5172 MiB | 4 | 192.168.1.240 | Zigbee plug + AX200 + dongle passthrough |
| 102 | ubuntu-cloud | 4096 MiB | ~1336 MiB | 8, `cpu: host` | 192.168.1.83 | Docker stacks |
| 200 | tank | 512 MiB | low | 2 | 192.168.1.148 | Samba, ZFS bind mounts |

---

## Runtime power states

| Layer | Result |
|-------|--------|
| `cpuidle` / `cpupower idle-info` | POLL, C1, C2, **C3 max** — no CC6 |
| `turbostat` (8s, guests running) | ~**90% C3**; **PkgWatt ~14.1 W** (not wall plug) |
| `/sys/power/mem_sleep` | `[s2idle]` only |
| DSDT (`acpidump` + `iasl`) | **`Name (XS3)`** present; **`_S3` absent** (0 matches) |
| PCIe ASPM | Root/downstream mostly **Disabled**; no `pcie_aspm=force` in cmdline |

---

## Balloon (2026-07-22)

| VM | `balloon` config | QMP `actual` | Guest driver | Reclaiming? |
|----|------------------|--------------|--------------|-------------|
| 101 | 512 (floor MiB) | **5120** (= max) | `virtio_balloon` loaded | **No** — guest ~2.7 GiB used, host has 16 GiB free |
| 102 | 512 | **4096** (= max) | virtio0 bound; dmesg: `Out of puff!` | **No** |

**Interpretation:** Proxmox balloon is **configured correctly** (`balloon: 512`, `virtio-balloon-pci` + `free-page-reporting=on`). PVE **does not trim** guest RAM while the host has abundant free memory. `balloon: 512` is the **minimum floor** when the host *inflates* the balloon under pressure — not automatic deflation. For idle power, **reduce static `memory:`** (Phase 5) beats expecting balloon on this host today.

---

## Storage

| Pool | Layout | Always on |
|------|--------|-----------|
| rpool | USB RTL9210 256G NVMe | Yes (boot) |
| fast | mirror 2× Crucial P3 4TB | Yes |
| slow | mirror 2× Samsung 870 QVO 2TB | Yes |
| backup USB | not attached | — |

Primary LAN: PCIe RTL8168 `enp3s0` (not USB 5G this boot).

---

## SFF thread — post #295578

[Post #295578](https://smallformfactor.net/forum/threads/06-05-2026-asrock-deskmini-a-x300-bios-p2-20-final-p2-20-sl01-native-s3-p2-20a-ss-disabled-p2-20b-acs-on-agesav2-pi-1-2-0-10.18423/page-16#post-295578): **obrida** shares **X3MSTX_2.20B.zip** (ACS build) — not a powerstate-bug analysis. See [FORUM-REPLY-NOTES.md](../../FORUM-REPLY-NOTES.md).
