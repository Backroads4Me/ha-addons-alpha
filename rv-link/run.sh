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
SLUG_CAN_BRIDGE="837b0638_can-mqtt-bridge"

# Bridge Config (to pass to CAN bridge addon)
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
  # If "installed" field exists, use it
  local installed=$(echo "$response" | jq -r '.data.installed // empty')
  if [ -n "$installed" ]; then
    log_debug "$slug explicit installed status: $installed"
    [ "$installed" == "true" ]
    return $?
  fi

  # If no "installed" field, check if "version" field exists (indicates installed addon)
  local version=$(echo "$response" | jq -r '.data.version // empty')
  if [ -n "$version" ]; then
    log_debug "$slug has version $version, therefore is installed"
    return 0
  fi

  log_debug "$slug does not appear to be installed"
  return 1
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

set_boot_auto() {
  local slug=$1
  bashio::log.info "   > Setting $slug to start on boot..."
  local result
  result=$(api_call POST "/addons/$slug/options" '{"boot":"auto"}')
  if echo "$result" | jq -e '.result == "ok"' >/dev/null 2>&1; then
    bashio::log.info "   ✅ $slug will start on boot"
  else
    bashio::log.warning "   ⚠️  Failed to set boot option for $slug: $(echo "$result" | jq -r '.message')"
    return 1
  fi
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
  # Mosquitto is NOT installed. Install it.
  bashio::log.info "   📥 Mosquitto not found. Installing..."
  install_addon "$SLUG_MOSQUITTO" || exit 1
  start_addon "$SLUG_MOSQUITTO" || exit 1
fi

# Ensure Mosquitto starts on boot
set_boot_auto "$SLUG_MOSQUITTO" || bashio::log.warning "   ⚠️  Could not set Mosquitto to auto-start"

# Configure MQTT connection now that Mosquitto is running
# Wait for MQTT service to be registered (takes a few seconds after start)
bashio::log.info "   📡 Waiting for MQTT service registration..."
MQTT_SERVICE_AVAILABLE=false
for i in {1..30}; do
    if bashio::services.available "mqtt" &>/dev/null; then
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
    nr_check=$(api_call GET "/addons/$SLUG_NODERED/info")
    # Check if addon is actually installed (by checking for version field)
    nr_version=$(echo "$nr_check" | jq -r '.data.version // empty')
    if [ -n "$nr_version" ]; then
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

# Init command to configure settings.js (runs inside Node-RED container at startup)
# Uses shell tools (sed, grep) that are available in Node-RED container
SETTINGS_INIT_CMD='[ ! -f /config/settings.js ] && exit 0; grep -q "flowFile:" /config/settings.js || sed -i "s|module.exports = {|module.exports = {\\n    flowFile: \"/share/rv-link/flows.json\",\\n    contextStorage: { default: \"memory\", memory: { module: \"memory\" }, file: { module: \"localfilesystem\" } },|" /config/settings.js; echo "Node-RED configuration complete"'

if [ -z "$SECRET" ]; then
  bashio::log.info "   ⚠️  No credential_secret found. Generating one..."
  NEW_SECRET=$(openssl rand -hex 16)
  NEW_OPTIONS=$(echo "$NR_OPTIONS" | jq --arg secret "$NEW_SECRET" --arg initcmd "$SETTINGS_INIT_CMD" '. + {"credential_secret": $secret, "ssl": false, "init_commands": [$initcmd]}')
  set_options "$SLUG_NODERED" "$NEW_OPTIONS" || exit 1
else
  INIT_COMMANDS=$(echo "$NR_OPTIONS" | jq -r '.init_commands // [] | length')

  if [ "$INIT_COMMANDS" -eq 0 ]; then
    bashio::log.info "   > Adding flowFile init command..."
    NEW_OPTIONS=$(echo "$NR_OPTIONS" | jq --arg initcmd "$SETTINGS_INIT_CMD" '. + {"init_commands": [$initcmd]}')
    set_options "$SLUG_NODERED" "$NEW_OPTIONS" || exit 1
  fi
fi

if ! is_running "$SLUG_NODERED"; then
  start_addon "$SLUG_NODERED" || exit 1
fi

# Ensure Node-RED starts on boot
set_boot_auto "$SLUG_NODERED" || bashio::log.warning "   ⚠️  Could not set Node-RED to auto-start"

# Settings.js Configuration
# Note: We cannot directly access Node-RED's settings.js from this container.
# Instead, we use init_commands (configured above) which run inside the Node-RED container.
bashio::log.info "   📝 Settings.js will be configured via init_commands on Node-RED startup"
log_debug "Current working directory: $(pwd)"
log_debug "Root directory accessible paths: $(ls -la / | grep -E 'addon|config|share' || echo 'No matching directories')"
bashio::log.info "   ℹ️  Flow file path will be configured automatically"

# ========================
# Phase 2: Deployment
# ========================
bashio::log.info "📋 Phase 2: Deploying RV Link Flows"

PRESERVE_CUSTOMIZATIONS=$(bashio::config 'preserve_project_customizations')
FLOWS_FILE="$PROJECT_PATH/flows.json"

# Ensure directory exists
mkdir -p "$PROJECT_PATH"

# Ensure directory exists
mkdir -p "$PROJECT_PATH"

# Check if project directory is populated
if [ "$(ls -A $PROJECT_PATH)" ]; then
    if [ "$PRESERVE_CUSTOMIZATIONS" = "true" ]; then
        bashio::log.info "   ℹ️  Project files found at $PROJECT_PATH"
        bashio::log.info "   ℹ️  Preserving customizations (set preserve_project_customizations=false to update)"
        log_debug "Skipping project deployment to preserve user changes"
    else
        bashio::log.info "   🔄 Updating project with bundled version..."
        log_debug "Syncing files from $BUNDLED_PROJECT to $PROJECT_PATH..."
        # Copy all files, including hidden ones, recursively
        cp -rf "$BUNDLED_PROJECT/." "$PROJECT_PATH/"
        bashio::log.info "   ✅ Project files deployed (updated)"
    fi
else
    bashio::log.info "   📦 Installing bundled project to $PROJECT_PATH..."
    log_debug "Copying files from $BUNDLED_PROJECT..."
    cp -rf "$BUNDLED_PROJECT/." "$PROJECT_PATH/"
    bashio::log.info "   ✅ Project files deployed (first install)"
fi

# Restart Node-RED to pick up new flows
bashio::log.info "   🔄 Restarting Node-RED to load flows..."
restart_addon "$SLUG_NODERED" || exit 1

# ========================
# Phase 3: CAN-MQTT Bridge
# ========================
bashio::log.info "📋 Phase 3: Installing CAN-MQTT Bridge"

# Check if CAN-MQTT Bridge is installed
if ! is_installed "$SLUG_CAN_BRIDGE"; then
    bashio::log.info "   🔽 Installing CAN-MQTT Bridge addon..."
    if ! install_addon "$SLUG_CAN_BRIDGE"; then
        bashio::log.fatal "❌ Failed to install CAN-MQTT Bridge addon"
        bashio::log.fatal "   This addon is essential for RV Link to function."
        exit 1
    fi
else
    bashio::log.info "   ✅ CAN-MQTT Bridge addon already installed"
fi

# Configure CAN-MQTT Bridge with our settings
bashio::log.info "   ⚙️  Configuring CAN-MQTT Bridge..."
CAN_BRIDGE_CONFIG=$(cat <<EOF
{
  "options": {
    "can_interface": "$CAN_INTERFACE",
    "can_bitrate": "$CAN_BITRATE",
    "mqtt_host": "$MQTT_HOST",
    "mqtt_port": $MQTT_PORT,
    "mqtt_user": "$MQTT_USER",
    "mqtt_pass": "$MQTT_PASS",
    "mqtt_topic_raw": "$MQTT_TOPIC_RAW",
    "mqtt_topic_send": "$MQTT_TOPIC_SEND",
    "mqtt_topic_status": "$MQTT_TOPIC_STATUS",
    "debug_logging": false,
    "ssl": false
  }
}
EOF
)

result=$(api_call POST "/addons/$SLUG_CAN_BRIDGE/options" "$CAN_BRIDGE_CONFIG")
if echo "$result" | jq -e '.result == "ok"' >/dev/null 2>&1; then
    bashio::log.info "   ✅ CAN-MQTT Bridge configured"
else
    bashio::log.error "   ⚠️  Failed to configure CAN-MQTT Bridge: $(echo "$result" | jq -r '.message')"
fi

# Set CAN-MQTT Bridge to start on boot
set_boot_auto "$SLUG_CAN_BRIDGE"

# Start CAN-MQTT Bridge
bashio::log.info "   ▶️  Starting CAN-MQTT Bridge..."
result=$(api_call POST "/addons/$SLUG_CAN_BRIDGE/start")
if echo "$result" | jq -e '.result == "ok"' >/dev/null 2>&1; then
    bashio::log.info "   ✅ CAN-MQTT Bridge started"
else
    bashio::log.warning "   ⚠️  Failed to start CAN-MQTT Bridge: $(echo "$result" | jq -r '.message')"
    bashio::log.warning "   Note: Bridge will fail if CAN hardware is not connected, but system orchestration succeeded."
fi

# ========================
# All Systems Ready
# ========================
bashio::log.info "🚀 RV Link System Fully Operational"
bashio::log.info ""
bashio::log.info "   Components installed:"
bashio::log.info "   ✅ Mosquitto MQTT Broker"
bashio::log.info "   ✅ Node-RED Automation"
bashio::log.info "   ✅ CAN-MQTT Bridge"
bashio::log.info ""
bashio::log.info "   💡 Access Node-RED: Settings → Add-ons → Node-RED → Open Web UI"
bashio::log.info "   💡 CAN bridge status: Check CAN-MQTT Bridge addon logs"

# Keep addon running as orchestrator
bashio::log.info "   💤 RV Link orchestrator will remain running..."

# Cleanup handler
cleanup() {
    bashio::log.info "Shutdown signal received, exiting gracefully..."
    exit 0
}
trap cleanup SIGTERM SIGINT

# Sleep indefinitely
while true; do
    sleep 3600
done
