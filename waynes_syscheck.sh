#!/bin/bash

# =============================================================================
#  Wayne's Syscheck of Doom — v4.0 (Linux Mint Edition)
#  Linux Mint 22.x / Ubuntu Noble — Full Edition
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/waynes_syscheck_$(date '+%Y-%m-%d_%H-%M-%S').log"
exec > >(tee >(sed 's/\x1b\[[0-9;]*m//g' > "$LOG_FILE")) 2>&1

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

# AMD Zen3 false-positive filter
AMD_NOISE='Bank [0-9]+ is reserved|cache level: RESV|MC[0-9]+_STATUS|IPID: 0x0+|Syndrome: 0x0+|Error Addr: 0x0+|System Fatal error|tx: INSN|MCE decoding enabled|events logged'

# --- SUDO ---
if ! sudo -v 2>/dev/null; then
    fail "Sudo authentication failed."
    exit 1
fi
while true; do sudo -n true; sleep 60; kill -0 "$$" || exit; done 2>/dev/null &
SUDO_PID=$!
trap "kill $SUDO_PID 2>/dev/null" EXIT

clear
echo -e "${BLUE}${BOLD}"
echo "  ╔══════════════════════════════════════════════════╗"
echo "  ║     Wayne's Syscheck of Doom  v4.0 (Mint)       ║"
echo "  ╚══════════════════════════════════════════════════╝"
echo -e "${NC}${DIM}  $(date '+%A, %B %d %Y  %H:%M:%S')  —  $(uname -r)${NC}"

GLOBAL_ISSUES=0

# =============================================================================
# 1. UPDATES
# =============================================================================
section "Repository Intelligence"

echo -e "  ${DIM}Synchronizing package databases...${NC}"
sudo apt-get update -qq 2>/dev/null
sudo flatpak update --appstream -y >/dev/null 2>&1

APT_UPDATES=$(int "$(apt list --upgradable 2>/dev/null | grep -v 'Listing' | wc -l)")
FLAT_UPDATES=$(int "$(flatpak remote-ls --updates 2>/dev/null | wc -l)")

(( APT_UPDATES  == 0 )) && ok "APT repo:    Up to date" \
    || warn "APT repo:    ${RED}${APT_UPDATES} pending${NC}"
(( FLAT_UPDATES == 0 )) && ok "Flatpak:     Up to date" \
    || warn "Flatpak:     ${RED}${FLAT_UPDATES} pending${NC}"

TOTAL_UPDATES=$(( APT_UPDATES + FLAT_UPDATES ))
if (( TOTAL_UPDATES > 0 )); then
    echo
    read -rp "  Execute system-wide patch? (y/N): " run_updates
    if [[ "$run_updates" =~ ^[Yy]$ ]]; then
        sudo apt-get upgrade -y
        (( FLAT_UPDATES > 0 )) && sudo flatpak update -y
        ok "System patched."
        # Recheck updates after patching to update issue count
        APT_UPDATES=$(int "$(apt list --upgradable 2>/dev/null | grep -v 'Listing' | wc -l)")
        FLAT_UPDATES=$(int "$(flatpak remote-ls --updates 2>/dev/null | wc -l)")
    fi
fi

# Count remaining update issues after patching attempt
(( APT_UPDATES  != 0 )) && (( GLOBAL_ISSUES++ ))
(( FLAT_UPDATES != 0 )) && (( GLOBAL_ISSUES++ ))

# =============================================================================
# 2. PACKAGE DATABASE INTEGRITY
# =============================================================================
section "Package Database Integrity"

echo -e "  ${DIM}Checking for broken packages...${NC}"
BROKEN=$(int "$(sudo dpkg --audit 2>/dev/null | wc -l)")
if (( BROKEN == 0 )); then
    ok "Package DB:  No broken packages"
else
    fail "Package DB:  ${RED}${BROKEN} broken package(s)${NC}"
    sudo dpkg --audit 2>/dev/null | head -5
    (( GLOBAL_ISSUES++ ))
fi

# Check for held packages
HELD=$(int "$(apt-mark showhold 2>/dev/null | wc -l)")
if (( HELD == 0 )); then
    ok "Held pkgs:   None"
else
    warn "Held pkgs:   ${YELLOW}${HELD} package(s) held back${NC}"
    apt-mark showhold 2>/dev/null | while IFS= read -r line; do
        echo -e "             ${DIM}${line}${NC}"
    done
fi

# Check for autoremovable packages
AUTOREMOVE=$(int "$(apt-get --dry-run autoremove 2>/dev/null | grep '^Remov' | wc -l)")
if (( AUTOREMOVE == 0 )); then
    ok "Autoremove:  Nothing to remove"
else
    warn "Autoremove:  ${YELLOW}${AUTOREMOVE} package(s) can be removed${NC}"
    read -rp "  Remove unneeded packages? (y/N): " rem_auto
    if [[ "$rem_auto" =~ ^[Yy]$ ]]; then
        sudo apt-get autoremove -y && ok "Autoremove complete."
    fi
    (( GLOBAL_ISSUES++ ))
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

# Kernel/initramfs
VMLINUZ_COUNT=$(int "$(ls /boot/vmlinuz-* 2>/dev/null | wc -l)")
INITRD_COUNT=$(int  "$(ls /boot/initrd.img-* 2>/dev/null | wc -l)")

if (( VMLINUZ_COUNT > 0 )); then
    ok "Kernels:     ${VMLINUZ_COUNT} kernel image(s) found"
    ls /boot/vmlinuz-* 2>/dev/null | while IFS= read -r f; do
        info "             $(basename "$f")  ${DIM}($(du -sh "$f" 2>/dev/null | awk '{print $1}'))${NC}"
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

APT_CACHE_SIZE=$(sudo du -sh /var/cache/apt/archives 2>/dev/null | awk '{print $1}')
info "APT cache:   ${YELLOW}${APT_CACHE_SIZE}${NC}"
read -rp "  Perform deep clean? (y/N): " deep_clean
if [[ "$deep_clean" =~ ^[Yy]$ ]]; then
    sudo apt-get clean
    sudo apt-get autoremove -y >/dev/null 2>&1

    FLAT_BEFORE=$(sudo du -sh /var/lib/flatpak 2>/dev/null | awk '{print $1}')
    sudo flatpak uninstall --unused -y >/dev/null 2>&1
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

    THUMB_SIZE=$(du -sh ~/.cache/thumbnails 2>/dev/null | awk '{print $1}')
    if [[ -n "$THUMB_SIZE" && "$THUMB_SIZE" != "0" ]]; then
        rm -rf ~/.cache/thumbnails/* 2>/dev/null
        info "Thumbnails:  ${RED}${THUMB_SIZE}${NC} → ${GREEN}0${NC}"
    else
        info "Thumbnails:  ${GREEN}Already clean${NC}"
    fi

    TRASH_SIZE=$(du -sh ~/.local/share/Trash/files 2>/dev/null | awk '{print $1}')
    if [[ -n "$TRASH_SIZE" && "$TRASH_SIZE" != "0" ]]; then
        rm -rf ~/.local/share/Trash/files/* 2>/dev/null
        info "Trash:       ${RED}${TRASH_SIZE}${NC} → ${GREEN}0${NC}"
    else
        info "Trash:       ${GREEN}Already empty${NC}"
    fi

    NEW_SIZE=$(sudo du -sh /var/cache/apt/archives 2>/dev/null | awk '{print $1}')
    ok "Deep clean complete. Cache: ${RED}${APT_CACHE_SIZE}${NC} → ${GREEN}${NEW_SIZE}${NC}"
fi

# =============================================================================
# 7. SERVICES
# =============================================================================
section "System Services"

FAILED_UNITS=$(int "$(systemctl --failed --plain --no-legend 2>/dev/null | grep -v 'casper-md5check' | grep -c '.')")
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

# =============================================================================
# 8. DNS SECURITY
# =============================================================================
section "DNS Security"

DOT_STATUS=$(resolvectl status 2>/dev/null | grep -m1 'Protocols:' | grep -o '+DNSOverTLS\|-DNSOverTLS')
DNSSEC_STATUS=$(resolvectl status 2>/dev/null | grep -m1 'DNSSEC=' | grep -o 'DNSSEC=yes\|DNSSEC=allow-downgrade\|DNSSEC=no')
DNS_SERVER=$(resolvectl status 2>/dev/null | grep 'Current DNS Server' | head -1 | awk '{print $NF}')

# Verify DNS-over-TLS by checking for active TLS connections to DNS server
DOT_VERIFIED=0
if [[ "$DOT_STATUS" == "+DNSOverTLS" ]] && [[ -n "$DNS_SERVER" ]]; then
    # Extract IP from DNS_SERVER (remove #suffix if present)
    DNS_IP=$(echo "$DNS_SERVER" | cut -d'#' -f1)
    # Check for active TCP connections on port 853 (DoT) to the DNS server
    if command -v ss &>/dev/null; then
        if ss -tnp 2>/dev/null | grep ":853 " | grep -q "$DNS_IP"; then
            DOT_VERIFIED=1
        fi
    fi
fi

if [[ "$DOT_STATUS" == "+DNSOverTLS" ]] && (( DOT_VERIFIED == 1 )); then
    ok "DNS-over-TLS: Encrypted (verified active connection)"
elif [[ "$DOT_STATUS" == "+DNSOverTLS" ]]; then
    warn "DNS-over-TLS: ${YELLOW}Configured but no active connection detected${NC}"
else
    fail "DNS-over-TLS: ${RED}NOT encrypted${NC}"
    (( GLOBAL_ISSUES++ ))
fi

[[ "$DNSSEC_STATUS" == "DNSSEC=yes" ]] \
    && ok "DNSSEC:      Enforced" \
    || warn "DNSSEC:      ${YELLOW}${DNSSEC_STATUS:-not set}${NC}"
info "DNS Server:  ${DNS_SERVER:-unknown}"

# Only flush DNS cache if it's larger than threshold (50 entries)
DNS_CACHE_THRESHOLD=50
CACHE_SIZE=0
if command -v resolvectl &>/dev/null; then
    CACHE_STAT=$(sudo resolvectl statistics 2>/dev/null | grep -i 'Current cache size')
    CACHE_SIZE=$(int "$CACHE_STAT")
fi

if (( CACHE_SIZE > DNS_CACHE_THRESHOLD )); then
    sudo resolvectl flush-caches 2>/dev/null
    ok "DNS cache:   Flushed (was ${CACHE_SIZE} entries)"
else
    info "DNS cache:   ${CACHE_SIZE} entries (no flush needed)"
fi

# =============================================================================
# 9. DISK USAGE
# =============================================================================
section "Storage Overview"

# Use process substitution instead of pipe to avoid subshell variable scoping issues
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

# =============================================================================
# 11. HARDWARE TELEMETRY
# =============================================================================
section "Hardware Telemetry"

C_TEMP=$(sensors 2>/dev/null | grep -m1 'Tctl' | awk '{print $2}' | tr -d '+°C' | cut -d'.' -f1)
C_FREQ=$(grep -m1 'cpu MHz' /proc/cpuinfo 2>/dev/null | awk '{printf "%.0f", $4}')
C_LOAD=$(uptime | awk -F'load average:' '{print $2}' | awk '{print $1}' | tr -d ' ,')
C_UPTIME=$(uptime -p | sed 's/up //')

printf "  ${CYAN}%-16s${NC} Temp: %-14s  Freq: ${PURPLE}%s MHz${NC}  Load: ${YELLOW}%s${NC}\n" \
    "CPU (5700X3D)" "$(temp_color "${C_TEMP:-0}" 70 85)" "${C_FREQ:-0}" "${C_LOAD:-0}"
echo -e "  ${DIM}  Uptime: ${C_UPTIME}${NC}"

# GPU HWMON detection - avoid subshell variable scoping issue
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
# Use lsblk to find all disk devices (type=disk) to reliably detect NVMe, SATA, etc.
while read -r name type; do
    [[ "$type" != "disk" ]] && continue
    disk="/dev/$name"
    [[ -b "$disk" ]] || continue
    (( DRIVES_FOUND++ ))
    # Handle SMART output for both NVMe and SATA/HDD
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

UFW_STATUS=$(sudo ufw status 2>/dev/null | grep -i 'Status:' | awk '{print $2}')
[[ "$UFW_STATUS" == "active" ]] \
    && ok "Firewall:    UFW active" \
    || warn "Firewall:    ${YELLOW}UFW not active${NC}"

# =============================================================================
# 14. INSTALLED SOFTWARE OVERVIEW
# =============================================================================
section "Installed Software Overview"

TOTAL_PKGS=$(int    "$(dpkg -l 2>/dev/null | grep '^ii' | wc -l)")
FLATPAK_PKGS=$(int  "$(flatpak list --app 2>/dev/null | wc -l)")
SNAP_PKGS=$(int     "$(snap list 2>/dev/null | grep -v '^Name' | wc -l)")

# Filter out system/base packages — only show what the user actually chose to install
USER_PKGS=$(apt-mark showmanual 2>/dev/null | sort | grep -vE \
    '^(lib|gir1\.2-|python3-|python-|fonts-|gcc-|cpp-|binutils-|xserver-|xfonts-|printer-driver-)' | \
    grep -vE '(-common|-data|-dev|-dbg|-bin|-utils|-core|-base|-locale-|-plugins|-l10n)$' | \
    grep -vE '^(acl|adduser|adwaita|alsa-|amd64-micro|anacron|apg|apparmor|app-install|appstream|apt$|aptdaemon|aptitude|aptkit|apt-utils|aspell|at-spi2|attr|avahi|base-files|base-passwd|bash$|bash-completion|bc$|bind9|bolt|brasero|brltty|bsd|btrfs|bubblewrap|busybox|bzip2|ca-certificates|cifs|cjs|colord|command-not|console-setup|coreutils|cpdb|cpio$|cracklib|cron$|cron-daemon|cryptsetup|curl$|dash$|dbus|dc$|dconf|dcraw|dctrl|debconf|debianutils|desktop-file|dhcpcd|dialog$|dictionaries|diffutils|dirmngr|distro-info|dkms|dmeventd|dmidecode|dmraid|dmsetup|dmz-cursor|dnsmasq-base|dns-root|docbook|dosfstools|dpkg|dracut|e2fs|efibootmgr|eject|emacsen|enchant|espeak|ethtool|evtest|exfat|evolution-data|fakeroot|fdisk|file$|findutils|finalrd|fingwit|firmware-sof|folder-color|foomatic|fprintd|friendly-recovery|ftp$|fuse|fwupd|gcr|gdisk|geoclue|geocode|geoip|genisoimage|gettext|gkbd|glib|gnome-desktop|gnome-keyring|gnome-menus|gnome-online|gnome-session|gnome-settings|gnome-themes|gnupg|gpg|grep|groff|grub|guile|hicolor|ibus|initramfs|iproute2|iputils|kbd|keyboard|klibc|kmod|language|lsb|lvm2|makedev|mdadm|mime|mlocate|modemmanager|mount|multiarch|netbase|netplan|network-manager|ntfs|open-iscsi|openprinting|os-prober|p11-kit|pci\.ids|pciutils|pcmcia|perl|pinentry|pkexec|pkgconf|pkg-config|plocate|policykit|polkit|poppler|powermgmt|procps|psmisc|publicsuffix|pulseaudio|quota|readline|rfkill|rpcsvc|rsyslog|rtkit|samba|sane|sbsign|secureboot|sed|sensible|session|sgml|shared-mime|shim|ssl-cert|sudo|switcheroo|syslinux|sysvinit|tar|tcl|tcl8|tcpdump|telnet|thermald|tpm-udev|tzdata|ubuntu-dbgsym|ubuntu-drivers|ubuntu-keyring|ubuntu-mono|ubuntu-system|ucf|udev|udisks2|uno-libs|untex|update-inetd|upower|ure|usb\.|usb-mode|usbmuxd|usbutils|user-setup|util-linux|uuid|va-driver|vainfo|vdpauinfo|vim-|wamerican|wbritish|webp-pixbuf|wget|whiptail|wireless-reg|wireless-tools|wmctrl|wpasupplicant|x11-|xauth|xawtv|xbitmaps|xbrlapi|xcvt|xdg-dbus|xdg-desktop|xdg-user|xdg-utils|xkb-data|xml-core|xwayland|xxd|xz-utils|yaru|yelp|zenity-common|zlib|zstd|plymouth|systemd|xorg|xapp-|xapps-|strace|inxi|gpgconf|gpgsm|gpgv|exif$|dc$)' \
    )

USER_PKG_COUNT=$(echo "$USER_PKGS" | grep -v '^$' | wc -l)

info "Total packages:       ${PURPLE}${TOTAL_PKGS}${NC}"
info "User installed:       ${PURPLE}${USER_PKG_COUNT}${NC}"
info "Flatpak apps:         ${PURPLE}${FLATPAK_PKGS}${NC}"
info "Snap packages:        ${PURPLE}${SNAP_PKGS}${NC}"

echo
echo -e "  ${BOLD}${CYAN}User Installed Packages:${NC}"
echo -e "  ${DIM}────────────────────────────────────────────────────────────${NC}"
echo "$USER_PKGS" | grep -v '^$' | column -c 90 | \
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

if (( SNAP_PKGS > 0 )); then
    echo
    echo -e "  ${BOLD}${CYAN}Snap Packages:${NC}"
    echo -e "  ${DIM}────────────────────────────────────────────────────────────${NC}"
    snap list 2>/dev/null | grep -v '^Name' | while IFS= read -r line; do
        echo -e "  ${YELLOW}${line}${NC}"
    done
fi

# =============================================================================
# FINAL REPORT
# =============================================================================
echo
echo -e "${BLUE}${BOLD}  ════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}${BOLD}  SYSTEM HEALTH REPORT${NC}"
echo -e "${BLUE}${BOLD}  ════════════════════════════════════════════════════${NC}"

if (( GLOBAL_ISSUES == 0 )); then
    echo -e "  ${GREEN}${BOLD}✔  All systems nominal. Wayne's rig is perfect.${NC}"
else
    echo -e "  ${YELLOW}${BOLD}⚠  ${GLOBAL_ISSUES} issue(s) need attention.${NC}"
fi

echo -e "  ${DIM}Checked: Updates · Packages · Filesystem · Boot · Journal${NC}"
echo -e "  ${DIM}         Services · DNS · Storage · Memory · Hardware · SMART · Network · Software${NC}"
echo -e "${BLUE}${BOLD}  ════════════════════════════════════════════════════${NC}"
echo
read -rp "  Press Enter to exit..."
echo
echo -e "  ${DIM}Log saved to: ${LOG_FILE}${NC}"
echo
