#!/bin/bash

# Setup Script for VPN Enforcer
# This script installs the necessary files and configures the system.

if [ "$EUID" -ne 0 ]; then
  echo "Please run as root (sudo ./setup.sh)"
  exit 1
fi

echo "Welcome to the VPN Enforcer Setup"

# 1. Gather Configuration
echo "Please enter the IP address of your allowed VPN server:"
read VPN_SERVER_IP

echo "Please enter the VPN interface name (e.g., utun0, or leave empty for 'utun'):"
read VPN_INTERFACE_INPUT
VPN_INTERFACE="${VPN_INTERFACE_INPUT:-utun}"

echo "Set a password for bypassing the VPN restriction:"
read -s ADMIN_PASSWORD
echo
echo "Confirm password:"
read -s ADMIN_PASSWORD_CONFIRM
echo

if [ "$ADMIN_PASSWORD" != "$ADMIN_PASSWORD_CONFIRM" ]; then
    echo "Passwords do not match. Aborting."
    exit 1
fi

# Generate Hash
BYPASS_PASSWORD_HASH=$(echo -n "$ADMIN_PASSWORD" | shasum -a 256 | awk '{print $1}')

# 2. Create Configuration File
CONFIG_FILE="/etc/vpn_enforcer.conf"
echo "Creating configuration file at $CONFIG_FILE..."
cat <<EOF > "$CONFIG_FILE"
VPN_SERVER_IP="$VPN_SERVER_IP"
VPN_INTERFACE="$VPN_INTERFACE"
BYPASS_PASSWORD_HASH="$BYPASS_PASSWORD_HASH"
EOF
chmod 600 "$CONFIG_FILE"

# 3. Install Scripts
INSTALL_DIR="/usr/local/bin"
echo "Installing scripts to $INSTALL_DIR..."
cp vpn_enforcer.sh "$INSTALL_DIR/vpn_enforcer.sh"
cp vpn_control.sh "$INSTALL_DIR/vpn_control.sh"
chmod +x "$INSTALL_DIR/vpn_enforcer.sh"
chmod +x "$INSTALL_DIR/vpn_control.sh"

# 4. Install LaunchDaemon
PLIST_SOURCE="com.user.vpnenforcer.plist"
PLIST_DEST="/Library/LaunchDaemons/com.user.vpnenforcer.plist"
echo "Installing LaunchDaemon to $PLIST_DEST..."
cp "$PLIST_SOURCE" "$PLIST_DEST"
chown root:wheel "$PLIST_DEST"
chmod 644 "$PLIST_DEST"

# 5. Enable Packet Filter (PF)
echo "Enabling Packet Filter..."
pfctl -e 2>/dev/null

# 6. Load Daemon
echo "Loading Daemon..."
launchctl unload "$PLIST_DEST" 2>/dev/null
launchctl load "$PLIST_DEST"

echo "Installation Complete!"
echo "The VPN Enforcer is now running."
echo "To bypass the restriction, run: sudo vpn_control.sh"
