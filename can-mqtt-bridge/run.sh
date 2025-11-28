#!/usr/bin/with-contenv bashio
# Copyright 2025 Ted Lanham
# Licensed under the MIT License
# CAN to MQTT Bridge Main Script

set -e

# Ensure we're running as s6 service
if [ -z "${S6_SERVICE_PATH+x}" ]; then
  bashio::log.warning "This script is designed to run as an s6 service"
fi

# Create health check file directory
mkdir -p /var/run/s6/healthcheck

# ========================
# Configuration Loading
# ========================
CAN_INTERFACE=$(bashio::config 'can_interface')
CAN_BITRATE=$(bashio::config 'can_bitrate')
EXPECTED_OSCILLATOR=$(bashio::config 'expected_oscillator')

# Try to use service discovery for MQTT broker
if bashio::services.available "mqtt"; then
    bashio::log.info "MQTT service discovered"
    MQTT_HOST=$(bashio::services "mqtt" "host")
    MQTT_PORT=$(bashio::services "mqtt" "port")
    MQTT_USER=$(bashio::services "mqtt" "username")
    MQTT_PASS=$(bashio::services "mqtt" "password")
else
    # Fall back to manual configuration
    bashio::log.info "Using manual MQTT configuration"
    MQTT_HOST=$(bashio::config 'mqtt_host')
    MQTT_PORT=$(bashio::config 'mqtt_port')
    MQTT_USER=$(bashio::config 'mqtt_user')
    MQTT_PASS=$(bashio::config 'mqtt_pass')
fi
MQTT_TOPIC_RAW=$(bashio::config 'mqtt_topic_raw')
MQTT_TOPIC_SEND=$(bashio::config 'mqtt_topic_send')
MQTT_TOPIC_STATUS=$(bashio::config 'mqtt_topic_status')
DEBUG_LOGGING=$(bashio::config 'debug_logging')
SSL=$(bashio::config 'ssl')
PASSWORD=$(bashio::config 'password')

# Security settings
MQTT_SSL_ARGS=""
if [ "$SSL" = "true" ]; then
    MQTT_SSL_ARGS="--cafile /etc/ssl/certs/ca-certificates.crt --tls-version tlsv1.2"
    bashio::log.info "SSL enabled for MQTT connections"
fi

# Password protection
if [ -n "$PASSWORD" ]; then
    bashio::log.info "Password protection enabled"
fi

# Global process tracking
CAN_TO_MQTT_PID=""
MQTT_TO_CAN_PID=""

# ========================
# Configuration Validation
# ========================
validate_config() {
    bashio::log.info "Validating configuration..."

    # Validate MQTT connection parameters
    if [[ -z "$MQTT_HOST" ]]; then
        bashio::log.fatal "MQTT host is required"
        return 1
    fi

    # Validate MQTT port
    if ! [[ "$MQTT_PORT" =~ ^[0-9]+$ ]] || [ "$MQTT_PORT" -lt 1 ] || [ "$MQTT_PORT" -gt 65535 ]; then
        bashio::log.fatal "Invalid MQTT port: $MQTT_PORT"
        return 1
    fi

    bashio::log.info "✅ Configuration validation passed"
    return 0
}


# ========================
# Health Check Function
# ========================
update_health_check() {
    local status=$1
    echo "$status" > /var/run/s6/healthcheck/status

    # Status is published only at startup and shutdown
}


# ========================
# Cleanup Function
# ========================
cleanup() {
    bashio::log.info "Shutdown signal received. Cleaning up..."
    
    # Kill background processes
    if [ -n "$CAN_TO_MQTT_PID" ] && kill -0 "$CAN_TO_MQTT_PID" 2>/dev/null; then
        bashio::log.info "Stopping CAN->MQTT bridge (PID: $CAN_TO_MQTT_PID)"
        kill -TERM "$CAN_TO_MQTT_PID" 2>/dev/null || true
    fi
    
    if [ -n "$MQTT_TO_CAN_PID" ] && kill -0 "$MQTT_TO_CAN_PID" 2>/dev/null; then
        bashio::log.info "Stopping MQTT->CAN bridge (PID: $MQTT_TO_CAN_PID)"
        kill -TERM "$MQTT_TO_CAN_PID" 2>/dev/null || true
    fi
    
    # Stop web server if running
    if [ -n "$WEB_SERVER_PID" ] && kill -0 "$WEB_SERVER_PID" 2>/dev/null; then
        bashio::log.info "Stopping web server (PID: $WEB_SERVER_PID)"
        kill -TERM "$WEB_SERVER_PID" 2>/dev/null || true
    fi
    
    # Publish offline status
    mosquitto_pub -h "$MQTT_HOST" -p "$MQTT_PORT" \
                  ${MQTT_USER:+-u "$MQTT_USER"} ${MQTT_PASS:+-P "$MQTT_PASS"} \
                  -t "$MQTT_TOPIC_STATUS" -m "bridge_offline" -q 1 -r 2>/dev/null || true
    
    # Bring down CAN interface
    ip link set "$CAN_INTERFACE" down 2>/dev/null || true

    bashio::log.info "Cleanup completed"
    exit 0
}

# Set up signal handlers
trap cleanup SIGTERM SIGINT SIGQUIT

# ========================
# Startup Banner
# ========================
bashio::log.info "=== CAN to MQTT Bridge Starting ==="
bashio::log.info "CAN Interface: $CAN_INTERFACE @ ${CAN_BITRATE} bps"
bashio::log.info "MQTT Broker: $MQTT_HOST:$MQTT_PORT"
bashio::log.info "MQTT User: ${MQTT_USER:-'(none)'}"
bashio::log.info "Topics - Raw: $MQTT_TOPIC_RAW, Send: $MQTT_TOPIC_SEND, Status: $MQTT_TOPIC_STATUS"
bashio::log.info "Debug Logging: ${DEBUG_LOGGING}"
if [ "$DEBUG_LOGGING" = "true" ]; then
    bashio::log.info "Verbose debug logging is ENABLED"
else
    bashio::log.info "Verbose debug logging is disabled"
fi
echo

# ========================
# CAN Interface Initialization
# ========================
bashio::log.info "Initializing CAN interface..."

# Print current status for debugging
bashio::log.info "Current interface status:"
ip link show "$CAN_INTERFACE" 2>/dev/null || bashio::log.info "Interface $CAN_INTERFACE not found (this may be normal)"

# If the device is already up, bring it down first
if [ -f "/sys/class/net/$CAN_INTERFACE/operstate" ] && [ "$(cat "/sys/class/net/$CAN_INTERFACE/operstate")" = "up" ]; then
    bashio::log.info "Interface is up, bringing it down first"
    ip link set "$CAN_INTERFACE" down
fi

# ========================
# Oscillator Frequency Detection & Compensation
# ========================
detect_and_compensate_oscillator() {
    local requested_bitrate=$1
    local interface=$2

    bashio::log.info "Checking for oscillator frequency mismatch..."

    # Get detailed interface information without changing state
    local can_details
    can_details=$(ip -details link show "$interface" 2>/dev/null)

    if [ -z "$can_details" ]; then
        bashio::log.warning "Could not retrieve interface details - skipping oscillator check"
        echo "$requested_bitrate"
        return 0
    fi

    # Extract clock frequency using BusyBox-compatible sed
    local driver_clock
    driver_clock=$(echo "$can_details" | sed -n 's/.*clock \([0-9]*\).*/\1/p' | head -n1)

    if [ -z "$driver_clock" ] || [ "$driver_clock" -eq 0 ] 2>/dev/null; then
        bashio::log.warning "Could not detect driver clock frequency - skipping oscillator check"
        echo "$requested_bitrate"
        return 0
    fi

    bashio::log.info "Detected driver clock: ${driver_clock} Hz"

    # Determine expected oscillator frequency
    local expected_oscillator

    # Check if user manually configured expected oscillator
    if [ -n "$EXPECTED_OSCILLATOR" ] && [ "$EXPECTED_OSCILLATOR" -gt 0 ] 2>/dev/null; then
        expected_oscillator=$EXPECTED_OSCILLATOR
        bashio::log.info "Using configured expected oscillator: ${expected_oscillator} Hz"
    else
        # Auto-infer expected oscillator based on driver clock
        # Key insight: 8MHz driver reading is almost always the bug (should be 16MHz)

        if [ "$driver_clock" -eq 16000000 ] || [ "$driver_clock" -eq 20000000 ]; then
            # 16MHz or 20MHz driver reading - assume correct, no compensation needed
            bashio::log.info "Driver clock ${driver_clock} Hz appears correct - no compensation needed"
            echo "$requested_bitrate"
            return 0
        elif [ "$driver_clock" -eq 8000000 ]; then
            # Ambiguous: could be correct 8MHz or the 16MHz bug
            # Default to assuming it's the bug (most common) but inform user
            expected_oscillator=16000000
            bashio::log.info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            bashio::log.info "Driver reports 8 MHz clock - this is often a bug"
            bashio::log.info "Assuming hardware is actually 16 MHz (most common)"
            bashio::log.info "If your hardware truly has 8 MHz crystal, set:"
            bashio::log.info "  expected_oscillator: 8000000"
            bashio::log.info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        elif [ "$driver_clock" -eq 4000000 ]; then
            # Less common: 8MHz hardware detected as 4MHz
            expected_oscillator=8000000
            bashio::log.info "Inferred expected oscillator: ${expected_oscillator} Hz"
        else
            # Unknown configuration - default to 16MHz (most common for Waveshare HATs)
            expected_oscillator=16000000
            bashio::log.warning "Unusual driver clock ${driver_clock} Hz - defaulting to 16MHz oscillator"
            bashio::log.warning "If this doesn't work, set expected_oscillator manually in config"
        fi
    fi

    # Calculate compensation factor
    local compensation_factor
    compensation_factor=$(awk "BEGIN {printf \"%.6f\", $expected_oscillator / $driver_clock}")

    # Only compensate if factor is not approximately 1.0
    if awk "BEGIN {exit !($compensation_factor >= 0.99 && $compensation_factor <= 1.01)}"; then
        bashio::log.info "Compensation factor ${compensation_factor} is close to 1.0 - no compensation needed"
        echo "$requested_bitrate"
        return 0
    fi

    # Calculate compensated bitrate
    local compensated_bitrate
    compensated_bitrate=$(awk "BEGIN {printf \"%.0f\", $requested_bitrate / $compensation_factor}")

    # Validate compensated bitrate is reasonable (between 10 kbps and 1 Mbps)
    if [ "$compensated_bitrate" -lt 10000 ] || [ "$compensated_bitrate" -gt 1000000 ]; then
        bashio::log.error "Calculated compensated bitrate ${compensated_bitrate} is out of valid range"
        bashio::log.error "Driver clock: ${driver_clock} Hz, Expected: ${expected_oscillator} Hz"
        bashio::log.error "Requested: ${requested_bitrate} bps, Factor: ${compensation_factor}"
        bashio::log.error "Using requested bitrate without compensation - CAN bus may not work correctly!"
        echo "$requested_bitrate"
        return 1
    fi

    # Log the compensation
    bashio::log.info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    bashio::log.info "Oscillator Frequency Mismatch Detected - Auto-Compensating"
    bashio::log.info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    bashio::log.info "Expected oscillator frequency: ${expected_oscillator} Hz ($(awk "BEGIN {printf \"%.0f\", $expected_oscillator/1000000}") MHz)"
    bashio::log.info "Driver configured frequency:   ${driver_clock} Hz ($(awk "BEGIN {printf \"%.0f\", $driver_clock/1000000}") MHz)"
    bashio::log.info "Compensation factor:           ${compensation_factor}x"
    bashio::log.info "Requested bitrate:             ${requested_bitrate} bps"
    bashio::log.info "Compensated bitrate:           ${compensated_bitrate} bps"
    bashio::log.info "Actual CAN bus speed:          ${requested_bitrate} bps (after compensation)"
    bashio::log.info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    # Return compensated bitrate
    echo "$compensated_bitrate"
    return 0
}

# Detect oscillator mismatch and calculate compensated bitrate if needed
EFFECTIVE_BITRATE=$(detect_and_compensate_oscillator "$CAN_BITRATE" "$CAN_INTERFACE")

# Set up CAN interface with effective bitrate (may be compensated)
if [ "$EFFECTIVE_BITRATE" != "$CAN_BITRATE" ]; then
    bashio::log.info "Setting up CAN interface with compensated bitrate $EFFECTIVE_BITRATE (target: $CAN_BITRATE)"
else
    bashio::log.info "Setting up CAN interface with bitrate $CAN_BITRATE"
fi

if ! ip link set "$CAN_INTERFACE" up type can bitrate "$EFFECTIVE_BITRATE"; then
    bashio::log.fatal "Failed to set CAN interface up with bitrate $EFFECTIVE_BITRATE"
    bashio::log.fatal "Please ensure CAN hardware is connected and recognized"
    exit 1
fi

# Bring interface up (second command from working add-on)
if ! ip link set "$CAN_INTERFACE" up; then
    bashio::log.fatal "Failed to bring CAN interface up"
    exit 1
fi

# Print final status for debugging
bashio::log.info "Final interface status:"
ip link show "$CAN_INTERFACE"

# Debug mode: Show detailed interface diagnostics
if [ "$DEBUG_LOGGING" = "true" ]; then
    bashio::log.info "[DEBUG] ========== CAN Interface Diagnostics =========="

    # Show detailed interface information
    if [ -d "/sys/class/net/$CAN_INTERFACE" ]; then
        bashio::log.info "[DEBUG] Interface operstate: $(cat /sys/class/net/$CAN_INTERFACE/operstate 2>/dev/null || echo 'unknown')"
        bashio::log.info "[DEBUG] Interface carrier: $(cat /sys/class/net/$CAN_INTERFACE/carrier 2>/dev/null || echo 'unknown')"

        # Show CAN statistics if available
        if [ -d "/sys/class/net/$CAN_INTERFACE/statistics" ]; then
            bashio::log.info "[DEBUG] RX packets: $(cat /sys/class/net/$CAN_INTERFACE/statistics/rx_packets 2>/dev/null || echo '0')"
            bashio::log.info "[DEBUG] TX packets: $(cat /sys/class/net/$CAN_INTERFACE/statistics/tx_packets 2>/dev/null || echo '0')"
            bashio::log.info "[DEBUG] RX errors: $(cat /sys/class/net/$CAN_INTERFACE/statistics/rx_errors 2>/dev/null || echo '0')"
            bashio::log.info "[DEBUG] TX errors: $(cat /sys/class/net/$CAN_INTERFACE/statistics/tx_errors 2>/dev/null || echo '0')"
        fi
    fi

    # Show CAN-specific settings and timing parameters
    bashio::log.info "[DEBUG] === CAN Interface Settings ==="
    bashio::log.info "[DEBUG] Configured bitrate: $CAN_BITRATE bps"

    # Extract and display CAN timing parameters from ip -details output
    CAN_DETAILS=$(ip -details link show "$CAN_INTERFACE" 2>/dev/null)
    if [ -n "$CAN_DETAILS" ]; then
        bashio::log.info "[DEBUG] Full interface details:"
        echo "$CAN_DETAILS" | while IFS= read -r line; do
            bashio::log.info "[DEBUG]   $line"
        done

        # Try to extract specific CAN parameters (using BusyBox-compatible commands)
        ACTUAL_BITRATE=$(echo "$CAN_DETAILS" | sed -n 's/.*bitrate \([0-9]*\).*/\1/p' | head -n1)
        [ -z "$ACTUAL_BITRATE" ] && ACTUAL_BITRATE="unknown"

        SAMPLE_POINT=$(echo "$CAN_DETAILS" | sed -n 's/.*sample-point \([0-9.]*\).*/\1/p' | head -n1)
        [ -z "$SAMPLE_POINT" ] && SAMPLE_POINT="unknown"

        TQ=$(echo "$CAN_DETAILS" | sed -n 's/.*tq \([0-9]*\).*/\1/p' | head -n1)
        [ -z "$TQ" ] && TQ="unknown"

        bashio::log.info "[DEBUG] === Extracted CAN Parameters ==="
        bashio::log.info "[DEBUG] Actual bitrate: $ACTUAL_BITRATE bps"
        bashio::log.info "[DEBUG] Sample point: $SAMPLE_POINT"
        bashio::log.info "[DEBUG] Time quantum (tq): $TQ ns"
    else
        bashio::log.warning "[DEBUG] Could not retrieve detailed CAN settings"
    fi

    # Test candump availability and basic functionality
    bashio::log.info "[DEBUG] === CAN Tools Check ==="
    if command -v candump >/dev/null 2>&1; then
        bashio::log.info "[DEBUG] candump is available: $(which candump)"
    else
        bashio::log.error "[DEBUG] candump command not found!"
    fi

    if command -v cansend >/dev/null 2>&1; then
        bashio::log.info "[DEBUG] cansend is available: $(which cansend)"
    else
        bashio::log.error "[DEBUG] cansend command not found!"
    fi

    if command -v ip >/dev/null 2>&1; then
        bashio::log.info "[DEBUG] ip (iproute2) is available: $(which ip)"
    else
        bashio::log.error "[DEBUG] ip command not found!"
    fi

    # Show compensation details in debug mode
    if [ "$EFFECTIVE_BITRATE" != "$CAN_BITRATE" ]; then
        bashio::log.info "[DEBUG] === Oscillator Compensation Active ==="
        bashio::log.info "[DEBUG] User requested bitrate: $CAN_BITRATE bps"
        bashio::log.info "[DEBUG] Compensated bitrate:    $EFFECTIVE_BITRATE bps"
        bashio::log.info "[DEBUG] Actual CAN bus speed:   $CAN_BITRATE bps (after compensation)"

        # Verify actual bitrate from interface
        if [ "$ACTUAL_BITRATE" = "$CAN_BITRATE" ]; then
            bashio::log.info "[DEBUG] ✓ Verification: Actual bitrate matches requested!"
        elif [ "$ACTUAL_BITRATE" = "$EFFECTIVE_BITRATE" ]; then
            bashio::log.warning "[DEBUG] ⚠ Verification: Actual bitrate matches compensated value"
            bashio::log.warning "[DEBUG]   This means compensation did NOT work as expected"
            bashio::log.warning "[DEBUG]   Expected: $CAN_BITRATE, Got: $ACTUAL_BITRATE"
        else
            bashio::log.warning "[DEBUG] ⚠ Verification: Unexpected actual bitrate: $ACTUAL_BITRATE"
        fi
    fi

    bashio::log.info "[DEBUG] ==============================================="
fi

bashio::log.info "✅ CAN interface $CAN_INTERFACE initialized successfully at ${CAN_BITRATE} bps"

# ========================
# Configuration & MQTT Connection Test
# ========================
# Run configuration validation
if ! validate_config; then
    bashio::log.fatal "Configuration validation failed. Exiting."
    exit 1
fi

bashio::log.info "Testing MQTT connection..."

MQTT_AUTH_ARGS=""
[ -n "$MQTT_USER" ] && MQTT_AUTH_ARGS="$MQTT_AUTH_ARGS -u $MQTT_USER"
[ -n "$MQTT_PASS" ] && MQTT_AUTH_ARGS="$MQTT_AUTH_ARGS -P $MQTT_PASS"

if mosquitto_pub -h "$MQTT_HOST" -p "$MQTT_PORT" $MQTT_AUTH_ARGS \
   -t "$MQTT_TOPIC_STATUS" -m "bridge_starting" -q 1 >/dev/null 2>&1; then
    bashio::log.info "✅ MQTT connection successful"
else
    bashio::log.fatal "❌ MQTT connection failed - check broker settings and credentials"
    exit 1
fi


# ========================
# Start Bridge Processes
# ========================

# CAN -> MQTT Bridge (with comprehensive debug logging)
bashio::log.info "Starting CAN->MQTT bridge..."
{
    FRAME_COUNT=0
    while true; do
        [ "$DEBUG_LOGGING" = "true" ] && bashio::log.info "[DEBUG] CAN->MQTT: Starting candump on $CAN_INTERFACE"
        [ "$DEBUG_LOGGING" = "true" ] && bashio::log.info "[DEBUG] CAN->MQTT: Listening for CAN frames..."

        # Capture both stdout and stderr from candump
        if [ "$DEBUG_LOGGING" = "true" ]; then
            # Debug mode: show all candump output and errors
            candump -L "$CAN_INTERFACE" 2>&1 | while IFS= read -r line; do
                # Check if this is an error message
                if [[ "$line" =~ ^error ]] || [[ "$line" =~ ^Error ]] || [[ "$line" =~ ^WARNING ]]; then
                    bashio::log.error "[DEBUG] CAN->MQTT candump error: $line"
                else
                    # Log raw candump output
                    bashio::log.info "[DEBUG] CAN->MQTT candump raw: $line"

                    # Extract frame (3rd field)
                    frame=$(echo "$line" | awk '{print $3}')
                    if [ -n "$frame" ]; then
                        FRAME_COUNT=$((FRAME_COUNT + 1))
                        bashio::log.info "[DEBUG] CAN->MQTT frame #$FRAME_COUNT: $frame"
                        echo "$frame"
                    fi
                fi
            done | mosquitto_pub -h "$MQTT_HOST" -p "$MQTT_PORT" $MQTT_AUTH_ARGS \
                                -t "$MQTT_TOPIC_RAW" -q 1 -l
        else
            # Normal mode: just process frames
            candump -L "$CAN_INTERFACE" 2>&1 | while IFS= read -r line; do
                # Still log errors even in normal mode
                if [[ "$line" =~ ^error ]] || [[ "$line" =~ ^Error ]] || [[ "$line" =~ ^WARNING ]]; then
                    bashio::log.error "CAN->MQTT candump error: $line"
                else
                    frame=$(echo "$line" | awk '{print $3}')
                    if [ -n "$frame" ]; then
                        echo "$frame"
                    fi
                fi
            done | mosquitto_pub -h "$MQTT_HOST" -p "$MQTT_PORT" $MQTT_AUTH_ARGS \
                                -t "$MQTT_TOPIC_RAW" -q 1 -l
        fi

        EXIT_CODE=$?
        [ "$DEBUG_LOGGING" = "true" ] && bashio::log.warning "[DEBUG] CAN->MQTT: candump exited with code $EXIT_CODE"
        [ "$DEBUG_LOGGING" = "true" ] && bashio::log.warning "[DEBUG] CAN->MQTT: Total frames received before disconnect: $FRAME_COUNT"

        bashio::log.warning "CAN->MQTT bridge disconnected, reconnecting in 30 seconds..."
        sleep 30
    done
} &
CAN_TO_MQTT_PID=$!
bashio::log.info "✅ CAN->MQTT bridge started (PID: $CAN_TO_MQTT_PID)"

# MQTT -> CAN Bridge (with error handling and reconnection)
bashio::log.info "Starting MQTT->CAN bridge..."
{
    while true; do
        [ "$DEBUG_LOGGING" = "true" ] && bashio::log.info "[DEBUG] Starting MQTT->CAN bridge connection"
        mosquitto_sub -h "$MQTT_HOST" -p "$MQTT_PORT" $MQTT_AUTH_ARGS \
                      -t "$MQTT_TOPIC_SEND" -q 1 2>/dev/null | \
        while IFS= read -r message; do
            if [ -n "$message" ]; then
                [ "$DEBUG_LOGGING" = "true" ] && bashio::log.info "[DEBUG] MQTT->CAN received: $message"

                # Convert frame format if needed (from raw hex to ID#DATA format)
                if [[ "$message" =~ ^[0-9A-Fa-f]+$ ]] && [[ ${#message} -gt 8 ]]; then
                    # Extract CAN ID (first 8 characters) and data (remaining)
                    raw_can_id="${message:0:8}"
                    can_data="${message:8}"

                    # Pad CAN ID to 8 characters if needed for Extended Frame Format
                    if [ ${#raw_can_id} -lt 8 ]; then
                        # Pad with leading zeros to make it 8 chars (Extended Frame Format)
                        can_id=$(printf "%08s" "$raw_can_id")
                    else
                        can_id="$raw_can_id"
                    fi

                    # Validate data length (max 8 bytes = 16 hex chars)
                    if [ ${#can_data} -gt 16 ]; then
                        bashio::log.warning "[$(date '+%H:%M:%S')] Data too long (${#can_data} chars), truncating to 16 chars"
                        can_data="${can_data:0:16}"
                    fi

                    formatted_message="${can_id}#${can_data}"
                    [ "$DEBUG_LOGGING" = "true" ] && bashio::log.info "[DEBUG] Converted: $message -> $formatted_message"
                else
                    # Check if it's already in ID#DATA format but needs CAN ID padding
                    if [[ "$message" =~ ^[0-9A-Fa-f]+#[0-9A-Fa-f]*$ ]]; then
                        # Split existing ID#DATA format
                        existing_id="${message%#*}"
                        existing_data="${message#*#}"

                        # Pad CAN ID if it's 7 characters (common for Extended Frames)
                        if [ ${#existing_id} -eq 7 ]; then
                            padded_id="0${existing_id}"
                            formatted_message="${padded_id}#${existing_data}"
                            [ "$DEBUG_LOGGING" = "true" ] && bashio::log.info "[DEBUG] Padded CAN ID: $message -> $formatted_message"
                        else
                            formatted_message="$message"
                        fi
                    else
                        # Different format, use as-is
                        formatted_message="$message"
                    fi
                fi

                # Send with error logging
                if cansend_output=$(cansend "$CAN_INTERFACE" "$formatted_message" 2>&1); then
                    [ "$DEBUG_LOGGING" = "true" ] && bashio::log.info "[DEBUG] Successfully sent CAN frame: $formatted_message"
                else
                    bashio::log.error "Failed to send CAN frame: $formatted_message"
                    bashio::log.error "Error details: $cansend_output"
                    bashio::log.error "Original MQTT message: $message"
                fi
            fi
        done
        
        bashio::log.warning "MQTT->CAN bridge disconnected, reconnecting in 30 seconds..."
        sleep 30
    done
} &
MQTT_TO_CAN_PID=$!
bashio::log.info "✅ MQTT->CAN bridge started (PID: $MQTT_TO_CAN_PID)"

# ========================
# Announce Online Status
# ========================
sleep 2  # Give bridges time to start

# Use a single connection for status messages
{
    echo "bridge_online"
    sleep 1
} | mosquitto_pub -h "$MQTT_HOST" -p "$MQTT_PORT" $MQTT_AUTH_ARGS \
                  -t "$MQTT_TOPIC_STATUS" -q 1 -r -l

# ========================
# Start Ingress Web Server
# ========================
if bashio::var.true "$(bashio::addon.ingress)"; then
    bashio::log.info "Starting ingress web server..."
    
    # Create simple status page
    mkdir -p /var/www
    cat > /var/www/index.html << EOF
<!DOCTYPE html>
<html>
<head>
    <title>CAN to MQTT Bridge</title>
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <style>
        body { font-family: Arial, sans-serif; margin: 0; padding: 20px; }
        .status { padding: 10px; margin: 10px 0; border-radius: 4px; }
        .online { background-color: #d4edda; color: #155724; }
        .offline { background-color: #f8d7da; color: #721c24; }
        .card { background: white; border-radius: 8px; padding: 20px; margin: 10px 0; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
        h1 { color: #333; }
    </style>
</head>
<body>
    <h1>CAN to MQTT Bridge</h1>
    <div class="card">
        <h2>Status</h2>
        <div id="status" class="status online">Bridge is online</div>
    </div>
    <div class="card">
        <h2>Configuration</h2>
        <p><strong>CAN Interface:</strong> ${CAN_INTERFACE}</p>
        <p><strong>CAN Bitrate:</strong> ${CAN_BITRATE} bps</p>
        <p><strong>MQTT Broker:</strong> ${MQTT_HOST}:${MQTT_PORT}</p>
    </div>
</body>
</html>
EOF

    # Start simple web server
    cd /var/www
    python3 -m http.server 8099 &
    WEB_SERVER_PID=$!
    bashio::log.info "✅ Web server started (PID: $WEB_SERVER_PID)"
fi

bashio::log.info "🚀 CAN-MQTT Bridge is now running!"
bashio::log.info "Monitoring bridge processes. Press Ctrl+C or stop the add-on to shutdown."

# ========================
# Process Monitoring
# ========================
MONITOR_ITERATION=0
while true; do
    # Check if either process died
    if ! kill -0 "$CAN_TO_MQTT_PID" 2>/dev/null; then
        bashio::log.error "CAN->MQTT process died unexpectedly (PID: $CAN_TO_MQTT_PID)"
        update_health_check "UNHEALTHY: CAN->MQTT process died"
        cleanup
        exit 1
    fi

    if ! kill -0 "$MQTT_TO_CAN_PID" 2>/dev/null; then
        bashio::log.error "MQTT->CAN process died unexpectedly (PID: $MQTT_TO_CAN_PID)"
        update_health_check "UNHEALTHY: MQTT->CAN process died"
        cleanup
        exit 1
    fi

    # Debug mode: Log CAN bus statistics every 30 seconds (3 iterations)
    if [ "$DEBUG_LOGGING" = "true" ] && [ $((MONITOR_ITERATION % 3)) -eq 0 ]; then
        if [ -d "/sys/class/net/$CAN_INTERFACE/statistics" ]; then
            RX_PACKETS=$(cat /sys/class/net/$CAN_INTERFACE/statistics/rx_packets 2>/dev/null || echo '0')
            TX_PACKETS=$(cat /sys/class/net/$CAN_INTERFACE/statistics/tx_packets 2>/dev/null || echo '0')
            RX_ERRORS=$(cat /sys/class/net/$CAN_INTERFACE/statistics/rx_errors 2>/dev/null || echo '0')
            TX_ERRORS=$(cat /sys/class/net/$CAN_INTERFACE/statistics/tx_errors 2>/dev/null || echo '0')
            RX_DROPPED=$(cat /sys/class/net/$CAN_INTERFACE/statistics/rx_dropped 2>/dev/null || echo '0')
            TX_DROPPED=$(cat /sys/class/net/$CAN_INTERFACE/statistics/tx_dropped 2>/dev/null || echo '0')

            bashio::log.info "[DEBUG] === CAN Bus Statistics ==="
            bashio::log.info "[DEBUG] RX: packets=$RX_PACKETS errors=$RX_ERRORS dropped=$RX_DROPPED"
            bashio::log.info "[DEBUG] TX: packets=$TX_PACKETS errors=$TX_ERRORS dropped=$TX_DROPPED"

            # Show interface state
            OPERSTATE=$(cat /sys/class/net/$CAN_INTERFACE/operstate 2>/dev/null || echo 'unknown')
            CARRIER=$(cat /sys/class/net/$CAN_INTERFACE/carrier 2>/dev/null || echo 'unknown')
            bashio::log.info "[DEBUG] Interface state: $OPERSTATE, carrier: $CARRIER"

            # If no packets received, provide troubleshooting hint
            if [ "$RX_PACKETS" -eq 0 ] && [ $MONITOR_ITERATION -gt 0 ]; then
                bashio::log.warning "[DEBUG] No CAN frames received yet. Possible causes:"
                bashio::log.warning "[DEBUG]   - No devices transmitting on the CAN bus"
                bashio::log.warning "[DEBUG]   - Wrong bitrate (currently: $CAN_BITRATE bps)"
                bashio::log.warning "[DEBUG]   - Hardware connection issue"
                bashio::log.warning "[DEBUG]   - CAN termination resistor missing/incorrect"
            fi

            bashio::log.info "[DEBUG] =========================="
        fi
    fi

    # Log process health every hour for basic monitoring
    if [ $(($(date +%s) % 3600)) -eq 0 ]; then
        bashio::log.info "Process monitor: CAN->MQTT (PID: $CAN_TO_MQTT_PID), MQTT->CAN (PID: $MQTT_TO_CAN_PID) - all healthy"
    fi

    # Update health check status (local file only)
    update_health_check "OK"

    MONITOR_ITERATION=$((MONITOR_ITERATION + 1))

    # Wait before next check
    sleep 10
done