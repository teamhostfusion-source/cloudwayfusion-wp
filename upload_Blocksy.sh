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

# นับจำนวนโฟลเดอร์ทั้งหมดเพื่อทำ Progress
PRE_COUNT=$(find . -maxdepth 1 -type d ! -name "." ! -name "applications" | wc -l)

echo "-----------------------------------------------------------------" | tee -a "$LOG_FILE"
echo "🚀 Start Process: $(date)" | tee -a "$LOG_FILE"
echo "Scanning $PRE_COUNT folders..." | tee -a "$LOG_FILE"
echo "-----------------------------------------------------------------" | tee -a "$LOG_FILE"
printf "%-22s | %-28s | %-12s\n" "Folder Name" "Domain" "Status" | tee -a "$LOG_FILE"
echo "-----------------------------------------------------------------" | tee -a "$LOG_FILE"

# ตัวแปรเก็บสถิติ
WP_SITES_FOUND=0
UPDATE_SUCCESS=0
SKIPPED_COUNT=0
FAILED_LIST=""

for APP_FOLDER in */; do
    APP_NAME="${APP_FOLDER%/}"

    # ข้ามโฟลเดอร์ที่ไม่เกี่ยวข้อง
    if [[ "$APP_NAME" == "applications" || "$APP_NAME" == "." || "$APP_NAME" == ".." ]]; then
        continue
    fi

    SITE_PATH="$APPS_DIR/$APP_FOLDER/public_html"

    # 1. เช็กว่ามี public_html หรือไม่
    if [ -d "$SITE_PATH" ]; then
        cd "$SITE_PATH" || continue
        
        # 2. เช็กว่าเป็น WordPress หรือไม่ (ดึง Domain มาโชว์)
        DOMAIN=$(wp option get home --skip-plugins --skip-themes --allow-root 2>/dev/null | sed 's|^https*://||')

        if [ -n "$DOMAIN" ]; then
            ((WP_SITES_FOUND++))
            
            # 3. [เงื่อนไขสำคัญ] เช็กว่ามี Plugin นี้ติดตั้งอยู่หรือไม่
            if wp plugin is-installed "$PLUGIN_SLUG" --allow-root 2>/dev/null; then
                
                # --- เริ่มกระบวนการทำงานในแต่ละ Site ---
                LOCAL_ZIP="$SITE_PATH/$TEMP_ZIP_NAME"
                
                # Download ไฟล์มาไว้ที่เว็บนี้โดยเฉพาะ
                wget -q -O "$LOCAL_ZIP" "$GITHUB_URL"

                # ตรวจสอบไฟล์ ZIP ว่าโหลดมาสมบูรณ์ไหม
                if [[ ! -s "$LOCAL_ZIP" ]] || ! unzip -t "$LOCAL_ZIP" >/dev/null 2>&1; then
                    printf "%-22s | %-28s | %-12s\n" "$APP_NAME" "$DOMAIN" "❌ DL Failed" | tee -a "$LOG_FILE"
                    FAILED_LIST+="- $APP_NAME: Download failed or invalid ZIP\n"
                    rm -f "$LOCAL_ZIP"
                    continue
                fi

                # ลบของเก่าออกก่อนเพื่อความสะอาด
                wp plugin delete "$PLUGIN_SLUG" --allow-root >> "$LOG_FILE" 2>&1
                
                # ติดตั้งจากไฟล์ ZIP ที่โหลดมา
                INSTALL_OUTPUT=$(wp plugin install "$LOCAL_ZIP" --allow-root 2>&1)
                
                if [ $? -eq 0 ]; then
                    # แก้ไขชื่อโฟลเดอร์กรณี GitHub เติม suffix เช่น -main
                    GITHUB_FOLDER=$(ls "$SITE_PATH/wp-content/plugins/" | grep "^$PLUGIN_SLUG-")
                    if [ -n "$GITHUB_FOLDER" ]; then
                        mv "$SITE_PATH/wp-content/plugins/$GITHUB_FOLDER" "$SITE_PATH/wp-content/plugins/$PLUGIN_SLUG"
                    fi
                    
                    # Activate และตั้งค่าสิทธิ์
                    wp plugin activate "$PLUGIN_SLUG" --allow-root >> "$LOG_FILE" 2>&1
                    chown -R www-data:www-data "$SITE_PATH/wp-content/plugins/$PLUGIN_SLUG" 2>/dev/null
                    
                    # ล้าง Cache และ Transient
                    wp transient delete --all --allow-root >> "$LOG_FILE" 2>&1
                    wp cache flush --allow-root >> "$LOG_FILE" 2>&1

                    printf "%-22s | %-28s | %-12s\n" "$APP_NAME" "$DOMAIN" "✅ Updated" | tee -a "$LOG_FILE"
                    ((UPDATE_SUCCESS++))
                else
                    printf "%-22s | %-28s | %-12s\n" "$APP_NAME" "$DOMAIN" "❌ Error" | tee -a "$LOG_FILE"
                    ERROR_DETAIL=$(echo "$INSTALL_OUTPUT" | grep "Error" | head -n 1)
                    FAILED_LIST+="- $APP_NAME: $ERROR_DETAIL\n"
                fi

                # ลบไฟล์ ZIP ทิ้งทันทีหลังเสร็จงาน
                rm -f "$LOCAL_ZIP"

            else
                # ถ้าไม่มี Plugin ให้ข้ามไป
                printf "%-22s | %-28s | %-12s\n" "$APP_NAME" "$DOMAIN" "⏭️  Skip (No Plugin)" | tee -a "$LOG_FILE"
                ((SKIPPED_COUNT++))
            fi
        else
            printf "%-22s | %-28s | %-12s\n" "$APP_NAME" "---" "⚠️  Not WP" | tee -a "$LOG_FILE"
        fi
        cd "$APPS_DIR"
    else
        printf "%-22s | %-28s | %-12s\n" "$APP_NAME" "---" "⚠️  No Path" | tee -a "$LOG_FILE"
    fi
done

# --- 3) สรุปผล ---
echo "-----------------------------------------------------------------" | tee -a "$LOG_FILE"
echo "📊 Summary Report" | tee -a "$LOG_FILE"
echo "-----------------------------------------------------------------" | tee -a "$LOG_FILE"
echo "WordPress sites found  : $WP_SITES_FOUND" | tee -a "$LOG_FILE"
echo "Successfully updated   : $UPDATE_SUCCESS" | tee -a "$LOG_FILE"
echo "Skipped (No Plugin)    : $SKIPPED_COUNT" | tee -a "$LOG_FILE"

if [ -n "$FAILED_LIST" ]; then
    echo "-----------------------------------------------------------------" | tee -a "$LOG_FILE"
    echo "❌ Failed Sites:" | tee -a "$LOG_FILE"
    echo -e "$FAILED_LIST" | tee -a "$LOG_FILE"
fi
echo "-----------------------------------------------------------------" | tee -a "$LOG_FILE"
echo "Log file saved to: $LOG_FILE"
