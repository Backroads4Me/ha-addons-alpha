# Home Assistant RV Link Add-on

This add-on acts as a meta-installer to set up a complete monitoring and control system for an RV, based on Home Assistant.

It automatically installs and configures:
- **Mosquitto MQTT Broker**
- **Node-RED** (and configures it with a specific project for RV automation)
- **CAN-MQTT Bridge**
- **Mushroom Cards** for Lovelace
- **Power Flow Card Plus** for Lovelace
- **HA Victron MQTT** integration

## Installation

1. Add the repository to your Home Assistant instance.
2. Install the "RV Link" add-on.
3. Start the add-on. The installation process will run automatically.
4. Restart Home Assistant to load all integrations and cards.
