#!/usr/bin/env bash

set -e

TIMESTAMP=$(date +%F_%H-%M-%S)
PANEL_UPDATE="https://github.com/pterodactyl/panel/releases/latest/download/panel.tar.gz"
WINGS_UPDATE="https://github.com/pterodactyl/wings/releases/latest/download/wings_linux_$([[ "$(uname -m)" == "x86_64" ]] && echo "amd64" || echo "arm64")"
PANEL_PATH="/var/www/pterodactyl"

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

function check_dependencies {
    echo -e "* Checking system dependencies..."

    # Check PHP Version
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

    # Check Composer Version
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
    
    check_dependencies

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

function check_panel_version {
    if [ ! -d "$PANEL_PATH" ]; then
        return
    fi
    
    cd "$PANEL_PATH" || exit 1
    echo -e "${GREEN}* Checking Pterodactyl Panel version...${NC}"
    CURRENT_VERSION=$(php artisan p:info | grep "Panel Version" | awk '{print $3}')
    LATEST_VERSION=$(php artisan p:info | grep "Latest Version" | awk '{print $3}')

    if [[ "$CURRENT_VERSION" == "$LATEST_VERSION" ]] && [[ -n "$CURRENT_VERSION" ]]; then
        echo -e "${GREEN}* Panel and Wings are already up-to-date (Version: $CURRENT_VERSION)${NC}"
        exit 0
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
    if tar -czf "files_$TIMESTAMP.tar.gz" -C "$PANEL_PATH" .; then
        echo -e "${GREEN}* Panel files archived successfully.${NC}"
    else
        echo -e "${RED}* Panel files archiving failed!${NC}"
        exit 1
    fi
}

function update_panel() {
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
check_panel_version
create_backup
update_panel
sleep 4
update_wings