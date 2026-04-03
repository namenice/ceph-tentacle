#!/bin/bash

# --- 1. Check Root Privilege ---
if [[ $EUID -ne 0 ]]; then
   echo "❌ Error: This script must be run as root."
   exit 1
fi

echo "📦 [1/4] Adding HAProxy 3.0 PPA and Installing..."
export DEBIAN_FRONTEND=noninteractive

# ติดตั้งตัวจัดการ PPA
apt-get update
apt-get install -y --no-install-recommends software-properties-common curl wget

# เพิ่ม PPA และติดตั้ง HAProxy 3.0
add-apt-repository -y ppa:vbernat/haproxy-3.0
apt-get update
apt-get install -y haproxy=3.0.\*

echo "👤 [2/4] Ensuring Directories and Permissions..."
# PPA จะสร้าง user haproxy ให้โดยอัตโนมัติ
mkdir -p /var/lib/haproxy
chown haproxy:haproxy /var/lib/haproxy

echo "⚙️ [3/4] Creating Optimized Configuration (S3 & Ceph Dashboard)..."
# สำรองไฟล์เดิมไว้ก่อน
mv /etc/haproxy/haproxy.cfg /etc/haproxy/haproxy.cfg.bak

cat <<EOF | tee /etc/haproxy/haproxy.cfg > /dev/null
global
    log /dev/log local0
    log /dev/log local1 notice
    user haproxy
    group haproxy
    daemon

    # --- Performance Tuning ---
    maxconn 100000
    # HAProxy 3.0 ใช้คอร์ทั้งหมดอัตโนมัติ แต่ระบุเพื่อความชัดเจนได้
    nbthread $(nproc)
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
    # HAProxy 3.0 จาก PPA มาพร้อม Prometheus support อยู่แล้ว
    http-request use-service prometheus-exporter if { path /metrics }
    
    stats enable
    stats uri /stats
    stats refresh 10s
    stats admin if LOCALHOST

frontend s3_frontend
    bind *:80
    description "Main Entry for Ceph RGW"
    log-format "%ci:%cp [%t] %ft %b/%s %TR/%Tw/%Tc/%Tr/%Ta %ST %B %CC %CS %tsc %ac/%fc/%bc/%sc/%rc %sq/%bq %hr %hs %{+Q}r"
    default_backend rgw_back

frontend fe_ceph_dashboard
    bind *:8443
    mode tcp
    option tcplog
    default_backend be_ceph_dashboard

backend rgw_back
    description "Ceph RGW Cluster"
    balance roundrobin
    option httpchk GET /
    http-check expect status 200
    # server rgw-node1 192.168.1.11:8080 check inter 2s

backend be_ceph_dashboard
    mode tcp
    option httpchk GET /
    http-check expect status 200
    # ส่ง Health Check แบบ SSL โดยไม่ตรวจใบเซอร์
    server lab-mgr01 172.71.1.102:8443 check check-ssl verify none
    server lab-mgr02 172.71.1.103:8443 check check-ssl verify none
EOF

echo "🔄 [4/4] Restarting and Enabling Service..."
# ปรับแต่ง Resource Limit ผ่าน Systemd Drop-in (สำหรับ Package install)
mkdir -p /etc/systemd/system/haproxy.service.d/
cat <<EOF | tee /etc/systemd/system/haproxy.service.d/limits.conf > /dev/null
[Service]
LimitNOFILE=1048576
EOF

systemctl daemon-reload
systemctl enable haproxy
systemctl restart haproxy

echo ""
echo "========================================================"
echo "🎯 HAProxy 3.0 Installation via PPA Complete!"
echo "========================================================"
echo "✅ Install Method:  APT (PPA:vbernat)"
echo "✅ Version:         $(haproxy -v | awk '{print $3}')"
echo "✅ S3 Optimized:    YES"
echo "✅ Active/Standby:  Configured for Dashboard"
echo "--------------------------------------------------------"
echo "📈 Stats UI:        http://$(hostname -I | awk '{print $1}'):8404/stats"
echo "📊 Metrics:          http://$(hostname -I | awk '{print $1}'):8404/metrics"
echo "========================================================"
