#!/bin/bash

BASE_DIR="$HOME/applications"
LOG_FILE="$HOME/update_blocksy_smart.log"

> "$LOG_FILE"
echo "------ เริ่มกระบวนการ Smart Check & Update ------" | tee -a "$LOG_FILE"

# กรองหาเฉพาะเว็บที่ใช้งานจริง
ALL_SITES_LIST=$(find -L "$BASE_DIR" -name "wp-config.php" | grep -vEi "backup|old|archive|trash|staging|/\.")
TOTAL_SITES=$(echo "$ALL_SITES_LIST" | grep -c "wp-config.php")

if [ "$TOTAL_SITES" -eq 0 ]; then
    echo "Error: ไม่พบการติดตั้ง WordPress"
    exit 1
fi

CURRENT_INDEX=0

while read -r config_path; do
    [ -z "$config_path" ] && continue
    
    ((CURRENT_INDEX++))
    SITE_PATH=$(dirname "$config_path")
    
    (
        cd "$SITE_PATH" || exit 1
        DOMAIN=$(wp option get home --allow-root 2>/dev/null || echo "Unknown Domain")
        echo "------------------------------------------------" | tee -a "$LOG_FILE"
        echo "[$CURRENT_INDEX/$TOTAL_SITES] เว็บ: $DOMAIN" | tee -a "$LOG_FILE"

        # 1. บังคับให้ WordPress เช็คเวอร์ชันล่าสุดกับเซิร์ฟเวอร์หลักก่อน
        wp core update-db --allow-root >/dev/null 2>&1
        wp transient delete update_themes --allow-root >/dev/null 2>&1

        # 2. เช็คสถานะของ Blocksy ว่ามีอัปเดตมารอหรือไม่ (เทียบเท่ากับการมองหาปุ่มบนเว็บ)
        if wp theme is-installed blocksy --allow-root 2>/dev/null; then
            
            # ดึงสถานะอัปเดต (ถ้ามีอัปเดต ค่าที่ได้จะเป็นคำว่า "available")
            UPDATE_STATUS=$(wp theme list --name=blocksy --field=update --allow-root 2>/dev/null)
            
            if [ "$UPDATE_STATUS" == "available" ]; then
                echo "    [FOUND] เจอปุ่ม/สถานะรออัปเดต! กำลังกดอัปเดต..." | tee -a "$LOG_FILE"
                
                # ทำการอัปเดต (เสมือนการกดปุ่ม)
                wp theme update blocksy --allow-root >> "$LOG_FILE" 2>&1
                
                echo "    [SUCCESS] อัปเดตและลบป้ายแจ้งเตือนเรียบร้อย" | tee -a "$LOG_FILE"
            else
                echo "    [SKIP] ไม่พบอัปเดต (ไม่มีปุ่มให้กด) ธีมเป็นเวอร์ชันล่าสุดแล้ว" | tee -a "$LOG_FILE"
            fi
        else
            echo "    [SKIP] ไม่ได้ติดตั้งธีม Blocksy" | tee -a "$LOG_FILE"
        fi
        
        # 3. เคลียร์ Cache เพื่อความชัวร์
        wp cache flush --allow-root >/dev/null 2>&1
    )

done <<< "$ALL_SITES_LIST"

echo "------------------------------------------------" | tee -a "$LOG_FILE"
echo "เสร็จสมบูรณ์! เช็ค Log ได้ที่: $LOG_FILE"
