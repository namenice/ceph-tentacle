#!/bin/bash

# 1. กำหนดตัวแปร (ให้ตรงกับที่ติดตั้งไว้)
DATA_DIR="/mnt/minio_data"

echo "--- 🗑️ เริ่มต้นกระบวนการลบ MinIO ---"

# 2. หยุดการทำงานและปิด Service
echo "Stopping MinIO service..."
sudo systemctl stop minio
sudo systemctl disable minio

# 3. ลบแพ็กเกจ MinIO ออกจากระบบ
# purge จะลบทั้งโปรแกรมและไฟล์คอนฟิกที่มากับตัว .deb
echo "Removing MinIO package..."
sudo apt purge minio -y

# 4. ลบไฟล์คอนฟิกที่สร้างเพิ่มขึ้นมาเอง
echo "Cleaning up configuration files..."
sudo rm -f /etc/default/minio
sudo rm -f /etc/systemd/system/minio.service # เผื่อกรณีมีไฟล์ค้างจากวิธี Binary

# 5. ลบไฟล์ .deb ที่อาจค้างอยู่ในเครื่อง
rm -f minio.deb

# 6. รีโหลด Systemd daemon
sudo systemctl daemon-reload

# 7. ถามความสมัครใจในการลบข้อมูล (Data)
echo "------------------------------------------------"
read -p "คุณต้องการลบข้อมูลทั้งหมดใน $DATA_DIR ด้วยหรือไม่? (y/N): " confirm
if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
    sudo rm -rf $DATA_DIR
    echo "✅ ลบ Folder ข้อมูลเรียบร้อยแล้ว"
else
    echo "📂 เก็บ Folder ข้อมูลเอาไว้ที่ $DATA_DIR"
fi

echo "--- ✨ ลบ MinIO ออกจากระบบเรียบร้อยแล้ว! ---"
