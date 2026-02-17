#!/bin/bash

# Configuration
CONFIG_FILE="/etc/vpn_enforcer.conf"
BYPASS_FLAG_FILE="/tmp/vpn_enforcer_bypass"

# Read configuration
if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
else
    echo "Error: Configuration file not found at $CONFIG_FILE"
    exit 1
fi

echo "Enter bypass password:"
read -s PASSWORD

# Calculate hash
INPUT_HASH=$(echo -n "$PASSWORD" | shasum -a 256 | awk '{print $1}')

if [ "$INPUT_HASH" == "$BYPASS_PASSWORD_HASH" ]; then
    echo "Password correct. Internet access enabled for 5 minutes."
    touch "$BYPASS_FLAG_FILE"
else
    echo "Incorrect password."
    exit 1
fi
