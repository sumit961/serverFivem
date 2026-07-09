# Test Steps — cm-admin v2.6.0

## Restart Order
```cfg
restart cm-ui
restart cm-core
restart cm-auth
restart cm-playerdata
restart cm-characters
restart cm-climatime
restart cm-spawn
restart cm-hud
restart cm-admin
```

## Admin Mode
1. Join the server and select your character.
2. Type `/admin`.
3. Confirm success notification appears.
4. Press `F11`.
5. Confirm admin menu opens.
6. Type `/admin` again.
7. Confirm menu closes and noclip is disabled.

## GPS Teleport
1. Enable `/admin`.
2. Open the GTA map and set a waypoint.
3. Press `F11` > Dashboard > `GPS Teleport`, or type `/cmtp`.
4. Confirm player teleports to the waypoint safely.
5. Test without a waypoint and confirm it shows an error instead of teleporting.

## Noclip Invisibility
1. Enable `/admin`.
2. Press `F2` or use `/noclip`.
3. Confirm admin becomes invisible while clipping.
4. Press `F2` again.
5. Confirm player becomes visible again and is placed safely on ground.

## Admin Head Tag
1. Use two clients.
2. Client A enables `/admin`.
3. Client B stands near Client A.
4. Confirm Client B sees overhead text like:
   `Administrator` and `Name (Character ID)`.
5. Confirm no server ID appears in the overhead tag.
6. Client A disables `/admin`.
7. Confirm overhead admin tag disappears.

## Live Map
1. Enable `/admin` and press `F11`.
2. Open the Map tab.
3. Confirm the GTA map background loads.
4. Confirm online players show on the map.
5. Toggle Vehicles on and confirm vehicle blips appear only if rank has `map.vehicles` or `vehicles.view`.
6. Confirm logged-in admins are highlighted only if rank has `map.admins` or `admins.view`.
7. Drag map, zoom with wheel, and click a player blip.
8. Confirm clicking player opens their profile.

## Developer Launchers
1. Give your rank `dev.view` and the specific tool permission, for example `dev.climatime`.
2. Open Developer tab.
3. Click Climatime Admin > Run.
4. Confirm admin menu closes and Climatime opens cleanly.
5. Register a tool from another resource and confirm it appears without editing `cm-admin`.

## Rank Permission Builder
1. Open Ranks tab as owner/head admin.
2. Select a rank.
3. Drag a permission into Assigned permissions.
4. Click `×` to remove a permission.
5. Save rank.
6. Restart `cm-admin` and confirm the permission persisted.

## Logs
1. Open Logs tab.
2. Confirm only categories allowed by the rank are visible.
3. Use a player action, money action, GPS TP, dev tool, or external resource log.
4. Confirm the log appears in the correct category.

## Performance Checks
1. Keep F8 open during map refresh.
2. Confirm no reliable network event overflow appears.
3. Confirm no constant console spam appears.
4. Confirm map vehicle scan only happens when Vehicles toggle is on.
5. Confirm no `forbidden blur CSS` is used.
