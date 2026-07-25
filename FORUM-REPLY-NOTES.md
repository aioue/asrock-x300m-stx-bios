# SFF.Network forum — reply notes

**Author:** Tom posts as **obrida** on SFF.Network. Post [#295578](https://smallformfactor.net/forum/threads/06-05-2026-asrock-deskmini-a-x300-bios-p2-20-final-p2-20-sl01-native-s3-p2-20a-ss-disabled-p2-20b-acs-on-agesav2-pi-1-2-0-10.18423/page-16#post-295578) is **your** P2.20B ACS share.

**Attribution:** Draft guidance from [Cursor](https://cursor.com) (Composer 2.5), July 2026.

---

## Recommendation

**Yes — worth a follow-up** where thread claims touch firmware behaviour you can verify from **IFR decompile + live read-back** on P2.20B. Not a thank-you to yourself; a short **methods → outcome** note that confirms or disproves what someone said.

**Tone:** What we did, what we measured, what we found. No SL01 advocacy, no plug-watt hype, no “you should flash X”.

**Where to post:**

| Target | When |
|--------|------|
| **Reply on #295578** (your share) | Optional one-liner: “Follow-up measurements on this build below” + pointer, **or** leave share as-is |
| **Reply on S3 / power posts** (2z0 #295210, Aleo #295437, Dr. Nick #295436) | **Preferred** — directly addresses claims |
| **New top-level** | Avoid |

Search thread first; skip repeating `XS3` if already covered unless you add **P2.20B-specific live data**.

---

## What we did (cite in posts)

1. **IFR decompile** of `X3MSTX_2.20B` — VarStores (`Setup`, `AmdSetup`, `AMD_PBS_SETUP`), power-relevant offsets ([`bios-power-settings-p2.20b.md`](bios-power-settings-p2.20b.md)).
2. **Live NVRAM read-back** on running P2.20B (`read-live-bios-settings.py`) — e.g. `S3/Modern Standby Support`, Global C-state, DF Cstates.
3. **ACPI dump** on live host — `acpidump` + `iasl`: DSDT has `Name(XS3)`, no `_S3`.
4. **Runtime idle** — `cpuidle` / `turbostat` on Proxmox (5650G, VMs running): deepest state **C3**, no CC6; package ~14 W (not wall).

Blog / repo (optional link): [Deconstructing ASRock X300 BIOS](https://aioue.net/2026/04/25/deconstructing-asrock-x300-bios-power-options/) · [asrock-x300m-stx-bios](https://github.com/aioue/asrock-x300m-stx-bios)

---

## Thread claims vs our evidence

| Thread claim | Our outcome on **P2.20B** |
|--------------|---------------------------|
| Aleo: BIOS shows **Modern Standby** for S3 option on P2.20A | **Confirms** same family behaviour: live `AMD_PBS` → Modern Standby (`0x01`), not native S3 |
| Dr. Nick / others: does **S3 work** on final P2.20 line? | **Disproves STR path on P2.20B**: DSDT `XS3` not `_S3`; kernel `mem_sleep = [s2idle]` only |
| 2z0 / JZ list: **2.20JZ** = S3, **2.20** = noS3 | **Consistent** with our P2.20B (non-JZ) ACPI + standby setting; we did not flash JZ/SL01 |
| Implied: S3 fix ⇒ better **runtime** idle (CC6) | **Not shown** on P2.20B: C3 max under Proxmox; we are **not** claiming SL01 changes runtime idle |
| obrida share: P2.20B for **ACS / IOMMU** | **Confirms** on our Proxmox host (5650G); separate from suspend/idle |

---

## Draft reply — S3 / Modern Standby (Aleo, Dr. Nick, 2z0)

> Follow-up on **P2.20B** (the ACS build I shared above) — I decompiled the IFR from the ROM and cross-checked on my live Proxmox box (5650G).
>
> **Suspend:** `acpidump`/`iasl` on the running system shows `Name(XS3)` in DSDT, not `_S3` (same class of ACPI typo [Lorenz Brun](https://lorenz.brun.one/enabling-s3-sleep-on-x300/) described). Kernel only exposes `mem_sleep = [s2idle]`. That matches Aleo’s note that the BIOS presents **Modern Standby**, not classic S3 STR, on the non-JZ final line.
>
> **Runtime idle (separate from suspend):** with VMs up, `cpuidle` stops at **C3** (no CC6 in `turbostat`). I have not tested P2.20.SL01 / 2.20JZ — no comment on whether those change runtime idle.
>
> IFR offsets and live read-back notes are in my [X300 BIOS write-up](https://aioue.net/2026/04/25/deconstructing-asrock-x300-bios-power-options/) if useful.

---

## Draft reply — short add-on to #295578 (your post)

Only if you want a self-reply under your zip:

> Measured this build on my own host after flashing — ACPI/live idle notes in reply to the S3 questions on this page (DSDT `XS3`, `[s2idle]`, C3-max runtime on Proxmox). Sharing in case it helps anyone choosing between P2.20B and the JZ/SL S3 variants.

---

## What not to say

- Don’t argue with ASRock or other posters
- Don’t recommend flashing SL01/JZ from this data
- Don’t quote wall-plug watts without HA plug context
- Don’t present IFR `0x0FC` script writes (`0xFF` live) as safe

---

## Decision log

| Date | Decision |
|------|----------|
| 2026-07-22 | Author = obrida; reply = decompile + live evidence vs thread claims |
| 2026-07-22 | No post submitted yet |
