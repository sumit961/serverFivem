# CM Admin map integration

`cm-admin` owns the calibrated bounds for `ui/assets/gta-map-local.png`.

Server resources can read the effective bounds (saved bounds when enabled,
otherwise `Config.Map.Bounds`) without receiving admin/player data:

```lua
local bounds, source = exports['cm-admin']:GetMapBounds()
```

`bounds` contains `minX`, `maxX`, `minY`, and `maxY`. `source` is either
`saved` or `config`.
