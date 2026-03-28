#!/bin/bash

BASE_DIR="$HOME/applications"
LOG_FILE="$HOME/update_blocksy_action.log"

> "$LOG_FILE"
echo "------ เริ่มกระบวนการ อัปเดต Blocksy (จำลองการกดปุ่ม) ------" | tee -a "$LOG_FILE"

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
        # 1. จำลองการกดปุ่ม: สั่งอัปเดตไฟล์ธีมและปลั๊กอิน
        # ---------------------------------------------------------
        if wp theme is-installed blocksy --allow-root 2>/dev/null; then
            echo "    [ACTION] กำลังสั่งอัปเดตธีม Blocksy..." | tee -a "$LOG_FILE"
            wp theme update blocksy --allow-root >/dev/null 2>&1
            wp theme install blocksy --force --allow-root >/dev/null 2>&1 # เผื่อ API WP ค้าง ให้ทับไฟล์ไปเลย
        else
            echo "    [SKIP] ไม่พบธีม Blocksy" | tee -a "$LOG_FILE"
            exit 0
        fi

        if wp plugin is-installed blocksy-companion --allow-root 2>/dev/null; then
            wp plugin update blocksy-companion --allow-root >/dev/null 2>&1
        fi
        
        if wp plugin is-installed blocksy-companion-pro --allow-root 2>/dev/null; then
            wp plugin update blocksy-companion-pro --allow-root >/dev/null 2>&1
        fi

        # ---------------------------------------------------------
        # 2. จำลองการกดปุ่ม: เตะป้ายแจ้งเตือนทิ้งจากฐานข้อมูล
        # ---------------------------------------------------------
        echo "    [CLEANUP] เคลียร์สถานะป้ายแจ้งเตือนในฐานข้อมูล..." | tee -a "$LOG_FILE"
        
        # ค้นหาและลบ Option ที่ Blocksy ใช้จำค่าป้ายแจ้งเตือนนี้
        wp option list --search="*blocksy*" --field=option_name --allow-root 2>/dev/null | grep -i "notice\|update\|version" | xargs -I {} wp option delete {} --allow-root >/dev/null 2>&1
        wp option list --search="*ct_*" --field=option_name --allow-root 2>/dev/null | grep -i "notice\|update" | xargs -I {} wp option delete {} --allow-root >/dev/null 2>&1

        # ลบ Transients ทั้งหมด (เคลียร์ความจำหลังบ้าน)
        wp transient delete --all --allow-root >/dev/null 2>&1

        # ---------------------------------------------------------
        # 3. ล้าง Cache ทั้งหน้าบ้านและหลังบ้าน
        # ---------------------------------------------------------
        wp cache flush --allow-root >/dev/null 2>&1
        
        # รองรับปลั๊กอินแคชยอดนิยม
        if wp plugin is-active wp-rocket --allow-root 2>/dev/null; then wp rocket clean --allow-root >/dev/null 2>&1; fi
        if wp plugin is-active litespeed-cache --allow-root 2>/dev/null; then wp litespeed-purge all --allow-root >/dev/null 2>&1; fi
        if wp plugin is-active sg-cachepress --allow-root 2>/dev/null; then wp sgpurge --allow-root >/dev/null 2>&1; fi

        echo "    [OK] อัปเดตและเคลียร์ปุ่มเสร็จสิ้นเรียบร้อย!" | tee -a "$LOG_FILE"
    )

done <<< "$ALL_SITES_LIST"

echo "------------------------------------------------" | tee -a "$LOG_FILE"
echo "การจำลองอัปเดตเสร็จสมบูรณ์! เช็ค Log ได้ที่: $LOG_FILE"
