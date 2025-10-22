## [0.4.7] - 2025-10-22

### Fixed

- **CRITICAL**: Resolved Bluetooth disconnect during WiFi scan by using async threading WITHOUT heartbeat notifications
- GLib main loop now stays responsive during 5-second Supervisor API scan, preventing iOS timeout disconnect
- Removed BLE notifications during scan to avoid WiFi/BLE radio interference on Raspberry Pi

### Technical Details

**Root cause identified**: The Supervisor API `get_access_points()` call blocks for 5+ seconds. When called synchronously:
- GLib main loop freezes (cannot process BLE events)
- iOS sees unresponsive connection and disconnects after 2-3 seconds
- Even without notifications, a frozen main loop kills the BLE connection

**Solution**: Use async threading to keep main loop responsive, but NO BLE notifications during scan:
- WiFi scan runs in background thread (doesn't block main loop)
- BLE connection stays alive and responsive to iOS
- No notifications sent during scan (prevents WiFi/BLE radio interference)
- Only send READY2 + results after scan completes

This combines the best of both approaches:
- ✅ Main loop responsive (BLE connection alive)
- ✅ No radio interference (no notifications during scan)

## [0.4.6] - 2025-10-22

### Fixed

- **CRITICAL**: Resolved Bluetooth disconnect during WiFi scan by reverting to synchronous scan approach
- Removed async WiFi scanning with background threading that caused BLE/WiFi radio interference
- Removed "SCANNING" notifications and heartbeat mechanism that competed with WiFi scan
- BLE connection now stays idle during WiFi scan, eliminating radio contention on Raspberry Pi hardware

### Changed

- Reverted to synchronous `mgr.get_list()` call (blocks main loop during scan) like original working version
- iOS app now waits for scan completion without timing out (as designed)
- Removed 109 lines of async complexity in favor of 20 lines of proven synchronous code

### Technical Details

- Root cause: Raspberry Pi WiFi and Bluetooth share the same 2.4GHz radio
- When actively sending BLE notifications during WiFi scan, radios compete causing disconnection
- Original btwifiset.py kept BLE idle during scan, preventing interference
- This fix matches the proven behavior of the original working version

## [0.4.5] - 2025-10-21

### Fixed

- iOS app disconnect during WiFi scan by removing premature READY2 and empty AP list sends
- Heartbeat now sends SCANNING notifications instead of empty JSON

## [0.4.3] - 2025-10-21

### Fixed

- iOS still disconnected after AP2s because it expects JSON frames on the wifiData characteristic shortly after the request. Added immediate one-part multiwifi heartbeat frame and periodic heartbeats during scan to keep session alive.

## [0.4.2] - 2025-10-21

### Fixed

- Prevented iOS disconnect during WiFi scans by sending immediate "wifi:SCANNING" over BLE without queueing via [WifiDataCharacteristic.send_now_simple()](bluetooth-wifi-setup/app/ble/service.py:523)

### Changed

- Offloaded WiFi scanning to a background thread to keep the GLib main loop responsive so notifications flush promptly; see [WifiSetService.register_SSID()](bluetooth-wifi-setup/app/ble/service.py:196)

## [0.4.1] - 2025-10-21

### Fixed

Fixed iOS app timeout during WiFi scan by sending immediate "SCANNING" acknowledgment

## [0.4.0] - 2025-10-21

### Added

- Added `hassio_role: manager` to config.yaml to fix 403 Forbidden errors on WiFi network scanning

## [0.3.9] - 2025-10-20

### Fixed

- Fixed AttributeError when wifi_config is None from Supervisor API

### Changed

- Replaced iwlist-based WiFi scanning with Supervisor API in NetworkManager.scan()

## [0.3.8] - 2025-10-20

### Fixed

- Added ultra-granular logging in supervisor_known_networks() to identify exact line causing 2.6s hang
- Split logging to avoid f-string evaluation issues in critical path
- Added type logging for interface_info to detect lazy-loading objects
- Added explicit None check before truthy evaluation

### Changed

- Changed from single f-string log to multiple discrete log statements for better isolation of hanging code

## [0.3.7] - 2025-10-20

### Fixed

- Added extensive diagnostic logging to get_NM_Known_networks() to trace execution flow
- Added exception handling to get_NM_Known_networks() method to prevent silent failures
- Added exception handling to supervisor_known_networks() static method
- Reduced iwlist scan timeout from 15s to 5s to fail faster in HAOS environments
- Added detailed logging before and after iwlist subprocess execution
- Added stderr/stdout logging for failed iwlist commands

### Changed

- Enhanced logging throughout Supervisor API calls to identify where execution stops
- All WiFi config methods now log entry/exit points and intermediate steps

## [0.3.6] - 2025-10-20

### Fixed

- Fixed critical Bluetooth disconnect issue during WiFi scan operations
- Added comprehensive exception handling to AP2s and APs handlers in register_SSID method (app/ble/service.py)
- Added defensive logging throughout WiFi scan process to track execution flow (app/wifi/manager.py:get_list())
- Added robust exception handling to NetworkManager.scan() method with specific handlers for FileNotFoundError, TimeoutExpired, and AttributeError
- Added timeout handling and error logging to WpaSupplicant.scan() method
- Bluetooth connection now stays stable even if WiFi scan fails, with error notifications sent to client instead of silent disconnect

### Changed

- WiFi scan errors now return empty list gracefully instead of crashing the BLE service
- All scan failures now log full tracebacks for easier debugging

## [0.3.5] - 2025-10-18

### Fixed

- Fixed run.sh import test that would always fail due to relative imports in main.py
- Fixed SUPERVISOR_TOKEN check to allow wpa_supplicant fallback in non-HA environments
- Fixed critical indentation error in WpaSupplicant.request_connection method (app/wifi/manager.py:262)
- Fixed string syntax error in connect_wait method with broken multi-line f-string (app/wifi/manager.py:504-507)
- Fixed missing BTDbusSender class by creating app/ble/dbus_sender.py module for button functionality
- Fixed unterminated docstring in register_SSID method (app/ble/service.py:194)
- Fixed docstring indentation error in where_is_ssid method (app/wifi/manager.py:591)
- Fixed misplaced docstrings in manager.py by converting to comments (lines 356-364, 609-614)
- Fixed malformed docstring closing quote in WifiManager class (app/wifi/manager.py:556)

## [0.3.2] - 2025-10-17

### Fixed

- Fixed a `ModuleNotFoundError` by adding the `app` directory to the Docker image. This was missed during the v0.3.0 refactoring.
- Fixed an `AttributeError` for `dbus.service` by adding the missing `import dbus.service` statement in `app/ble/core.py`.

## [0.3.0] - 2025-10-17

### Changed

- **BREAKING**: Refactored the entire monolithic `main.py` script into a modular application structure under the `app/` directory. This improves maintainability and resolves tooling buffer issues.
- Changed the Wi-Fi scanning method to use a direct `iwlist scan` system call instead of the Home Assistant Supervisor API. This is a more robust method that avoids the previous `403 Forbidden` errors.

### Added

- Added the `wireless-tools` package to the `Dockerfile` to provide the `iwlist` utility required for the new scanning method.

### Fixed

- Fixed a critical bug where Wi-Fi scanning would fail due to a `403 Forbidden` error when calling the Supervisor API.

## [0.2.1] - 2025-10-17

### Changed

- **BREAKING**: Replaced all NetworkManager command-line (nmcli) calls with Home Assistant Supervisor REST API

### Added

- New `SupervisorAPI` class for network management via HTTP requests to Supervisor API
- Supervisor token validation in startup script

### Fixed

- Bluetooth device name configuration now properly respects the configured name
- Device name only falls back to hostname when configuration is blank (not appending both)

### Removed

- Complete removal of nmcli subprocess calls (~20+ instances)
- Removed `networkmanager` and `networkmanager-wifi` packages from Dockerfile
- Removed unused `/usr/local/btwifiset/` directory structure

## [0.1.12] - 2025-10-16

### Fixed

- Fixed Python indentation error

### Changed

- Migrated to monorepo structure at https://github.com/Backroads4Me/ha-addons

## [0.1.11] - 2025-10-16

- Removed logging noise
- Debugging

## [0.1.7] - 2025-10-16

### Fixed

- Fixed Python 3.12+ SyntaxWarnings in btwifiset.py by converting regex patterns to raw strings
- Eliminated 6 invalid escape sequence warnings in regex patterns

### Changed

- Updated regex patterns to use raw strings (r'...') for proper Python 3.12+ compatibility
- Modified lines: 398, 459, 1065, 1545, 1557, 1620 in btwifiset.py

## [0.1.4] - 2025-10-16

### Fixed

- Re-added `networkmanager` and `networkmanager-wifi` packages to Dockerfile (required for `nmcli` CLI tool)
- Python code requires `nmcli` command to configure WiFi networks
- `nmcli` client connects to host's NetworkManager via D-Bus (`host_dbus: true`)

### Changed

- Updated Dockerfile comment to clarify NetworkManager client usage
- Kept improved D-Bus accessibility check in run.sh

## [0.1.3] - 2025-10-16

### Fixed

- Fixed NetworkManager detection to use D-Bus API instead of `nmcli` command
- NetworkManager is accessed via host D-Bus (`host_dbus: true`), not as an installed binary

### Changed

- Removed unnecessary `networkmanager` and `networkmanager-wifi` packages from Dockerfile
- Updated NetworkManager check to verify D-Bus accessibility
- Improved error messages for NetworkManager troubleshooting

## [0.1.2] - 2025-10-16

### Fixed

- Fixed Bluetooth adapter detection to use sysfs (`/sys/class/bluetooth/`) instead of device nodes (`/dev/hci0`)
- Removed unnecessary device mapping from config.yaml - addon now uses BlueZ D-Bus API properly

### Changed

- Updated documentation to reflect proper Bluetooth detection method
- Improved error messages for Bluetooth adapter troubleshooting

## [0.1.1] - 2025-10-16

### Changed

- Configured GitHub Container Registry for pre-built images
- Improved documentation formatting with centered header

### Added

- Automated release workflow for GitHub Releases

## [0.1.0] - 2025-10-15

### Added

- Initial release of Bluetooth WiFi Setup addon for Home Assistant OS
- BLE server for WiFi configuration via BTBerryWifi mobile app
- NetworkManager integration for WiFi network configuration
- Support for scanning available WiFi networks
- Configurable timeout for automatic shutdown (default: 15 minutes)
- Multiple log levels (debug, info, warning, error)
- Security features:
  - Auto-shutdown after timeout
  - Optional keep-alive mode
  - Optional Bluetooth encryption support (premium feature)
- Hardware validation checks for Bluetooth and WiFi adapters
- Comprehensive user documentation (DOCS.md)
- Multi-architecture support (aarch64, amd64, armv7)
- Configuration options:
  - Bluetooth timeout (1-1440 minutes)
  - Custom BLE device name
  - Log level selection
  - Keep-alive mode toggle
  - Encryption enable/disable
  - Custom password support

### Technical Details

- Based on [Rpi-SetWiFi-viaBluetooth](https://github.com/nksan/Rpi-SetWiFi-viaBluetooth) v2
- Uses NetworkManager via DBus for WiFi configuration
- BlueZ 5.x for Bluetooth Low Energy server
- Python 3 with dbus-python, PyGObject, and cryptography
- Alpine Linux base image

### Known Limitations

- Requires Bluetooth adapter accessible via BlueZ D-Bus API
- WiFi adapter expected at `wlan0` (warning if not found)
- Requires BTBerryWifi mobile app (iOS/Android)
- Premium app features (encryption) require separate purchase
