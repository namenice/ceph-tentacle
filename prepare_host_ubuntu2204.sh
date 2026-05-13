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
sudo locale-gen en_GB.UTF-8 >> "$LOG_FILE" 2>&1
sudo update-locale LC_TIME=en_GB.UTF-8 >> "$LOG_FILE" 2>&1

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
# 1. เช็คว่าเป็น Hardware หรือ VM
VIRT_TYPE=$(systemd-detect-virt)

if [ "$VIRT_TYPE" = "none" ]; then
    NODE_TYPE="Physical Hardware"
    # ถ้าเป็นเครื่องจริง กั้น RAM 4GB (เหมาะกับ OSD Node)
    MIN_FREE=4194304 
else
    NODE_TYPE="Virtual Machine ($VIRT_TYPE)"
    # ถ้าเป็น VM กั้น RAM 512MB (เหมาะกับ RGW/Admin Node)
    MIN_FREE=524288
fi

# 2. (Optional) ปรับจูนเพิ่มเติมตามปริมาณ RAM จริง 
# แม้จะเป็น VM แต่ถ้า RAM เยอะมาก ก็ควรเพิ่ม MIN_FREE ตามสัดส่วน
TOTAL_MEM_KB=$(grep MemTotal /proc/meminfo | awk '{print $2}')
if [ "$VIRT_TYPE" != "none" ] && [ "$TOTAL_MEM_KB" -gt 67108864 ]; then
    # กรณีเป็น VM แต่ RAM > 64GB ให้กั้นไว้ 1GB เพื่อความปลอดภัย
    MIN_FREE=1048576
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

# --- 9. Install Tooling ---
setup_ssh_root() {
# 2. สร้างไฟล์คอนฟิกใหม่ใน sshd_config.d
# การตั้งค่าในนี้จะไป Override หรือเพิ่มเติมจากไฟล์หลัก
cat <<EOF > /etc/ssh/sshd_config.d/01-ceph-root-ssh.conf
# Custom SSH configuration for Ceph Nodes
PermitRootLogin yes
PasswordAuthentication yes
EOF
# ปรับ Permission ให้ปลอดภัย
chmod 644 /etc/ssh/sshd_config.d/01-ceph-root-ssh.conf
# 3. Restart SSH service
systemctl restart sshd
}
setup_ssh_root >> "$LOG_FILE" 2>&1 &
show_progress $! "🔑 Configuring SSH Root Access via sshd_config.d..."

# ---  Detailed Summary of Actions ---
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
echo -e "🌐 ${GREEN}NETWORK INTERFACES (Hierarchy Tree):${NC}"

# รายการสำหรับเช็คว่า Interface ไหนถูกจัดการไปแล้ว เพื่อไม่ให้แสดงซ้ำ
PROCESSED_IFS=()

# 1. แสดงกลุ่ม Bonding และโครงสร้างลำดับชั้น
for master_bond in $(ls /sys/class/net/ 2>/dev/null); do
    if [ -d "/sys/class/net/$master_bond/bonding" ]; then

        # --- 1.1 แสดง Physical Slaves พร้อม Status และ MTU (eno1, eno2, ...) ---
        SLAVES_DISPLAY=""
        for slave in $(cat /sys/class/net/$master_bond/bonding/slaves 2>/dev/null); do
            S_MTU=$(cat /sys/class/net/$slave/mtu 2>/dev/null)
            S_STATE=$(cat /sys/class/net/$slave/operstate 2>/dev/null | tr '[:lower:]' '[:upper:]')
            [[ "$S_STATE" == "UP" ]] && S_COLOR="${GREEN}" || S_COLOR="${RED}"

            SLAVES_DISPLAY+="${slave} [${S_COLOR}${S_STATE}${NC}] (MTU:${S_MTU}), "
            PROCESSED_IFS+=("$slave")
        done
        # พิมพ์บรรทัด Physical Slaves (ตัดคอมม่าตัวสุดท้าย)
        echo -e "   ${SLAVES_DISPLAY%, }"

        # --- 1.2 แสดง Master Bond ---
        B_MODE=$(cat /sys/class/net/$master_bond/bonding/mode | awk '{print $1}')
        B_MTU=$(cat /sys/class/net/$master_bond/mtu 2>/dev/null)
        B_RAW_STATE=$(cat /sys/class/net/$master_bond/operstate 2>/dev/null)
        B_STATE=$(echo $B_RAW_STATE | tr '[:lower:]' '[:upper:]')

        [[ "$B_STATE" == "UP" ]] && B_COLOR="${GREEN}" || B_COLOR="${RED}"
        [[ "$B_STATE" == "LOWERLAYERDOWN" ]] && { B_STATE="L-DOWN"; B_COLOR="${RED}"; }

        echo -e "   └─> ${GREEN}${master_bond}${NC} [Bond Master ($B_MODE)] Status: ${B_COLOR}${B_STATE}${NC}, MTU: ${B_MTU}"
        PROCESSED_IFS+=("$master_bond")

        # --- 1.3 แสดง VLANs ที่เกาะอยู่ใต้ Bond นี้ ---
        for vlan in $(ls /sys/class/net/); do
            # เช็คความสัมพันธ์ Parent (รองรับชื่อแบบ bond0.3949 หรือการเช็ค link ใน ip -d)
            PARENT=$(ip -d link show "$vlan" 2>/dev/null | grep -Po 'link \K[^ ]+' | head -n 1)

            if [[ "$PARENT" == "$master_bond" ]] || [[ "$vlan" == "$master_bond."* ]]; then
                V_ID=$(ip -d link show "$vlan" | grep -Po 'vlan protocol .* id \K\d+')
                V_MTU=$(cat /sys/class/net/$vlan/mtu 2>/dev/null)
                V_RAW_STATE=$(cat /sys/class/net/$vlan/operstate 2>/dev/null)
                V_STATE=$(echo $V_RAW_STATE | tr '[:lower:]' '[:upper:]')

                [[ "$V_STATE" == "UP" ]] && V_COLOR="${GREEN}" || V_COLOR="${RED}"
                [[ "$V_STATE" == "LOWERLAYERDOWN" ]] && { V_STATE="L-DOWN"; V_COLOR="${RED}"; }

                # ตรวจสอบ Label MTU 9000 vs 1500
                if [ "$V_MTU" -eq 9000 ]; then V_MTU_L="${GREEN}9000 (Jumbo)${NC}"; else V_MTU_L="${NC}1500 (Std)${NC}"; fi

                echo -e "       └─> ${GREEN}${vlan}${NC} [VLAN: ${V_ID}] Status: ${V_COLOR}${V_STATE}${NC}, MTU: ${V_MTU_L}"
                PROCESSED_IFS+=("$vlan")

                # --- 1.4 แสดง IP ของ VLAN ---
                V_IP=$(ip -4 -br addr show "$vlan" 2>/dev/null | awk '{print $3}')
                if [ ! -z "$V_IP" ]; then
                    echo -e "           └─> IPv4: ${GREEN}${V_IP}${NC}"
                fi
            fi
        done
        echo "" # เว้นบรรทัดระหว่างกลุ่ม
    fi
done

# 2. แสดง Physical อื่นๆ ที่ไม่ได้ทำ Bond (ถ้ามี)
FIRST_OTHER=true
for phys in $(ls /sys/class/net/); do
    [[ "$phys" == "lo" ]] || [[ "$phys" == "bonding_masters" ]] && continue
    if [[ ! " ${PROCESSED_IFS[@]} " =~ " ${phys} " ]]; then
        if $FIRST_OTHER; then echo -e "🌐 OTHER PHYSICAL INTERFACES:"; FIRST_OTHER=false; fi
        P_MTU=$(cat /sys/class/net/$phys/mtu 2>/dev/null)
        P_STATE=$(cat /sys/class/net/$phys/operstate 2>/dev/null | tr '[:lower:]' '[:upper:]')
        P_IP=$(ip -4 -br addr show "$phys" 2>/dev/null | awk '{print $3}')
        [[ -z "$P_IP" ]] && P_IP="No IP"
        [[ "$P_STATE" == "UP" ]] && P_COLOR="${GREEN}" || P_COLOR="${RED}"
        echo -e "   - ${phys} [${P_COLOR}${P_STATE}${NC}] : IP: ${P_IP} | MTU: ${P_MTU}"
    fi
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
echo "   - Max Open Files     : $(grep "soft nofile" /etc/security/limits.d/ceph.conf | awk '{print $4}')"
echo ""
echo -e "✅ ${GREEN}SERVICES & SECURITY:${NC}"
echo "   - Time Sync (Chrony) : $(systemctl is-active chrony)"
echo -e "   - Swap Status        : $([[ -z $(swapon --show) ]] && echo -e "${GREEN}OFF (PASS)${NC}" || echo -e "${RED}ON (WARNING)${NC}")"
echo "   - Detailed Log Path  : $LOG_FILE"
#!/bin/bash
echo ""
echo -e "🔍 ${GREEN}Verifying SSH Root Access (Include-aware):${NC}"
# 1. ตรวจสอบจากค่าที่ Effective จริง (ใช้ sshd -T เพื่อดูค่าที่ระบบมองเห็นหลังรวมทุกไฟล์แล้ว)
SSH_VARS=$(sshd -T)
CURRENT_PERMIT_ROOT=$(echo "$SSH_VARS" | grep -i "^permitrootlogin" | awk '{print $2}')
CURRENT_PWD_AUTH=$(echo "$SSH_VARS" | grep -i "^passwordauthentication" | awk '{print $2}')

# Check PermitRootLogin
if [ "$CURRENT_PERMIT_ROOT" == "yes" ]; then
    echo -e "   [✔] PermitRootLogin: ${GREEN}yes${NC} (Effective)"
else
    echo -e "   [✘] PermitRootLogin: ${RED}$CURRENT_PERMIT_ROOT${NC}"
fi

# Check PasswordAuthentication
if [ "$CURRENT_PWD_AUTH" == "yes" ]; then
    echo -e "   [✔] PasswordAuth  : ${GREEN}yes${NC} (Effective)"
else
    echo -e "   [✘] PasswordAuth  : ${RED}$CURRENT_PWD_AUTH${NC}"
fi

# 2. ตรวจสอบว่าไฟล์ที่เราสร้างขึ้นมีอยู่จริงไหม
if [ -f "/etc/ssh/sshd_config.d/01-ceph-root-ssh.conf" ]; then
    echo -e "   [✔] Config File   : Found 01-ceph-root-ssh.conf"
else
    echo -e "   [!] Config File   : ${RED}Custom config file not found!${NC}"
fi

# 3. Service Status
if systemctl is-active --quiet ssh; then
    echo -e "   [✔] Service       : SSH Daemon is running"
else
    echo -e "   [✘] Service       : SSH Daemon is DOWN"
fi
echo ""
echo "--------------------------------------------------------"
echo -e "👉 ${RED}NEXT STEP:${NC} REBOOT now to apply all kernel changes."
echo "========================================================"
