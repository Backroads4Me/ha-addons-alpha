## [0.5.1] - 2025-11-19

### Fixed
- Fixed MQTT authentication by waiting for service registration after Mosquitto starts

## [0.5.0] - 2025-11-19

### Fixed
- Fixed startup type from services to application to match Dockerfile CMD usage
- Fixed MQTT configuration race condition by moving after Mosquitto installation
- Fixed missing MQTT connectivity check before starting bridge
- Fixed addon installation error handling with proper exit codes
- Fixed Node-RED restart without waiting for completion
- Fixed CAN interface failure handling with graceful degradation
- Fixed Mosquitto addon installation check that incorrectly reported addon as installed

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
