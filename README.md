# Wayne's Syscheck of Doom v4.0
> A bulletproof, single-bash-script system health checker for Linux Mint 22.x / Ubuntu Noble

A comprehensive, zero-dependency system audit tool that checks updates, package integrity, filesystem health, boot status, hardware telemetry, DNS security, drive health, and more - all in one color-coded, easy-to-read report.

## Features
- **Update Management**: Syncs APT/Flatpak repos with optional automated patching
- **Package Integrity**: Checks for broken packages, held packages, and autoremovable bloat
- **Filesystem Validation**: Supports EXT4/BTRFS/XFS, scans for I/O errors and filesystem corruption
- **Boot Health**: Verifies UEFI/Legacy boot mode, checks GRUB/systemd-boot, confirms kernel/initramfs presence
- **SMART Monitoring**: Auto-detects all drives (NVMe/SATA/HDD) via `lsblk` - no more missed NVMe drives
- **DNS Security**: Validates DNS-over-TLS with active connection verification + DNSSEC enforcement checks
- **Hardware Telemetry**: Real-time CPU/GPU temp, freq, load, uptime, VRAM usage, fan speed, power draw
- **Storage Optimization**: Intelligent cache flushing (only flushes DNS/APT caches when needed)
- **Service Monitoring**: Checks systemd services, NetworkManager, Bluetooth, Pipewire status
- **Software Inventory**: Lists user-installed packages, Flatpak/Snap apps with clean column output
- **Bulletproof Design**: Fixed critical bugs (subshell scoping, `int()` function, `df` space parsing)

## Prerequisites
- Linux Mint 22.x / Ubuntu Noble (or compatible Debian-based distro)
- `bash` 4.0+
- `sudo` privileges
- Standard pre-installed tools: `apt`, `flatpak`, `systemctl`, `smartctl`, `sensors`, `df`, `lsblk`, `resolvectl`

## Installation
Clone the repository:
```bash
git clone https://github.com/<your-username>/waynes-syscheck-doom.git
cd waynes-syscheck-doom
```

Or download the script directly:
```bash
wget https://raw.githubusercontent.com/<your-username>/waynes-syscheck-doom/main/waynes_syscheck.sh
chmod +x waynes_syscheck.sh
```

## Usage
Run the script (sudo required for full functionality):
```bash
sudo ./waynes_syscheck.sh
```

Follow the interactive prompts for optional actions:
- System-wide patching
- Storage deep cleaning
- Autoremove unused packages

## Example Output
```
╔══════════════════════════════════════════════════╗
  ║     Wayne's Syscheck of Doom  v4.0 (Mint)       ║
  ╚══════════════════════════════════════════════════╝
  Tuesday, April 28 2026  03:56:22  —  6.17.0-22-generic

┌─ Repository Intelligence 
  ✔  APT repo:    Up to date
  ✔  Flatpak:     Up to date

┌─ Package Database Integrity 
  ✔  Package DB:  No broken packages
  ✔  Held pkgs:   None
  ✔  Autoremove:  Nothing to remove

... (truncated) ...

  ════════════════════════════════════════════════════
  SYSTEM HEALTH REPORT
  ════════════════════════════════════════════════════
  ✔  All systems nominal. Wayne's rig is perfect.
  ════════════════════════════════════════════════════
```

## Notes
- **Phased Updates**: Ubuntu may defer packages like `thermald` due to phased rollout - this is normal behavior
- **DNS Verification**: Script verifies active TLS connections to your configured DNS server (Quad9 by default)
- **SMART Checks**: All NVMe/SATA/HDD drives are automatically detected - no manual configuration needed
- **Zero Dependencies**: Only uses tools pre-installed on standard Linux Mint/Ubuntu systems

## License
Free to use, modify, and distribute. No warranty provided - use at your own risk.
