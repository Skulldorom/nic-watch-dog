#!/bin/bash
# update-watchdog.sh - Update NIC Watchdog to the latest version

set -e

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

REPO_URL="https://raw.githubusercontent.com/Skulldorom/nic-watch-dog/main/nic-watchdog.sh"
UPDATE_SCRIPT_URL="https://raw.githubusercontent.com/Skulldorom/nic-watch-dog/main/update-watchdog.sh"
INSTALL_PATH="/usr/local/bin/nic-watchdog"
UPDATE_INSTALL_PATH="/usr/local/bin/update-watchdog"
SERVICE_NAME="nic-watchdog.service"
TEMP_FILE="/tmp/nic-watchdog-update.sh"
TEMP_UPDATE_FILE="/tmp/update-watchdog-install.sh"
SERVICE_START_WAIT=2

# Get the absolute path of the current script
SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"

echo -e "${YELLOW}NIC Watchdog Update Script${NC}"
echo "================================"
echo

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Error: This script must be run as root or with sudo${NC}"
    echo "Usage: sudo update-watchdog"
    exit 1
fi

# Auto-install this update script if not installed in the correct location
if [ "$SCRIPT_PATH" != "$UPDATE_INSTALL_PATH" ]; then
    echo -e "${YELLOW}→ Update script is not installed in system path${NC}"
    echo -e "${YELLOW}→ Installing update-watchdog to ${UPDATE_INSTALL_PATH}...${NC}"
    
    # Check if we need to download or copy local file
    if [ -f "$SCRIPT_PATH" ]; then
        # Copy the current script
        cp "$SCRIPT_PATH" "$UPDATE_INSTALL_PATH"
        chmod +x "$UPDATE_INSTALL_PATH"
        echo -e "${GREEN}✓ Update script installed successfully!${NC}"
    else
        # Download from GitHub
        echo -e "${YELLOW}→ Downloading update script from GitHub...${NC}"
        if command -v wget &> /dev/null; then
            if ! wget -q -O "$TEMP_UPDATE_FILE" "$UPDATE_SCRIPT_URL"; then
                echo -e "${RED}Error: Failed to download update script from GitHub${NC}"
                rm -f "$TEMP_UPDATE_FILE"
                exit 1
            fi
        elif command -v curl &> /dev/null; then
            if ! curl -sf -o "$TEMP_UPDATE_FILE" "$UPDATE_SCRIPT_URL"; then
                echo -e "${RED}Error: Failed to download update script from GitHub${NC}"
                rm -f "$TEMP_UPDATE_FILE"
                exit 1
            fi
        else
            echo -e "${RED}Error: Neither wget nor curl is installed${NC}"
            exit 1
        fi
        
        chmod +x "$TEMP_UPDATE_FILE"
        mv "$TEMP_UPDATE_FILE" "$UPDATE_INSTALL_PATH"
        echo -e "${GREEN}✓ Update script installed successfully!${NC}"
    fi
    
    echo -e "${GREEN}→ Now you can run 'sudo update-watchdog' from anywhere${NC}"
    echo -e "${YELLOW}→ Re-running from installed location...${NC}"
    echo
    
    # Re-run from the installed location
    exec "$UPDATE_INSTALL_PATH" "$@"
fi

# Check if service is running
SERVICE_RUNNING=false
if systemctl is-active --quiet "$SERVICE_NAME"; then
    SERVICE_RUNNING=true
    echo -e "${YELLOW}→ Stopping ${SERVICE_NAME}...${NC}"
    systemctl stop "$SERVICE_NAME"
fi

# Download the latest version
echo -e "${YELLOW}→ Downloading latest version from GitHub...${NC}"
if command -v wget &> /dev/null; then
    if ! wget -q -O "$TEMP_FILE" "$REPO_URL"; then
        echo -e "${RED}Error: Failed to download from GitHub${NC}"
        rm -f "$TEMP_FILE"
        exit 1
    fi
elif command -v curl &> /dev/null; then
    if ! curl -sf -o "$TEMP_FILE" "$REPO_URL"; then
        echo -e "${RED}Error: Failed to download from GitHub${NC}"
        rm -f "$TEMP_FILE"
        exit 1
    fi
else
    echo -e "${RED}Error: Neither wget nor curl is installed${NC}"
    exit 1
fi

# Verify download was successful
if [ ! -s "$TEMP_FILE" ]; then
    echo -e "${RED}Error: Failed to download the latest version${NC}"
    rm -f "$TEMP_FILE"
    exit 1
fi

# Validate that it's a shell script
if ! head -n 1 "$TEMP_FILE" | grep -qE '^#!.*bash$'; then
    echo -e "${RED}Error: Downloaded file is not a valid bash script${NC}"
    rm -f "$TEMP_FILE"
    exit 1
fi

# Make it executable
echo -e "${YELLOW}→ Making script executable...${NC}"
chmod +x "$TEMP_FILE"

# Backup existing version if it exists
BACKUP_PATH=""
if [ -f "$INSTALL_PATH" ]; then
    BACKUP_PATH="${INSTALL_PATH}.backup.$(date +%Y%m%d-%H%M%S)"
    echo -e "${YELLOW}→ Backing up existing version to ${BACKUP_PATH}${NC}"
    cp "$INSTALL_PATH" "$BACKUP_PATH"
fi

# Install the new version
echo -e "${YELLOW}→ Installing to ${INSTALL_PATH}...${NC}"
mv "$TEMP_FILE" "$INSTALL_PATH"

# Restart service if it was running
if [ "$SERVICE_RUNNING" = true ]; then
    echo -e "${YELLOW}→ Restarting ${SERVICE_NAME}...${NC}"
    systemctl start "$SERVICE_NAME"
    sleep "$SERVICE_START_WAIT"
    if systemctl is-active --quiet "$SERVICE_NAME"; then
        echo -e "${GREEN}✓ Service restarted successfully${NC}"
    else
        echo -e "${RED}✗ Service failed to start. Rolling back to previous version...${NC}"
        if [ -n "$BACKUP_PATH" ] && [ -f "$BACKUP_PATH" ]; then
            cp "$BACKUP_PATH" "$INSTALL_PATH"
            systemctl start "$SERVICE_NAME"
            sleep "$SERVICE_START_WAIT"
            if systemctl is-active --quiet "$SERVICE_NAME"; then
                echo -e "${GREEN}✓ Rollback successful: Previous version restored and service running${NC}"
                echo -e "${RED}Update failed due to new version issues. Check logs with: journalctl -u ${SERVICE_NAME}${NC}"
            else
                echo -e "${RED}✗ Critical: Rollback failed! Service could not be restarted with previous version${NC}"
                echo -e "${RED}Manual intervention required. Check logs with: journalctl -u ${SERVICE_NAME}${NC}"
            fi
        else
            echo -e "${RED}✗ No backup available to rollback${NC}"
            echo -e "${RED}Manual intervention required. Check logs with: journalctl -u ${SERVICE_NAME}${NC}"
        fi
        exit 1
    fi
fi

echo
echo -e "${GREEN}✓ NIC Watchdog updated successfully!${NC}"
echo
echo "Current version installed at: $INSTALL_PATH"

# Show service status if enabled
if systemctl is-enabled --quiet "$SERVICE_NAME" 2>/dev/null; then
    echo
    echo "Service status:"
    systemctl status "$SERVICE_NAME" --no-pager -l
fi
