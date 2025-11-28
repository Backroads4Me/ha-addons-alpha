## [1.0.9] - 2025-11-28

### Added

- Automatic detection and compensation for MCP251x oscillator frequency mismatches
- Optional `expected_oscillator` configuration parameter for manual override
- Intelligent inference of expected oscillator frequency from common standards (8 MHz, 16 MHz, 20 MHz)
- Defaults to 16 MHz oscillator when driver clock is non-standard and no manual override provided
- Detailed logging of compensation calculations and actual vs requested bitrate
- Debug mode verification showing whether compensation achieved target bitrate
- Comprehensive troubleshooting documentation for oscillator mismatch scenarios

### Changed

- CAN interface initialization now checks for clock frequency mismatch before setup
- Bitrate configuration automatically compensated when driver/hardware mismatch detected

## [1.0.8] - 2025-11-28

### Added

- Detailed CAN interface diagnostics in debug mode showing operstate, carrier, packet counters, and error counters
- CAN interface settings display showing actual bitrate, sample point, and timing parameters
- Comprehensive CAN->MQTT bridge logging showing raw candump output and every frame received
- Periodic CAN bus statistics logging every 30 seconds in debug mode
- Troubleshooting hints when no CAN frames are received
- candump error output now captured and logged instead of being suppressed
- CAN tools availability check (candump, cansend, and ip)

### Fixed

- Parameter extraction using BusyBox-compatible sed instead of grep -P

## [1.0.0] - 2025-10-22

### Changed

- Initial release of CAN to MQTT Bridge
