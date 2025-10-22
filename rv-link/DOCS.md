# RV Link Documentation

This document provides details on the configuration and use of the RV Link add-on.

## Configuration

This add-on has no user-configurable options. It runs once to install and set up the required components.

## Installed Components

- **Mosquitto MQTT Broker**: The central message bus.
- **Node-RED**: The automation engine. A custom project is deployed automatically.
- **CAN-MQTT Bridge**: For interfacing with a CAN bus network.
- **Lovelace Cards**: Mushroom and Power Flow Card Plus.
- **Integrations**: HA Victron MQTT.

## Node-RED Project

The add-on automatically enables Node-RED's project mode and clones the [rv-link-node-red](https://github.com/Backroads4Me/rv-link-node-red) repository. This project contains all the necessary flows for the RV automation system.
