"""Button entities for Launchscope."""

from __future__ import annotations

from homeassistant.components.button import ButtonEntity
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
    async_add_entities(
        [
            LaunchscopeStopButton(coordinator, entry),
            LaunchscopeCECActivateButton(coordinator, entry),
            LaunchscopeCECPowerOnButton(coordinator, entry),
            LaunchscopeCECSetSourceButton(coordinator, entry),
            LaunchscopeCECStandbyButton(coordinator, entry),
        ]
    )


class LaunchscopeStopButton(CoordinatorEntity, ButtonEntity):
    """Stop the current app and return to the launcher."""

    def __init__(self, coordinator: LauncherCoordinator, entry: ConfigEntry) -> None:
        super().__init__(coordinator)
        self._attr_unique_id = f"{entry.entry_id}_stop"
        self._attr_name = "Stop App"
        self._attr_icon = "mdi:stop"
        self._attr_device_info = _DEVICE(entry)

    @property
    def available(self) -> bool:
        data = self.coordinator.data or {}
        return data.get("state") == "app_running"

    async def async_press(self) -> None:
        await self.coordinator.async_post("/api/stop")
        await self.coordinator.async_request_refresh()


class LaunchscopeCECActivateButton(CoordinatorEntity, ButtonEntity):
    """Power on TV + AVR and switch to the host PC input via CEC."""

    def __init__(self, coordinator: LauncherCoordinator, entry: ConfigEntry) -> None:
        super().__init__(coordinator)
        self._attr_unique_id = f"{entry.entry_id}_cec_activate"
        self._attr_name = "Activate Launchscope"
        self._attr_icon = "mdi:television-play"
        self._attr_device_info = _DEVICE(entry)

    async def async_press(self) -> None:
        await self.coordinator.async_post("/api/cec/activate")


class LaunchscopeCECPowerOnButton(CoordinatorEntity, ButtonEntity):
    """Power on TV and AVR without switching input."""

    def __init__(self, coordinator: LauncherCoordinator, entry: ConfigEntry) -> None:
        super().__init__(coordinator)
        self._attr_unique_id = f"{entry.entry_id}_cec_power_on"
        self._attr_name = "Turn On TV"
        self._attr_icon = "mdi:power"
        self._attr_device_info = _DEVICE(entry)

    async def async_press(self) -> None:
        await self.coordinator.async_post("/api/cec/power-on")


class LaunchscopeCECSetSourceButton(CoordinatorEntity, ButtonEntity):
    """Set this device as the active source without powering on."""

    def __init__(self, coordinator: LauncherCoordinator, entry: ConfigEntry) -> None:
        super().__init__(coordinator)
        self._attr_unique_id = f"{entry.entry_id}_cec_set_source"
        self._attr_name = "Set as Active Source"
        self._attr_icon = "mdi:import"
        self._attr_device_info = _DEVICE(entry)

    async def async_press(self) -> None:
        await self.coordinator.async_post("/api/cec/set-source")


class LaunchscopeCECStandbyButton(CoordinatorEntity, ButtonEntity):
    """Send the AVR to standby via CEC."""

    def __init__(self, coordinator: LauncherCoordinator, entry: ConfigEntry) -> None:
        super().__init__(coordinator)
        self._attr_unique_id = f"{entry.entry_id}_cec_standby"
        self._attr_name = "Turn Off TV"
        self._attr_icon = "mdi:television-off"
        self._attr_device_info = _DEVICE(entry)

    async def async_press(self) -> None:
        await self.coordinator.async_post("/api/cec/standby")
