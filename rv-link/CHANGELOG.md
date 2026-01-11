## [0.8.52] - 2026-01-11

### Added

- MQTT integration prerequisite check before installation
- Persistent notification in HA UI when MQTT integration setup required
- Enhanced error detection to surface CAN-MQTT Bridge failures in RV Link logs
- Installation summary showing status of all components
- Diagnostic MQTT credential logging for troubleshooting

### Fixed

- CAN-MQTT Bridge MQTT authentication failures now properly reported in RV Link logs
- Mosquitto restart triggers MQTT integration discovery for new installations

### Changed

- Installation now pauses if MQTT integration not configured, with clear setup instructions

## [0.8.51] - 2026-01-09

### Fixed

- Corrected CAN to MQTT addon slug

## [0.8.5] - 2025-11-27

### Fixed

- Fixed MQTT topic fields being blank in CAN-MQTT Bridge by adding missing schema entries

## [0.8.3] - 2025-11-25

### Changed

- First release