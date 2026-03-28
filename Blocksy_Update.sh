#!/bin/bash

BASE_DIR="$HOME/applications"
LOG_FILE="$HOME/update_blocksy_only.log"

> "$LOG_FILE"
echo "------ บังคับอัปเดต Blocksy เริ่มต้นเวลา $(date) ------" | tee -a "$LOG_FILE"

# ค้นหาทุกเว็บที่มีไฟล์ wp-config.php
ALL_SITES_LIST=$(find -L "$BASE_DIR" -name "wp-config.php" ! -path "*/.*")
TOTAL_SITES=$(echo "$ALL_SITES_LIST" | grep -c "wp-config.php")

if [ "$TOTAL_SITES" -eq 0 ]; then
    echo "Error: ไม่พบการติดตั้ง WordPress ใน $BASE_DIR" | tee -a "$LOG_FILE"
    exit 1
fi

echo "พบ WordPress ทั้งหมด $TOTAL_SITES เว็บ เริ่มทำการวนลูป..." | tee -a "$LOG_FILE"

CURRENT_INDEX=0

while read -r config_path; do
    [ -z "$config_path" ] && continue
    
    ((CURRENT_INDEX++))
    SITE_PATH=$(dirname "$config_path")
    DISPLAY_NAME=$(echo "$SITE_PATH" | sed "s|$BASE_DIR/||")
    
    (
        cd "$SITE_PATH" || { exit 1; }
        
        # ดึงชื่อโดเมนมาแสดงผล
        DOMAIN=$(wp option get home --allow-root 2>/dev/null || echo "Unknown Domain")
        echo "------------------------------------------------" | tee -a "$LOG_FILE"
        echo "[$CURRENT_INDEX/$TOTAL_SITES] เว็บ: $DOMAIN ($DISPLAY_NAME)" | tee -a "$LOG_FILE"

        # 1. ล้าง Cache การตรวจสอบอัปเดตของ WordPress ทิ้งก่อน
        wp transient delete update_themes update_plugins --allow-root >/dev/null 2>&1

        # 2. จัดการ Blocksy Theme (ติดตั้งทับด้วย --force)
        if wp theme is-installed blocksy --allow-root 2>/dev/null; then
            echo "    [UPDATE] กำลังบังคับอัปเดต Blocksy Theme..." | tee -a "$LOG_FILE"
            wp theme install blocksy --force --allow-root >> "$LOG_FILE" 2>&1
        else
            echo "    [SKIP] ข้าม: ไม่พบธีม Blocksy" | tee -a "$LOG_FILE"
        fi

        # 3. จัดการ Blocksy Companion (ตัวปล่อยป้ายแจ้งเตือน)
        if wp plugin is-installed blocksy-companion --allow-root 2>/dev/null; then
            echo "    [UPDATE] กำลังบังคับอัปเดต Blocksy Companion..." | tee -a "$LOG_FILE"
            wp plugin install blocksy-companion --force --allow-root >> "$LOG_FILE" 2>&1
        fi
        
        # 4. จัดการ Blocksy Companion Pro (ถ้ามี)
        if wp plugin is-installed blocksy-companion-pro --allow-root 2>/dev/null; then
            echo "    [UPDATE] กำลังอัปเดต Blocksy Companion Pro..." | tee -a "$LOG_FILE"
            # ตัว Pro ไม่มีใน repository กลาง ใช้ update ปกติ
            wp plugin update blocksy-companion-pro --allow-root >> "$LOG_FILE" 2>&1
        fi

        # 5. ล้าง Transients ทั้งหมดและล้าง Cache Server เพื่อลบป้ายแจ้งเตือนที่ค้างอยู่
        echo "    [CLEANUP] กำลังล้าง Cache และป้ายแจ้งเตือน..." | tee -a "$LOG_FILE"
        wp transient delete --all --allow-root >/dev/null 2>&1
        wp cache flush --allow-root &>/dev/null
        wp varnish purge --allow-root &>/dev/null 2>&1 
        
        echo "    [OK] เสร็จสิ้นสำหรับเว็บนี้" | tee -a "$LOG_FILE"
        exit 0
    )

done <<< "$ALL_SITES_LIST"

echo "------------------------------------------------" | tee -a "$LOG_FILE"
echo "การวนลูปอัปเดตเสร็จสมบูรณ์! เช็ครายละเอียดได้ที่: $LOG_FILE"
