#!/usr/bin/env bash
# Chapter 27 host-tuning script. Run on the bare-metal or VM host that
# owns the Postgres process. Re-runnable: every section is idempotent.
#
# This script does NOT run inside a container. It tunes the host kernel.
# On managed Postgres, the kernel is owned by the cloud provider and you
# cannot touch any of this.
#
# Usage:
#   sudo ./os-tuning.sh
#
# Verify after reboot:
#   sysctl vm.swappiness vm.dirty_bytes vm.dirty_background_bytes vm.nr_hugepages
#   cat /sys/kernel/mm/transparent_hugepage/enabled
#   cat /sys/block/nvme0n1/queue/scheduler

set -euo pipefail

if [[ $EUID -ne 0 ]]; then
    echo "Run as root." >&2
    exit 1
fi

# --- (1) sysctl: swap, dirty pages, hugepages ------------------------------
# vm.swappiness = 1: swap as a last resort, never as a routine choice.
# vm.dirty_*_bytes: keep writeback small and continuous, not bursty.
# vm.nr_hugepages: 8500 * 2 MB = ~17 GB, enough for shared_buffers = 16 GB.
cat > /etc/sysctl.d/99-postgres.conf <<'EOF'
vm.swappiness = 1
vm.dirty_background_bytes = 67108864
vm.dirty_bytes = 268435456
vm.nr_hugepages = 8500
EOF

sysctl --system

# --- (2) Transparent Hugepages: disable ------------------------------------
# THP is enabled by default on most distributions. Postgres wants explicit
# hugepages, not opportunistic ones. Disable both at runtime and at boot.
echo never > /sys/kernel/mm/transparent_hugepage/enabled
echo never > /sys/kernel/mm/transparent_hugepage/defrag

# Persist across reboots via systemd. (GRUB cmdline is the alternative.)
cat > /etc/systemd/system/disable-thp.service <<'EOF'
[Unit]
Description=Disable Transparent Huge Pages
DefaultDependencies=no
After=sysinit.target local-fs.target
Before=postgresql.service

[Service]
Type=oneshot
ExecStart=/bin/sh -c "echo never > /sys/kernel/mm/transparent_hugepage/enabled && echo never > /sys/kernel/mm/transparent_hugepage/defrag"

[Install]
WantedBy=basic.target
EOF

systemctl daemon-reload
systemctl enable disable-thp.service

# --- (3) I/O scheduler: NVMe = none, SATA SSD = mq-deadline ----------------
# Hot-applies the scheduler to currently attached devices. The udev rule
# below makes the choice persistent across reboots.
for dev in /sys/block/nvme*n*; do
    [[ -e "$dev" ]] && echo none > "$dev/queue/scheduler" 2>/dev/null || true
done
for dev in /sys/block/sd*; do
    [[ -e "$dev" ]] || continue
    if [[ "$(cat "$dev/queue/rotational")" == "0" ]]; then
        echo mq-deadline > "$dev/queue/scheduler" 2>/dev/null || true
    fi
done

cat > /etc/udev/rules.d/60-postgres-scheduler.rules <<'EOF'
ACTION=="add|change", KERNEL=="nvme[0-9]*n[0-9]*", ATTR{queue/scheduler}="none"
ACTION=="add|change", KERNEL=="sd[a-z]*", ATTR{queue/rotational}=="0", ATTR{queue/scheduler}="mq-deadline"
EOF

udevadm control --reload-rules

# --- (4) memlock ulimit for the postgres user ------------------------------
# Required for huge_pages = on. Without it, Postgres cannot lock the buffer
# pool into hugepages and silently falls back.
cat > /etc/security/limits.d/99-postgres.conf <<'EOF'
postgres soft memlock unlimited
postgres hard memlock unlimited
EOF

echo
echo "Done. Reboot recommended to verify all settings persist."
echo "After reboot, verify with:"
echo "  sysctl vm.swappiness vm.dirty_bytes vm.dirty_background_bytes vm.nr_hugepages"
echo "  cat /sys/kernel/mm/transparent_hugepage/enabled"
echo "  cat /sys/block/nvme0n1/queue/scheduler"
echo "  grep HugePages /proc/meminfo"
