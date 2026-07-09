# Test Steps - CM Climatime v1.7.2

1. Restart `cm-climatime`.
2. Open `/climatime` and go to Zones.
3. Confirm the zone form is hidden at first.
4. Click the map and confirm the new zone form appears.
5. Confirm there is no visible weather dropdown.
6. Select `All-Time Weather`, click a weather chip, save, and confirm the zone keeps that weather.
7. Select `Dynamic Weather Rotation` or `Mixed Weather Pool` and confirm Rotation min appears.
8. Confirm map marker alignment matches the calibrated admin map bounds.
9. Set manual time speed to `0.5` or `1.5` using admin/dev action and confirm time no longer freezes/snaps backward after sync.
