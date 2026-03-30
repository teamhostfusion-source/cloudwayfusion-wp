#!/bin/bash

# --- 1. ตั้งค่า GitHub URL ---
# นำ Link .zip จาก GitHub มาใส่ตรงนี้ (ถ้าเป็น Private Repo อย่าลืมใส่ Token ตามที่คุยกันไว้นะครับ)
PLUGIN_GITHUB_URL="https://github.com/teamhostfusion-source/cloudwayfusion-wp/blob/main/blocksy-companion-pro.2.1.37.zip"
PLUGIN_SLUG="blocksy-companion-pro"

# --- 2. ตั้งค่าระบบ ---
BASE_DIR="$HOME/applications"
LOG_FILE="$HOME/update_blocksy_pro_github.log"

> "$LOG_FILE"
echo "------ เริ่มกระบวนการอัปเดต $PLUGIN_SLUG จาก GitHub [$(date)] ------" | tee -a "$LOG_FILE"

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

        # เช็คว่ามีปลั๊กอินอยู่แล้วถึงจะทำการอัปเดตทับ
        if wp plugin is-installed "$PLUGIN_SLUG" --allow-root 2>/dev/null; then
            echo "    [ACTION] พบปลั๊กอินเดิม กำลังดาวน์โหลดและติดตั้งทับจาก GitHub..." | tee -a "$LOG_FILE"
            
            # ลบของเก่าออกก่อน (ชัวร์กว่า --force กรณีชื่อโฟลเดอร์จาก GitHub ไม่ตรงกัน)
            wp plugin delete "$PLUGIN_SLUG" --allow-root >/dev/null 2>&1
            
            # ติดตั้งไฟล์ใหม่จาก GitHub
            wp plugin install "$PLUGIN_GITHUB_URL" --activate --allow-root >/dev/null 2>&1
            
            # แก้ไขปัญหาชื่อโฟลเดอร์ GitHub ที่มีขีดต่อท้าย (เช่น -main, -master)
            GITHUB_FOLDER=$(ls wp-content/plugins | grep "^$PLUGIN_SLUG-")
            if [ ! -z "$GITHUB_FOLDER" ]; then
                mv "wp-content/plugins/$GITHUB_FOLDER" "wp-content/plugins/$PLUGIN_SLUG"
                # สั่ง Activate อีกรอบเผื่อโฟลเดอร์เปลี่ยนชื่อแล้ว WordPress หลง
                wp plugin activate "$PLUGIN_SLUG" --allow-root >/dev/null 2>&1
            fi

            # ป้องกันปัญหาเรื่องสิทธิ์ไฟล์
            chown -R www-data:www-data "$SITE_PATH/wp-content/plugins/$PLUGIN_SLUG"
            
            echo "    [CLEANUP] เคลียร์ Cache และฐานข้อมูล..." | tee -a "$LOG_FILE"
            
            # ลบ Option แจ้งเตือนของ Blocksy
            wp option list --search="*blocksy*" --field=option_name --allow-root 2>/dev/null | grep -i "notice\|update\|version" | xargs -I {} wp option delete {} --allow-root >/dev/null 2>&1
            wp transient delete --all --allow-root >/dev/null 2>&1
            wp cache flush --allow-root >/dev/null 2>&1
            
            # รองรับ Cache Plugins
            wp plugin is-active litespeed-cache --allow-root 2>/dev/null && wp litespeed-purge all --allow-root >/dev/null 2>&1
            wp plugin is-active wp-rocket --allow-root 2>/dev/null && wp rocket clean --allow-root >/dev/null 2>&1

            echo "    [OK] อัปเดตจาก GitHub เรียบร้อย!" | tee -a "$LOG_FILE"
        else
            echo "    [SKIP] ไม่พบปลั๊กอิน $PLUGIN_SLUG ข้ามการทำงาน" | tee -a "$LOG_FILE"
        fi

    )
done <<< "$ALL_SITES_LIST"

echo "------------------------------------------------" | tee -a "$LOG_FILE"
echo "ทำงานเสร็จสิ้น! เช็คผลลัพธ์ได้ที่: $LOG_FILE"
