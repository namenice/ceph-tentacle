#!/bin/bash

# --- 1. Check Root Privilege ---
if [[ $EUID -ne 0 ]]; then
   echo "❌ Error: This script must be run as root."
   exit 1
fi

echo "📦 [1/5] Installing HAProxy 3.0 via PPA..."
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends software-properties-common curl wget
add-apt-repository -y ppa:vbernat/haproxy-3.0
apt-get update
apt-get install -y haproxy=3.0.\*

echo "📂 [2/5] Setting up Modular Directory (conf.d)..."
mkdir -p /etc/haproxy/conf.d
mkdir -p /var/lib/haproxy
chown haproxy:haproxy /var/lib/haproxy

# เก็บไฟล์ Default เดิมของระบบไว้เป็นไฟล์หลัก (Reference)
if [ ! -f /etc/haproxy/haproxy.cfg.orig ]; then
    cp /etc/haproxy/haproxy.cfg /etc/haproxy/haproxy.cfg.orig
    echo "✅ Default config backed up to /etc/haproxy/haproxy.cfg.orig"
fi

echo "⚙️ [3/5] Creating Modular Config Files..."

# --- 00-global.cfg ---
cat <<EOF | tee /etc/haproxy/conf.d/00-global.cfg > /dev/null
global
    log /dev/log local0
    user haproxy
    group haproxy
    daemon
    maxconn 100000
    stats socket /var/lib/haproxy/stats expose-fd listeners level admin
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
    timeout connect 5s
    timeout client 300s
    timeout server 300s
    timeout http-keep-alive 60s
    timeout http-request 10s
    maxconn 50000
EOF

# --- 10-s3-rgw.cfg ---
cat <<EOF | tee /etc/haproxy/conf.d/10-s3-rgw.cfg > /dev/null
frontend fe_rgw
    bind *:80
    description "Main Entry for Ceph RGW"
    log-format "%ci:%cp [%t] %ft %b/%s %TR/%Tw/%Tc/%Tr/%Ta %ST %B %CC %CS %tsc %ac/%fc/%bc/%sc/%rc %sq/%bq %hr %hs %{+Q}r"
    default_backend be_rgw

backend be_rgw
    description "Ceph RGW Cluster"
    balance roundrobin
    option httpchk GET /
    http-check expect status 200
    server rgw-node1 172.71.1.106:80 check inter 2s
EOF

# --- 20-dashboard.cfg ---
cat <<EOF | tee /etc/haproxy/conf.d/20-dashboard.cfg > /dev/null
frontend fe_ceph_dashboard
    bind *:8443
    mode tcp
    option tcplog
    default_backend be_ceph_dashboard

backend be_ceph_dashboard
    mode tcp
    option httpchk GET /
    http-check expect status 200
    # ใช้ Check-SSL เพื่อแยก Active/Standby MGR
    server lab-mgr01 172.71.1.102:8443 check check-ssl verify none
    server lab-mgr02 172.71.1.103:8443 check check-ssl verify none
EOF

# --- 30-metrics.cfg ---
cat <<EOF | tee /etc/haproxy/conf.d/30-metrics.cfg > /dev/null
frontend stats_prometheus
    bind *:8404
    description "HAProxy Monitoring"
    http-request use-service prometheus-exporter if { path /metrics }
    stats enable
    stats uri /stats
    stats refresh 10s
    stats admin if LOCALHOST
EOF

echo "🛠️ [4/5] Modifying Systemd to load conf.d..."
# สร้าง Drop-in file เพื่อแก้ไข ExecStart โดยไม่ต้องยุ่งกับไฟล์หลักของระบบ
mkdir -p /etc/systemd/system/haproxy.service.d/
cat <<EOF | tee /etc/systemd/system/haproxy.service.d/override.conf > /dev/null
[Service]
# ขยาย Limit ไฟล์สำหรับงานหนัก
LimitNOFILE=1048576
# ล้าง ExecStart เดิมและระบุใหม่ให้โหลดไฟล์จาก conf.d
ExecStart=
ExecStart=/usr/sbin/haproxy -Ws -f /etc/haproxy/haproxy.cfg -f /etc/haproxy/conf.d/ -p /run/haproxy.pid
EOF

echo "🔄 [5/5] Restarting HAProxy..."
systemctl daemon-reload
systemctl enable haproxy
systemctl restart haproxy

echo ""
echo "========================================================"
echo "🎯 HAProxy 3.0 Modular Installation Complete!"
echo "========================================================"
echo "📂 Config Directory:  /etc/haproxy/conf.d/"
echo "📄 Global Settings:   00-global.cfg"
echo "📄 S3 RGW Settings:   10-s3-rgw.cfg"
echo "📄 Dashboard:         20-dashboard.cfg"
echo "📄 Metrics/Stats:     30-metrics.cfg"
echo "--------------------------------------------------------"
echo "✅ Default Config kept as reference in /etc/haproxy/haproxy.cfg"
echo "✅ Monitoring: http://$(hostname -I | awk '{print $1}'):8404/stats"
echo "✅ Metrics: http://$(hostname -I | awk '{print $1}'):8404/metrics"
echo "========================================================"
