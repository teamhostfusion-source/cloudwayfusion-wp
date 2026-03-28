#!/bin/bash

BASE_DIR="$HOME/applications"
LOG_FILE="$HOME/update_blocksy_final.log"

> "$LOG_FILE"
echo "------ Check & Update Blocksy ------" | tee -a "$LOG_FILE"

# ค้นหาไฟล์ wp-config.php โดย 'กรอง' โฟลเดอร์ backup, old, staging, trash ออกไป
ALL_SITES_LIST=$(find -L "$BASE_DIR" -name "wp-config.php" | grep -vEi "backup|old|archive|trash|staging|/\.")
TOTAL_SITES=$(echo "$ALL_SITES_LIST" | grep -c "wp-config.php")

if [ "$TOTAL_SITES" -eq 0 ]; then
    echo "Error: ไม่พบการติดตั้ง WordPress (หรือถูกกรองออกหมด) ใน $BASE_DIR" | tee -a "$LOG_FILE"
    exit 1
fi

echo "พบ WordPress ที่น่าจะใช้งานจริงทั้งหมด $TOTAL_SITES เว็บ เริ่มทำการวนลูป..." | tee -a "$LOG_FILE"

CURRENT_INDEX=0

while read -r config_path; do
    [ -z "$config_path" ] && continue
    
    ((CURRENT_INDEX++))
    SITE_PATH=$(dirname "$config_path")
    
    (
        cd "$SITE_PATH" || exit 1
        
        # ดึงชื่อโดเมน
        DOMAIN=$(wp option get home --allow-root 2>/dev/null || echo "Unknown Domain")
        echo "------------------------------------------------" | tee -a "$LOG_FILE"
        echo "[$CURRENT_INDEX/$TOTAL_SITES] ตรวจสอบเว็บ: $DOMAIN" | tee -a "$LOG_FILE"
        echo "Path: $SITE_PATH" >> "$LOG_FILE" # แอบเก็บ Path ลง Log ด้วยเพื่อความชัวร์

        # 1. เช็คและล้าง Cache อัปเดตของ WordPress ก่อน 
        wp transient delete update_themes update_plugins --allow-root >/dev/null 2>&1
        
        # 2. ตรวจสอบและอัปเดต Blocksy Theme
        if wp theme is-installed blocksy --allow-root 2>/dev/null; then
            CURRENT_VER=$(wp theme get blocksy --field=version --allow-root 2>/dev/null)
            echo "    [CHECK] พบธีม Blocksy (เวอร์ชันปัจจุบัน: $CURRENT_VER)" | tee -a "$LOG_FILE"
            
            # ใช้งาน wp theme update ตามมาตรฐาน
            UPDATE_MSG=$(wp theme update blocksy --allow-root 2>&1)
            
            if echo "$UPDATE_MSG" | grep -q "Success"; then
                NEW_VER=$(wp theme get blocksy --field=version --allow-root 2>/dev/null)
                echo "    [SUCCESS] อัปเดต Blocksy เป็นเวอร์ชัน $NEW_VER เรียบร้อย!" | tee -a "$LOG_FILE"
            elif echo "$UPDATE_MSG" | grep -q "already at the latest version"; then
                echo "    [OK] Theme เป็นเวอร์ชันล่าสุดอยู่แล้ว (Up-to-date!)" | tee -a "$LOG_FILE"
            else
                echo "    [WARN] พบปัญหา: $UPDATE_MSG" | tee -a "$LOG_FILE"
                echo "    [RETRY] บังคับติดตั้งทับ (Force Install)..." | tee -a "$LOG_FILE"
                wp theme install blocksy --force --allow-root >/dev/null 2>&1
            fi
        else
            echo "    [SKIP] ไม่พบธีม Blocksy" | tee -a "$LOG_FILE"
        fi

        # 3. ตรวจสอบและอัปเดตปลั๊กอิน Blocksy Companion
        if wp plugin is-installed blocksy-companion --allow-root 2>/dev/null; then
            echo "    [CHECK] กำลังอัปเดต Blocksy Companion..." | tee -a "$LOG_FILE"
            wp plugin update blocksy-companion --allow-root >/dev/null 2>&1
        fi

        if wp plugin is-installed blocksy-companion-pro --allow-root 2>/dev/null; then
            echo "    [CHECK] กำลังอัปเดต Blocksy Companion Pro..." | tee -a "$LOG_FILE"
            wp plugin update blocksy-companion-pro --allow-root >/dev/null 2>&1
        fi

        # 4. ล้าง Cache ท้ายสุด เพื่อให้หน้า Dashboard รีเฟรชสถานะเป็นสีเขียวทันที
        echo "    [CLEANUP] กำลังเคลียร์ฐานข้อมูลและป้ายแจ้งเตือน..." | tee -a "$LOG_FILE"
        wp transient delete --all --allow-root >/dev/null 2>&1
        wp cache flush --allow-root >/dev/null 2>&1
        wp varnish purge --allow-root >/dev/null 2>&1
        
        echo "    [OK] เสร็จสิ้น" | tee -a "$LOG_FILE"
    )

done <<< "$ALL_SITES_LIST"

echo "------------------------------------------------" | tee -a "$LOG_FILE"
echo "การดำเนินการเสร็จสมบูรณ์! ตรวจสอบประวัติได้ที่: $LOG_FILE"
