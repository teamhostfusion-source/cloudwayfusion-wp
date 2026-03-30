#!/bin/bash                                         

USER_HOME="$HOME"
PLUGIN_SLUG="blocksy-companion-pro"

# --- 1) ตั้งค่า GitHub (ใช้ Direct Link / Raw) ---
# เปลี่ยน URL ให้เป็นแบบ raw.githubusercontent.com เพื่อให้โหลดไฟล์ ZIP ได้โดยตรง
GITHUB_URL="https://github.com/teamhostfusion-source/cloudwayfusion-wp/raw/main/blocksy-companion-pro.zip"
# หากเป็น Private Repo ให้ใช้: GITHUB_URL="https://<TOKEN>@raw.githubusercontent.com/..."

TEMP_ZIP_NAME="${PLUGIN_SLUG}_temp.zip"
DOWNLOAD_DEST="$USER_HOME/$TEMP_ZIP_NAME"
LOG_FILE="$USER_HOME/install_blocksy_$(date +%Y%m%d_%H%M%S).txt"

> "$LOG_FILE"

echo "-----------------------------------------------------------------" | tee -a "$LOG_FILE"
echo "⬇️  Step 1: Downloading Master File..." | tee -a "$LOG_FILE"
echo "-----------------------------------------------------------------" | tee -a "$LOG_FILE"

# โหลดไฟล์มาเก็บไว้ที่ Home ครั้งเดียว
wget -q -O "$DOWNLOAD_DEST" "$GITHUB_URL"

# ตรวจสอบไฟล์ ZIP ว่าโหลดมาสมบูรณ์ไหม
if [[ ! -s "$DOWNLOAD_DEST" ]] || ! unzip -t "$DOWNLOAD_DEST" >/dev/null 2>&1; then
    echo "❌ Error: โหลดไฟล์ไม่สำเร็จ หรือไฟล์ ZIP เสีย (ตรวจสอบ URL/Token)" | tee -a "$LOG_FILE"
    rm -f "$DOWNLOAD_DEST"
    exit 1
fi

echo "✅ Master ZIP verified at: $DOWNLOAD_DEST" | tee -a "$LOG_FILE"

# --- 2) กำหนด Path และเริ่มกระบวนการกระจายไฟล์ ---
BASE_DIR="$USER_HOME/applications"
if [ -L "$BASE_DIR" ]; then
    APPS_DIR=$(readlink -f "$BASE_DIR")
else
    APPS_DIR="$BASE_DIR"
fi

cd "$APPS_DIR" || { echo "❌ Error: ไม่พบโฟลเดอร์ applications"; exit 1; }

PRE_COUNT=$(find . -maxdepth 1 -type d ! -name "." ! -name "applications" | wc -l)

echo "-----------------------------------------------------------------" | tee -a "$LOG_FILE"
echo "🚀 Step 2: Mass Installation started at $(date)" | tee -a "$LOG_FILE"
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
            
            # เช็กว่ามีของเก่าไหมเพื่อแสดงสถานะใน Log
            if wp plugin is-installed "$PLUGIN_SLUG" --allow-root 2>/dev/null; then
                # ลบของเก่าออกก่อน
                wp plugin delete "$PLUGIN_SLUG" --allow-root >> "$LOG_FILE" 2>&1
                STATUS_TEXT="✅ Updated"
            else
                STATUS_TEXT="✅ Installed"
            fi
            
            # ติดตั้งปลั๊กอิน (ชี้ไปที่ไฟล์ ZIP ตัวแม่ที่โหลดไว้ตอนแรก)
            INSTALL_OUTPUT=$(wp plugin install "$DOWNLOAD_DEST" --allow-root 2>&1)
            
            if [ $? -eq 0 ]; then
                # จัดการชื่อโฟลเดอร์กรณี GitHub แตกไฟล์มาแล้วติด suffix
                GITHUB_FOLDER=$(ls "$SITE_PATH/wp-content/plugins/" | grep "^$PLUGIN_SLUG-")
                if [ -n "$GITHUB_FOLDER" ]; then
                    mv "$SITE_PATH/wp-content/plugins/$GITHUB_FOLDER" "$SITE_PATH/wp-content/plugins/$PLUGIN_SLUG"
                fi
                
                wp plugin activate "$PLUGIN_SLUG" --allow-root >> "$LOG_FILE" 2>&1
                chown -R www-data:www-data "$SITE_PATH/wp-content/plugins/$PLUGIN_SLUG" 2>/dev/null
                
                # ล้าง Cache ต่างๆ
                wp transient delete --all --allow-root >> "$LOG_FILE" 2>&1
                wp cache flush --allow-root >> "$LOG_FILE" 2>&1

                printf "%-22s | %-28s | %-12s\n" "$APP_NAME" "$DOMAIN" "$STATUS_TEXT" | tee -a "$LOG_FILE"
                ((INSTALL_SUCCESS++))
            else
                printf "%-22s | %-28s | %-12s\n" "$APP_NAME" "$DOMAIN" "❌ Error" | tee -a "$LOG_FILE"
                ERROR_DETAIL=$(echo "$INSTALL_OUTPUT" | grep "Error" | head -n 1)
                FAILED_LIST+="- $APP_NAME: $ERROR_DETAIL\n"
            fi
        else
            printf "%-22s | %-28s | %-12s\n" "$APP_NAME" "---" "⚠️ Not WP" | tee -a "$LOG_FILE"
        fi
        cd "$APPS_DIR"
    else
        printf "%-22s | %-28s | %-12s\n" "$APP_NAME" "---" "⚠️ No Path" | tee -a "$LOG_FILE"
    fi
done

# ลบไฟล์ตัวแม่ทิ้งหลังเสร็จสิ้นกระบวนการทั้งหมด
rm -f "$DOWNLOAD_DEST"

# --- 3) สรุปผล ---
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
echo "Log: $LOG_FILE"
