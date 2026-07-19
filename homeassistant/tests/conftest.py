"""Shared fixtures for launchscope tests."""

from __future__ import annotations

from unittest.mock import AsyncMock, MagicMock, patch

import pytest
from homeassistant.core import HomeAssistant

from custom_components.launchscope.const import CONF_API_KEY, CONF_HOST, CONF_PORT

pytest_plugins = "pytest_homeassistant_custom_component"


ENTRY_DATA = {
    CONF_HOST: "192.168.1.100",
    CONF_PORT: 8765,
    CONF_API_KEY: "testkey",
}

STATUS_IDLE = {
    "state": "ui_running",
    "current_app": None,
    "audio": {"volume": 0.72, "muted": False, "sink_name": "HDMI Audio"},
}

STATUS_APP_RUNNING = {
    "state": "app_running",
    "current_app": {"id": "kodi", "name": "Kodi"},
    "audio": {"volume": 0.50, "muted": False, "sink_name": "HDMI Audio"},
}

APPS_LIST = [
    {"id": "kodi", "name": "Kodi"},
    {"id": "moonlight", "name": "Moonlight"},
]


def make_response(status: int, json_data=None):
    """Build a mock aiohttp response."""
    resp = AsyncMock()
    resp.status = status
    resp.content_length = len(str(json_data)) if json_data is not None else 0
    resp.raise_for_status = MagicMock()
    if status >= 400:
        from aiohttp import ClientResponseError

        resp.raise_for_status.side_effect = ClientResponseError(
            request_info=MagicMock(), history=(), status=status
        )
    resp.json = AsyncMock(return_value=json_data)
    resp.__aenter__ = AsyncMock(return_value=resp)
    resp.__aexit__ = AsyncMock(return_value=False)
    return resp


@pytest.fixture
def mock_session():
    """Return a mock aiohttp ClientSession."""
    session = MagicMock()
    session.get = MagicMock()
    session.post = MagicMock()
    return session
