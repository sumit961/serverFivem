# cm-climatime v1.7.0 Test Steps

## Restart order

```cfg
restart cm-ui
restart cm-core
restart cm-auth
restart cm-playerdata
restart cm-characters
restart cm-climatime
restart cm-spawn
restart cm-hud
```

## Required ensure order

```cfg
ensure cm-ui
ensure oxmysql
ensure cm-core
ensure cm-auth
ensure cm-playerdata
ensure cm-characters
ensure cm-climatime
ensure cm-spawn
ensure cm-hud
ensure cm-admin
```

## Test 1 - No gameplay notification spam

1. Join the server normally.
2. Open `/climatime` as admin.
3. Change global weather from Clear to Rain or Thunder.
4. Confirm normal gameplay does not show GTA feed notifications such as `Weather Forecast` or `Local Weather`.
5. Confirm admin feedback appears only inside the Climatime UI toast when the panel is open.

## Test 2 - Weather prepared before spawn card click

1. Set Climatime to a clear obvious weather/time, for example Thunder or midnight.
2. Log out/back in or return to character selector.
3. Select a character and go to the `cm-spawn` page.
4. Before clicking Last Location or Hotel, check that the sky/time is already prepared behind the spawn screen/transition.
5. Click Last Location or Hotel.
6. Confirm there is no visible post-spawn sky/time snap after the player appears.

## Test 3 - Dead player spawn override still works

1. Kill a character and save death state using `cm-playerdata`.
2. Rejoin and select that character.
3. Click any spawn card.
4. Confirm the player is forced to the saved death/body location with deathscreen still active.
5. Confirm Climatime does not override this flow or reveal the player early.

## Test 4 - Zone weather before final reveal

1. Create a weather zone with a clearly different weather, for example Snow in Paleto.
2. Save and enable zones.
3. Make Last Location or a future spawn card resolve inside that zone.
4. Select the spawn.
5. Confirm the zone weather is prepared before the player reveal.

## Test 5 - Bigger admin UI and map interaction

1. Open `/climatime`.
2. Confirm the panel is larger and uses CM blue/cyan style.
3. Go to Zones.
4. Click the map to set a center.
5. Drag the center marker.
6. Drag the radius handle.
7. Use zoom buttons and mouse wheel zoom.
8. Press `Use My Position` and confirm coordinates update.
9. Save the zone and confirm it appears in the list and on the map.

## Test 6 - Performance sanity

1. Keep `/climatime` closed during normal gameplay.
2. Watch server/client console for spam.
3. Confirm there are no repeated weather notification messages.
4. Open the map and drag/zoom; confirm no heavy hitching.
5. Close the panel and confirm UI timers/map updates stop doing visible work.
