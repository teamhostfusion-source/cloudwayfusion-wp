#!/bin/bash                                         

USER_HOME="$HOME"
# --- 1) ตั้งค่าไฟล์และระบบ ---
BASE_DIR="$USER_HOME/applications"
ZIP_FILE="$USER_HOME/blocksy-companion-pro.zip" # ชื่อไฟล์ ZIP ของคุณ
PLUGIN_SLUG="blocksy-companion-pro"
LOG_FILE="$USER_HOME/update_blocksy_$(date +%Y%m%d_%H%M%S).txt"

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

# --- 2) การนับยอดก่อนเริ่ม (Pre-Scan Count) ---
PRE_COUNT=$(find . -maxdepth 1 -type d ! -name "." ! -name "applications" | wc -l)

echo "-----------------------------------------------------------------" | tee -a "$LOG_FILE"
echo "🚀 Blocksy Pro Mass Update started at $(date)" | tee -a "$LOG_FILE"
echo "Total folders to check: $PRE_COUNT" | tee -a "$LOG_FILE"
echo "ZIP File: $ZIP_FILE" | tee -a "$LOG_FILE"
echo "-----------------------------------------------------------------" | tee -a "$LOG_FILE"
# ปรับความกว้างของตารางให้พอดีกับข้อความ Status
printf "%-22s | %-28s | %-12s\n" "Folder Name" "Domain" "Status" | tee -a "$LOG_FILE"
echo "-----------------------------------------------------------------" | tee -a "$LOG_FILE"

# --- 3) เริ่มการ Scan และ Update ---
WP_SITES_FOUND=0
UPDATE_SUCCESS=0
SKIPPED_COUNT=0
SCANNED_COUNT=0
FAILED_LIST=""

for APP_FOLDER in */; do
    APP_NAME="${APP_FOLDER%/}"

    # ข้ามโฟลเดอร์ที่ไม่เกี่ยวข้อง
    if [ "$APP_NAME" == "applications" ] || [ "$APP_NAME" == "." ] || [ "$APP_NAME" == ".." ]; then
        continue
    fi

    ((SCANNED_COUNT++))
    SITE_PATH="$APPS_DIR/$APP_FOLDER/public_html"

    if [ -d "$SITE_PATH" ]; then
        cd "$SITE_PATH" || continue
        
        # ตรวจสอบว่าเป็น WP และดึง Domain (ตัด https:// ออกเพื่อให้ตารางสวยงาม)
        DOMAIN=$(wp option get home --skip-plugins --skip-themes --allow-root 2>/dev/null | sed 's|^https*://||')

        if [ -n "$DOMAIN" ]; then
            ((WP_SITES_FOUND++))
            
            # เช็คว่าเว็บนี้มีปลั๊กอิน Blocksy อยู่แล้วหรือไม่
            if wp plugin is-installed "$PLUGIN_SLUG" --allow-root 2>/dev/null; then
                
                # สั่งติดตั้งทับ
                if wp plugin install "$ZIP_FILE" --activate --force --allow-root >> "$LOG_FILE" 2>&1; then
                    
                    # คืนสิทธิ์ให้ Web Server
                    chown -R www-data:www-data "$SITE_PATH/wp-content/plugins/$PLUGIN_SLUG" 2>/dev/null
                    
                    # --- CLEANUP (ลบแจ้งเตือน & ล้างแคช) ---
                    wp option list --search="*blocksy*" --field=option_name --allow-root 2>/dev/null | grep -i "notice\|update\|version" | xargs -I {} wp option delete {} --allow-root >> "$LOG_FILE" 2>&1
                    wp transient delete --all --allow-root >> "$LOG_FILE" 2>&1
                    wp cache flush --allow-root >> "$LOG_FILE" 2>&1
                    
                    wp plugin is-active litespeed-cache --allow-root 2>/dev/null && wp litespeed-purge all --allow-root >> "$LOG_FILE" 2>&1
                    wp plugin is-active wp-rocket --allow-root 2>/dev/null && wp rocket clean --allow-root >> "$LOG_FILE" 2>&1
                    # -------------------------------------

                    printf "%-22s | %-28s | %-12s\n" "$APP_NAME" "$DOMAIN" "✅ Updated" | tee -a "$LOG_FILE"
                    ((UPDATE_SUCCESS++))
                else
                    printf "%-22s | %-28s | %-12s\n" "$APP_NAME" "$DOMAIN" "❌ Failed" | tee -a "$LOG_FILE"
                    FAILED_LIST+="- $APP_NAME (Update failed)\n"
                fi
            else
                # กรณีเว็บนี้ไม่ได้ลงปลั๊กอิน Blocksy ไว้
                printf "%-22s | %-28s | %-12s\n" "$APP_NAME" "$DOMAIN" "⏭️ Skip (No plugin)" | tee -a "$LOG_FILE"
                ((SKIPPED_COUNT++))
            fi
        else
            printf "%-22s | %-28s | %-12s\n" "$APP_NAME" "(Not a WP Site)" "⚠️ Skip" | tee -a "$LOG_FILE"
            FAILED_LIST+="- $APP_NAME (Found public_html but DB error/Not WP)\n"
        fi
        
        cd "$APPS_DIR"
    else
        printf "%-22s | %-28s | %-12s\n" "$APP_NAME" "(No public_html)" "⚠️ Skip" | tee -a "$LOG_FILE"
        FAILED_LIST+="- $APP_NAME (Missing public_html folder)\n"
    fi
done

# --- 4) การนับยอดหลังทำงานเสร็จ (Post-Scan Summary) ---
echo "-----------------------------------------------------------------" | tee -a "$LOG_FILE"
echo "✅ Update Process Completed!" | tee -a "$LOG_FILE"
echo "-----------------------------------------------------------------" | tee -a "$LOG_FILE"
echo "Total folders found         : $PRE_COUNT" | tee -a "$LOG_FILE"
echo "Total folders processed     : $SCANNED_COUNT" | tee -a "$LOG_FILE"
echo "WordPress sites detected    : $WP_SITES_FOUND" | tee -a "$LOG_FILE"
echo "Skipped (Plugin not found)  : $SKIPPED_COUNT" | tee -a "$LOG_FILE"
echo "Successfully updated        : $UPDATE_SUCCESS" | tee -a "$LOG_FILE"

if [ -n "$FAILED_LIST" ]; then
    echo "-----------------------------------------------------------------" | tee -a "$LOG_FILE"
    echo "⚠️  Details of folders with issues:" | tee -a "$LOG_FILE"
    echo -e "$FAILED_LIST" | tee -a "$LOG_FILE"
fi
echo "-----------------------------------------------------------------" | tee -a "$LOG_FILE"
echo "Log saved to: $LOG_FILE"
