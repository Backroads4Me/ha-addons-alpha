## [0.0.4] - 2025-11-19

### Fixed

- Main.py now properly initializes ConfigData from command-line arguments
- Supervisor API disconnect method no longer disables WiFi interface
- Signal strength conversion uses correct dBm range
- Thread safety for BLE notification queue
- Connection verification after WiFi network configuration
- WiFi adapter check now fails addon startup if no adapter present
- Removed duplicate Python packages from requirements.txt

## [0.0.3] - 2025-11-19

### Fixed

- Dockerfile syntax error with duplicate header

## [0.0.1] - 2025-10-22

### Added

- Initial release of Bluetooth WiFi Setup addon for Home Assistant OS
