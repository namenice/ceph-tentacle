#!/bin/bash

# --- 1. Check Root Privilege ---
if [[ $EUID -ne 0 ]]; then
   echo "❌ Error: This script must be run as root."
   exit 1
fi

# --- 2. OS Version Validation ---
OS_ID=$(grep -w "ID" /etc/os-release | cut -d'=' -f2 | tr -d '"')
OS_VERSION=$(grep -w "VERSION_ID" /etc/os-release | cut -d'=' -f2 | tr -d '"')

echo "🔍 Checking OS Compatibility..."
if [[ "$OS_ID" == "ubuntu" ]] && [[ "$OS_VERSION" == "22.04" ]]; then
    echo "✅ OS Verified: Ubuntu $OS_VERSION (Jammy Jellyfish)"
else
    echo "❌ Error: This script is strictly for Ubuntu 22.04."
    exit 1
fi

echo "🚀 [Start] Preparing Host for Ceph RGW..."

# --- 3. Set Timezone ---
timedatectl set-timezone Asia/Bangkok

# --- 4. Update System & Install Core Dependencies ---
echo "📦 Updating packages and installing dependencies..."
apt update && apt upgrade -y > /dev/null
apt install -y curl wget vim python3 python3-pip lvm2 chrony \
            apt-transport-https ca-certificates \
            dbus-user-session python3-distutils > /dev/null

# --- 5. Disable Swap ---
echo "🚫 Disabling Swap..."
swapoff -a
sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab

# --- 6. Enable Chrony (Time Sync) ---
echo "⏰ Starting Time Sync service..."
systemctl enable --now chrony > /dev/null
systemctl restart chrony

# --- 7. Kernel Tuning ---
echo "⚙️ Tuning Kernel Parameters..."
TOTAL_MEM_KB=$(grep MemTotal /proc/meminfo | awk '{print $2}')
if [ "$TOTAL_MEM_KB" -gt 67108864 ]; then 
    MIN_FREE=4194304 # 4GB
    NODE_TYPE="Hardware/High-RAM"
else
    MIN_FREE=524288  # 512MB
    NODE_TYPE="VM/Low-RAM"
fi

cat <<EOF | tee /etc/sysctl.d/90-ceph.conf > /dev/null
net.core.somaxconn = 8192
net.ipv4.tcp_tw_reuse = 1
net.ipv4.ip_local_port_range = 1024 65535
net.core.rmem_max = 67108864
net.core.wmem_max = 67108864
net.ipv4.tcp_rmem = 4096 87380 67108864
net.ipv4.tcp_wmem = 4096 65536 67108864
vm.swappiness = 5
vm.min_free_kbytes = $MIN_FREE
vm.max_map_count = 262144
fs.file-max = 4194304
EOF
sudo sysctl --system > /dev/null

# --- 8. Set Resource Limits ---
echo "📋 Configuring Resource Limits..."
cat <<EOF | sudo tee /etc/security/limits.d/ceph.conf > /dev/null
* soft nofile 1048576
* hard nofile 1048576
EOF

# --- 9. Install Tooling ---
echo "🛠️ Installing debugging tools..."
apt install -y htop iotop iftop net-tools smartmontools > /dev/null

# --- 10. Detailed Summary of Actions ---
echo ""
echo "========================================================"
echo "🎯 HOST PREPARATION COMPLETED!"
echo "========================================================"
echo "📊 SYSTEM INFO:"
echo "   - OS Version     : Ubuntu $OS_VERSION"
echo "   - Hostname       : $(hostname)"
echo "   - Detected RAM   : $((TOTAL_MEM_KB / 1024 / 1024)) GB"
echo "   - Node Profile   : $NODE_TYPE"
echo ""
echo "⚙️ KERNEL & MEMORY TUNING:"
echo "   - vm.min_free_kbytes : $((MIN_FREE / 1024)) MB (Guarded for Kernel)"
echo "   - vm.swappiness      : $(sysctl -n vm.swappiness) (Optimized for RAM)"
echo "   - fs.file-max        : $(sysctl -n fs.file-max) (System-wide file limit)"
echo ""
echo "🌐 NETWORK OPTIMIZATION:"
echo "   - somaxconn          : $(sysctl -n net.core.somaxconn) (Backlog Queue)"
echo "   - TCP Max Buffer     : 64 MB (High-throughput ready)"
echo ""
echo "📂 RESOURCE LIMITS (ulimit):"
echo "   - Max Open Files     : $(grep "soft nofile" /etc/security/limits.d/ceph.conf | awk '{print $4}') (Standard for Ceph)"
echo ""
echo "✅ SERVICES & SECURITY:"
echo "   - Time Sync (Chrony) : $(systemctl is-active chrony)"
echo "   - Swap Status        : $([[ -z $(swapon --show) ]] && echo "OFF (PASS)" || echo "ON (WARNING)")"
echo "   - Debug Tools        : Installed (htop, iotop, iftop, smartctl)"
echo "--------------------------------------------------------"
echo "👉 NEXT STEP: REBOOT now to apply all kernel changes."
echo "========================================================"
