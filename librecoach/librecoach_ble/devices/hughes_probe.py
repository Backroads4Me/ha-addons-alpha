"""Alpha-only Hughes Gen2 protocol probe.

Alpha testers with a Hughes Watchdog run labelled scenarios (plug-in delay,
neutral monitoring off, ...) and export a report of every byte the device
reported while each scenario was active. The report is what we use to decide
what the undocumented Gen2 status bytes mean before encoding them in hughes.py.

This module exists only in ha-addons-alpha, which is never mirrored to beta or
production. alpha-notes/sync-from-beta.sh preserves it and re-registers it in
devices/__init__.py. Everything the probe adds to Home Assistant is published
from here, so the shared Node-RED flows carry no trace of it.
"""

import asyncio
import json
import logging
import time
from collections import deque
from datetime import datetime
from pathlib import Path

from ..const import MQTT_BASE, TOPIC_AVAILABLE, TOPIC_SET
from .base import StateMessage
from .hughes import HughesHandler

_LOGGER = logging.getLogger(__name__)

PROBE_TOPIC = MQTT_BASE + "/hughes/{address}/probe"
REPORT_NAME = "librecoach_hughes_probe.txt"
DEFAULT_REPORT_DIR = "/config/www"

V2_LINE_OFFSETS = (9, 43)
# Non-measurement bytes of each 34-byte line block. Names ending in "?" are
# unconfirmed readings the probe exists to confirm or refute.
WATCHED_BYTES = {
    16: "power_factor b0",
    17: "power_factor b1",
    18: "power_factor b2",
    19: "power_factor b3",
    20: "output_voltage (booster) b0",
    21: "output_voltage (booster) b1",
    22: "output_voltage (booster) b2",
    23: "output_voltage (booster) b3",
    24: "backlight",
    25: "neutral_monitoring (0=on, 1=bypassed)",
    26: "boost_mode (booster)?",
    27: "temperature (booster)?",
    32: "error_code",
    33: "line index? (0=L1, 1=L2; not relay)",
}

MAX_EVENTS = 5000
# A byte that changes this often is a measurement, not a status; later changes
# are counted rather than logged so it cannot flood the timeline.
NOISY_AFTER = 30
MAX_DISTINCT_VALUES = 32
PROBE_HEARTBEAT = 30


def _now() -> str:
    return datetime.now().isoformat(timespec="seconds")


def byte_label(key: str) -> str:
    """Describe a watched byte key such as "L1.33" with its raw frame index."""
    line, offset = key[1:].split(".")
    offset = int(offset)
    raw_index = V2_LINE_OFFSETS[int(line) - 1] + offset
    return f"{key} raw[{raw_index}] {WATCHED_BYTES[offset]}"


class HughesProbe:
    """Record watched Gen2 bytes, labelled by the tester's current scenario."""

    def __init__(self):
        self.reset()

    def reset(self):
        self.events = deque(maxlen=MAX_EVENTS)
        self.dropped = 0
        self.scenario = "unlabelled"
        self.scenarios = {}
        self.values = {}
        self.change_counts = {}
        self.last_change = "none"
        self.last_frame = None
        self.last_unparsed = None
        self.report = "none"
        self._start_scenario(self.scenario)

    def record(self, kind: str, **fields):
        if len(self.events) == self.events.maxlen:
            self.dropped += 1
        self.events.append({"time": _now(), "scenario": self.scenario, "kind": kind, **fields})

    def _start_scenario(self, label: str):
        self.scenarios.setdefault(label, {
            "started": _now(),
            "frames": 0,
            "first_frame": None,
            "last_frame": None,
            "values": {},
        })

    def set_scenario(self, label: str):
        label = " ".join(str(label or "").split())[:255] or "unlabelled"
        self.scenario = label
        self._start_scenario(label)
        self.record("scenario", label=label, frame=self.last_frame)

    def observe(self, raw: bytes, parsed: dict):
        """Record one complete data frame and any watched byte that changed."""
        frame = raw.hex()
        if not parsed:
            if frame != self.last_unparsed:
                self.last_unparsed = frame
                self.record("unparsed_data_frame", length=len(raw), frame=frame)
            return

        current = {}
        line_count = 2 if parsed.get("is_50a") else 1
        for line, base in enumerate(V2_LINE_OFFSETS[:line_count], start=1):
            for offset in WATCHED_BYTES:
                current[f"L{line}.{offset}"] = raw[base + offset]

        if self.last_frame is None:
            self.record("first_frame", frame=frame)
        for key, value in current.items():
            previous = self.values.get(key)
            if previous is None or previous == value:
                continue
            count = self.change_counts.get(key, 0) + 1
            self.change_counts[key] = count
            if count <= NOISY_AFTER:
                self.record(
                    "change", byte=byte_label(key), old=previous, new=value,
                    context=self._context(parsed), frame=frame,
                )
                self.last_change = (
                    f"{byte_label(key)}: {previous} -> {value} at "
                    f"{datetime.now().strftime('%H:%M:%S')}"
                )
            elif count == NOISY_AFTER + 1:
                self.record("noisy", byte=byte_label(key), note="further changes are not logged")

        self.values = current
        self.last_frame = frame
        scenario = self.scenarios[self.scenario]
        scenario["frames"] += 1
        scenario["first_frame"] = scenario["first_frame"] or frame
        scenario["last_frame"] = frame
        for key, value in current.items():
            seen = scenario["values"].setdefault(key, set())
            if len(seen) < MAX_DISTINCT_VALUES:
                seen.add(value)

    @staticmethod
    def _context(parsed: dict) -> dict:
        fields = (
            "voltage_l1", "current_l1", "voltage_l2", "current_l2",
            "error_code_l1", "error_code_l2", "neutral_monitoring", "neutral_problem",
        )
        return {field: parsed.get(field) for field in fields if parsed.get(field) is not None}

    def state(self) -> dict:
        return {
            "scenario": self.scenario,
            "last_change": self.last_change,
            "events": len(self.events),
            "report": self.report,
            "bytes": {byte_label(key): value for key, value in self.values.items()},
        }

    def render_report(self, device_name: str, address: str) -> str:
        """Build the plain-text report a tester sends back."""
        out = [
            "LibreCoach Hughes probe report (alpha)",
            f"Generated: {_now()}",
            f"Device: {device_name or 'unknown'}  Address: {address}",
            f"Events: {len(self.events)} recorded, {self.dropped} oldest dropped",
            "",
            "Each V2 data frame is a 9-byte header, then one 34-byte block per",
            "line (L1 at raw[9], L2 at raw[43]). Keys read L<line>.<offset in block>.",
            "",
            "== Values seen per scenario ==",
        ]
        for label, scenario in self.scenarios.items():
            if not scenario["frames"]:
                continue
            out.append("")
            out.append(f"[{scenario['started']}] {label}  ({scenario['frames']} frames)")
            for key in sorted(scenario["values"], key=self._key_order):
                seen = sorted(scenario["values"][key])
                shown = ", ".join(str(value) for value in seen)
                if len(seen) >= MAX_DISTINCT_VALUES:
                    shown += ", ... (many)"
                out.append(f"  {byte_label(key)}: {shown}")
            out.append(f"  first frame: {scenario['first_frame']}")
            out.append(f"  last frame:  {scenario['last_frame']}")

        out.extend(["", "== Timeline =="])
        for event in self.events:
            out.append(self._timeline_line(event))

        out.extend(["", "== Raw events (JSON lines) =="])
        out.extend(json.dumps(event, sort_keys=True) for event in self.events)
        return "\n".join(out) + "\n"

    @staticmethod
    def _key_order(key: str):
        line, offset = key[1:].split(".")
        return int(line), int(offset)

    @staticmethod
    def _timeline_line(event: dict) -> str:
        prefix = f"{event['time']}  [{event['scenario']}]  {event['kind']}"
        kind = event["kind"]
        if kind == "change":
            return f"{prefix}  {event['byte']}: {event['old']} -> {event['new']}  {json.dumps(event['context'])}"
        if kind == "scenario":
            return f"{prefix}  -> {event['label']}"
        if kind == "noisy":
            return f"{prefix}  {event['byte']} ({event['note']})"
        if kind in ("command", "command_result"):
            return f"{prefix}  {json.dumps({k: v for k, v in event.items() if k not in ('time', 'scenario', 'kind')})}"
        if kind == "response":
            return f"{prefix}  type=0x{event['message_type']:02X} payload={event['payload']}"
        return f"{prefix}  {event.get('frame', '')}"


class HughesProbeHandler(HughesHandler):
    """HughesHandler that also records a protocol probe on Gen2 devices."""

    report_dir = None
    # Reconnect the moment the Watchdog powers back up, so the probe records
    # its startup delay (relay open, then closed) after a shore-power cut.
    reconnect_on_advertisement = True

    def __init__(self, address, config):
        super().__init__(address, config)
        self.probe = HughesProbe()
        self._probe_discovery_sent = False
        self._probe_dirty = True
        self._probe_published = 0.0
        self._probe_removed = False
        self._probe_removal_pending = False

    @property
    def _probing(self) -> bool:
        return self.protocol == "V2"

    async def authenticate(self, client) -> bool:
        if self._probing:
            self.probe.record("connect", device_name=self.device_name)
            self._probe_discovery_sent = False
        return await super().authenticate(client)

    async def handle_command(self, client, command: dict) -> dict | bool:
        action = command.get("command") if isinstance(command, dict) else None
        if self._probing and action == "probe_scenario":
            self.probe.set_scenario(command.get("value"))
            self._probe_dirty = True
            return True
        if self._probing and action == "probe_reset":
            self.probe.reset()
            self._probe_dirty = True
            return True
        if self._probing and action == "probe_remove_entities":
            self._probe_removed = True
            self._probe_removal_pending = True
            return True
        if self._probing and action == "probe_export":
            await self._export_report()
            self._probe_dirty = True
            return True

        if self._probing:
            self.probe.record("command", command=command)
        result = await super().handle_command(client, command)
        if self._probing:
            self.probe.record("command_result", success=bool(result))
            self._probe_dirty = True
        return result

    def _parse_v2(self, raw: bytes) -> dict:
        parsed = super()._parse_v2(raw)
        before = self.probe.last_change
        self.probe.observe(raw, parsed)
        self._probe_dirty |= self.probe.last_change != before
        return parsed

    def _resolve_ack(self, command: int, payload: bytes):
        self.probe.record("response", message_type=command, payload=bytes(payload).hex())
        self._probe_dirty = True
        super()._resolve_ack(command, payload)

    def _parse_v2_error_history(self, frame: bytes) -> list[dict]:
        self.probe.record("error_report", frame=frame.hex())
        return super()._parse_v2_error_history(frame)

    def state_messages(self, parsed: dict) -> list[StateMessage]:
        messages = super().state_messages(parsed)
        if not self._probing:
            return messages
        if self._probe_removed:
            if self._probe_removal_pending:
                # An empty discovery payload deletes the entity from Home Assistant.
                messages.extend(
                    StateMessage(message.topic, "", retain=True)
                    for message in self._probe_discovery()
                )
                self._probe_removal_pending = False
            return messages
        if not self._probe_discovery_sent:
            messages.extend(self._probe_discovery())
            self._probe_discovery_sent = True
            self._probe_dirty = True
        now = time.monotonic()
        if self._probe_dirty or now - self._probe_published >= PROBE_HEARTBEAT:
            messages.append(StateMessage(
                PROBE_TOPIC.format(address=self.address),
                json.dumps(self.probe.state()),
                retain=False,
            ))
            self._probe_dirty = False
            self._probe_published = now
        return messages

    def _probe_discovery(self) -> list[StateMessage]:
        # Not retained, so nothing re-creates the entities once the tester leaves
        # alpha. Probe Remove Entities deletes them before that; entities left
        # behind become orphans the tester deletes in Home Assistant.
        safe = self.address.replace(":", "_")
        base_id = f"hughes_{safe}_probe"
        probe_topic = PROBE_TOPIC.format(address=self.address)
        set_topic = TOPIC_SET.format(device_type="hughes", address=self.address)
        shared = {
            "device": {"identifiers": [f"librecoach-ble-hughes-{safe}"]},
            "availability_topic": TOPIC_AVAILABLE.format(device_type="hughes", address=self.address),
            "qos": 1,
        }
        entities = [
            ("text", "scenario", {
                "name": "Probe Scenario",
                "state_topic": probe_topic,
                "value_template": "{{ value_json.scenario }}",
                "command_topic": set_topic,
                "command_template": '{"command": "probe_scenario", "value": {{ value | tojson }}}',
                "max": 255,
                "icon": "mdi:clipboard-text-outline",
            }),
            ("sensor", "last_change", {
                "name": "Probe Last Change",
                "state_topic": probe_topic,
                "value_template": "{{ value_json.last_change[:255] }}",
                "json_attributes_topic": probe_topic,
                "json_attributes_template": "{{ value_json.bytes | tojson }}",
                "icon": "mdi:swap-horizontal",
                "entity_category": "diagnostic",
            }),
            ("sensor", "report", {
                "name": "Probe Report",
                "state_topic": probe_topic,
                "value_template": "{{ value_json.report }}",
                "icon": "mdi:file-document-outline",
                "entity_category": "diagnostic",
            }),
            ("button", "export", {
                "name": "Probe Export Report",
                "command_topic": set_topic,
                "payload_press": '{"command": "probe_export"}',
                "icon": "mdi:file-export-outline",
            }),
            ("button", "reset", {
                "name": "Probe Reset",
                "command_topic": set_topic,
                "payload_press": '{"command": "probe_reset"}',
                "icon": "mdi:restart",
                "entity_category": "config",
            }),
            ("button", "remove_entities", {
                "name": "Probe Remove Entities",
                "command_topic": set_topic,
                "payload_press": '{"command": "probe_remove_entities"}',
                "icon": "mdi:delete-outline",
                "entity_category": "config",
            }),
        ]
        messages = []
        for component, suffix, payload in entities:
            entity_id = f"{base_id}_{suffix}"
            payload = {
                **shared,
                **payload,
                "unique_id": entity_id,
                "default_entity_id": f"{component}.{entity_id}",
            }
            messages.append(StateMessage(
                f"homeassistant/{component}/{entity_id}/config",
                json.dumps(payload),
                retain=False,
            ))
        return messages

    async def _export_report(self):
        """Write the report under /local and tell the tester where to get it."""
        hass = _get_hass()
        report_dir = self.report_dir or (
            hass.config.path("www") if hass else DEFAULT_REPORT_DIR
        )
        path = Path(report_dir) / REPORT_NAME
        text = self.probe.render_report(self.device_name, self.address)

        def _write():
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(text, encoding="utf-8")

        await asyncio.get_running_loop().run_in_executor(None, _write)
        url = f"/local/{REPORT_NAME}?v={int(time.time())}"
        self.probe.report = f"{_now()} {url}"
        _LOGGER.info("Hughes probe report written to %s", path)
        if hass:
            try:
                await hass.services.async_call("persistent_notification", "create", {
                    "title": "Hughes probe report ready",
                    "message": (
                        f'<a href="{url}" target="_blank"><b>Open the probe report</b></a>. '
                        "Save it and send it to the LibreCoach developer."
                    ),
                    "notification_id": "librecoach_hughes_probe",
                })
            except Exception as exc:
                _LOGGER.warning("Could not create probe notification: %s", exc)


def _get_hass():
    try:
        from homeassistant.core import async_get_hass

        return async_get_hass()
    except Exception:
        return None
