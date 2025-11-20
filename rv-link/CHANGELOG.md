## [0.5.1] - 2025-11-20

### Fixed
- Fixed false conflict error when Mosquitto is already installed by checking service hostname
- Fixed Node-RED takeover permission check being bypassed when is_installed() fails to detect existing installation
- Fixed is_installed() function to properly detect installed addons by checking version field when installed field is absent
- Fixed syntax error from using local keyword outside of function
- Improved error message when Node-RED is already installed to guide users to enable confirm_nodered_takeover setting

### Changed
- **BREAKING**: Removed addon_configs mapping as cross-container access is not possible
- Completely redesigned settings.js configuration to use Python-based init_commands
- Init command now properly enables projects mode in editorTheme section
- Init command adds context storage configuration (memory and file)
- Init command sets projectsDir to /share so Node-RED finds external projects
- Init command automatically sets rv-link as the active project in projects.json
- Removed unnecessary 120-second wait for inaccessible settings.js file
- Simplified startup flow with clearer messaging about init_commands approach

## [0.4.9] - 2025-11-20

### Changed
- Version skipped due to refactoring

## [0.4.8] - 2025-11-19

### Changed
- Project deployment location changed from /share/node-red-projects/rv-link to /share/rv-link for better visibility

## [0.4.7] - 2025-11-19

### Fixed
- Fixed startup type from services to application to match Dockerfile CMD usage
- Fixed MQTT configuration race condition by moving after Mosquitto installation
- Fixed MQTT authentication by waiting for service registration after Mosquitto starts
- Fixed missing MQTT connectivity check before starting bridge
- Fixed addon installation error handling with proper exit codes
- Fixed Node-RED restart without waiting for completion
- Fixed CAN interface failure handling with graceful degradation
- Fixed Mosquitto addon installation check that incorrectly reported addon as installed
- Fixed settings.js context storage configuration by waiting for Node-RED to create file on first start
- Moved context storage modification to correct position in startup sequence

### Added
- Added MQTT connectivity verification function
- Added restart_addon function with proper wait logic
- Added background process monitoring for CAN bridge
- Added orchestrator-only mode when CAN hardware unavailable
- Added auto-restart logic for bridge processes

### Changed
- Pinned git clone to specific version tags for reproducible builds
- Removed unused force_update configuration option
- Removed Python debug output from settings.js modification
- Updated documentation to match monolith architecture
- Improved settings.js wait logic with proper timing

## [0.4.1] - 2025-11-19

### Changed
- Monolith architecture updates and bug fixes.
- Added debug logging and safety checks.

## [0.4.0] - 2025-11-18

### Changed

- Complete redesign

## [0.1.0] - 2025-11-06

### Added

- Initial release of RV Link meta-installer add-on
