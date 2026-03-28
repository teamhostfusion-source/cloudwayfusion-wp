#!/bin/bash

BASE_DIR="$HOME/applications"
LOG_FILE="$HOME/update_blocksy_master.log"

> "$LOG_FILE"
echo "------ เริ่มกระบวนการ Force Update Blocksy & Clear Cache ------" | tee -a "$LOG_FILE"

# กรองโฟลเดอร์ Backup/Staging ทิ้ง เอาเฉพาะเว็บจริง
ALL_SITES_LIST=$(find -L "$BASE_DIR" -name "wp-config.php" | grep -vEi "backup|old|archive|trash|staging|/\.")
TOTAL_SITES=$(echo "$ALL_SITES_LIST" | grep -c "wp-config.php")

if [ "$TOTAL_SITES" -eq 0 ]; then
    echo "Error: ไม่พบการติดตั้ง WordPress ที่ใช้งานจริง"
    exit 1
fi

echo "พบ WordPress จำนวน $TOTAL_SITES เว็บ..." | tee -a "$LOG_FILE"
CURRENT_INDEX=0

while read -r config_path; do
    [ -z "$config_path" ] && continue
    
    ((CURRENT_INDEX++))
    SITE_PATH=$(dirname "$config_path")
    
    (
        cd "$SITE_PATH" || exit 1
        DOMAIN=$(wp option get home --allow-root 2>/dev/null || echo "Unknown Domain")
        echo "------------------------------------------------" | tee -a "$LOG_FILE"
        echo "[$CURRENT_INDEX/$TOTAL_SITES] กำลังจัดการเว็บ: $DOMAIN" | tee -a "$LOG_FILE"

        # ---------------------------------------------------------
        # 1. บังคับอัปเดต Theme และ Plugin แบบไม่สนใจเวอร์ชันปัจจุบัน
        # ---------------------------------------------------------
        if wp theme is-installed blocksy --allow-root 2>/dev/null; then
            echo "    [UPDATE] บังคับโหลด Blocksy Theme ล่าสุดมาติดตั้งทับ..." | tee -a "$LOG_FILE"
            # ใช้ install --force เพื่อโหลด ZIP ล่าสุดจากเว็บมาทับไฟล์เดิม 100% แก้ปัญหา API รวน
            wp theme install blocksy --force --allow-root >> "$LOG_FILE" 2>&1
        fi

        if wp plugin is-installed blocksy-companion --allow-root 2>/dev/null; then
            echo "    [UPDATE] บังคับอัปเดต Blocksy Companion..." | tee -a "$LOG_FILE"
            wp plugin install blocksy-companion --force --allow-root >> "$LOG_FILE" 2>&1
        fi
        
        if wp plugin is-installed blocksy-companion-pro --allow-root 2>/dev/null; then
            echo "    [UPDATE] กำลังอัปเดต Blocksy Companion Pro..." | tee -a "$LOG_FILE"
            wp plugin update blocksy-companion-pro --allow-root >/dev/null 2>&1
        fi

        # ---------------------------------------------------------
        # 2. กวาดล้าง Cache เพื่อลบป้ายแจ้งเตือนและอัปเดตหน้าเว็บ
        # ---------------------------------------------------------
        echo "    [CLEANUP] กำลังล้างระบบ Cache ทุกรูปแบบ..." | tee -a "$LOG_FILE"
        
        # ล้างป้ายแจ้งเตือนค้างในหลังบ้าน
        wp transient delete --all --allow-root >/dev/null 2>&1
        
        # ล้าง Object Cache หลัก
        wp cache flush --allow-root >/dev/null 2>&1
        wp varnish purge --allow-root >/dev/null 2>&1
        
        # ล้าง WP Rocket (ถ้ามี)
        if wp plugin is-active wp-rocket --allow-root 2>/dev/null; then
            wp rocket clean --allow-root >/dev/null 2>&1
            echo "    [CACHE] ล้างแคช WP Rocket แล้ว" | tee -a "$LOG_FILE"
        fi
        
        # ล้าง SG Optimizer (ถ้ามี)
        if wp plugin is-active sg-cachepress --allow-root 2>/dev/null; then
            wp sgpurge --allow-root >/dev/null 2>&1
        fi
        
        # ล้าง LiteSpeed Cache (ถ้ามี)
        if wp plugin is-active litespeed-cache --allow-root 2>/dev/null; then
            wp litespeed-purge all --allow-root >/dev/null 2>&1
        fi
        
        echo "    [OK] เสร็จสิ้นสมบูรณ์สำหรับเว็บนี้" | tee -a "$LOG_FILE"
    )

done <<< "$ALL_SITES_LIST"

echo "------------------------------------------------" | tee -a "$LOG_FILE"
echo "ดำเนินการเสร็จสิ้นทั้งหมด! สามารถตรวจสอบประวัติการทำงานได้ที่ไฟล์: $LOG_FILE"
