# CM-Items v1.1 Export Fix

Fixes export compatibility so both call styles work:

```lua
exports['cm-items'].IsInventoryItem('water')
exports['cm-items']:IsInventoryItem('water')
```

This prevents valid physical items like `water` from being rejected by `cm-inventory`.
