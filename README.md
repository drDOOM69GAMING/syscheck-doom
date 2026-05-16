# Wayne's Syscheck of Doom v4.0
> A bulletproof, single-bash-script system health checker for Linux Mint 22.x / Ubuntu Noble

A comprehensive, zero-dependency system audit tool that checks updates, package integrity, filesystem health, boot status, hardware telemetry, DNS security, drive health, and more — all in one color-coded, easy-to-read report.

## Features
- **Update Management**: Syncs APT/Flatpak repos with optional automated patching
- **Package Integrity**: Checks for broken packages, held packages, and autoremovable bloat
- **Filesystem Validation**: Supports EXT4/BTRFS/XFS, scans for I/O errors and filesystem corruption
- **Boot Health**: Verifies UEFI/Legacy boot mode, checks GRUB/systemd-boot, confirms kernel/initramfs presence
- **SMART Monitoring**: Auto-detects all drives (NVMe/SATA/HDD) via `lsblk` — no more missed NVMe drives
- **DNS Security**: Validates DNS-over-TLS with active connection verification + DNSSEC enforcement checks
- **Hardware Telemetry**: Real-time CPU/GPU temp, freq, load, uptime, VRAM usage, fan speed, power draw
- **Storage Optimization**: Two-stage deep clean — system-level (nala/apt, flatpak, journals) then user-level (temp files, thumbnails, trash, dev caches)
- **Dev Tool Cache Cleanup**: Purges pip, npm, pnpm, yarn, Cargo, Maven, Go module, and Docker dangling build caches with clear warnings for global stores
- **Dev Directory Scan**: Finds bloated project dirs (`node_modules`, `.venv`, `venv`, `__pycache__`, `target`) across home while skipping system dirs for speed
- **Temp File Cleanup**: Safely purges `/tmp` and `/var/tmp` files older than 1 day
- **nala Support**: Auto-detects and uses `nala` as the package manager when available
- **Service Monitoring**: Checks systemd services, NetworkManager, Bluetooth, Pipewire status
- **Software Inventory**: Lists user-installed packages, Flatpak/Snap apps with clean column output
- **Bulletproof Design**: Root guard, headless/cron-safe prompts, hidden-file-safe trash deletion, `set -e` protection on all commands

## Prerequisites
- Linux Mint 22.x / Ubuntu Noble (or compatible Debian-based distro)
- `bash` 4.0+
- `sudo` privileges
- Standard pre-installed tools: `apt`, `flatpak`, `systemctl`, `smartctl`, `sensors`, `df`, `lsblk`, `resolvectl`

## Installation
Clone the repository:
```bash
git clone https://github.com/drDOOM69GAMING/syscheck-doom.git
cd syscheck-doom
```

Or download the script directly:
```bash
wget https://raw.githubusercontent.com/drDOOM69GAMING/syscheck-doom/main/waynes_syscheck.sh
chmod +x waynes_syscheck.sh
```

## Usage
Run the script:
```bash
./waynes_syscheck.sh
```

The script will prompt for sudo internally when needed. Follow the interactive prompts for optional actions:
- System-wide patching
- Two-stage deep clean (system cache → user cache & trash)
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

┌─ Storage Optimization 
  •  Init system:        systemd
  •  Architecture:       x86_64
  •  Package manager:    nala
  •  Super user group:   wayneamd
  •  APT cache:   76K
  Perform deep clean? (y/N): y
  ⚠  Performing system cleanup...
  •  Flatpak:     Nothing to remove
  •  Journal:     Already clean

  Clean up old cache files and empty the trash? (y/N): y
  ⚠  Cleaning up old cache files and emptying trash...
  •  /tmp:        Already clean
  •  /var/tmp:    92K → 8.0K
  •  Thumbnails:  4.0K → 0
  •  Scanning for heavy dev directories:
  314M  /home/wayneamd/MediaPlayerDOOM/venv
  58M   /home/wayneamd/.opencode/node_modules

... (truncated) ...

  ════════════════════════════════════════════════════
  SYSTEM HEALTH REPORT
  ════════════════════════════════════════════════════
  ✔  All systems nominal.
  ════════════════════════════════════════════════════
```

## Notes
- **Phased Updates**: Ubuntu may defer packages like `thermald` due to phased rollout — this is normal behavior
- **DNS Verification**: Script verifies active TLS connections to your configured DNS server (Quad9 by default)
- **SMART Checks**: All NVMe/SATA/HDD drives are automatically detected — no manual configuration needed
- **Global Cache Warnings**: Clearing Go (`go clean -modcache`) and Maven (`~/.m2/repository`) forces full re-download of all dependencies on next build
- **Hidden Files in Trash**: Trash uses `find -mindepth 1 -delete` to catch dotfiles (`.env`, `.git`) that `rm *` would miss
- **Headless Note**: `read` prompts assume an interactive terminal — run directly, not via cron/SSH
- **Zero Dependencies**: Only uses tools pre-installed on standard Linux Mint/Ubuntu systems

## License
Free to use, modify, and distribute. No warranty provided — use at your own risk.
