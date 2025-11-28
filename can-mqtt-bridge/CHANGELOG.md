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
