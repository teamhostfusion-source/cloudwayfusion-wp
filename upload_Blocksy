#!/bin/bash

# --- ตั้งค่าส่วนตัว ---
BASE_DIR="$HOME/applications"
LOG_FILE="$HOME/update_github_assets.log"
# ระบุ URL ของ GitHub (ตัวอย่าง: https://github.com/USER/REPO/archive/refs/heads/main.zip)
PLUGIN_GITHUB_URL="https://github.com/creativethemes/blocksy-companion/archive/refs/heads/master.zip"
THEME_GITHUB_URL="https://github.com/creativethemes/blocksy/archive/refs/heads/master.zip"

# ชื่อโฟลเดอร์ปลายทางที่ถูกต้อง (Slug)
PLUGIN_SLUG="blocksy-companion"
THEME_SLUG="blocksy"

> "$LOG_FILE"
echo "------ เริ่มกระบวนการอัปเดตจาก GitHub สำหรับทุกเว็บไซต์ ------" | tee -a "$LOG_FILE"

# กรองโฟลเดอร์เอาเฉพาะที่มี wp-config.php
ALL_SITES_LIST=$(find -L "$BASE_DIR" -maxdepth 3 -name "wp-config.php" | grep -vEi "backup|old|archive|trash|staging|/\.")
TOTAL_SITES=$(echo "$ALL_SITES_LIST" | grep -c "wp-config.php")

[ "$TOTAL_SITES" -eq 0 ] && echo "Error: ไม่พบเว็บไซต์" && exit 1

CURRENT_INDEX=0

while read -r config_path; do
    ((CURRENT_INDEX++))
    SITE_PATH=$(dirname "$config_path")
    
    (
        cd "$SITE_PATH" || exit 1
        DOMAIN=$(wp option get home --allow-root 2>/dev/null || echo "Unknown")
        echo "------------------------------------------------" | tee -a "$LOG_FILE"
        echo "[$CURRENT_INDEX/$TOTAL_SITES] กำลังจัดการ: $DOMAIN" | tee -a "$LOG_FILE"

        # 1. อัปเดต Theme จาก GitHub
        if wp theme is-installed "$THEME_SLUG" --allow-root 2>/dev/null; then
            echo "    [ACTION] อัปเดต Theme: $THEME_SLUG จาก GitHub..." | tee -a "$LOG_FILE"
            wp theme install "$THEME_GITHUB_URL" --force --activate --allow-root >/dev/null 2>&1
            
            # แก้ไขปัญหา GitHub Folder Name (เช่น blocksy-master -> blocksy)
            THEME_DIR="./wp-content/themes"
            GITHUB_FOLDER=$(ls $THEME_DIR | grep "$THEME_SLUG-")
            if [ ! -z "$GITHUB_FOLDER" ]; then
                mv "$THEME_DIR/$GITHUB_FOLDER" "$THEME_DIR/$THEME_SLUG"
            fi
        fi

        # 2. อัปเดต Plugin จาก GitHub
        if wp plugin is-installed "$PLUGIN_SLUG" --allow-root 2>/dev/null; then
            echo "    [ACTION] อัปเดต Plugin: $PLUGIN_SLUG จาก GitHub..." | tee -a "$LOG_FILE"
            wp plugin install "$PLUGIN_GITHUB_URL" --force --activate --allow-root >/dev/null 2>&1
            
            # แก้ไขชื่อโฟลเดอร์ Plugin (ถ้ามีขีดต่อท้ายจาก GitHub)
            PLUGIN_DIR="./wp-content/plugins"
            GITHUB_PLG_FOLDER=$(ls $PLUGIN_DIR | grep "$PLUGIN_SLUG-")
            if [ ! -z "$GITHUB_PLG_FOLDER" ]; then
                mv "$PLUGIN_DIR/$GITHUB_PLG_FOLDER" "$PLUGIN_DIR/$PLUGIN_SLUG"
            fi
        fi

        # 3. Cleanup & Cache (ตาม Code เดิมของคุณ)
        echo "    [CLEANUP] เคลียร์ Database notices & Cache..." | tee -a "$LOG_FILE"
        wp transient delete --all --allow-root >/dev/null 2>&1
        wp cache flush --allow-root >/dev/null 2>&1
        
        # Purge Litespeed / WP Rocket
        wp plugin is-active litespeed-cache --allow-root 2>/dev/null && wp litespeed-purge all --allow-root >/dev/null 2>&1
        wp plugin is-active wp-rocket --allow-root 2>/dev/null && wp rocket clean --allow-root >/dev/null 2>&1

        echo "    [OK] เสร็จสิ้น!" | tee -a "$LOG_FILE"
    )
done <<< "$ALL_SITES_LIST"

echo "------------------------------------------------" | tee -a "$LOG_FILE"
echo "Done! ตรวจสอบ Log: $LOG_FILE"
