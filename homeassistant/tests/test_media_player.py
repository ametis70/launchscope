"""Tests for media player entity."""

from __future__ import annotations

from unittest.mock import AsyncMock, MagicMock

from homeassistant.components.media_player import MediaPlayerState
from tests.conftest import (
    APPS_LIST,
    STATUS_APP_RUNNING,
    STATUS_IDLE,
    make_response,
)

from custom_components.launchscope.media_player import LaunchscopeMediaPlayer


def make_player(data, apps=None):
    coordinator = MagicMock()
    coordinator.data = data
    coordinator.async_post = AsyncMock()
    coordinator.async_request_refresh = AsyncMock()
    entry = MagicMock()
    entry.entry_id = "test_entry"
    player = LaunchscopeMediaPlayer(coordinator, entry)
    player._apps = apps or []
    return player


# ── state ────────────────────────────────────────────────────────────────── #


def test_state_app_running():
    player = make_player(STATUS_APP_RUNNING)
    assert player.state == MediaPlayerState.ON


def test_state_ui_running():
    player = make_player(STATUS_IDLE)
    assert player.state == MediaPlayerState.IDLE


def test_state_no_data():
    player = make_player(None)
    assert player.state == MediaPlayerState.OFF


def test_state_unknown_string():
    player = make_player({"state": "starting"})
    assert player.state == MediaPlayerState.IDLE


# ── source / app ─────────────────────────────────────────────────────────── #


def test_source_app_running():
    player = make_player(STATUS_APP_RUNNING)
    assert player.source == "Kodi"


def test_source_idle():
    player = make_player(STATUS_IDLE)
    assert player.source is None


def test_app_name_app_running():
    player = make_player(STATUS_APP_RUNNING)
    assert player.app_name == "Kodi"


def test_source_list():
    player = make_player(STATUS_IDLE, apps=APPS_LIST)
    assert player.source_list == ["Kodi", "Moonlight"]


def test_source_list_empty():
    player = make_player(STATUS_IDLE, apps=[])
    assert player.source_list == []


# ── volume ───────────────────────────────────────────────────────────────── #


def test_volume_level():
    player = make_player(STATUS_IDLE)
    assert player.volume_level == 0.72


def test_volume_level_capped_at_1():
    data = {**STATUS_IDLE, "audio": {"volume": 1.5, "muted": False, "sink_name": ""}}
    player = make_player(data)
    assert player.volume_level == 1.0


def test_volume_level_no_audio():
    player = make_player({"state": "ui_running", "current_app": None, "audio": None})
    assert player.volume_level is None


def test_is_volume_muted_false():
    player = make_player(STATUS_IDLE)
    assert player.is_volume_muted is False


def test_is_volume_muted_true():
    data = {**STATUS_IDLE, "audio": {"volume": 0.5, "muted": True, "sink_name": ""}}
    player = make_player(data)
    assert player.is_volume_muted is True


def test_is_volume_muted_no_audio():
    player = make_player({"state": "ui_running", "current_app": None, "audio": None})
    assert player.is_volume_muted is None


# ── actions ──────────────────────────────────────────────────────────────── #


async def test_set_volume_level():
    player = make_player(STATUS_IDLE)
    await player.async_set_volume_level(0.8)
    player.coordinator.async_post.assert_awaited_once_with("/api/audio/volume", {"value": 0.8})


async def test_mute_volume():
    player = make_player(STATUS_IDLE)
    await player.async_mute_volume(True)
    player.coordinator.async_post.assert_awaited_once_with("/api/audio/mute", {"muted": True})


async def test_volume_up():
    player = make_player(STATUS_IDLE)
    await player.async_volume_up()
    player.coordinator.async_post.assert_awaited_once_with("/api/audio/volume", {"delta": 0.05})


async def test_volume_down():
    player = make_player(STATUS_IDLE)
    await player.async_volume_down()
    player.coordinator.async_post.assert_awaited_once_with("/api/audio/volume", {"delta": -0.05})


async def test_media_stop():
    player = make_player(STATUS_APP_RUNNING)
    await player.async_media_stop()
    player.coordinator.async_post.assert_awaited_once_with("/api/stop")
    player.coordinator.async_request_refresh.assert_awaited_once()


# ── select_source ─────────────────────────────────────────────────────────  #


async def test_select_source_known_app():
    player = make_player(STATUS_IDLE, apps=APPS_LIST)
    await player.async_select_source("Kodi")
    player.coordinator.async_post.assert_awaited_once_with("/api/launch/kodi")
    player.coordinator.async_request_refresh.assert_awaited_once()


async def test_select_source_unknown_retries_fetch(hass):
    """Unknown source triggers a re-fetch of the app list before giving up."""
    player = make_player(STATUS_IDLE, apps=[])

    fresh_apps_resp = make_response(200, APPS_LIST)
    player.coordinator._session = MagicMock()
    player.coordinator._session.get = MagicMock(return_value=fresh_apps_resp)
    player.coordinator.base_url = "http://host:8765"
    player.coordinator.headers = {}

    await player.async_select_source("Kodi")

    # After re-fetch the app was found and launched.
    player.coordinator.async_post.assert_awaited_once_with("/api/launch/kodi")


async def test_select_source_unknown_after_retry_gives_up():
    """If app still not found after re-fetch, nothing is launched."""
    player = make_player(STATUS_IDLE, apps=[])

    fresh_apps_resp = make_response(200, [])  # empty even after re-fetch
    player.coordinator._session = MagicMock()
    player.coordinator._session.get = MagicMock(return_value=fresh_apps_resp)
    player.coordinator.base_url = "http://host:8765"
    player.coordinator.headers = {}

    await player.async_select_source("NonExistent")

    player.coordinator.async_post.assert_not_awaited()


async def test_select_source_by_name_not_id():
    """Source selection matches on name, not id."""
    player = make_player(STATUS_IDLE, apps=APPS_LIST)
    await player.async_select_source("Moonlight")
    player.coordinator.async_post.assert_awaited_once_with("/api/launch/moonlight")
