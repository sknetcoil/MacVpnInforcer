#!/bin/bash

# Configuration
CONFIG_FILE="/etc/vpn_enforcer.conf"

# Read configuration
if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
else
    echo "Error: Configuration file not found at $CONFIG_FILE"
    exit 1
fi

# Constants
PF_ANCHOR_NAME="com.user.vpnenforcer"
PF_ANCHOR_FILE="/etc/pf.anchors/com.user.vpnenforcer"
BYPASS_FLAG_FILE="/tmp/vpn_enforcer_bypass"
BYPASS_DURATION=300 # 5 minutes

# Function to check if VPN is connected
check_vpn() {
    # Check if the VPN interface exists and is up
    if ifconfig | grep -q "$VPN_INTERFACE"; then
        return 0 # VPN is UP
    else
        return 1 # VPN is DOWN
    fi
}

# Function to enable restrictive firewall rules
enable_firewall() {
    echo "VPN DOWN. Enabling firewall restrictions..."
    
    # Create the anchor file if it doesn't exist
    if [ ! -f "$PF_ANCHOR_FILE" ]; then
        echo "Creating PF anchor file..."
        # Block everything by default on physical interfaces, allow local, allow VPN server
        cat <<EOF > "$PF_ANCHOR_FILE"
# Macros
vpn_server = "$VPN_SERVER_IP"

# Options
set block-policy drop
set skip on lo0

# Block all outgoing traffic by default
block out all

# Allow traffic to VPN server
pass out proto udp from any to \$vpn_server
pass out proto tcp from any to \$vpn_server

# Allow DHCP (bootps/bootpc)
pass out proto udp from any port 68 to any port 67
pass out proto udp from any port 67 to any port 68

# Allow DNS (optional, might need to restrict to specific servers)
pass out proto udp from any to any port 53
pass out proto tcp from any to any port 53
EOF
    fi

    # Load the anchor
    pfctl -a "$PF_ANCHOR_NAME" -f "$PF_ANCHOR_FILE" 2>/dev/null
    pfctl -e 2>/dev/null # Ensure PF is enabled
}

# Function to disable restrictive firewall rules
disable_firewall() {
    echo "VPN UP. Disabling firewall restrictions..."
    pfctl -a "$PF_ANCHOR_NAME" -F all 2>/dev/null
}

# Function to check bypass status
check_bypass() {
    if [ -f "$BYPASS_FLAG_FILE" ]; then
        # Check if the bypass file is older than the duration
        current_time=$(date +%s)
        file_time=$(stat -f %m "$BYPASS_FLAG_FILE")
        age=$((current_time - file_time))
        
        if [ "$age" -lt "$BYPASS_DURATION" ]; then
            echo "Bypass active ($((BYPASS_DURATION - age))s remaining)."
            return 0 # Bypass IS active
        else
            echo "Bypass expired."
            rm "$BYPASS_FLAG_FILE"
            return 1 # Bypass is NOT active
        fi
    fi
    return 1 # Bypass is NOT active
}

# Main Loop
while true; do
    if check_bypass; then
        disable_firewall
    elif check_vpn; then
        disable_firewall
    else
        enable_firewall
    fi
    sleep 5
done
