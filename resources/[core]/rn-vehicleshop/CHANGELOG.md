# rn-vehicleshop — Production Cleanup & Fix Changelog

## 1. Code cleanup (client/client.lua, client/capture.lua)
- Removed ALL debug/dev commands and their helper functions:
  - capture.lua: vehgreen, vehgreenpos, vehgreenup, vehgreendown, vehgreenz,
    vehgreenscale, vehgreendel, vehcarpos, vehadminhide, vehadminshow,
    vehcarforward/back/left/right/up/down, vehcarheading, vehcarrotate,
    vehcarground, vehcarhere, plus the debug onResourceStop and helpers
    (debugGreenProp, notifyAndPrint, coordsToVector4Line, studio-move helpers).
  - client.lua: vehcoords, vehcampos, vehcamgreen, vehcamplayer, vehcamset, mycar
    and their camera helper functions.
- Validated: no orphaned references remain; Lua compiles cleanly.

## 2. fxmanifest.lua
- Removed `this_is_a_map 'yes'` — it conflicts with a resource that also runs
  client/server scripts and can break script load order. Streamed map still loads
  from stream/ automatically.

## 3. Test drive (client/client.lua) — ownership/key bypass
- Test-drive vehicle now gets a non-ownership plate (TESTDRV##), state-bag flags
  (cmTestDrive, cmIgnoreOwnership, cmTempAccess, cmPlate), SetVehicleNeedsToBeHotwired
  false, SetVehicleHasBeenOwnedByPlayer true, and a best-effort cm-vehiclekeys temp key.
  This stops "you do not own this car / no key" during a test drive.
- Test-drive cars are local only and deleted when the drive ends (never saved as owned).
- HUD is shown during the drive and hidden again on return to the showroom.

## 4. HUD + notifications (client/client.lua)
- Added a cm-hud notification wrapper with a safe fallback (exports['cm-hud']:Notify
  -> AddNotification -> NUI toast). Native GTA feed notifications removed.
- HUD + minimap are hidden while in store/admin/capture UI, restored on exit and
  during test drive.
- Purchase notification is deferred ~1.4s until AFTER the store closes, shown once.

## 5. Store exit flow (config.lua, client/client.lua)
- Config.ExitLocation set to the exact requested spot:
  vector4(-2264.3823, 392.3130, 174.6739, 263.2466).
- Store exit uses exact-Z placement (no ground-snap) so the player does not fall
  through the MLO floor. Camera destroyed, player unfrozen + visible + collision on,
  NUI focus cleared, HUD restored, routing bucket left, fades resolved.

## 6. Image capture (client/capture.lua)
- Before each screenshot: forces noon + EXTRASUNNY + no cloud shadows + a flat,
  bright studio timecycle (CAMERA_BRIGHTNESS_AND_CONTRAST) and cleans the car, for
  even lighting with minimal shadow. Lighting is reverted to the studio default after.
- Capture keeps the existing vehicle position, green-screen prop position, and camera
  angle (fixedCoords / scale / studio vehicle unchanged, as requested).

## 7. Crop modal (ui/main.js, ui/style.css, client/capture.lua)
- Admin panel is hidden while the crop modal is open and pointer-events are disabled
  on it; crop modal sits at max z-index and keeps mouse focus (cropModalFocus NUI
  callback re-asserts SetNuiFocus). Admin panel and its focus return on close/cancel.
- Crop output is downscaled to a 640px max side (transparent PNG) to optimise store
  loading; aspect ratio preserved, high-quality smoothing.

## 8. UI styling (ui/style.css, ui/index.html)
- Removed solid/near-black backgrounds across store + admin:
  #main is now transparent (vehicle visible), store side panels and admin panels use
  translucent glass (blur). 
- Admin panel redesigned: transparent center (car visible), left-docked glass panel
  with the catalog list/search on top and the settings form below, modern blue buttons.
- ESC behaviour: crop modal -> dealer dialog -> admin -> submenu back -> close store.
  Added an on-screen ESC hint while the store/admin UI is open.

## 9. Interaction prompt
- The [E] prompt is hidden immediately on E-press (local guard set the same frame) and
  when the store/admin view opens, so it never lingers behind the menu. It returns only
  when the player is back near the dealer.

## Notes / things requiring your server to confirm
- cm-hud notify export name is wrapped defensively; if your cm-hud uses a different
  export, tell me and I will match it exactly.
- Test-drive key bypass uses common cm-vehicles/cm-vehiclekeys conventions; if your
  build uses a specific temp-key export, share it and I will wire it precisely.
