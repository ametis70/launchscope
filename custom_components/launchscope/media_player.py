"""Media player entity for Launchscope."""

from __future__ import annotations

import logging

import aiohttp
from homeassistant.components.media_player import (
    MediaPlayerDeviceClass,
    MediaPlayerEntity,
    MediaPlayerEntityFeature,
    MediaPlayerState,
)
from homeassistant.config_entries import ConfigEntry
from homeassistant.core import HomeAssistant, callback
from homeassistant.helpers.entity_platform import AddEntitiesCallback
from homeassistant.helpers.update_coordinator import CoordinatorEntity

from .const import DOMAIN
from .coordinator import LauncherCoordinator

_LOGGER = logging.getLogger(__name__)

SUPPORTED = (
    MediaPlayerEntityFeature.SELECT_SOURCE
    | MediaPlayerEntityFeature.STOP
    | MediaPlayerEntityFeature.VOLUME_SET
    | MediaPlayerEntityFeature.VOLUME_MUTE
    | MediaPlayerEntityFeature.VOLUME_STEP
)


async def async_setup_entry(
    hass: HomeAssistant,
    entry: ConfigEntry,
    async_add_entities: AddEntitiesCallback,
) -> None:
    coordinator: LauncherCoordinator = hass.data[DOMAIN][entry.entry_id]
    async_add_entities([LaunchscopeMediaPlayer(coordinator, entry)])


class LaunchscopeMediaPlayer(CoordinatorEntity, MediaPlayerEntity):
    _attr_device_class = MediaPlayerDeviceClass.TV

    def __init__(self, coordinator: LauncherCoordinator, entry: ConfigEntry) -> None:
        super().__init__(coordinator)
        self._attr_unique_id = f"{entry.entry_id}_media_player"
        self._attr_name = "Launchscope"
        self._attr_icon = "mdi:television-play"
        self._attr_supported_features = SUPPORTED
        self._attr_device_info = {
            "identifiers": {(DOMAIN, entry.entry_id)},
            "name": "Launchscope",
            "manufacturer": "Launchscope",
        }
        self._apps: list[dict] = []

    async def async_added_to_hass(self) -> None:
        await super().async_added_to_hass()
        await self._fetch_apps()
        self.async_write_ha_state()

    async def _fetch_apps(self) -> None:
        try:
            async with self.coordinator._session.get(
                f"{self.coordinator.base_url}/api/apps",
                headers=self.coordinator.headers,
                timeout=aiohttp.ClientTimeout(total=10),
            ) as resp:
                if resp.status == 200:
                    apps = await resp.json()
                    if apps != self._apps:
                        self._apps = apps
                        _LOGGER.debug(
                            "Loaded %d apps: %s", len(self._apps), [a["name"] for a in self._apps]
                        )
                else:
                    _LOGGER.warning("GET /api/apps returned HTTP %s", resp.status)
        except Exception as err:
            _LOGGER.warning("Failed to fetch apps: %s", err)

    @callback
    def _handle_coordinator_update(self) -> None:
        """Re-fetch app list on every coordinator update."""
        self.hass.async_create_task(self._fetch_apps_and_update())

    async def _fetch_apps_and_update(self) -> None:
        await self._fetch_apps()
        self.async_write_ha_state()

    @property
    def _data(self) -> dict:
        return self.coordinator.data or {}

    @property
    def state(self) -> MediaPlayerState:
        s = self._data.get("state", "")
        if s == "app_running":
            return MediaPlayerState.ON
        if s:
            return MediaPlayerState.IDLE
        return MediaPlayerState.OFF

    @property
    def app_name(self) -> str | None:
        app = self._data.get("current_app")
        return app.get("name") if app else None

    @property
    def source(self) -> str | None:
        app = self._data.get("current_app")
        return app.get("name") if app else None

    @property
    def source_list(self) -> list[str]:
        return [a["name"] for a in self._apps]

    @property
    def volume_level(self) -> float | None:
        audio = self._data.get("audio")
        if audio:
            return min(audio.get("volume", 0.0), 1.0)
        return None

    @property
    def is_volume_muted(self) -> bool | None:
        audio = self._data.get("audio")
        return audio.get("muted") if audio else None

    async def async_set_volume_level(self, volume: float) -> None:
        await self.coordinator.async_post("/api/audio/volume", {"value": volume})

    async def async_mute_volume(self, mute: bool) -> None:
        await self.coordinator.async_post("/api/audio/mute", {"muted": mute})

    async def async_volume_up(self) -> None:
        await self.coordinator.async_post("/api/audio/volume", {"delta": 0.05})

    async def async_volume_down(self) -> None:
        await self.coordinator.async_post("/api/audio/volume", {"delta": -0.05})

    async def async_select_source(self, source: str) -> None:
        app_id = next((a["id"] for a in self._apps if a["name"] == source), None)
        if not app_id:
            _LOGGER.error(
                "Unknown source '%s', available: %s", source, [a["name"] for a in self._apps]
            )
            await self._fetch_apps()
            app_id = next((a["id"] for a in self._apps if a["name"] == source), None)
            if not app_id:
                return
        await self.coordinator.async_post(f"/api/launch/{app_id}")
        await self.coordinator.async_request_refresh()

    async def async_media_stop(self) -> None:
        await self.coordinator.async_post("/api/stop")
        await self.coordinator.async_request_refresh()
