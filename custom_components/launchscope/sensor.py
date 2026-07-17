"""Sensor entities for Launchscope."""
from __future__ import annotations

from homeassistant.components.sensor import SensorEntity
from homeassistant.config_entries import ConfigEntry
from homeassistant.core import HomeAssistant
from homeassistant.helpers.entity_platform import AddEntitiesCallback
from homeassistant.helpers.update_coordinator import CoordinatorEntity

from .const import DOMAIN
from .coordinator import LauncherCoordinator

_DEVICE = lambda entry: {
    "identifiers": {(DOMAIN, entry.entry_id)},
    "name": "Launchscope",
    "manufacturer": "Launchscope",
}


async def async_setup_entry(
    hass: HomeAssistant,
    entry: ConfigEntry,
    async_add_entities: AddEntitiesCallback,
) -> None:
    coordinator: LauncherCoordinator = hass.data[DOMAIN][entry.entry_id]
    async_add_entities([
        LaunchscopeCurrentAppSensor(coordinator, entry),
        LaunchscopeCECTVSensor(coordinator, entry),
        LaunchscopeCECAVRSensor(coordinator, entry),
        LaunchscopeCECActiveSourceSensor(coordinator, entry),
    ])


class LaunchscopeCurrentAppSensor(CoordinatorEntity, SensorEntity):
    def __init__(self, coordinator: LauncherCoordinator, entry: ConfigEntry) -> None:
        super().__init__(coordinator)
        self._attr_unique_id   = f"{entry.entry_id}_current_app"
        self._attr_name        = "Current App"
        self._attr_icon        = "mdi:apps"
        self._attr_device_info = _DEVICE(entry)

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


class LaunchscopeCECTVSensor(CoordinatorEntity, SensorEntity):
    """Binary sensor for TV power state reported by cec-uinput."""

    def __init__(self, coordinator: LauncherCoordinator, entry: ConfigEntry) -> None:
        super().__init__(coordinator)
        self._attr_unique_id   = f"{entry.entry_id}_cec_tv_on"
        self._attr_name        = "TV Power"
        self._attr_icon        = "mdi:television"
        self._attr_device_info = _DEVICE(entry)

    @property
    def native_value(self) -> str | None:
        cec = (self.coordinator.data or {}).get("cec")
        if cec is None:
            return None
        return "on" if cec.get("tv_on") else "off"


class LaunchscopeCECAVRSensor(CoordinatorEntity, SensorEntity):
    """Binary sensor for AVR power state reported by cec-uinput."""

    def __init__(self, coordinator: LauncherCoordinator, entry: ConfigEntry) -> None:
        super().__init__(coordinator)
        self._attr_unique_id   = f"{entry.entry_id}_cec_avr_on"
        self._attr_name        = "AVR Power"
        self._attr_icon        = "mdi:amplifier"
        self._attr_device_info = _DEVICE(entry)

    @property
    def available(self) -> bool:
        cec = (self.coordinator.data or {}).get("cec")
        return cec is not None and cec.get("avr_on") is not None

    @property
    def native_value(self) -> str | None:
        cec = (self.coordinator.data or {}).get("cec")
        if not self.available:
            return None
        return "on" if cec.get("avr_on") else "off"


class LaunchscopeCECActiveSourceSensor(CoordinatorEntity, SensorEntity):
    """Sensor for the active CEC source logical address."""

    def __init__(self, coordinator: LauncherCoordinator, entry: ConfigEntry) -> None:
        super().__init__(coordinator)
        self._attr_unique_id   = f"{entry.entry_id}_cec_active_source"
        self._attr_name        = "CEC Active Source"
        self._attr_icon        = "mdi:hdmi-port"
        self._attr_device_info = _DEVICE(entry)

    @property
    def native_value(self) -> int | None:
        cec = (self.coordinator.data or {}).get("cec")
        if cec is None:
            return None
        return cec.get("active_source")

    @property
    def extra_state_attributes(self) -> dict:
        cec = (self.coordinator.data or {}).get("cec") or {}
        return {"is_active_source": cec.get("is_active_source")}
