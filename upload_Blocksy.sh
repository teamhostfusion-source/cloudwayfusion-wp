#!/bin/bash

# --- 1. ตั้งค่า Path ของไฟล์ .zip ในเครื่อง ---
PLUGIN_ZIP_PATH=""
PLUGIN_SLUG=""

# --- 2. ตั้งค่าระบบ ---
BASE_DIR="$HOME/applications"
LOG_FILE="$HOME/update_blocksy_pro.log"

> "$LOG_FILE"
echo "------ เริ่มกระบวนการอัปเดต (ติดตั้งทับ) ปลั๊กอิน $PLUGIN_SLUG [$(date)] ------" | tee -a "$LOG_FILE"

# ตรวจสอบไฟล์ Zip
if [ ! -f "$PLUGIN_ZIP_PATH" ]; then
    echo "Error: ไม่พบไฟล์ .zip ที่ $PLUGIN_ZIP_PATH" | tee -a "$LOG_FILE"
    exit 1
fi

# กรองหาเว็บ
ALL_SITES_LIST=$(find -L "$BASE_DIR" -maxdepth 3 -name "wp-config.php" | grep -vEi "backup|old|archive|trash|staging|/\.")
TOTAL_SITES=$(echo "$ALL_SITES_LIST" | grep -c "wp-config.php")

if [ "$TOTAL_SITES" -eq 0 ]; then
    echo "Error: ไม่พบการติดตั้ง WordPress"
    exit 1
fi

CURRENT_INDEX=0

while read -r config_path; do
    ((CURRENT_INDEX++))
    SITE_PATH=$(dirname "$config_path")
    
    (
        cd "$SITE_PATH" || exit 1
        DOMAIN=$(wp option get home --allow-root 2>/dev/null || echo "Unknown Domain")
        
        echo "------------------------------------------------" | tee -a "$LOG_FILE"
        echo "[$CURRENT_INDEX/$TOTAL_SITES] เว็บ: $DOMAIN" | tee -a "$LOG_FILE"

        # เช็คว่ามีปลั๊กอินอยู่แล้ว (ตามเงื่อนไขของคุณ)
        if wp plugin is-installed "$PLUGIN_SLUG" --allow-root 2>/dev/null; then
            echo "    [ACTION] พบปลั๊กอินเดิม กำลังแตกไฟล์ Zip ติดตั้งทับ..." | tee -a "$LOG_FILE"
            
            # คำสั่งติดตั้งทับ (--force คือตัวจัดการให้ลงทับไฟล์เดิม)
            wp plugin install "$PLUGIN_ZIP_PATH" --force --activate --allow-root >/dev/null 2>&1
            
            # ป้องกันปัญหาเรื่องสิทธิ์ไฟล์ (เปลี่ยนกลับเป็น www-data)
            chown -R www-data:www-data "$SITE_PATH/wp-content/plugins/$PLUGIN_SLUG"
            
            echo "    [CLEANUP] เคลียร์ Cache และฐานข้อมูล..." | tee -a "$LOG_FILE"
            
            # ลบ Option แจ้งเตือนของ Blocksy
            wp option list --search="*blocksy*" --field=option_name --allow-root 2>/dev/null | grep -i "notice\|update\|version" | xargs -I {} wp option delete {} --allow-root >/dev/null 2>&1
            wp transient delete --all --allow-root >/dev/null 2>&1
            wp cache flush --allow-root >/dev/null 2>&1
            
            # รองรับ Cache Plugins
            wp plugin is-active litespeed-cache --allow-root 2>/dev/null && wp litespeed-purge all --allow-root >/dev/null 2>&1
            wp plugin is-active wp-rocket --allow-root 2>/dev/null && wp rocket clean --allow-root >/dev/null 2>&1

            echo "    [OK] ติดตั้งทับเรียบร้อย!" | tee -a "$LOG_FILE"
        else
            echo "    [SKIP] ไม่พบปลั๊กอิน $PLUGIN_SLUG ข้ามการทำงาน" | tee -a "$LOG_FILE"
        fi

    )
done <<< "$ALL_SITES_LIST"

echo "------------------------------------------------" | tee -a "$LOG_FILE"
echo "ทำงานเสร็จสิ้น! เช็คผลลัพธ์ได้ที่: $LOG_FILE"
