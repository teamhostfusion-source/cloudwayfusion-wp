#!/bin/bash
# bzz - Pro Version (Optimized for Blocksy, Global Search & Auto-Update)
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
    echo "Usage: $0 [-L URL] [-R URL] [-C URL] [-F new_url] [-O old_url -N new_url]"
    exit 1
fi

BASE_DIR="$HOME/applications"
LOG_FILE="$HOME/update_wp.log"

> "$LOG_FILE"
echo "------ Update started at $(date) ------" | tee -a "$LOG_FILE"

# ค้นหาทุกเว็บใน Path ที่กำหนด
ALL_SITES_LIST=$(find -L "$BASE_DIR" -name "wp-config.php" ! -path "*/.*")
TOTAL_SITES=$(echo "$ALL_SITES_LIST" | grep -c "wp-config.php")

if [ "$TOTAL_SITES" -eq 0 ]; then
    echo "Error: No WordPress installations found." | tee -a "$LOG_FILE"
    exit 1
fi

echo "Found $TOTAL_SITES WordPress sites" | tee -a "$LOG_FILE"

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

        # --- ฟังก์ชัน: อัปเดต Blocksy Theme แบบรอจนเสร็จ (เคลียร์ปุ่มแจ้งเตือน) ---
        echo "    [UPDATE] Updating Blocksy theme to the latest version..." | tee -a "$LOG_FILE"
        
        if wp theme is-installed blocksy --allow-root 2>/dev/null; then
            # ใช้คำสั่ง update (จะทำงานเหมือนการกดปุ่ม Update บนหน้าเว็บและรอจนเสร็จ)
            UPDATE_RESULT=$(wp theme update blocksy --allow-root 2>&1)
            echo "$UPDATE_RESULT" >> "$LOG_FILE"
            
            if echo "$UPDATE_RESULT" | grep -q "Success"; then
                echo "    [OK] Blocksy theme updated successfully! (The update button is now gone)" | tee -a "$LOG_FILE"
            elif echo "$UPDATE_RESULT" | grep -q "already at the latest version"; then
                echo "    [SKIP] Blocksy theme is already up to date." | tee -a "$LOG_FILE"
            else
                echo "    [WARN] Failed to update Blocksy. Please check the log." | tee -a "$LOG_FILE"
            fi
        else
            echo "    [SKIP] Blocksy theme is not installed." | tee -a "$LOG_FILE"
        fi

        # 2. อัปเดต Plugin: Blocksy Companion
        if wp plugin is-installed blocksy-companion --allow-root 2>/dev/null; then
            PLUGIN_UPDATE_RESULT=$(wp plugin update blocksy-companion --allow-root 2>&1)
            echo "$PLUGIN_UPDATE_RESULT" >> "$LOG_FILE"
            
            if echo "$PLUGIN_UPDATE_RESULT" | grep -q "Success"; then
                echo "    [OK] Blocksy Companion updated." | tee -a "$LOG_FILE"
            elif echo "$PLUGIN_UPDATE_RESULT" | grep -q "already at the latest version"; then
                echo "    [SKIP] Blocksy Companion is already up to date." | tee -a "$LOG_FILE"
            fi
        fi
        
        # 3. อัปเดต Blocksy Companion Pro
        if wp plugin is-installed blocksy-companion-pro --allow-root 2>/dev/null; then
            wp transient delete update_plugins --allow-root >/dev/null 2>&1
            PLUGIN_PRO_UPDATE_RESULT=$(wp plugin update blocksy-companion-pro --allow-root 2>&1)
            echo "$PLUGIN_PRO_UPDATE_RESULT" >> "$LOG_FILE"
            
            if echo "$PLUGIN_PRO_UPDATE_RESULT" | grep -q "Success"; then
                echo "    [OK] Blocksy Companion Pro updated." | tee -a "$LOG_FILE"
            elif echo "$PLUGIN_PRO_UPDATE_RESULT" | grep -q "already at the latest version"; then
                echo "    [SKIP] Blocksy Companion Pro is already up to date." | tee -a "$LOG_FILE"
            fi
        fi

        # --- ฟังก์ชัน 1: อัปเดตลิงก์ในหน้า Page (Content) ---
        update_page_link() {
            local slug=$1; local new_url=$2; local label=$3
            
            local page_id=$(wp post list --post_type=page --name="$slug" --format=ids --allow-root 2>/dev/null)
            
            if [ -n "$page_id" ]; then
                local old_content=$(wp post get "$page_id" --field=post_content --allow-root)
                
                if echo "$old_content" | grep -Eq "<a[^>]+href="; then
                    local new_content=$(echo "$old_content" | sed -E "s|href=\"[^\"]*\"|href=\"$new_url\"|g")
                    wp post update "$page_id" --post_content="$new_content" --allow-root >> "$LOG_FILE" 2>&1
                    echo "    [OK] Page: $label ($slug) updated" | tee -a "$LOG_FILE"
                else
                    echo "    [SKIP] Page: $label ($slug) has no links to update" | tee -a "$LOG_FILE"
                fi
            else
                echo "    [SKIP] Page: $label ($slug) not found on this site" | tee -a "$LOG_FILE"
            fi
        }

        # --- ฟังก์ชัน 2: จัดการ Shortcut Bar (Blocksy) ---
        update_shortcuts_bar() {
            local target_url=$1   
            local search_url=$2   
            
            [ -z "$search_url" ] && search_url="https://google.com"

            echo "    [BT] Targeting Blocksy Shortcut Bar: '$search_url' -> '$target_url'..." | tee -a "$LOG_FILE"
            wp search-replace "$search_url" "$target_url" wp_options --include-columns=option_value --allow-root >> "$LOG_FILE" 2>&1
            echo "    [OK] Shortcut Bar processed" | tee -a "$LOG_FILE"
        }

        # --- ฟังก์ชัน 3: ค้นหาและแทนที่ทั้งฐานข้อมูล (Global) ---
        update_option_url() {
            local old_url=$1; local new_url=$2
            if [ -n "$old_url" ] && [ -n "$new_url" ]; then
                echo "    [DB] Global Replace: '$old_url' -> '$new_url'..." | tee -a "$LOG_FILE"
                wp search-replace "$old_url" "$new_url" --all-tables --allow-root >> "$LOG_FILE" 2>&1
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
