#!/bin/bash                                         

USER_HOME="$HOME"
PLUGIN_SLUG="blocksy-companion-pro"
GITHUB_URL="https://raw.githubusercontent.com/teamhostfusion-source/cloudwayfusion-wp/main/blocksy-companion-pro.zip"

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
echo "✅ Master ZIP verified." | tee -a "$LOG_FILE"

BASE_DIR="$USER_HOME/applications"
[ -d "$BASE_DIR" ] || { echo "❌ Error: Directory $BASE_DIR not found"; exit 1; }

echo "-----------------------------------------------------------------" | tee -a "$LOG_FILE"
echo "🚀 Step 2: Mass Installation started..." | tee -a "$LOG_FILE"
printf "%-22s | %-28s | %-12s\n" "Folder Name" "Domain" "Status" | tee -a "$LOG_FILE"
echo "-----------------------------------------------------------------" | tee -a "$LOG_FILE"

SUCCESS_COUNT=0
SKIP_COUNT=0
FAIL_COUNT=0

for APP_PATH in "$BASE_DIR"/*/; do
    APP_NAME=$(basename "$APP_PATH")
    SITE_PATH="${APP_PATH}public_html"

    if [[ "$APP_NAME" == "applications" ]] || [[ ! -d "$SITE_PATH" ]]; then
        continue
    fi

    if [[ ! -f "$SITE_PATH/wp-config.php" ]]; then
        printf "%-22s | %-28s | %-12s\n" "$APP_NAME" "---" "⚠️ Not WP" | tee -a "$LOG_FILE"
        ((SKIP_COUNT++))
        continue
    fi

    # 1. ใช้ ( cd ... && wp ... ) เพื่อให้เหมือนการเข้าไปรันด้วยมือจริงๆ มากที่สุด
    # ถอด timeout และ skip-plugins ออกตอนดึงชื่อเว็บ ป้องกัน WP-CLI Crash
    DOMAIN=$(cd "$SITE_PATH" && wp option get home --allow-root 2>/dev/null | sed 's|^https*://||' | tr -d '\r\n ')

    if [[ -z "$DOMAIN" ]]; then
        printf "%-22s | %-28s | %-12s\n" "$APP_NAME" "---" "❌ WP-CLI Err" | tee -a "$LOG_FILE"
        ((FAIL_COUNT++))
        continue
    fi

    # 2. กระบวนการลบและติดตั้ง (ครอบด้วยวงเล็บเพื่อป้องกันการหลง Directory)
    (
        cd "$SITE_PATH" || exit
        
        # ลบของเก่า
        wp plugin is-installed "$PLUGIN_SLUG" --allow-root 2>/dev/null && \
        wp plugin delete "$PLUGIN_SLUG" --allow-root >/dev/null 2>&1
        
        # ติดตั้งและ Activate (ใช้ timeout 60s ป้องกันค้างตอนแตกไฟล์)
        if timeout 60s wp plugin install "$DOWNLOAD_DEST" --activate --allow-root >/dev/null 2>&1; then
            chown -R www-data:www-data "$SITE_PATH/wp-content/plugins/$PLUGIN_SLUG" 2>/dev/null
            wp cache flush --allow-root >/dev/null 2>&1
            printf "%-22s | %-28s | %-12s\n" "$APP_NAME" "$DOMAIN" "✅ Success" | tee -a "$LOG_FILE"
            # ใช้ echo ส่งค่ากลับออกมาเพื่อบวกตัวเลข
            echo "SUCCESS" > "$SITE_PATH/tmp_status.txt"
        else
            printf "%-22s | %-28s | %-12s\n" "$APP_NAME" "$DOMAIN" "❌ Install Fail" | tee -a "$LOG_FILE"
            echo "FAIL" > "$SITE_PATH/tmp_status.txt"
        fi
    )

    # เช็กผลลัพธ์จาก Subshell เพื่ออัปเดตสถิติ
    if [[ -f "$SITE_PATH/tmp_status.txt" ]]; then
        STATUS=$(cat "$SITE_PATH/tmp_status.txt")
        [[ "$STATUS" == "SUCCESS" ]] && ((SUCCESS_COUNT++))
        [[ "$STATUS" == "FAIL" ]] && ((FAIL_COUNT++))
        rm -f "$SITE_PATH/tmp_status.txt"
    fi

done

rm -f "$DOWNLOAD_DEST"

echo "-----------------------------------------------------------------" | tee -a "$LOG_FILE"
echo "✅ Success   : $SUCCESS_COUNT sites" | tee -a "$LOG_FILE"
echo "❌ Failed    : $FAIL_COUNT sites" | tee -a "$LOG_FILE"
echo "⚠️ Skipped   : $SKIP_COUNT sites" | tee -a "$LOG_FILE"
echo "-----------------------------------------------------------------" | tee -a "$LOG_FILE"
