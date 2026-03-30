#!/bin/bash                                         

USER_HOME="$HOME"
PLUGIN_SLUG="blocksy-companion-pro"

# --- 1) ตั้งค่าชื่อไฟล์ที่อัปโหลดไว้แล้ว ---
SEARCH_FILENAME="blocksy-companion-pro.zip" 
LOG_FILE="$USER_HOME/install_blocksy_$(date +%Y%m%d_%H%M%S).txt"

> "$LOG_FILE"
echo "-----------------------------------------------------------------" | tee -a "$LOG_FILE"
echo "🔍 Step 1: Searching and Verifying the ZIP file..." | tee -a "$LOG_FILE"

# ค้นหาไฟล์ .zip ภายใน Home Directory
ZIP_FILE=$(find "$USER_HOME" -maxdepth 3 -type f -name "$SEARCH_FILENAME" 2>/dev/null | head -n 1)

if [ -z "$ZIP_FILE" ]; then
    echo "❌ Error: ไม่พบ-ไฟล์ $SEARCH_FILENAME ในระบบ" | tee -a "$LOG_FILE"
    echo "👉 กรุณาตรวจสอบว่าอัปโหลดไฟล์มาแล้ว และชื่อไฟล์ตรงกับตัวพิมพ์เล็ก-ใหญ่ทุกตัวอักษร" | tee -a "$LOG_FILE"
    exit 1
fi

# ตรวจสอบว่าเป็นไฟล์ ZIP ที่สมบูรณ์หรือไม่ (ป้องกันไฟล์เสีย)
if ! unzip -t "$ZIP_FILE" >/dev/null 2>&1; then
    echo "❌ Error: ไฟล์ $SEARCH_FILENAME ที่พบ ไม่ใช่ไฟล์ ZIP ที่สมบูรณ์ หรือไฟล์อาจจะเสียจากการอัปโหลด" | tee -a "$LOG_FILE"
    exit 1
fi

echo "✅ Found and Verified valid ZIP file at: $ZIP_FILE" | tee -a "$LOG_FILE"

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
echo "🚀 Step 2: Mass Install Process started at $(date)" | tee -a "$LOG_FILE"
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
        
        # ตรวจสอบว่าเป็น WP และดึง Domain
        DOMAIN=$(wp option get home --skip-plugins --skip-themes --allow-root 2>/dev/null | sed 's|^https*://||')

        if [ -n "$DOMAIN" ]; then
            ((WP_SITES_FOUND++))
            
            # เช็คว่ามีปลั๊กอินอยู่แล้วถึงจะทำการติดตั้งทับ
            if wp plugin is-installed "$PLUGIN_SLUG" --allow-root 2>/dev/null; then
                
                # ลบของเก่าออกก่อน (เพื่อความสะอาดและกัน Error โฟลเดอร์ชนกัน)
                wp plugin delete "$PLUGIN_SLUG" --allow-root >> "$LOG_FILE" 2>&1
                
                # สั่งติดตั้งและดักจับข้อความ Error ไว้ในตัวแปร INSTALL_OUTPUT
                INSTALL_OUTPUT=$(wp plugin install "$ZIP_FILE" --allow-root 2>&1)
                INSTALL_STATUS=$?
                
                if [ $INSTALL_STATUS -eq 0 ]; then
                    
                    # จัดการแก้ชื่อโฟลเดอร์ให้ถูกต้อง (กรณีไฟล์ Zip มาจาก GitHub)
                    GITHUB_FOLDER=$(ls "$SITE_PATH/wp-content/plugins/" | grep "^$PLUGIN_SLUG-")
                    if [ ! -z "$GITHUB_FOLDER" ]; then
                        mv "$SITE_PATH/wp-content/plugins/$GITHUB_FOLDER" "$SITE_PATH/wp-content/plugins/$PLUGIN_SLUG"
                    fi
                    
                    # สั่ง Activate และคืนสิทธิ์ให้ www-data
                    wp plugin activate "$PLUGIN_SLUG" --allow-root >> "$LOG_FILE" 2>&1
                    chown -R www-data:www-data "$SITE_PATH/wp-content/plugins/$PLUGIN_SLUG" 2>/dev/null
                    
                    # --- CLEANUP ฐานข้อมูลและแคช ---
                    wp option list --search="*blocksy*" --field=option_name --allow-root 2>/dev/null | grep -i "notice\|update\|version" | xargs -I {} wp option delete {} --allow-root >> "$LOG_FILE" 2>&1
                    wp transient delete --all --allow-root >> "$LOG_FILE" 2>&1
                    wp cache flush --allow-root >> "$LOG_FILE" 2>&1
                    wp plugin is-active litespeed-cache --allow-root 2>/dev/null && wp litespeed-purge all --allow-root >> "$LOG_FILE" 2>&1
                    wp plugin is-active wp-rocket --allow-root 2>/dev/null && wp rocket clean --allow-root >> "$LOG_FILE" 2>&1

                    printf "%-22s | %-28s | %-12s\n" "$APP_NAME" "$DOMAIN" "✅ Installed" | tee -a "$LOG_FILE"
                    ((UPDATE_SUCCESS++))
                else
                    printf "%-22s | %-28s | %-12s\n" "$APP_NAME" "$DOMAIN" "❌ Failed" | tee -a "$LOG_FILE"
                    # ดึง Error บรรทัดแรกสุดมาเก็บไว้โชว์ตอนท้าย
                    ERROR_MSG=$(echo "$INSTALL_OUTPUT" | grep "Error" | head -n 1)
                    FAILED_LIST+="- $APP_NAME: $ERROR_MSG\n"
                fi
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
echo "✅ Installation Process Completed!" | tee -a "$LOG_FILE"
echo "-----------------------------------------------------------------" | tee -a "$LOG_FILE"
echo "Total folders found         : $PRE_COUNT" | tee -a "$LOG_FILE"
echo "WordPress sites detected    : $WP_SITES_FOUND" | tee -a "$LOG_FILE"
echo "Successfully installed      : $UPDATE_SUCCESS" | tee -a "$LOG_FILE"

if [ -n "$FAILED_LIST" ]; then
    echo "-----------------------------------------------------------------" | tee -a "$LOG_FILE"
    echo "⚠️  สาเหตุที่ติดตั้งไม่ผ่าน (Error Details):" | tee -a "$LOG_FILE"
    echo -e "$FAILED_LIST" | tee -a "$LOG_FILE"
fi
echo "-----------------------------------------------------------------" | tee -a "$LOG_FILE"
