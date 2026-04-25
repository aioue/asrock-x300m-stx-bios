# P2.20B Live Read-Back Notes

Status: initial live SSH read-back was attempted from the devcontainer on 2026-04-25, but SSH to `root@192.168.1.10` timed out before authentication. The host later came back online and read-back succeeded; see `live-readback-2026-04-25.md`.

```text
ssh -o ControlMaster=no -o BatchMode=yes -o ConnectTimeout=5 root@192.168.1.10 'echo ok'
ssh: connect to host 192.168.1.10 port 22: Connection timed out
```

This matched the known devcontainer/LAN blocker documented in the main repo: Docker Desktop on macOS may need Local Network permission re-enabled after a container rebuild. In this case the host later became reachable again.

## What To Fix Before Retrying

On the Mac host:

1. Open System Settings.
2. Go to Privacy & Security > Local Network.
3. Ensure Docker Desktop is allowed.
4. Retry SSH from the devcontainer:

```bash
ssh -o ControlMaster=no -o BatchMode=yes -o ConnectTimeout=5 root@192.168.1.10 'echo ok'
```

## Read-Only Live BIOS Collector

Use the repository script:

```bash
ssh -o ControlMaster=no root@192.168.1.10 'python3 -s' < read-live-bios-settings.py
```

Or copy it to the Proxmox host and run:

```bash
python3 read-live-bios-settings.py
```

The script reads only:

- `/sys/class/dmi/id/*`
- `/proc/cmdline`
- `/sys/firmware/efi/efivars/Setup-ec87d643-eba4-4bb5-a1e5-3f3e36b20da9`
- `/sys/firmware/efi/efivars/AmdSetup-3a997502-647a-4c82-998e-52ef9486a247`
- `/sys/firmware/efi/efivars/AMD_PBS_SETUP-a339d746-f678-49b3-9fc7-54ce0f9df226`

It does not write efivarfs and does not call `chattr`, `cp`, `dd`, or `setup_var`.

## Settings Compared

The collector compares live values against the conservative `P2.20B` recommendations for:

- `Setup`: Fusion Message C State, Fusion Message C Multi-Core, Deep Sleep, Restore on AC/Power Loss, WAN Device, Onboard LAN.
- `AmdSetup`: Global C-state Control, Core Performance Boost, DF Cstates, CPPC CTRL, CPPC Preferred Cores, SATA DevSleep ports, ACS, ARI, IOMMU, System Configuration AM4, Power Supply Idle Control, HD Audio.
- `AMD_PBS_SETUP`: S3/Modern Standby Support, PM L1 SS, WLAN Enable, Blue Tooth Enable.
- `AOD_SETUP`: ECO Mode.

Live caveat: on the current `P2.20B` host, `Setup-ec87d643-eba4-4bb5-a1e5-3f3e36b20da9` is not exposed through efivarfs. The collector reports the missing store instead of failing.

## Dump Tree Creation Notes

Useful notes preserved from prior BIOS analysis work:

- Use `UEFIExtract` to dump the full AMI UEFI firmware structure from the raw 16 MiB ROM image.
- Run `ifrextractor` against the relevant PE32/TE module bodies to recover human-readable IFR setup forms.
- Important modules for this board are generally `Setup`, `CbsSetupDxeRN`, `CbsSetupDxeRV`, `AmdPbsSetupDxe`, `AodSetupDxe`, and sometimes `AMITSE`.
- Search IFR output for power/virtualisation terms such as `c-state`, `cppc`, `Power Supply Idle`, `ASPM`, `L1`, `ACS`, `ARI`, `IOMMU`, `SATA`, `USB`, `wake`, `sleep`, `PPT`, `TDC`, and `EDC`.
- Keep stock firmware and ASRock `P2.20B` analysis outputs separate so offsets, VarStores, and valid values are not accidentally mixed.
- Treat saved BIOS profile `.BIN` files separately from full ROM images; they are not full firmware dumps.
- Prebuilt `UEFIExtract` binaries were not suitable in this environment, so `analyze-bios-rom.sh` builds `UEFIExtract` from source.
- `ifrextractor` is built from source; the binary name is `ifrextractor`, not `ifrextract`.
- `UEFIExtract` puts useful module names in directory paths, not always in `info.txt`; module detection must search path names like `100 Setup` and `79 CbsSetupDxeRN`.
- IFR extraction only works on the correct PE32/TE `body.bin` files; broad/random `body.bin` parsing gives noise or empty results.
- `UEFIExtract image all` may generate report/GUID output without the tree layout expected by the analyzer. `UEFIExtract image unpack` creates the legacy `.dump` tree used by the scanner.
- On the `P2.20B` ROM, `unpack` may return non-zero while still leaving a usable `.dump` tree. If the dump tree exists, rerun the analyzer and continue.
- Stock `2.20` and `P2.20B` must be analysed independently because VarStore sizes, offsets, or valid values may differ.
- The previous live patch script was based on stock `2.20`; it must be revalidated before use on `P2.20B`.
- `Audio IOs` does not have a real "disable audio" value; `HD Audio Enable` is the safer master setting.

## Why Saved Profiles Are Not Enough

`P2.20B_defaults.BIN` and `P2.20B_customised.BIN` can show changed bytes, but they are ASRock/AMI profile exports rather than named live UEFI variables. They do not contain plain `Setup`, `AmdSetup`, `AMD_PBS_SETUP`, or `AOD_SETUP` names, and should not be treated as direct concatenations of efivar data.

Live read-back from efivarfs is therefore required to reliably map:

- variable name
- GUID
- VarStore-relative offset
- current value
- IFR-valid values
- desired value
