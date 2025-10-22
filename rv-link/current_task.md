# Home Assistant Meta-Installer Add-on

This document outlines how to create a **custom Home Assistant add-on** that automatically installs and configures several other add-ons and integrations, including Node-RED, Mosquitto, CAN MQTT Bridge, and various Lovelace custom cards.

---

## 🧩 Overview

This add-on acts as a **“meta-installer”** that:

- Uses the **Home Assistant Supervisor API** to install add-ons such as Node-RED, Mosquitto, and custom repositories.
- Clones or downloads Lovelace custom cards to the `www/community` directory.
- Optionally deploys preconfigured Node-RED flows or MQTT configurations.

---

## 🧱 Add-ons and Integrations Installed

| Category      | Name                 | Repository                                                                                        |
| ------------- | -------------------- | ------------------------------------------------------------------------------------------------- |
| Custom Add-on | CAN MQTT Bridge      | [Backroads4Me/ha-addons](https://github.com/Backroads4Me/ha-addons/blob/main/can-mqtt-bridge)     |
| Lovelace Card | Mushroom Cards       | [piitaya/lovelace-mushroom](https://github.com/piitaya/lovelace-mushroom)                         |
| Lovelace Card | Power Flow Card Plus | [flixlix/power-flow-card-plus](https://github.com/flixlix/power-flow-card-plus)                   |
| Integration   | HA Victron MQTT      | [tomer-w/ha-victron-mqtt](https://github.com/tomer-w/ha-victron-mqtt)                             |
| Add-on        | Node-RED             | [hassio-addons/addon-node-red](https://github.com/hassio-addons/addon-node-red)                   |
| Add-on        | Mosquitto Broker     | [home-assistant/addons/mosquitto](https://github.com/home-assistant/addons/tree/master/mosquitto) |

---

## 🧰 Step-by-Step Instructions

### 1. Create the Add-on Directory

In your Home Assistant configuration folder (typically `/addons/local`):

```bash
mkdir -p /addons/local/meta-installer
cd /addons/local/meta-installer
2. Create config.yaml
yaml
Copy code
name: "Home Assistant Meta-Installer"
version: "1.0.0"
slug: "meta_installer"
description: "Installs Node-RED, Mosquitto, CAN MQTT Bridge, and Lovelace custom cards automatically."
arch:
  - aarch64
  - amd64
startup: once
boot: manual
init: false
hassio_api: true
homeassistant_api: true
privileged:
  - NET_ADMIN
options: {}
schema: {}
3. Create Dockerfile
Dockerfile
Copy code
ARG BUILD_FROM=ghcr.io/home-assistant/amd64-base:latest
FROM $BUILD_FROM

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

RUN apk add --no-cache git curl jq bash

COPY run.sh /run.sh
RUN chmod +x /run.sh

CMD ["/run.sh"]
4. Create run.sh
This script performs all installation tasks via the Supervisor API and direct downloads.

bash
Copy code
#!/usr/bin/env bash
set -e

echo "🔧 Starting Home Assistant Meta Installer..."
echo "Supervisor API URL: $SUPERVISOR_API"
echo "Using token: ${SUPERVISOR_TOKEN:0:8}..."

SUPERVISOR="http://supervisor"
AUTH_HEADER="Authorization: Bearer $SUPERVISOR_TOKEN"

# === Install repositories and add-ons ===

echo "📦 Installing required add-on repositories..."

# Add Backroads4Me add-on repo
curl -s -X POST -H "$AUTH_HEADER" \
  -d '{"repository":"https://github.com/Backroads4Me/ha-addons"}' \
  $SUPERVISOR/store/repositories || true

# Add official HA add-on repo (already added by default)
# Add Node-RED repo (Hass.io Community)
curl -s -X POST -H "$AUTH_HEADER" \
  -d '{"repository":"https://github.com/hassio-addons/repository"}' \
  $SUPERVISOR/store/repositories || true

echo "✅ Repositories added."

sleep 5

# === Install add-ons ===

echo "🚀 Installing add-ons..."

declare -A ADDONS
ADDONS=(
  ["a0d7b954_nodered"]="Node-RED"
  ["core_mosquitto"]="Mosquitto MQTT Broker"
  ["local_can-mqtt-bridge"]="CAN MQTT Bridge"
)

for ADDON in "${!ADDONS[@]}"; do
  echo "➡️ Installing ${ADDONS[$ADDON]}..."
  curl -s -X POST -H "$AUTH_HEADER" "$SUPERVISOR/addons/$ADDON/install" || echo "⚠️ Skipped $ADDON"
done

echo "✅ Add-on installation complete."

sleep 10

# === Install Lovelace cards ===

echo "🎨 Installing Lovelace custom cards..."

WWW_PATH="/config/www/community"
mkdir -p "$WWW_PATH"

cd "$WWW_PATH"

git clone https://github.com/piitaya/lovelace-mushroom || echo "Mushroom exists"
git clone https://github.com/flixlix/power-flow-card-plus || echo "Power Flow Card Plus exists"

echo "✅ Lovelace cards installed."

# === Install HA Victron MQTT integration ===

echo "⚙️ Installing HA Victron MQTT integration..."
CUSTOM_COMPONENTS="/config/custom_components"
mkdir -p "$CUSTOM_COMPONENTS"
cd "$CUSTOM_COMPONENTS"

git clone https://github.com/tomer-w/ha-victron-mqtt || echo "Victron MQTT exists"

echo "✅ HA Victron MQTT installed."

# === Final summary ===
echo "🎉 Installation tasks complete!"
echo "Restart Home Assistant to load new integrations and custom cards."
5. Permissions
Ensure all files are executable and readable:

bash
Copy code
chmod +x run.sh
6. Build and Install
In Home Assistant:

Go to Settings → Add-ons → Add-on Store → ⋮ → Repositories
Add this local repository (if not already detected).

Refresh and install Home Assistant Meta-Installer.

Start it manually once.

7. Verify Installation
After it runs:

Node-RED and Mosquitto should appear under Add-ons.

CAN MQTT Bridge should be installed from your custom repo.

Custom Lovelace cards will be located in /config/www/community/.

ha-victron-mqtt will be under /config/custom_components/.

Restart Home Assistant Core to activate the new frontend cards and integrations.

```

# ============================================

# NODE-RED PROJECT AUTOMATION STEPS

# ============================================

# Purpose:

# Use from a Home Assistant add-on (meta-installer) to:

# 1. Enable Node-RED project mode

# 2. Clone a Node-RED project (with flows + static files) into /share

# 3. Restart Node-RED

# 4. Use the Node-RED API to switch to that project

# ============================================

# ---------------

# 1. Environment setup

# ---------------

# Supervisor environment variables are injected automatically:

# SUPERVISOR_TOKEN = Bearer token for Supervisor API access

# SUPERVISOR_API = http://supervisor

# HOMEASSISTANT_API = http://supervisor/core/api

# No manual setup required.

# ---------------

# 2. Enable Node-RED Projects Mode

# ---------------

# Use the Supervisor API to enable "Projects" and set the shared folder path.

# This lets Node-RED access /share/node-red-project as its workspace.

curl -s -X POST -H "Authorization: Bearer $SUPERVISOR_TOKEN" \
 -d '{"options": {"projects": {"enabled": true, "path": "/share/node-red-project"}}}' \
 http://supervisor/addons/a0d7b954_nodered/options

# ---------------

# 3. Restart Node-RED Add-on

# ---------------

# Required after changing configuration.

curl -s -X POST -H "Authorization: Bearer $SUPERVISOR_TOKEN" \
 http://supervisor/addons/a0d7b954_nodered/restart

# Wait 15–20 seconds for Node-RED to fully start.

sleep 20

# ---------------

# 4. Stage Node-RED Project Files

# ---------------

# Clone or copy your Node-RED project (including static assets) into /share.

# This is accessible to Node-RED when project mode is enabled.

mkdir -p /share/node-red-project
cd /share/node-red-project

# Example using git:

git clone https://github.com/YourUser/your-node-red-project .

# Alternatively, copy from a local file:

# cp -r /tmp/my_project/\* /share/node-red-project/

# ---------------

# 5. Detect Node-RED Port

# ---------------

# Retrieve the host port Node-RED is listening on via Supervisor API.

# Typically 1880 by default.

NODE_RED_PORT=$(curl -s -H "Authorization: Bearer $SUPERVISOR_TOKEN" \
 http://supervisor/addons/a0d7b954_nodered/info | jq -r '.data.network[0].host_port')

echo "Detected Node-RED port: $NODE_RED_PORT"

# ---------------

# 6. Verify Node-RED Admin API

# ---------------

# Check if Node-RED is responding.

curl -s http://127.0.0.1:${NODE_RED_PORT}/projects || echo "Node-RED API not reachable"

# ---------------

# 7. Configure and Activate Project

# ---------------

# If you cloned a project folder (e.g., "my_project"), tell Node-RED to activate it.

curl -s -X PUT "http://127.0.0.1:${NODE_RED_PORT}/projects" \
 -H "Content-Type: application/json" \
 -d '{"activeProject": "my_project"}'

# If the project doesn’t yet exist, you can create it explicitly:

curl -s -X POST "http://127.0.0.1:${NODE_RED_PORT}/projects" \
 -H "Content-Type: application/json" \
 -d '{
"name": "my_project",
"metadata": { "description": "My custom Node-RED automation project" },
"settings": { "activeProject": "my_project" }
}'

# ---------------

# 8. (Optional) Replace or Import Flows

# ---------------

# If you want to push flow definitions from a JSON file:

curl -s -X POST "http://127.0.0.1:${NODE_RED_PORT}/flows" \
 -H "Content-Type: application/json" \
 -d @"$SHARE_PATH/node-red-project/flows.json"

# ---------------

# 9. Restart Node-RED Again (Optional)

# ---------------

# Ensures that project settings and flows are fully loaded.

curl -s -X POST -H "Authorization: Bearer $SUPERVISOR_TOKEN" \
 http://supervisor/addons/a0d7b954_nodered/restart

# ============================================

# Result:

# - Node-RED is using /share/node-red-project as its active workspace.

# - All flows and static assets are available inside the Node-RED add-on.

# - The project can be updated by re-cloning or pulling new changes.

# ============================================

# ---------------

# 10. Update Process (for future revisions)

# ---------------

# To update your Node-RED project automatically later:

cd /share/node-red-project
git pull origin main
curl -s -X POST -H "Authorization: Bearer $SUPERVISOR_TOKEN" \
 http://supervisor/addons/a0d7b954_nodered/restart
