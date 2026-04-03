#!/bin/bash

# --- Configuration ---
HAPROXY_VER="3.2.15"
HAPROXY_URL="https://www.haproxy.org/download/3.2/src/haproxy-${HAPROXY_VER}.tar.gz"

# Check Root
if [[ $EUID -ne 0 ]]; then
   echo "❌ Please run as root"
   exit 1
fi

echo "📦 [1/6] Installing Build Dependencies..."
apt update && apt install -y build-essential gcc make libpcre2-dev libssl-dev zlib1g-dev libsystemd-dev wget curl

echo "📂 [2/6] Downloading and Extracting HAProxy ${HAPROXY_VER}..."
cd /tmp
wget -q $HAPROXY_URL
tar -xzf "haproxy-${HAPROXY_VER}.tar.gz"
cd "haproxy-${HAPROXY_VER}"

echo "🛠️ [3/6] Compiling HAProxy (this may take a minute)..."
make -j $(nproc) TARGET=linux-glibc USE_PCRE2=1 USE_OPENSSL=1 USE_ZLIB=1 USE_SYSTEMD=1 USE_PROMETHEUS_EXPORTER=1
make install

# มั่นใจว่าไฟล์อยู่ที่ /usr/local/bin ตามที่คุณต้องการ
cp /usr/local/sbin/haproxy /usr/local/bin/haproxy

echo "👤 [4/6] Setting up User and Directories..."
getent group haproxy >/dev/null || groupadd -g 188 haproxy
getent passwd haproxy >/dev/null || useradd -g haproxy -u 188 -d /var/lib/haproxy -s /sbin/nologin -c haproxy haproxy

mkdir -p /etc/haproxy /var/lib/haproxy
chown haproxy:haproxy /var/lib/haproxy

echo "📄 [5/6] Creating Systemd Service File..."
# ใช้ 'EOF' เพื่อป้องกันตัวแปรถูกตีความขณะสร้างไฟล์
cat <<'EOF' | tee /etc/systemd/system/haproxy.service > /dev/null
[Unit]
Description=HAProxy Load Balancer
After=network-online.target
Wants=network-online.target

[Service]
LimitNOFILE=1048576
Environment="CONFIG=/etc/haproxy/haproxy.cfg" "PIDFILE=/run/haproxy.pid"

# ชี้ไปที่ /usr/local/bin ตามที่คุณระบุ
ExecStartPre=/usr/local/bin/haproxy -f $CONFIG -c -q
ExecStart=/usr/local/bin/haproxy -Ws -f $CONFIG -p $PIDFILE

ExecReload=/usr/local/bin/haproxy -f $CONFIG -c -q
ExecReload=/bin/kill -USR2 $MAINPID

KillMode=mixed
Restart=always
SuccessExitStatus=143
Type=notify

[Install]
WantedBy=multi-user.target
EOF

echo "⚙️ [6/6] Creating Default Configuration..."
cat <<EOF | tee /etc/haproxy/haproxy.cfg > /dev/null
global
    log /dev/log local0
    user haproxy
    group haproxy
    daemon
    # ปรับให้รองรับงานหนักสำหรับ S3
    maxconn 100000
    stats socket /var/lib/haproxy/stats expose-fd listeners level admin

defaults
    log global
    mode http
    option httplog
    timeout connect 5s
    timeout client 50s
    timeout server 50s
    maxconn 50000

frontend s3_frontend
    bind *:80
    # เพิ่มส่วนนี้เพื่อรอรับ Ceph RGW ในอนาคต
    # default_backend rgw_back

frontend stats
    bind *:8404
    stats enable
    stats uri /stats
    stats refresh 10s
    stats admin if LOCALHOST
    http-request use-service prometheus-exporter if { path /metrics }
EOF

echo "🔄 Restarting and Enabling Service..."
systemctl daemon-reload
systemctl enable --now haproxy
systemctl restart haproxy

echo ""
echo "========================================================"
echo "🎯 HAProxy ${HAPROXY_VER} Installation Complete!"
echo "========================================================"
systemctl status haproxy --no-pager
echo "--------------------------------------------------------"
echo "📊 Stats Page: http://$(hostname -I | awk '{print $1}'):8404/stats"
echo "========================================================"
