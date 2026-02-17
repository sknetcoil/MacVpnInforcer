#!/bin/bash

# ============================================================================
# VPN Enforcer V3 - Uninstaller
# ============================================================================
# Completely removes VPN Enforcer and restores default network settings.
# ============================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Error:${NC} Please run as root: ${BOLD}sudo ./uninstall.sh${NC}"
    exit 1
fi

echo ""
echo -e "${RED}${BOLD}================================================${NC}"
echo -e "${RED}${BOLD}       VPN Enforcer V3 - Uninstaller${NC}"
echo -e "${RED}${BOLD}================================================${NC}"
echo ""
echo -e "${YELLOW}This will completely remove VPN Enforcer and${NC}"
echo -e "${YELLOW}restore your default network settings.${NC}"
echo ""
echo -n "Are you sure? (y/n): "
read -r CONFIRM

if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
    echo "Uninstall cancelled."
    exit 0
fi

echo ""

# 1. Stop the daemon
echo -e "  [1/6] Stopping daemon..."
launchctl unload /Library/LaunchDaemons/com.user.vpnenforcer.plist 2>/dev/null

# Also kill process directly if PID file exists
if [ -f "/var/run/vpnenforcer/vpn_enforcer.pid" ]; then
    pid=$(cat /var/run/vpnenforcer/vpn_enforcer.pid 2>/dev/null)
    if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
        kill "$pid" 2>/dev/null
        sleep 1
    fi
fi
echo -e "  ${GREEN}Done${NC}"

# 2. Flush firewall rules FIRST (restore internet access)
echo -e "  [2/6] Restoring network access..."
pfctl -a com.user.vpnenforcer -F all 2>/dev/null
echo -e "  ${GREEN}Done${NC} - Internet access restored"

# 3. Remove installed files
echo -e "  [3/6] Removing installed files..."
rm -f /Library/LaunchDaemons/com.user.vpnenforcer.plist
rm -f /usr/local/bin/vpn_enforcer.sh
rm -f /usr/local/bin/vpn_control.sh
rm -f /etc/pf.anchors/com.user.vpnenforcer
rm -f /etc/newsyslog.d/vpn_enforcer.conf
echo -e "  ${GREEN}Done${NC}"

# 4. Remove configuration (ask first)
echo -n "  [4/6] Remove configuration (/etc/vpn_enforcer.conf)? (y/n): "
read -r RM_CONFIG
if [[ "$RM_CONFIG" =~ ^[Yy]$ ]]; then
    rm -f /etc/vpn_enforcer.conf
    echo -e "  ${GREEN}Done${NC} - Configuration removed"
else
    echo -e "  ${YELLOW}Kept${NC} - Configuration preserved for reinstall"
fi

# 5. Remove secure directory and state files
echo -e "  [5/6] Removing state files..."
rm -rf /var/run/vpnenforcer
echo -e "  ${GREEN}Done${NC}"

# 6. Remove logs (ask first)
echo -n "  [6/6] Remove log files? (y/n): "
read -r RM_LOGS
if [[ "$RM_LOGS" =~ ^[Yy]$ ]]; then
    rm -f /var/log/vpn_enforcer.log*
    rm -f /var/log/vpn_enforcer.err*
    echo -e "  ${GREEN}Done${NC} - Logs removed"
else
    echo -e "  ${YELLOW}Kept${NC} - Logs preserved at /var/log/vpn_enforcer.log"
fi

echo ""
echo -e "${GREEN}${BOLD}================================================${NC}"
echo -e "${GREEN}${BOLD}       Uninstallation Complete${NC}"
echo -e "${GREEN}${BOLD}================================================${NC}"
echo ""
echo -e "  Your system has been restored to default network settings."
echo -e "  Internet access should work normally without VPN."
echo ""
