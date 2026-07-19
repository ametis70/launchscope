"""Tests for sensor entities."""

from __future__ import annotations

from unittest.mock import MagicMock

import pytest

from custom_components.launchscope.sensor import LaunchscopeCurrentAppSensor
from tests.conftest import STATUS_IDLE, STATUS_APP_RUNNING


def make_sensor(data):
    coordinator = MagicMock()
    coordinator.data = data
    entry = MagicMock()
    entry.entry_id = "test_entry"
    sensor = LaunchscopeCurrentAppSensor(coordinator, entry)
    return sensor


def test_native_value_idle():
    sensor = make_sensor(STATUS_IDLE)
    assert sensor.native_value == "idle"


def test_native_value_app_running():
    sensor = make_sensor(STATUS_APP_RUNNING)
    assert sensor.native_value == "kodi"


def test_native_value_no_data():
    sensor = make_sensor(None)
    assert sensor.native_value == "idle"


def test_extra_state_attributes_idle():
    sensor = make_sensor(STATUS_IDLE)
    attrs = sensor.extra_state_attributes
    assert attrs["app_name"] is None
    assert attrs["state"] == "ui_running"


def test_extra_state_attributes_app_running():
    sensor = make_sensor(STATUS_APP_RUNNING)
    attrs = sensor.extra_state_attributes
    assert attrs["app_name"] == "Kodi"
    assert attrs["state"] == "app_running"


def test_extra_state_attributes_no_data():
    sensor = make_sensor(None)
    attrs = sensor.extra_state_attributes
    assert attrs["app_name"] is None
    assert attrs["state"] is None


def test_unique_id():
    sensor = make_sensor(STATUS_IDLE)
    assert "current_app" in sensor._attr_unique_id


def test_icon():
    sensor = make_sensor(STATUS_IDLE)
    assert sensor._attr_icon == "mdi:apps"
