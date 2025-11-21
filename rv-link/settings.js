/**
 * RV Link Node-RED Settings
 *
 * This file is bundled with the RV Link addon and copied to /config/settings.js
 * during initialization. It ensures that Node-RED is configured correctly
 * for the RV Link environment.
 */

module.exports = {
    // Retry time in milliseconds for MQTT connections
    mqttReconnectTime: 15000,

    // Retry time in milliseconds for Serial port connections
    serialReconnectTime: 15000,

    // The maximum length, in characters, of any message sent to the debug sidebar tab
    debugMaxLength: 1000,

    // RV Link Specific Configuration
    // -------------------------------------------------------------------------
    
    // Point to the bundled project flows
    flowFile: '/config/projects/rv-link-node-red/flows.json',

    // Configure context storage (Memory + File)
    contextStorage: {
        default: "memory",
        memory: { module: "memory" },
        file: { module: "localfilesystem" }
    },

    // -------------------------------------------------------------------------

    functionGlobalContext: {
        // os:require('os'),
    },

    paletteCategories: [
        "home_assistant",
        "home_assistant entities",
        "subflows",
        "common",
        "function",
        "network",
        "sequence",
        "parser",
        "storage",
    ],

    logging: {
        console: {
            metrics: false,
            audit: false,
        },
    },

    editorTheme: {
        projects: {
            enabled: false,
        },
    },
};
