# RV Link Documentation

Complete documentation for the RV Link all-in-one RV control system add-on.

## Overview

RV Link is a Home Assistant add-on that orchestrates a complete RV monitoring and control solution by installing and configuring three essential components.

### Key Features

- **One-Time Setup Orchestrator**: Installs and configures Mosquitto, Node-RED, and CAN-MQTT Bridge
- **Automated Deployment**: Deploys pre-packaged Node-RED flows for RV control
- **Safety Protection**: Asks permission before modifying existing Node-RED installations
- **Auto-start Configuration**: All components configured to start automatically on boot
- **Runs Once and Exits**: Completes setup and exits cleanly - only needs to run during installation/updates

## How It Works

When you start the RV Link add-on:

1. **System Orchestration**: Installs/starts Mosquitto broker and Node-RED
2. **Project Deployment**: Deploys the bundled RV Link Node-RED flows to `/share/.rv-link`
3. **CAN Bridge Setup**: Installs and configures the CAN-MQTT Bridge addon
4. **Exit Clean**: Setup completes and addon exits

All three components are configured to start automatically on Home Assistant boot. The RV Link addon itself does not need to remain running - it only runs during initial setup and updates.

## Automatic Configuration

RV Link automatically configures Node-RED to use the shared flow file at `/share/.rv-link/flows.json`, allowing the addon to deploy and update the RV Link automation flows.

## Prerequisites

### Hardware

- **RV-C Network Interface**: CAN interface such as Waveshare CAN HAT on Raspberry Pi 5
  - Note: CAN hardware is essential for the system to function

### Software

RV Link automatically installs these if missing:
- **Mosquitto Broker** (Official add-on) - MQTT message bus
- **Node-RED** (Community add-on) - Flow-based automation
- **CAN-MQTT Bridge** (Custom add-on) - Bidirectional RV-C network to MQTT bridge

## Configuration Options

Access configuration: Settings → Add-ons → RV Link → Configuration

### `can_interface`

**Type**: String
**Default**: `can0`

The network interface name of your CAN hardware (e.g., can0 for Waveshare CAN HAT).

**Example**:
```yaml
can_interface: can0
```

### `can_bitrate`

**Type**: Integer
**Default**: `250000`

The bitrate of your RV-C network. Most RVs use 250kbps.

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

### Step 4: Connect CAN Hardware

1. Connect your CAN interface (e.g., Waveshare CAN HAT on Raspberry Pi 5)
2. Verify it appears as `can0` (or adjust `can_interface` config)

**Note**: The CAN-MQTT Bridge addon will fail to start without CAN hardware, but system orchestration will succeed.

### Step 5: Start the Add-on

1. Settings → Add-ons → RV Link
2. Click "Start"
3. Watch the logs to see progress

The add-on will:
- Install Mosquitto (if needed)
- Install Node-RED (if needed)
- Deploy the RV Link flows
- Install and configure CAN-MQTT Bridge

### Step 6: Access Node-RED

1. Settings → Add-ons → Node-RED → Open Web UI
2. The RV Link flows should load automatically from `/share/.rv-link/flows.json`
3. Deploy the flows if needed (click Deploy button)

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
- Bundled Node-RED flows
- CAN bridge improvements

**Important**: Updating RV Link always replaces the flows with the bundled version. RV Link manages the Node-RED flows automatically.

## Project Location

RV Link manages flows in two locations:

**Source (managed by RV Link):**
```
/share/.rv-link/
```
- Hidden directory containing bundled flows
- Updated when RV Link addon runs
- Do not manually modify

**Active (used by Node-RED):**
```
/config/projects/rv-link-node-red/flows.json
```
- Copied from source on Node-RED startup
- Node-RED reads and writes to this location
- MQTT credentials automatically injected here

## Troubleshooting

### Error: "MQTT broker is not responding"

**Cause**: Mosquitto failed to start or is not accepting connections.

**Solution**:
1. Check Mosquitto add-on logs: Settings → Add-ons → Mosquitto broker → Log
2. Ensure Mosquitto is running
3. Restart RV Link after fixing Mosquitto

### CAN-MQTT Bridge addon fails to start

**Cause**: No CAN hardware detected or wrong interface name.

**Solution**:
1. Verify CAN interface hardware is connected (e.g., Waveshare CAN HAT on Raspberry Pi 5)
2. Check CAN-MQTT Bridge addon logs for details
3. Update `can_interface` config in RV Link if not `can0`
4. Restart both RV Link and CAN-MQTT Bridge addons after connecting hardware

**Note**: System orchestration will succeed even if CAN bridge fails.

### Error: "Installation aborted to protect existing flows"

**Cause**: Node-RED is already installed and `confirm_nodered_takeover` is not enabled.

**Solution**:
1. **Important**: This protects your existing Node-RED flows from being overwritten
2. If you want RV Link to take over Node-RED:
   - Go to RV Link configuration
   - Set `confirm_nodered_takeover: true`
   - Restart RV Link
3. **Warning**: This will replace your current Node-RED flows

### Node-RED doesn't show the flows

**Cause**: Flow file might not have been configured or deployed properly.

**Solution**:
1. Check that `/config/projects/rv-link-node-red/flows.json` exists
2. Check Node-RED addon logs for errors during startup
3. Check RV Link addon logs for deployment messages
4. Restart Node-RED addon to re-run init commands
5. Verify flowFile setting in `/addon_configs/a0d7b954_nodered/settings.js` points to `projects/rv-link-node-red/flows.json`

### CAN frames not appearing in MQTT

**Cause**: CAN-MQTT Bridge not running or wrong topic.

**Solution**:
1. Check CAN-MQTT Bridge addon logs for startup messages
2. Verify addon is running: Settings → Add-ons → CAN-MQTT Bridge
3. Check MQTT topic: default is `can/raw`
4. Monitor MQTT with MQTT Explorer or `mosquitto_sub -v -t "can/#"`
5. Verify CAN traffic exists (see CAN-MQTT Bridge documentation)

### Add-on keeps restarting

**Cause**: Critical error during startup.

**Solution**:
1. Check logs: Settings → Add-ons → RV Link → Log
2. Look for errors in Phase 1 (Orchestration), Phase 2 (Deployment), or Phase 3 (CAN-MQTT Bridge)
3. Common issues:
   - Mosquitto installation failed (check internet connection)
   - Node-RED configuration error (check Node-RED logs)
   - CAN-MQTT Bridge installation failed (check addon store availability)

## Advanced Usage

### Using Node-RED Independently

If you want to use Node-RED without RV Link management:

1. Uninstall the RV Link add-on
2. Go to Node-RED add-on Configuration tab
3. Click "Edit in YAML"
4. Find the `init_commands:` section and replace it with:
   ```yaml
   init_commands: []
   ```
   Or delete the entire `init_commands:` section
5. Save and restart Node-RED

This removes RV Link's automatic flow deployment and lets you use Node-RED independently.

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

- **Documentation & Support**: https://rvlink.app

## Technical Details

### Architecture

RV Link acts as a pure orchestrator that installs and configures three separate addons:
1. **Mosquitto** - MQTT broker for message routing
2. **Node-RED** - Flow-based automation with RV Link flows
3. **CAN-MQTT Bridge** - Bidirectional RV-C network to MQTT bridge

### Permissions

RV Link requires:
- `hassio_api: true` - To communicate with Supervisor API
- `hassio_role: manager` - To install and configure other add-ons
- `map: share:rw` - To deploy Node-RED flows to shared storage

Note: Node-RED's settings.js is modified using init_commands that run inside the Node-RED container, as direct file access is not possible across containers.

### API Usage

The add-on uses the Supervisor API to:
- Install add-ons (Mosquitto, Node-RED, CAN-MQTT Bridge)
- Configure add-on options
- Set boot configuration for auto-start
- Start and restart add-ons when needed

### Flows Structure

The deployed flows directory contains:
- `flows.json` - Your Node-RED flows (loaded via flowFile setting)
- `README.md` (optional) - Documentation about the flows

Note: This uses Node-RED's flowFile setting rather than projects mode, simplifying the setup and removing Git dependencies.

## FAQ

**Q: Can I modify the flows after deployment?**
A: You can modify flows in the Node-RED UI, but changes will be overwritten when RV Link updates. To use your own flows permanently, see "Using Node-RED Independently" in the Advanced Usage section.

**Q: How do I get help or provide feedback?**
A: Visit https://rvlink.app for documentation and support.
