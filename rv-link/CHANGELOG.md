## [0.2.0] - 2025-11-06

### Changed

- Complete redesign
- Add-on now focuses exclusively on deploying and updating the Node-RED project
- Prerequisites must now be installed manually (Node-RED, Mosquitto, CAN MQTT Bridge)

### Added

- Configuration option `force_update` to control local change handling (defaults to true)
- Automatic context storage configuration (memoryOnly + file) on first run
- Comprehensive error checking and user-friendly messages
- Git-based project update mechanism with local change detection
- Step-by-step progress reporting during deployment
- Backup of original Node-RED settings before modification
- Filesystem access to Node-RED's configuration directory
- Enhanced logging for alpha testing and troubleshooting:
  - Environment information display (Alpine version, git version, bash version)
  - Detailed API request/response logging for all Supervisor API calls
  - Verbose git operation output with command echo and indented results
  - File operation verification (sizes, line counts, before/after stats)
  - Enhanced error messages with diagnostic information
  - Directory listing on failures
  - Supervisor token validation check
  - Settings.js modification step-by-step logging

## [0.1.0] - 2025-11-06

### Added

- Initial release of RV Link meta-installer add-on
