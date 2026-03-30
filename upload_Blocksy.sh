#!/bin/bash                                         

USER_HOME="$HOME"
PLUGIN_SLUG="blocksy-companion-pro"

# --- 1) ตั้งค่า GitHub (ใส่ Token และ URL ให้ถูกต้อง) ---
GITHUB_URL="https://github.com/teamhostfusion-source/cloudwayfusion-wp/blob/main/blocksy-companion-pro.zip"
TEMP_ZIP_NAME="${PLUGIN_SLUG}_temp.zip"
LOG_FILE="$USER_HOME/install_blocksy_$(date +%Y%m%d_%H%M%S).txt"

> "$LOG_FILE"

# --- 2) ตรวจสอบ Path ของ Applications ---
BASE_DIR="$USER_HOME/applications"
if [ -L "$BASE_DIR" ]; then
    APPS_DIR=$(readlink -f "$BASE_DIR")
else
    APPS_DIR="$BASE_DIR"
fi

cd "$APPS_DIR" || { echo "❌ Error: ไม่พบโฟลเดอร์ applications" | tee -a "$LOG_FILE"; exit 1; }

PRE_COUNT=$(find . -maxdepth 1 -type d ! -name "." ! -name "applications" | wc -l)

echo "-----------------------------------------------------------------" | tee -a "$LOG_FILE"
echo "🚀 Start Process: $(date)" | tee -a "$LOG_FILE"
echo "Target: Install/Update $PLUGIN_SLUG on all WP sites"
echo "-----------------------------------------------------------------" | tee -a "$LOG_FILE"
printf "%-22s | %-28s | %-12s\n" "Folder Name" "Domain" "Status" | tee -a "$LOG_FILE"
echo "-----------------------------------------------------------------" | tee -a "$LOG_FILE"

WP_SITES_FOUND=0
INSTALL_SUCCESS=0
FAILED_LIST=""

for APP_FOLDER in */; do
    APP_NAME="${APP_FOLDER%/}"

    if [[ "$APP_NAME" == "applications" || "$APP_NAME" == "." || "$APP_NAME" == ".." ]]; then
        continue
    fi

    SITE_PATH="$APPS_DIR/$APP_FOLDER/public_html"

    if [ -d "$SITE_PATH" ]; then
        cd "$SITE_PATH" || continue
        
        DOMAIN=$(wp option get home --skip-plugins --skip-themes --allow-root 2>/dev/null | sed 's|^https*://||')

        if [ -n "$DOMAIN" ]; then
            ((WP_SITES_FOUND++))
            
            # --- เริ่มขั้นตอนการทำงานสำหรับทุกเว็บที่เป็น WordPress ---
            LOCAL_ZIP="$SITE_PATH/$TEMP_ZIP_NAME"
            
            # 1. Download ไฟล์
            wget -q -O "$LOCAL_ZIP" "$GITHUB_URL"

            # 2. ตรวจสอบไฟล์ ZIP
            if [[ ! -s "$LOCAL_ZIP" ]] || ! unzip -t "$LOCAL_ZIP" >/dev/null 2>&1; then
                printf "%-22s | %-28s | %-12s\n" "$APP_NAME" "$DOMAIN" "❌ DL Failed" | tee -a "$LOG_FILE"
                FAILED_LIST+="- $APP_NAME: Download failed or invalid ZIP\n"
                rm -f "$LOCAL_ZIP"
                continue
            fi

            # 3. ถ้ามีของเก่าอยู่ให้ลบออกก่อน (เพื่อให้เป็น Version ล่าสุดจาก GitHub)
            if wp plugin is-installed "$PLUGIN_SLUG" --allow-root 2>/dev/null; then
                wp plugin delete "$PLUGIN_SLUG" --allow-root >> "$LOG_FILE" 2>&1
                STATUS_TEXT="✅ Updated"
            else
                STATUS_TEXT="✅ Installed"
            fi
            
            # 4. ติดตั้งปลั๊กอิน
            INSTALL_OUTPUT=$(wp plugin install "$LOCAL_ZIP" --allow-root 2>&1)
            
            if [ $? -eq 0 ]; then
                # แก้ไขชื่อโฟลเดอร์กรณี GitHub เติม suffix
                GITHUB_FOLDER=$(ls "$SITE_PATH/wp-content/plugins/" | grep "^$PLUGIN_SLUG-")
                if [ -n "$GITHUB_FOLDER" ]; then
                    mv "$SITE_PATH/wp-content/plugins/$GITHUB_FOLDER" "$SITE_PATH/wp-content/plugins/$PLUGIN_SLUG"
                fi
                
                wp plugin activate "$PLUGIN_SLUG" --allow-root >> "$LOG_FILE" 2>&1
                chown -R www-data:www-data "$SITE_PATH/wp-content/plugins/$PLUGIN_SLUG" 2>/dev/null
                
                # Clean up WP
                wp transient delete --all --allow-root >> "$LOG_FILE" 2>&1
                wp cache flush --allow-root >> "$LOG_FILE" 2>&1

                printf "%-22s | %-28s | %-12s\n" "$APP_NAME" "$DOMAIN" "$STATUS_TEXT" | tee -a "$LOG_FILE"
                ((INSTALL_SUCCESS++))
            else
                printf "%-22s | %-28s | %-12s\n" "$APP_NAME" "$DOMAIN" "❌ Error" | tee -a "$LOG_FILE"
                ERROR_DETAIL=$(echo "$INSTALL_OUTPUT" | grep "Error" | head -n 1)
                FAILED_LIST+="- $APP_NAME: $ERROR_DETAIL\n"
            fi

            # ลบไฟล์ ZIP ทิ้ง
            rm -f "$LOCAL_ZIP"
        else
            printf "%-22s | %-28s | %-12s\n" "$APP_NAME" "---" "⚠️  Not WP" | tee -a "$LOG_FILE"
        fi
        cd "$APPS_DIR"
    else
        printf "%-22s | %-28s | %-12s\n" "$APP_NAME" "---" "⚠️  No Path" | tee -a "$LOG_FILE"
    fi
done

# --- สรุปผล ---
echo "-----------------------------------------------------------------" | tee -a "$LOG_FILE"
echo "📊 Summary Report" | tee -a "$LOG_FILE"
echo "-----------------------------------------------------------------" | tee -a "$LOG_FILE"
echo "WordPress sites found  : $WP_SITES_FOUND" | tee -a "$LOG_FILE"
echo "Total Success          : $INSTALL_SUCCESS" | tee -a "$LOG_FILE"

if [ -n "$FAILED_LIST" ]; then
    echo "-----------------------------------------------------------------" | tee -a "$LOG_FILE"
    echo "❌ Failed Sites Details:" | tee -a "$LOG_FILE"
    echo -e "$FAILED_LIST" | tee -a "$LOG_FILE"
fi
echo "-----------------------------------------------------------------" | tee -a "$LOG_FILE"
