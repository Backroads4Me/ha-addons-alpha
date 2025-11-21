#!/usr/bin/with-contenv bashio
set -e

bashio::log.info "================================================"
bashio::log.info "🚐 RV Link - System Starting"
bashio::log.info "================================================"

# ========================
# Configuration
# ========================
SUPERVISOR="http://supervisor"
AUTH_HEADER="Authorization: Bearer $SUPERVISOR_TOKEN"
PROJECT_PATH="/share/.rv-link"
BUNDLED_PROJECT="/opt/rv-link-project"

# Add-on Slugs
SLUG_MOSQUITTO="core_mosquitto"
SLUG_NODERED="a0d7b954_nodered"
SLUG_CAN_BRIDGE="837b0638_can-mqtt-bridge"

# State file to track RV Link management
STATE_FILE="/data/.rvlink-state.json"
ADDON_VERSION="0.6.39"

# Bridge Config (to pass to CAN bridge addon)
CAN_INTERFACE=$(bashio::config 'can_interface')
CAN_BITRATE=$(bashio::config 'can_bitrate')
MQTT_TOPIC_RAW=$(bashio::config 'mqtt_topic_raw')
MQTT_TOPIC_SEND=$(bashio::config 'mqtt_topic_send')
MQTT_TOPIC_STATUS=$(bashio::config 'mqtt_topic_status')
MQTT_USER=$(bashio::config 'mqtt_user')
MQTT_PASS=$(bashio::config 'mqtt_pass')
DEBUG_LOGGING=$(bashio::config 'debug_logging')

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

  echo "$response"
}

is_installed() {
  local slug=$1
  local response
  response=$(api_call GET "/addons/$slug/info")

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

wait_for_nodered_api() {
  bashio::log.info "   > Waiting for Node-RED API to be ready..."
  
  # Try different hostnames for Node-RED access
  local hosts=("a0d7b954-nodered" "172.30.32.1" "homeassistant.local")
  local port=1880
  local retries=60
  
  while [ $retries -gt 0 ]; do
    for host in "${hosts[@]}"; do
      local url="http://${host}:${port}/"
      if [ "$DEBUG_LOGGING" = "true" ]; then
        bashio::log.info "   [DEBUG] Trying $url"
      fi
      
      # Capture output/error to debug
      local output
      # Use -S to show errors even with -s (silent mode)
      # Use -v (verbose) if debug logging is enabled for maximum detail
      if [ "$DEBUG_LOGGING" = "true" ]; then
          if output=$(curl -v -sS -f -m 2 "$url" 2>&1); then
            bashio::log.info "   ✅ Node-RED API is ready at $url"
            echo "$host" > /tmp/nodered_host
            return 0
          fi
      else
          if output=$(curl -sS -f -m 2 "$url" 2>&1); then
            bashio::log.info "   ✅ Node-RED API is ready at $url"
            echo "$host" > /tmp/nodered_host
            return 0
          fi
      fi

      # Only log detailed error if debug logging is on OR if we are running out of retries (e.g. last 5)
      if [ "$DEBUG_LOGGING" = "true" ] || [ $retries -le 5 ]; then
           bashio::log.warning "   [DEBUG] Connection to $url failed: $output"
      fi
    done
    
    sleep 2
    ((retries--))
  done
  
  bashio::log.error "   ❌ Node-RED API not responding on any known host"
  return 1
}

deploy_nodered_flows() {
  bashio::log.info "   > Triggering Node-RED flow deployment..."
  
  # Get the working host from detection
  local host="a0d7b954-nodered"
  if [ -f /tmp/nodered_host ]; then
    host=$(cat /tmp/nodered_host)
  fi
  local base_url="http://${host}:1880"
  
  # Get current flows from Node-RED
  local flows=$(curl -s -f -m 5 "${base_url}/flows" 2>/dev/null)
  
  if [ -z "$flows" ] || ! echo "$flows" | jq -e '.' >/dev/null 2>&1; then
    bashio::log.error "   ❌ Failed to fetch flows from Node-RED at ${base_url}"
    return 1
  fi
  
  # Deploy the flows (POST back to trigger encryption of credentials)
  local result=$(curl -s -f -m 5 -X POST \
    -H "Content-Type: application/json" \
    -H "Node-RED-Deployment-Type: full" \
    -d "$flows" \
    "${base_url}/flows" 2>/dev/null)
  
  if [ $? -eq 0 ]; then
    bashio::log.info "   ✅ Node-RED flows deployed (credentials encrypted)"
    return 0
  else
    bashio::log.warning "   ⚠️  Failed to deploy flows, may need manual deployment"
    return 1
  fi
}

# ========================
# State Management
# ========================
is_nodered_managed() {
  if [ ! -f "$STATE_FILE" ]; then
    return 1
  fi
  
  local managed=$(jq -r '.nodered_managed // false' "$STATE_FILE")
  [ "$managed" = "true" ]
}

mark_nodered_managed() {
  mkdir -p /data
  cat > "$STATE_FILE" <<EOF
{
  "nodered_managed": true,
  "version": "$ADDON_VERSION",
  "last_update": "$(date -Iseconds)"
}
EOF
  bashio::log.info "   ✅ Marked Node-RED as managed by RV Link"
}

get_managed_version() {
  if [ ! -f "$STATE_FILE" ]; then
    echo ""
    return
  fi
  jq -r '.version // ""' "$STATE_FILE"
}

# ========================
# Phase 0: Deployment
# ========================
bashio::log.info "📋 Phase 0: Deploying Files"

# Ensure directory exists
mkdir -p "$PROJECT_PATH"

# Always deploy/update project files from bundled version
if [ "$(ls -A $PROJECT_PATH)" ]; then
    bashio::log.info "   🔄 Updating project files from bundled version..."
else
    bashio::log.info "   📦 Deploying bundled project to $PROJECT_PATH..."
fi

# Sync all files, deleting extraneous ones in destination
rsync -a --delete "$BUNDLED_PROJECT/" "$PROJECT_PATH/"
# Ensure permissions are open (Node-RED runs as non-root)
chmod -R 777 "$PROJECT_PATH"
bashio::log.info "   ✅ Project files deployed"


# ========================
# Phase 1: Mosquitto MQTT Broker
# ========================
bashio::log.info "📋 Phase 1: Installing Mosquitto MQTT Broker"

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

# Always ensure rvlink user exists in Mosquitto for consistency
# Both Node-RED and CAN-MQTT Bridge will use these credentials
bashio::log.info "   ⚙️  Ensuring 'rvlink' user exists in Mosquitto..."
# MQTT_USER and MQTT_PASS are read from config at the top
MQTT_HOST="core-mosquitto"
MQTT_PORT=1883

# Create user in Mosquitto options
MOSQUITTO_OPTIONS=$(api_call GET "/addons/$SLUG_MOSQUITTO/info" | jq '.data.options')

# Remove existing rvlink user if present, then add it with current password
# Handle case where logins might be null
NEW_MOSQUITTO_OPTIONS=$(echo "$MOSQUITTO_OPTIONS" | jq --arg user "$MQTT_USER" --arg pass "$MQTT_PASS" '
    .logins = (.logins // []) | 
    .logins |= (map(select(.username != $user)) + [{"username": $user, "password": $pass}])
')

if [ -z "$NEW_MOSQUITTO_OPTIONS" ] || [ "$NEW_MOSQUITTO_OPTIONS" == "null" ]; then
    bashio::log.error "   ❌ Failed to generate Mosquitto configuration"
    exit 1
fi

api_call POST "/addons/$SLUG_MOSQUITTO/options" "{\"options\": $NEW_MOSQUITTO_OPTIONS}" > /dev/null
bashio::log.info "   ✅ Configured Mosquitto user: $MQTT_USER"

# Restart Mosquitto to apply new user
if is_running "$SLUG_MOSQUITTO"; then
  restart_addon "$SLUG_MOSQUITTO" || exit 1
fi

# Verify MQTT is actually responding
wait_for_mqtt "$MQTT_HOST" "$MQTT_PORT" "$MQTT_USER" "$MQTT_PASS" || {
    bashio::log.fatal "❌ MQTT broker is not responding. Cannot continue."
    exit 1
}

# ========================
# Phase 2: CAN-MQTT Bridge
# ========================
bashio::log.info "📋 Phase 2: Installing CAN-MQTT Bridge"

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

# Use jq to safely construct the JSON, handling special characters in passwords
CAN_BRIDGE_CONFIG=$(jq -n \
  --arg can_interface "$CAN_INTERFACE" \
  --arg can_bitrate "$CAN_BITRATE" \
  --arg mqtt_host "$MQTT_HOST" \
  --argjson mqtt_port "$MQTT_PORT" \
  --arg mqtt_user "$MQTT_USER" \
  --arg mqtt_pass "$MQTT_PASS" \
  --arg mqtt_topic_raw "$MQTT_TOPIC_RAW" \
  --arg mqtt_topic_send "$MQTT_TOPIC_SEND" \
  --arg mqtt_topic_status "$MQTT_TOPIC_STATUS" \
  '{
    "options": {
      "can_interface": $can_interface,
      "can_bitrate": $can_bitrate,
      "mqtt_host": $mqtt_host,
      "mqtt_port": $mqtt_port,
      "mqtt_user": $mqtt_user,
      "mqtt_pass": $mqtt_pass,
      "mqtt_topic_raw": $mqtt_topic_raw,
      "mqtt_topic_send": $mqtt_topic_send,
      "mqtt_topic_status": $mqtt_topic_status,
      "debug_logging": false,
      "ssl": false
    }
  }'
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
# Phase 3: Node-RED
# ========================
bashio::log.info "📋 Phase 3: Installing Node-RED"

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

# If Node-RED was already installed, check if we need takeover permission
# Skip takeover check if already managed by RV Link
if [ "$NODERED_ALREADY_INSTALLED" = "true" ]; then
  if is_nodered_managed; then
    MANAGED_VERSION=$(get_managed_version)
    bashio::log.info "   ✅ Node-RED already managed by RV Link (version $MANAGED_VERSION)"
  else
    # Node-RED exists but not managed by RV Link - need permission
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
fi

# Configure Node-RED
NR_INFO=$(api_call GET "/addons/$SLUG_NODERED/info")
NR_OPTIONS=$(echo "$NR_INFO" | jq '.data.options')
SECRET=$(echo "$NR_OPTIONS" | jq -r '.credential_secret // empty')

# Init command - Point Node-RED to project directory instead of copying flows
# This keeps all files in one place and avoids duplication
SETTINGS_INIT_CMD="mkdir -p /config/projects/rv-link-node-red; cp -rf /share/.rv-link/. /config/projects/rv-link-node-red/; rm -f /config/projects/rv-link-node-red/flows_cred.json; jq --arg user '$MQTT_USER' --arg pass '$MQTT_PASS' 'map(if .id == \"80727e60a251c36c\" then . + {credentials: {user: \$user, password: \$pass}} else . end)' /config/projects/rv-link-node-red/flows.json > /config/projects/rv-link-node-red/flows.json.tmp && mv /config/projects/rv-link-node-red/flows.json.tmp /config/projects/rv-link-node-red/flows.json; if [ -f /config/settings.js ]; then sed -i \"s|flowFile:.*|flowFile: 'projects/rv-link-node-red/flows.json',|\" /config/settings.js; grep -q 'adminAuth:' /config/settings.js || sed -i 's|module.exports.*=.*{|module.exports = {\\n    adminAuth: { type: \"credentials\", users: [], default: { permissions: \"*\" } },|' /config/settings.js; grep -q 'contextStorage:' /config/settings.js || sed -i 's|module.exports.*=.*{|module.exports = {\\n    contextStorage: { default: \"memory\", memory: { module: \"memory\" }, file: { module: \"localfilesystem\" } },|' /config/settings.js; fi; echo 'Node-RED configuration complete'"

NEEDS_RESTART=false

if [ -z "$SECRET" ]; then
  bashio::log.info "   ⚠️  No credential_secret found. Generating one..."
  NEW_SECRET=$(openssl rand -hex 16)
  NEW_OPTIONS=$(echo "$NR_OPTIONS" | jq --arg secret "$NEW_SECRET" --arg initcmd "$SETTINGS_INIT_CMD" '. + {"credential_secret": $secret, "ssl": false, "init_commands": [$initcmd]}')
  set_options "$SLUG_NODERED" "$NEW_OPTIONS" || exit 1
  NEEDS_RESTART=true
else
  CURRENT_INIT_CMD=$(echo "$NR_OPTIONS" | jq -r '.init_commands[0] // empty')

  if [ "$CURRENT_INIT_CMD" != "$SETTINGS_INIT_CMD" ]; then
    bashio::log.info "   > Updating Node-RED init commands..."
    NEW_OPTIONS=$(echo "$NR_OPTIONS" | jq --arg initcmd "$SETTINGS_INIT_CMD" '. + {"init_commands": [$initcmd]}')
    set_options "$SLUG_NODERED" "$NEW_OPTIONS" || exit 1
    NEEDS_RESTART=true
  else
    bashio::log.info "   ✅ Node-RED init commands are up to date"
  fi
fi

# Ensure Node-RED starts/restarts to apply init commands
if [ "$NEEDS_RESTART" = "true" ]; then
  if is_running "$SLUG_NODERED"; then
    # Already running, restart to apply new init commands
    bashio::log.info "   > Restarting Node-RED to apply init commands..."
    restart_addon "$SLUG_NODERED" || exit 1
  else
    # Not running, start it (init commands will run on startup)
    bashio::log.info "   > Starting Node-RED with new configuration..."
    start_addon "$SLUG_NODERED" || exit 1
  fi
else
  # No changes needed, but ensure it's running
  if ! is_running "$SLUG_NODERED"; then
    start_addon "$SLUG_NODERED" || exit 1
  fi
fi

# Ensure Node-RED starts on boot
set_boot_auto "$SLUG_NODERED" || bashio::log.warning "   ⚠️  Could not set Node-RED to auto-start"

# Track deployment success for final status
DEPLOYMENT_SUCCESSFUL=true

# Verify Node-RED is actually running before attempting API access
bashio::log.info "   > Verifying Node-RED is running..."
nr_retries=30
while [ $nr_retries -gt 0 ]; do
  if is_running "$SLUG_NODERED"; then
    bashio::log.info "   ✅ Node-RED is in 'started' state"
    break
  fi
  bashio::log.info "   > Waiting for Node-RED to reach 'started' state... ($nr_retries retries left)"
  sleep 2
  ((nr_retries--))
done

if ! is_running "$SLUG_NODERED"; then
  bashio::log.error "   ❌ Node-RED failed to reach 'started' state"
  bashio::log.error "   ❌ RV Link installation FAILED"
  DEPLOYMENT_SUCCESSFUL=false
else
  # Wait for Node-RED HTTP API and deploy flows to activate credentials
  # This encrypts the plaintext credentials from flows.json into flows_cred.json
  if wait_for_nodered_api; then
    if ! deploy_nodered_flows; then
      bashio::log.warning "   ⚠️  Auto-deployment failed, you may need to manually deploy flows in Node-RED UI"
      DEPLOYMENT_SUCCESSFUL=false
    fi
  else
    bashio::log.error "   ❌ Node-RED API not responding"
    bashio::log.error "   ❌ RV Link installation FAILED"
    DEPLOYMENT_SUCCESSFUL=false
  fi
fi

# Mark/update Node-RED as managed by RV Link (updates version on upgrades)
if [ "$DEPLOYMENT_SUCCESSFUL" = "true" ]; then
  mark_nodered_managed
fi

# ========================
# Final Status
# ========================
if [ "$DEPLOYMENT_SUCCESSFUL" = "true" ]; then
  bashio::log.info ""
bashio::log.info "================================================"
  bashio::log.info "🚐 RV Link System Fully Operational"
  bashio::log.info "================================================"
  bashio::log.info ""
  bashio::log.info "   Components installed:"
  bashio::log.info "   ✅ Mosquitto MQTT Broker"
  bashio::log.info "   ✅ CAN-MQTT Bridge"
  bashio::log.info "   ✅ Node-RED Automation"
  bashio::log.info ""
  bashio::log.info "🚐 See the Overview Dashboard for new RV Link entities"
  bashio::log.info "🚐 Visit https://rvlink.app for more information"
  bashio::log.info ""
  bashio::log.info "   ℹ️  RV Link setup complete. The addon will now exit."
  bashio::log.info "   ℹ️  Restart this addon only when updating RV Link."
  bashio::log.info ""
  exit 0
else
  bashio::log.info ""
  bashio::log.info "================================================"
  bashio::log.error "❌ RV Link Installation FAILED"
  bashio::log.info "================================================"
  bashio::log.info ""
  bashio::log.error "   Critical component failed to start properly."
  bashio::log.error "   Please check the logs above for details."
  bashio::log.error "   You may need to manually configure Node-RED."
  bashio::log.info ""
  exit 1
fi

# Setup complete, addon exits cleanly
