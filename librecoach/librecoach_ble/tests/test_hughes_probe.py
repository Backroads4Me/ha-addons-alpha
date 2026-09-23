"""Tests for the alpha-only Hughes protocol probe."""

import json

import conftest  # registers Home Assistant and bleak fakes

from librecoach_ble.devices import DEVICE_HANDLERS
from librecoach_ble.devices.hughes_probe import HughesProbeHandler, REPORT_NAME
from test_hughes import run, v2_block, v2_frame, v2_packet


def probe_handler(name="WD_E5_123"):
    return HughesProbeHandler("AA:BB", {"_device_name": name})


def feed(handler, *blocks):
    handler._on_v2_notification(None, v2_frame(*blocks))
    return handler._latest_state


def test_alpha_registry_uses_the_probe_handler():
    assert HughesProbeHandler in DEVICE_HANDLERS


def test_changes_are_logged_against_the_active_scenario():
    handler = probe_handler()
    feed(handler, v2_block(121.4, 14.3, 1735.0, 142.3), v2_block(120.2, 8.1, 973.6, 42.3))
    run(handler.handle_command(None, {"command": "probe_scenario", "value": "  neutral   off "}))
    feed(
        handler,
        v2_block(121.5, 14.1, 1710.0, 142.4, neutral=1),
        v2_block(120.1, 8.0, 960.0, 42.4, relay=2),
    )

    changes = [event for event in handler.probe.events if event["kind"] == "change"]
    assert [(event["byte"], event["old"], event["new"]) for event in changes] == [
        ("L1.25 raw[34] neutral_detection?", 0, 1),
        ("L2.33 raw[76] relay_status?", 0, 2),
    ]
    assert {event["scenario"] for event in changes} == {"neutral off"}
    assert changes[0]["context"]["voltage_l1"] == 121.5
    assert handler.probe.scenarios["neutral off"]["values"]["L1.25"] == {1}


def test_measurement_like_bytes_stop_flooding_the_timeline():
    handler = probe_handler()
    for step in range(40):
        block = v2_block(121.4, 14.3, 1735.0, 142.3)
        block[16] = step
        feed(handler, block)

    kinds = [event["kind"] for event in handler.probe.events]
    assert kinds.count("change") == 30
    assert kinds.count("noisy") == 1


def test_discovery_joins_the_hughes_device_and_is_not_retained():
    handler = probe_handler()
    state = feed(handler, v2_block(121.4, 14.3, 1735.0, 142.3))
    messages = handler.state_messages(state)

    configs = {m.topic: m for m in messages if m.topic.endswith("/config")}
    assert set(configs) == {
        "homeassistant/text/hughes_aa_bb_probe_scenario/config",
        "homeassistant/sensor/hughes_aa_bb_probe_last_change/config",
        "homeassistant/sensor/hughes_aa_bb_probe_report/config",
        "homeassistant/button/hughes_aa_bb_probe_export/config",
        "homeassistant/button/hughes_aa_bb_probe_reset/config",
        "homeassistant/button/hughes_aa_bb_probe_remove_entities/config",
    }
    assert not any(m.retain for m in configs.values())
    scenario = json.loads(configs["homeassistant/text/hughes_aa_bb_probe_scenario/config"].payload)
    assert scenario["device"] == {"identifiers": ["librecoach-ble-hughes-aa_bb"]}
    assert scenario["command_topic"] == "librecoach/ble/hughes/aa:bb/set"
    assert any(m.topic == "librecoach/ble/hughes/aa:bb/probe" for m in messages)

    # Discovery is sent once per connection.
    again = handler.state_messages(state)
    assert not any(m.topic.endswith("/config") for m in again)


def test_v1_devices_are_not_probed():
    handler = probe_handler("PMD123")
    topics = [m.topic for m in handler.state_messages({"protocol": "V1"})]
    assert topics == ["librecoach/ble/hughes/aa:bb/state"]


def test_device_commands_and_responses_are_recorded():
    handler = probe_handler()
    feed(handler, v2_block(121.4, 14.3, 1735.0, 142.3))

    class Client:
        async def write_gatt_char(self, characteristic, packet, response=False):
            handler._on_v2_notification(None, v2_packet(packet[6], b"\x01"))

    assert run(handler.handle_command(Client(), {"command": "neutral_detection", "value": False})) is True
    kinds = [event["kind"] for event in handler.probe.events]
    assert kinds[-3:] == ["command", "response", "command_result"]
    assert handler.probe.events[-2]["message_type"] == 0x0D


def test_export_writes_a_report_with_scenarios_and_timeline(tmp_path):
    handler = probe_handler()
    handler.report_dir = str(tmp_path)
    feed(handler, v2_block(121.4, 14.3, 1735.0, 142.3))
    run(handler.handle_command(None, {"command": "probe_scenario", "value": "startup delay"}))
    feed(handler, v2_block(121.4, 0.0, 0.0, 142.3, relay=1))
    feed(handler, v2_block(121.4, 14.3, 1735.0, 142.3))

    assert run(handler.handle_command(None, {"command": "probe_export"})) is True
    report = (tmp_path / REPORT_NAME).read_text()
    assert "] startup delay  (2 frames)" in report
    assert "L1.33 raw[42] relay_status?: 0, 1" in report
    assert "L1.33 raw[42] relay_status?: 0 -> 1" in report
    assert f"/local/{REPORT_NAME}?v=" in handler.probe.state()["report"]


def test_reset_clears_the_recording():
    handler = probe_handler()
    feed(handler, v2_block(121.4, 14.3, 1735.0, 142.3))
    run(handler.handle_command(None, {"command": "probe_scenario", "value": "x"}))
    run(handler.handle_command(None, {"command": "probe_reset"}))

    assert handler.probe.scenario == "unlabelled"
    assert list(handler.probe.events) == []


def test_remove_entities_deletes_discovery_once_and_stops_republishing():
    handler = probe_handler()
    state = feed(handler, v2_block(121.4, 14.3, 1735.0, 142.3))
    created = [m.topic for m in handler.state_messages(state) if m.topic.endswith("/config")]

    assert run(handler.handle_command(None, {"command": "probe_remove_entities"})) is True
    removal = handler.state_messages(state)
    deletes = [m for m in removal if m.topic.endswith("/config")]
    assert sorted(m.topic for m in deletes) == sorted(created)
    assert all(m.payload == "" and m.retain for m in deletes)
    assert not any(m.topic.endswith("/probe") for m in removal)

    # A reconnect (which clears the sent flag) must not bring the entities back.
    handler._probe_discovery_sent = False
    after = handler.state_messages(state)
    assert not any(m.topic.endswith(("/config", "/probe")) for m in after)
