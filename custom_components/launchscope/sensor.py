"""Sensor entities for Launchscope."""
from __future__ import annotations

from homeassistant.components.sensor import SensorEntity
from homeassistant.config_entries import ConfigEntry
from homeassistant.core import HomeAssistant
from homeassistant.helpers.entity_platform import AddEntitiesCallback
from homeassistant.helpers.update_coordinator import CoordinatorEntity

from .const import DOMAIN
from .coordinator import LauncherCoordinator


async def async_setup_entry(
    hass: HomeAssistant,
    entry: ConfigEntry,
    async_add_entities: AddEntitiesCallback,
) -> None:
    coordinator: LauncherCoordinator = hass.data[DOMAIN][entry.entry_id]
    async_add_entities([LaunchscopeCurrentAppSensor(coordinator, entry)])


class LaunchscopeCurrentAppSensor(CoordinatorEntity, SensorEntity):
    def __init__(self, coordinator: LauncherCoordinator, entry: ConfigEntry) -> None:
        super().__init__(coordinator)
        self._attr_unique_id   = f"{entry.entry_id}_current_app"
        self._attr_name        = "Current App"
        self._attr_icon        = "mdi:apps"
        self._attr_device_info = {
            "identifiers": {(DOMAIN, entry.entry_id)},
            "name": "Launchscope",
            "manufacturer": "Launchscope",
        }

    @property
    def native_value(self) -> str:
        data = self.coordinator.data or {}
        app = data.get("current_app")
        return app.get("id", "idle") if app else "idle"

    @property
    def extra_state_attributes(self) -> dict:
        data = self.coordinator.data or {}
        app = data.get("current_app")
        return {
            "app_name": app.get("name") if app else None,
            "state": data.get("state"),
        }
