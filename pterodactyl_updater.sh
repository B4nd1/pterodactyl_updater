#!/usr/bin/env bash

set -e

TIMESTAMP=$(date +%F_%H-%M-%S)
PANEL_UPDATE="https://github.com/pterodactyl/panel/releases/latest/download/panel.tar.gz"
WINGS_UPDATE="https://github.com/pterodactyl/wings/releases/latest/download/wings_linux_$([[ "$(uname -m)" == "x86_64" ]] && echo "amd64" || echo "arm64")"
PANEL_PATH="/var/www/pterodactyl"
WEBSERVER_USER="www-data"

# Dynamically find the directory where this script is located
SCRIPT_DIR=$(dirname "$(realpath "$0")")
BACKUP_DIR="$SCRIPT_DIR/pterodactyl_$TIMESTAMP"

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

function check_dependencies {
    echo -e "* Checking system dependencies..."

    if command -v php >/dev/null 2>&1; then
        PHP_VERSION_CHECK=$(php -r "echo version_compare(PHP_VERSION, '8.2', '>=') ? 'OK' : 'FAIL';")
        if [[ "$PHP_VERSION_CHECK" != "OK" ]]; then
            echo -e "${RED}* PHP 8.2 or higher is required. Please follow the PHP Upgrade Guide [https://pterodactyl.io/guides/php_upgrade.html] and try again.${NC}"
            exit 1
        fi
    else
        echo -e "${RED}* PHP is not installed. Please install PHP 8.2 or higher.${NC}"
        exit 1
    fi

    if command -v composer >/dev/null 2>&1; then
        COMPOSER_VERSION=$(composer --version -n 2>/dev/null)
        if [[ ! "$COMPOSER_VERSION" =~ Composer\ version\ 2\. ]]; then
             echo -e "${RED}* Composer 2.x is required. Please upgrade Composer and try again.${NC}"
             exit 1
        fi
    else
        echo -e "${RED}* Composer is not installed. Please install Composer 2.x.${NC}"
        exit 1
    fi
    echo -e "${GREEN}* Dependencies check passed (PHP 8.2+, Composer 2.x).${NC}"
}

function main {
    if [[ $EUID -ne 0 ]]; then
       echo -e "${RED}* This script must be run as root.${NC}"
       exit 1
    fi

    HAS_PANEL=false
    HAS_WINGS=false

    if [ -d "$PANEL_PATH" ]; then
        HAS_PANEL=true
        check_dependencies
    fi

    if [ -f "/usr/local/bin/wings" ]; then
        HAS_WINGS=true
    fi

    if [[ "$HAS_PANEL" == false ]] && [[ "$HAS_WINGS" == false ]]; then
        echo -e "${RED}* Neither Pterodactyl Panel nor Wings were found on this system.${NC}"
        exit 1
    fi

    echo -n "* Do you want to proceed with the update? (y/N): "
    read -r CONFIRM_PROCEED
    if [[ ! "$CONFIRM_PROCEED" =~ [Yy] ]]; then
        echo -e "${RED}* Update aborted!${NC}"
        exit 1
    fi
}

function check_panel_version {
    SKIP_PANEL_UPDATE=false
    if [ ! -d "$PANEL_PATH" ]; then
        SKIP_PANEL_UPDATE=true
        return
    fi

    cd "$PANEL_PATH" || exit 1
    echo -e "${GREEN}* Checking Pterodactyl Panel version...${NC}"
    CURRENT_VERSION=$(php artisan p:info | grep "Panel Version" | awk '{print $3}')
    LATEST_VERSION=$(php artisan p:info | grep "Latest Version" | awk '{print $3}')

    if [[ "$CURRENT_VERSION" == "$LATEST_VERSION" ]] && [[ -n "$CURRENT_VERSION" ]]; then
        echo -e "${GREEN}* Panel is already up-to-date (Version: $CURRENT_VERSION). Skipping Panel update.${NC}"
        SKIP_PANEL_UPDATE=true
    fi
}

function create_backup {
    if [[ "$SKIP_PANEL_UPDATE" == true ]]; then
        return
    fi

    echo -n "* Do you want to create a backup? [Y/n]: "
    read -r CONFIRM_BACKUP
    if [[ "$CONFIRM_BACKUP" =~ ^[Nn]$ ]]; then
        echo -e "* Skipping backup..."
        return
    fi

    echo -e "${GREEN}* Starting pre-update backup...${NC}"

    # Create the backup directory next to the script
    mkdir -p "$BACKUP_DIR"

    if [ -f "$PANEL_PATH/.env" ]; then
        DB_NAME=$(grep DB_DATABASE "$PANEL_PATH/.env" | cut -d '=' -f2)

        echo -e "* Exporting database: $DB_NAME using root privileges..."

        if mysqldump "$DB_NAME" > "$BACKUP_DIR/db_$TIMESTAMP.sql"; then
            echo -e "${GREEN}* Database backup successful.${NC}"
        else
            echo -e "${RED}* Database backup failed!${NC}"
            exit 1

        fi
    fi

    echo -e "* Archiving panel files..."

    # Excludes logs AND the newly created backup folder to prevent recursive tar errors
    if tar --exclude='storage/logs/*' --exclude="pterodactyl_$TIMESTAMP" -czf "$BACKUP_DIR/files_$TIMESTAMP.tar.gz" -C "$PANEL_PATH" .; then
        echo -e "${GREEN}* Panel files archived successfully to $BACKUP_DIR.${NC}"
    else
        echo -e "${RED}* Panel files archiving failed!${NC}"
        exit 1
    fi
}

function update_panel() {
    if [[ "$SKIP_PANEL_UPDATE" == true ]]; then
        return
    fi

    if [ -d "$PANEL_PATH" ]; then
      echo -e "${GREEN}* Starting Panel Update ($CURRENT_VERSION -> $LATEST_VERSION)...${NC}"
      cd "$PANEL_PATH"
      php artisan down
      sleep 5
      curl -L "$PANEL_UPDATE" | tar -xzv
      chmod -R 755 storage/* bootstrap/cache
      composer install --no-dev --optimize-autoloader
      php artisan view:clear
      php artisan config:clear
      php artisan migrate --seed --force
      chown -R "$WEBSERVER_USER":"$WEBSERVER_USER" *
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
check_panel_version
create_backup
update_panel
sleep 4
update_wings