#!/usr/bin/env bash

set -e

TIMESTAMP=$(date +%F_%H-%M-%S)
PANEL_UPDATE="https://github.com/pterodactyl/panel/releases/latest/download/panel.tar.gz"
WINGS_UPDATE="https://github.com/pterodactyl/wings/releases/latest/download/wings_linux_$([[ "$(uname -m)" == "x86_64" ]] && echo "amd64" || echo "arm64")"
PANEL_PATH="/var/www/pterodactyl"

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

function main {
    if [[ $EUID -ne 0 ]]; then
       echo -e "${RED}* This script must be run as root.${NC}"
       exit 1
    fi

    if [ -d "$PANEL_PATH" ]; then
        echo -n "* Do you want to proceed with the update? (y/N): "
        read -r CONFIRM_PROCEED
        if [[ ! "$CONFIRM_PROCEED" =~ [Yy] ]]; then
            echo -e "${RED}* Update aborted!${NC}"
            exit 1
        fi
    else
        echo -e "${RED}* Pterodactyl directory not found at $PANEL_PATH${NC}"
        exit 1
    fi
}

function create_backup {
    echo -n "* Do you want to create a backup? [Y/n]: "
    read -r CONFIRM_BACKUP
    if [[ "$CONFIRM_BACKUP" =~ ^[Nn]$ ]]; then
        echo -e "* Skipping backup..."
        return
    fi

    echo -e "${GREEN}* Starting pre-update backup...${NC}"

    if [ -f "$PANEL_PATH/.env" ]; then
        DB_NAME=$(grep DB_DATABASE "$PANEL_PATH/.env" | cut -d '=' -f2)

        echo -e "* Exporting database: $DB_NAME using root privileges..."

        # MariaDB/MySQL will use the unix_socket to auth as the DB root.
        if mysqldump "$DB_NAME" > "db_$TIMESTAMP.sql"; then
            echo -e "${GREEN}* Database backup successful.${NC}"
        else
            echo -e "${RED}* Database backup failed!${NC}"
            exit 1
            
        fi
    fi

    echo -e "* Archiving panel files..."
    tar -czf "files_$TIMESTAMP.tar.gz" -C "$PANEL_PATH" .
}

function update_panel() {
    if [ -d "$PANEL_PATH" ]; then
      echo -e "${GREEN}* Starting Panel Update...${NC}"
      cd "$PANEL_PATH"
      php artisan down
      sleep 5
      curl -L "$PANEL_UPDATE" | tar -xzv
      chmod -R 755 storage/* bootstrap/cache
      composer install --no-dev --optimize-autoloader
      php artisan view:clear
      php artisan config:clear
      php artisan migrate --seed --force
      # If using NGINX or Apache (not on CentOS)    
      chown -R www-data:www-data *
      php artisan queue:restart
      php artisan up

      echo -e "${GREEN}* Panel Updated Successfully.${NC}"
    fi
}

function update_wings() {
    if [ -f "/usr/local/bin/wings" ]; then
      echo -e "${GREEN}* Updating Wings...${NC}"
      cd "/usr/local/bin/"
      systemctl stop wings
      sleep 5
      curl -L -o /usr/local/bin/wings "$WINGS_UPDATE"
      chmod u+x /usr/local/bin/wings
      systemctl restart wings
      echo -e "${GREEN}* Wings Updated and Restarted.${NC}"
    else
        echo -e "${RED}* Wings binary not found in /usr/local/bin/, skipping.${NC}"
    fi
}

main
create_backup
update_panel
sleep 4
update_wings