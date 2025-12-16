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
UPDATE_SCRIPT_PATH="/usr/local/bin/update-watchdog"
SERVICE_NAME="nic-watchdog.service"
TEMP_FILE="/tmp/nic-watchdog-update.sh"
TEMP_UPDATE_SCRIPT="/tmp/update-watchdog-new.sh"
SERVICE_START_WAIT=2

echo -e "${YELLOW}NIC Watchdog Update Script${NC}"
echo "================================"
echo

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Error: This script must be run as root or with sudo${NC}"
    echo "Usage: sudo update-watchdog"
    exit 1
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
    BACKUP_PATH="${INSTALL_PATH}.backup"
    echo -e "${YELLOW}→ Creating backup at ${BACKUP_PATH}...${NC}"
    if ! cp "$INSTALL_PATH" "$BACKUP_PATH"; then
        echo -e "${RED}Error: Failed to create backup${NC}"
        rm -f "$TEMP_FILE"
        exit 1
    fi
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

# Clean up backup file after successful update
if [ -n "$BACKUP_PATH" ] && [ -f "$BACKUP_PATH" ]; then
    echo -e "${YELLOW}→ Cleaning up backup file...${NC}"
    if ! rm "$BACKUP_PATH" 2>/dev/null; then
        echo -e "${RED}Warning: Failed to remove backup file at ${BACKUP_PATH}${NC}"
        echo -e "${YELLOW}You may want to manually remove it later${NC}"
    fi
fi

echo
echo "Current version installed at: $INSTALL_PATH"

# Show service status if enabled
if systemctl is-enabled --quiet "$SERVICE_NAME" 2>/dev/null; then
    echo
    echo "Service status:"
    systemctl status "$SERVICE_NAME" --no-pager -l
fi

# Update the update script itself
# Temporarily disable 'set -e' so that failures in self-update don't cause script to exit
set +e
echo
echo -e "${YELLOW}→ Updating update script itself...${NC}"

# Download the latest update script
DOWNLOAD_SUCCESS=false
if command -v wget &> /dev/null; then
    if wget -q -O "$TEMP_UPDATE_SCRIPT" "$UPDATE_SCRIPT_URL"; then
        DOWNLOAD_SUCCESS=true
    fi
elif command -v curl &> /dev/null; then
    if curl -sf -o "$TEMP_UPDATE_SCRIPT" "$UPDATE_SCRIPT_URL"; then
        DOWNLOAD_SUCCESS=true
    fi
fi

if [ "$DOWNLOAD_SUCCESS" = false ]; then
    echo -e "${RED}Warning: Failed to download update script from GitHub${NC}"
    echo -e "${YELLOW}The update script was not updated, but the watchdog was updated successfully${NC}"
    rm -f "$TEMP_UPDATE_SCRIPT"
    exit 0
fi

# Verify download was successful
if [ ! -s "$TEMP_UPDATE_SCRIPT" ]; then
    echo -e "${RED}Warning: Failed to download the latest update script${NC}"
    echo -e "${YELLOW}The update script was not updated, but the watchdog was updated successfully${NC}"
    rm -f "$TEMP_UPDATE_SCRIPT"
    exit 0
fi

# Validate that it's a shell script
if ! head -n 1 "$TEMP_UPDATE_SCRIPT" | grep -qE '^#!.*bash$'; then
    echo -e "${RED}Warning: Downloaded update script is not a valid bash script${NC}"
    echo -e "${YELLOW}The update script was not updated, but the watchdog was updated successfully${NC}"
    rm -f "$TEMP_UPDATE_SCRIPT"
    exit 0
fi

# Make it executable
chmod +x "$TEMP_UPDATE_SCRIPT"

# Install the new update script
if [ -f "$UPDATE_SCRIPT_PATH" ]; then
    mv "$TEMP_UPDATE_SCRIPT" "$UPDATE_SCRIPT_PATH"
    echo -e "${GREEN}✓ Update script updated successfully!${NC}"
else
    echo -e "${YELLOW}→ Update script not installed at expected location ($UPDATE_SCRIPT_PATH)${NC}"
    echo -e "${YELLOW}  Skipping update script self-update${NC}"
    rm -f "$TEMP_UPDATE_SCRIPT"
fi
