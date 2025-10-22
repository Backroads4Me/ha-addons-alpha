#!/usr/bin/env bash
set -e

# ============================================
# NODE-RED PROJECT AUTOMATION SCRIPT
# ============================================

# Environment variables are provided by the Supervisor
AUTH_HEADER="Authorization: Bearer $SUPERVISOR_TOKEN"
SUPERVISOR="http://supervisor"

echo "[Node-RED Setup] 🚀 Locating Node-RED add-on..."
NODE_RED_ADDON=$(curl -s -H "$AUTH_HEADER" "$SUPERVISOR/addons" | jq -r '.data.addons[] | select(.slug | endswith("nodered")) | .slug')

if [ -z "$NODE_RED_ADDON" ]; then
    echo "[Node-RED Setup] ❌ ERROR: Could not find Node-RED add-on slug. Exiting."
    exit 1
fi
echo "[Node-RED Setup] ✅ Found Node-RED slug: $NODE_RED_ADDON"

PROJECT_REPO="https://github.com/Backroads4Me/rv-link"
PROJECT_DIR="/share/node-red-project"
PROJECT_NAME="rv-link"

echo "[Node-RED Setup] 🚀 Starting setup..."

# ?--------------
# 1. Enable Node-RED Projects Mode
# ?--------------
echo "[Node-RED Setup] 1. Enabling Node-RED project mode..."
curl -s -X POST -H "$AUTH_HEADER" \
 -d '{"options": {"projects": {"enabled": true, "path": "/share/node-red-project"}}}' \
 "$SUPERVISOR/addons/$NODE_RED_ADDON/options"

echo "[Node-RED Setup] ✅ Project mode enabled."

# ?--------------
# 2. Restart Node-RED Add-on to apply settings
# ?--------------
echo "[Node-RED Setup] 2. Restarting Node-RED to apply settings..."
curl -s -X POST -H "$AUTH_HEADER" \
 "$SUPERVISOR/addons/$NODE_RED_ADDON/restart"

echo "[Node-RED Setup] ⏳ Waiting for Node-RED to restart (30 seconds)..."
sleep 30

# ?--------------
# 3. Stage Node-RED Project Files
# ?--------------
echo "[Node-RED Setup] 3. Staging project files from $PROJECT_REPO..."

mkdir -p "$PROJECT_DIR"

if [ -d "$PROJECT_DIR/.git" ]; then
  echo "[Node-RED Setup] -> Project directory exists, pulling latest changes..."
  cd "$PROJECT_DIR"
  git pull origin main
else
  echo "[Node-RED Setup] -> Cloning new project..."
  git clone "$PROJECT_REPO" "$PROJECT_DIR"
fi

cd "$PROJECT_DIR"
echo "[Node-RED Setup] ✅ Project files staged in $PROJECT_DIR."

# ?--------------
# 4. Detect Node-RED Port
# ?--------------
echo "[Node-RED Setup] 4. Detecting Node-RED API port..."
NODE_RED_PORT=$(curl -s -H "$AUTH_HEADER" \
 "$SUPERVISOR/addons/$NODE_RED_ADDON/info" | jq -r '.data.network | to_entries[] | select(.value == 1880) | .key | split("/")[0]')

if [ -z "$NODE_RED_PORT" ] || [ "$NODE_RED_PORT" == "null" ]; then
    NODE_RED_PORT=1880 # Fallback to default
    echo "[Node-RED Setup] ⚠️ Could not detect port, falling back to default: $NODE_RED_PORT"
else
    echo "[Node-RED Setup] ✅ Detected Node-RED port: $NODE_RED_PORT"
fi

NODE_RED_HOST="addon_${NODE_RED_ADDON}"
NODE_RED_API_URL="http://${NODE_RED_HOST}:${NODE_RED_PORT}"

# ?--------------
# 5. Verify Node-RED Admin API
# ?--------------
echo "[Node-RED Setup] 5. Verifying Node-RED Admin API at $NODE_RED_API_URL..."

# Try to reach API but do not fail addon if unavailable
NR_API_AVAILABLE=false
for attempt in {1..6}; do
    if curl -s -f "$NODE_RED_API_URL/settings" > /dev/null; then
        NR_API_AVAILABLE=true
        break
    fi
    echo "[Node-RED Setup] -> API not ready (attempt $attempt/6), retrying in 10 seconds..."
    sleep 10
done

if [ "$NR_API_AVAILABLE" = true ]; then
    echo "[Node-RED Setup] ✅ Node-RED API is responsive."
else
    echo "[Node-RED Setup] ⚠️ Node-RED Admin API not reachable. Project activation will be skipped."
fi

# ?--------------
# 6. Configure and Activate Project
# ?--------------
echo "[Node-RED Setup] 6. Activating project '$PROJECT_NAME'..."

if [ "$NR_API_AVAILABLE" = true ]; then
  # Create the project if it doesn't exist
  curl -s -X POST "$NODE_RED_API_URL/projects" \
    -H "Content-Type: application/json" \
    -d '{
  "name": "'$PROJECT_NAME'",
  "credentialSecret": "rv-link-secret"
}'

  # Activate the project
  curl -s -X PUT "$NODE_RED_API_URL/projects/$PROJECT_NAME" \
    -H "Content-Type: application/json" \
    -d '{"active": true}'

  echo "[Node-RED Setup] ✅ Project '$PROJECT_NAME' activated."
else
  echo "[Node-RED Setup] ⚠️ Skipping project activation due to unavailable Admin API."
fi

# ?--------------
# 7. Final Restart of Node-RED
# ?--------------
echo "[Node-RED Setup] 7. Performing final restart of Node-RED..."
curl -s -X POST -H "$AUTH_HEADER" \
 "$SUPERVISOR/addons/$NODE_RED_ADDON/restart"

echo "[Node-RED Setup] ✅ Node-RED setup complete!"