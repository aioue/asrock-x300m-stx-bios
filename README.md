# ASRock X300M-STX BIOS

BIOS firmware, saved setup profiles, analysis outputs, and power configuration
notes for the ASRock X300M-STX motherboard.

## Hardware And Goal

- Board: ASRock X300M-STX mini-STX AM4
- CPU: AMD Ryzen 5 PRO 5650G (Cezanne / Zen 3)
- OS target: Proxmox VE, always-on host with VMs/containers
- Primary goals:
  - Low idle power
  - Stable Proxmox operation
  - IOMMU groups split well enough for virtualisation/passthrough

## Important Firmware Context

`P2.20B` is an ASRock-provided variant of BIOS `2.20`.

ASRock enabled `ACS` / `ARI` in `P2.20B` so PCIe/IOMMU groups are properly split
for Proxmox virtualisation and passthrough use. Treat `P2.20B` as the preferred
firmware baseline for this host unless a newer ASRock build supersedes it with
the same ACS/ARI behaviour.

There are two saved setup profile files from `P2.20B`:

- `bios-files/settings/p2.20b/P2.20B_defaults.BIN` -- saved immediately after
  first boot/defaults
- `bios-files/settings/p2.20b/P2.20B_customised.BIN` -- saved after manual BIOS
  customisation

Future analysis should compare:

1. Stock `2.20` vs ASRock `P2.20B` firmware, looking especially for ACS/ARI,
   IOMMU, PCIe, AMD PBS/CBS, and power-management differences.
2. `P2.20B_defaults.BIN` vs `P2.20B_customised.BIN`, to identify the exact setup
   variables changed manually in the BIOS UI.
3. Existing `apply-bios-settings.sh` assumptions against `P2.20B`, because
   NVRAM offsets and VarStore sizes may differ from stock `2.20`.

## Repository Layout

```text
.
├── analyze-bios-rom.sh
├── apply-bios-settings.sh
├── read-live-bios-settings.py
├── bios-power-settings.md
├── bios-power-settings-p2.20b.md
├── bios-files/
│   ├── firmware/
│   │   ├── stock-2.20/
│   │   │   └── X3MSTX_2.20
│   │   └── asrock-acs-ari-2.20b/
│   │       └── X3MSTX_2.20B
│   └── settings/
│       └── p2.20b/
│           ├── P2.20B_defaults.BIN
│           └── P2.20B_customised.BIN
└── analysis/
    └── stock-2.20/
        ├── X3MSTX_2.20.dump/
        ├── X3MSTX_2.20.guids.csv
        ├── X3MSTX_2.20.report.txt
        └── bios-analysis-X3MSTX_2.20/
```

## Scripts

- `analyze-bios-rom.sh` -- reusable AMI UEFI analysis script. It builds
  `UEFIExtract` and `ifrextractor` if needed, extracts IFR data from Setup /
  AMD CBS / AMD PBS modules, and searches for power-related BIOS settings.
- `apply-bios-settings.sh` -- cautious `efivarfs` writer for selected low-power
  NVRAM settings. The target offsets were checked against `P2.20B` IFR output,
  but `--apply` is disabled pending live rework because the current host does
  not expose the expected `Setup-*` efivar and one CBS RV offset did not
  validate.
- `read-live-bios-settings.py` -- read-only live `efivarfs` collector for
  comparing the active host's BIOS settings against the `P2.20B` recommendations.
- `bios-power-settings.md` -- stock `2.20` power-management findings and
  recommendations.
- `bios-power-settings-p2.20b.md` -- active `P2.20B` power-management findings,
  ACS/ARI notes, and dry-run patching guidance.

## Usage

```bash
# Analyse stock 2.20 again
./analyze-bios-rom.sh bios-files/firmware/stock-2.20/X3MSTX_2.20 analysis/stock-2.20-rerun

# Analyse ASRock P2.20B
./analyze-bios-rom.sh bios-files/firmware/asrock-acs-ari-2.20b/X3MSTX_2.20B analysis/p2.20b

# Review existing stock 2.20 recommendations
cat bios-power-settings.md

# Review active P2.20B recommendations
cat bios-power-settings-p2.20b.md

# Read-only live BIOS setting comparison over SSH
ssh -o ControlMaster=no root@192.168.1.10 'python3 -s' < read-live-bios-settings.py

# Fail-safe dry-run of the older patch script; currently expected to stop
# because Setup-* is not exposed on the live host.
sudo ./apply-bios-settings.sh
```

## Fresh Chat Context

If continuing this work in a fresh chat, start here:

1. Read this README.
2. Use `P2.20B-analysis-prompt.md` as the fresh-chat handoff prompt.
3. Read `bios-power-settings.md` for the stock `2.20` analysis.
4. Inspect `bios-files/firmware/asrock-acs-ari-2.20b/X3MSTX_2.20B`.
5. Compare `bios-files/settings/p2.20b/P2.20B_defaults.BIN` and
   `bios-files/settings/p2.20b/P2.20B_customised.BIN`.
6. Read `analysis/p2.20b/live-readback-notes.md` for the current SSH blocker,
   dump-tree notes, and the read-only efivarfs workflow.
7. Read `analysis/p2.20b/live-readback-2026-04-25.md` for the live host values,
   IOMMU groups, and ASPM snapshot.
8. Do not use `apply-bios-settings.sh --apply` until the script is reworked for
   the missing `Setup-*` efivar and the `Power Supply Idle Control` offset
   mismatch.
