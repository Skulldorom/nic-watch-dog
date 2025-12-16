#!/bin/bash
# nic-watchdog.sh - auto recover NIC if it hangs & alert via Discord webhook

# Default configuration values
NIC="${NIC:-eth0}"
PING_TARGET_1="${PING_TARGET_1:-8.8.8.8}"         # Google DNS
PING_TARGET_2="${PING_TARGET_2:-1.1.1.1}"         # Cloudflare DNS
FAIL_THRESHOLD="${FAIL_THRESHOLD:-3}"
SLEEP_INTERVAL="${SLEEP_INTERVAL:-30}"
DISCORD_WEBHOOK="${DISCORD_WEBHOOK:-}"

# Load configuration from .env file if it exists
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR/.env" ]; then
    # Source the .env file, ignoring comments and empty lines
    set -a
    source "$SCRIPT_DIR/.env"
    set +a
fi

send_discord() {
    local subject="$1"
    local message="$2"

    # Optional: pick a color based on subject/content
    # Default grey
    local color=10066329   # 0x999999
    if [[ "$subject" == *"Test"* ]]; then
        color=255          # 0x0000FF (blue)
    elif [[ "$message" == *"Connectivity restored"* ]]; then
        color=65280        # 0x00FF00 (green)
    elif [[ "$message" == *"restarted"* ]]; then
        color=16753920     # 0xFF8800 (orange)
    fi

    # Escape double quotes in message
    local esc_message
    esc_message=$(printf '%s' "$message" | sed 's/"/\\"/g')

    curl -s -H "Content-Type: application/json" \
         -X POST \
         -d "{
               \"username\": \"NIC Watchdog\",
               \"embeds\": [{
                   \"title\": \"${subject}\",
                   \"description\": \"${esc_message}\",
                   \"color\": ${color},
                   \"footer\": {
                       \"text\": \"Proxmox\"
                   }
               }]
             }" \
         "$DISCORD_WEBHOOK" > /dev/null
}

fails=0
reboot_counter=0
REBOOT_THRESHOLD=$((600 / SLEEP_INTERVAL))  # 10 minutes worth of checks

# --- Test mode ---
if [ "$1" == "--test" ]; then
    logger -t nic-watchdog "Manual test triggered, testing NIC $NIC and sending Discord notification"

    # Check if NIC interface is up
    if ! ip link show "$NIC" | grep -q "state UP"; then
        logger -t nic-watchdog "Test: NIC $NIC is DOWN"
        send_discord "NIC Watchdog Test" "❌ Test: NIC '$NIC' interface is DOWN."
        exit 1
    fi

    # Test connectivity to both targets
    if ping -c 1 -W 2 "$PING_TARGET_1" > /dev/null 2>&1 || ping -c 1 -W 2 "$PING_TARGET_2" > /dev/null 2>&1; then
        logger -t nic-watchdog "Test: Can reach ping targets ($PING_TARGET_1 or $PING_TARGET_2)"
        send_discord "NIC Watchdog Test" "✅ Test OK: Can reach ping targets ($PING_TARGET_1 or $PING_TARGET_2)."
    else
        logger -t nic-watchdog "Test: CANNOT reach either $PING_TARGET_1 or $PING_TARGET_2, attempting restart"
        ip link set "$NIC" down
        sleep 2
        ip link set "$NIC" up
        sleep 3  # Give the NIC time to come up

        # Re-test after restart
        if ping -c 1 -W 2 "$PING_TARGET_1" > /dev/null 2>&1 || ping -c 1 -W 2 "$PING_TARGET_2" > /dev/null 2>&1; then
            logger -t nic-watchdog "Test: After restart, can reach ping targets"
            send_discord "NIC Watchdog Test" "⚠️ Test: Initially failed but connectivity works after restarting NIC '$NIC'."
        else
            logger -t nic-watchdog "Test: After restart, still cannot reach either target"
            send_discord "NIC Watchdog Test" "❌ Test FAILED: Still cannot reach $PING_TARGET_1 or $PING_TARGET_2 even after restarting NIC '$NIC'."
        fi
    fi

    exit 0
fi

logger -t nic-watchdog "Starting NIC watchdog for $NIC (targets: $PING_TARGET_1, $PING_TARGET_2)"

while true; do
    # Check if at least one ping target is reachable
    if ping -c 1 -W 2 "$PING_TARGET_1" > /dev/null 2>&1 || ping -c 1 -W 2 "$PING_TARGET_2" > /dev/null 2>&1; then
        # Success - at least one target is reachable
        if [ $fails -gt 0 ]; then
            logger -t nic-watchdog "Connectivity restored (can reach $PING_TARGET_1 or $PING_TARGET_2)"
            send_discord "NIC Watchdog" "✅ Connectivity restored (can reach $PING_TARGET_1 or $PING_TARGET_2)."
        fi
        fails=0
        reboot_counter=0  # Reset reboot counter on success
    else
        # Failure - neither target is reachable
        fails=$((fails+1))
        reboot_counter=$((reboot_counter+1))
        if [ $fails -lt $FAIL_THRESHOLD ]; then
            logger -t nic-watchdog "Warning: cannot reach $PING_TARGET_1 or $PING_TARGET_2 ($fails/$FAIL_THRESHOLD)"
        else
            logger -t nic-watchdog "Restarting $NIC after $fails failed attempts"
            ip link set "$NIC" down
            sleep 2
            ip link set "$NIC" up
            send_discord "NIC Watchdog Action: $NIC Restarted" "❌ The NIC '$NIC' was restarted after $fails failed pings (neither $PING_TARGET_1 nor $PING_TARGET_2 were reachable)."
            fails=0
        fi
        # --- New: reboot if NIC still down after 10 minutes ---
        if [ $reboot_counter -ge $REBOOT_THRESHOLD ]; then
            logger -t nic-watchdog "CRITICAL: NIC still down after 10 minutes, rebooting server"
            send_discord "NIC Watchdog Critical" "💥 Server is rebooting because connectivity could not be restored after 10 minutes."
            reboot
        fi
    fi
    sleep "$SLEEP_INTERVAL"
done
