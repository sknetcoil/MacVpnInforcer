#!/bin/bash

# ============================================================================
# VPN Enforcer V3 - Control Script
# ============================================================================
# Unified management interface for VPN Enforcer.
#
# Usage:
#   sudo vpn_control.sh status   - Show live status dashboard
#   sudo vpn_control.sh bypass   - Activate emergency bypass
#   sudo vpn_control.sh logs     - View recent log entries
#   sudo vpn_control.sh test     - Test VPN detection
#   sudo vpn_control.sh restart  - Restart the daemon
# ============================================================================

# --- Colors & Symbols --------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

# Status indicators
ICON_SHIELD_ON="${GREEN}[PROTECTED]${NC}"
ICON_SHIELD_OFF="${RED}[UNPROTECTED]${NC}"
ICON_BYPASS="${YELLOW}[BYPASS]${NC}"
ICON_OK="${GREEN}OK${NC}"
ICON_FAIL="${RED}FAIL${NC}"
ICON_WARN="${YELLOW}WARN${NC}"

# --- Paths -------------------------------------------------------------------
CONFIG_FILE="/etc/vpn_enforcer.conf"
SECURE_DIR="/var/run/vpnenforcer"
BYPASS_FLAG_FILE="$SECURE_DIR/bypass.flag"
STATE_FILE="$SECURE_DIR/state"
PID_FILE="$SECURE_DIR/vpn_enforcer.pid"
LOG_FILE="/var/log/vpn_enforcer.log"
BYPASS_LOG="$SECURE_DIR/bypass_audit.log"
PLIST="/Library/LaunchDaemons/com.user.vpnenforcer.plist"

# --- Load Config -------------------------------------------------------------
if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
else
    echo -e "${RED}Error:${NC} Config not found at $CONFIG_FILE"
    echo "Run setup.sh to install VPN Enforcer."
    exit 1
fi

BYPASS_DURATION="${BYPASS_DURATION:-300}"

# --- Helper Functions --------------------------------------------------------
check_root() {
    if [ "$EUID" -ne 0 ]; then
        echo -e "${RED}Error:${NC} This command requires root. Use: ${BOLD}sudo vpn_control.sh $1${NC}"
        exit 1
    fi
}

is_daemon_running() {
    if [ -f "$PID_FILE" ]; then
        local pid
        pid=$(cat "$PID_FILE" 2>/dev/null)
        if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
            return 0
        fi
    fi
    return 1
}

get_vpn_status() {
    local iface
    for iface in $(ifconfig -l 2>/dev/null); do
        if [[ "$iface" == ${VPN_INTERFACE}* ]]; then
            if ifconfig "$iface" 2>/dev/null | grep -q "inet "; then
                echo "$iface"
                return 0
            fi
        fi
    done
    return 1
}

get_bypass_remaining() {
    if [ -f "$BYPASS_FLAG_FILE" ]; then
        local current_time file_time age remaining
        current_time=$(date +%s)
        file_time=$(stat -f %m "$BYPASS_FLAG_FILE" 2>/dev/null)
        if [ -n "$file_time" ]; then
            age=$((current_time - file_time))
            if [ "$age" -lt "$BYPASS_DURATION" ]; then
                remaining=$((BYPASS_DURATION - age))
                echo "$remaining"
                return 0
            fi
        fi
    fi
    return 1
}

format_duration() {
    local seconds="$1"
    local mins=$((seconds / 60))
    local secs=$((seconds % 60))
    if [ "$mins" -gt 0 ]; then
        printf "%dm %02ds" "$mins" "$secs"
    else
        printf "%ds" "$secs"
    fi
}

# --- Commands ----------------------------------------------------------------

cmd_status() {
    echo ""
    echo -e "${BLUE}${BOLD}  VPN Enforcer V3 - Status${NC}"
    echo -e "${DIM}  $(date '+%Y-%m-%d %H:%M:%S')${NC}"
    echo -e "  ${DIM}──────────────────────────────────────${NC}"

    # Daemon status
    if is_daemon_running; then
        local pid
        pid=$(cat "$PID_FILE" 2>/dev/null)
        echo -e "  Daemon:      ${ICON_OK} (PID $pid)"
    else
        echo -e "  Daemon:      ${ICON_FAIL} NOT RUNNING"
    fi

    # VPN status
    local vpn_iface
    vpn_iface=$(get_vpn_status)
    if [ $? -eq 0 ]; then
        echo -e "  VPN:         ${GREEN}Connected${NC} ($vpn_iface)"
    else
        echo -e "  VPN:         ${RED}Disconnected${NC}"
    fi

    # Enforcement state
    local state="UNKNOWN"
    if [ -f "$STATE_FILE" ]; then
        state=$(cat "$STATE_FILE" 2>/dev/null)
    fi

    local reason=""
    if [ -f "$SECURE_DIR/reason" ]; then
        reason=$(cat "$SECURE_DIR/reason" 2>/dev/null)
    fi

    case "$state" in
        BLOCKED)
            echo -e "  Firewall:    $ICON_SHIELD_ON Traffic blocked"
            ;;
        ALLOWED)
            echo -e "  Firewall:    $ICON_SHIELD_OFF Traffic allowed"
            ;;
        *)
            echo -e "  Firewall:    ${ICON_WARN} Unknown state"
            ;;
    esac

    # Reason
    case "$reason" in
        VPN_CONNECTED)    echo -e "  Reason:      VPN is connected" ;;
        VPN_DISCONNECTED) echo -e "  Reason:      VPN is disconnected" ;;
        BYPASS_ACTIVE)    echo -e "  Reason:      Emergency bypass active" ;;
    esac

    # Bypass status
    local remaining
    remaining=$(get_bypass_remaining)
    if [ $? -eq 0 ]; then
        local formatted
        formatted=$(format_duration "$remaining")
        echo -e "  ${DIM}──────────────────────────────────────${NC}"
        echo -e "  Bypass:      ${YELLOW}ACTIVE${NC} ($formatted remaining)"

        # Progress bar
        local pct=$((remaining * 100 / BYPASS_DURATION))
        local filled=$((pct / 5))
        local empty=$((20 - filled))
        local bar=""
        for ((i=0; i<filled; i++)); do bar+="="; done
        for ((i=0; i<empty; i++)); do bar+="-"; done
        echo -e "  Timer:       ${YELLOW}[${bar}]${NC} ${pct}%"
    fi

    # PF anchor check
    echo -e "  ${DIM}──────────────────────────────────────${NC}"
    local rule_count
    rule_count=$(pfctl -a com.user.vpnenforcer -s rules 2>/dev/null | wc -l | xargs)
    if [ "$rule_count" -gt 0 ]; then
        echo -e "  PF Rules:    ${ICON_OK} ($rule_count rules loaded)"
    else
        echo -e "  PF Rules:    ${DIM}none loaded${NC}"
    fi

    # PF status
    if pfctl -s info 2>/dev/null | grep -q "Status: Enabled"; then
        echo -e "  PF Engine:   ${ICON_OK}"
    else
        echo -e "  PF Engine:   ${ICON_FAIL} DISABLED"
    fi

    echo -e "  ${DIM}──────────────────────────────────────${NC}"
    echo -e "  Config:      $CONFIG_FILE"
    echo -e "  VPN Server:  $VPN_SERVER_IP"
    echo -e "  Interface:   $VPN_INTERFACE"
    echo -e "  Duration:    $(format_duration "$BYPASS_DURATION")"
    [ -n "$ALLOWED_DNS" ] && echo -e "  DNS:         $ALLOWED_DNS"
    echo ""
}

cmd_bypass() {
    check_root "bypass"

    echo ""
    echo -e "${YELLOW}${BOLD}  VPN Enforcer - Emergency Bypass${NC}"
    echo -e "  ${DIM}──────────────────────────────────────${NC}"

    # Check if bypass is already active
    local remaining
    remaining=$(get_bypass_remaining)
    if [ $? -eq 0 ]; then
        local formatted
        formatted=$(format_duration "$remaining")
        echo -e "  Bypass is already active (${YELLOW}$formatted${NC} remaining)."
        echo -n "  Extend with a new $(format_duration "$BYPASS_DURATION") window? (y/n): "
        read -r EXTEND
        if [[ ! "$EXTEND" =~ ^[Yy]$ ]]; then
            echo "  Cancelled."
            return
        fi
    else
        echo "  This grants internet access for $(format_duration "$BYPASS_DURATION") without VPN."
    fi

    echo -n "  Enter bypass password: "
    read -rs PASSWORD
    echo

    if [ -z "$PASSWORD" ]; then
        echo -e "  ${RED}No password entered.${NC}"
        exit 1
    fi

    # Hash and compare
    local input_hash
    input_hash=$(echo -n "$PASSWORD" | shasum -a 256 | awk '{print $1}')
    PASSWORD=""  # Clear from memory

    if [ "$input_hash" = "$BYPASS_PASSWORD_HASH" ]; then
        # Ensure directory exists
        if [ ! -d "$SECURE_DIR" ]; then
            mkdir -p "$SECURE_DIR"
            chmod 700 "$SECURE_DIR"
            chown root:wheel "$SECURE_DIR"
        fi

        touch "$BYPASS_FLAG_FILE"
        chmod 600 "$BYPASS_FLAG_FILE"

        # Audit log
        echo "$(date '+%Y-%m-%d %H:%M:%S') BYPASS_ACTIVATED duration=${BYPASS_DURATION}s user=$(whoami) tty=$(tty 2>/dev/null || echo 'unknown')" >> "$BYPASS_LOG" 2>/dev/null

        echo ""
        echo -e "  ${GREEN}${BOLD}Bypass activated!${NC}"
        echo -e "  Internet access granted for ${YELLOW}$(format_duration "$BYPASS_DURATION")${NC}."
        echo -e "  Access will be revoked automatically."
        echo ""
    else
        # Log failed attempt
        echo "$(date '+%Y-%m-%d %H:%M:%S') BYPASS_FAILED user=$(whoami) tty=$(tty 2>/dev/null || echo 'unknown')" >> "$BYPASS_LOG" 2>/dev/null

        echo -e "  ${RED}Incorrect password.${NC}"
        exit 1
    fi
}

cmd_logs() {
    local lines="${1:-30}"

    echo ""
    echo -e "${BLUE}${BOLD}  VPN Enforcer - Recent Logs${NC}"
    echo -e "  ${DIM}──────────────────────────────────────${NC}"

    if [ -f "$LOG_FILE" ]; then
        tail -n "$lines" "$LOG_FILE" | while IFS= read -r line; do
            # Colorize log levels
            if echo "$line" | grep -q "\[ERROR\]"; then
                echo -e "  ${RED}$line${NC}"
            elif echo "$line" | grep -q "\[WARN\]"; then
                echo -e "  ${YELLOW}$line${NC}"
            elif echo "$line" | grep -q "\[STATE\]"; then
                if echo "$line" | grep -q "BLOCKED"; then
                    echo -e "  ${RED}$line${NC}"
                else
                    echo -e "  ${GREEN}$line${NC}"
                fi
            elif echo "$line" | grep -q "\[AUDIT\]"; then
                echo -e "  ${CYAN}$line${NC}"
            else
                echo -e "  ${DIM}$line${NC}"
            fi
        done
    else
        echo -e "  ${DIM}No log file found at $LOG_FILE${NC}"
    fi

    # Show audit log if exists
    if [ -f "$BYPASS_LOG" ]; then
        echo ""
        echo -e "  ${BOLD}Bypass Audit Trail:${NC}"
        echo -e "  ${DIM}──────────────────────────────────────${NC}"
        tail -n 5 "$BYPASS_LOG" | while IFS= read -r line; do
            if echo "$line" | grep -q "FAILED"; then
                echo -e "  ${RED}$line${NC}"
            else
                echo -e "  ${YELLOW}$line${NC}"
            fi
        done
    fi
    echo ""
}

cmd_test() {
    echo ""
    echo -e "${BLUE}${BOLD}  VPN Enforcer - Diagnostics${NC}"
    echo -e "  ${DIM}──────────────────────────────────────${NC}"

    # Check config
    echo -e "  ${BOLD}Configuration:${NC}"
    if [ -f "$CONFIG_FILE" ]; then
        echo -e "    Config file:   ${ICON_OK}"
    else
        echo -e "    Config file:   ${ICON_FAIL} Missing"
    fi

    # Check daemon
    echo -e "  ${BOLD}Daemon:${NC}"
    if is_daemon_running; then
        echo -e "    Process:       ${ICON_OK}"
    else
        echo -e "    Process:       ${ICON_FAIL} Not running"
    fi

    if launchctl list 2>/dev/null | grep -q "com.user.vpnenforcer"; then
        echo -e "    LaunchDaemon:  ${ICON_OK} Loaded"
    else
        echo -e "    LaunchDaemon:  ${ICON_FAIL} Not loaded"
    fi

    # Check PF
    echo -e "  ${BOLD}Packet Filter:${NC}"
    if pfctl -s info 2>/dev/null | grep -q "Status: Enabled"; then
        echo -e "    PF Engine:     ${ICON_OK} Enabled"
    else
        echo -e "    PF Engine:     ${ICON_FAIL} Disabled"
    fi

    local rule_count
    rule_count=$(pfctl -a com.user.vpnenforcer -s rules 2>/dev/null | wc -l | xargs)
    echo -e "    Anchor rules:  $rule_count loaded"

    # Check VPN interface
    echo -e "  ${BOLD}Network:${NC}"
    local vpn_iface
    vpn_iface=$(get_vpn_status)
    if [ $? -eq 0 ]; then
        echo -e "    VPN ($VPN_INTERFACE): ${GREEN}UP${NC} on $vpn_iface"
        local vpn_ip
        vpn_ip=$(ifconfig "$vpn_iface" 2>/dev/null | grep "inet " | awk '{print $2}')
        echo -e "    VPN IP:        $vpn_ip"
    else
        echo -e "    VPN ($VPN_INTERFACE): ${RED}DOWN${NC}"
    fi

    # List all interfaces for debugging
    echo -e "    All interfaces: $(ifconfig -l 2>/dev/null)"

    # Check files
    echo -e "  ${BOLD}Files:${NC}"
    for f in "$CONFIG_FILE" "/usr/local/bin/vpn_enforcer.sh" "/usr/local/bin/vpn_control.sh" "$PLIST"; do
        if [ -f "$f" ]; then
            echo -e "    $f  ${ICON_OK}"
        else
            echo -e "    $f  ${ICON_FAIL}"
        fi
    done
    echo ""
}

cmd_restart() {
    check_root "restart"

    echo -e "  Restarting VPN Enforcer daemon..."

    launchctl unload "$PLIST" 2>/dev/null
    sleep 1
    if launchctl load "$PLIST" 2>/dev/null; then
        echo -e "  ${GREEN}Daemon restarted successfully.${NC}"
    else
        echo -e "  ${RED}Failed to restart daemon.${NC}"
        exit 1
    fi
}

cmd_help() {
    echo ""
    echo -e "${BLUE}${BOLD}  VPN Enforcer V3 - Commands${NC}"
    echo -e "  ${DIM}──────────────────────────────────────${NC}"
    echo ""
    echo -e "  ${BOLD}Usage:${NC} sudo vpn_control.sh <command>"
    echo ""
    echo -e "  ${BOLD}Commands:${NC}"
    echo -e "    ${CYAN}status${NC}     Show live status dashboard"
    echo -e "    ${CYAN}bypass${NC}     Activate emergency bypass"
    echo -e "    ${CYAN}logs${NC}       View recent log entries (default: 30 lines)"
    echo -e "    ${CYAN}logs N${NC}     View N recent log entries"
    echo -e "    ${CYAN}test${NC}       Run full diagnostics"
    echo -e "    ${CYAN}restart${NC}    Restart the daemon"
    echo -e "    ${CYAN}help${NC}       Show this help message"
    echo ""
}

# --- Main Dispatch -----------------------------------------------------------
case "${1:-}" in
    status)
        cmd_status
        ;;
    bypass)
        cmd_bypass
        ;;
    logs)
        cmd_logs "${2:-30}"
        ;;
    test)
        cmd_test
        ;;
    restart)
        cmd_restart
        ;;
    help|--help|-h)
        cmd_help
        ;;
    "")
        # Default: show status (backward compatible with V2 which went straight to bypass)
        echo -e "${DIM}  Tip: Use 'sudo vpn_control.sh help' for all commands.${NC}"
        cmd_status
        ;;
    *)
        echo -e "${RED}Unknown command:${NC} $1"
        cmd_help
        exit 1
        ;;
esac
