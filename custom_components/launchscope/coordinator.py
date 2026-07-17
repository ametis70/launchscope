"""DataUpdateCoordinator for Launchscope."""
from __future__ import annotations

import asyncio
import logging
from datetime import timedelta

import aiohttp
from homeassistant.core import HomeAssistant
from homeassistant.helpers.aiohttp_client import async_get_clientsession
from homeassistant.helpers.update_coordinator import DataUpdateCoordinator, UpdateFailed

from .const import DOMAIN

_LOGGER = logging.getLogger(__name__)


class LauncherCoordinator(DataUpdateCoordinator):
    def __init__(self, hass: HomeAssistant, host: str, port: int, api_key: str) -> None:
        self.base_url = f"http://{host}:{port}"
        self.headers  = {"X-Api-Key": api_key}
        self._session  = async_get_clientsession(hass)
        super().__init__(
            hass,
            _LOGGER,
            name=DOMAIN,
            update_interval=timedelta(seconds=30),
        )

    async def _async_update_data(self):
        try:
            async with asyncio.timeout(10):
                async with self._session.get(
                    f"{self.base_url}/api/status",
                    headers=self.headers,
                ) as resp:
                    resp.raise_for_status()
                    data = await resp.json()

                # Fetch CEC state — best-effort, don't fail the update if unavailable.
                try:
                    async with self._session.get(
                        f"{self.base_url}/api/cec/state",
                        headers=self.headers,
                        timeout=aiohttp.ClientTimeout(total=5),
                    ) as cec_resp:
                        if cec_resp.status == 200:
                            data["cec"] = await cec_resp.json()
                except Exception:
                    pass

                return data
        except Exception as err:
            raise UpdateFailed(f"Error communicating with launchscoped: {err}") from err

    async def async_post(self, path: str, payload: dict | None = None):
        """Fire-and-forget POST; returns the JSON response or raises."""
        async with asyncio.timeout(10):
            async with self._session.post(
                f"{self.base_url}{path}",
                headers=self.headers,
                json=payload or {},
            ) as resp:
                resp.raise_for_status()
                if resp.content_length:
                    return await resp.json()
                return None
