#!/bin/bash

# --- 1. Configuration ---
export VAULT_ADDR='http://127.0.0.1:8200'
KEY_FILE="/etc/vault.d/.vault_keys.txt"
POLICY_NAME="rgw-sse-s3"
POLICY_FILE="/etc/vault.d/rgw-sse-s3-policy.hcl"
ROLE_NAME="rgw-role"
TRANSIT_KEY_NAME="s3-key"

# ตรวจสอบสิทธิ์ Root
if [[ $EUID -ne 0 ]]; then
   echo "❌ โปรดรันด้วยสิทธิ์ root (sudo)"
   exit 1
fi

# ตรวจสอบและติดตั้ง jq หากยังไม่มี
if ! command -v jq &> /dev/null; then
    echo "📦 กำลังติดตั้ง jq..."
    apt update && apt install -y jq
fi

# ตรวจสอบว่า Vault Server พร้อมตอบสนองไหม
if ! curl -s --connect-timeout 3 $VAULT_ADDR/v1/sys/health > /dev/null; then
    echo "❌ Error: ไม่สามารถเชื่อมต่อ Vault ได้ที่ $VAULT_ADDR"
    exit 1
fi

echo "🛡️ [1/3] Checking Vault Status with jq..."

# ดึงสถานะทั้งหมดมาเป็น JSON ก้อนเดียวเพื่อลดจำนวนการยิงคำสั่ง
STATUS_JSON=$(vault status -format=json 2>/dev/null)

# ใช้ jq ดึงค่า initialized และ sealed
IS_INIT=$(echo "$STATUS_JSON" | jq -r '.initialized')
IS_SEALED=$(echo "$STATUS_JSON" | jq -r '.sealed')

# 1. จัดการการ Initialize
if [ "$IS_INIT" == "true" ]; then
    echo "⚠️  Vault ถูก Initialize ไปแล้ว ข้ามขั้นตอนนี้..."
else
    echo "🚀 กำลังทำการ Initialize Vault..."
    mkdir -p /etc/vault.d
    INIT_OUT=$(vault operator init -key-shares=5 -key-threshold=3 -format=json)

    # บันทึก Keys ทั้งหมดในรูปแบบ JSON (ปลอดภัยและอ่านง่ายสำหรับ jq)
    echo "$INIT_OUT" | tee $KEY_FILE > /dev/null
    chmod 600 $KEY_FILE
    echo "✅ บันทึก Keys ใหม่ไว้ที่ $KEY_FILE เรียบร้อย"

    # อัปเดตสถานะหลัง Init
    IS_SEALED=true
fi

# 2. จัดการการ Unseal
if [ "$IS_SEALED" == "true" ]; then
    echo "🔓 Vault ปิดอยู่ (Sealed) กำลังทำการ Unseal..."

    # ตรวจสอบว่ามีไฟล์ Key ไหม
    if [ ! -f "$KEY_FILE" ]; then
        echo "❌ Error: ไม่พบไฟล์กุญแจที่ $KEY_FILE"
        exit 1
    fi

    # ดึง Unseal Keys มาใช้ (รองรับทั้งไฟล์แบบ text เดิม และไฟล์แบบ json ใหม่)
    # ในที่นี้ขอดึงจากไฟล์รูปแบบเดิมที่คุณมี หรือถ้าเป็น JSON ก็ใช้ jq ดึงได้
    if grep -q "{" "$KEY_FILE"; then
        # กรณีไฟล์เป็น JSON
        K1=$(cat $KEY_FILE | jq -r '.unseal_keys_b64[0]')
        K2=$(cat $KEY_FILE | jq -r '.unseal_keys_b64[1]')
        K3=$(cat $KEY_FILE | jq -r '.unseal_keys_b64[2]')
        ROOT_TOKEN=$(cat $KEY_FILE | jq -r '.root_token')
    else
        # กรณีไฟล์เป็น Text รูปแบบเดิม
        K1=$(grep "Unseal Key 1" $KEY_FILE | awk '{print $NF}')
        K2=$(grep "Unseal Key 2" $KEY_FILE | awk '{print $NF}')
        K3=$(grep "Unseal Key 3" $KEY_FILE | awk '{print $NF}')
        ROOT_TOKEN=$(grep "Initial Root Token" $KEY_FILE | awk '{print $NF}')
    fi

    vault operator unseal "$K1" > /dev/null
    vault operator unseal "$K2" > /dev/null
    vault operator unseal "$K3" > /dev/null
    echo "✅ Unseal สำเร็จ"
else
    echo "⚠️  Vault เปิดอยู่แล้ว (Unsealed) ข้ามขั้นตอนการไขกุญแจ..."
    ROOT_TOKEN=$(grep "Initial Root Token" $KEY_FILE | awk '{print $NF}')
fi

# --- 3. Login and Configuration ---
echo "🔑 [3/3] Logging in..."
vault login "$ROOT_TOKEN" > /dev/null

echo "⚙️ Configuring Secrets Engine & Policy..."
vault secrets list -format=json | jq -e '."transit/"' >/dev/null || vault secrets enable transit
vault list -format=json transit/keys 2>/dev/null | jq -e ". | contains([\"$TRANSIT_KEY_NAME\"])" >/dev/null || vault write -f transit/keys/$TRANSIT_KEY_NAME

cat <<EOF > $POLICY_FILE
path "transit/keys/*" { capabilities = ["create", "update", "read", "delete", "list"] }
path "transit/datakey/plaintext/*" { capabilities = ["create", "update"] }
path "transit/decrypt/*" { capabilities = ["update"] }
EOF
vault policy write $POLICY_NAME $POLICY_FILE > /dev/null

echo "🔌 Configuring AppRole..."
vault auth list -format=json | jq -e '."approle/"' >/dev/null || vault auth enable approle

vault write auth/approle/role/$ROLE_NAME \
    token_policies="$POLICY_NAME" \
    token_ttl=1h \
    token_max_ttl=4h > /dev/null

# ดึงค่าสุดท้ายออกมาแสดงผล
ROLE_ID=$(vault read -format=json auth/approle/role/$ROLE_NAME/role-id | jq -r '.data.role_id')
SECRET_ID=$(vault write -f -format=json auth/approle/role/$ROLE_NAME/secret-id | jq -r '.data.secret_id')

echo ""
echo "========================================================"
echo "🎯 VAULT READY (JSON-POWERED SETUP)"
echo "========================================================"
echo "👉 ROLE_ID   : $ROLE_ID"
echo "👉 SECRET_ID : $SECRET_ID"
echo "========================================================"
