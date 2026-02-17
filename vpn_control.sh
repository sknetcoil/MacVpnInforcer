#!/bin/bash

# Configuration
CONFIG_FILE="/etc/vpn_enforcer.conf"
SECURE_DIR="/var/run/vpnenforcer"
BYPASS_FLAG_FILE="$SECURE_DIR/bypass.flag"

# Read configuration
if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
else
    echo "Error: Configuration file not found at $CONFIG_FILE"
    exit 1
fi

echo "VPN Enforcer - Emergency Bypass"
echo "This will grant internet access for 5 minutes without VPN."
echo "Enter bypass password:"
read -s PASSWORD
echo

# Calculate hash
INPUT_HASH=$(echo -n "$PASSWORD" | shasum -a 256 | awk '{print $1}')

if [ "$INPUT_HASH" == "$BYPASS_PASSWORD_HASH" ]; then
    echo "Password correct."
    
    # Ensure directory exists (it should be created by the daemon/setup, but fail-safe)
    if [ ! -d "$SECURE_DIR" ]; then
        echo "Error: Secure directory not found. Is the VPN Enforcer daemon running?"
        exit 1
    fi
    
    touch "$BYPASS_FLAG_FILE"
    echo "Internet access enabled for 5 minutes."
else
    echo "Incorrect password."
    exit 1
fi
