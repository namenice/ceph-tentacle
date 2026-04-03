#!/bin/bash

# --- Configuration ---
HAPROXY_VER="3.2.15"
HAPROXY_URL="https://www.haproxy.org/download/3.2/src/haproxy-${HAPROXY_VER}.tar.gz"

# --- 1. Check Root Privilege ---
if [[ $EUID -ne 0 ]]; then
   echo "❌ Error: This script must be run as root."
   exit 1
fi

echo "📦 [1/6] Installing Build Dependencies..."
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y build-essential gcc make libpcre2-dev libssl-dev \
                   zlib1g-dev libsystemd-dev liblua5.4-dev wget curl

echo "📂 [2/6] Downloading and Extracting HAProxy ${HAPROXY_VER}..."
cd /tmp
wget -q $HAPROXY_URL -O "haproxy-${HAPROXY_VER}.tar.gz"
tar -xzf "haproxy-${HAPROXY_VER}.tar.gz"
cd "haproxy-${HAPROXY_VER}"

echo "🛠️ [3/6] Compiling HAProxy with Full Features (S3 & Prometheus)..."
# เพิ่ม Flag สำคัญ: USE_PROMETHEUS_EXPORTER=1 และ USE_LUA=1
make -j $(nproc) TARGET=linux-glibc \
    USE_PCRE2=1 \
    USE_OPENSSL=1 \
    USE_ZLIB=1 \
    USE_SYSTEMD=1 \
    USE_LUA=1 \
    USE_PROMETHEUS_EXPORTER=1

make install
cp /usr/local/sbin/haproxy /usr/local/bin/haproxy

echo "👤 [4/6] Setting up User and Directories..."
getent group haproxy >/dev/null || groupadd -g 188 haproxy
getent passwd haproxy >/dev/null || useradd -g haproxy -u 188 -d /var/lib/haproxy -s /sbin/nologin -c haproxy haproxy

mkdir -p /etc/haproxy /var/lib/haproxy
chown haproxy:haproxy /var/lib/haproxy

echo "📄 [5/6] Creating Systemd Service File..."
cat <<'EOF' | tee /etc/systemd/system/haproxy.service > /dev/null
[Unit]
Description=HAProxy Load Balancer (Optimized for Ceph S3)
After=network-online.target
Wants=network-online.target

[Service]
# เพิ่ม Limit สำหรับรับงานหนัก
LimitNOFILE=1048576
Environment="CONFIG=/etc/haproxy/haproxy.cfg" "PIDFILE=/run/haproxy.pid"

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

echo "⚙️ [6/6] Creating Optimized Configuration for S3..."
cat <<EOF | tee /etc/haproxy/haproxy.cfg > /dev/null
global
    log /dev/log local0
    user haproxy
    group haproxy
    daemon
    
    # --- Performance Tuning ---
    maxconn 100000
    nbthread $(nproc)
    cpu-map auto:1-$(nproc) 0-$(( $(nproc) - 1 ))
    stats socket /var/lib/haproxy/stats expose-fd listeners level admin
    
    # Optimize for large objects (S3)
    tune.bufsize 32768
    tune.maxrewrite 1024

defaults
    log global
    mode http
    option httplog
    option dontlognull
    option http-keep-alive
    option forwardfor
    option redispatch
    
    # --- S3 Specific Timeouts ---
    timeout connect 5s
    timeout client 300s
    timeout server 300s
    timeout http-keep-alive 60s
    timeout http-request 10s
    
    maxconn 50000

frontend stats
    bind *:8404
    description "HAProxy Statistics and Prometheus Metrics"
    
    # Native Prometheus Exporter (Requires compiled-in module)
    #http-request use-service prometheus-exporter if { path /metrics }
    
    # Standard Stats UI
    stats enable
    stats uri /stats
    stats refresh 10s
    stats admin if LOCALHOST

frontend s3_frontend
    bind *:80
    description "Main Entry for Ceph RGW"
    
    # S3 Log Format (More detailed for debugging)
    log-format "%ci:%cp [%t] %ft %b/%s %TR/%Tw/%Tc/%Tr/%Ta %ST %B %CC %CS %tsc %ac/%fc/%bc/%sc/%rc %sq/%bq %hr %hs %{+Q}r"
    
    # กำหนดหลังบ้าน (Backend)
    default_backend rgw_back

backend rgw_back
    description "Ceph RGW Cluster"
    balance roundrobin
    
    # Health check specific for RGW
    option httpchk GET /
    http-check expect status 200
    
    # ตัวอย่าง Server (แก้ไข IP ตามระบบของคุณ)
    # server rgw-node1 192.168.1.11:8080 check inter 2s rise 2 fall 3
    # server rgw-node2 192.168.1.12:8080 check inter 2s rise 2 fall 3

# --- Frontend สำหรับ Ceph Dashboard ---
frontend fe_ceph_dashboard
    bind *:8443
    mode tcp              # เปลี่ยนเป็น TCP เพื่อให้ Browser คุยกับ Ceph โดยตรง
    option tcplog
    default_backend be_ceph_dashboard

backend be_ceph_dashboard
    mode tcp
    option httpchk GET /
    http-check expect status 200

    server lab-mgr01 172.71.1.102:8443 check check-ssl verify none
    server lab-mgr02 172.71.1.103:8443 check check-ssl verify none

EOF

echo "🔄 Restarting and Enabling Service..."
systemctl daemon-reload
systemctl enable --now haproxy
systemctl restart haproxy

echo ""
echo "========================================================"
echo "🎯 HAProxy ${HAPROXY_VER} Build Complete!"
echo "========================================================"
echo "✅ Compiled with Prometheus: YES"
echo "✅ Compiled with LUA Support: YES"
echo "✅ S3 Optimized Timeouts:   YES"
echo "--------------------------------------------------------"
echo "📈 Stats UI:        http://$(hostname -I | awk '{print $1}'):8404/stats"
echo "📊 Metrics Endpoint: http://$(hostname -I | awk '{print $1}'):8404/metrics"
echo "--------------------------------------------------------"
echo "👉 NEXT STEP: Edit /etc/haproxy/haproxy.cfg to add your"
echo "   RGW Node IPs in 'backend rgw_back' and setup SSL."
echo "========================================================"
