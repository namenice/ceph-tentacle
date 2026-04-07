#!/bin/bash

# 1. กำหนดตัวแปร (ปรับเปลี่ยนได้ตามใจชอบ)
DEB_URL="https://dl.min.io/server/minio/release/linux-amd64/archive/minio_20241107005220.0.0_amd64.deb"
DATA_DIR="/mnt/minio_data"
MINIO_ROOT_USER="minioadmin"
MINIO_ROOT_PASSWORD="minioadminpassword"

echo "--- 📦 กำลังดาวน์โหลดและติดตั้ง MinIO (.deb) ---"

# 2. ดาวน์โหลดไฟล์ .deb
wget $DEB_URL -O minio.deb

# 3. ติดตั้งโดยใช้ dpkg
sudo dpkg -i minio.deb

# 4. สร้าง Directory สำหรับเก็บข้อมูล (ถ้ายังไม่มี)
sudo mkdir -p $DATA_DIR

# โดยปกติไฟล์ .deb ของ MinIO จะสร้าง User 'minio-user' มาให้แล้ว
# เราจะทำการมอบสิทธิ์ขาดใน Folder ข้อมูลให้ User นี้
sudo chown minio-user:minio-user $DATA_DIR

# 5. สร้างไฟล์คอนฟิก /etc/default/minio
# ตัวเลือก --console-address :9001 ช่วยให้เราเข้าหน้าเว็บจัดการได้ง่ายๆ
cat <<EOF | sudo tee /etc/default/minio
MINIO_VOLUMES="$DATA_DIR"
MINIO_OPTS="--address :9000 --console-address :9001"
MINIO_ROOT_USER="$MINIO_ROOT_USER"
MINIO_ROOT_PASSWORD="$MINIO_ROOT_PASSWORD"
EOF

# 6. ตั้งค่าให้ Service เริ่มทำงานอัตโนมัติ
sudo systemctl enable minio
sudo systemctl restart minio

echo "--- ✅ ติดตั้งเสร็จเรียบร้อย! ---"
echo "สถานะบริการ:"
sudo systemctl status minio --no-pager | grep Active

echo ""
echo "🔗 Access Details:"
echo "API: http://$(hostname -I | awk '{print $1}'):9000"
echo "Console (Web GUI): http://$(hostname -I | awk '{print $1}'):9001"
echo "Username: $MINIO_ROOT_USER"
echo "Password: $MINIO_ROOT_PASSWORD"
echo "------------------------------------------------"
