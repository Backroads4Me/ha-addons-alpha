## [0.7.13] - 2025-11-23

### Changed

- Documentation

## [0.7.0] - 2025-11-23

### Working snapshot

## [0.6.57] - 2025-11-23

### Changed

- Final status message simplified for clarity
- Watchdog mode enabled for all auto-start addons (Mosquitto, Node-RED, CAN-MQTT Bridge)
- Documentation updated to reference Raspberry Pi 5 and Waveshare CAN HAT as primary hardware
- Support links updated to point to rvlink.app

### Fixed

- Redundant debug message prefixes removed
- Documentation updated to use "RV-C network" terminology consistently

## [0.6.56] - 2025-11-22

### Fixed

- Flow deployment "Argument list too long" error by piping flows data to curl via stdin instead of command-line argument

## [0.6.55] - 2025-11-22

### Fixed

- Node-RED flow deployment using correct deployment type ("full" instead of invalid "reload")
- Improved error handling in deployment function to capture and log HTTP status codes

## [0.6.48] - 2025-11-21

### Fixed

- Corrected a build process issue where critical Node-RED startup logic was not included, causing installation to fail silently.
- The script now correctly waits for the Node-RED API and triggers a flow deployment to ensure MQTT nodes connect automatically.

## [0.6.47] - 2025-11-21

### Removed

- Dynamic settings.js creation and copying mechanism.
- Obsolete `settings.js` and `verify_sed.sh` files.
- Node-RED API waiting and flow deployment logic (`wait_for_nodered_api`, `deploy_nodered_flows`).

### Changed

- Node-RED configuration simplified:
    - `flows.json` is now directly modified with MQTT credentials (using environment variables) and copied to `/config/flows.json`.
    - Node-RED environment variables (`MQTT_USER`, `MQTT_PASS`, `MQTT_HOST`, `MQTT_PORT`) are now passed directly via Supervisor API.
    - Node-RED no longer uses a custom `settings.js` or project mode for flows.
    - Project directories for `rvc` content are still created and copied to ensure dependent files are available to Node-RED.

## [0.6.38] - 2025-11-20

### Changed
- Docker build now explicitly removes `.gitignore`, `.gitattributes`, and `flows_cred.json` from the bundled project.
- Ensures a cleaner deployment without unnecessary version control files or stale credentials.

## [0.6.37] - 2025-11-20

### Fixed
- Fixed Node-RED API authentication failure (401 Unauthorized) by injecting `adminAuth` configuration to allow anonymous access.
- This ensures `rv-link` can successfully check status and deploy flows without manual login.
- Updated Node-RED flow configuration to use the configured `mqtt_user` and `mqtt_pass` instead of hardcoded defaults.

## [0.6.36] - 2025-11-20

### Fixed
- Fixed debug logging in Node-RED detection to correctly capture `curl` error messages (was suppressed by `-s` flag).
- Now uses `curl -sS` (or `-v` in debug mode) to ensure connection errors are visible in logs.

## [0.6.35] - 2025-11-20

### Changed
- Refactored MQTT configuration: `mqtt_host` and `mqtt_port` removed from options (now internal defaults).
- `mqtt_user` and `mqtt_pass` are now configurable options with default values ("rvlink"/"One23four").
- Updated `run.sh` to use the configured MQTT credentials.

## [0.6.34] - 2025-11-20

### Changed
- Added detailed debug logging to Node-RED API detection to diagnose connection failures
- Captures and logs specific curl error messages (connection refused, timeout, etc.)

## [0.6.33] - 2025-11-20

### Changed
- Remove .git directory during Docker build instead of during deployment
- Significantly reduces Docker image size
- Removed --exclude from rsync (no longer needed)

## [0.6.32] - 2025-11-20

### Changed
- Exclude .git* files during rsync instead of deleting after copy
- Cleaner approach - git files never reach /share/.rv-link/ or Node-RED config
- Simplified init command by removing unnecessary cleanup step

## [0.6.31] - 2025-11-20

### Changed
- Init command now removes .git* files from deployed project directory
- Cleans up unnecessary version control files in production deployment

## [0.6.30] - 2025-11-20

### Fixed
- Init command now deletes old flows_cred.json before injecting new credentials
- Prevents credential mismatch between old encrypted file and new flows

## [0.6.29] - 2025-11-20

### Changed
- Node-RED now reads flows directly from project directory instead of copying to /config/flows.json
- flowFile setting points to 'projects/rv-link-node-red/flows.json' for single source of truth
- Eliminated duplicate flows.json file
- MQTT credentials injected into project flows.json instead of /config/flows.json

### Fixed
- Cleaner architecture with flows kept in project directory alongside other assets
- Simplified init command by removing redundant file copy

## [0.6.28] - 2025-11-20

### Changed
- Project directory moved from `/share/rv-link` to `/share/.rv-link` (hidden)
- Prevents users from accidentally modifying managed flows

## [0.6.27] - 2025-11-20

### Changed
- Addon now uses `startup: services` and exits after setup completion
- Changed to `boot: auto` to ensure addon runs on upgrades and HA restarts
- Addon completes setup in seconds and exits cleanly instead of running indefinitely
- Removed infinite sleep loop - addon is now a true one-time setup orchestrator

### Fixed
- Addon no longer wastes resources running 24/7 doing nothing
- Updated documentation to reflect new run-once behavior

## [0.6.26] - 2025-11-20

### Fixed
- Bash syntax error where 'local' was used outside function scope

## [0.6.25] - 2025-11-20

### Changed
- Simplified customization documentation - users can now easily disable RV Link management by clearing init_commands
- Removed complex fork workflow from documentation in favor of simple YAML edit

## [0.6.24] - 2025-11-20

### Changed
- Replaced rocket emoji with RV truck emoji in success messages
- Updated final success message to direct users to Overview Dashboard and rvlink.app
- Removed Node-RED UI access instruction from final message

### Fixed
- Addon now properly exits with failure (exit 1) when Node-RED fails to start or deploy
- Success status only shown when all critical components are verified working
- Better error reporting for deployment failures

## [0.6.23] - 2025-11-20

### Removed
- Removed `preserve_project_customizations` configuration option
- RV Link now always manages and updates Node-RED flows automatically

### Changed
- Simplified file deployment logic - always deploys latest bundled flows
- Updated documentation to clarify that flow customizations should be done via repository fork

## [0.6.22] - 2025-11-20

### Changed
- Node-RED API detection now tries multiple hostnames for better Docker network compatibility
- Added verification that Node-RED reaches 'started' state before API access attempts

### Fixed
- Node-RED API connection failures due to Docker networking resolved by trying multiple hosts
- Better error messages when Node-RED API is unreachable

## [0.6.21] - 2025-11-20

### Added
- Automatic Node-RED flow deployment via HTTP Admin API after startup
- Wait for Node-RED API readiness before attempting deployment

### Fixed
- MQTT credentials now properly encrypted into flows_cred.json via automatic deployment
- Node-RED flows now work immediately without requiring manual deployment
- Init commands now execute properly on first configuration by ensuring Node-RED starts/restarts

## [0.6.20] - 2025-11-20

### Fixed
- Node-RED init command converted to single-line format to prevent eval syntax errors

## [0.6.19] - 2025-11-20

### Added
- State tracking system to remember Node-RED management status across restarts
- Version tracking in state file for upgrade detection

### Fixed
- Node-RED takeover confirmation now only required on first install, not on restarts
- RV Link no longer asks for permission after it has already taken over Node-RED

## [0.6.18] - 2025-11-20

### Changed
- CAN-MQTT Bridge now installs before Node-RED to ensure proper component availability
- Startup log message updated to use recreational vehicle icon

### Fixed
- MQTT credentials now properly injected into Node-RED flows using corrected jq escaping
- Node-RED restart logic improved to ensure init commands execute on all configuration changes

## [0.6.17] - 2025-11-20

### Fixed
- MQTT credential consistency issue resolved by always creating rvlink user in Mosquitto
- Both Node-RED and CAN-MQTT Bridge now use the same rvlink credentials regardless of service discovery

## [0.6.16] - 2025-11-20

### Fixed
- MQTT credentials now properly injected into mqtt-broker configuration node using jq
- Node-RED will automatically encrypt credentials into flows_cred.json on first load

## [0.6.15] - 2025-11-20

### Changed
- Cleaned up debug logging and diagnostic code left from development
- Re-enabled debug_logging config option instead of forcing debug mode

## [0.6.14] - 2025-11-20

### Fixed
- Node-RED flows now appear immediately without requiring manual restart by automatically restarting Node-RED when init commands are updated
- MQTT broker configuration node credentials now properly set to rvlink/One23four via direct injection into flows.json

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
