# Prism CarPlay

Prism CarPlay is a FiveM vehicle tablet resource that provides vehicle
controls, media playback, navigation, lighting, tuning, neon controls and
dashcam recordings.

## Resource layout

```text
client/
  main.lua       vehicle state, tablet lifecycle and NUI callbacks
  sound.lua      media/audio state and NUI audio callbacks
server/
  main.lua       dashcam storage, HTTP delivery and recording events
  sound.lua      server-side audio synchronisation
  items.lua      usable CarPlay/tuner items
  server.js      optional Fivemanage upload/delete bridge
config.lua       editable gameplay and UI configuration
locales/         translation tables
web/
  index.html     active editable NUI shell
  styles.css     active design system and responsive layout
  src/           editable state, views, NUI bridge and audio manager
  dist/          original compiled frontend retained as a fallback/asset store
```

The original web package was supplied without its React/Vite source tree. The
resource now uses a clean, build-free frontend under `web/src/` and
`web/styles.css`, while the original compiled bundle remains under `web/dist/`
as a fallback and continues to provide the existing map, image and music
assets. The new frontend preserves the Lua callback/message contract, so UI
changes can be made without editing the gameplay layer.

## Configuration

Edit `config.lua` for normal resource settings. The default primary colour is
CM cyan (`#00D1FF`). Notification and seatbelt integrations are intentionally
kept as small bridge functions near the top of the file.

For Fivemanage dashcam uploads, add this to the server-only `server.cfg`:

```cfg
set prism_carplay_fivemanage_api_key "YOUR_API_KEY"
```

Do not put this key in `config.lua`. That file is loaded as a shared script and
would expose the key to clients.

## Deployment notes

- Do not deploy `node_modules`; the resource only needs the declared server
  dependency when the Node bridge is used.
- Keep the `web/dist` asset filenames referenced by `index.html` in sync if a
  new web build is introduced.
- `Config.Dashcam.storageType = 'local'` avoids the Fivemanage integration.
- The dashcam directory is writable at runtime and is not intended for source
  control.

## Safe extension points

1. Add integrations in the bridge functions in `config.lua`.
2. Add translations in `locales/en.lua` and `locales/es.lua`.
3. Change visual design in `web/styles.css`.
4. Change screens and behaviour in `web/src/views.js` and `web/src/app.js`.
5. Add server-only upload providers beside `server/server.js` rather than
   putting credentials in shared Lua.
