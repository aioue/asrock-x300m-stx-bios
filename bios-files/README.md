# BIOS Files Inventory

Firmware images and saved BIOS setup profiles for the ASRock X300M-STX.

## Firmware Images

- `firmware/stock-2.20/X3MSTX_2.20`
  - Stock ASRock BIOS `2.20`
  - Baseline used for the original IFR/power-settings analysis

- `firmware/asrock-acs-ari-2.20b/X3MSTX_2.20B`
  - ASRock-provided `P2.20B`
  - Custom build of `2.20` with `ACS` / `ARI` enabled for better Proxmox IOMMU
    group separation
  - Preferred firmware baseline for this host unless superseded

## Saved Setup Profiles

- `settings/p2.20b/P2.20B_defaults.BIN`
  - Saved from the first boot/default setup state after flashing `P2.20B`

- `settings/p2.20b/P2.20B_customised.BIN`
  - Saved after manual BIOS customisation on `P2.20B`
  - Compare with `P2.20B_defaults.BIN` to identify exact setting changes

## Analysis Notes

The setup profile `.BIN` files are not full 16 MiB firmware images. They are
saved BIOS setup/profile exports and should be analysed separately from the full
ROM images.

For firmware analysis, use the full ROM images under `firmware/`.
