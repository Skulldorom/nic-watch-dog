# NIC Watch Dog

A network interface watchdog script for Linux servers (especially useful on Proxmox) that automatically monitors network connectivity and restarts the network interface if it becomes unresponsive. Includes optional Discord webhook notifications.

## Features

- 🔍 **Dual Ping Target Monitoring**: Tests connectivity against two configurable targets (default: Google DNS and Cloudflare DNS)
- 🔄 **Automatic NIC Recovery**: Automatically restarts the network interface after multiple consecutive failures
- 🚨 **Discord Notifications**: Optional Discord webhook integration for alerts
- 🧪 **Test Mode**: Built-in test mode to verify configuration before deployment
- ⏱️ **Configurable Thresholds**: Customize failure counts, check intervals, and timeout values
- 💥 **Server Reboot Protection**: Automatically reboots the server if connectivity cannot be restored after 10 minutes

## Requirements

- Linux-based operating system (tested on Proxmox, Debian, Ubuntu)
- `bash` shell
- `curl` (for Discord notifications)
- `iproute2` package (for `ip` command)
- `iputils-ping` package (for `ping` command)
- Root or sudo privileges (required to restart network interfaces)

## Installation

1. **Download the script:**
   ```bash
   wget https://raw.githubusercontent.com/Skulldorom/nic-watch-dog/main/nic-watchdog.sh
   # or
   curl -O https://raw.githubusercontent.com/Skulldorom/nic-watch-dog/main/nic-watchdog.sh
   ```

2. **Make it executable:**
   ```bash
   chmod +x nic-watchdog.sh
   ```

3. **Move to a system location (optional but recommended):**
   ```bash
   sudo mv nic-watchdog.sh /usr/local/bin/nic-watchdog
   ```

## Configuration

You can configure the watchdog using either a `.env` file (recommended) or by editing the script directly.

### Option 1: Using a .env file (Recommended)

1. **Copy the example configuration file:**
   ```bash
   cp .env.example .env
   ```

2. **Edit the `.env` file with your settings:**
   ```bash
   nano .env
   # Or use your preferred editor: vi, vim, etc.
   ```

3. **Configure the following variables:**
   ```bash
   NIC=eth0                      # Network interface to monitor (e.g., eth0, enp0s3)
   PING_TARGET_1=8.8.8.8         # First ping target (Google DNS)
   PING_TARGET_2=1.1.1.1         # Second ping target (Cloudflare DNS)
   FAIL_THRESHOLD=3              # Number of consecutive failures before restarting NIC
   SLEEP_INTERVAL=30             # Seconds between connectivity checks
   DISCORD_WEBHOOK=              # Your Discord webhook URL (optional)
   ```

The `.env` file is ignored by git, so your configuration won't be committed to the repository.

### Option 2: Edit the script directly

If you prefer not to use a `.env` file, you can edit the default values at the top of the `nic-watchdog.sh` script:

```bash
NIC="${NIC:-eth0}"
PING_TARGET_1="${PING_TARGET_1:-8.8.8.8}"
PING_TARGET_2="${PING_TARGET_2:-1.1.1.1}"
FAIL_THRESHOLD="${FAIL_THRESHOLD:-3}"
SLEEP_INTERVAL="${SLEEP_INTERVAL:-30}"
DISCORD_WEBHOOK="${DISCORD_WEBHOOK:-}"
```

### Finding Your Network Interface Name

To find the name of your network interface:
```bash
ip link show
# or
ip addr
```

Common interface names:
- `eth0`, `eth1` - Traditional Ethernet naming
- `enp0s3`, `enp0s8` - Predictable network interface names
- `ens18`, `ens33` - Common on virtual machines

### Setting Up Discord Notifications (Optional)

1. Create a Discord webhook in your server:
   - Go to Server Settings → Integrations → Webhooks
   - Click "New Webhook"
   - Copy the webhook URL

2. Add the webhook URL to the script:
   ```bash
   DISCORD_WEBHOOK="https://discord.com/api/webhooks/YOUR_WEBHOOK_URL"
   ```

If you don't configure a Discord webhook, the script will still work but won't send notifications.

## Usage

### Test Mode

Before running the watchdog continuously, test your configuration:

```bash
sudo ./nic-watchdog.sh --test
```

This will:
1. Check if the network interface is up
2. Test connectivity to both ping targets
3. Send a test notification to Discord (if configured)
4. Attempt to restart the NIC if connectivity fails (and retest)

### Running Manually

To run the watchdog in the foreground (useful for testing):

```bash
sudo ./nic-watchdog.sh
```

Press `Ctrl+C` to stop it.

### Running as a systemd Service (Recommended)

1. **Create a systemd service file:**
   ```bash
   sudo nano /etc/systemd/system/nic-watchdog.service
   # Or use your preferred editor: vi, vim, etc.
   ```

2. **Add the following content:**
   ```ini
   [Unit]
   Description=NIC Watchdog Service
   After=network.target

   [Service]
   Type=simple
   ExecStart=/usr/local/bin/nic-watchdog
   Restart=always
   RestartSec=10

   [Install]
   WantedBy=multi-user.target
   ```

3. **Enable and start the service:**
   ```bash
   sudo systemctl daemon-reload
   sudo systemctl enable nic-watchdog.service
   sudo systemctl start nic-watchdog.service
   ```

4. **Check service status:**
   ```bash
   sudo systemctl status nic-watchdog.service
   ```

5. **View logs:**
   ```bash
   sudo journalctl -u nic-watchdog.service -f
   ```

### Running with Cron (Alternative)

If you prefer using cron instead of systemd:

```bash
sudo crontab -e
```

Add this line to run the watchdog every minute (only starts if not already running):
```
* * * * * /usr/local/bin/nic-watchdog-wrapper.sh
```

Create the wrapper script:
```bash
sudo nano /usr/local/bin/nic-watchdog-wrapper.sh
# Or use your preferred editor: vi, vim, etc.
```

```bash
#!/bin/bash
if ! pgrep -f "nic-watchdog.sh" > /dev/null; then
    /usr/local/bin/nic-watchdog >> /var/log/nic-watchdog.log 2>&1 &
fi
```

Make it executable:
```bash
sudo chmod +x /usr/local/bin/nic-watchdog-wrapper.sh
```

## How It Works

1. **Monitoring Loop**: Every 30 seconds (by default), the script tests connectivity by pinging both configured targets
2. **Failure Detection**: If neither ping target responds, the failure counter increments
3. **NIC Restart**: After 3 consecutive failures (by default), the script restarts the network interface
4. **Recovery**: If connectivity is restored, the failure counter resets
5. **Server Reboot**: If the NIC cannot be recovered after 10 minutes of continuous failures, the server is automatically rebooted

### Connectivity Check Logic

The script considers connectivity **successful** if **at least one** of the two ping targets responds. This provides redundancy - if one target is temporarily down, the script won't falsely trigger a NIC restart.

## Troubleshooting

### The script says connectivity failed but the network is working

- **Check your ping targets**: Make sure the IP addresses in `PING_TARGET_1` and `PING_TARGET_2` are reachable from your network
- **Firewall issues**: Ensure ICMP (ping) packets are not blocked by your firewall
- **DNS issues**: Use IP addresses instead of hostnames for ping targets
- **Try changing targets**: Use your gateway IP or another reliable server on your network

### The script doesn't restart the NIC

- **Permission issues**: Make sure you're running the script as root or with sudo
- **Check logs**: Look at system logs with `journalctl -t nic-watchdog`
- **Interface name**: Verify the `NIC` variable matches your actual interface name

### Discord notifications not working

- **Verify webhook URL**: Make sure your Discord webhook URL is correct
- **Check curl**: Ensure curl is installed (`which curl`)
- **Network connectivity**: The script needs internet access to send Discord notifications
- **Test manually**:
  ```bash
  curl -X POST -H "Content-Type: application/json" \
       -d '{"content":"Test message"}' \
       "YOUR_WEBHOOK_URL"
  ```

### The script keeps restarting my NIC unnecessarily

- **Increase FAIL_THRESHOLD**: Raise the number of consecutive failures required before restarting
- **Increase SLEEP_INTERVAL**: Check connectivity less frequently
- **Check ping targets**: Make sure both targets are consistently reachable
- **Network latency**: If your network has high latency, increase the ping timeout (change `-W 2` to `-W 5` in the script)

### How to stop the service

If running as a systemd service:
```bash
sudo systemctl stop nic-watchdog.service
sudo systemctl disable nic-watchdog.service
```

If running manually, press `Ctrl+C` or:
```bash
sudo pkill -f nic-watchdog.sh
```

## Log Files

The script logs to the system journal. View logs with:

```bash
# View all logs
sudo journalctl -t nic-watchdog

# Follow logs in real-time
sudo journalctl -t nic-watchdog -f

# View logs from today
sudo journalctl -t nic-watchdog --since today
```

## Customization

### Changing Ping Timeout

To change how long the script waits for ping responses, modify the `-W` parameter in the ping commands (default is 2 seconds):

```bash
ping -c 1 -W 5 "$PING_TARGET_1"  # Wait 5 seconds instead of 2
```

### Using Your Gateway as a Ping Target

To use your network gateway as a ping target:

```bash
# Find your gateway
ip route | grep default

# Example output: default via 192.168.1.1 dev eth0
# Use 192.168.1.1 as PING_TARGET_1
```

### Adjusting the Server Reboot Timer

The server will reboot if connectivity cannot be restored after 10 minutes. To change this:

```bash
REBOOT_THRESHOLD=$((1200 / SLEEP_INTERVAL))  # 20 minutes (1200 seconds)
```

## Security Considerations

- **Root Access**: This script requires root privileges to restart network interfaces and potentially reboot the server
- **Discord Webhook**: Keep your Discord webhook URL private to prevent spam
- **Network Disruption**: Be cautious when testing - the script will actually restart your network interface
- **Server Reboot**: The script will reboot your server after 10 minutes of connectivity issues

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

This project is open source and available under the MIT License.

## Support

If you encounter issues or have questions:
1. Check the Troubleshooting section above
2. Review the system logs: `sudo journalctl -t nic-watchdog`
3. Open an issue on GitHub

## Credits

Created for monitoring and auto-recovery of network interfaces on Proxmox servers and other Linux systems.
