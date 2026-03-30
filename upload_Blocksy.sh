#!/bin/bash                                         

USER_HOME="$HOME"
PLUGIN_SLUG="blocksy-companion-pro"

# --- 1) ตั้งค่าระบบและ GitHub ---
# ตรวจสอบ Token ให้ชัวร์ว่ายังไม่หมดอายุ
GITHUB_URL="https://github.com/teamhostfusion-source/cloudwayfusion-wp/blob/main/blocksy-companion-pro.zip"
SEARCH_FILENAME="${PLUGIN_SLUG}_temp.zip"
LOG_FILE="$USER_HOME/install_blocksy_$(date +%Y%m%d_%H%M%S).txt"

> "$LOG_FILE"

# --- 2) กำหนด Path หลักของ Applications ---
BASE_DIR="$USER_HOME/applications"
if [ -L "$BASE_DIR" ]; then
    APPS_DIR=$(readlink -f "$BASE_DIR")
else
    APPS_DIR="$BASE_DIR"
fi

cd "$APPS_DIR" || exit 1

PRE_COUNT=$(find . -maxdepth 1 -type d ! -name "." ! -name "applications" | wc -l)

echo "-----------------------------------------------------------------" | tee -a "$LOG_FILE"
echo "🚀 Step 1: Individual Download & Install started at $(date)" | tee -a "$LOG_FILE"
echo "Total folders to check: $PRE_COUNT" | tee -a "$LOG_FILE"
echo "-----------------------------------------------------------------" | tee -a "$LOG_FILE"
printf "%-22s | %-28s | %-12s\n" "Folder Name" "Domain" "Status" | tee -a "$LOG_FILE"
echo "-----------------------------------------------------------------" | tee -a "$LOG_FILE"

WP_SITES_FOUND=0
UPDATE_SUCCESS=0
SKIPPED_COUNT=0
SCANNED_COUNT=0
FAILED_LIST=""

for APP_FOLDER in */; do
    APP_NAME="${APP_FOLDER%/}"

    if [ "$APP_NAME" == "applications" ] || [ "$APP_NAME" == "." ] || [ "$APP_NAME" == ".." ]; then
        continue
    fi

    ((SCANNED_COUNT++))
    SITE_PATH="$APPS_DIR/$APP_FOLDER/public_html"

    if [ -d "$SITE_PATH" ]; then
        cd "$SITE_PATH" || continue
        
        DOMAIN=$(wp option get home --skip-plugins --skip-themes --allow-root 2>/dev/null | sed 's|^https*://||')

        if [ -n "$DOMAIN" ]; then
            ((WP_SITES_FOUND++))
            
                           
                # --- [จุดที่เปลี่ยน] Download ไฟล์ลงในโฟลเดอร์ของเว็บนี้โดยเฉพาะ ---
                LOCAL_DOWNLOAD_DEST="$SITE_PATH/$SEARCH_FILENAME"
                wget -q -O "$LOCAL_DOWNLOAD_DEST" "$GITHUB_URL"

                # ตรวจสอบไฟล์ที่โหลดมา
                if [ ! -s "$LOCAL_DOWNLOAD_DEST" ] || ! unzip -t "$LOCAL_DOWNLOAD_DEST" >/dev/null 2>&1; then
                    printf "%-22s | %-28s | %-12s\n" "$APP_NAME" "$DOMAIN" "❌ DL Failed" | tee -a "$LOG_FILE"
                    FAILED_LIST+="- $APP_NAME: Download failed or invalid ZIP\n"
                    rm -f "$LOCAL_DOWNLOAD_DEST"
                    continue
                fi

                # ลบ Plugin ตัวเก่าออกก่อน
                wp plugin delete "$PLUGIN_SLUG" --allow-root >> "$LOG_FILE" 2>&1
                
                # ติดตั้งจากไฟล์ Zip ที่โหลดมาไว้ในเครื่อง
                INSTALL_OUTPUT=$(wp plugin install "$LOCAL_DOWNLOAD_DEST" --allow-root 2>&1)
                INSTALL_STATUS=$?
                
                if [ $INSTALL_STATUS -eq 0 ]; then
                    # จัดการเรื่องชื่อโฟลเดอร์ (กรณี GitHub เติม -main หรือ -master)
                    GITHUB_FOLDER=$(ls "$SITE_PATH/wp-content/plugins/" | grep "^$PLUGIN_SLUG-")
                    if [ ! -z "$GITHUB_FOLDER" ]; then
                        mv "$SITE_PATH/wp-content/plugins/$GITHUB_FOLDER" "$SITE_PATH/wp-content/plugins/$PLUGIN_SLUG"
                    fi
                    
                    wp plugin activate "$PLUGIN_SLUG" --allow-root >> "$LOG_FILE" 2>&1
                    chown -R www-data:www-data "$SITE_PATH/wp-content/plugins/$PLUGIN_SLUG" 2>/dev/null
                    
                    # Cleanup WP Cache & Data
                    wp option list --search="*blocksy*" --field=option_name --allow-root 2>/dev/null | grep -i "notice\|update\|version" | xargs -I {} wp option delete {} --allow-root >> "$LOG_FILE" 2>&1
                    wp transient delete --all --allow-root >> "$LOG_FILE" 2>&1
                    wp cache flush --allow-root >> "$LOG_FILE" 2>&1

                    printf "%-22s | %-28s | %-12s\n" "$APP_NAME" "$DOMAIN" "✅ Installed" | tee -a "$LOG_FILE"
                    ((UPDATE_SUCCESS++))
                
                fi

                # ลบไฟล์ Zip ทิ้งหลังจากติดตั้งเสร็จ (เพื่อความสะอาด)
                rm -f "$LOCAL_DOWNLOAD_DEST"
            else
                printf "%-22s | %-28s | %-12s\n" "$APP_NAME" "$DOMAIN" "⏭️ Skip" | tee -a "$LOG_FILE"
                ((SKIPPED_COUNT++))
            fi
        else
            printf "%-22s | %-28s | %-12s\n" "$APP_NAME" "(Not a WP Site)" "⚠️ Skip" | tee -a "$LOG_FILE"
        fi
        cd "$APPS_DIR"
    else
        printf "%-22s | %-28s | %-12s\n" "$APP_NAME" "(No public_html)" "⚠️ Skip" | tee -a "$LOG_FILE"
    fi
done

echo "-----------------------------------------------------------------" | tee -a "$LOG_FILE"
echo "✅ Process Completed!" | tee -a "$LOG_FILE"
echo "-----------------------------------------------------------------" | tee -a "$LOG_FILE"
echo "WordPress sites detected : $WP_SITES_FOUND" | tee -a "$LOG_FILE"
echo "Successfully installed   : $UPDATE_SUCCESS" | tee -a "$LOG_FILE"

if [ -n "$FAILED_LIST" ]; then
    echo "-----------------------------------------------------------------" | tee -a "$LOG_FILE"
    echo "⚠️  Error Details:" | tee -a "$LOG_FILE"
    echo -e "$FAILED_LIST" | tee -a "$LOG_FILE"
fi
