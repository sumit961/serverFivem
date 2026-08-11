# Validation report

Build: `2.18.0-final-crop-preview`

Completed before packaging:

- Parsed every modified Lua file with `luaparse` after normalising FiveM's
  backtick-hash syntax for the generic parser.
- Checked `web/app.js` with Node's syntax checker.
- Checked all HTML IDs for duplicates.
- Executed the real NUI background-removal, crop, PNG encode, and WebP encode
  functions against synthetic 128×128 green-screen frames.
- Confirmed the manifest no longer registers global freemode head replacements;
  only the local green-screen prop is streamed.
- Confirmed the capture code contains no RCore, screenshot-upload, HTTP image API,
  or `SaveResourceFile('cm-items', ...)` path.
- Confirmed the nine DOCX position screenshots are mapped to their nv_cloth
  categories; watches share the bracelet composition and bags keep rear framing.
- Parsed every Lua file again after adding wrist-bone camera targeting; checked
  `web/app.js` with Node's syntax checker.
- Confirmed the optional **Adjust Position & Take Image** editor exposes player
  movement/rotation, camera orbit/position/FOV, a square frame guide, and
  persistent category composition; normal capture does not pause in the editor.
- Confirmed capture freezes both the disposable ped and hidden real player,
  suppresses gameplay movement, and restores the original frozen state in every
  normal, cancel, failure, watchdog, and resource-stop cleanup path.
- Confirmed the capture ped uses a zero-speed, fixed-time character-creation pose;
  secondary facial/body animation and IK are disabled and the animation frame is
  reasserted each render tick until every cleanup path restores normal time.
- Confirmed inventory capture is hard-wired to `allowEmptyHeadDrawable` native
  ghost isolation and contains exactly one screenshot request. The baseline/body-
  subtraction processor and runtime fallback were removed.
- Confirmed the client requests `allowEmptyHeadDrawable true` automatically at
  resource start and again before capture, and fails closed if drawable `-1` is
  unavailable.
- Confirmed Body Part Browser, Clothing Visibility, Capture Position, angle/Z,
  and invisible-head test UI/code are absent from the packaged resource.
- Confirmed component-index metadata overrides ambiguous legacy `shirt` labels:
  component 8 is Shirts and component 11 is Outerwear. Capture retries retain an
  immutable copy of their starting category/drawable/gender.
- Confirmed Shirts, Outerwear, and Armor use a transform-only time freeze without
  applying the shoulder-changing character-creation pose animation.
- Confirmed the crop editor opens only from **Set Crop for This Category** and the
  canonical saved crop is reused silently for every drawable/texture, adjusted
  shot, bulk run, and future session.
- Confirmed the current texture is frozen before asynchronous preview work and
  remains identical through native preview, capture payload, retry, and filename.
- Confirmed a crop-editor request is consumed before the editor opens, preventing
  retry or save completion from asking for the same category crop again.
- Confirmed the visible capture preview is assigned after category crop processing;
  it now uses the same final data URL passed to PNG/WebP encoding and saving.

The container cannot launch a FiveM game client, so native rendering must still
be smoke-tested on the target server. The runtime pipeline is fail-closed: it
does not report success unless native drawable/texture readback matches, the
screenshot processes to a non-empty image, PNG/WebP signatures validate, and both
files are written.

Recommended first server test:

1. Restart `screenshot-basic`, then `nv_cloth` (also clears old streamed-ped cache).
2. Open `/clothingadmin`.
3. Capture one hat, watch, bracelet, shoe, pants, and torso texture.
4. Inspect `generated_images/` for matching `.png` and `.webp` pairs.
5. Run a small category before starting the complete male/female export.

## Build 2.19.1-store-manager-fix

- Parsed every Lua file (server, shared, all clients including the new
  `client/cl_manage.lua`) with luac 5.4 after normalising backtick-hash syntax.
- Checked `web/app.js` with Node's syntax checker; confirmed all HTML IDs are
  unique and no getElementById reference was orphaned by the fit-helper rework
  (the two pre-existing dead refs `bulkEnableBtn`/`bulkDisableBtn` from 2.18
  remain null-guarded).
- Executed a functional harness against the real `app.js` in a stub DOM:
  manage-row grouping (whole-drawable row wins over per-texture rows), gender /
  category / published / unpublished / org / no-image / search filters, image
  URL resolution (generated_images → nui://nv_cloth, ui/images → nui://cm-items,
  nui/http/data passthrough), save payload construction (label/price/org/
  published/textureId -1), the publish guard (a clothe without an image cannot
  be published and posts nothing), applyManageSaved row replacement, retake
  preselect safety while the shop is closed, and the arms display text.
- Executed the extracted server helpers under Lua 5.4: managed shop list
  includes every Config.OrgShops locker; org extraction from shop names; new
  captures save unpublished; retakes preserve publish state, org shop, price,
  label, and required_job; unpublished stays unpublished; hidden/event rows
  keep their hidden flag.
- Confirmed NUI callbacks in `cl_manage.lua` answer immediately and run any
  Wait-bearing work (model load, scene teardown, admin-panel handoff) in
  CreateThread.
- Confirmed `/clothingstore`, `/orgcloset`, and the manage save/get events are
  server-gated (isClothingAdmin / Config.OrgShops job check); the org locker
  shop key is derived server-side from the verified job, never from the client.
- Confirmed all capture-camera/crop schema additions use a column-existence check
  and do not execute `ALTER TABLE ... ADD COLUMN` on an existing column.
- Confirmed the early admin-save handler closes over forward-declared
  `findExistingManagedRow` and `preserveManagedState` locals.
- Confirmed a stale/open shop is closed before the manager scene opens rather
  than causing `/clothingstore` to return without opening anything.

Requires an in-game smoke test (the container cannot run FiveM):
1. `/clothingstore` → Outerwear: select the card, cycle body/arms and
   undershirt, then SAVE TORSO FIT.
2. Capture one item → confirm it appears in `/clothingstore` as SAVED (grey badge)
   and does NOT appear in the player store.
3. `/clothingstore`: publish it with a price → confirm it appears in the store.
4. Assign it to ems → confirm it leaves the public store and `/orgcloset` shows
   it for an ems character only.
5. RETAKE IMAGE on a female clothe while on a male admin character → confirm the
   model swaps, the admin panel opens preselected, and closing it restores the
   original character model and outfit.

## Historical Build 2.20.0 (superseded by 2.21)

- Validate the MALE/FEMALE admin buttons against the actual ped model and native
  drawable counts, not only the visible UI filter.
- Save a male Outerwear fit, change textures and reopen it; component 3 arms and
  component 8 undershirt must remain the saved values. Repeat with female and
  verify the two fits remain independent.
- Build 2.21 intentionally removed fit-master writes from image capture; torso
  fit is now saved only from `/clothingstore`.
- Verify IDs follow `nvcloth_<gender>_<category>_<type>_<slot>_d<draw>_t<tex>`
  and remain unchanged after a retake/restart.
- Close admin after one or more gender switches and verify the original model,
  face, components and props are restored.

## Build 2.21.0-manager-torso-preview

1. Open `/clothingadmin`; confirm torso controls/name/price/catalog controls are
   absent and image capture still creates or updates exact image rows.
2. Close after previewing and capturing several items; confirm the opening
   outfit is restored and remains restored after capture cleanup finishes.
3. Open `/clothingstore`, switch FEMALE → MALE → FEMALE and confirm each tab
   keeps its own clothing cards.
4. Select cards without pressing PREVIEW and confirm the ped changes live.
5. Select an Outerwear card, change body/arms and undershirt, save torso fit,
   reopen the manager and confirm the same gender/drawable fit returns for all
   textures without changing its deterministic clothing ID.
