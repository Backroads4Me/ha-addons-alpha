## [0.6.13] - 2025-11-20

### Fixed
- Ensured CAN-MQTT Bridge receives the correct auto-generated MQTT password

## [0.6.12] - 2025-11-20

### Fixed
- Removed copying of `flows_cred.json` to prevent encryption key errors
- Now relying fully on injected environment variables for MQTT credentials

## [0.6.11] - 2025-11-20

### Added
- Injected `MQTT_USER` and `MQTT_PASS` as environment variables into Node-RED container
- Enables using `${MQTT_USER}` and `${MQTT_PASS}` in Node-RED flows for dynamic credential configuration

## [0.6.10] - 2025-11-20

### Fixed
- Automatically configures `core_mosquitto` with default user `rvlink` (password: `One23four`) if no MQTT credentials are provided
- Ensures seamless connection for CAN-MQTT Bridge and Node-RED without manual user creation

## [0.6.9] - 2025-11-20

### Fixed
- Implemented automatic restart of Node-RED when configuration/flows are updated
- Added copying of `flows_cred.json` to preserve credentials if present in bundle
- Cleaned up debug logging from initialization process

## [0.6.8] - 2025-11-20

### Fixed
- Added `-f` flag to `cp` command in `init_commands` to force overwrite of `flows.json`
- Added debug logging to `init_commands` (output to `/share/rv-link/init_debug.log`) to troubleshoot file copying

## [0.6.7] - 2025-11-20

### Fixed
- Updated Node-RED initialization to copy project files to `/config/projects/rv-link-node-red/` to match flow references
- Ensured `flows.json` is copied to `/config/flows.json` for automatic loading

## [0.6.6] - 2025-11-20

### Fixed
- Switched to `rsync` for project file synchronization to ensure exact mirroring (deletes extraneous files)
- Fixed `sed` regex compatibility for Node-RED configuration injection (using POSIX `[[:space:]]`)
- Fixed file permissions for `/share/rv-link` to ensure Node-RED can read flows
- Cleaned up verbose API logging

## [0.6.5] - 2025-11-20

### Fixed
- Fixed race condition where Node-RED started before project files were deployed by moving deployment to Phase 0
- Fixed `init_commands` not updating on existing installations by forcing update if command differs

## [0.6.4] - 2025-11-20

### Fixed
- Fixed race condition where Node-RED started before project files were deployed by moving deployment to Phase 0
- Fixed `init_commands` not updating on existing installations by forcing update if command differs

## [0.6.3] - 2025-11-20

### Fixed
- Fixed CAN-MQTT Bridge configuration failure by adding missing `ssl` and `debug_logging` fields to options payload
- Fixed Node-RED configuration failure by correcting `sed` command delimiter in `init_commands`

### Changed
- Updated Node-RED deployment to sync the entire project directory (recursively) instead of just `flows.json`, ensuring all assets are available
- Added explicit Node-RED context storage configuration (default: memory, file: localfilesystem) to `settings.js` injection

## [0.6.2] - 2025-11-20

### Fixed
- Fixed Node-RED startup failure caused by malformed contextStorage sed command

### Changed
- Simplified Node-RED configuration to only set flowFile path (removed automatic contextStorage configuration)

## [0.6.1] - 2025-11-20

### Fixed
- Fixed MQTT connectivity verification failure caused by missing mosquitto-clients dependency
- Fixed "Service not enabled" error messages during MQTT service registration wait

## [0.6.0] - 2025-11-20

### Changed
- **BREAKING**: Separated CAN-MQTT bridge from bundled code to standalone addon installation
- RV Link now installs three separate addons: Mosquitto, Node-RED, and CAN-MQTT Bridge
- Removed CAN hardware dependencies from RV Link (moved to CAN-MQTT Bridge addon)
- Simplified RV Link to pure orchestrator role
- CAN-MQTT Bridge configured automatically with RV Link settings
- Node-RED flows now always pulled from main branch instead of version tags

### Removed
- Bundled CAN bridge implementation removed
- CAN-related system dependencies removed from Dockerfile (can-utils, iproute2)
- CAN hardware access permissions removed from config.yaml (privileged, devices, kernel_modules, host_network)
- Backup file creation removed (flows.json.bak and settings.js.bak no longer created)

## [0.5.3] - 2025-11-20

### Added
- Added set_boot_auto() function to configure addons to start on boot
- RV Link, Mosquitto, and Node-RED now all start automatically on Home Assistant boot

### Changed
- Version bump to reflect breaking changes from 0.5.2
- Changed RV Link boot configuration from manual to auto

## [0.5.2] - 2025-11-20

### Fixed
- Fixed Node-RED startup failure caused by Python dependency and heredoc delimiter issues in init command

### Added
- Added preserve_project_customizations configuration option (default: false) to control flow deployment behavior

### Changed
- **BREAKING**: Simplified from Node-RED projects to direct flowFile approach
- Removed unnecessary projects mode complexity (no Git integration needed)
- Node-RED now loads flows directly from /share/rv-link/flows.json via flowFile setting
- Deployment now copies flows.json file instead of full project directory
- Init command significantly simplified - only sets flowFile path and contextStorage
- Flows update to bundled version by default on every restart (ensures users get latest)
- Users can enable preserve_project_customizations=true to keep their custom modifications

## [0.5.1] - 2025-11-20

### Fixed
- Fixed false conflict error when Mosquitto is already installed by checking service hostname
- Fixed Node-RED takeover permission check being bypassed when is_installed() fails to detect existing installation
- Fixed is_installed() function to properly detect installed addons by checking version field when installed field is absent
- Fixed syntax error from using local keyword outside of function
- Fixed init command heredoc delimiter issue and Python dependency by switching to shell-based approach
- Improved error message when Node-RED is already installed to guide users to enable confirm_nodered_takeover setting

### Changed
- **BREAKING**: Removed addon_configs mapping as cross-container access is not possible
- Completely redesigned settings.js configuration to use shell-based init_commands (sed/grep)
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
