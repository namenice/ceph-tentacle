#!/bin/bash

# --- 1. Configuration (ใส่ IP ทั้งหมดเรียงลำดับจาก Master ไป Backup) ---
NODE_IPS=("172.71.7.28" "172.71.7.29") # เครื่องแรกคือ Master, ที่เหลือคือ Backup
VIP="172.71.7.35/24"
INTERFACE="eth0"
ROUTER_ID="135"

# --- 2. Detection Logic ---
MY_IP=$(hostname -I | awk '{print $1}')
MY_INDEX=-1

for i in "${!NODE_IPS[@]}"; do
   if [[ "${NODE_IPS[$i]}" == "$MY_IP" ]]; then
       MY_INDEX=$i
       break
   fi
done

if [[ $MY_INDEX -eq -1 ]]; then
    echo "❌ Error: My IP ($MY_IP) is not in the NODE_IPS list."
    exit 1
fi

# คำนวณ Role และ Priority (Master = 200, Backup ตัวถัดๆ ไปลดทีละ 50)
if [[ $MY_INDEX -eq 0 ]]; then
    STATE="MASTER"
    PRIORITY=200
else
    STATE="BACKUP"
    PRIORITY=$((200 - (MY_INDEX * 50)))
fi

# เตรียม Unicast Peers (IP ของเครื่องอื่นในกลุ่มทั้งหมด)
PEERS=""
for ip in "${NODE_IPS[@]}"; do
    if [[ "$ip" != "$MY_IP" ]]; then
        # ใช้ช่องว่างแทน \n เพื่อป้องกันปัญหา String Interpretation
        PEERS="$PEERS $ip"
    fi
done

echo "✅ Detected Role: $STATE (Priority: $PRIORITY)"

# --- 3. Installation & Config Generation ---
apt update && apt install -y keepalived

# Kernel Tuning
echo "net.ipv4.ip_nonlocal_bind = 1" | sudo tee /etc/sysctl.d/90-keepalived.conf > /dev/null
sudo sysctl --system > /dev/null

cat <<EOF | sudo tee /etc/keepalived/keepalived.conf > /dev/null
global_defs {
    router_id node0$((MY_INDEX + 1))
}

vrrp_script check_haproxy {
    script "/usr/bin/killall -0 haproxy"
    interval 2
    weight 2
}

vrrp_instance VRRP1 {
    state $STATE
    interface $INTERFACE
    virtual_router_id $ROUTER_ID
    priority $PRIORITY
    advert_int 1

    unicast_src_ip $MY_IP
    unicast_peer {
        $PEERS
    }

    authentication {
        auth_type PASS
        auth_pass ceph_s3_secret
    }

    virtual_ipaddress {
        $VIP
    }

    track_script {
        check_haproxy
    }
}
EOF

systemctl enable --now keepalived
systemctl restart keepalived

echo "========================================================"
echo "🎯 Keepalived Node $((MY_INDEX + 1)) Setup as $STATE"
echo "========================================================"
