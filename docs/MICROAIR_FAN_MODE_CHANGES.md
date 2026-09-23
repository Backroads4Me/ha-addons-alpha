# Micro-Air Fan Mode Overhaul — Change Summary & Test Plan

Date: 2026-07-05
Spec: `~/src/librecoach/ha-easytouch-wifi/docs/LIBRECOACH_MICROAIR_FAN_MODE_SPEC.md`
Origin: protocol behavior confirmed in `ha-easytouch-wifi` commit `d5f9fee`
(Add Cycled Low/High fan modes; drop FA bitmask logic).

## What Changed

Fan modes are no longer inferred from observed max fan speed or the `FA`
capability array. All layers now share one protocol-confirmed fan value map:

| Value | HA fan mode   | Meaning                                    |
|------:|---------------|--------------------------------------------|
| `0`   | `auto`        | Auto                                       |
| `1`   | `low`         | Manual low, continuous                     |
| `2`   | `high`        | Manual high, continuous (**was `medium`**) |
| `3`   | `high`        | Top speed on some 3-speed units            |
| `65`  | `Cycled Low`  | Fan runs only during active cycle, low     |
| `66`  | `Cycled High` | Fan runs only during active cycle, high    |
| `128` | `auto`        | N/A / auto sentinel                        |

### BLE add-on (this repo)

`librecoach/librecoach_ble/devices/microair.py`

- `FAN_MODE_MAP` updated to the canonical map above (`2` → `high`, added
  `3`, `65`, `66`).
- Dropped the unused `FA` fan array from the retained per-zone capability
  record published on `librecoach/ble/microair/{mac}/zone/{zone}/config`.
  Nothing consumed it; the Wi-Fi integration confirmed it does not reflect
  real fan capabilities.

### Node-RED (`~/src/librecoach/librecoach-node-red`)

- `microair_create_climate.js` — climate discovery now advertises the fixed
  list `["auto", "low", "high", "Cycled Low", "Cycled High"]`. `medium` is
  gone; the list no longer depends on observed state.
- `microair_decode_status.js` — recomputes `fan_mode` from the canonical map.
  The entire observed-max-fan-speed machinery was removed: the `_maxfan`
  file-context cache is no longer read or written, and `max_fan_speed` /
  `max_fan_changed` were dropped from the internal standardized message.
- `microair_encode_command.js` — encodes `auto`/`low`/`high`/`Cycled Low`/
  `Cycled High` as `128`/`1`/`2`/`65`/`66`. Gas/furnace heat modes
  (mode_num 3, 4, 13) have an autonomous fan: `auto` sends `gasFan: 128`,
  any other fan command is ignored (no MQTT message emitted). Fan-only
  `auto` falls back to fixed `2` (high) instead of observed max speed —
  see the open question below.
- `microair_optimistic_update.js` — uses the same canonical map so the HA UI
  shows `Cycled Low`/`Cycled High` immediately after a command.
- `microair_unique.js` — removed the dead `max_fan_changed` rediscovery
  trigger.

Entity IDs, MQTT topics, and raw numeric fan fields
(`fan_mode_num`, `cool_fan_mode_num`, etc.) are unchanged.

Note: separately from this change, capability persistence requirements are
documented in the Wi-Fi repo at
`docs/LIBRECOACH_MICROAIR_CAPABILITY_PERSISTENCE.md` — not implemented yet.

## How to Test

Verification already done: BLE add-on test suite passes (25/25); the five
Node-RED function bodies syntax-check clean; wiring maps regenerated.

Deployment:

1. Rebuild/reinstall the `librecoach` add-on from this repo so the updated
   `microair.py` is running.
2. Restart the Node-RED add-on — the flow-splitter
   (`restoreFunctionsTemplates: true`) restores the updated function code from
   `src/` during startup.
3. In HA, the Micro-Air climate entity should be rediscovered automatically;
   if the fan list looks stale, delete the retained
   `homeassistant/climate/microair_*_zone_*/config` message or restart the
   MQTT discovery by redeploying.

Then check, per spec acceptance criteria:

- [ ] HA fan dropdown shows exactly `auto`, `low`, `high`, `Cycled Low`,
      `Cycled High` — no `medium`.
- [ ] With the thermostat's fan set to manual high on the device itself,
      HA shows `high` (previously showed `medium` on some units).
- [ ] Set fan to `Cycled Low` from HA → device enters cycled low; MQTT
      command on `librecoach/ble/microair/{mac}/set` carries fan value `65`
      (watch with `mosquitto_sub` or the HA MQTT debug page). Same for
      `Cycled High` → `66`, `high` → `2`.
- [ ] The HA UI updates to the selected cycled mode immediately (optimistic),
      and stays there after the next BLE poll (~device state confirms).
- [ ] Set the device to a cycled mode from its own faceplate → HA state
      shows `Cycled Low`/`Cycled High`, not `auto`.
- [ ] While heat source is gas/furnace: selecting any fan speed other than
      `auto` does nothing (no MQTT command published); selecting `auto`
      publishes `gasFan: 128`.
- [ ] Cool/electric-heat/auto modes: fan commands land in `coolFan` /
      `eleFan` / `autoFan` respectively.

## Answering the Fan-Only Open Question

Open question from the spec: **does the device accept `fanOnly: 128`
(auto) in fan-only mode, or does it require a fixed speed?**

Current behavior keeps the old exception: selecting `auto` while in
fan-only mode sends `fanOnly: 2` (high) instead of `128`.

To answer it:

1. Put the thermostat in fan-only mode.
2. Publish a raw command to the bridge topic (substitute your MAC):

   ```bash
   mosquitto_pub -t 'librecoach/ble/microair/AA:BB:CC:DD:EE:FF/set' \
     -m '{"Type":"Change","Changes":{"fanOnly":128,"zone":0}}'
   ```

3. Observe the device faceplate and the next status payload on
   `librecoach/ble/microair/{mac}/zone/0/state`:
   - If the device switches to an auto/cycling fan and reports
     `fan_mode_num: 128` (or `0`), it accepts auto in fan-only mode →
     change `microair_encode_command.js` to send `128` for fan-only `auto`
     and remove the fallback.
   - If the device ignores the command, errors, or keeps the previous
     manual speed, it does not → keep the fallback and document the
     result in this file and in the spec (Requirement 5 asks for a
     documented device reason).
4. Also try `fanOnly: 65` / `66` on the faceplate or via the same method to
   confirm whether cycled modes are valid in fan-only mode; if not, they
   should be filtered from fan-only commands too.

Record the answer here once tested.
