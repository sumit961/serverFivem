# CM Characters v1.6.1 - Production Quiet Logs

This patch keeps `cm-characters` production-safe by hiding normal selector/preview debug logs unless debugging is explicitly enabled.

## Default behaviour

With the default config:

```lua
Config.Debug = false
Config.VerboseLogs = false
Config.ProductionMode = true
```

Normal logs such as selector scene loading, dummy ped spawn, cleanup, slot refresh, and world lock ON/OFF are suppressed.

Warnings and errors still print.

## Enable debug logs temporarily

In `config.lua` set either:

```lua
Config.Debug = true
```

or:

```lua
Config.VerboseLogs = true
```

Then restart `cm-characters`.

## Notes

The `THREE.WebGLRenderer` message comes from `screenshot-basic`, not from `cm-characters`. It is normally harmless.
