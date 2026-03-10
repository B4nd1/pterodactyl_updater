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
    echo -e "${GREEN}* Starting pre-update backup...${NC}"

    if [ -f "$PANEL_PATH/.env" ]; then
        DB_NAME=$(grep DB_DATABASE "$PANEL_PATH/.env" | cut -d '=' -f2)

        echo -e "* Exporting database: $DB_NAME using root privileges..."

        # MariaDB/MySQL will use the unix_socket to auth as the DB root.
        if mysqldump "$DB_NAME" > "db_$TIMESTAMP.sql" 2>/dev/null; then
            echo -e "${GREEN}* Database backup successful.${NC}"
        else
            echo -e "${RED}* Database backup failed! Checking alternative method...${NC}"
            export $(grep -v '^#' "$PANEL_PATH/.env" | xargs)
            mysqldump -u "$DB_USERNAME" -p"$DB_PASSWORD" "$DB_DATABASE" > "db_$TIMESTAMP.sql"
        fi
    fi

    echo -e "* Archiving panel files..."
    tar -czf "files_$TIMESTAMP.tar.gz" -C "$PANEL_PATH" .
}

function update_panel() {
    if [ -d "$PANEL_PATH" ]; then
      cd "$PANEL_PATH"
      curl -L $PANEL_UPDATE | tar -xzv
      sleep 5
      php artisan down
      chmod -R 755 storage/* bootstrap/cache
      composer install --no-dev --optimize-autoloader
      php artisan view:clear
      php artisan config:clear
      php artisan migrate --seed --force
      chown -R www-data:www-data *
      php artisan queue:restart
      php artisan up

      echo "Panel Updated"
    fi
}

function update_wings() {
    if [ -d "/usr/local/bin/" ]; then
      echo "Updating Wings........"
      sleep 5
      cd "/usr/local/bin/"
      systemctl stop wings
      curl -L -o /usr/local/bin/wings $WINGS_UPDATE
      chmod u+x /usr/local/bin/wings
      systemctl restart wings
      echo "Wings Updated"
    fi
}

main
create_backup
update_panel
sleep 4
update_wings