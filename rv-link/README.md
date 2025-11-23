# RV Link - Complete RV Control System

RV Link is the all-in-one solution for integrating your RV's RV-C network with Home Assistant. It acts as a **System Orchestrator**, automatically setting up the entire environment for you.

## ✨ Features

-   **🔌 Hardware Bridge**: Connects directly to your CAN interface (e.g., Waveshare CAN HAT on Raspberry Pi 5) and bridges RV-C network traffic to MQTT.
-   **🧠 System Orchestrator**: Automatically installs and configures the official **Mosquitto Broker** and **Node-RED**.
-   **📦 Project Bundler**: Comes with the `rv-link-node-red` automation project pre-bundled. No Git required!
-   **🛡️ Safety First**: Respects your existing Node-RED flows and asks permission before taking over.

## 🚀 Installation

### 1. Add the Repository

[![Open your Home Assistant instance and show the add-on repository dialog with a specific repository URL pre-filled.](https://my.home-assistant.io/badges/supervisor_add_addon_repository.svg)](https://my.home-assistant.io/redirect/supervisor_add_addon_repository/?repository_url=https%3A%2F%2Fgithub.com%2FBackroads4Me%2Fha-addons)

Or manually add: `https://github.com/Backroads4Me/ha-addons`

### 2. Install RV Link

Find **RV Link** in the store and click **Install**.

### 3. Start & Enjoy

Click **Start**. The add-on will:
1.  Check for **Mosquitto**. If missing, it installs it.
2.  Check for **Node-RED**. If missing, it installs it.
3.  **Deploy** the RV Link automation flows.
4.  **Start** the CAN-to-MQTT bridge.

## ⚠️ Important Notes

### Mosquitto Requirement
RV Link **strictly requires** the official Home Assistant **Mosquitto broker** add-on.
-   If you are using another broker (like EMQX), installation will **fail** to prevent conflicts.
-   Please switch to the official Mosquitto add-on to use RV Link.

### Existing Node-RED Users
If you already have Node-RED installed:
-   RV Link will **PAUSE** and wait for your permission.
-   It will **NOT** overwrite your existing flows automatically.
-   To proceed, you must go to **Configuration** and enable `confirm_nodered_takeover`.

## 🔧 Configuration

| Option | Default | Description |
| :--- | :--- | :--- |
| `can_interface` | `can0` | The network interface of your CAN hardware (e.g., can0 for Waveshare CAN HAT). |
| `can_bitrate` | `250000` | Bitrate of your RV-C network (usually 250k). |
| `confirm_nodered_takeover` | `false` | **Safety Switch**: Set to `true` to allow RV Link to replace existing Node-RED flows. |

## 📚 Support

-   **Documentation & Support**: [rvlink.app](https://rvlink.app)
