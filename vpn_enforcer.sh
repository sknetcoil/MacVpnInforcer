#!/bin/bash

# VPN Enforcer V2 - Robust & Event-Driven
# 
# This script monitors network state changes using scutil and enforces
# firewall rules when the VPN is not connected.

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
LOG_FILE="/var/log/vpn_enforcer.log"
SECURE_DIR="/var/run/vpnenforcer"
BYPASS_FLAG_FILE="$SECURE_DIR/bypass.flag"
BYPASS_DURATION=300 # 5 minutes

# State tracking
CURRENT_STATE="UNKNOWN"

# logging function
log_message() {
    local message="$1"
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $message" >> "$LOG_FILE"
}

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
    if [ "$CURRENT_STATE" == "BLOCKED" ]; then return; fi
    
    log_message "Action: Enabling firewall restrictions (VPN DOWN)..."
    
    # Create the anchor file if it doesn't exist
    if [ ! -f "$PF_ANCHOR_FILE" ]; then
        log_message "Creating PF anchor file..."
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
    
    CURRENT_STATE="BLOCKED"
    log_message "State changed to: BLOCKED"
}

# Function to disable restrictive firewall rules
disable_firewall() {
    if [ "$CURRENT_STATE" == "ALLOWED" ]; then return; fi

    log_message "Action: Disabling firewall restrictions (VPN UP or BYPASS)..."
    pfctl -a "$PF_ANCHOR_NAME" -F all 2>/dev/null
    
    CURRENT_STATE="ALLOWED"
    log_message "State changed to: ALLOWED"
}

# Function to check bypass status
check_bypass() {
    if [ -f "$BYPASS_FLAG_FILE" ]; then
        # Check if the bypass file is older than the duration
        current_time=$(date +%s)
        file_time=$(stat -f %m "$BYPASS_FLAG_FILE")
        age=$((current_time - file_time))
        
        if [ "$age" -lt "$BYPASS_DURATION" ]; then
            return 0 # Bypass IS active
        else
            log_message "Bypass expired (auto-cleanup)."
            rm "$BYPASS_FLAG_FILE"
            return 1 # Bypass is NOT active
        fi
    fi
    return 1 # Bypass is NOT active
}

# Main enforcement logic
evaluate_state() {
    if check_bypass; then
        disable_firewall
    elif check_vpn; then
        disable_firewall
    else
        enable_firewall
    fi
}

# Cleanup on exit (Fail-Closed default, but logs exit)
cleanup() {
    log_message "Daemon stopping. Ensuring firewall is ACTIVE (Fail-Closed)..."
    enable_firewall
    exit 0
}

# Trap signals
trap cleanup SIGTERM SIGINT

log_message "VPN Enforcer V2 started."
mkdir -p "$SECURE_DIR"
chmod 700 "$SECURE_DIR"

# Initial check
evaluate_state

# Monitor loop using scutil
# We watch for changes in IPv4 configuration, which happens on connect/disconnect
log_message "Starting event monitoring..."

# Using coprocess to read output of scutil --monitor
# It outputs "Key ..." when changes happen.
# We also wake up every 10 seconds just in case of missed events or to check bypass expiry.
( scutil --monitor State:/Network/Global/IPv4 ) | while read -r line; do
    evaluate_state
done &

PID_SCUTIL=$!

# Main loop to check bypass expiry (since scutil won't trigger on file time)
while true; do
    evaluate_state
    sleep 5
done

kill $PID_SCUTIL
