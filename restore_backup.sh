#!/usr/bin/env bash

set -e

PANEL_PATH="/var/www/pterodactyl"
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}* This script must be run as root.${NC}"
   exit 1
fi

SCRIPT_DIR=$(dirname "$(realpath "$0")")

# 1. Find Backup Folders
echo -e "${GREEN}* Scanning for backup folders...${NC}"
shopt -s nullglob
backup_dirs=("$SCRIPT_DIR"/pterodactyl_*)
shopt -u nullglob

if [ ${#backup_dirs[@]} -eq 0 ]; then
    echo -e "${RED}* No backup folders found in $SCRIPT_DIR.${NC}"
    exit 1
fi

echo -e "\nAvailable Backup Folders:"
for i in "${!backup_dirs[@]}"; do
    echo "$((i+1))) $(basename "${backup_dirs[$i]}")"
done

read -p "Select a backup folder [1-${#backup_dirs[@]}]: " dir_choice
if [[ ! "$dir_choice" =~ ^[0-9]+$ ]] || [ "$dir_choice" -lt 1 ] || [ "$dir_choice" -gt "${#backup_dirs[@]}" ]; then
    echo -e "${RED}* Invalid selection. Exiting.${NC}"
    exit 1
fi

SELECTED_DIR="${backup_dirs[$((dir_choice-1))]}"
echo -e "* Selected: $(basename "$SELECTED_DIR")\n"

# 2. Detect Available Backups in the Selected Folder
shopt -s nullglob
archive_files=("$SELECTED_DIR"/files_*.tar.gz)
db_files=("$SELECTED_DIR"/db_*.sql)
shopt -u nullglob

HAS_FILES=false
HAS_DB=false
FILES_BACKUP=""
DB_BACKUP=""

if [ ${#archive_files[@]} -gt 0 ]; then
    HAS_FILES=true
    FILES_BACKUP="${archive_files[0]}"
fi

if [ ${#db_files[@]} -gt 0 ]; then
    HAS_DB=true
    DB_BACKUP="${db_files[0]}"
fi

if [[ "$HAS_FILES" == false ]] && [[ "$HAS_DB" == false ]]; then
    echo -e "${RED}* The selected folder does not contain any valid backups (files_*.tar.gz or db_*.sql).${NC}"
    exit 1
fi

# 3. Ask what to restore
echo -e "What do you want to restore from this backup?"
OPTIONS=()
[ "$HAS_FILES" = true ] && OPTIONS+=("Archive (Files)")
[ "$HAS_DB" = true ] && OPTIONS+=("Database")
if [ "$HAS_FILES" = true ] && [ "$HAS_DB" = true ]; then
    OPTIONS+=("Both")
fi

for i in "${!OPTIONS[@]}"; do
    echo "$((i+1))) ${OPTIONS[$i]}"
done

read -p "Enter choice [1-${#OPTIONS[@]}]: " RESTORE_CHOICE
if [[ ! "$RESTORE_CHOICE" =~ ^[0-9]+$ ]] || [ "$RESTORE_CHOICE" -lt 1 ] || [ "$RESTORE_CHOICE" -gt "${#OPTIONS[@]}" ]; then
    echo -e "${RED}* Invalid choice. Exiting.${NC}"
    exit 1
fi

SELECTED_OPTION="${OPTIONS[$((RESTORE_CHOICE-1))]}"

RESTORE_FILES_NOW=false
RESTORE_DB_NOW=false

case "$SELECTED_OPTION" in
    "Archive (Files)") RESTORE_FILES_NOW=true ;;
    "Database") RESTORE_DB_NOW=true ;;
    "Both") RESTORE_FILES_NOW=true; RESTORE_DB_NOW=true ;;
    *) echo -e "${RED}* Unexpected error.${NC}"; exit 1 ;;
esac

echo -e "\n* You have selected to restore:"
[ "$RESTORE_FILES_NOW" = true ] && echo "  - Archive: $(basename "$FILES_BACKUP")"
[ "$RESTORE_DB_NOW" = true ] && echo "  - Database: $(basename "$DB_BACKUP")"

echo -n "* This will overwrite current panel data with the selected backups. Proceed? [y/N]: "
read -r CONFIRM_RESTORE
if [[ ! "$CONFIRM_RESTORE" =~ ^[Yy]$ ]]; then
    echo -e "${RED}* Restoration aborted!${NC}"
    exit 1
fi

# 4. Perform Restore
if [ "$RESTORE_FILES_NOW" = true ]; then
    echo -e "${GREEN}* Restoring Panel Files...${NC}"
    
    if [ ! -d "$PANEL_PATH" ]; then
        mkdir -p "$PANEL_PATH"
    fi
    
    cd "$PANEL_PATH" || exit 1
    
    if [ -f "artisan" ]; then
        php artisan down || true
    fi
    
    if tar -xzf "$FILES_BACKUP" -C "$PANEL_PATH"; then
        echo -e "${GREEN}* Files extracted successfully.${NC}"
    else
        echo -e "${RED}* Failed to extract files!${NC}"
        exit 1
    fi
    
    chown -R www-data:www-data .
    
    if [ -f "artisan" ]; then
        php artisan up || true
    fi
fi

if [ "$RESTORE_DB_NOW" = true ]; then
    echo -e "${GREEN}* Restoring Database...${NC}"
    
    if [ -f "$PANEL_PATH/.env" ]; then
        DB_NAME=$(grep "^DB_DATABASE=" "$PANEL_PATH/.env" | cut -d '=' -f2)
        
        if [ -n "$DB_NAME" ]; then
            if mysql "$DB_NAME" < "$DB_BACKUP"; then
                echo -e "${GREEN}* Database restored successfully.${NC}"
            else
                echo -e "${RED}* Database restore failed!${NC}"
                exit 1
            fi
        else
            echo -e "${RED}* Could not parse DB_DATABASE from .env!${NC}"
            exit 1
        fi
    else
        echo -e "${RED}* .env file not found at $PANEL_PATH/.env - Cannot determine database name!${NC}"
        exit 1
    fi
fi

echo -e "${GREEN}* Restoration complete!${NC}"