# Hughes Gen2 protocol probe (alpha only)

The probe answers questions about Hughes Watchdog Gen2 (`WD_V5`–`WD_E9`) status
bytes that nobody on the project can test first-hand, starting with:

- What does `relay_status` (L1 byte 33, `raw[42]`) report when the relay is open
  versus closed?
- Is `neutral_detection` (byte 25) the neutral-monitoring **setting** (enabled or
  bypassed) or a detected neutral **fault**?

An alpha tester labels what they are doing in Home Assistant. The probe records
every change to the non-measurement bytes, and the tester exports one report
file and sends it back. We then encode the findings in `hughes.py`.

## Keeping it out of beta and production

- The probe is `librecoach/librecoach_ble/devices/hughes_probe.py`, and its tests
  are in `librecoach_ble/tests/test_hughes_probe.py`. Both exist only in this
  repo, and nothing is ever mirrored out of alpha.
- `devices/__init__.py` swaps in `HughesProbeHandler`. `sync-from-beta.sh` keeps
  both files and re-applies that swap after copying beta's source.
- The probe publishes its own MQTT discovery without retain, so the shared
  Node-RED flows carry nothing for it, and the beta-flag cleanup in Node-RED
  (`betaDiscoveryTopics`) cannot see or remove its entities.
- Testers remove the entities with **Probe Remove Entities** before leaving
  alpha. Beta and stable have no probe code, so after a switch the only way to
  remove leftovers is by hand: Settings → Devices & services → Entities, filter
  on "Probe", select them and delete. They show as "no longer provided".
- To retire the probe, delete both files, the `__init__.py` block, the
  `ALPHA_ONLY` entries and the registration step in `sync-from-beta.sh`.

## Getting it to a tester

1. They create a full Home Assistant backup and stop their beta or stable
   LibreCoach add-on.
2. They add `https://github.com/Backroads4Me/ha-addons-alpha` as an add-on
   repository and install **LibreCoach** from **ALPHA TESTING: LibreCoach**.
3. They re-enter their add-on options, including enabling Hughes, and start it.

## What the tester sees

These appear on the existing Hughes device in Home Assistant, on Gen2 units
only:

| Entity | Purpose |
|---|---|
| **Probe Scenario** (text) | Type what you are about to do. Every change recorded afterwards is tagged with it. |
| **Probe Last Change** (sensor) | The most recent byte change. Its attributes show the current value of every watched byte. |
| **Probe Export Report** (button) | Writes the report and posts a Home Assistant notification with a download link. |
| **Probe Report** (sensor) | When the last report was written and where. |
| **Probe Reset** (button) | Clears the recording to start a fresh session. |
| **Probe Remove Entities** (button) | Deletes all probe entities from Home Assistant. Press it last, before switching back to beta or stable. Restarting Home Assistant while still on alpha brings them back. |

- The recording is held in memory and is lost if Home Assistant restarts, so
  export before any restart.
- Scenario, export and reset go through the device command path, so they only
  work while the Watchdog is connected.
- The report is written to `/config/www/librecoach_hughes_probe.txt` and served
  at `/local/librecoach_hughes_probe.txt`.
- `/local` needs no login. The report holds the Watchdog's Bluetooth address,
  its name and its readings, nothing else.

## Test plan to send testers

Set **Probe Scenario** before each step and wait about 30 seconds after each
change. Only do the steps you are comfortable with.

1. **Baseline:** `baseline shore power`. Leave it on normal shore power with
   neutral monitoring on.
2. **Neutral monitoring:** `neutral monitoring OFF`, then turn the Neutral
   Monitoring switch off. Next set `neutral monitoring ON` and turn it back on.
   This does not interrupt power.
3. **Backlight (known control):** `backlight 1`, set Backlight Brightness to 1,
   then return it to where it was. This checks the method against a byte we
   already understand.
4. **Startup delay:** `startup delay`, set while the Watchdog is still
   connected. Switch the pedestal breaker off, wait 10 seconds and switch it on.
   The probe reconnects as soon as the Watchdog advertises again, so leave it
   running until the relay clicks in and the coach has power. If **Probe Last
   Change** shows no change to `L1.33` afterwards, press **BLE Reconnect** the
   moment the display lights up and repeat. This interrupts shore power briefly.
5. **Relay control (optional):** only if the coach can run on batteries or an
   inverter for a minute. Set `relay OFF command`, turn Shore Power Relay off,
   then set `relay ON command` and turn it back on.
6. **Anything unusual:** if the Watchdog shows a fault on its own, label it with
   what the display says.

Finish with **Probe Export Report**, open the link in the notification, save
the file and send it to us. Then press **Probe Remove Entities** before
switching back to beta or stable.

## Reading a report

- **Values seen per scenario:** for each label, every value each watched byte
  took, plus the first and last raw frame. A byte that changes value between
  the `neutral monitoring OFF` and `ON` scenarios while the error code stays 0
  is the setting.
- **Timeline:** each change with its old and new value, line voltage, current
  and error codes at that moment, and the full frame. Commands sent and the
  device's raw response packets are listed in the same order.
- **Raw events:** the same data as JSON lines, for scripts.
- Bytes that change more than 30 times are measurements. They are marked
  `noisy` once, and later changes are left out of the timeline.
