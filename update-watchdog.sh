#!/bin/bash
# update-watchdog.sh - Update NIC Watchdog to the latest version

set -e

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

REPO_URL="https://raw.githubusercontent.com/Skulldorom/nic-watch-dog/main/nic-watchdog.sh"
INSTALL_PATH="/usr/local/bin/nic-watchdog"
SERVICE_NAME="nic-watchdog.service"
TEMP_FILE="/tmp/nic-watchdog-update.sh"
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
    wget -q -O "$TEMP_FILE" "$REPO_URL"
elif command -v curl &> /dev/null; then
    curl -s -o "$TEMP_FILE" "$REPO_URL"
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
if ! head -n 1 "$TEMP_FILE" | grep -q '^#!/bin/bash'; then
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
                echo -e "${YELLOW}→ Previous version restored and service restarted${NC}"
            fi
        fi
        echo -e "${RED}Update failed. Check logs with: journalctl -u ${SERVICE_NAME}${NC}"
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
