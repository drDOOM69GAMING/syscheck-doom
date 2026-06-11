#!/bin/bash

# =============================================================================
#  Wayne's Syscheck of Doom — v4.0 (Arch Linux / CachyOS Edition)
#  Arch Linux / CachyOS — Full Edition
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FINAL_LOG="${SCRIPT_DIR}/waynes_syscheck_$(date '+%Y-%m-%d_%H-%M-%S').log"
TMP_LOG=$(mktemp "/tmp/waynes_syscheck_XXXXXXXX.log")
exec > >(tee >(sed 's/\x1b\[[0-9;]*m//g' > "$TMP_LOG")) 2>&1

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

ok()   { echo -e "  ${GREEN}✔${NC}  $*"; }
warn() { echo -e "  ${YELLOW}⚠${NC}  $*"; }
fail() { echo -e "  ${RED}✘${NC}  $*"; }
info() { echo -e "  ${CYAN}•${NC}  $*"; }

section() {
    echo
    echo -e "${BLUE}${BOLD}┌─ $* ${NC}"
}

temp_color() {
    local t=$1 warn=${2:-70} crit=${3:-85}
    if   (( t >= crit )); then echo -e "${RED}${t}°C${NC}"
    elif (( t >= warn )); then echo -e "${YELLOW}${t}°C${NC}"
    else echo -e "${GREEN}${t}°C${NC}"
    fi
}

pct_color() {
    local p=$1
    if   (( p >= 90 )); then echo -e "${RED}${p}%${NC}"
    elif (( p >= 70 )); then echo -e "${YELLOW}${p}%${NC}"
    else echo -e "${GREEN}${p}%${NC}"
    fi
}

int() {
    local num
    num=$(echo "$1" | grep -oE '[0-9]+' | head -1)
    echo "${num:-0}"
}

# AMD Zen3 false-positive filter + KDE Plasma spurious MCE match
AMD_NOISE='Bank [0-9]+ is reserved|cache level: RESV|MC[0-9]+_STATUS|IPID: 0x0+|Syndrome: 0x0+|Error Addr: 0x0+|System Fatal error|tx: INSN|MCE decoding enabled|events logged|plasmalogin.*MCE'

# --- SUDO ---
if ! groups | grep -q '\bwheel\b'; then
    fail "User is not in the wheel group. Sudo will not work."
    exit 1
fi

clear
echo -e "${BLUE}${BOLD}"
echo "  ╔══════════════════════════════════════════════════╗"
echo "  ║   Wayne's Syscheck of Doom  v4.0 (Arch/CachyOS) ║"
echo "  ╚══════════════════════════════════════════════════╝"
echo -e "${NC}${DIM}  $(date '+%A, %B %d %Y  %H:%M:%S')  —  $(uname -r)${NC}"

GLOBAL_ISSUES=0

# =============================================================================
# 1. UPDATES
# =============================================================================
section "Repository Intelligence"

echo -e "  ${DIM}Synchronizing package databases...${NC}"
sudo pacman -Sy 2>/dev/null
sudo flatpak update --appstream -y >/dev/null 2>&1

PAC_UPDATES=$(int "$(pacman -Qu 2>/dev/null | wc -l)")
FLAT_UPDATES=$(int "$(flatpak remote-ls --updates 2>/dev/null | wc -l)")

# AUR updates
AUR_HELPER=""
if command -v yay &>/dev/null; then
    AUR_HELPER="yay"
elif command -v paru &>/dev/null; then
    AUR_HELPER="paru"
fi
AUR_UPDATES=0
if [[ -n "$AUR_HELPER" ]]; then
    AUR_UPDATES=$(int "$($AUR_HELPER -Qua 2>/dev/null | wc -l)")
fi

(( PAC_UPDATES  == 0 )) && ok "Pacman repo: Up to date" \
    || warn "Pacman repo: ${RED}${PAC_UPDATES} pending${NC}"
if [[ -n "$AUR_HELPER" ]]; then
    (( AUR_UPDATES  == 0 )) && ok "AUR ($AUR_HELPER):    Up to date" \
        || warn "AUR ($AUR_HELPER):    ${RED}${AUR_UPDATES} pending${NC}"
fi
(( FLAT_UPDATES == 0 )) && ok "Flatpak:     Up to date" \
    || warn "Flatpak:     ${RED}${FLAT_UPDATES} pending${NC}"

TOTAL_UPDATES=$(( PAC_UPDATES + FLAT_UPDATES + AUR_UPDATES ))
if (( TOTAL_UPDATES > 0 )); then
    echo
    read -rp "  Execute system-wide update? (y/N): " run_updates
    if [[ "$run_updates" =~ ^[Yy]$ ]]; then
        sudo pacman -Su --noconfirm
        [[ -n "$AUR_HELPER" ]] && $AUR_HELPER -Sua --noconfirm 2>/dev/null || true
        (( FLAT_UPDATES > 0 )) && sudo flatpak update -y
        ok "System updated."
        PAC_UPDATES=$(int "$(pacman -Qu 2>/dev/null | wc -l)")
        [[ -n "$AUR_HELPER" ]] && AUR_UPDATES=$(int "$($AUR_HELPER -Qua 2>/dev/null | wc -l)") || AUR_UPDATES=0
        FLAT_UPDATES=$(int "$(flatpak remote-ls --updates 2>/dev/null | wc -l)")
    fi
fi

(( PAC_UPDATES  != 0 )) && (( GLOBAL_ISSUES++ ))
(( AUR_UPDATES  != 0 )) && (( GLOBAL_ISSUES++ ))
(( FLAT_UPDATES != 0 )) && (( GLOBAL_ISSUES++ ))

# =============================================================================
# 2. PACKAGE DATABASE INTEGRITY
# =============================================================================
section "Package Database Integrity"

echo -e "  ${DIM}Checking package database consistency...${NC}"
DB_OUTPUT=$(sudo pacman -Dk 2>&1)
DB_ISSUES=$(echo "$DB_OUTPUT" | grep -c '^error:' || true)
if (( DB_ISSUES == 0 )); then
    ok "Package DB:  Database consistent"
else
    fail "Package DB:  ${RED}${DB_ISSUES} issue(s) found${NC}"
    echo "$DB_OUTPUT" | head -10
    (( GLOBAL_ISSUES++ ))
fi

echo -e "  ${DIM}Checking for broken/missing files on disk (this may take a minute)...${NC}"
read -rp "  Scan all installed packages for missing files? (y/N): " check_files
BROKEN_PKGS=""
if [[ "$check_files" =~ ^[Yy]$ ]]; then
    if command -v paccheck &>/dev/null; then
        BROKEN_PKGS=$(sudo paccheck --quiet --files 2>/dev/null | grep 'missing' | awk '{print $1}' | sort -u)
    else
        BROKEN_PKGS=$(sudo pacman -Qk 2>/dev/null | grep -v '0 missing' | awk -F: '{print $1}')
    fi
    BROKEN_COUNT=$(echo "$BROKEN_PKGS" | grep -v '^$' | wc -l)
    if (( BROKEN_COUNT == 0 )); then
        ok "File check:  All files present"
    else
        fail "File check:  ${RED}${BROKEN_COUNT} package(s) with missing files${NC}"
        echo "$BROKEN_PKGS" | while IFS= read -r pkg; do
            echo -e "             ${DIM}${pkg}${NC}"
        done
        read -rp "  Reinstall broken packages to fix? (y/N): " fix_pkgs
        if [[ "$fix_pkgs" =~ ^[Yy]$ ]]; then
            echo "$BROKEN_PKGS" | tr '\n' ' ' | sudo pacman -S --noconfirm - 2>/dev/null && ok "Broken packages reinstalled."
        fi
        (( GLOBAL_ISSUES++ ))
    fi
fi

# Check for ignored packages in pacman.conf
HELD=$(grep -c '^IgnorePkg\|^IgnoreGroup' /etc/pacman.conf 2>/dev/null || true)
IGNORED_PKGS=$(grep -E '^IgnorePkg|^IgnoreGroup' /etc/pacman.conf 2>/dev/null || true)
if (( HELD == 0 )); then
    ok "Ignored pkgs: None"
else
    warn "Ignored pkgs: ${YELLOW}${HELD} directive(s) set${NC}"
    echo "$IGNORED_PKGS" | while IFS= read -r line; do
        echo -e "             ${DIM}${line}${NC}"
    done
fi

# Check for orphaned packages
ORPHANS=$(int "$(pacman -Qdt 2>/dev/null | wc -l)")
if (( ORPHANS == 0 )); then
    ok "Orphans:     No orphaned packages"
else
    warn "Orphans:     ${YELLOW}${ORPHANS} orphaned package(s)${NC}"
    pacman -Qdt 2>/dev/null | head -10
    read -rp "  Remove orphaned packages? (y/N): " rem_orph
    if [[ "$rem_orph" =~ ^[Yy]$ ]]; then
        ORPH_LIST=$(pacman -Qdtq 2>/dev/null)
        if [[ -n "$ORPH_LIST" ]]; then
            sudo pacman -Rns $ORPH_LIST --noconfirm 2>/dev/null && ok "Orphans removed."
        else
            warn "No orphans to remove."
        fi
    fi
    (( GLOBAL_ISSUES++ ))
fi

# Check for orphaned files (files on disk not owned by any package)
read -rp "  Scan for unowned files in /opt /usr/local /srv? (y/N): " check_unowned
if [[ "$check_unowned" =~ ^[Yy]$ ]]; then
    echo -e "  ${DIM}Building list of package-owned files (this may take a moment)...${NC}"
    TMP_OWNED=$(mktemp)
    sudo pacman -Ql $(pacman -Qq 2>/dev/null) 2>/dev/null | awk '{print $2}' | sort -u > "$TMP_OWNED"
    UNOWNED=$(sudo find /opt /usr/local /srv -type f 2>/dev/null | while IFS= read -r f; do
        grep -qxF "$f" "$TMP_OWNED" 2>/dev/null || echo "$f"
    done)
    UNOWNED_COUNT=$(echo "$UNOWNED" | grep -v '^$' | wc -l)
    rm -f "$TMP_OWNED"
    if (( UNOWNED_COUNT == 0 )); then
        ok "Unowned files: None found in scanned directories"
    else
        warn "Unowned files: ${YELLOW}${UNOWNED_COUNT} file(s) not owned by any package${NC}"
        echo "$UNOWNED" | head -20 | while IFS= read -r f; do
            echo -e "             ${DIM}${f}${NC}"
        done
        (( UNOWNED_COUNT > 20 )) && info "             ${DIM}... and $((UNOWNED_COUNT - 20)) more${NC}"
    fi
fi

# =============================================================================
# 3. FILESYSTEM INTEGRITY
# =============================================================================
section "Filesystem Integrity"

for mount_point in / /home; do
    if mountpoint -q "$mount_point" 2>/dev/null || [[ "$mount_point" == "/" ]]; then
        FSTYPE=$(findmnt -no FSTYPE "$mount_point" 2>/dev/null)
        case "$FSTYPE" in
            btrfs)
                B_ERRS=$(int "$(sudo btrfs device stats "$mount_point" 2>/dev/null \
                    | grep -v ' 0$' | grep -c 'error\|corruption\|generation\|flush\|read')")
                if (( B_ERRS == 0 )); then
                    ok "BTRFS ${mount_point}:  No errors"
                else
                    fail "BTRFS ${mount_point}:  ${RED}${B_ERRS} error(s)${NC}"
                    sudo btrfs device stats "$mount_point" 2>/dev/null | grep -v ' 0$'
                    (( GLOBAL_ISSUES++ ))
                fi
                ;;
            ext4)
                EXT4_ERRS=$(int "$(sudo dmesg 2>/dev/null | grep -c 'EXT4-fs error')")
                if (( EXT4_ERRS == 0 )); then
                    ok "EXT4 ${mount_point}:   No errors in kernel log"
                else
                    fail "EXT4 ${mount_point}:   ${RED}${EXT4_ERRS} error(s)${NC}"
                    (( GLOBAL_ISSUES++ ))
                fi
                ;;
            xfs)
                XFS_ERRS=$(int "$(sudo dmesg 2>/dev/null | grep -ciE 'XFS.*error|XFS.*corrupt')")
                if (( XFS_ERRS == 0 )); then
                    ok "XFS ${mount_point}:    No errors in kernel log"
                else
                    fail "XFS ${mount_point}:    ${RED}${XFS_ERRS} error(s)${NC}"
                    (( GLOBAL_ISSUES++ ))
                fi
                ;;
            vfat|fat32)
                ok "VFAT /boot:  Boot partition — skipped (normal)"
                ;;
            *)
                info "FS ${mount_point}:     Type: ${FSTYPE:-unknown}"
                ;;
        esac
    fi
done

IO_ERRORS=$(int "$(sudo dmesg --level=err,crit 2>/dev/null \
    | grep -iE 'I/O error|ata.*failed|nvme.*error|blk.*error' \
    | grep -vE "$AMD_NOISE" \
    | wc -l)")
if (( IO_ERRORS == 0 )); then
    ok "I/O errors:  None in kernel log"
else
    fail "I/O errors:  ${RED}${IO_ERRORS} real I/O error(s)${NC}"
    sudo dmesg --level=err 2>/dev/null \
        | grep -iE 'I/O error|ata.*failed|nvme.*error|blk.*error' \
        | grep -vE "$AMD_NOISE" \
        | tail -3 | while IFS= read -r line; do
            echo -e "             ${DIM}${RED}${line}${NC}"
        done
    (( GLOBAL_ISSUES++ ))
fi

# =============================================================================
# 4. BOOT & INITRAMFS HEALTH
# =============================================================================
section "Boot & Initramfs Health"

[[ -d /sys/firmware/efi ]] && ok "EFI:         UEFI boot mode confirmed" || info "EFI:         Legacy BIOS mode"

if [[ -d /sys/firmware/efi ]]; then
    EFI_ENTRIES=$(int "$(sudo efibootmgr 2>/dev/null | grep -c 'Boot[0-9]')")
    info "EFI entries: ${EFI_ENTRIES} entries found"
fi

# Bootloader detection
if command -v grub-install &>/dev/null || [[ -f /boot/grub/grub.cfg ]]; then
    ok "Bootloader:  GRUB detected"
elif bootctl status &>/dev/null; then
    ok "Bootloader:  systemd-boot active"
else
    info "Bootloader:  Unknown"
fi

# Kernel/initramfs — Arch uses vmlinuz-linux-* / initramfs-*.img
VMLINUZ_COUNT=$(int "$(sudo sh -c 'ls /boot/vmlinuz-*' 2>/dev/null | wc -l)")
INITRD_COUNT=$(int  "$(sudo sh -c 'ls /boot/initramfs-*.img' 2>/dev/null | wc -l)")

if (( VMLINUZ_COUNT > 0 )); then
    ok "Kernels:     ${VMLINUZ_COUNT} kernel image(s) found"
    sudo sh -c 'ls /boot/vmlinuz-*' 2>/dev/null | while IFS= read -r f; do
        info "             $(basename "$f")  ${DIM}($(sudo du -sh "$f" 2>/dev/null | awk '{print $1}'))${NC}"
    done
    if (( INITRD_COUNT > 0 )); then
        ok "Initramfs:   ${INITRD_COUNT} image(s) found"
    else
        warn "Initramfs:   ${YELLOW}None found${NC}"
        (( GLOBAL_ISSUES++ ))
    fi
else
    fail "Kernels:     ${RED}No kernel images found in /boot${NC}"
    (( GLOBAL_ISSUES++ ))
fi

# Boot time analysis
BOOT_TIME=$(systemd-analyze time 2>/dev/null | head -1 | grep -oP '[\d.]+(?=s$)' || echo "")
if [[ -n "$BOOT_TIME" ]]; then
    BLAME=$(systemd-analyze blame 2>/dev/null | head -3 | awk '{printf "%s (%s), ", $2, $1}' | sed 's/, $//')
    info "Boot time:  ${BOOT_TIME}s  ${DIM}(${BLAME})${NC}"
fi

# =============================================================================
# 5. SYSTEM JOURNAL HEALTH
# =============================================================================
section "System Journal Health"

MCE_LOG=$(journalctl -b --no-pager 2>/dev/null \
    | grep -iE 'machine check|mce|hardware error' \
    | grep -vE "$AMD_NOISE")
MCE_REAL=$(int "$(echo "$MCE_LOG" | grep -v '^$' | wc -l)")
MCE_SUPPRESSED=$(int "$(journalctl -b --no-pager 2>/dev/null \
    | grep -iE 'hardware error' | wc -l)")

if (( MCE_REAL == 0 )); then
    ok "Hardware:    No real MCE/hardware errors"
    (( MCE_SUPPRESSED > 0 )) && \
        info "             ${DIM}(${MCE_SUPPRESSED} AMD Zen3 5700X3D spurious messages suppressed — known false positive)${NC}"
else
    fail "Hardware:    ${RED}${MCE_REAL} real hardware error(s)${NC}"
    echo "$MCE_LOG" | tail -3 | while IFS= read -r line; do
        echo -e "             ${DIM}${RED}${line}${NC}"
    done
    (( GLOBAL_ISSUES++ ))
fi

OOM_COUNT=$(int "$(journalctl -b --no-pager 2>/dev/null \
    | grep -ic 'Out of memory\|oom.kill')")
if (( OOM_COUNT == 0 )); then
    ok "OOM Killer:  No out-of-memory events this boot"
else
    warn "OOM Killer:  ${YELLOW}${OOM_COUNT} OOM event(s) this boot${NC}"
    (( GLOBAL_ISSUES++ ))
fi

# =============================================================================
# 6. CLEANUP
# =============================================================================
section "Storage Optimization"

INIT_SYS=$(ps -p 1 -o comm= 2>/dev/null || echo "unknown")
PKG_MGR="pacman"
SUDO_GROUP=$(grep -Po '^wheel:\K.*' /etc/group 2>/dev/null | awk -F: '{print $NF}')

echo -e "  ${CYAN}•${NC}  Init system:        ${INIT_SYS}"
echo -e "  ${CYAN}•${NC}  Architecture:       $(uname -m)"
echo -e "  ${CYAN}•${NC}  Package manager:    ${PKG_MGR}"
echo -e "  ${CYAN}•${NC}  Super user group:   ${SUDO_GROUP:-wheel}"
echo

PAC_CACHE_SIZE=$(sudo du -sh /var/cache/pacman/pkg 2>/dev/null | awk '{print $1}')
info "Pacman cache: ${YELLOW}${PAC_CACHE_SIZE}${NC}"
read -rp "  Perform deep clean? (y/N): " deep_clean
if [[ "$deep_clean" =~ ^[Yy](es)?$ ]]; then
    echo -e "  ${YELLOW}⚠${NC}  Performing system cleanup..."

    if command -v paccache &>/dev/null; then
        echo -e "  ${CYAN}•${NC}  Pacman cache cleanup level:"
        echo -e "      ${BOLD}1${NC}) Light   — keep 3 versions (default)"
        echo -e "      ${BOLD}2${NC}) Medium  — keep 1 version"
        echo -e "      ${BOLD}3${NC}) Nuclear — remove all cached packages"
        read -rp "  Choose (1-3) [1]: " cache_level
        case "${cache_level:-1}" in
            2) sudo paccache -rk1 2>/dev/null || true
               info "Pacman cache: Kept latest 1 version per package" ;;
            3) sudo find /var/cache/pacman/pkg -name 'download-*' -delete 2>/dev/null
               sudo pacman -Scc --noconfirm >/dev/null 2>&1 || true
               info "Pacman cache: Completely cleared" ;;
            *) sudo paccache -r 2>/dev/null || true
               info "Pacman cache: Kept latest 3 versions per package" ;;
        esac
    else
        sudo pacman -Sc --noconfirm 2>/dev/null || true
        info "Pacman cache: Cleaned (keeping currently installed)"
    fi
    echo -e "  ${CYAN}•${NC}  $(sudo du -sh /var/cache/pacman/pkg 2>/dev/null | awk '{printf "%s\t%s", $1, $2}')"

    FLAT_BEFORE=$(sudo du -sh /var/lib/flatpak 2>/dev/null | awk '{print $1}')
    flatpak uninstall --unused --non-interactive -y 2>/dev/null || true
    sudo flatpak uninstall --unused --non-interactive -y 2>/dev/null || true
    FLAT_AFTER=$(sudo du -sh /var/lib/flatpak 2>/dev/null | awk '{print $1}')
    [[ "$FLAT_BEFORE" != "$FLAT_AFTER" ]] \
        && info "Flatpak:     ${RED}${FLAT_BEFORE}${NC} → ${GREEN}${FLAT_AFTER}${NC}" \
        || info "Flatpak:     ${GREEN}Nothing to remove${NC}"

    JOURNAL_BEFORE=$(journalctl --disk-usage 2>/dev/null | awk '{print $NF}')
    sudo journalctl --vacuum-time=3d >/dev/null 2>&1
    JOURNAL_AFTER=$(journalctl --disk-usage 2>/dev/null | awk '{print $NF}')
    [[ "$JOURNAL_BEFORE" != "$JOURNAL_AFTER" ]] \
        && info "Journal:     ${RED}${JOURNAL_BEFORE}${NC} → ${GREEN}${JOURNAL_AFTER}${NC}" \
        || info "Journal:     ${GREEN}Already clean${NC}"

    echo
    read -rp "  Clean up old cache files and empty the trash? (y/N): " clean_cache
    if [[ "$clean_cache" =~ ^[Yy](es)?$ ]]; then
        echo -e "  ${YELLOW}⚠${NC}  Cleaning up old cache files and emptying trash..."

        TMP_SIZE=$(sudo du -sh /tmp 2>/dev/null | awk '{print $1}')
        sudo find /tmp -type f -atime +1 -delete 2>/dev/null || true
        sudo find /tmp -type d -empty -delete 2>/dev/null || true
        TMP_AFTER=$(sudo du -sh /tmp 2>/dev/null | awk '{print $1}')
        [[ "$TMP_SIZE" != "$TMP_AFTER" ]] \
            && info "/tmp:        ${RED}${TMP_SIZE}${NC} → ${GREEN}${TMP_AFTER}${NC}" \
            || info "/tmp:        ${GREEN}Already clean${NC}"

        VTMP_SIZE=$(sudo du -sh /var/tmp 2>/dev/null | awk '{print $1}')
        sudo find /var/tmp -type f -atime +1 -delete 2>/dev/null || true
        sudo find /var/tmp -type d -empty -delete 2>/dev/null || true
        VTMP_AFTER=$(sudo du -sh /var/tmp 2>/dev/null | awk '{print $1}')
        [[ "$VTMP_SIZE" != "$VTMP_AFTER" ]] \
            && info "/var/tmp:   ${RED}${VTMP_SIZE}${NC} → ${GREEN}${VTMP_AFTER}${NC}" \
            || info "/var/tmp:   ${GREEN}Already clean${NC}"

        THUMB_SIZE=$(du -sh ~/.cache/thumbnails 2>/dev/null | awk '{print $1}')
        if [[ -n "$THUMB_SIZE" && "$THUMB_SIZE" != "0" ]]; then
            rm -rf ~/.cache/thumbnails/* 2>/dev/null
            info "Thumbnails:  ${RED}${THUMB_SIZE}${NC} → ${GREEN}0${NC}"
        fi

        TRASH_SIZE=$(du -sh ~/.local/share/Trash/files 2>/dev/null | awk '{print $1}')
        if [[ -n "$TRASH_SIZE" && "$TRASH_SIZE" != "0" ]]; then
            find "$HOME/.local/share/Trash/files" -mindepth 1 -delete 2>/dev/null || true
            find "$HOME/.local/share/Trash/info" -mindepth 1 -delete 2>/dev/null || true
            info "Trash:       ${RED}${TRASH_SIZE}${NC} → ${GREEN}0${NC}"
        fi

        echo
        info "${BOLD}Dev tool caches:${NC}"
        if [ -d "$HOME/.cache/pip" ]; then
            rm -rf "$HOME/.cache/pip" 2>/dev/null || true
            info "  pip cache      Cleared"
        fi
        command -v npm &>/dev/null && npm cache clean --force 2>/dev/null || true
        command -v pnpm &>/dev/null && pnpm store prune 2>/dev/null || true
        command -v yarn &>/dev/null && yarn cache clean 2>/dev/null || true
        [ -d "$HOME/.cargo/registry/cache" ] && rm -rf "$HOME/.cargo/registry/cache" 2>/dev/null || true
        if [ -d "$HOME/.m2/repository" ]; then
            info "  Maven cache    Cleared (re-downloads on next build)"
            rm -rf "$HOME/.m2/repository" 2>/dev/null || true
        fi
        if command -v go &>/dev/null; then
            info "  Go modcache    Cleared (re-downloads on next build)"
            go clean -modcache 2>/dev/null || true
        fi
        if command -v docker &>/dev/null; then
            docker system prune -f 2>/dev/null || true
            docker builder prune -f 2>/dev/null || true
        fi

        echo
        info "${BOLD}Scanning for heavy dev directories:${NC}"
        find "$HOME" \
            \( -path "$HOME/.local" -o \
               -path "$HOME/.config" -o \
               -path "$HOME/.cache" -o \
               -path "$HOME/.mozilla" -o \
               -path "$HOME/.var" \) -prune \
            -o -type d \( \
            -name "node_modules" -o \
            -name ".venv" -o \
            -name "venv" -o \
            -name "__pycache__" -o \
            -name "target" \
            \) -prune -exec du -sh {} + 2>/dev/null | sort -hr | column -t -s $'\t' || true

        echo -e "  ${GREEN}✔${NC}  Cache and trash cleanup completed."
    fi

    ok "Deep clean complete."
fi

# =============================================================================
# 7. SERVICES
# =============================================================================
section "System Services"

FAILED_UNITS=$(int "$(systemctl --failed --plain --no-legend 2>/dev/null | grep -c '.')")
if (( FAILED_UNITS > 0 )); then
    fail "Failed services: ${RED}${FAILED_UNITS}${NC}"
    systemctl --failed --no-legend
    (( GLOBAL_ISSUES++ ))
else
    ok "Services:    All operational"
fi

for svc in NetworkManager bluetooth; do
    systemctl is-active --quiet "$svc" 2>/dev/null \
        && ok "${svc}:$(printf '%*s' $((18 - ${#svc})) '') Running" \
        || info "${svc}:$(printf '%*s' $((18 - ${#svc})) '') Not active"
done

systemctl --user is-active --quiet pipewire 2>/dev/null \
    && ok "pipewire:          Running (user service)" \
    || info "pipewire:          Not active"

# User services
USER_FAILED=$(int "$(systemctl --user --failed --plain --no-legend 2>/dev/null | grep -c '.')")
if (( USER_FAILED > 0 )); then
    fail "User services: ${RED}${USER_FAILED} failed${NC}"
    systemctl --user --failed --no-legend 2>/dev/null
    (( GLOBAL_ISSUES++ ))
fi

# Time sync
if command -v timedatectl &>/dev/null; then
    NTP_SYNC=$(timedatectl show 2>/dev/null | grep NTPSynchronized | cut -d= -f2)
    if [[ "$NTP_SYNC" == "yes" ]]; then
        ok "Time sync:   NTP synchronized"
    else
        warn "Time sync:   ${YELLOW}NTP not synchronized${NC}"
    fi
fi

# =============================================================================
# 8. DNS SECURITY
# =============================================================================
section "DNS Security"

if command -v resolvectl &>/dev/null; then
    DOT_STATUS=$(resolvectl status 2>/dev/null | grep -m1 'Protocols:' | grep -o '+DNSOverTLS\|-DNSOverTLS')
    DNSSEC_STATUS=$(resolvectl status 2>/dev/null | grep -m1 'DNSSEC=' | grep -o 'DNSSEC=yes\|DNSSEC=allow-downgrade\|DNSSEC=no')
    DNS_SERVER=$(resolvectl status 2>/dev/null | grep 'Current DNS Server' | head -1 | awk '{print $NF}')
else
    DOT_STATUS=""
    DNSSEC_STATUS=""
    DNS_SERVER=""
fi

DOT_VERIFIED=0
if [[ "$DOT_STATUS" == "+DNSOverTLS" ]] && [[ -n "$DNS_SERVER" ]]; then
    DNS_IP=$(echo "$DNS_SERVER" | cut -d'#' -f1)
    timeout 2 resolvectl query --cache=no google.com 2>/dev/null || true

    if command -v ss &>/dev/null; then
        if ss -tnp 2>/dev/null | grep ":853 " | grep -q "$DNS_IP"; then
            DOT_VERIFIED=1
        fi
    fi

    if (( DOT_VERIFIED == 0 )) && command -v openssl &>/dev/null; then
        if timeout 3 openssl s_client -connect "$DNS_IP:853" -servername "${DNS_SERVER#*#}" 2>&1 | grep -q "CONNECTED"; then
            DOT_VERIFIED=1
        fi
    fi
fi

if ! command -v resolvectl &>/dev/null; then
    info "DNS:         systemd-resolved not in use — skipping DNS security checks"
else
    if [[ "$DOT_STATUS" == "+DNSOverTLS" ]] && (( DOT_VERIFIED == 1 )); then
        ok "DNS-over-TLS: Encrypted (verified active connection)"
    elif [[ "$DOT_STATUS" == "+DNSOverTLS" ]]; then
        warn "DNS-over-TLS: ${YELLOW}Configured but no active connection detected${NC}"
    else
        info "DNS:         Not encrypted — expected for local network DNS ($DNS_SERVER)"
        read -rp "  Set up encrypted DNS (Cloudflare + Quad9 DoT)? (y/N): " setup_dot
        if [[ "$setup_dot" =~ ^[Yy]$ ]]; then
            echo -e "  ${YELLOW}⚠${NC}  Configuring systemd-resolved for DNS-over-TLS..."
            sudo mkdir -p /etc/systemd/resolved.conf.d
            printf "[Resolve]\nDNS=1.1.1.1#cloudflare-dns.com 9.9.9.9#dns.quad9.net\nDNSOverTLS=yes\nDNSSEC=no\n" | sudo tee /etc/systemd/resolved.conf.d/dns_over_tls.conf >/dev/null
            sudo systemctl restart systemd-resolved 2>/dev/null
            sleep 1
            # Force DNS servers on active interface so DHCP doesn't override
            ACTIVE_IFACE=$(ip link show 2>/dev/null | grep 'state UP' | grep -v 'lo:' | head -1 | awk -F': ' '{print $2}')
            if [[ -n "$ACTIVE_IFACE" ]]; then
                sudo resolvectl dns "$ACTIVE_IFACE" 1.1.1.1 9.9.9.9 2>/dev/null
                sudo resolvectl domain "$ACTIVE_IFACE" ~. 2>/dev/null
                sudo resolvectl dnsovertls "$ACTIVE_IFACE" yes 2>/dev/null
            fi
            sleep 1
            NEW_DOT=$(resolvectl status 2>/dev/null | grep -m1 'Protocols:' | grep -o '+DNSOverTLS\|-DNSOverTLS')
            if [[ "$NEW_DOT" == "+DNSOverTLS" ]]; then
                ok "DNS-over-TLS: Encrypted — active and verified"
            else
                warn "DNS-over-TLS: ${YELLOW}Configured but not yet active — try rebooting${NC}"
            fi
        fi
    fi

    [[ "$DNSSEC_STATUS" == "DNSSEC=yes" ]] \
        && ok "DNSSEC:      Enforced" \
        || warn "DNSSEC:      ${YELLOW}${DNSSEC_STATUS:-not set}${NC}"
    info "DNS Server:  ${DNS_SERVER:-unknown}"

    DNS_CACHE_THRESHOLD=50
    CACHE_SIZE=0
    CACHE_STAT=$(sudo resolvectl statistics 2>/dev/null | grep -i 'Current cache size')
    CACHE_SIZE=$(int "$CACHE_STAT")

    if (( CACHE_SIZE > DNS_CACHE_THRESHOLD )); then
        sudo resolvectl flush-caches 2>/dev/null
        ok "DNS cache:   Flushed (was ${CACHE_SIZE} entries)"
    else
        info "DNS cache:   ${CACHE_SIZE} entries (no flush needed)"
    fi
fi

# =============================================================================
# 9. DISK USAGE
# =============================================================================
section "Storage Overview"

while IFS='|' read -r fs size used avail pct mount; do
    pct_num=${pct//%/}
    colored_pct=$(pct_color "$pct_num")
    printf "  ${CYAN}%-22s${NC}  %s used of %s  (%s full)  ${DIM}%s${NC}\n" \
        "$mount" "$used" "$size" "$colored_pct" "$fs"
    if (( pct_num >= 85 )); then
        echo -e "  ${YELLOW}⚠${NC}  ${YELLOW}${mount} is ${pct_num}% full — consider clearing space${NC}"
    fi
done < <(df -h 2>/dev/null | awk '
    NR > 1 && $1 ~ /^\/dev\// {
        fs = $1; size = $2; used = $3; avail = $4; pct = $5
        mount = ""
        for (i = 6; i <= NF; i++) {
            mount = mount (i > 6 ? " " : "") $i
        }
        printf "%s|%s|%s|%s|%s|%s\n", fs, size, used, avail, pct, mount
    }
')

# Timeshift snapshots
if command -v timeshift &>/dev/null && systemctl is-active --quiet timeshift 2>/dev/null; then
    TS_COUNT=$(int "$(sudo timeshift --list 2>/dev/null | grep -c '^[0-9]')")
    if (( TS_COUNT > 0 )); then
        TS_LATEST=$(sudo timeshift --list 2>/dev/null | grep '^[0-9]' | tail -1 | awk '{print $3, $4}')
        info "Timeshift:   ${TS_COUNT} snapshot(s), latest: ${TS_LATEST}"
    else
        info "Timeshift:   No snapshots yet"
    fi
fi

# =============================================================================
# 10. MEMORY
# =============================================================================
section "Memory"

read -r total used free shared buff avail <<< \
    "$(free -m | awk 'NR==2{print $2,$3,$4,$5,$6,$7}')"
total=${total:-1}; used=${used:-0}
pct_used=$(( used * 100 / total ))
info "RAM:         ${used}MB used / ${total}MB total  ($(pct_color "$pct_used"))"

SWAP_TOTAL=$(int "$(free -m | awk '/^Swap/{print $2}')")
SWAP_USED=$(int  "$(free -m | awk '/^Swap/{print $3}')")
if (( SWAP_TOTAL > 0 )); then
    SWAP_PCT=$(( SWAP_USED * 100 / SWAP_TOTAL ))
    info "Swap:        ${SWAP_USED}MB used / ${SWAP_TOTAL}MB total  ($(pct_color "$SWAP_PCT"))"
else
    info "Swap:        Not configured"
fi

# Zram stats
if [[ -b /dev/zram0 ]]; then
    ZRAM_SIZE=$(int "$(awk '{printf "%.0f", $1/1024/1024}' /sys/block/zram0/mm_stat 2>/dev/null || echo 0)")
    ZRAM_USED=$(int "$(awk '{printf "%.0f", $3/1024/1024}' /sys/block/zram0/mm_stat 2>/dev/null || echo 0)")
    ZRAM_COMP=$(awk '{printf "%.1f", $5/$3}' /sys/block/zram0/mm_stat 2>/dev/null || echo "N/A")
    if (( ZRAM_SIZE > 0 )); then
        ZRAM_ALGO=$(cat /sys/block/zram0/comp_algorithm 2>/dev/null | grep -oP '^\S+' || echo "unknown")
        info "Zram:        ${ZRAM_USED}MB used / ${ZRAM_SIZE}MB total  (${ZRAM_ALGO}, comp: ${ZRAM_COMP}x)"
    fi
fi
# =============================================================================
section "Hardware Telemetry"

C_TEMP=$(sensors 2>/dev/null | grep -m1 'Tctl' | awk '{print $2}' | tr -d '+°C' | cut -d'.' -f1)
C_FREQ=$(grep -m1 'cpu MHz' /proc/cpuinfo 2>/dev/null | awk '{printf "%.0f", $4}')
C_LOAD=$(uptime | awk -F'load average:' '{print $2}' | awk '{print $1}' | tr -d ' ,')
C_UPTIME=$(uptime -p | sed 's/up //')

printf "  ${CYAN}%-16s${NC} Temp: %-14s  Freq: ${PURPLE}%s MHz${NC}  Load: ${YELLOW}%s${NC}\n" \
    "CPU (5700X3D)" "$(temp_color "${C_TEMP:-0}" 70 85)" "${C_FREQ:-0}" "${C_LOAD:-0}"
echo -e "  ${DIM}  Uptime: ${C_UPTIME}${NC}"

GPU_HWMON=""
for d in /sys/class/hwmon/hwmon*; do
    [[ -d "$d" ]] || continue
    grep -qi "amdgpu" "$d/name" 2>/dev/null && GPU_HWMON="$d" && break
done

if [[ -n "$GPU_HWMON" ]]; then
    G_TEMP=$(($(cat "$GPU_HWMON/temp1_input" 2>/dev/null || echo 0) / 1000))
    G_JUNC=$(($(cat "$GPU_HWMON/temp2_input" 2>/dev/null || echo 0) / 1000))
    G_MEM=$(($(cat  "$GPU_HWMON/temp3_input" 2>/dev/null || echo 0) / 1000))
    G_FAN=$(cat "$GPU_HWMON/fan1_input" 2>/dev/null || echo 0)
    G_PWR=$(awk '{printf "%.0f", $1/1000000}' "$GPU_HWMON/power1_average" 2>/dev/null || echo 0)
    G_VRAM_PATH=$(ls /sys/class/drm/card*/device/mem_info_vram_used  2>/dev/null | head -1)
    G_VTOT_PATH=$(ls /sys/class/drm/card*/device/mem_info_vram_total 2>/dev/null | head -1)
    G_FREQ_PATH=$(ls /sys/class/drm/card*/device/pp_dpm_sclk         2>/dev/null | head -1)
    G_VRAM=$(awk '{printf "%.0f", $1/1048576}' "$G_VRAM_PATH" 2>/dev/null || echo 0)
    G_VTOT=$(awk '{printf "%.0f", $1/1048576}' "$G_VTOT_PATH" 2>/dev/null || echo 0)
    G_FREQ=$(grep '\*' "$G_FREQ_PATH" 2>/dev/null | awk '{print $2}' | head -1 | sed 's/[^0-9]//g')
    G_FREQ="${G_FREQ:-0}"

    printf "  ${CYAN}%-16s${NC} Core: %-14s  Junc: %-14s  Mem: %s\n" \
        "GPU (RX 6800)" \
        "$(temp_color "$G_TEMP" 75 90)" \
        "$(temp_color "$G_JUNC" 90 105)" \
        "$(temp_color "$G_MEM"  80 95)"
    printf "  ${DIM}  Fan: %s RPM   Power: %sW   VRAM: %s/%s MB   Freq: %sMHz${NC}\n" \
        "$G_FAN" "$G_PWR" "$G_VRAM" "$G_VTOT" "$G_FREQ"
else
    warn "GPU:         AMDGPU hwmon not found"
fi

# =============================================================================
# 12. DRIVE HEALTH (SMART)
# =============================================================================
section "Drive Health (SMART)"

DRIVES_FOUND=0
while read -r name type; do
    [[ "$type" != "disk" ]] && continue
    disk="/dev/$name"
    [[ -b "$disk" ]] || continue
    (( DRIVES_FOUND++ ))
    SMART=$(sudo smartctl -H "$disk" 2>/dev/null | grep -iE 'overall|result|passed|failed' | xargs)
    if [[ "$SMART" =~ [Pp][Aa][Ss][Ss][Ee][Dd] ]] || [[ "$SMART" =~ [Oo][Kk] ]]; then
        ok "$(printf '%-12s' "$disk")  ${GREEN}${SMART}${NC}"
    elif [[ -n "$SMART" ]]; then
        fail "$(printf '%-12s' "$disk")  ${RED}${SMART}${NC}"
        (( GLOBAL_ISSUES++ ))
    else
        info "$(printf '%-12s' "$disk")  ${DIM}No SMART data${NC}"
    fi
done < <(lsblk -d -n -o NAME,TYPE)
(( DRIVES_FOUND == 0 )) && info "No drives found for SMART check"

# =============================================================================
# 13. NETWORK
# =============================================================================
section "Network"

ping -c1 -W2 8.8.8.8 &>/dev/null \
    && ok "Internet:    Connected" \
    || { fail "Internet:    ${RED}No connectivity${NC}"; (( GLOBAL_ISSUES++ )); }

ACTIVE_IFACES=$(ip link show 2>/dev/null \
    | grep 'state UP' | grep -v 'lo:' | awk -F': ' '{print $2}' | tr '\n' ' ')
info "Active ifaces: ${ACTIVE_IFACES:-none detected}"

# Check for active firewall with rules — ufw, firewalld, or nftables/iptables
FW_ACTIVE=0
FW_RULES=0
if command -v ufw &>/dev/null; then
    UFW_STATUS=$(sudo ufw status 2>/dev/null | grep -i 'Status:' | awk '{print $2}')
    if [[ "$UFW_STATUS" == "active" ]]; then
        FW_ACTIVE=1
        UFW_RULES=$(sudo ufw status 2>/dev/null | awk 'NR>3 && NF' | wc -l)
        (( UFW_RULES > 0 )) && FW_RULES=1
    fi
fi
if (( FW_ACTIVE == 0 )) && systemctl is-active --quiet firewalld 2>/dev/null; then
    FW_ACTIVE=1
    FW_RULES=1
fi
if (( FW_ACTIVE == 0 )) && command -v nft &>/dev/null; then
    sudo nft list ruleset 2>/dev/null | grep -q 'chain' && FW_ACTIVE=1 && FW_RULES=1
fi
if (( FW_ACTIVE == 0 )) && command -v iptables &>/dev/null; then
    sudo iptables -L 2>/dev/null | grep -q 'Chain' && FW_ACTIVE=1 && FW_RULES=1
fi

if (( FW_RULES == 1 )); then
    ok "Firewall:    Good"
elif (( FW_ACTIVE == 1 )) && command -v ufw &>/dev/null; then
    warn "Firewall:    ${YELLOW}UFW active but no rules configured${NC}"
    read -rp "  Apply recommended firewall rules? (y/N): " set_fw
    if [[ "$set_fw" =~ ^[Yy]$ ]]; then
        echo -e "  ${YELLOW}⚠${NC}  Configuring UFW with recommended rules..."
        sudo ufw --force disable 2>/dev/null
        sudo ufw --force reset 2>/dev/null
        sudo ufw default deny incoming 2>/dev/null
        sudo ufw default allow outgoing 2>/dev/null
        sudo ufw limit 22/tcp 2>/dev/null
        sudo ufw allow 80/tcp 2>/dev/null
        sudo ufw allow 443/tcp 2>/dev/null
        sudo ufw --force enable 2>/dev/null
        ok "Firewall:    Configured and enabled"
    fi
elif (( FW_ACTIVE == 1 )); then
    ok "Firewall:    Active"
else
    warn "Firewall:    ${YELLOW}No active firewall detected${NC}"
    if command -v ufw &>/dev/null; then
        read -rp "  Enable UFW with recommended rules? (y/N): " set_fw
        if [[ "$set_fw" =~ ^[Yy]$ ]]; then
            echo -e "  ${YELLOW}⚠${NC}  Configuring UFW with recommended rules..."
            sudo ufw default deny incoming 2>/dev/null
            sudo ufw default allow outgoing 2>/dev/null
            sudo ufw limit 22/tcp 2>/dev/null
            sudo ufw allow 80/tcp 2>/dev/null
            sudo ufw allow 443/tcp 2>/dev/null
            sudo ufw --force enable 2>/dev/null
            ok "Firewall:    Configured and enabled"
        fi
    fi
fi

# =============================================================================
# 14. INSTALLED SOFTWARE OVERVIEW
# =============================================================================
section "Installed Software Overview"

TOTAL_PKGS=$(int    "$(pacman -Q 2>/dev/null | wc -l)")
USER_PKGS=$(pacman -Qe 2>/dev/null | sort)
USER_PKG_COUNT=$(echo "$USER_PKGS" | grep -v '^$' | wc -l)
FLATPAK_PKGS=$(int  "$(flatpak list --app 2>/dev/null | wc -l)")
AUR_PKG_COUNT=0
if [[ -n "$AUR_HELPER" ]]; then
    AUR_PKG_COUNT=$(int "$($AUR_HELPER -Qm 2>/dev/null | wc -l)")
fi

info "Total packages:       ${PURPLE}${TOTAL_PKGS}${NC}"
info "Explicitly installed: ${PURPLE}${USER_PKG_COUNT}${NC}"
[[ -n "$AUR_HELPER" ]] && info "AUR packages:         ${PURPLE}${AUR_PKG_COUNT}${NC}"
info "Flatpak apps:         ${PURPLE}${FLATPAK_PKGS}${NC}"

echo
echo -e "  ${BOLD}${CYAN}Explicitly Installed Packages:${NC}"
echo -e "  ${DIM}────────────────────────────────────────────────────────────${NC}"
echo "$USER_PKGS" | grep -v '^$' | awk '{print $1}' | column -c 90 | \
    while IFS= read -r line; do echo -e "  ${GREEN}${line}${NC}"; done

echo
echo -e "  ${BOLD}${CYAN}Flatpak Applications:${NC}"
echo -e "  ${DIM}────────────────────────────────────────────────────────────${NC}"
if (( FLATPAK_PKGS > 0 )); then
    flatpak list --app --columns=name,application 2>/dev/null | \
        while IFS=$'\t' read -r name appid; do
            printf "  ${PURPLE}%-35s${NC} ${DIM}%s${NC}\n" "$name" "$appid"
        done
else
    info "No Flatpak applications installed"
fi

# =============================================================================
# FINAL REPORT
# =============================================================================
echo
echo -e "${BLUE}${BOLD}  ════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}${BOLD}  SYSTEM HEALTH REPORT${NC}"
echo -e "${BLUE}${BOLD}  ════════════════════════════════════════════════════${NC}"

if (( GLOBAL_ISSUES == 0 )); then
    echo -e "  ${GREEN}${BOLD}✔  All systems nominal.${NC}"
else
    echo -e "  ${YELLOW}${BOLD}⚠  ${GLOBAL_ISSUES} issue(s) need attention.${NC}"
fi

echo -e "  ${DIM}Checked: Updates · Packages · Filesystem · Boot · Journal${NC}"
echo -e "  ${DIM}         Services · DNS · Storage · Memory · Hardware · SMART · Network · Software${NC}"
echo -e "${BLUE}${BOLD}  ════════════════════════════════════════════════════${NC}"
echo
read -rp "  Press Enter to exit..."
echo
if (( GLOBAL_ISSUES > 0 )); then
    mv "$TMP_LOG" "$FINAL_LOG"
    echo -e "  ${DIM}Log saved to: ${FINAL_LOG}${NC}"
else
    rm -f "$TMP_LOG"
fi
echo
