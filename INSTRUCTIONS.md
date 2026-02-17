# VPN Enforcer V3 - Quick Start

## Installation

```bash
cd /Users/snirkadosh/WebApps/MacVpn
chmod +x setup.sh uninstall.sh
sudo ./setup.sh
```

Follow the prompts to configure your VPN server, interface, and bypass password.

## Verify It Works

```bash
# Check status
sudo vpn_control.sh status

# Run diagnostics
sudo vpn_control.sh test
```

Then disconnect your VPN - browsing should fail immediately. Reconnect - it should work again.

## Daily Commands

| Command | What it does |
|---------|-------------|
| `sudo vpn_control.sh status` | Live status dashboard |
| `sudo vpn_control.sh bypass` | Temporary internet without VPN |
| `sudo vpn_control.sh logs` | View recent activity |
| `sudo vpn_control.sh test` | Full system diagnostics |
| `sudo vpn_control.sh restart` | Restart the daemon |

## Upgrading from V2

Run `sudo ./setup.sh` - it detects V2 and offers to upgrade while preserving your existing configuration.

## Uninstall

```bash
sudo ./uninstall.sh
```
