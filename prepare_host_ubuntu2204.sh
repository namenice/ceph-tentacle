#!/bin/bash

# --- 0. Define Variables & Colors ---
LOG_FILE="/tmp/ceph_prep.log"
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' 
CHECKMARK='\u2714'
CROSS='\u2718'

# สร้างไฟล์ Log และบันทึกเวลา
echo "==========================================" > "$LOG_FILE"
echo "🚀 Ceph Preparation Log - $(date)" >> "$LOG_FILE"
echo "==========================================" >> "$LOG_FILE"

# --- 0. Helper Function for Progress Spinner ---
show_progress() {
    local pid=$1
    local message=$2
    local spinstr='|/-\'
    echo -n -e "$message "
    while kill -0 $pid 2>/dev/null; do
        local temp=${spinstr#?}
        printf " [%c]  " "$spinstr"
        local spinstr=$temp${spinstr%"$temp"}
        sleep 0.1
        printf "\b\b\b\b\b\b"
    done
    
    wait $pid
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}[$CHECKMARK SUCCESS]${NC}"
        echo -e "✅ $message : COMPLETED" >> "$LOG_FILE"
    else
        echo -e "${RED}[$CROSS FAILED]${NC}"
        echo -e "❌ $message : FAILED" >> "$LOG_FILE"
        echo -e "${RED}ℹ️ Check detailed logs: tail -n 50 $LOG_FILE${NC}"
        exit 1
    fi
}

# --- 1. Check Root ---
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}❌ Error: This script must be run as root.${NC}" | tee -a "$LOG_FILE"
   exit 1
fi

# --- 2. OS Validation ---
OS_ID=$(grep -w "ID" /etc/os-release | cut -d'=' -f2 | tr -d '"')
OS_VERSION=$(grep -w "VERSION_ID" /etc/os-release | cut -d'=' -f2 | tr -d '"')

if [[ "$OS_ID" != "ubuntu" ]] || [[ "$OS_VERSION" != "22.04" ]]; then
    echo -e "${RED}❌ Error: This script is strictly for Ubuntu 22.04.${NC}" | tee -a "$LOG_FILE"
    exit 1
fi

echo -e "🚀 ${GREEN}[Start]${NC} Preparing Host (Detailed output redirected to $LOG_FILE)..."

# --- 3. Set Timezone ---
timedatectl set-timezone Asia/Bangkok >> "$LOG_FILE" 2>&1

# --- 4. Update & Install ---
(apt-get update -y && apt-get upgrade -y) >> "$LOG_FILE" 2>&1 &
show_progress $! "📦 Updating & Upgrading system packages..."

apt-get install -y curl wget vim python3 python3-pip lvm2 chrony \
            apt-transport-https ca-certificates \
            dbus-user-session python3-distutils bc net-tools >> "$LOG_FILE" 2>&1 &
show_progress $! "📦 Installing core dependencies..."

# --- 5. Disable Swap ---
disable_swap() {
    swapoff -a
    sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab
}
disable_swap >> "$LOG_FILE" 2>&1 &
show_progress $! "🚫 Disabling Swap permanent..."

# --- 6. Enable Chrony ---
setup_chrony() {
    systemctl enable --now chrony
    systemctl restart chrony
}
setup_chrony >> "$LOG_FILE" 2>&1 &
show_progress $! "⏰ Configuring Chrony time sync..."

# --- 7. Kernel Tuning ---
TOTAL_MEM_KB=$(grep MemTotal /proc/meminfo | awk '{print $2}')
if [ "$TOTAL_MEM_KB" -gt 67108864 ]; then 
    MIN_FREE=4194304 # 4GB
    NODE_TYPE="Hardware/OSD Node"
else
    MIN_FREE=524288  # 512MB
    NODE_TYPE="VM/RGW Node"
fi

apply_kernel_tuning() {
cat <<EOF > /etc/sysctl.d/90-ceph.conf
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
sudo sysctl --system
}
apply_kernel_tuning >> "$LOG_FILE" 2>&1 &
show_progress $! "⚙️ Tuning Kernel Parameters..."

# --- 8. Set Resource Limits ---
apply_limits() {
cat <<EOF > /etc/security/limits.d/ceph.conf
* soft nofile 1048576
* hard nofile 1048576
EOF
}
apply_limits >> "$LOG_FILE" 2>&1 &
show_progress $! "📋 Configuring Resource Limits (ulimit)..."

# --- 9. Install Tooling ---
apt-get install -y htop iotop iftop smartmontools >> "$LOG_FILE" 2>&1 &
show_progress $! "🛠️ Installing debugging tools..."

# --- Hardware & Network Detection Variables ---
CPU_MODEL=$(lscpu | grep "Model name" | cut -d':' -f2 | xargs)
CPU_CORES=$(nproc)
KERNEL_VER=$(uname -r)
DISK_COUNT=$(lsblk -dno TYPE | grep -c disk)

# --- 10. Detailed Summary of Actions ---
echo -e "\n========================================================"
echo -e "🎯 ${GREEN}HOST PREPARATION COMPLETED!${NC}"
echo -e "========================================================"
echo -e "📊 ${GREEN}SYSTEM INFO:${NC}"
echo "   - OS Version     : Ubuntu $OS_VERSION"
echo "   - Kernel Version : $KERNEL_VER"
echo "   - Hostname       : $(hostname)"
echo "   - CPU            : $CPU_MODEL ($CPU_CORES Cores)"
echo "   - Detected RAM   : $((TOTAL_MEM_KB / 1024 / 1024)) GB"
echo "   - Disk Count     : $DISK_COUNT Physical Disk(s)"
echo "   - Node Profile   : $NODE_TYPE"
echo ""
echo -e "🌐 ${GREEN}NETWORK INTERFACES (IPv4):${NC}"
# Logic ปรับปรุงใหม่เพื่อเช็ค Bond/VLAN Hierarchy
ip -4 -o addr show | awk '{print $2, $4}' | while read ifname ipaddr; do
    [[ "$ifname" == "lo" ]] && continue

    # 1. ดึงชื่อจริง (กรณีมี @ เช่น bond1.3951@bond1)
    REAL_IF=$(echo $ifname | cut -d'@' -f1)
    PARENT=$(ip -d link show "$REAL_IF" | grep -Po '(\w+)(?=@)|link \K[^ ]+' | head -n 1)

    # 2. เช็ค MTU
    MTU=$(cat /sys/class/net/$REAL_IF/mtu 2>/dev/null)

    # 3. เช็ค VLAN ID (ดึงจาก id xxxx โดยตรง)
    VLAN_ID=$(ip -d link show "$REAL_IF" | grep -Po 'vlan protocol .* id \K\d+')
    [[ -z "$VLAN_ID" ]] && VLAN_ID="None"

    printf "   - %-15s : IP: %-18s | MTU: %-5s | VLAN: %-5s \n" "$REAL_IF" "$ipaddr" "$MTU" "$VLAN_ID"
done
echo ""
echo -e "⚙️ ${GREEN}KERNEL & MEMORY TUNING (Applied):${NC}"
echo "   - vm.min_free_kbytes : $((MIN_FREE / 1024)) MB (Reserved for Kernel)"
echo "   - vm.swappiness      : $(sysctl -n vm.swappiness) (Optimized for Storage)"
echo "   - fs.file-max        : $(sysctl -n fs.file-max) (Max File Handles)"
echo ""
echo -e "🌐 ${GREEN}NETWORK KERNEL TUNING:${NC}"
echo "   - somaxconn          : $(sysctl -n net.core.somaxconn) (Backlog Queue)"
echo "   - TCP Max Buffer     : 64 MB (High-throughput ready)"
echo ""
echo -e "📂 ${GREEN}RESOURCE LIMITS (ulimit):${NC}"
echo "   - Max Open Files     : $(grep "soft nofile" /etc/security/limits.d/ceph.conf | awk '{print $3}')"
echo ""
echo -e "✅ ${GREEN}SERVICES & SECURITY:${NC}"
echo "   - Time Sync (Chrony) : $(systemctl is-active chrony)"
echo -e "   - Swap Status        : $([[ -z $(swapon --show) ]] && echo -e "${GREEN}OFF (PASS)${NC}" || echo -e "${RED}ON (WARNING)${NC}")"
echo "   - Detailed Log Path  : $LOG_FILE"
echo "--------------------------------------------------------"
echo -e "👉 ${RED}NEXT STEP:${NC} REBOOT now to apply all kernel changes."
echo "========================================================"
