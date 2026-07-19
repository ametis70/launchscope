"""Tests for the config flow."""

from __future__ import annotations

from unittest.mock import MagicMock, patch

import pytest

from custom_components.launchscope.const import CONF_API_KEY, CONF_HOST, CONF_PORT, DOMAIN
from tests.conftest import ENTRY_DATA, make_response


@pytest.fixture(autouse=True)
def auto_enable_custom_integrations(enable_custom_integrations):
    """Enable custom integrations for all tests in this module."""


async def test_flow_success(hass):
    resp = make_response(200, {"state": "ui_running"})

    with patch(
        "custom_components.launchscope.config_flow.async_get_clientsession",
        return_value=MagicMock(get=MagicMock(return_value=resp)),
    ):
        result = await hass.config_entries.flow.async_init(DOMAIN, context={"source": "user"})
        assert result["type"] == "form"

        result = await hass.config_entries.flow.async_configure(
            result["flow_id"], user_input=ENTRY_DATA
        )

    assert result["type"] == "create_entry"
    assert result["title"] == f"Launchscope ({ENTRY_DATA[CONF_HOST]})"
    assert result["data"][CONF_HOST] == ENTRY_DATA[CONF_HOST]
    assert result["data"][CONF_PORT] == ENTRY_DATA[CONF_PORT]
    assert result["data"][CONF_API_KEY] == ENTRY_DATA[CONF_API_KEY]


async def test_flow_invalid_auth(hass):
    resp = make_response(401)

    with patch(
        "custom_components.launchscope.config_flow.async_get_clientsession",
        return_value=MagicMock(get=MagicMock(return_value=resp)),
    ):
        result = await hass.config_entries.flow.async_init(DOMAIN, context={"source": "user"})
        result = await hass.config_entries.flow.async_configure(
            result["flow_id"], user_input=ENTRY_DATA
        )

    assert result["type"] == "form"
    assert result["errors"]["base"] == "invalid_auth"


async def test_flow_cannot_connect_non_200(hass):
    resp = make_response(503)

    with patch(
        "custom_components.launchscope.config_flow.async_get_clientsession",
        return_value=MagicMock(get=MagicMock(return_value=resp)),
    ):
        result = await hass.config_entries.flow.async_init(DOMAIN, context={"source": "user"})
        result = await hass.config_entries.flow.async_configure(
            result["flow_id"], user_input=ENTRY_DATA
        )

    assert result["type"] == "form"
    assert result["errors"]["base"] == "cannot_connect"


async def test_flow_cannot_connect_exception(hass):
    from aiohttp import ClientConnectionError

    with patch(
        "custom_components.launchscope.config_flow.async_get_clientsession",
        return_value=MagicMock(get=MagicMock(side_effect=ClientConnectionError("refused"))),
    ):
        result = await hass.config_entries.flow.async_init(DOMAIN, context={"source": "user"})
        result = await hass.config_entries.flow.async_configure(
            result["flow_id"], user_input=ENTRY_DATA
        )

    assert result["type"] == "form"
    assert result["errors"]["base"] == "cannot_connect"


async def test_flow_shows_form_initially(hass):
    result = await hass.config_entries.flow.async_init(DOMAIN, context={"source": "user"})
    assert result["type"] == "form"
    assert result["step_id"] == "user"
    assert "errors" not in result or result["errors"] == {}
