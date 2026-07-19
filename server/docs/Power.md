# System Power Actions

`launchscoped` handles shutdown, restart, and suspend via `POST /api/system/power`. It executes `systemctl poweroff`, `systemctl reboot`, or `systemctl suspend` directly as the user it runs under.

On non-NixOS systems the HTPC user needs permission to run these commands without a password. Grant it via a polkit rule:

```javascript
// /etc/polkit-1/rules.d/10-htpc-power.rules
polkit.addRule(function(action, subject) {
    if ((action.id == "org.freedesktop.login1.power-off" ||
         action.id == "org.freedesktop.login1.reboot"   ||
         action.id == "org.freedesktop.login1.suspend")  &&
        subject.user == "htpc") {
        return polkit.Result.YES;
    }
});
```

Replace `"htpc"` with the actual username `launchscoped` runs as.

On NixOS this is handled automatically — `systemd-logind` grants session owners permission to power off and suspend without polkit escalation.
