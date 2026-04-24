#!/bin/bash

# ========================================================
# ⚙️ CONFIGURATION ENVIRONMENT (แก้ไขที่นี่)
# ========================================================
SOURCE_DIR="/root/data/"
TARGET_IP="172.71.7.139"
TARGET_DIR="/root/backup/"
SSH_PORT="22"
REMOTE_USER="root"

CONFIG_PATH="/etc/lsyncd/lsyncd.conf.lua"
LOG_DIR="/var/log/lsyncd"
# ========================================================

# --- 1. Check Root Privilege ---
if [[ $EUID -ne 0 ]]; then
   echo "❌ Error: This script must be run as root."
   exit 1
fi

echo "🔄 [Start] Lsyncd Deployment with Target Verification..."

# --- 2. Verify SSH Connection (Passwordless) ---
echo "🔍 [Step 1] Verifying SSH connectivity to $TARGET_IP..."
ssh -q -o BatchMode=yes -o ConnectTimeout=5 -p $SSH_PORT $REMOTE_USER@$TARGET_IP exit
if [[ $? -ne 0 ]]; then
    echo "❌ Error: Cannot SSH to $TARGET_IP without password."
    echo "   Please run: ssh-copy-id -p $SSH_PORT $REMOTE_USER@$TARGET_IP"
    exit 1
fi
echo "✅ SSH Connection: OK"

# --- 3. Verify Rsync on Target ---
echo "🔍 [Step 2] Checking rsync on target host..."
ssh -p $SSH_PORT $REMOTE_USER@$TARGET_IP "which rsync && rsync --version | head -n 1" > /dev/null 2>&1
if [[ $? -ne 0 ]]; then
    echo "❌ Error: rsync is not installed on $TARGET_IP."
    echo "   Please run: apt install rsync -y (on target host)"
    exit 1
fi
echo "✅ Target Rsync: Installed"

# --- 4. Install Local Prerequisites ---
echo "📦 [Step 3] Installing local dependencies (lsyncd & rsync)..."
apt update && apt install -y lsyncd rsync

# --- 5. Prepare Directories and Logs ---
echo "📂 [Step 4] Preparing directories and log files..."
mkdir -p /etc/lsyncd
mkdir -p $LOG_DIR
mkdir -p $SOURCE_DIR
touch $LOG_DIR/lsynced.log
touch $LOG_DIR/lsyncd.status
chmod 755 $LOG_DIR

# --- 6. Generate Lsyncd Configuration ---
echo "⚙️ [Step 5] Generating Lsyncd configuration..."
cat <<EOF > $CONFIG_PATH
settings {
    statusFile = "$LOG_DIR/lsyncd.status",
    nodaemon = false,
    statusInterval = 10
}

sync {
    default.rsync,
    source = "$SOURCE_DIR",
    target = "$REMOTE_USER@$TARGET_IP:$TARGET_DIR",

    rsync = {
        archive = true,
        compress = true,
        _extra = {
            "-e", "ssh -p $SSH_PORT",
            "--out-format=lsyncd[%p]: %f (%l bytes)",
            "--log-file=$LOG_DIR/lsynced.log",
            "--log-file-format=%t %f %b",
        }
    }
}
EOF

# --- 7. Enable and Start Service ---
echo "🚀 [Step 6] Enabling and starting Lsyncd service..."
systemctl enable lsyncd
systemctl restart lsyncd

echo ""
echo "========================================================"
echo "🎯 LSYNCD DEPLOYMENT COMPLETED!"
echo "========================================================"
echo "✅ SSH & Target Sync : Verified"
echo "✅ Lsyncd Status     : $(systemctl is-active lsyncd)"
echo "✅ Config File       : $CONFIG_PATH"
echo "✅ Log File          : $LOG_DIR/lsynced.log"
echo "--------------------------------------------------------"
echo "📊 Monitoring Command:"
echo "   tail -f $LOG_DIR/lsynced.log"
echo "========================================================"
