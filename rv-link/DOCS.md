# RV Link Documentation

Complete documentation for the RV Link Node-RED project deployer add-on.

## Overview

RV Link is a specialized Home Assistant add-on that automates the deployment and updating of a Node-RED project designed for RV monitoring and control systems.

### Key Features

- **Automated Project Deployment**: Clones your Node-RED project from GitHub
- **Seamless Updates**: Update the add-on to update your project
- **Project Mode Management**: Automatically configures Node-RED for project mode
- **Version Synchronization**: Add-on version = Project version
- **Local Change Handling**: Configurable behavior for local modifications

## How It Works

When you start the RV Link add-on:

1. **Locates Node-RED**: Finds your installed Node-RED add-on
2. **Enables Project Mode**: Configures Node-RED to use projects
3. **Deploys Project**: Clones or updates the project from GitHub
4. **Restarts Node-RED**: Applies all changes

The add-on runs once and exits. Run it again to update your project.

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

### Required

- **Node-RED add-on** must be installed (from Community Add-ons)
  - Settings → Add-ons → Add-on Store
  - Search for "Node-RED" and install

### Recommended

For a complete RV monitoring setup:

- **Mosquitto Broker** (Official add-ons) - MQTT message bus
- **CAN MQTT Bridge** (Backroads4Me add-ons) - CAN bus integration

## Configuration Options

Access configuration: Settings → Add-ons → RV Link → Configuration

### `force_update` (optional)

**Type**: Boolean
**Default**: `true`

Controls how local changes to the Node-RED project are handled:

- `true` (default): Always update, discarding any local modifications
- `false`: Preserve local changes, skip update if modifications exist

**Example**:
```yaml
force_update: false
```

**When to use**:
- Keep default (`true`) to always receive the latest project updates
- Set to `false` if you make custom modifications to flows that you want to preserve

## Installation Guide

### Step 1: Install Node-RED

1. Settings → Add-ons → Add-on Store
2. Search for "Node-RED"
3. Click "Node-RED" by Community Add-ons
4. Click "Install"
5. Wait for installation to complete
6. **Start Node-RED** and configure it (set credentials, etc.)

### Step 2: Install Optional Add-ons

For full RV monitoring functionality:

**Mosquitto Broker**:
1. Settings → Add-ons → Add-on Store
2. Official add-ons → Mosquitto broker
3. Install and start

**CAN MQTT Bridge**:
1. Settings → Add-ons → Add-on Store → ⋮ → Repositories
2. Add: `https://github.com/Backroads4Me/ha-addons`
3. Find "CAN MQTT Bridge" and install

### Step 3: Install RV Link

1. Settings → Add-ons → Add-on Store → ⋮ → Repositories
2. Add: `https://github.com/Backroads4Me/ha-addons`
3. Find "RV Link" in the store
4. Click "Install"

### Step 4: Configure RV Link (Optional)

If you want to change default settings:

1. Settings → Add-ons → RV Link → Configuration
2. Adjust options as needed (see Configuration Options above)
3. Click "Save"

### Step 5: Deploy the Project

1. Settings → Add-ons → RV Link
2. Click "Start"
3. Watch the logs to see progress
4. Wait for "🎉 RV Link deployment complete!"

### Step 6: Access Your Project

1. Settings → Add-ons → Node-RED → Open Web UI
2. If prompted, select the "rv-link" project
3. Your flows are ready to deploy!

## Updating the Project

### When Updates Are Available

You'll see an update notification in Home Assistant when a new version is released.

### Update Process

1. Settings → Add-ons → RV Link
2. Click "Update"
3. After update completes, click "Start"
4. The project will be updated automatically

### Update Behavior

- **No local changes**: Project updates automatically
- **Local changes exist**:
  - If `force_update: true` (default): Local changes overwritten with latest version
  - If `force_update: false`: Update skipped, local changes preserved

## Project Location

The Node-RED project is stored at:
```
/share/node-red-projects/rv-link/
```

This location is shared between add-ons and persists across restarts.

## Troubleshooting

### Error: "Node-RED addon not found!"

**Cause**: Node-RED is not installed.

**Solution**: Install Node-RED from the Add-on Store first.

### Error: "Node-RED is not installed!"

**Cause**: Node-RED is in the store but not installed yet.

**Solution**: Complete the Node-RED installation before running RV Link.

### Warning: "Local changes detected - forcing update"

**Cause**: You've modified the project locally and `force_update` is `true` (default).

**Solution**:
- To accept latest version: No action needed (changes will be overwritten)
- To preserve your changes: Set `force_update: false` in configuration

### Node-RED doesn't show the project

**Cause**: Project mode might not have initialized properly.

**Solution**:
1. Open Node-RED Web UI
2. Look for project selector (top right or in menu)
3. Select "rv-link" project
4. If no project selector appears, check Node-RED logs

### Project cloning fails

**Cause**: Network issues or GitHub connectivity problems.

**Solution**:
- Check your internet connection
- Verify GitHub is accessible from your network
- Check add-on logs for specific error messages

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
- `map: addon_configs:rw` - To modify Node-RED's settings.js file

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
