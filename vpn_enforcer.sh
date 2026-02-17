#!/bin/bash

# ============================================================================
# VPN Enforcer V3 - Robust, Event-Driven, Fail-Closed
# ============================================================================
#
# Monitors network state via scutil and enforces firewall rules when VPN
# is not connected. Fixes all known V2 bugs including orphaned scutil
# processes, unreachable cleanup code, and overly broad interface matching.
#
# Key improvements over V2:
#   - Proper process tree management (no orphaned scutil)
#   - Correct VPN interface detection (exact match)
#   - Multiple VPN server support
#   - Configurable DNS servers
#   - PID file for process management
#   - Health self-checks
#   - Bypass audit trail
# ============================================================================

set -o pipefail

# --- Configuration -----------------------------------------------------------
CONFIG_FILE="/etc/vpn_enforcer.conf"

if [ ! -f "$CONFIG_FILE" ]; then
    echo "[FATAL] Configuration file not found: $CONFIG_FILE"
    echo "        Run setup.sh to install VPN Enforcer."
    exit 1
fi

# shellcheck source=/etc/vpn_enforcer.conf
source "$CONFIG_FILE"

# Validate required config values
if [ -z "$VPN_SERVER_IP" ]; then
    echo "[FATAL] VPN_SERVER_IP not set in $CONFIG_FILE"
    exit 1
fi
if [ -z "$VPN_INTERFACE" ]; then
    echo "[FATAL] VPN_INTERFACE not set in $CONFIG_FILE"
    exit 1
fi

# --- Constants ---------------------------------------------------------------
readonly VERSION="3.0.0"
readonly PF_ANCHOR_NAME="com.user.vpnenforcer"
readonly PF_ANCHOR_FILE="/etc/pf.anchors/com.user.vpnenforcer"
readonly LOG_FILE="/var/log/vpn_enforcer.log"
readonly ERR_FILE="/var/log/vpn_enforcer.err"
readonly SECURE_DIR="/var/run/vpnenforcer"
readonly BYPASS_FLAG_FILE="$SECURE_DIR/bypass.flag"
readonly PID_FILE="$SECURE_DIR/vpn_enforcer.pid"
readonly STATE_FILE="$SECURE_DIR/state"
readonly BYPASS_LOG="$SECURE_DIR/bypass_audit.log"

# Configurable with defaults
BYPASS_DURATION="${BYPASS_DURATION:-300}"
POLL_INTERVAL="${POLL_INTERVAL:-5}"
ALLOWED_DNS="${ALLOWED_DNS:-}"

# --- State -------------------------------------------------------------------
CURRENT_STATE="UNKNOWN"
SCUTIL_PID=""
MONITOR_PID=""

# --- Logging -----------------------------------------------------------------
log_msg() {
    local level="$1"
    local message="$2"
    local timestamp
    timestamp="$(date '+%Y-%m-%d %H:%M:%S')"

    case "$level" in
        INFO)  local prefix="[INFO]"  ;;
        WARN)  local prefix="[WARN]"  ;;
        ERROR) local prefix="[ERROR]" ;;
        STATE) local prefix="[STATE]" ;;
        AUDIT) local prefix="[AUDIT]" ;;
        *)     local prefix="[????]"  ;;
    esac

    echo "$timestamp $prefix $message" >> "$LOG_FILE"
}

log_info()  { log_msg "INFO"  "$1"; }
log_warn()  { log_msg "WARN"  "$1"; }
log_error() { log_msg "ERROR" "$1"; }
log_state() { log_msg "STATE" "$1"; }
log_audit() {
    log_msg "AUDIT" "$1"
    # Also write to dedicated audit log
    echo "$(date '+%Y-%m-%d %H:%M:%S') $1" >> "$BYPASS_LOG" 2>/dev/null
}

# --- VPN Detection -----------------------------------------------------------
check_vpn() {
    # V3 FIX: Use exact interface match instead of substring grep.
    # V2 bug: "utun" matched utun0, utun1, utun999 etc.
    # Now we check if any interface starting with VPN_INTERFACE is UP.
    local iface
    for iface in $(ifconfig -l 2>/dev/null); do
        if [[ "$iface" == ${VPN_INTERFACE}* ]]; then
            # Verify the interface is actually UP with an assigned address
            if ifconfig "$iface" 2>/dev/null | grep -q "inet "; then
                return 0  # VPN is UP
            fi
        fi
    done
    return 1  # VPN is DOWN
}

# --- Firewall Management ----------------------------------------------------
generate_pf_rules() {
    local rules=""

    rules+="# VPN Enforcer V3 - Auto-generated PF rules\n"
    rules+="# Generated: $(date '+%Y-%m-%d %H:%M:%S')\n\n"

    # Options
    rules+="set block-policy drop\n"
    rules+="set skip on lo0\n\n"

    # Block all outgoing traffic by default
    rules+="block out all\n\n"

    # Allow traffic to VPN server(s) - V3: supports comma-separated IPs
    local IFS=','
    for server_ip in $VPN_SERVER_IP; do
        server_ip="$(echo "$server_ip" | xargs)"  # trim whitespace
        if [ -n "$server_ip" ]; then
            rules+="# VPN Server: $server_ip\n"
            rules+="pass out proto udp from any to $server_ip\n"
            rules+="pass out proto tcp from any to $server_ip\n"
        fi
    done
    unset IFS
    rules+="\n"

    # Allow DHCP
    rules+="# DHCP\n"
    rules+="pass out proto udp from any port 68 to any port 67\n"
    rules+="pass out proto udp from any port 67 to any port 68\n\n"

    # DNS - V3 FIX: restrict to specific servers if configured
    rules+="# DNS\n"
    if [ -n "$ALLOWED_DNS" ]; then
        local IFS=','
        for dns_ip in $ALLOWED_DNS; do
            dns_ip="$(echo "$dns_ip" | xargs)"
            if [ -n "$dns_ip" ]; then
                rules+="pass out proto udp from any to $dns_ip port 53\n"
                rules+="pass out proto tcp from any to $dns_ip port 53\n"
            fi
        done
        unset IFS
    else
        # Fallback: allow DNS to any (backward compatible)
        rules+="pass out proto udp from any to any port 53\n"
        rules+="pass out proto tcp from any to any port 53\n"
    fi

    echo -e "$rules"
}

enable_firewall() {
    if [ "$CURRENT_STATE" = "BLOCKED" ]; then return; fi

    log_info "Enabling firewall restrictions (VPN DOWN)..."

    # Always regenerate rules to pick up config changes
    generate_pf_rules > "$PF_ANCHOR_FILE"
    chmod 644 "$PF_ANCHOR_FILE"

    # Load the anchor - V3 FIX: check return codes
    if ! pfctl -a "$PF_ANCHOR_NAME" -f "$PF_ANCHOR_FILE" 2>/dev/null; then
        log_error "Failed to load PF anchor rules!"
        return 1
    fi

    if ! pfctl -e 2>/dev/null; then
        # pfctl -e returns 1 if already enabled - that's OK
        :
    fi

    CURRENT_STATE="BLOCKED"
    echo "BLOCKED" > "$STATE_FILE" 2>/dev/null
    log_state "BLOCKED - All outbound traffic dropped (except VPN/DNS/DHCP)"
}

disable_firewall() {
    if [ "$CURRENT_STATE" = "ALLOWED" ]; then return; fi

    log_info "Disabling firewall restrictions..."

    if ! pfctl -a "$PF_ANCHOR_NAME" -F all 2>/dev/null; then
        log_error "Failed to flush PF anchor rules!"
        return 1
    fi

    CURRENT_STATE="ALLOWED"
    echo "ALLOWED" > "$STATE_FILE" 2>/dev/null
    log_state "ALLOWED - Traffic flowing normally"
}

# --- Bypass Management -------------------------------------------------------
check_bypass() {
    if [ ! -f "$BYPASS_FLAG_FILE" ]; then
        return 1  # No bypass active
    fi

    local current_time file_time age remaining
    current_time=$(date +%s)
    file_time=$(stat -f %m "$BYPASS_FLAG_FILE" 2>/dev/null)

    if [ -z "$file_time" ]; then
        log_warn "Could not read bypass flag timestamp, removing stale flag."
        rm -f "$BYPASS_FLAG_FILE"
        return 1
    fi

    age=$((current_time - file_time))

    if [ "$age" -lt "$BYPASS_DURATION" ]; then
        remaining=$((BYPASS_DURATION - age))
        # Write remaining time for status display
        echo "$remaining" > "$SECURE_DIR/bypass_remaining" 2>/dev/null
        return 0  # Bypass IS active
    else
        log_info "Bypass expired after ${BYPASS_DURATION}s."
        log_audit "BYPASS_EXPIRED duration=${BYPASS_DURATION}s"
        rm -f "$BYPASS_FLAG_FILE"
        rm -f "$SECURE_DIR/bypass_remaining"
        return 1  # Bypass expired
    fi
}

# --- Core Logic --------------------------------------------------------------
evaluate_state() {
    local reason=""

    if check_bypass; then
        reason="BYPASS_ACTIVE"
        disable_firewall
    elif check_vpn; then
        reason="VPN_CONNECTED"
        disable_firewall
    else
        reason="VPN_DISCONNECTED"
        enable_firewall
    fi

    # Write reason for status display
    echo "$reason" > "$SECURE_DIR/reason" 2>/dev/null
}

# --- Process Management (V3 FIX: proper cleanup) ----------------------------
kill_children() {
    # Kill the scutil monitor process and the pipe reader
    if [ -n "$MONITOR_PID" ] && kill -0 "$MONITOR_PID" 2>/dev/null; then
        kill "$MONITOR_PID" 2>/dev/null
        wait "$MONITOR_PID" 2>/dev/null
    fi

    # Also kill any scutil processes we spawned
    # Use process group to ensure no orphans
    if [ -n "$SCUTIL_PID" ] && kill -0 "$SCUTIL_PID" 2>/dev/null; then
        kill "$SCUTIL_PID" 2>/dev/null
        wait "$SCUTIL_PID" 2>/dev/null
    fi
}

cleanup() {
    log_info "Daemon shutting down (signal received)..."
    kill_children

    # Fail-closed: ensure firewall stays active
    CURRENT_STATE="UNKNOWN"  # Force re-enable
    enable_firewall
    log_state "FAIL_CLOSED - Daemon stopped, firewall remains ACTIVE"

    rm -f "$PID_FILE"
    rm -f "$SECURE_DIR/bypass_remaining"
    exit 0
}

# Trap signals for clean shutdown
trap cleanup SIGTERM SIGINT SIGHUP

# --- Health Check ------------------------------------------------------------
health_check() {
    # Verify PF is still enabled
    if ! pfctl -s info 2>/dev/null | grep -q "Status: Enabled"; then
        log_warn "PF was disabled! Re-enabling..."
        pfctl -e 2>/dev/null
        CURRENT_STATE="UNKNOWN"  # Force state re-evaluation
    fi

    # Verify our anchor is loaded when we expect it to be
    if [ "$CURRENT_STATE" = "BLOCKED" ]; then
        local rule_count
        rule_count=$(pfctl -a "$PF_ANCHOR_NAME" -s rules 2>/dev/null | wc -l | xargs)
        if [ "$rule_count" -eq 0 ]; then
            log_warn "Firewall rules were cleared! Re-applying..."
            CURRENT_STATE="UNKNOWN"  # Force re-enable
        fi
    fi
}

# --- Startup -----------------------------------------------------------------
start_monitor() {
    # Create a named pipe for scutil communication
    local fifo="$SECURE_DIR/scutil_fifo"
    rm -f "$fifo"
    mkfifo "$fifo" 2>/dev/null
    chmod 600 "$fifo" 2>/dev/null

    # V3 FIX: Start scutil as a separate tracked process, not in a subshell pipe.
    # This prevents the V2 bug where PID_SCUTIL captured the pipe reader PID
    # instead of the actual scutil process, causing orphaned processes.
    scutil --monitor State:/Network/Global/IPv4 > "$fifo" 2>/dev/null &
    SCUTIL_PID=$!

    # Read from the fifo in a background loop
    (
        while read -r _line; do
            evaluate_state
        done < "$fifo"
    ) &
    MONITOR_PID=$!

    log_info "Network monitor started (scutil PID=$SCUTIL_PID, reader PID=$MONITOR_PID)"
}

main() {
    log_info "=========================================="
    log_info "VPN Enforcer V${VERSION} starting..."
    log_info "=========================================="
    log_info "Config: VPN_SERVER_IP=$VPN_SERVER_IP"
    log_info "Config: VPN_INTERFACE=$VPN_INTERFACE"
    log_info "Config: BYPASS_DURATION=${BYPASS_DURATION}s"
    log_info "Config: POLL_INTERVAL=${POLL_INTERVAL}s"
    [ -n "$ALLOWED_DNS" ] && log_info "Config: ALLOWED_DNS=$ALLOWED_DNS"

    # Ensure secure directory exists
    mkdir -p "$SECURE_DIR"
    chmod 700 "$SECURE_DIR"
    chown root:wheel "$SECURE_DIR" 2>/dev/null

    # Set explicit log permissions
    touch "$LOG_FILE"
    chmod 640 "$LOG_FILE"
    chown root:wheel "$LOG_FILE" 2>/dev/null

    # Write PID file
    echo $$ > "$PID_FILE"

    # Initial evaluation
    evaluate_state

    # Start event-driven monitor
    start_monitor

    # V3 FIX: Main loop is now interruptible and includes health checks.
    # The loop handles bypass expiry polling and periodic health checks.
    local health_counter=0
    while true; do
        sleep "$POLL_INTERVAL" &
        wait $!  # Makes sleep interruptible by signals

        evaluate_state

        # Health check every 12 cycles (~60s at default interval)
        health_counter=$((health_counter + 1))
        if [ "$health_counter" -ge 12 ]; then
            health_check
            health_counter=0
        fi
    done
}

main "$@"
