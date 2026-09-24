#!/usr/bin/env bash
# Proxmox VE post-install baseline setup.
#
# Run this once, manually, at the Proxmox root console or over SSH,
# AFTER you've logged in yourself (this script never touches credentials
# and assumes it's already running as root in an authenticated shell).
#
# What it does:
#   1. Switches from the enterprise repo (needs a paid subscription) to
#      the free no-subscription repo.
#   2. Updates and upgrades all packages.
#   3. Installs fail2ban and turns on an SSH jail (blocks repeated
#      failed SSH login attempts).
#   4. Installs unattended-upgrades so security patches apply automatically.
#
# Deliberately NOT included (handled in later homelab stages instead):
#   - Firewall rules / VLAN segmentation (Stage 4/5 of the homelab plan)
#   - Disabling root SSH login (do this yourself once you've confirmed
#     key-based SSH access works — don't want to lock yourself out)

set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
    echo "This script must be run as root." >&2
    exit 1
fi

echo "==> Switching Proxmox repos to no-subscription"
# Disable the enterprise repo (requires a paid license we don't have)
if [ -f /etc/apt/sources.list.d/pve-enterprise.list ]; then
    sed -i 's/^deb/#deb/' /etc/apt/sources.list.d/pve-enterprise.list
fi
if [ -f /etc/apt/sources.list.d/ceph.list ]; then
    sed -i 's/^deb/#deb/' /etc/apt/sources.list.d/ceph.list
fi

# Enable the free no-subscription repo if it isn't already present
PVE_NOSUB_LIST=/etc/apt/sources.list.d/pve-no-subscription.list
if [ ! -f "$PVE_NOSUB_LIST" ]; then
    CODENAME=$(awk -F= '/^VERSION_CODENAME/{print $2}' /etc/os-release)
    if [ -z "$CODENAME" ]; then
        echo "Could not detect VERSION_CODENAME from /etc/os-release, aborting." >&2
        exit 1
    fi
    echo "deb http://download.proxmox.com/debian/pve ${CODENAME} pve-no-subscription" > "$PVE_NOSUB_LIST"
fi

echo "==> Updating package lists and upgrading"
apt-get update
apt-get -y full-upgrade

echo "==> Installing fail2ban"
apt-get -y install fail2ban
cat > /etc/fail2ban/jail.d/sshd.local <<'EOF'
[sshd]
enabled = true
port    = ssh
maxretry = 5
bantime  = 1h
EOF
systemctl enable --now fail2ban

echo "==> Installing unattended-upgrades"
apt-get -y install unattended-upgrades
cat > /etc/apt/apt.conf.d/51unattended-upgrades-pve <<'EOF'
Unattended-Upgrade::Origins-Pattern {
    "origin=Debian,codename=${distro_codename},label=Debian-Security";
};
Unattended-Upgrade::Automatic-Reboot "false";
EOF
systemctl enable --now unattended-upgrades

echo "==> Done. Consider rebooting to confirm everything came up clean:"
echo "    reboot"
