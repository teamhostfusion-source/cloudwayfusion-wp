#!/bin/bash                                         

USER_HOME="$HOME"
PLUGIN_SLUG="blocksy-companion-pro"

# --- 1) ตั้งค่าระบบและ URL ---
# ตรวจสอบ Token ให้ชัวร์ว่ายังไม่หมดอายุ และมีสิทธิ์อ่าน repo
GITHUB_URL="https://github.com/teamhostfusion-source/cloudwayfusion-wp/blob/main/blocksy-companion-pro.2.1.37.zip"

SEARCH_FILENAME="${PLUGIN_SLUG}_temp.zip"
DOWNLOAD_DEST="$USER_HOME/$SEARCH_FILENAME"
LOG_FILE="$USER_HOME/install_blocksy_$(date +%Y%m%d_%H%M%S).txt"

> "$LOG_FILE"
echo "-----------------------------------------------------------------" | tee -a "$LOG_FILE"
echo "⬇️  Step 1: Downloading plugin from GitHub..." | tee -a "$LOG_FILE"

# โหลดไฟล์ลงมาที่ Server
wget -q -O "$DOWNLOAD_DEST" "$GITHUB_URL"

if [ ! -s "$DOWNLOAD_DEST" ]; then
    echo "❌ Error: โหลดไฟล์ไม่สำเร็จ หรือไฟล์ว่างเปล่า" | tee -a "$LOG_FILE"
    exit 1
fi

echo "-----------------------------------------------------------------" | tee -a "$LOG_FILE"
echo "🔍 Step 2: Searching and Verifying the ZIP file..." | tee -a "$LOG_FILE"

# ค้นหาไฟล์ที่เพิ่งโหลดมา
ZIP_FILE=$(find "$USER_HOME" -maxdepth 2 -type f -name "$SEARCH_FILENAME" 2>/dev/null | head -n 1)

if [ -z "$ZIP_FILE" ]; then
    echo "❌ Error: ไม่พบไฟล์ $SEARCH_FILENAME ในระบบ" | tee -a "$LOG_FILE"
    exit 1
fi

# **จุดสำคัญ:** ตรวจสอบว่าเป็นไฟล์ ZIP ที่สมบูรณ์หรือไม่
if ! unzip -t "$ZIP_FILE" >/dev/null 2>&1; then
    echo "❌ Error: ไฟล์ที่โหลดมาพัง หรือไม่ใช่ ZIP ของจริง!" | tee -a "$LOG_FILE"
    echo "👉 สาเหตุที่เป็นไปได้: Token ของ GitHub ผิด, หมดอายุ, หรือ URL ไม่ถูกต้อง (ระบบไปโหลดเอาหน้าเว็บ 404 มาแทน)" | tee -a "$LOG_FILE"
    rm -f "$ZIP_FILE" # ลบไฟล์ปลอมทิ้ง
    exit 1
fi

echo "✅ Found and Verified valid ZIP file at: $ZIP_FILE" | tee -a "$LOG_FILE"

# --- 3) กำหนด Path หลักของ Applications ---
BASE_DIR="$USER_HOME/applications"
if [ -L "$BASE_DIR" ]; then
    APPS_DIR=$(readlink -f "$BASE_DIR")
else
    APPS_DIR="$BASE_DIR"
fi

cd "$APPS_DIR" || exit 1

PRE_COUNT=$(find . -maxdepth 1 -type d ! -name "." ! -name "applications" | wc -l)

echo "-----------------------------------------------------------------" | tee -a "$LOG_FILE"
echo "🚀 Step 3: Mass Install Process started at $(date)" | tee -a "$LOG_FILE"
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
            
            if wp plugin is-installed "$PLUGIN_SLUG" --allow-root 2>/dev/null; then
                
                # ลบของเก่า
                wp plugin delete "$PLUGIN_SLUG" --allow-root >> "$LOG_FILE" 2>&1
                
                # **จุดสำคัญ:** สั่งติดตั้งและดักจับข้อความ Error ไว้ในตัวแปร
                INSTALL_OUTPUT=$(wp plugin install "$ZIP_FILE" --allow-root 2>&1)
                INSTALL_STATUS=$?
                
                if [ $INSTALL_STATUS -eq 0 ]; then
                    
                    # จัดการโฟลเดอร์ GitHub
                    GITHUB_FOLDER=$(ls "$SITE_PATH/wp-content/plugins/" | grep "^$PLUGIN_SLUG-")
                    if [ ! -z "$GITHUB_FOLDER" ]; then
                        mv "$SITE_PATH/wp-content/plugins/$GITHUB_FOLDER" "$SITE_PATH/wp-content/plugins/$PLUGIN_SLUG"
                    fi
                    
                    wp plugin activate "$PLUGIN_SLUG" --allow-root >> "$LOG_FILE" 2>&1
                    chown -R www-data:www-data "$SITE_PATH/wp-content/plugins/$PLUGIN_SLUG" 2>/dev/null
                    
                    # CLEANUP
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

rm -f "$ZIP_FILE"

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
