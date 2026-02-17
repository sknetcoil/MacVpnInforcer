# macOS VPN Enforcer

A robust security tool for macOS that blocks all internet traffic unless a designated VPN is active. Runs as a system daemon with instant reaction to network changes.

## Overview

VPN Enforcer monitors your network state and automatically blocks outbound traffic whenever your VPN disconnects. It uses macOS's built-in Packet Filter (PF) firewall and `scutil` event monitoring for sub-second response times.

## Features

- **Instant enforcement** - Event-driven monitoring via `scutil` reacts to VPN drops in < 1 second
- **Fail-closed design** - If the daemon stops or crashes, traffic stays blocked
- **Multiple VPN servers** - Support for comma-separated server IPs
- **Configurable DNS** - Optionally restrict DNS queries to specific servers
- **Secure bypass** - Password-protected temporary internet access with audit trail
- **Status dashboard** - Color-coded live status with `vpn_control.sh status`
- **Diagnostics** - Built-in test command to verify all components
- **Health monitoring** - Self-healing checks ensure PF stays enabled and rules stay loaded
- **Log management** - Automatic rotation, color-coded log viewer
- **Upgrade-safe** - Setup detects existing installs and offers clean upgrades

## Installation

### Prerequisites
- macOS (tested on Ventura, Sonoma, Sequoia)
- Root privileges (`sudo`)
- Your VPN server IP address

### Steps
```bash
chmod +x setup.sh
sudo ./setup.sh
```

The installer will prompt for:
1. VPN server IP(s) - supports multiple, comma-separated
2. VPN interface prefix (default: `utun`)
3. DNS servers (optional restriction)
4. Bypass duration (default: 5 minutes)
5. Bypass password

## Usage

### Management Commands

```bash
# Show live status dashboard
sudo vpn_control.sh status

# Activate emergency bypass
sudo vpn_control.sh bypass

# View color-coded logs
sudo vpn_control.sh logs

# Run full diagnostics
sudo vpn_control.sh test

# Restart the daemon
sudo vpn_control.sh restart
```

### How It Works
- **VPN Connected** - Internet works normally
- **VPN Disconnected** - All outbound traffic blocked immediately (except VPN server, DNS, DHCP)
- **Bypass Active** - Temporary unrestricted access for the configured duration

## Uninstallation

```bash
sudo ./uninstall.sh
```

Prompts to keep or remove configuration and logs.

## Version History

### V3 (Current)
- Fixed orphaned `scutil` process bug (proper PID tracking via named pipe)
- Fixed unreachable cleanup code after infinite loop
- Fixed VPN interface detection (exact match instead of substring)
- Added input validation for IP addresses
- Added multiple VPN server support
- Added configurable DNS restrictions
- Added configurable bypass duration (30s-3600s)
- Added unified control script with subcommands (status/bypass/logs/test/restart)
- Added color-coded status dashboard with bypass timer
- Added bypass audit trail with failed attempt logging
- Added PID file for process management
- Added health self-checks (PF enabled, rules loaded)
- Added upgrade path from V2
- Added confirmation prompts in uninstaller
- Improved LaunchDaemon with throttle interval and conditional keep-alive
- Improved logging with levels (INFO/WARN/ERROR/STATE/AUDIT)

### V2
- Event-driven monitoring via `scutil`
- Secure bypass storage in `/var/run/vpnenforcer/`
- Log rotation via newsyslog
- State caching to avoid redundant firewall reloads
- Signal handling (fail-closed on SIGTERM/SIGINT)

### V1
- Basic 5-second polling loop
- Simple bypass in `/tmp/` (insecure)
- Minimal logging

## Technical Details

| Component | Location |
|-----------|----------|
| Daemon script | `/usr/local/bin/vpn_enforcer.sh` |
| Control script | `/usr/local/bin/vpn_control.sh` |
| Configuration | `/etc/vpn_enforcer.conf` |
| PF anchor | `/etc/pf.anchors/com.user.vpnenforcer` |
| Logs | `/var/log/vpn_enforcer.log` |
| State files | `/var/run/vpnenforcer/` |
| LaunchDaemon | `/Library/LaunchDaemons/com.user.vpnenforcer.plist` |

## Disclaimer

This tool modifies your system's firewall rules. Use at your own risk. Ensure you have the correct VPN server IP, or you may lock yourself out of the internet until you use the bypass or uninstall the tool.
