#!/usr/bin/env bash
set -e

echo "================================================"
echo "🚀 RV Link - Node-RED Project Deployer"
echo "================================================"
echo ""

# Environment Information (for troubleshooting)
echo "🔍 Environment Information:"
echo "   Alpine version: $(cat /etc/alpine-release 2>/dev/null || echo "unknown")"
echo "   Git version: $(git --version 2>&1)"
echo "   Bash version: $BASH_VERSION"
echo "   Current user: $(whoami)"
echo "   Working directory: $(pwd)"
echo "   Supervisor token present: $([ -n "$SUPERVISOR_TOKEN" ] && echo "yes (${#SUPERVISOR_TOKEN} chars)" || echo "NO - THIS WILL FAIL")"
echo ""

# Configuration
SUPERVISOR="http://supervisor"
AUTH_HEADER="Authorization: Bearer $SUPERVISOR_TOKEN"
PROJECT_DIR="/share/node-red-projects"
CONFIG_FILE="/data/options.json"

# Project settings (hardcoded)
PROJECT_REPO="https://github.com/Backroads4Me/rv-link-node-red"
PROJECT_NAME="rv-link"

# Read user options
echo "📋 Reading configuration from $CONFIG_FILE..."
if [ ! -f "$CONFIG_FILE" ]; then
  echo "   ⚠️  WARNING: Config file not found at $CONFIG_FILE"
  FORCE_UPDATE="true"
else
  echo "   ✅ Config file found"
  FORCE_UPDATE=$(jq -r '.force_update // true' "$CONFIG_FILE")
fi

echo ""
echo "📋 Configuration:"
echo "   Project: $PROJECT_NAME"
echo "   Repository: $PROJECT_REPO"
echo "   Force Update: $FORCE_UPDATE"
echo "   Project Directory: $PROJECT_DIR"
echo ""

# Helper function for Supervisor API calls
api_call() {
  local method=$1
  local endpoint=$2
  local data=$3

  if [ -n "$data" ]; then
    curl -s -X "$method" -H "$AUTH_HEADER" -H "Content-Type: application/json" \
      -d "$data" "$SUPERVISOR$endpoint"
  else
    curl -s -X "$method" -H "$AUTH_HEADER" "$SUPERVISOR$endpoint"
  fi
}

# Step 1: Find Node-RED addon
echo "🔍 Step 1: Locating Node-RED addon..."
echo "   > Querying Supervisor API for installed addons..."
ADDONS_RESPONSE=$(api_call GET "/addons")
echo "   > Searching for addon with name='Node-RED'..."
NODE_RED_SLUG=$(echo "$ADDONS_RESPONSE" | jq -r '.data.addons[] | select(.name == "Node-RED") | .slug' | head -n1)

if [ -z "$NODE_RED_SLUG" ]; then
  echo "❌ ERROR: Node-RED addon not found!"
  echo ""
  echo "📊 Diagnostic Information:"
  echo "   Installed addons:"
  echo "$ADDONS_RESPONSE" | jq -r '.data.addons[]? | "      - \(.name) (\(.slug))"' 2>/dev/null || echo "      Failed to parse addon list"
  echo ""
  echo "Please install Node-RED before running this addon:"
  echo "   Settings → Add-ons → Add-on Store"
  echo "   Search for 'Node-RED' and install it"
  echo ""
  exit 1
fi

echo "   ✅ Found Node-RED: $NODE_RED_SLUG"
echo ""

# Step 2: Check if Node-RED is installed (has version)
echo "🔍 Step 2: Checking Node-RED installation..."
echo "   > Querying addon info for $NODE_RED_SLUG..."
NODE_RED_INFO=$(api_call GET "/addons/$NODE_RED_SLUG/info")
NODE_RED_VERSION=$(echo "$NODE_RED_INFO" | jq -r '.data.version // empty')
NODE_RED_STATE=$(echo "$NODE_RED_INFO" | jq -r '.data.state // "unknown"')

if [ -z "$NODE_RED_VERSION" ]; then
  echo "❌ ERROR: Node-RED is not installed!"
  echo ""
  echo "📊 Diagnostic Information:"
  echo "   Addon slug: $NODE_RED_SLUG"
  echo "   Addon state: $NODE_RED_STATE"
  echo "   Please install Node-RED from the Add-on Store first."
  echo ""
  exit 1
fi

echo "   ✅ Node-RED v$NODE_RED_VERSION is installed"
echo "   📊 State: $NODE_RED_STATE"
echo ""

# Step 3: Enable Node-RED project mode
echo "⚙️  Step 3: Configuring Node-RED project mode..."
echo "   > Sending configuration: {\"options\": {\"projects\": true}}"
CONFIG_RESULT=$(api_call POST "/addons/$NODE_RED_SLUG/options" "{\"options\": {\"projects\": true}}")
echo "   > API Response: $CONFIG_RESULT"

if echo "$CONFIG_RESULT" | jq -e '.result == "ok"' >/dev/null 2>&1; then
  echo "   ✅ Project mode enabled"
else
  echo "   ⚠️  Could not enable project mode: $(echo "$CONFIG_RESULT" | jq -r '.message // "Unknown error"')"
  echo "   Continuing anyway..."
fi
echo ""

# Step 3.5: Configure Context Storage (One-time setup)
echo "⚙️  Step 3.5: Configuring context storage..."

# Determine Node-RED config directory based on detected slug
NODERED_CONFIG_DIR="/addon_configs/${NODE_RED_SLUG}"
SETTINGS_FILE="$NODERED_CONFIG_DIR/settings.js"

echo "   > Config directory: $NODERED_CONFIG_DIR"
echo "   > Settings file: $SETTINGS_FILE"
echo "   > Settings file exists: $([ -f "$SETTINGS_FILE" ] && echo "yes" || echo "NO")"

if [ ! -f "$SETTINGS_FILE" ]; then
  echo "   ⚠️  Settings file not found at $SETTINGS_FILE"
  echo "   📊 Directory contents:"
  ls -la "$NODERED_CONFIG_DIR" 2>&1 | sed 's/^/      /' || echo "      Failed to list directory"
  echo "   Skipping context storage configuration"
else
  echo "   ✅ Settings file found"
  echo "   📊 File size: $(stat -c%s "$SETTINGS_FILE" 2>/dev/null || stat -f%z "$SETTINGS_FILE") bytes"
  echo "   📊 Line count: $(wc -l < "$SETTINGS_FILE") lines"

  # Check if context storage is already configured (only configure once)
  if grep -q "contextStorage" "$SETTINGS_FILE"; then
    echo "   ✅ Context storage already configured (skipping)"
  else
    echo "   📝 Initial setup: Adding context storage configuration..."

    # Backup original settings before first modification
    if [ ! -f "$SETTINGS_FILE.rvlink-backup" ]; then
      echo "   📋 Creating backup of original settings..."
      cp "$SETTINGS_FILE" "$SETTINGS_FILE.rvlink-backup"
      echo "   ✅ Backup created: ${SETTINGS_FILE}.rvlink-backup"
    fi

    # Create temporary file with context storage config
    cat > /tmp/context_storage.js << 'EOF'

    // RV Link: Context Storage Configuration
    contextStorage: {
        default: "memoryOnly",
        memoryOnly: {
            module: 'memory'
        },
        file: {
            module: 'localfilesystem'
        }
    },
EOF

    # Insert the context storage config into settings.js
    # HAOS-compatible approach: Use head instead of sed for portability
    echo "   > Modifying settings.js file..."
    echo "   > Step 1: Creating temp file without last line..."
    head -n -1 "$SETTINGS_FILE" > "${SETTINGS_FILE}.tmp"
    echo "   > Step 2: Appending context storage config..."
    cat /tmp/context_storage.js >> "${SETTINGS_FILE}.tmp"
    echo "   > Step 3: Adding closing brace..."
    echo "}" >> "${SETTINGS_FILE}.tmp"
    echo "   > Step 4: Replacing original file..."
    mv "${SETTINGS_FILE}.tmp" "$SETTINGS_FILE"

    rm /tmp/context_storage.js

    echo "   ✅ Context storage configured (memoryOnly + file)"
    echo "   📊 New file size: $(stat -c%s "$SETTINGS_FILE" 2>/dev/null || stat -f%z "$SETTINGS_FILE") bytes"
    echo "   📊 New line count: $(wc -l < "$SETTINGS_FILE") lines"
    echo "   ℹ️  This is a one-time configuration"
  fi
fi
echo ""

# Step 4: Restart Node-RED to apply configuration
echo "🔄 Step 4: Restarting Node-RED to apply settings..."
echo "   > Sending restart request to $NODE_RED_SLUG..."
RESTART_RESULT=$(api_call POST "/addons/$NODE_RED_SLUG/restart" "")
echo "   > API Response: $RESTART_RESULT"
echo "   ⏳ Waiting for Node-RED to start (30 seconds)..."
sleep 30
echo "   ✅ Node-RED restarted"
echo ""

# Step 5: Deploy Node-RED project
echo "📦 Step 5: Deploying Node-RED project..."
echo "   > Creating project directory: $PROJECT_DIR"
mkdir -p "$PROJECT_DIR"
cd "$PROJECT_DIR"
echo "   > Changed to directory: $(pwd)"

PROJECT_PATH="$PROJECT_DIR/$PROJECT_NAME"
echo "   > Project path: $PROJECT_PATH"
echo "   > Project exists: $([ -d "$PROJECT_PATH/.git" ] && echo "yes" || echo "no")"

if [ -d "$PROJECT_PATH/.git" ]; then
  echo "   ℹ️  Project already exists"

  cd "$PROJECT_PATH"
  echo "   > Changed to: $(pwd)"

  # Detect the default branch
  echo "   > Detecting current branch..."
  DEFAULT_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "main")
  echo "   > Current branch: $DEFAULT_BRANCH"

  # Check for local changes
  echo "   > Checking for local modifications..."
  if ! git diff-index --quiet HEAD -- 2>/dev/null; then
    echo "   ⚠️  Local changes detected:"
    git status --short 2>&1 | sed 's/^/      /'

    if [ "$FORCE_UPDATE" = "true" ]; then
      echo "   ⚠️  Force update enabled - discarding local changes"
      echo "   > git fetch origin"
      git fetch origin 2>&1 | sed 's/^/      /'
      echo "   > git reset --hard origin/$DEFAULT_BRANCH"
      git reset --hard origin/$DEFAULT_BRANCH 2>&1 | sed 's/^/      /'
      echo "   ✅ Project updated (local changes discarded)"
    else
      echo "   ⚠️  Force update disabled - preserving local changes"
      echo "   💡 Set 'force_update: true' in addon config to overwrite local changes"
      echo ""
      echo "✅ Deployment complete (existing project preserved)"
      exit 0
    fi
  else
    echo "   ✅ No local changes detected"
    echo "   📥 Pulling latest changes from $DEFAULT_BRANCH..."
    echo "   > git pull origin $DEFAULT_BRANCH"
    git pull origin $DEFAULT_BRANCH 2>&1 | sed 's/^/      /'
    echo "   ✅ Project updated"
  fi
else
  echo "   📥 Cloning project repository..."
  echo "   > git clone $PROJECT_REPO $PROJECT_PATH"
  git clone "$PROJECT_REPO" "$PROJECT_PATH" 2>&1 | sed 's/^/      /'
  cd "$PROJECT_PATH"
  echo "   > Changed to: $(pwd)"

  # Detect the default branch after cloning
  echo "   > Detecting default branch..."
  DEFAULT_BRANCH=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@')
  if [ -z "$DEFAULT_BRANCH" ]; then
    DEFAULT_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "main")
  fi
  echo "   > Default branch: $DEFAULT_BRANCH"

  # Explicitly checkout the default branch (HAOS compatibility)
  echo "   > git checkout $DEFAULT_BRANCH"
  git checkout "$DEFAULT_BRANCH" 2>&1 | sed 's/^/      /' || true

  echo "   ✅ Project cloned (branch: $DEFAULT_BRANCH)"
fi
echo ""

# Step 6: Verify project structure
echo "🔍 Step 6: Verifying project structure..."
if [ -f "$PROJECT_PATH/package.json" ]; then
  echo "   ✅ Project structure looks good"
else
  echo "   ⚠️  Warning: package.json not found"
  echo "   Project may need manual configuration in Node-RED"
fi
echo ""

# Step 7: Final restart of Node-RED
echo "🔄 Step 7: Final Node-RED restart..."
echo "   > Sending restart request to $NODE_RED_SLUG..."
RESTART_RESULT=$(api_call POST "/addons/$NODE_RED_SLUG/restart" "")
echo "   > API Response: $RESTART_RESULT"
echo "   ✅ Node-RED restarted"
echo ""

# Success summary
echo "================================================"
echo "🎉 RV Link deployment complete!"
echo "================================================"
echo ""
echo "📋 What was done:"
echo "   ✅ Node-RED project mode enabled"
echo "   ✅ Context storage configured (memoryOnly + file)"
echo "   ✅ Project '$PROJECT_NAME' deployed"
echo "   ✅ Node-RED restarted with new configuration"
echo ""
echo "⚠️  Next steps:"
echo "   1. Open Node-RED: Settings → Add-ons → Node-RED → Open Web UI"
echo "   2. Select project '$PROJECT_NAME' if prompted"
echo "   3. Deploy your flows"
echo ""
echo "💡 To update: Just update this addon when a new version is available!"
echo ""
