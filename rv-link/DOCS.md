# RV Link Documentation

Complete documentation for the RV Link all-in-one RV control system add-on.

## Overview

RV Link is a monolithic Home Assistant add-on that provides a complete RV monitoring and control solution. It combines a CAN bus bridge with automated Node-RED project deployment and system orchestration.

### Key Features

- **Complete System Orchestrator**: Automatically installs and configures Mosquitto and Node-RED
- **CAN-MQTT Bridge**: Connects your RV's CAN bus directly to MQTT
- **Bundled Automation Project**: Pre-packaged Node-RED flows for RV control
- **Safety Protection**: Asks permission before modifying existing Node-RED installations
- **Graceful Degradation**: Works as orchestrator-only if CAN hardware is unavailable

## How It Works

When you start the RV Link add-on:

1. **System Orchestration**: Installs/starts Mosquitto broker and Node-RED
2. **Project Deployment**: Deploys the bundled RV Link Node-RED project
3. **CAN Bridge Setup**: Initializes CAN interface and starts bidirectional bridge
4. **Continuous Operation**: Runs as a long-lived service monitoring CAN traffic

The add-on remains running to maintain the CAN-MQTT bridge connection.

## Automatic Configuration

RV Link automatically configures Node-RED with optimal settings:

### Context Storage

The add-on configures two context storage options:
- **memoryOnly** (default): Fast, in-memory storage that resets on restart
- **file**: Persistent storage saved to disk

This allows your Node-RED flows to use context variables like:
```javascript
// Store in memory (faster, non-persistent)
context.set("myValue", 123);

// Store to file (slower, persists across restarts)
context.set("myValue", 123, "file");
```

**Note**: The context storage configuration is applied once during initial installation and is automatically backed up before modification.

## Prerequisites

### Hardware

- **CAN Bus Interface**: USB-CAN adapter (e.g., CandleLight, Toucan, etc.)
  - Optional: Addon works without CAN hardware in orchestrator-only mode

### Software

RV Link automatically installs these if missing:
- **Mosquitto Broker** (Official add-on) - MQTT message bus
- **Node-RED** (Community add-on) - Flow-based automation

## Configuration Options

Access configuration: Settings → Add-ons → RV Link → Configuration

### `can_interface`

**Type**: String
**Default**: `can0`

The network interface name of your USB-CAN adapter.

**Example**:
```yaml
can_interface: can0
```

### `can_bitrate`

**Type**: Integer
**Default**: `250000`

The bitrate of your RV-C bus. Most RVs use 250kbps.

**Options**: `125000`, `250000`, `500000`, `1000000`

**Example**:
```yaml
can_bitrate: 250000
```

### `confirm_nodered_takeover`

**Type**: Boolean
**Default**: `false`

Safety switch to prevent accidental overwriting of existing Node-RED flows.

**When to use**:
- Set to `true` if you have Node-RED already installed and want RV Link to take control
- Leave as `false` for new installations

**Example**:
```yaml
confirm_nodered_takeover: true
```

### MQTT Settings

Advanced users can override auto-discovered MQTT settings:

- `mqtt_host` - MQTT broker hostname (default: auto-discovered)
- `mqtt_port` - MQTT port (default: 1883)
- `mqtt_user` - MQTT username (optional)
- `mqtt_pass` - MQTT password (optional)
- `mqtt_topic_raw` - Topic for raw CAN frames (default: `can/raw`)
- `mqtt_topic_send` - Topic for sending CAN frames (default: `can/send`)
- `mqtt_topic_status` - Topic for status messages (default: `can/status`)

## Installation Guide

### Step 1: Add Repository

1. Settings → Add-ons → Add-on Store → ⋮ → Repositories
2. Add: `https://github.com/Backroads4Me/ha-addons`

### Step 2: Install RV Link

1. Find "RV Link" in the store
2. Click "Install"
3. Wait for installation to complete

### Step 3: Configure (Optional)

If you need to adjust CAN interface or other settings:

1. Settings → Add-ons → RV Link → Configuration
2. Adjust options as needed (see Configuration Options above)
3. Click "Save"

**Note for Existing Node-RED Users**: If you already have Node-RED installed with flows, you must enable `confirm_nodered_takeover: true` in the configuration before starting.

### Step 4: Connect CAN Hardware (Optional)

1. Connect your USB-CAN adapter (e.g., CandleLight, Toucan)
2. Verify it appears as `can0` (or adjust `can_interface` config)

**Note**: RV Link will work without CAN hardware, but the bridge functionality will be disabled.

### Step 5: Start the Add-on

1. Settings → Add-ons → RV Link
2. Click "Start"
3. Watch the logs to see progress

The add-on will:
- Install Mosquitto (if needed)
- Install Node-RED (if needed)
- Deploy the RV Link project
- Start the CAN-MQTT bridge (if hardware available)

### Step 6: Access Node-RED

1. Settings → Add-ons → Node-RED → Open Web UI
2. If prompted, select the "rv-link" project
3. Deploy the flows if needed

## Updating the Add-on

### When Updates Are Available

You'll see an update notification in Home Assistant when a new version is released.

### Update Process

1. Settings → Add-ons → RV Link
2. Click "Update"
3. Wait for update to complete
4. The add-on will restart automatically with the new version

### What Gets Updated

- Add-on code and dependencies
- Bundled Node-RED project (always replaced with latest version)
- CAN bridge improvements

**Important**: Updating always replaces the Node-RED project with the bundled version. If you've made local changes to flows, they will be overwritten. To preserve custom flows, fork the project repository.

## Project Location

The RV Link project is stored at:
```
/share/rv-link/
```

This location is:
- Directly in the `/share` folder for easy visibility
- Shared between add-ons and persists across restarts
- Used by Node-RED as an external project
- Accessible via File Editor or SSH for manual modifications

## Troubleshooting

### Error: "MQTT broker is not responding"

**Cause**: Mosquitto failed to start or is not accepting connections.

**Solution**:
1. Check Mosquitto add-on logs: Settings → Add-ons → Mosquitto broker → Log
2. Ensure Mosquitto is running
3. Restart RV Link after fixing Mosquitto

### Warning: "CAN bridge will NOT start - hardware not available"

**Cause**: No CAN hardware detected or wrong interface name.

**Solution**:
1. Verify USB-CAN adapter is connected
2. Check interface name with `ip link show` in Terminal
3. Update `can_interface` config if not `can0`
4. Restart add-on after connecting hardware

**Note**: This is not a fatal error - orchestration and Node-RED will still work.

### Error: "Installation aborted to protect existing flows"

**Cause**: Node-RED is already installed and `confirm_nodered_takeover` is not enabled.

**Solution**:
1. **Important**: This protects your existing Node-RED flows from being overwritten
2. If you want RV Link to take over Node-RED:
   - Go to RV Link configuration
   - Set `confirm_nodered_takeover: true`
   - Restart RV Link
3. **Warning**: This will replace your current Node-RED flows

### Node-RED doesn't show the rv-link project

**Cause**: Project mode might not have initialized properly.

**Solution**:
1. Open Node-RED Web UI
2. Look for project selector (top right or in menu)
3. Select "rv-link" project
4. If no project selector appears:
   - Check Node-RED add-on logs
   - Restart Node-RED add-on
   - Check RV Link logs for deployment errors

### CAN frames not appearing in MQTT

**Cause**: CAN bridge not running or wrong topic.

**Solution**:
1. Check RV Link logs for "Bridge processes started"
2. Verify CAN traffic exists: `candump can0` in Terminal
3. Check MQTT topic: default is `can/raw`
4. Monitor MQTT with MQTT Explorer or `mosquitto_sub -v -t "can/#"`

### Add-on keeps restarting

**Cause**: Critical error during startup.

**Solution**:
1. Check logs: Settings → Add-ons → RV Link → Log
2. Look for errors in Phase 1 (Orchestration), Phase 2 (Deployment), or Phase 3 (Bridge)
3. Common issues:
   - Mosquitto installation failed (check internet connection)
   - Node-RED configuration error (check Node-RED logs)
   - CAN interface error (check hardware)

## Advanced Usage

### Using a Custom Fork

To use your own fork of the RV Link project:

1. Fork https://github.com/Backroads4Me/rv-link-node-red
2. Make your modifications
3. Update the `PROJECT_REPO` variable in the RV Link add-on's `run.sh` file to point to your fork

**Note**: This requires modifying the add-on itself and is intended for advanced users only.

## Logs

To view detailed logs:

Settings → Add-ons → RV Link → Log

### Alpha Version - Enhanced Logging

This alpha release includes extensive diagnostic logging for troubleshooting:

**Environment Information:**
- Alpine Linux version
- Git and bash versions
- User and working directory
- Supervisor token validation

**Detailed Operation Logs:**
- All Supervisor API requests and responses
- Git command output (fetch, pull, reset, clone, checkout)
- File operations with before/after stats
- Settings.js modification steps
- Directory contents on failures

**What Logs Show:**
- Configuration being used
- Each step of the deployment process with sub-steps
- Success or error messages with diagnostic info
- Git operations with full command output
- API responses from Home Assistant Supervisor
- File sizes, line counts, and modification details

This verbose logging will be reduced in future stable releases.

## Support

- **Issues**: https://github.com/Backroads4Me/ha-addons/issues
- **Project Repo**: https://github.com/Backroads4Me/rv-link-node-red
- **Discussions**: GitHub Discussions in the repository

## Technical Details

### Permissions

RV Link requires:
- `hassio_api: true` - To communicate with Supervisor API
- `hassio_role: manager` - To configure other add-ons (Node-RED)
- `map: share:rw` - To access shared storage for project files

Note: Node-RED's settings.js is modified using init_commands that run inside the Node-RED container, as direct file access is not possible across containers.

### API Usage

The add-on uses the Supervisor API to:
- Query installed add-ons
- Configure Node-RED options
- Restart Node-RED when needed

### Project Structure

The deployed project should contain:
- `package.json` - Node-RED project metadata
- `flow.json` - Your Node-RED flows
- `flow_cred.json` (optional) - Encrypted credentials
- `.git/` - Git repository data

## FAQ

**Q: Can I modify the flows after deployment?**
A: Yes! Set `force_update: false` to preserve your local changes during updates.

**Q: How do I contribute to the project?**
A: Fork the project repository at https://github.com/Backroads4Me/rv-link-node-red, make changes, and submit a pull request.

**Q: What if I don't want automatic updates?**
A: Simply don't update the add-on. Your project will remain at its current version.

**Q: Can I use this without the CAN MQTT Bridge?**
A: Yes! The project may include CAN-related flows, but you can disable or remove them in Node-RED.
