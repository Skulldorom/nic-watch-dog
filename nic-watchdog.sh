#!/bin/bash
# nic-watchdog.sh - auto recover NIC if it hangs & alert via Discord webhook
NIC="eth0"
PING_TARGET="192.168.0.1"
FAIL_THRESHOLD=3
SLEEP_INTERVAL=30
# ==== CHANGE THIS: Put your Discord webhook here ====
DISCORD_WEBHOOK=""

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

    if ping -I "$NIC" -c 1 -W 2 "$PING_TARGET" > /dev/null 2>&1; then
        logger -t nic-watchdog "Test: NIC $NIC can reach $PING_TARGET"
        send_discord "NIC Watchdog Test" "✅ Test OK: NIC '$NIC' can reach $PING_TARGET."
    else
        logger -t nic-watchdog "Test: NIC $NIC CANNOT reach $PING_TARGET, attempting restart"
        ip link set "$NIC" down
        sleep 2
        ip link set "$NIC" up

        # Re-test after restart
        if ping -I "$NIC" -c 1 -W 2 "$PING_TARGET" > /dev/null 2>&1; then
            logger -t nic-watchdog "Test: After restart, NIC $NIC can reach $PING_TARGET"
            send_discord "NIC Watchdog Test" "⚠️ Test: NIC '$NIC' initially failed but works after restart."
        else
            logger -t nic-watchdog "Test: After restart, NIC $NIC still cannot reach $PING_TARGET"
            send_discord "NIC Watchdog Test" "❌ Test FAILED: NIC '$NIC' still cannot reach $PING_TARGET even after restart."
        fi
    fi

    exit 0
fi

logger -t nic-watchdog "Starting NIC watchdog for $NIC (target $PING_TARGET)"

while true; do
    if ping -I "$NIC" -c 1 -W 2 "$PING_TARGET" > /dev/null 2>&1; then
        # Success
        if [ $fails -gt 0 ]; then
            logger -t nic-watchdog "✅ Connectivity restored on $NIC"
            send_discord "NIC Watchdog" "✅ Connectivity restored on $NIC."
        fi
        fails=0
        reboot_counter=0  # Reset reboot counter on success
    else
        # Failure
        fails=$((fails+1))
        reboot_counter=$((reboot_counter+1))
        if [ $fails -lt $FAIL_THRESHOLD ]; then
            logger -t nic-watchdog "⚠️ Warning: ping to $PING_TARGET failed ($fails/$FAIL_THRESHOLD)"
        else
            logger -t nic-watchdog "❌ Restarting $NIC after $fails failed attempts"
            ip link set "$NIC" down
            sleep 2
            ip link set "$NIC" up
            send_discord "NIC Watchdog Action: $NIC Restarted" "❌ The NIC '$NIC' was restarted after $fails failed pings to $PING_TARGET."
            fails=0
        fi
        # --- New: reboot if NIC still down after 10 minutes ---
        if [ $reboot_counter -ge $REBOOT_THRESHOLD ]; then
            logger -t nic-watchdog "💥 NIC still down after 10 minutes, rebooting server"
            reboot
        fi
    fi
    sleep "$SLEEP_INTERVAL"
done
