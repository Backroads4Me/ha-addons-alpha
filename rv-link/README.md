# RV Link - Node-RED Project Deployer

Automatically deploys and updates a Node-RED automation project for RV monitoring and control systems.

## What is RV Link?

RV Link is a Home Assistant add-on that manages your Node-RED automation project. Instead of manually configuring Node-RED and copying flows, RV Link:

- ✅ Enables Node-RED project mode automatically
- ✅ Deploys a pre-built Node-RED project from GitHub
- ✅ Updates your project when you update the add-on
- ✅ Handles project versioning seamlessly

**The add-on version matches the project version** - when you see an update notification, you know there's a new version of the automation project available!

## Prerequisites

Before installing RV Link, you must install these add-ons:

### Required
- **Node-RED** - The automation engine (install from Community Add-ons)

### Recommended for RV Monitoring
- **Mosquitto Broker** - MQTT message bus (install from Official add-ons)
- **CAN MQTT Bridge** - For CAN bus integration (install from Backroads4Me repository)

## Installation

### 1. Add the Repository

Settings → Add-ons → Add-on Store → ⋮ → Repositories

Add: `https://github.com/Backroads4Me/ha-addons`

### 2. Install Prerequisites

Install Node-RED (and optionally Mosquitto and CAN MQTT Bridge) from the Add-on Store.

### 3. Install RV Link

Find "RV Link" in the add-on store and install it.

### 4. Start RV Link

Click "Start" - the add-on will automatically:
- Configure Node-RED for project mode
- Clone the RV Link project
- Restart Node-RED

### 5. Access Node-RED

Settings → Add-ons → Node-RED → Open Web UI

Select the "rv-link" project if prompted.

## Updating

When a new version of RV Link is released:

1. Update the add-on from the Add-on Store (you'll see an update notification)
2. Start the add-on again
3. Your Node-RED project will be updated automatically

That's it! The add-on version equals the project version.

## Configuration

By default, RV Link always updates to the latest version, overwriting any local changes. See [DOCS.md](DOCS.md) for the `force_update` option to preserve local modifications.

## Support

- Issues: https://github.com/Backroads4Me/ha-addons/issues
- Project Repository: https://github.com/Backroads4Me/rv-link-node-red
