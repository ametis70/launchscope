"""Tests for button entities."""

from __future__ import annotations

from unittest.mock import AsyncMock, MagicMock

import pytest

from custom_components.launchscope.button import (
    LaunchscopeCECActivateButton,
    LaunchscopeCECStandbyButton,
    LaunchscopeCECSwitchInputButton,
    LaunchscopeStopButton,
)
from tests.conftest import STATUS_APP_RUNNING, STATUS_IDLE


def make_button(cls, data):
    coordinator = MagicMock()
    coordinator.data = data
    coordinator.async_post = AsyncMock()
    coordinator.async_request_refresh = AsyncMock()
    entry = MagicMock()
    entry.entry_id = "test_entry"
    return cls(coordinator, entry)


# ── LaunchscopeStopButton ─────────────────────────────────────────────────  #


def test_stop_button_available_when_app_running():
    btn = make_button(LaunchscopeStopButton, STATUS_APP_RUNNING)
    assert btn.available is True


def test_stop_button_unavailable_when_idle():
    btn = make_button(LaunchscopeStopButton, STATUS_IDLE)
    assert btn.available is False


def test_stop_button_unavailable_when_no_data():
    btn = make_button(LaunchscopeStopButton, None)
    assert btn.available is False


async def test_stop_button_press():
    btn = make_button(LaunchscopeStopButton, STATUS_APP_RUNNING)
    await btn.async_press()
    btn.coordinator.async_post.assert_awaited_once_with("/api/stop")
    btn.coordinator.async_request_refresh.assert_awaited_once()


# ── LaunchscopeCECActivateButton ──────────────────────────────────────────  #


async def test_cec_activate_press():
    btn = make_button(LaunchscopeCECActivateButton, STATUS_IDLE)
    await btn.async_press()
    btn.coordinator.async_post.assert_awaited_once_with("/api/cec/activate")


def test_cec_activate_icon():
    btn = make_button(LaunchscopeCECActivateButton, STATUS_IDLE)
    assert btn._attr_icon == "mdi:television-play"


# ── LaunchscopeCECStandbyButton ───────────────────────────────────────────  #


async def test_cec_standby_press():
    btn = make_button(LaunchscopeCECStandbyButton, STATUS_IDLE)
    await btn.async_press()
    btn.coordinator.async_post.assert_awaited_once_with("/api/cec/standby")


def test_cec_standby_icon():
    btn = make_button(LaunchscopeCECStandbyButton, STATUS_IDLE)
    assert btn._attr_icon == "mdi:television-off"


# ── LaunchscopeCECSwitchInputButton ──────────────────────────────────────── #


async def test_cec_switch_input_press():
    btn = make_button(LaunchscopeCECSwitchInputButton, STATUS_IDLE)
    await btn.async_press()
    btn.coordinator.async_post.assert_awaited_once_with("/api/cec/switch-input")


def test_cec_switch_input_icon():
    btn = make_button(LaunchscopeCECSwitchInputButton, STATUS_IDLE)
    assert btn._attr_icon == "mdi:hdmi-port"


# ── unique_id uniqueness ──────────────────────────────────────────────────  #


def test_unique_ids_are_distinct():
    ids = {
        make_button(LaunchscopeStopButton, STATUS_IDLE)._attr_unique_id,
        make_button(LaunchscopeCECActivateButton, STATUS_IDLE)._attr_unique_id,
        make_button(LaunchscopeCECStandbyButton, STATUS_IDLE)._attr_unique_id,
        make_button(LaunchscopeCECSwitchInputButton, STATUS_IDLE)._attr_unique_id,
    }
    assert len(ids) == 4
