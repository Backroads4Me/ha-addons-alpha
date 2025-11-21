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
ADDON_VERSION="0.6.40"

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
      # Use -u for authentication
      if [ "$DEBUG_LOGGING" = "true" ]; then
          if output=$(curl -v -sS -f -u "$MQTT_USER:$MQTT_PASS" -m 2 "$url" 2>&1); then
            bashio::log.info "   ✅ Node-RED API is ready at $url"
            echo "$host" > /tmp/nodered_host
            return 0
          fi
      else
          if output=$(curl -sS -f -u "$MQTT_USER:$MQTT_PASS" -m 2 "$url" 2>&1); then
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
  local flows=$(curl -s -f -u "$MQTT_USER:$MQTT_PASS" -m 5 "${base_url}/flows" 2>/dev/null)
  
  if [ -z "$flows" ] || ! echo "$flows" | jq -e '.' >/dev/null 2>&1; then
    bashio::log.error "   ❌ Failed to fetch flows from Node-RED at ${base_url}"
    return 1
  fi
  
  # Deploy the flows (POST back to trigger encryption of credentials)
  local result=$(curl -s -f -u "$MQTT_USER:$MQTT_PASS" -m 5 -X POST \
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

# ... (skipping unchanged parts) ...

# Configure Node-RED
NR_INFO=$(api_call GET "/addons/$SLUG_NODERED/info")
NR_OPTIONS=$(echo "$NR_INFO" | jq '.data.options')
SECRET=$(echo "$NR_OPTIONS" | jq -r '.credential_secret // empty')

# Init command - Point Node-RED to project directory instead of copying flows
# This keeps all files in one place and avoids duplication
# Removed the sed command for adminAuth as we are now configuring users directly
SETTINGS_INIT_CMD="mkdir -p /config/projects/rv-link-node-red; cp -rf /share/.rv-link/. /config/projects/rv-link-node-red/; rm -f /config/projects/rv-link-node-red/flows_cred.json; jq --arg user '$MQTT_USER' --arg pass '$MQTT_PASS' 'map(if .id == \"80727e60a251c36c\" then . + {credentials: {user: \$user, password: \$pass}} else . end)' /config/projects/rv-link-node-red/flows.json > /config/projects/rv-link-node-red/flows.json.tmp && mv /config/projects/rv-link-node-red/flows.json.tmp /config/projects/rv-link-node-red/flows.json; if [ -f /config/settings.js ]; then sed -i \"s|flowFile:.*|flowFile: 'projects/rv-link-node-red/flows.json',|\" /config/settings.js; grep -q 'contextStorage:' /config/settings.js || sed -i 's|module.exports.*=.*{|module.exports = {\\n    contextStorage: { default: \"memory\", memory: { module: \"memory\" }, file: { module: \"localfilesystem\" } },|' /config/settings.js; fi; echo 'Node-RED configuration complete'"

NEEDS_RESTART=false

if [ -z "$SECRET" ]; then
  bashio::log.info "   ⚠️  No credential_secret found. Generating one..."
  NEW_SECRET=$(openssl rand -hex 16)
  # Add user configuration
  NEW_OPTIONS=$(echo "$NR_OPTIONS" | jq --arg secret "$NEW_SECRET" --arg initcmd "$SETTINGS_INIT_CMD" --arg user "$MQTT_USER" --arg pass "$MQTT_PASS" '. + {"credential_secret": $secret, "ssl": false, "init_commands": [$initcmd], "users": [{"username": $user, "password": $pass, "permissions": "*"}]}')
  set_options "$SLUG_NODERED" "$NEW_OPTIONS" || exit 1
  NEEDS_RESTART=true
else
  CURRENT_INIT_CMD=$(echo "$NR_OPTIONS" | jq -r '.init_commands[0] // empty')
  # Check if user is configured
  CURRENT_USER=$(echo "$NR_OPTIONS" | jq -r --arg user "$MQTT_USER" '.users[] | select(.username == $user) | .username')
  
  if [ "$CURRENT_INIT_CMD" != "$SETTINGS_INIT_CMD" ] || [ -z "$CURRENT_USER" ]; then
    bashio::log.info "   > Updating Node-RED configuration (init commands / users)..."
    # Update init commands and ensure user exists
    NEW_OPTIONS=$(echo "$NR_OPTIONS" | jq --arg initcmd "$SETTINGS_INIT_CMD" --arg user "$MQTT_USER" --arg pass "$MQTT_PASS" '
      . + {"init_commands": [$initcmd]} |
      .users = (.users // []) |
      .users |= (map(select(.username != $user)) + [{"username": $user, "password": $pass, "permissions": "*"}])
    ')
    set_options "$SLUG_NODERED" "$NEW_OPTIONS" || exit 1
    NEEDS_RESTART=true
  else
    bashio::log.info "   ✅ Node-RED configuration is up to date"
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
