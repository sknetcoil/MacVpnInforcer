#!/bin/bash

# Uninstaller for VPN Enforcer V2
# Removes all components and restores network settings.

if [ "$EUID" -ne 0 ]; then
  echo "Please run as root (sudo ./uninstall.sh)"
  exit 1
fi

echo "Uninstalling VPN Enforcer V2..."

# 1. Unload LaunchDaemon
echo "Unloading LaunchDaemon..."
launchctl unload /Library/LaunchDaemons/com.user.vpnenforcer.plist 2>/dev/null

# 2. Remove Files
echo "Removing files...
- LaunchDaemon
- Scripts
- Configuration
- PF Anchor
- Log Rotation Config
"

rm -f /Library/LaunchDaemons/com.user.vpnenforcer.plist
rm -f /usr/local/bin/vpn_enforcer.sh
rm -f /usr/local/bin/vpn_control.sh
rm -f /etc/vpn_enforcer.conf
rm -f /etc/pf.anchors/com.user.vpnenforcer
rm -f /etc/newsyslog.d/vpn_enforcer.conf

# 3. Remove Secure Directory
echo "Removing secure directory..."
rm -rf /var/run/vpnenforcer

# 4. Flush PF Rules
echo "Flushing Firewall Rules..."
pfctl -a com.user.vpnenforcer -F all 2>/dev/null

# 5. Remove Logs (Optional, ask user?)
# For now, we'll just remove them to be clean
echo "Removing Logs..."
rm -f /var/log/vpn_enforcer.log*

echo "Uninstallation Complete. System restored to original state."
