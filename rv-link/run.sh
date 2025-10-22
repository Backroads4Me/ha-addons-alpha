#!/usr/bin/env bash
set -e

echo "🔧 Starting RV Link Meta Installer..."
echo "Supervisor API URL: $SUPERVISOR_API"
echo "Using token: ${SUPERVISOR_TOKEN:0:8}..."

SUPERVISOR="http://supervisor"
AUTH_HEADER="Authorization: Bearer $SUPERVISOR_TOKEN"

# === Install repositories and add-ons ===

echo "📦 Installing required add-on repositories..."

# Add Backroads4Me add-on repo for CAN MQTT Bridge
curl -s -X POST -H "$AUTH_HEADER" \
  -d '{"repository":"https://github.com/Backroads4Me/ha-addons"}' \
  "$SUPERVISOR/store/repositories" || echo "⚠️  Could not add Backroads4Me repo, may already exist."

# Add Node-RED repo (Hass.io Community)
curl -s -X POST -H "$AUTH_HEADER" \
  -d '{"repository":"https://github.com/hassio-addons/repository"}' \
  "$SUPERVISOR/store/repositories" || echo "⚠️  Could not add hassio-addons repo, may already exist."

echo "✅ Repositories added. Waiting for store to refresh..."

sleep 10

# === Install add-ons ===

echo "🚀 Installing core add-ons..."

# Function to find and install an addon
install_addon() {
  local addon_slug_suffix=$1
  local addon_name=$2
  local is_core=${3:-false}
  local addon_full_slug=""

  echo "➡️ Locating $addon_name..."

  if [ "$is_core" = true ]; then
    addon_full_slug=$addon_slug_suffix
  else
    # Dynamically find the full slug from the store
    addon_full_slug=$(curl -s -H "$AUTH_HEADER" "$SUPERVISOR/store/addons" | jq -r --arg suffix "$addon_slug_suffix" '.data.addons[] | select(.slug | endswith($suffix)) | .slug')
  fi

  if [ -z "$addon_full_slug" ]; then
    echo "❌ ERROR: Could not find slug for $addon_name. Skipping installation."
    return
  fi

  echo "➡️ Installing $addon_name ($addon_full_slug)..."

  # Check if add-on is already installed
  if curl -s -H "$AUTH_HEADER" "$SUPERVISOR/addons/$addon_full_slug/info" | jq -e '.data.version' > /dev/null; then
    echo "✅ $addon_name is already installed."
  else
    # Install the add-on
    install_result=$(curl -s -X POST -H "$AUTH_HEADER" "$SUPERVISOR/addons/$addon_full_slug/install")
    if [[ $(echo "$install_result" | jq -r '.result') == "ok" ]]; then
      echo "✅ Installation started for $addon_name."
    else
      echo "❌ Failed to start installation for $addon_name: $(echo "$install_result" | jq -r '.message')"
    fi
  fi
}

# Install Mosquitto (core)
install_addon "core_mosquitto" "Mosquitto MQTT Broker" true

# Install Node-RED (community)
install_addon "nodered" "Node-RED"

# Install CAN MQTT Bridge (custom)
install_addon "can-mqtt-bridge" "CAN MQTT Bridge"

sleep 30

# === Install Lovelace cards ===

echo "🎨 Installing Lovelace custom cards..."

WWW_PATH="/config/www/community"
mkdir -p "$WWW_PATH"

# Mushroom Cards
if [ -d "$WWW_PATH/lovelace-mushroom" ]; then
  echo "✅ Mushroom cards already exist."
else
  echo "➡️ Installing Mushroom cards..."
  git clone https://github.com/piitaya/lovelace-mushroom "$WWW_PATH/lovelace-mushroom" || echo "❌ Failed to clone Mushroom cards."
fi

# Power Flow Card Plus
if [ -d "$WWW_PATH/power-flow-card-plus" ]; then
  echo "✅ Power Flow Card Plus already exists."
else
  echo "➡️ Installing Power Flow Card Plus..."
  git clone https://github.com/flixlix/power-flow-card-plus "$WWW_PATH/power-flow-card-plus" || echo "❌ Failed to clone Power Flow Card Plus."
fi

echo "✅ Lovelace cards installation process finished."

# === Install HA Victron MQTT integration ===

echo "⚙️ Installing HA Victron MQTT integration..."
CUSTOM_COMPONENTS="/config/custom_components"
mkdir -p "$CUSTOM_COMPONENTS"

if [ -d "$CUSTOM_COMPONENTS/ha-victron-mqtt" ]; then
  echo "✅ HA Victron MQTT integration already exists."
else
  echo "➡️ Installing HA Victron MQTT integration..."
  git clone https://github.com/tomer-w/ha-victron-mqtt "$CUSTOM_COMPONENTS/ha-victron-mqtt" || echo "❌ Failed to clone HA Victron MQTT."
fi

echo "✅ HA Victron MQTT installation process finished."

# === Configure Node-RED Project ===
echo "🚀 Starting Node-RED project setup..."
/setup-node-red.sh

# === Final summary ===
echo "🎉 Installation and setup tasks complete!"
echo "Please restart Home Assistant to load new integrations and custom cards."