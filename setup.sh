#!/bin/bash

# ============================================================================
# VPN Enforcer V3 - Setup Script
# ============================================================================
# Installs and configures the VPN Enforcer daemon with input validation,
# multi-server support, configurable DNS, and upgrade-safe installation.
# ============================================================================

# --- Colors & Formatting ----------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

print_header() {
    echo ""
    echo -e "${BLUE}${BOLD}================================================${NC}"
    echo -e "${BLUE}${BOLD}       VPN Enforcer V3 - Setup${NC}"
    echo -e "${BLUE}${BOLD}================================================${NC}"
    echo ""
}

print_step() {
    echo -e "${CYAN}[$1/$TOTAL_STEPS]${NC} ${BOLD}$2${NC}"
}

print_ok() {
    echo -e "  ${GREEN}OK${NC} $1"
}

print_warn() {
    echo -e "  ${YELLOW}WARN${NC} $1"
}

print_fail() {
    echo -e "  ${RED}FAIL${NC} $1"
}

TOTAL_STEPS=9

# --- Root Check --------------------------------------------------------------
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Error:${NC} Please run as root: ${BOLD}sudo ./setup.sh${NC}"
    exit 1
fi

print_header

# --- Check for existing installation (upgrade path) -------------------------
UPGRADE=false
if [ -f "/etc/vpn_enforcer.conf" ]; then
    echo -e "${YELLOW}Existing VPN Enforcer installation detected.${NC}"
    echo -n "Upgrade to V3? (y/n): "
    read -r UPGRADE_CHOICE
    if [[ "$UPGRADE_CHOICE" =~ ^[Yy]$ ]]; then
        UPGRADE=true
        echo -e "${GREEN}Upgrading...${NC} Existing config will be preserved."
        source /etc/vpn_enforcer.conf
        echo ""
    else
        echo "Aborting. Run uninstall.sh first to do a clean install."
        exit 0
    fi
fi

# --- Validate IP address format ----------------------------------------------
validate_ip() {
    local ip="$1"
    # Match IPv4 format: N.N.N.N where N is 0-255
    if [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
        local IFS='.'
        read -ra octets <<< "$ip"
        for octet in "${octets[@]}"; do
            if [ "$octet" -gt 255 ]; then
                return 1
            fi
        done
        return 0
    fi
    return 1
}

# --- Step 1: VPN Server IP(s) -----------------------------------------------
print_step 1 "VPN Server Configuration"

if [ "$UPGRADE" = true ] && [ -n "$VPN_SERVER_IP" ]; then
    echo -e "  Current VPN server(s): ${GREEN}$VPN_SERVER_IP${NC}"
    echo -n "  Keep current setting? (y/n): "
    read -r KEEP_IP
    if [[ "$KEEP_IP" =~ ^[Yy]$ ]]; then
        FINAL_VPN_IP="$VPN_SERVER_IP"
    fi
fi

if [ -z "$FINAL_VPN_IP" ]; then
    echo "  Enter VPN server IP address(es)."
    echo -e "  ${CYAN}Tip:${NC} For multiple servers, separate with commas (e.g., 1.2.3.4,5.6.7.8)"
    echo -n "  VPN Server IP(s): "
    read -r FINAL_VPN_IP

    if [ -z "$FINAL_VPN_IP" ]; then
        print_fail "VPN server IP is required."
        exit 1
    fi

    # Validate each IP
    local_IFS="$IFS"
    IFS=','
    for ip in $FINAL_VPN_IP; do
        ip="$(echo "$ip" | xargs)"  # trim
        if ! validate_ip "$ip"; then
            print_fail "Invalid IP address: $ip"
            exit 1
        fi
    done
    IFS="$local_IFS"
fi
print_ok "VPN Server(s): $FINAL_VPN_IP"

# --- Step 2: VPN Interface ---------------------------------------------------
print_step 2 "VPN Interface Configuration"

if [ "$UPGRADE" = true ] && [ -n "$VPN_INTERFACE" ]; then
    echo -e "  Current interface: ${GREEN}$VPN_INTERFACE${NC}"
    echo -n "  Keep current setting? (y/n): "
    read -r KEEP_IFACE
    if [[ "$KEEP_IFACE" =~ ^[Yy]$ ]]; then
        FINAL_VPN_INTERFACE="$VPN_INTERFACE"
    fi
fi

if [ -z "$FINAL_VPN_INTERFACE" ]; then
    echo "  Enter the VPN interface name prefix."
    echo -e "  ${CYAN}Tip:${NC} Common values: utun (most VPNs), ipsec, ppp"
    echo -e "  ${CYAN}Tip:${NC} Run 'ifconfig' while VPN is connected to find yours."
    echo -n "  Interface prefix [utun]: "
    read -r IFACE_INPUT
    FINAL_VPN_INTERFACE="${IFACE_INPUT:-utun}"
fi
print_ok "Interface: $FINAL_VPN_INTERFACE"

# --- Step 3: DNS Servers (new in V3) ----------------------------------------
print_step 3 "DNS Configuration"

FINAL_DNS=""
if [ "$UPGRADE" = true ] && [ -n "$ALLOWED_DNS" ]; then
    echo -e "  Current DNS servers: ${GREEN}$ALLOWED_DNS${NC}"
    echo -n "  Keep current setting? (y/n): "
    read -r KEEP_DNS
    if [[ "$KEEP_DNS" =~ ^[Yy]$ ]]; then
        FINAL_DNS="$ALLOWED_DNS"
    fi
fi

if [ -z "$FINAL_DNS" ]; then
    echo "  Restrict DNS queries to specific servers for better security."
    echo -e "  ${CYAN}Tip:${NC} Comma-separated (e.g., 8.8.8.8,1.1.1.1). Leave empty to allow all."
    echo -n "  DNS Servers [allow all]: "
    read -r DNS_INPUT

    if [ -n "$DNS_INPUT" ]; then
        # Validate DNS IPs
        local_IFS="$IFS"
        IFS=','
        for ip in $DNS_INPUT; do
            ip="$(echo "$ip" | xargs)"
            if ! validate_ip "$ip"; then
                print_fail "Invalid DNS IP: $ip"
                exit 1
            fi
        done
        IFS="$local_IFS"
        FINAL_DNS="$DNS_INPUT"
        print_ok "DNS restricted to: $FINAL_DNS"
    else
        print_ok "DNS: unrestricted (all servers allowed)"
    fi
fi

# --- Step 4: Bypass Duration (new in V3) ------------------------------------
print_step 4 "Bypass Configuration"

FINAL_BYPASS_DURATION="${BYPASS_DURATION:-300}"
if [ "$UPGRADE" != true ]; then
    echo "  How long should bypass access last? (in seconds)"
    echo -n "  Bypass duration [300]: "
    read -r DURATION_INPUT
    if [ -n "$DURATION_INPUT" ]; then
        if ! [[ "$DURATION_INPUT" =~ ^[0-9]+$ ]] || [ "$DURATION_INPUT" -lt 30 ] || [ "$DURATION_INPUT" -gt 3600 ]; then
            print_fail "Duration must be between 30 and 3600 seconds."
            exit 1
        fi
        FINAL_BYPASS_DURATION="$DURATION_INPUT"
    fi
fi
print_ok "Bypass duration: ${FINAL_BYPASS_DURATION}s ($(( FINAL_BYPASS_DURATION / 60 ))m $(( FINAL_BYPASS_DURATION % 60 ))s)"

# --- Step 5: Bypass Password ------------------------------------------------
print_step 5 "Bypass Password"

if [ "$UPGRADE" = true ] && [ -n "$BYPASS_PASSWORD_HASH" ]; then
    echo -n "  Change bypass password? (y/n): "
    read -r CHANGE_PASS
    if [[ "$CHANGE_PASS" =~ ^[Nn]$ ]]; then
        FINAL_HASH="$BYPASS_PASSWORD_HASH"
    fi
fi

if [ -z "$FINAL_HASH" ]; then
    echo "  Set a password for emergency bypass access."
    echo -n "  Password: "
    read -rs ADMIN_PASSWORD
    echo

    if [ -z "$ADMIN_PASSWORD" ]; then
        print_fail "Password cannot be empty."
        exit 1
    fi

    if [ ${#ADMIN_PASSWORD} -lt 4 ]; then
        print_fail "Password must be at least 4 characters."
        exit 1
    fi

    echo -n "  Confirm password: "
    read -rs ADMIN_PASSWORD_CONFIRM
    echo

    if [ "$ADMIN_PASSWORD" != "$ADMIN_PASSWORD_CONFIRM" ]; then
        print_fail "Passwords do not match."
        exit 1
    fi

    FINAL_HASH=$(echo -n "$ADMIN_PASSWORD" | shasum -a 256 | awk '{print $1}')
    # Clear password from memory
    ADMIN_PASSWORD=""
    ADMIN_PASSWORD_CONFIRM=""
fi
print_ok "Password configured"

# --- Step 6: Write Configuration File ----------------------------------------
print_step 6 "Writing configuration"

CONFIG_FILE="/etc/vpn_enforcer.conf"
cat <<EOF > "$CONFIG_FILE"
# VPN Enforcer V3 Configuration
# Generated: $(date '+%Y-%m-%d %H:%M:%S')

# VPN server IP(s) - comma-separated for multiple
VPN_SERVER_IP="$FINAL_VPN_IP"

# VPN interface prefix (e.g., utun, ipsec, ppp)
VPN_INTERFACE="$FINAL_VPN_INTERFACE"

# Bypass password hash (SHA-256)
BYPASS_PASSWORD_HASH="$FINAL_HASH"

# Bypass duration in seconds (default: 300 = 5 minutes)
BYPASS_DURATION=$FINAL_BYPASS_DURATION

# Polling interval in seconds (default: 5)
POLL_INTERVAL=5

# Allowed DNS servers - comma-separated (empty = allow all)
ALLOWED_DNS="$FINAL_DNS"
EOF
chmod 600 "$CONFIG_FILE"
chown root:wheel "$CONFIG_FILE"
print_ok "$CONFIG_FILE"

# --- Step 7: Create directories & install files ------------------------------
print_step 7 "Installing files"

# Secure directory
SECURE_DIR="/var/run/vpnenforcer"
mkdir -p "$SECURE_DIR"
chmod 700 "$SECURE_DIR"
chown root:wheel "$SECURE_DIR"
print_ok "Secure directory: $SECURE_DIR"

# Install scripts
INSTALL_DIR="/usr/local/bin"
mkdir -p "$INSTALL_DIR"
cp vpn_enforcer.sh "$INSTALL_DIR/vpn_enforcer.sh"
cp vpn_control.sh "$INSTALL_DIR/vpn_control.sh"
chmod 755 "$INSTALL_DIR/vpn_enforcer.sh"
chmod 755 "$INSTALL_DIR/vpn_control.sh"
print_ok "Scripts installed to $INSTALL_DIR"

# --- Step 8: Install LaunchDaemon -------------------------------------------
print_step 8 "Configuring system daemon"

PLIST_DEST="/Library/LaunchDaemons/com.user.vpnenforcer.plist"

# Stop existing daemon if running
launchctl unload "$PLIST_DEST" 2>/dev/null

cp com.user.vpnenforcer.plist "$PLIST_DEST"
chown root:wheel "$PLIST_DEST"
chmod 644 "$PLIST_DEST"
print_ok "LaunchDaemon installed"

# Configure log rotation
NEWSYSLOG_FILE="/etc/newsyslog.d/vpn_enforcer.conf"
echo "/var/log/vpn_enforcer.log  root:wheel  640  5  1024  *  Z" > "$NEWSYSLOG_FILE"
print_ok "Log rotation configured"

# --- Step 9: Start daemon ----------------------------------------------------
print_step 9 "Starting VPN Enforcer"

# Enable PF
if pfctl -e 2>/dev/null; then
    print_ok "Packet Filter enabled"
else
    # pfctl returns 1 if already enabled
    print_ok "Packet Filter already enabled"
fi

# Load daemon
if launchctl load "$PLIST_DEST" 2>/dev/null; then
    print_ok "Daemon started"
else
    print_fail "Failed to start daemon. Check: sudo launchctl list | grep vpn"
    exit 1
fi

# --- Done! -------------------------------------------------------------------
echo ""
echo -e "${GREEN}${BOLD}================================================${NC}"
echo -e "${GREEN}${BOLD}       Installation Complete!${NC}"
echo -e "${GREEN}${BOLD}================================================${NC}"
echo ""
echo -e "  ${BOLD}Status:${NC}      sudo vpn_control.sh status"
echo -e "  ${BOLD}Bypass:${NC}      sudo vpn_control.sh bypass"
echo -e "  ${BOLD}Logs:${NC}        sudo vpn_control.sh logs"
echo -e "  ${BOLD}Uninstall:${NC}   sudo ./uninstall.sh"
echo ""
echo -e "  ${YELLOW}Test it:${NC} Disconnect your VPN and try browsing - it should fail."
echo ""
