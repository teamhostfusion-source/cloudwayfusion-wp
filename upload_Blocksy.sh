#!/bin/bash                                         

USER_HOME="$HOME"
PLUGIN_SLUG="blocksy-companion-pro"
GITHUB_URL="https://github.com/teamhostfusion-source/cloudwayfusion-wp/raw/main/blocksy-companion-pro.zip"

TEMP_ZIP_NAME="${PLUGIN_SLUG}_temp.zip"
DOWNLOAD_DEST="$USER_HOME/$TEMP_ZIP_NAME"
LOG_FILE="$USER_HOME/install_blocksy_$(date +%Y%m%d_%H%M%S).txt"

> "$LOG_FILE"

echo "-----------------------------------------------------------------" | tee -a "$LOG_FILE"
echo "⬇️  Step 1: Downloading Master File..." | tee -a "$LOG_FILE"
wget -q -O "$DOWNLOAD_DEST" "$GITHUB_URL"

if [[ ! -s "$DOWNLOAD_DEST" ]] || ! unzip -t "$DOWNLOAD_DEST" >/dev/null 2>&1; then
    echo "❌ Error: โหลดไฟล์ไม่สำเร็จ หรือไฟล์ ZIP เสีย" | tee -a "$LOG_FILE"
    rm -f "$DOWNLOAD_DEST"
    exit 1
fi
echo "✅ Master ZIP verified at: $DOWNLOAD_DEST" | tee -a "$LOG_FILE"

BASE_DIR="$USER_HOME/applications"
[ -d "$BASE_DIR" ] || { echo "❌ Error: Directory $BASE_DIR not found"; exit 1; }

echo "-----------------------------------------------------------------" | tee -a "$LOG_FILE"
echo "🚀 Step 2: Mass Installation started at $(date)" | tee -a "$LOG_FILE"
printf "%-22s | %-28s | %-12s\n" "Folder Name" "Domain" "Status" | tee -a "$LOG_FILE"
echo "-----------------------------------------------------------------" | tee -a "$LOG_FILE"

# ตัวแปรเก็บสถิติ
SUCCESS_COUNT=0
SKIP_COUNT=0
FAIL_COUNT=0

# ลิสต์เฉพาะโฟลเดอร์ชั้นแรก ป้องกันการค้นหาลึกเกินไปจนค้าง
for APP_PATH in "$BASE_DIR"/*/; do
    APP_NAME=$(basename "$APP_PATH")
    SITE_PATH="${APP_PATH}public_html"

    # 1. ข้ามโฟลเดอร์ระบบหรือโฟลเดอร์ที่ไม่มี public_html
    if [[ "$APP_NAME" == "applications" ]] || [[ ! -d "$SITE_PATH" ]]; then
        continue
    fi

    # 2. [จุดสำคัญ] เช็กว่ามี wp-config.php หรือไม่ (ถ้าไม่มี แปลว่าไม่ใช่ WP ให้ข้ามเลย ประหยัดเวลามาก)
    if [[ ! -f "$SITE_PATH/wp-config.php" ]]; then
        printf "%-22s | %-28s | %-12s\n" "$APP_NAME" "---" "⚠️ Not WP" | tee -a "$LOG_FILE"
        ((SKIP_COUNT++))
        continue
    fi

    # 3. ดึงชื่อโดเมน (ให้เวลา 15 วินาที ถ้า WP-CLI ค้างให้ตัดจบ)
    DOMAIN=$(timeout 15s wp option get home --path="$SITE_PATH" --skip-plugins --skip-themes --allow-root 2>/dev/null | sed 's|^https*://||')

    if [[ -z "$DOMAIN" ]]; then
        printf "%-22s | %-28s | %-12s\n" "$APP_NAME" "---" "❌ Timeout/Err" | tee -a "$LOG_FILE"
        ((FAIL_COUNT++))
        continue
    fi

    # 4. ลบปลั๊กอินเดิม (ถ้ามี) แบบเงียบๆ
    timeout 15s wp plugin delete "$PLUGIN_SLUG" --path="$SITE_PATH" --allow-root >/dev/null 2>&1

    # 5. ติดตั้งและ Activate ปลั๊กอิน (ให้เวลา 45 วินาที เผื่อเว็บใหญ่แตกไฟล์นาน)
    if timeout 45s wp plugin install "$DOWNLOAD_DEST" --path="$SITE_PATH" --activate --allow-root >/dev/null 2>&1; then
        
        # คืนสิทธิ์ให้ www-data ป้องกันปัญหา Permission
        chown -R www-data:www-data "$SITE_PATH/wp-content/plugins/$PLUGIN_SLUG" 2>/dev/null
        
        # ล้าง Cache แบบปลอดภัย (ไม่โหลด theme/plugin ตัวอื่นมาขวาง)
        timeout 15s wp cache flush --path="$SITE_PATH" --skip-plugins --skip-themes --allow-root >/dev/null 2>&1

        printf "%-22s | %-28s | %-12s\n" "$APP_NAME" "$DOMAIN" "✅ Success" | tee -a "$LOG_FILE"
        ((SUCCESS_COUNT++))
    else
        printf "%-22s | %-28s | %-12s\n" "$APP_NAME" "$DOMAIN" "❌ Install Fail" | tee -a "$LOG_FILE"
        ((FAIL_COUNT++))
    fi

done

# ลบไฟล์ Master ZIP ทิ้ง
rm -f "$DOWNLOAD_DEST"

echo "-----------------------------------------------------------------" | tee -a "$LOG_FILE"
echo "📊 Summary Report" | tee -a "$LOG_FILE"
echo "-----------------------------------------------------------------" | tee -a "$LOG_FILE"
echo "✅ Success   : $SUCCESS_COUNT sites" | tee -a "$LOG_FILE"
echo "❌ Failed    : $FAIL_COUNT sites" | tee -a "$LOG_FILE"
echo "⚠️ Skipped   : $SKIP_COUNT sites" | tee -a "$LOG_FILE"
echo "-----------------------------------------------------------------" | tee -a "$LOG_FILE"
echo "Log file saved to: $LOG_FILE"
