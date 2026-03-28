#!/bin/bash
# Bzz - Pro Version (Optimized for Blocksy, JSON Data & Global Search)
LOGIN_REDIRECT_URL=""
REGISTER_REDIRECT_URL=""
NEW_CONTACT_URL=""
OLD_URL_TARGET=""
NEW_URL_VALUE=""
FIX_SHORTCUT_URL=""

while getopts "L:R:C:O:N:F:" opt; do
  case $opt in
    L) LOGIN_REDIRECT_URL="$OPTARG" ;; 
    R) REGISTER_REDIRECT_URL="$OPTARG" ;; 
    C) NEW_CONTACT_URL="$OPTARG" ;; 
    O) OLD_URL_TARGET="$OPTARG" ;; 
    N) NEW_URL_VALUE="$OPTARG"  ;; 
    F) FIX_SHORTCUT_URL="$OPTARG" ;; 
    \?) exit 1 ;;
  esac
done

# เช็ค Argument
if [ -z "$LOGIN_REDIRECT_URL" ] && [ -z "$REGISTER_REDIRECT_URL" ] && [ -z "$NEW_CONTACT_URL" ] && [ -z "$OLD_URL_TARGET" ] && [ -z "$FIX_SHORTCUT_URL" ]; then
    echo "Usage: $0 [-L URL] [-R URL] [-C URL] [-F new_shortcut_url] [-O old_url -N new_url]"
    exit 1
fi

# เช็คว่ามีคำสั่ง wp-cli หรือไม่
if ! command -v wp &> /dev/null; then
    echo "Error: wp-cli is not installed or not in PATH."
    exit 1
fi

BASE_DIR="$HOME/applications"
LOG_FILE="$HOME/update_wp.log"

> "$LOG_FILE"
echo "------ 1Update started at $(date) ------" >> "$LOG_FILE"

ALL_SITES_LIST=$(find -L "$BASE_DIR" -name "wp-config.php" ! -path "*/.*")
TOTAL_SITES=$(echo "$ALL_SITES_LIST" | grep -c "wp-config.php")

if [ "$TOTAL_SITES" -eq 0 ]; then
    echo "Error: No WordPress installations found in $BASE_DIR." | tee -a "$LOG_FILE"
    exit 1
fi

echo "Found $TOTAL_SITES WordPress Installations" | tee -a "$LOG_FILE"

SUCCESS_COUNT=0
FAILED_COUNT=0
CURRENT_INDEX=0

while read -r config_path; do
    [ -z "$config_path" ] && continue
    
    ((CURRENT_INDEX++))
    SITE_PATH=$(dirname "$config_path")
    DISPLAY_NAME=$(echo "$SITE_PATH" | sed "s|$BASE_DIR/||")
    
    (
        cd "$SITE_PATH" || { exit 1; }
        
        DOMAIN=$(wp option get home --allow-root 2>/dev/null || echo "Unknown Domain")
        echo "------------------------------------------------" | tee -a "$LOG_FILE"
        echo "[$CURRENT_INDEX/$TOTAL_SITES] Site: $DOMAIN ($DISPLAY_NAME)" | tee -a "$LOG_FILE"

        # --- ฟังก์ชัน 1: อัปเดตลิงก์ในหน้า Page (Content) ---
        update_page_link() {
            local slug=$1; local new_url=$2; local label=$3
            local page_id=$(wp post list --post_type=page --post_status=publish --fields=ID,post_name --format=csv --allow-root | grep -E ",($slug|-2|,($slug))" | cut -d',' -f1 | head -n 1)
            
            if [ -n "$page_id" ]; then
                local old_content=$(wp post get "$page_id" --field=post_content --allow-root)
                
                # รองรับทั้ง single quote (') และ double quote (") และข้อมูล JSON ของ Gutenberg
                if echo "$old_content" | grep -qE "href=['\"]"; then
                    # ใช้ sed แทนที่ URL ใน href ทั้งหมดในหน้านั้น (Force Update)
                    local new_content=$(echo "$old_content" | sed -E "s|href=['\"][^'\"]*['\"]|href=\"$new_url\"|g")
                    wp post update "$page_id" --post_content="$new_content" --allow-root >> "$LOG_FILE" 2>&1
                    echo "    [OK] Page: $label ($slug) links forced to new URL" | tee -a "$LOG_FILE"
                else
                    echo "    [SKIP] Page: $label ($slug) has no standard href links" | tee -a "$LOG_FILE"
                fi
            fi
        }

        # --- ฟังก์ชัน 2: จัดการ Shortcut Bar (Blocksy - JSON Escaped Support) ---
        update_shortcuts_bar() {
            local target_url=$1   # ลิงก์ใหม่
            local search_url=$2   # ลิงก์เดิม
            [ -z "$search_url" ] && search_url="https://google.com"

            echo "    [BT] Targeting Blocksy Shortcut Bar: '$search_url' -> '$target_url'..." | tee -a "$LOG_FILE"
            
            # 1. แทนที่แบบปกติ (Plain Text)
            wp search-replace "$search_url" "$target_url" wp_options --include-columns=option_value --allow-root >> "$LOG_FILE" 2>&1
            
            # 2. แทนที่แบบ JSON Escaped (สำคัญมากสำหรับ Blocksy)
            # แปลง https://old.com เป็น https:\/\/old.com
            local escaped_search=$(echo "$search_url" | sed 's/\//\\\//g')
            local escaped_target=$(echo "$target_url" | sed 's/\//\\\//g')
            
            wp search-replace "$escaped_search" "$escaped_target" wp_options --include-columns=option_value --allow-root >> "$LOG_FILE" 2>&1
            
            echo "    [OK] Shortcut Bar processed (Text & JSON)" | tee -a "$LOG_FILE"
        }

        # --- ฟังก์ชัน 3: ค้นหาและแทนที่ทั้งฐานข้อมูล (Global - JSON Support) ---
        update_option_url() {
            local old_url=$1; local new_url=$2
            if [ -n "$old_url" ] && [ -n "$new_url" ]; then
                echo "    [DB] Global Replace: '$old_url' -> '$new_url'..." | tee -a "$LOG_FILE"
                
                # 1. Normal Replace
                wp search-replace "$old_url" "$new_url" --all-tables --allow-root >> "$LOG_FILE" 2>&1
                
                # 2. JSON Escaped Replace (สำหรับ URL ที่ซ่อนใน Config ของ Page Builders / Themes)
                local escaped_old=$(echo "$old_url" | sed 's/\//\\\//g')
                local escaped_new=$(echo "$new_url" | sed 's/\//\\\//g')
                wp search-replace "$escaped_old" "$escaped_new" --all-tables --allow-root >> "$LOG_FILE" 2>&1
                
                echo "    [OK] Global database updated" | tee -a "$LOG_FILE"
            fi
        }

        # เริ่มต้นการทำงานตามเงื่อนไข
        [ -n "$LOGIN_REDIRECT_URL" ] && update_page_link "login" "$LOGIN_REDIRECT_URL" "Login"
        [ -n "$REGISTER_REDIRECT_URL" ] && update_page_link "register" "$REGISTER_REDIRECT_URL" "Register"
        [ -n "$NEW_CONTACT_URL" ] && update_page_link "contact-us" "$NEW_CONTACT_URL" "Contact"
        
        [ -n "$FIX_SHORTCUT_URL" ] && update_shortcuts_bar "$FIX_SHORTCUT_URL" "$OLD_URL_TARGET"
        
        [ -n "$OLD_URL_TARGET" ] && [ -n "$NEW_URL_VALUE" ] && update_option_url "$OLD_URL_TARGET" "$NEW_URL_VALUE"
        
        # --- ล้าง Cache ---
        echo "    [CACHE] Flushing Cache..." | tee -a "$LOG_FILE"
        wp cache flush --allow-root &>/dev/null
        wp varnish purge --allow-root &>/dev/null 2>&1 
        
        exit 0
    )

    if [ $? -eq 0 ]; then ((SUCCESS_COUNT++)); else ((FAILED_COUNT++)); fi

done <<< "$ALL_SITES_LIST"

echo "------------------------------------------------" | tee -a "$LOG_FILE"
echo "Summary: Success $SUCCESS_COUNT | Failed $FAILED_COUNT" | tee -a "$LOG_FILE"
echo "Detailed Log: $LOG_FILE"
