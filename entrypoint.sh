#!/bin/bash
set -e

# Configuration variables
MODE="${WARP_MODE:-proxy}"
PROXY_PORT="${WARP_PROXY_PORT:-40000}"
PROTOCOL="${WARP_PROTOCOL:-masque}"

# Constants for retry logic
MAX_RETRIES_WARP=30
RETRY_SLEEP_WARP=2
MAX_RETRIES_CONNECT=20
RETRY_SLEEP_CONNECT=3
CURL_TIMEOUT=2

WARP_PID=""
SOCAT_PID=""
WARP_PORT=56789
CONF_DIR="/var/lib/cloudflare-warp"
MDM_FILE="${CONF_DIR}/mdm.xml"
WARP_LOG_FILE="/var/log/warp.log"

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

warp_cli() { 
    warp-cli --accept-tos "$@"
}

check_required_commands() {
    local required_cmds=("warp-cli" "warp-svc" "dbus-daemon" "socat" "curl" "dbus-uuidgen")
    for cmd in "${required_cmds[@]}"; do
        if ! command_exists "$cmd"; then
            echo "Error: Required command '$cmd' not found."
            exit 1
        fi
    done
}

validate_inputs() {
    if [[ ! "$MODE" =~ ^(proxy|warp)$ ]]; then
        echo "Error: Invalid MODE '$MODE'. Must be 'proxy' or 'warp'."
        exit 1
    fi
    
    if [[ ! "$PROTOCOL" =~ ^(masque|wireguard)$ ]]; then
        echo "Error: Invalid PROTOCOL '$PROTOCOL'. Must be 'masque' or 'wireguard'."
        exit 1
    fi
}

cleanup() {
    echo "Cleaning up..."
    [ -n "$SOCAT_PID" ] && kill $SOCAT_PID 2>/dev/null || true
    [ -n "$WARP_PID" ] && kill $WARP_PID 2>/dev/null || true
}

trap cleanup EXIT INT TERM

print_diag_info() {
    echo ""
    echo "--- Process status ---"
    echo ""
    ps aux || true
    
    echo ""
    echo "--- File List in /run/cloudflare-warp, /run/dbus ---"
    echo ""
    ls -la /run/cloudflare-warp/ 2>/dev/null || echo "/run/cloudflare-warp empty or missing"
    ls -la /run/dbus/ 2>/dev/null || echo "/run/dbus empty or missing"

    echo ""
    echo "--- warp-svc Status ---"
    echo ""
    warp-cli --accept-tos status 2>&1 || true

    if [ -f /var/log/warp.log ]; then
        echo ""
        echo "--- warp.log ---"
        echo ""
        tail -20 /var/log/warp.log || true
    fi
}

run_dbus() {
    echo "Starting dbus..."
    mkdir -p /run/dbus
    if [ ! -f /var/lib/dbus/machine-id ]; then
        dbus-uuidgen > /var/lib/dbus/machine-id || {
            echo "Error: Failed to generate dbus machine-id."
            exit 1
        }
    fi
    rm -f /var/run/dbus/pid
    dbus-daemon --config-file=/usr/share/dbus-1/system.conf --print-address --fork || {
        echo "Error: Failed to start dbus-daemon."
        exit 1
    }
}

start_warp() {
    echo "Starting warp-svc..."
    warp-svc > $WARP_LOG_FILE 2>&1 &
    WARP_PID=$!
    sleep 2

    echo "Waiting for warp-svc to become ready..."
    local COUNT=0
    while ! warp_cli status > /dev/null 2>&1; do
        sleep $RETRY_SLEEP_WARP
        COUNT=$((COUNT+1))

        if [ $((COUNT % 3)) -eq 0 ]; then
            echo "Attempt $COUNT/$MAX_RETRIES_WARP: Still waiting for warp-svc to become ready..."
            if [ $((COUNT % 9)) -eq 0 ]; then
                echo ""
                echo "--- warp-svc Status ---"
                echo ""
                warp-cli --accept-tos status 2>&1 || true
            fi
        fi

        if [ ${COUNT} -ge ${MAX_RETRIES_WARP} ]; then
            echo "Error: warp-svc failed to start within $((MAX_RETRIES_WARP * RETRY_SLEEP_WARP)) seconds."
            print_diag_info
            exit 1
        fi
    done
    echo "warp-svc is up."
}

connect_warp() {
    echo "Connecting..."
    warp_cli connect || {
        echo "Error: Failed to connect warp."
        exit 1
    }

    echo "Waiting for connection..."
    local CURL_OPTS=("-s" "--max-time" "$CURL_TIMEOUT" "--retry" "2")

    if [ "${MODE}" = "proxy" ]; then
        CURL_OPTS+=("-x" "socks5h://127.0.0.1:${WARP_PORT}")
        echo "Testing via proxy: socks5h://127.0.0.1:${WARP_PORT}"
    else
        echo "Testing via global networking"
    fi

    local COUNT=0
    local RESPONSE=""

    while true; do
        RESPONSE=$(curl "${CURL_OPTS[@]}" https://www.cloudflare.com/cdn-cgi/trace 2>/dev/null || true)
        
        if echo "$RESPONSE" | grep -q "warp=on"; then
            echo "Connection verified - WARP is active."
            return 0
        fi

        if [ $((COUNT % 3)) -eq 0 ]; then
            echo "Attempt $COUNT/$MAX_RETRIES_CONNECT: Still waiting for warp to become ready..."
        fi
        
        sleep $RETRY_SLEEP_CONNECT
        COUNT=$((COUNT+1))
        if [ ${COUNT} -ge ${MAX_RETRIES_CONNECT} ]; then
            echo "Error: warp failed to connect within $((MAX_RETRIES_CONNECT * RETRY_SLEEP_CONNECT)) seconds."
            print_diag_info
            exit 1
        fi
    done
    echo "Warp connected."
}

auth_zero_trust(){
    echo "Generating Zero Trust MDM configuration..."
    mkdir -p "${CONF_DIR}" || {
        echo "Error: Failed to create config directory."
        exit 1
    }

    if [ -z "${WARP_ORG}" ] || [ -z "${WARP_CLIENT_ID}" ] || [ -z "${WARP_CLIENT_SECRET}" ]; then
        echo "Error: Missing required Zero Trust environment variables."
        exit 1
    fi

    echo "Setting MDM with: ${WARP_ORG}, ${MODE}, ${PROTOCOL}"
    cat > "${MDM_FILE}" <<EOF
<dict>
    <key>organization</key>
    <string>${WARP_ORG}</string>
    <key>auth_client_id</key>
    <string>${WARP_CLIENT_ID}</string>
    <key>auth_client_secret</key>
    <string>${WARP_CLIENT_SECRET}</string>
    <key>service_mode</key>
    <string>${MODE}</string>
    <key>proxy_port</key>
    <integer>${WARP_PORT}</integer>
    <key>warp_tunnel_protocol</key>
    <string>${PROTOCOL}</string>
    <key>auto_connect</key>
    <integer>1</integer>
    <key>onboarding</key>
    <false />
    <key>switch_locked</key>
    <true />
</dict>
EOF

    start_warp
}

auth_warp(){
    start_warp

    echo "Registering new warp client..."
    if [ -n "${WARP_LICENSE}" ]; then
        echo "Using provided license key..."
        warp_cli registration license "$WARP_LICENSE" || {
            echo "Error: Failed to register with license key."
            exit 1
        }
    else
        echo "Creating new free registration..."
        warp_cli registration new || {
            echo "Error: Failed to create free registration."
            exit 1
        }
    fi

    echo "Configuring mode: ${MODE} and protocol: ${PROTOCOL}"
    warp_cli mode "${MODE}" || exit 1
    warp_cli proxy port "${WARP_PORT}" || exit 1

    local proto="MASQUE"
    if [ "${PROTOCOL}" = "masque" ]; then
        proto="MASQUE"
    elif [ "${PROTOCOL}" = "wireguard" ]; then
        proto="WireGuard"
    else
        echo "Error: unknown protocol ${PROTOCOL}."
        exit 1
    fi
    warp_cli tunnel protocol set "${proto}" || exit 1
}

# Main execution
check_required_commands
validate_inputs

run_dbus

# Check for existing configuration
if [ -n "${WARP_ORG}" ] && [ -n "${WARP_CLIENT_ID}" ] && [ -n "${WARP_CLIENT_SECRET}" ]; then
    echo "Initializing Zero Trust configuration..."
    auth_zero_trust
elif [ -d "$CONF_DIR" ] && [ -n "$(ls -A "${CONF_DIR}")" ]; then
    echo "Using existing configuration..."
    start_warp
else
    echo "Initializing standard WARP configuration..."
    auth_warp
fi

echo "Add IP ranges to split tunnel configuration..."
warp_cli tunnel ip add-range 10.0.0.0/8 || exit 1
warp_cli tunnel ip add-range 172.16.0.0/12 || exit 1
warp_cli tunnel ip add-range 192.168.0.0/16 || exit 1

connect_warp

if [ "${MODE}" = "proxy" ]; then
    echo "Starting proxy forwarder on 0.0.0.0:${PROXY_PORT} -> 127.0.0.1:${WARP_PORT}"
    socat TCP-LISTEN:"${PROXY_PORT}",fork TCP:127.0.0.1:"${WARP_PORT}" &
    SOCAT_PID=$!
    echo "Proxy forwarder started with PID $SOCAT_PID"
fi

echo "Setup complete. Waiting for services..."
wait ${WARP_PID}