#!/bin/bash

BASE_DIR="$HOME/applications"
LOG_FILE="$HOME/update_blocksy_action.log"

# กำหนดลิ้งก์สำหรับดาวน์โหลดไฟล์ ZIP (ต้องเป็น Direct Link ที่โหลดไฟล์ได้ทันทีโดยไม่ต้อง Login)
DOWNLOAD_URL="https://github.com/teamhostfusion-source/cloudwayfusion-wp/raw/main/blocksy-companion-pro.zip" 

# ชื่อไฟล์ปลายทางที่จะเซฟไว้บนเซิร์ฟเวอร์
PREMIUM_ZIP_PATH="$HOME/blocksy-companion-pro-downloaded.zip"

> "$LOG_FILE"
echo "------ เริ่มกระบวนการ อัปเดต Blocksy (โหมดดาวน์โหลด & ติดตั้งทับ) ------" | tee -a "$LOG_FILE"

# ---------------------------------------------------------
# ขั้นตอนที่ 0: ดาวน์โหลดไฟล์อัปเดต
# ---------------------------------------------------------
echo "[ACTION] กำลังดาวน์โหลดไฟล์อัปเดตจากลิ้งก์..." | tee -a "$LOG_FILE"
curl -L -o "$PREMIUM_ZIP_PATH" "$DOWNLOAD_URL" >/dev/null 2>&1

# ตรวจสอบว่ามีไฟล์อยู่จริง และเป็นไฟล์ ZIP ที่สมบูรณ์หรือไม่
if [ ! -s "$PREMIUM_ZIP_PATH" ] || ! unzip -t "$PREMIUM_ZIP_PATH" >/dev/null 2>&1; then
    echo "[ERROR] ❌ ดาวน์โหลดไม่สำเร็จ หรือไฟล์ที่ได้ไม่ใช่ไฟล์ ZIP ที่สมบูรณ์!" | tee -a "$LOG_FILE"
    echo "กรุณาตรวจสอบลิ้งก์ DOWNLOAD_URL ว่าสามารถโหลดได้โดยตรงและไม่ติดหน้า Login" | tee -a "$LOG_FILE"
    rm -f "$PREMIUM_ZIP_PATH" # ลบไฟล์ที่เสียทิ้ง
    exit 1
else
    echo "[INFO] ✅ ดาวน์โหลดและตรวจสอบไฟล์ ZIP สำเร็จ!" | tee -a "$LOG_FILE"
fi

# กรองโฟลเดอร์ Backup/Staging ทิ้ง เอาเฉพาะเว็บจริง
ALL_SITES_LIST=$(find -L "$BASE_DIR" -name "wp-config.php" | grep -vEi "backup|old|archive|trash|staging|/\.")
TOTAL_SITES=$(echo "$ALL_SITES_LIST" | grep -c "wp-config.php")

if [ "$TOTAL_SITES" -eq 0 ]; then
    echo "Error: ไม่พบการติดตั้ง WordPress ที่ใช้งานจริง"
    exit 1
fi

CURRENT_INDEX=0

while read -r config_path; do
    [ -z "$config_path" ] && continue
    
    ((CURRENT_INDEX++))
    SITE_PATH=$(dirname "$config_path")
    
    (
        cd "$SITE_PATH" || exit 1
        DOMAIN=$(wp option get home --allow-root 2>/dev/null || echo "Unknown Domain")
        echo "------------------------------------------------" | tee -a "$LOG_FILE"
        echo "[$CURRENT_INDEX/$TOTAL_SITES] เว็บ: $DOMAIN" | tee -a "$LOG_FILE"

        # ---------------------------------------------------------
        # 1. จำลองการกดปุ่ม: สั่งอัปเดตไฟล์ธีมและปลั๊กอินฟรี
        # ---------------------------------------------------------
        if wp theme is-installed blocksy --allow-root 2>/dev/null; then
            echo "    [ACTION] กำลังสั่งอัปเดตธีม Blocksy..." | tee -a "$LOG_FILE"
            wp theme update blocksy --allow-root >/dev/null 2>&1
            wp theme install blocksy --force --allow-root >/dev/null 2>&1
        else
            echo "    [SKIP] ไม่พบธีม Blocksy" | tee -a "$LOG_FILE"
            exit 0
        fi

        if wp plugin is-installed blocksy-companion --allow-root 2>/dev/null; then
            wp plugin update blocksy-companion --allow-root >/dev/null 2>&1
        fi
        
        # ---------------------------------------------------------
        # 2. ท่าไม้ตาย: ยัดไฟล์ ZIP ทับ Blocksy Companion (Premium)
        # ---------------------------------------------------------
        if wp plugin is-installed blocksy-companion-pro --allow-root 2>/dev/null; then
            OLD_VERSION=$(wp plugin get blocksy-companion-pro --field=version --allow-root 2>/dev/null)
            echo "    [ACTION] พบ Blocksy Pro (v.$OLD_VERSION) กำลังติดตั้งทับจากไฟล์ที่ดาวน์โหลดมา..." | tee -a "$LOG_FILE"
            
            # สั่งติดตั้งจากไฟล์ ZIP และใช้ --force เพื่อให้มันเขียนทับโฟลเดอร์เดิม
            wp plugin install "$PREMIUM_ZIP_PATH" --force --allow-root >/dev/null 2>&1
            
            NEW_VERSION=$(wp plugin get blocksy-companion-pro --field=version --allow-root 2>/dev/null)
            
            if [ "$OLD_VERSION" == "$NEW_VERSION" ]; then
                echo "    [INFO] ยัดไฟล์สำเร็จ แต่น่าจะเป็นเวอร์ชันเดิมอยู่แล้ว (v.$NEW_VERSION)" | tee -a "$LOG_FILE"
            else
                echo "    [SUCCESS] 🔥 อัปเดต Blocksy Pro สำเร็จ! (เปลี่ยนเป็น v.$NEW_VERSION)" | tee -a "$LOG_FILE"
            fi
        fi

        # ---------------------------------------------------------
        # 3. จำลองการกดปุ่ม: เตะป้ายแจ้งเตือนทิ้งจากฐานข้อมูล
        # ---------------------------------------------------------
        echo "    [CLEANUP] เคลียร์สถานะป้ายแจ้งเตือนในฐานข้อมูล..." | tee -a "$LOG_FILE"
        
        wp option list --search="*blocksy*" --field=option_name --allow-root 2>/dev/null | grep -i "notice\|update\|version" | xargs -I {} wp option delete {} --allow-root >/dev/null 2>&1
        wp option list --search="*ct_*" --field=option_name --allow-root 2>/dev/null | grep -i "notice\|update" | xargs -I {} wp option delete {} --allow-root >/dev/null 2>&1

        wp transient delete --all --allow-root >/dev/null 2>&1

        # ---------------------------------------------------------
        # 4. ล้าง Cache ทั้งหน้าบ้านและหลังบ้าน
        # ---------------------------------------------------------
        wp cache flush --allow-root >/dev/null 2>&1
        
        if wp plugin is-active wp-rocket --allow-root 2>/dev/null; then wp rocket clean --allow-root >/dev/null 2>&1; fi
        if wp plugin is-active litespeed-cache --allow-root 2>/dev/null; then wp litespeed-purge all --allow-root >/dev/null 2>&1; fi
        if wp plugin is-active sg-cachepress --allow-root 2>/dev/null; then wp sgpurge --allow-root >/dev/null 2>&1; fi

        echo "    [OK] อัปเดตและเคลียร์ปุ่มเสร็จสิ้นเรียบร้อย!" | tee -a "$LOG_FILE"
    )

done <<< "$ALL_SITES_LIST"

echo "------------------------------------------------" | tee -a "$LOG_FILE"
echo "การอัปเดตเสร็จสมบูรณ์! ลบไฟล์ ZIP ที่ดาวน์โหลดมาเพื่อประหยัดพื้นที่..."
rm -f "$PREMIUM_ZIP_PATH"
echo "เช็ค Log ได้ที่: $LOG_FILE"
