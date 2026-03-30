#!/bin/bash                                         

USER_HOME="$HOME"
# กำหนดไฟล์ ZIP และ Log (ปรับ BASE_DIR ให้ตรงกับตำแหน่งไฟล์ ZIP ของคุณ)
BASE_DIR="$USER_HOME/applications"
ZIP_FILE="$USER_HOME/blocksy-companion-pro.zip"
LOG_FILE="$USER_HOME/plugin_update_$(date +%Y%m%d_%H%M%S).txt"

# ตรวจสอบว่าไฟล์ ZIP มีอยู่จริงไหมก่อนเริ่ม
if [ ! -f "$ZIP_FILE" ]; then
    echo "❌ Error: ZIP file not found at $ZIP_FILE"
    exit 1
fi

# กำหนด Path หลักของ Applications
if [ -L "$BASE_DIR" ]; then
    APPS_DIR=$(readlink -f "$BASE_DIR")
else
    APPS_DIR="$BASE_DIR"
fi

cd "$APPS_DIR" || exit 1

# --- 1) การนับยอดก่อนเริ่ม (Pre-Scan Count) ---
PRE_COUNT=$(find . -maxdepth 1 -type d ! -name "." ! -name "applications" | wc -l)

echo "------------------------------------------------" | tee -a "$LOG_FILE"
echo "🚀 Plugin Mass Update started at $(date)" | tee -a "$LOG_FILE"
echo "Total folders to check: $PRE_COUNT" | tee -a "$LOG_FILE"
echo "ZIP File: $ZIP_FILE" | tee -a "$LOG_FILE"
echo "------------------------------------------------" | tee -a "$LOG_FILE"
printf "%-25s | %-30s | %-10s\n" "Folder Name" "Domain" "Status" | tee -a "$LOG_FILE"
echo "------------------------------------------------" | tee -a "$LOG_FILE"

# --- 2) เริ่มการ Scan และ Update ---
WP_SITES_FOUND=0
UPDATE_SUCCESS=0
SCANNED_COUNT=0
FAILED_LIST=""

for APP_FOLDER in */; do
    APP_NAME="${APP_FOLDER%/}"

    if [ "$APP_NAME" == "applications" ] || [ "$APP_NAME" == "." ] || [ "$APP_NAME" == ".." ]; then
        continue
    fi

    ((SCANNED_COUNT++))
    SITE_PATH="$APPS_DIR/$APP_FOLDER/"

    if [ -d "$SITE_PATH" ]; then
        cd "$SITE_PATH" || continue
        
        # ตรวจสอบว่าเป็น WP และดึง Domain
        DOMAIN=$(wp option get home --skip-plugins --skip-themes --allow-root 2>/dev/null)

        if [ -n "$DOMAIN" ]; then
            ((WP_SITES_FOUND++))
            
            # สั่งติดตั้ง/อัปเดต Plugin
            if wp plugin install "$ZIP_FILE" --activate --force --allow-root >> "$LOG_FILE" 2>&1; then
                printf "%-25s | %-30s | %-10s\n" "$APP_NAME" "$DOMAIN" "✅ OK" | tee -a "$LOG_FILE"
                ((UPDATE_SUCCESS++))
            else
                printf "%-25s | %-30s | %-10s\n" "$APP_NAME" "$DOMAIN" "❌ Failed" | tee -a "$LOG_FILE"
                FAILED_LIST+="- $APP_NAME (Update failed)\n"
            fi
        else
            printf "%-25s | %-30s | %-10s\n" "$APP_NAME" "(Not a WP Site)" "⚠️ Skip" | tee -a "$LOG_FILE"
            FAILED_LIST+="- $APP_NAME (Found public_html but DB error/Not WP)\n"
        fi
        
        cd "$APPS_DIR"
    else
        printf "%-25s | %-30s | %-10s\n" "$APP_NAME" "(No public_html)" "⚠️ Skip" | tee -a "$LOG_FILE"
        FAILED_LIST+="- $APP_NAME (Missing public_html folder)\n"
    fi
done

# --- 3) การนับยอดหลังทำงานเสร็จ (Post-Scan Summary) ---
echo "------------------------------------------------" | tee -a "$LOG_FILE"
echo "✅ Update Process Completed!" | tee -a "$LOG_FILE"
echo "------------------------------------------------" | tee -a "$LOG_FILE"
echo "Total folders found         : $PRE_COUNT" | tee -a "$LOG_FILE"
echo "Total folders processed     : $SCANNED_COUNT" | tee -a "$LOG_FILE"
echo "WordPress sites detected    : $WP_SITES_FOUND" | tee -a "$LOG_FILE"
echo "Successfully updated        : $UPDATE_SUCCESS" | tee -a "$LOG_FILE"

if [ $WP_SITES_FOUND -lt $SCANNED_COUNT ] || [ $UPDATE_SUCCESS -lt $WP_SITES_FOUND ]; then
    echo "------------------------------------------------" | tee -a "$LOG_FILE"
    echo "⚠️  Details of folders not updated:" | tee -a "$LOG_FILE"
    echo -e "$FAILED_LIST" | tee -a "$LOG_FILE"
fi
echo "------------------------------------------------" | tee -a "$LOG_FILE"
echo "Log saved to: $LOG_FILE"
