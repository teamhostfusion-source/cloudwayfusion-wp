#!/bin/bash                                         

USER_HOME="$HOME"
# --- 1) ตั้งค่าระบบและ URL ของไฟล์ ---
# ใส่ Link สำหรับดาวน์โหลดไฟล์ .zip (เช่น ลิงก์ตรงจาก Server อื่น หรือ GitHub)
DOWNLOAD_URL="https://github.com/teamhostfusion-source/cloudwayfusion-wp/blob/main/blocksy-companion-pro.2.1.37.zip"

BASE_DIR="$USER_HOME/applications"
ZIP_FILE="$USER_HOME/blocksy-companion-pro_temp.zip" # ไฟล์จะถูกโหลดมาเก็บไว้ชื่อนี้
PLUGIN_SLUG="blocksy-companion-pro"
LOG_FILE="$USER_HOME/install_blocksy_$(date +%Y%m%d_%H%M%S).txt"

# กำหนด Path หลักของ Applications
if [ -L "$BASE_DIR" ]; then
    APPS_DIR=$(readlink -f "$BASE_DIR")
else
    APPS_DIR="$BASE_DIR"
fi

cd "$APPS_DIR" || exit 1

echo "-----------------------------------------------------------------" | tee -a "$LOG_FILE"
echo "⬇️  Step 1: Downloading plugin file..." | tee -a "$LOG_FILE"
echo "URL: $DOWNLOAD_URL" | tee -a "$LOG_FILE"

# โหลดไฟล์ลงมาที่ Server (-q คือซ่อนรายละเอียดการโหลด, -O คือตั้งชื่อไฟล์ปลายทาง)
wget -q -O "$ZIP_FILE" "$DOWNLOAD_URL"

# ตรวจสอบว่าโหลดสำเร็จและไฟล์มีขนาดมากกว่า 0 byte หรือไม่
if [ ! -s "$ZIP_FILE" ]; then
    echo "❌ Error: Failed to download the file or file is empty." | tee -a "$LOG_FILE"
    exit 1
fi
echo "✅ Download successful! File saved temporarily." | tee -a "$LOG_FILE"

# --- 2) การนับยอดก่อนเริ่ม (Pre-Scan Count) ---
PRE_COUNT=$(find . -maxdepth 1 -type d ! -name "." ! -name "applications" | wc -l)

echo "-----------------------------------------------------------------" | tee -a "$LOG_FILE"
echo "🚀 Step 2: Mass Install Process started at $(date)" | tee -a "$LOG_FILE"
echo "Total folders to check: $PRE_COUNT" | tee -a "$LOG_FILE"
echo "-----------------------------------------------------------------" | tee -a "$LOG_FILE"
printf "%-22s | %-28s | %-12s\n" "Folder Name" "Domain" "Status" | tee -a "$LOG_FILE"
echo "-----------------------------------------------------------------" | tee -a "$LOG_FILE"

# --- 3) เริ่มการ Scan และ Install ---
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
        
        # ตรวจสอบว่าเป็น WP และดึง Domain
        DOMAIN=$(wp option get home --skip-plugins --skip-themes --allow-root 2>/dev/null | sed 's|^https*://||')

        if [ -n "$DOMAIN" ]; then
            ((WP_SITES_FOUND++))
            
            # เช็คว่ามีปลั๊กอินอยู่แล้ว จึงทำการติดตั้งทับ
            if wp plugin is-installed "$PLUGIN_SLUG" --allow-root 2>/dev/null; then
                
                # สั่งติดตั้งจากไฟล์ ZIP ที่โหลดมา (ใช้ --force เพื่อทับไฟล์เดิม)
                if wp plugin install "$ZIP_FILE" --activate --force --allow-root >> "$LOG_FILE" 2>&1; then
                    
                    chown -R www-data:www-data "$SITE_PATH/wp-content/plugins/$PLUGIN_SLUG" 2>/dev/null
                    
                    # --- CLEANUP ---
                    wp option list --search="*blocksy*" --field=option_name --allow-root 2>/dev/null | grep -i "notice\|update\|version" | xargs -I {} wp option delete {} --allow-root >> "$LOG_FILE" 2>&1
                    wp transient delete --all --allow-root >> "$LOG_FILE" 2>&1
                    wp cache flush --allow-root >> "$LOG_FILE" 2>&1
                    
                    wp plugin is-active litespeed-cache --allow-root 2>/dev/null && wp litespeed-purge all --allow-root >> "$LOG_FILE" 2>&1
                    wp plugin is-active wp-rocket --allow-root 2>/dev/null && wp rocket clean --allow-root >> "$LOG_FILE" 2>&1
                    # ---------------

                    printf "%-22s | %-28s | %-12s\n" "$APP_NAME" "$DOMAIN" "✅ Installed" | tee -a "$LOG_FILE"
                    ((UPDATE_SUCCESS++))
                else
                    printf "%-22s | %-28s | %-12s\n" "$APP_NAME" "$DOMAIN" "❌ Failed" | tee -a "$LOG_FILE"
                    FAILED_LIST+="- $APP_NAME (Install failed)\n"
                fi
            else
                printf "%-22s | %-28s | %-12s\n" "$APP_NAME" "$DOMAIN" "⏭️ Skip" | tee -a "$LOG_FILE"
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

# ลบไฟล์ ZIP ทิ้งหลังจากติดตั้งเสร็จทุกเว็บแล้ว เพื่อไม่ให้รก Server
rm -f "$ZIP_FILE"

# --- 4) การนับยอดหลังทำงานเสร็จ (Post-Scan Summary) ---
echo "-----------------------------------------------------------------" | tee -a "$LOG_FILE"
echo "✅ Installation Process Completed!" | tee -a "$LOG_FILE"
echo "🗑️ Temporary ZIP file removed." | tee -a "$LOG_FILE"
echo "-----------------------------------------------------------------" | tee -a "$LOG_FILE"
echo "Total folders found         : $PRE_COUNT" | tee -a "$LOG_FILE"
echo "WordPress sites detected    : $WP_SITES_FOUND" | tee -a "$LOG_FILE"
echo "Successfully installed      : $UPDATE_SUCCESS" | tee -a "$LOG_FILE"

if [ -n "$FAILED_LIST" ]; then
    echo "-----------------------------------------------------------------" | tee -a "$LOG_FILE"
    echo "⚠️  Details of folders with issues:" | tee -a "$LOG_FILE"
    echo -e "$FAILED_LIST" | tee -a "$LOG_FILE"
fi
echo "-----------------------------------------------------------------" | tee -a "$LOG_FILE"
echo "Log saved to: $LOG_FILE"
