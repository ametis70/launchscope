"""Tests for LauncherCoordinator."""
from __future__ import annotations

from unittest.mock import AsyncMock, MagicMock, patch

import pytest
from homeassistant.helpers.update_coordinator import UpdateFailed

from custom_components.launchscope.coordinator import LauncherCoordinator
from tests.conftest import STATUS_IDLE, STATUS_APP_RUNNING, make_response


@pytest.fixture
def coordinator(hass):
    with patch(
        "custom_components.launchscope.coordinator.async_get_clientsession",
        return_value=MagicMock(),
    ):
        return LauncherCoordinator(hass, "192.168.1.1", 8765, "testkey")


async def test_update_data_success(hass, coordinator):
    resp = make_response(200, STATUS_IDLE)
    coordinator._session.get = MagicMock(return_value=resp)

    data = await coordinator._async_update_data()

    assert data["state"] == "ui_running"
    assert data["current_app"] is None


async def test_update_data_app_running(hass, coordinator):
    resp = make_response(200, STATUS_APP_RUNNING)
    coordinator._session.get = MagicMock(return_value=resp)

    data = await coordinator._async_update_data()

    assert data["state"] == "app_running"
    assert data["current_app"]["id"] == "kodi"


async def test_update_data_http_error_raises(hass, coordinator):
    resp = make_response(500)
    coordinator._session.get = MagicMock(return_value=resp)

    with pytest.raises(UpdateFailed):
        await coordinator._async_update_data()


async def test_update_data_connection_error_raises(hass, coordinator):
    from aiohttp import ClientConnectionError
    coordinator._session.get = MagicMock(side_effect=ClientConnectionError("refused"))

    with pytest.raises(UpdateFailed):
        await coordinator._async_update_data()


async def test_async_post_success(hass, coordinator):
    resp = make_response(200, {"status": "ok"})
    coordinator._session.post = MagicMock(return_value=resp)

    result = await coordinator.async_post("/api/stop")

    assert result == {"status": "ok"}


async def test_async_post_no_body(hass, coordinator):
    resp = make_response(202, None)
    resp.content_length = 0
    coordinator._session.post = MagicMock(return_value=resp)

    result = await coordinator.async_post("/api/launch/kodi")

    assert result is None


async def test_async_post_raises_on_error(hass, coordinator):
    resp = make_response(409)
    coordinator._session.post = MagicMock(return_value=resp)

    with pytest.raises(Exception):
        await coordinator.async_post("/api/launch/kodi")


async def test_base_url_constructed(hass):
    with patch(
        "custom_components.launchscope.coordinator.async_get_clientsession",
        return_value=MagicMock(),
    ):
        coord = LauncherCoordinator(hass, "10.0.0.1", 9000, "key")
    assert coord.base_url == "http://10.0.0.1:9000"


async def test_headers_contain_api_key(hass):
    with patch(
        "custom_components.launchscope.coordinator.async_get_clientsession",
        return_value=MagicMock(),
    ):
        coord = LauncherCoordinator(hass, "host", 8765, "secret")
    assert coord.headers["X-Api-Key"] == "secret"
