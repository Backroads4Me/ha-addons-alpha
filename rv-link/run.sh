#!/usr/bin/with-contenv bashio
set -e

bashio::log.info "================================================"
bashio::log.info "🚀 RV Link - Monolith System Starting"
bashio::log.info "================================================"

# ========================
# Configuration
# ========================
SUPERVISOR="http://supervisor"
AUTH_HEADER="Authorization: Bearer $SUPERVISOR_TOKEN"
PROJECT_PATH="/share/rv-link"
BUNDLED_PROJECT="/opt/rv-link-project"

# Add-on Slugs
SLUG_MOSQUITTO="core_mosquitto"
SLUG_NODERED="a0d7b954_nodered"

# Bridge Config
CAN_INTERFACE=$(bashio::config 'can_interface')
CAN_BITRATE=$(bashio::config 'can_bitrate')
MQTT_TOPIC_RAW=$(bashio::config 'mqtt_topic_raw')
MQTT_TOPIC_SEND=$(bashio::config 'mqtt_topic_send')
MQTT_TOPIC_STATUS=$(bashio::config 'mqtt_topic_status')
# FORCE DEBUG LOGGING FOR DIAGNOSTICS
DEBUG_LOGGING="true"
# DEBUG_LOGGING=$(bashio::config 'debug_logging')

# ========================
# Orchestrator Helpers
# ========================
log_debug() {
  if [ "$DEBUG_LOGGING" = "true" ]; then
    # Log to stderr to avoid polluting stdout (which is captured by $())
    echo "[DEBUG] $1" >&2
  fi
}

api_call() {
  local method=$1
  local endpoint=$2
  local data=${3:-}
  
  log_debug "API Call: $method $endpoint"
  if [ -n "$data" ]; then
    log_debug "API Data: $data"
    local response=$(curl -s -X "$method" -H "$AUTH_HEADER" -H "Content-Type: application/json" -d "$data" "$SUPERVISOR$endpoint")
  else
    local response=$(curl -s -X "$method" -H "$AUTH_HEADER" "$SUPERVISOR$endpoint")
  fi
  
  # ALWAYS log response to stderr for diagnostics
  echo "[DEBUG] API Response ($endpoint): $response" >&2
  echo "$response"
}

is_installed() {
  local slug=$1
  local response
  response=$(api_call GET "/addons/$slug/info")

  # Diagnostic logging for troubleshooting
  if [ "$DEBUG_LOGGING" = "true" ]; then
      echo "[DEBUG] Check $slug installed response: $response" >&2
  fi

  # Check if the API call was successful
  if ! echo "$response" | jq -e '.result == "ok"' >/dev/null 2>&1; then
    log_debug "API call to check $slug installation failed"
    return 1
  fi

  # Check installation status
  local installed=$(echo "$response" | jq -r '.data.installed // false')
  log_debug "$slug installed status: $installed"

  [ "$installed" == "true" ]
}

is_running() {
  local slug=$1
  local state
  state=$(echo "$(api_call GET "/addons/$slug/info")" | jq -r '.data.state // "unknown"')
  [ "$state" == "started" ]
}

install_addon() {
  local slug=$1
  bashio::log.info "   > Installing $slug..."
  local result
  result=$(api_call POST "/store/addons/$slug/install")
  if echo "$result" | jq -e '.result == "ok"' >/dev/null 2>&1; then
    bashio::log.info "   ✅ Installed $slug"
  else
    local error_msg=$(echo "$result" | jq -r '.message')
    bashio::log.error "   ❌ Failed to install $slug: $error_msg"

    # Special handling for Node-RED already installed
    if [[ "$slug" == "$SLUG_NODERED" ]] && [[ "$error_msg" == *"already installed"* ]]; then
      bashio::log.error ""
      bashio::log.error "   Node-RED is already installed on your system."
      bashio::log.error "   To use it with RV Link, you must grant permission:"
      bashio::log.error ""
      bashio::log.error "   1. Go to the RV Link add-on Configuration tab"
      bashio::log.error "   2. Enable the 'confirm_nodered_takeover' option"
      bashio::log.error "   3. Save and restart the RV Link add-on"
      bashio::log.error ""
      bashio::log.error "   ⚠️  WARNING: This will replace your existing Node-RED flows with RV Link flows."
    fi

    return 1
  fi
}

start_addon() {
  local slug=$1
  bashio::log.info "   > Starting $slug..."
  local result
  result=$(api_call POST "/addons/$slug/start")
  
  if ! echo "$result" | jq -e '.result == "ok"' >/dev/null 2>&1; then
      bashio::log.error "   ❌ Failed to start $slug. API Response: $(echo "$result" | jq -r '.message // "Unknown error"')"
      return 1
  fi

  local retries=10
  while [ $retries -gt 0 ]; do
    if is_running "$slug"; then
      bashio::log.info "   ✅ $slug is running"
      return 0
    fi
    sleep 2
    ((retries--))
  done
  bashio::log.warning "   ⚠️  $slug started but state is not 'started' yet"
}

set_options() {
  local slug=$1
  local json=$2
  bashio::log.info "   > Configuring $slug..."
  log_debug "Configuration JSON: $json"
  local result
  result=$(api_call POST "/addons/$slug/options" "{\"options\": $json}")
  if echo "$result" | jq -e '.result == "ok"' >/dev/null 2>&1; then
    bashio::log.info "   ✅ Configured $slug"
  else
    bashio::log.error "   ❌ Failed to configure $slug: $(echo "$result" | jq -r '.message')"
    return 1
  fi
}

restart_addon() {
  local slug=$1
  bashio::log.info "   > Restarting $slug..."
  local result
  result=$(api_call POST "/addons/$slug/restart")

  if ! echo "$result" | jq -e '.result == "ok"' >/dev/null 2>&1; then
      bashio::log.error "   ❌ Failed to restart $slug. API Response: $(echo "$result" | jq -r '.message // "Unknown error"')"
      return 1
  fi

  local retries=30
  while [ $retries -gt 0 ]; do
    if is_running "$slug"; then
      bashio::log.info "   ✅ $slug is running"
      return 0
    fi
    sleep 2
    ((retries--))
  done
  bashio::log.error "   ❌ $slug failed to restart in time"
  return 1
}

wait_for_mqtt() {
  local host=$1
  local port=$2
  local user=$3
  local pass=$4

  bashio::log.info "   > Waiting for MQTT broker at $host:$port..."

  local auth_args=""
  [ -n "$user" ] && auth_args="$auth_args -u $user"
  [ -n "$pass" ] && auth_args="$auth_args -P $pass"

  local retries=30
  while [ $retries -gt 0 ]; do
    if timeout 2 mosquitto_pub -h "$host" -p "$port" $auth_args -t "rvlink/test" -m "test" -q 0 2>/dev/null; then
      bashio::log.info "   ✅ MQTT broker is ready"
      return 0
    fi
    sleep 2
    ((retries--))
  done

  bashio::log.error "   ❌ MQTT broker not responding"
  return 1
}

# ========================
# Phase 1: Orchestration
# ========================
bashio::log.info "📋 Phase 1: System Orchestration"
log_debug "Debug logging enabled. This will be verbose."

# DIAGNOSTIC: List all installed addons
bashio::log.info "🔍 Diagnostic: Listing installed addons..."
INSTALLED_ADDONS=$(api_call GET "/addons")
echo "[DEBUG] Installed Addons: $INSTALLED_ADDONS" >&2

# 1. Mosquitto
if is_installed "$SLUG_MOSQUITTO"; then
  # Mosquitto is installed, ensure it's running
  bashio::log.info "   ✅ Mosquitto is already installed"
  if ! is_running "$SLUG_MOSQUITTO"; then
    start_addon "$SLUG_MOSQUITTO" || exit 1
  fi
else
  # Mosquitto is NOT installed. Check for conflicts.
  if bashio::services.available "mqtt"; then
    # MQTT service exists. Check if it's provided by Mosquitto that we just haven't detected yet
    # Get the service config to see which addon provides it
    MQTT_SERVICE_INFO=$(bashio::services "mqtt" "host" 2>/dev/null || echo "")
    log_debug "MQTT service detected. Host: $MQTT_SERVICE_INFO"

    # If the host is core-mosquitto, then it's the official addon - just not detected by is_installed
    if [[ "$MQTT_SERVICE_INFO" == *"core-mosquitto"* ]]; then
      bashio::log.info "   ✅ Mosquitto broker detected via service discovery"
    else
      bashio::log.fatal "❌ CONFLICT DETECTED: An MQTT broker is already active, but it is not the official Mosquitto add-on."
      bashio::log.fatal "   RV Link requires the official 'Mosquitto broker' add-on for guaranteed consistency."
      bashio::log.fatal "   MQTT service host: $MQTT_SERVICE_INFO"
      bashio::log.fatal "   Please uninstall your current MQTT broker and restart RV Link."
      exit 1
    fi
  else
    # No conflict, install Mosquitto
    bashio::log.info "   📥 Mosquitto not found. Installing..."
    install_addon "$SLUG_MOSQUITTO" || exit 1
    start_addon "$SLUG_MOSQUITTO" || exit 1
  fi
fi

# Configure MQTT connection now that Mosquitto is running
# Wait for MQTT service to be registered (takes a few seconds after start)
bashio::log.info "   📡 Waiting for MQTT service registration..."
MQTT_SERVICE_AVAILABLE=false
for i in {1..30}; do
    if bashio::services.available "mqtt" 2>/dev/null; then
        MQTT_SERVICE_AVAILABLE=true
        bashio::log.info "   ✅ MQTT service discovered"
        break
    fi
    sleep 1
done

if [ "$MQTT_SERVICE_AVAILABLE" = "true" ]; then
    MQTT_HOST=$(bashio::services "mqtt" "host")
    MQTT_PORT=$(bashio::services "mqtt" "port")
    MQTT_USER=$(bashio::services "mqtt" "username")
    MQTT_PASS=$(bashio::services "mqtt" "password")
else
    bashio::log.warning "   ⚠️  MQTT service not discovered, using manual configuration"
    MQTT_HOST=$(bashio::config 'mqtt_host')
    MQTT_PORT=$(bashio::config 'mqtt_port')
    MQTT_USER=$(bashio::config 'mqtt_user')
    MQTT_PASS=$(bashio::config 'mqtt_pass')
fi

MQTT_AUTH_ARGS=""
[ -n "$MQTT_USER" ] && MQTT_AUTH_ARGS="$MQTT_AUTH_ARGS -u $MQTT_USER"
[ -n "$MQTT_PASS" ] && MQTT_AUTH_ARGS="$MQTT_AUTH_ARGS -P $MQTT_PASS"

# Verify MQTT is actually responding
wait_for_mqtt "$MQTT_HOST" "$MQTT_PORT" "$MQTT_USER" "$MQTT_PASS" || {
    bashio::log.fatal "❌ MQTT broker is not responding. Cannot continue."
    exit 1
}

# 2. Node-RED
CONFIRM_TAKEOVER=$(bashio::config 'confirm_nodered_takeover')
NODERED_ALREADY_INSTALLED=false

if is_installed "$SLUG_NODERED"; then
  bashio::log.info "   ℹ️  Node-RED is already installed."
  NODERED_ALREADY_INSTALLED=true
else
  # Try to install Node-RED
  bashio::log.info "   📥 Node-RED not found. Installing..."
  if ! install_addon "$SLUG_NODERED"; then
    # Installation failed - check if it's because it's already installed
    local nr_check=$(api_call GET "/addons/$SLUG_NODERED/info")
    if echo "$nr_check" | jq -e '.data.installed == true' >/dev/null 2>&1; then
      bashio::log.info "   ℹ️  Node-RED was already installed (detection issue)"
      NODERED_ALREADY_INSTALLED=true
    else
      # Different error, exit
      exit 1
    fi
  fi
fi

# If Node-RED was already installed, check for takeover permission
if [ "$NODERED_ALREADY_INSTALLED" = "true" ]; then
  if [ "$CONFIRM_TAKEOVER" != "true" ]; then
     bashio::log.warning ""
     bashio::log.warning "   ⚠️  EXISTING INSTALLATION DETECTED"
     bashio::log.warning "   RV Link needs to configure Node-RED to run the RV Link project."
     bashio::log.warning "   This will REPLACE your active Node-RED flows."
     bashio::log.warning "   "
     bashio::log.warning "   To proceed, you must explicitly grant permission:"
     bashio::log.warning "   1. Go to the RV Link add-on configuration."
     bashio::log.warning "   2. Enable 'confirm_nodered_takeover'."
     bashio::log.warning "   3. Restart RV Link."
     bashio::log.warning ""
     bashio::log.fatal "   ❌ Installation aborted to protect existing flows."
     exit 1
  else
     bashio::log.info "   ✅ Permission granted to take over Node-RED."
  fi
fi

# Configure Node-RED
NR_INFO=$(api_call GET "/addons/$SLUG_NODERED/info")
NR_OPTIONS=$(echo "$NR_INFO" | jq '.data.options')
SECRET=$(echo "$NR_OPTIONS" | jq -r '.credential_secret // empty')

# Init command to add context storage to settings.js (runs inside Node-RED container)
# This runs at Node-RED startup and modifies /config/settings.js if contextStorage isn't already present
CONTEXT_STORAGE_INIT_CMD='if [ -f /config/settings.js ] && ! grep -q "contextStorage" /config/settings.js; then sed -i "s/module.exports = {/module.exports = {\n    contextStorage: { default: \"memoryOnly\", memoryOnly: { module: \"memory\" }, file: { module: \"localfilesystem\" } },/" /config/settings.js; fi'

if [ -z "$SECRET" ]; then
  bashio::log.info "   ⚠️  No credential_secret found. Generating one..."
  NEW_SECRET=$(openssl rand -hex 16)
  NEW_OPTIONS=$(echo "$NR_OPTIONS" | jq --arg secret "$NEW_SECRET" --arg initcmd "$CONTEXT_STORAGE_INIT_CMD" '. + {"credential_secret": $secret, "projects": true, "ssl": false, "init_commands": [$initcmd]}')
  set_options "$SLUG_NODERED" "$NEW_OPTIONS" || exit 1
else
  PROJECTS=$(echo "$NR_OPTIONS" | jq -r '.projects')
  INIT_COMMANDS=$(echo "$NR_OPTIONS" | jq -r '.init_commands // [] | length')

  NEEDS_UPDATE=false
  if [ "$PROJECTS" != "true" ]; then
    bashio::log.info "   > Enabling projects..."
    NEEDS_UPDATE=true
  fi

  if [ "$INIT_COMMANDS" -eq 0 ]; then
    bashio::log.info "   > Adding context storage init command..."
    NEEDS_UPDATE=true
  fi

  if [ "$NEEDS_UPDATE" = "true" ]; then
    NEW_OPTIONS=$(echo "$NR_OPTIONS" | jq --arg initcmd "$CONTEXT_STORAGE_INIT_CMD" '. + {"projects": true, "init_commands": [$initcmd]}')
    set_options "$SLUG_NODERED" "$NEW_OPTIONS" || exit 1
  fi
fi

if ! is_running "$SLUG_NODERED"; then
  start_addon "$SLUG_NODERED" || exit 1
fi

# Wait for Node-RED to create settings.js
NODERED_CONFIG_DIR="/addon_configs/$SLUG_NODERED"
SETTINGS_FILE="$NODERED_CONFIG_DIR/settings.js"
bashio::log.info "   ⏳ Waiting for Node-RED to initialize..."
log_debug "Looking for settings.js at: $SETTINGS_FILE"

# Stage 1: Wait for config directory to be created (up to 60 seconds)
for i in {1..60}; do
    if [ -d "$NODERED_CONFIG_DIR" ]; then
        log_debug "Config directory created after $i seconds"
        break
    fi
    if [ $((i % 10)) -eq 0 ]; then
        bashio::log.info "   ⏳ Still waiting for Node-RED config directory... (${i}s)"
    fi
    sleep 1
done

# Stage 2: Wait for settings.js to be created (up to 60 more seconds)
if [ -d "$NODERED_CONFIG_DIR" ]; then
    for i in {1..60}; do
        if [ -f "$SETTINGS_FILE" ]; then
            bashio::log.info "   ✅ Node-RED settings file created"
            break
        fi
        if [ $((i % 10)) -eq 0 ]; then
            bashio::log.info "   ⏳ Still waiting for settings.js file... (${i}s)"
        fi
        sleep 1
    done
fi

# Debug: List what's actually in the directory if file not found
if [ ! -f "$SETTINGS_FILE" ]; then
    log_debug "Settings file not found after waiting. Directory contents:"
    if [ -d "$NODERED_CONFIG_DIR" ]; then
        log_debug "$(ls -la "$NODERED_CONFIG_DIR" 2>&1)"
    else
        log_debug "Directory does not exist: $NODERED_CONFIG_DIR"
    fi
fi

# Context Storage Configuration
if [ -f "$SETTINGS_FILE" ]; then
   if ! grep -q "contextStorage" "$SETTINGS_FILE"; then
     bashio::log.info "   📝 Adding context storage configuration..."
     cp "$SETTINGS_FILE" "$SETTINGS_FILE.bak"

     # Use Python for robust file editing
     python3 -c "
import sys
import re

file_path = '$SETTINGS_FILE'
with open(file_path, 'r') as f:
    content = f.read()

# Config to insert
config = '''
    contextStorage: {
        default: 'memoryOnly',
        memoryOnly: { module: 'memory' },
        file: { module: 'localfilesystem' }
    },
'''

# Find the last closing brace
match = re.search(r'}(\s*;?\s*)$', content)
if match:
    # Insert before the last brace
    new_content = content[:match.start()] + config + content[match.start():]
    with open(file_path, 'w') as f:
        f.write(new_content)
else:
    print('Could not find closing brace in settings.js', file=sys.stderr)
    sys.exit(1)
"
     if [ $? -eq 0 ]; then
        bashio::log.info "   ✅ settings.js updated with context storage"
     else
        bashio::log.warning "   ⚠️  Failed to update settings.js automatically"
     fi
   else
     bashio::log.info "   ✅ Context storage already configured"
   fi
else
   bashio::log.warning "   ⚠️  settings.js not found, skipping context storage config"
fi

# ========================
# Phase 2: Deployment
# ========================
bashio::log.info "📋 Phase 2: Deploying RV Link Project"
bashio::log.info "   📦 Installing bundled project to $PROJECT_PATH..."
log_debug "Removing old project files..."
rm -rf "$PROJECT_PATH"
log_debug "Copying new project files from $BUNDLED_PROJECT..."
cp -r "$BUNDLED_PROJECT" "$PROJECT_PATH"
bashio::log.info "   ✅ Project deployed"

# Restart Node-RED to pick up new flows
bashio::log.info "   🔄 Restarting Node-RED to load new project..."
restart_addon "$SLUG_NODERED" || exit 1

# ========================
# Phase 3: CAN Bridge
# ========================
bashio::log.info "📋 Phase 3: Starting CAN Bridge"

# CAN Init
CAN_AVAILABLE=false
bashio::log.info "   > Initializing CAN interface $CAN_INTERFACE..."

if [ -f "/sys/class/net/$CAN_INTERFACE/operstate" ] && [ "$(cat "/sys/class/net/$CAN_INTERFACE/operstate")" = "up" ]; then
    ip link set "$CAN_INTERFACE" down
fi

if ip link set "$CAN_INTERFACE" up type can bitrate "$CAN_BITRATE" 2>/dev/null; then
    if ip link set "$CAN_INTERFACE" up 2>/dev/null; then
        bashio::log.info "   ✅ CAN interface up"
        CAN_AVAILABLE=true
    else
        bashio::log.error "   ❌ Failed to bring CAN interface up"
    fi
else
    bashio::log.error "   ❌ Failed to configure CAN interface (bitrate: $CAN_BITRATE)"
    bashio::log.error "   Possible causes:"
    bashio::log.error "   - No CAN hardware connected"
    bashio::log.error "   - Wrong interface name (current: $CAN_INTERFACE)"
    bashio::log.error "   - Incompatible bitrate (current: $CAN_BITRATE)"
fi

if [ "$CAN_AVAILABLE" = "false" ]; then
    bashio::log.warning "   ⚠️  CAN bridge will NOT start - hardware not available"
    bashio::log.warning "   The system orchestration succeeded, but CAN monitoring is disabled."
    bashio::log.warning "   Connect CAN hardware and restart this add-on to enable the bridge."
fi

# Bridge Loop
bashio::log.info "🚀 RV Link System Fully Operational"

# Cleanup handler
cleanup() {
    bashio::log.info "Shutdown signal received..."
    [ -n "$PID_C2M" ] && kill "$PID_C2M" 2>/dev/null
    [ -n "$PID_M2C" ] && kill "$PID_M2C" 2>/dev/null
    exit 0
}
trap cleanup SIGTERM SIGINT

if [ "$CAN_AVAILABLE" = "true" ]; then
    bashio::log.info "   🔗 Starting CAN-MQTT Bridge..."

    # CAN -> MQTT
    {
        while true; do
            candump -L "$CAN_INTERFACE" 2>/dev/null | awk '{print $3}' | \
            while IFS= read -r frame; do
                [ -n "$frame" ] && echo "$frame"
            done | mosquitto_pub -h "$MQTT_HOST" -p "$MQTT_PORT" $MQTT_AUTH_ARGS \
                                -t "$MQTT_TOPIC_RAW" -q 1 -l
            bashio::log.warning "CAN->MQTT bridge stopped, restarting in 5 seconds..."
            sleep 5
        done
    } &
    PID_C2M=$!

    # MQTT -> CAN
    {
        while true; do
            mosquitto_sub -h "$MQTT_HOST" -p "$MQTT_PORT" $MQTT_AUTH_ARGS \
                          -t "$MQTT_TOPIC_SEND" -q 1 | \
            while IFS= read -r message; do
                if [ -n "$message" ]; then
                     cansend "$CAN_INTERFACE" "$message" 2>/dev/null || bashio::log.warning "Failed to send: $message"
                fi
            done
            bashio::log.warning "MQTT->CAN bridge stopped, restarting in 5 seconds..."
            sleep 5
        done
    } &
    PID_M2C=$!

    bashio::log.info "   ✅ Bridge processes started (C2M: $PID_C2M, M2C: $PID_M2C)"

    # Monitor bridge processes
    while true; do
        if ! kill -0 "$PID_C2M" 2>/dev/null; then
            bashio::log.error "❌ CAN->MQTT process died unexpectedly!"
            exit 1
        fi
        if ! kill -0 "$PID_M2C" 2>/dev/null; then
            bashio::log.error "❌ MQTT->CAN process died unexpectedly!"
            exit 1
        fi
        sleep 10
    done
else
    # No CAN hardware, just keep addon running
    bashio::log.info "   💤 Running in orchestrator-only mode (no CAN bridge)"
    bashio::log.info "   The add-on will remain running. Connect CAN hardware and restart to enable bridging."

    # Sleep indefinitely
    while true; do
        sleep 3600
    done
fi
