# nv_cloth local clothing-image capture

This build captures clothing locally. It does not call RCore, an RCore server,
or an external screenshot/image-processing API.

## Requirements

- Start `screenshot-basic` before `nv_cloth`.
- Give the FiveM server process write permission to this resource directory.
- Open `/clothingadmin` with an account that passes the existing clothing-admin
  permission check.

## Complete export

1. Open `/clothingadmin`.
2. In **Complete Local Export**, click **Capture Everything · Male + Female**.
3. Confirm the native job count.
4. Use **Pause**, **Resume**, or **Cancel** at any time. These take effect after
   the currently active single screenshot finishes.
5. Failed jobs remain visible in **Failed Images**, including gender, category,
   drawable, texture, reason, and attempt count.

The complete export creates every native drawable/texture combination for both
`mp_m_freemode_01` and `mp_f_freemode_01`. Category export now captures every
texture too, rather than texture 0 only.

## Output

Each successful job writes both formats to:

`nv_cloth/generated_images/`

Example names:

- `male_torso_11_42_0.png`
- `male_torso_11_42_0.webp`
- `female_bracelets_7_3_1.png`

PNG and WebP signatures are validated before a job is reported successful.
`Config.IconCapture.catalogSync` is `false`, so image generation does not call
`cm-items` or `cm-gunstore`. Set it to `true` only if catalog integration is
deliberately wanted.

## Isolation method

Every job creates a disposable freemode ped of the requested gender. The real
player is hidden but is never model-swapped or stripped. All props are cleared,
all unrelated components use their empty drawable, and hair is removed. The
server replicates `allowEmptyHeadDrawable=true`, and the client requests the same
command automatically at resource start and before capture. Component 0 drawable
-1 hides the head without replacement files. Only the selected drawable/texture is
then applied. Exactly one screenshot is taken and chroma-keyed; there is no second
image, baseline, body subtraction, or reset-flag fallback in inventory capture.

If the client rejects head drawable `-1`, the job fails with
`allowEmptyHeadDrawable_unavailable` instead of photographing a body or silently
changing methods. Hats/glasses/earrings float without a head, watches/bracelets
without hands, shoes without feet, and pants without legs.

The pipeline rejects and retries an item when native readback does not match the
requested drawable/texture, the screenshot is missing or invalid, encoding fails,
or either local file cannot be written.

## DOCX category cameras

Build 2.15 maps the exact player heading/offset and camera orbit/distance/height/FOV
from `For glass.docx` into glasses, earrings, outerwear, shirt, pants, shoes,
headwear, neck accessories, and bracelet captures. Watches share the bracelet
composition. Bags keep their rear-view preset because the document has no bag row.

Existing saved camera rows from older builds are ignored automatically
because their preset versions do not match the new framing. Any settings saved
again with **Adjust Position & Take Image** become the new deliberate override.

Build 2.16 keeps native component metadata authoritative when importing catalog
rows. Component 8 always belongs to Shirts and component 11 always belongs to
Outerwear, even when an older catalog calls both categories `shirt`. Each capture
and retry also keeps an immutable copy of its starting category, drawable, and
gender so a later preview update cannot change the photographed item.

Build 2.17 also locks the selected texture before any asynchronous preview work.
The same immutable texture is used for the native preview, isolated capture ped,
retry, readback, and filename, preventing a selected white Shirt from reverting
to texture 0 (commonly blue) while the capture is being prepared.

The `allowEmptyHeadDrawable` developer command remains restricted by FiveM on a
normal production client. For the native `-1` head path, launch the one capture
client with `+set moo 31337`; the game server itself may remain in production.

## Live capture position editor

Normal **Take Image + Save** and all bulk actions shoot immediately with the saved
or DOCX default composition. Use **Adjust Position & Take Image** only when a
custom drawable needs different framing. After the isolated item and green screen
appear, use the on-screen controls to:

- rotate and move the capture ped left/right, toward/away, or vertically;
- orbit, raise, lower, zoom, or pull back the camera;
- widen or tighten the camera FOV while viewing a square 512×512 frame guide.

The live readout shows player heading/offset and camera orbit/distance/height/FOV.
`CONFIRM & SHOOT` stores the complete composition for that category, including
camera orbit and off-centre target offsets, then captures the image. Future
textures and category exports reuse it after restarts. `CANCEL` restores the real
player without saving or taking a screenshot.

The old Body Part Browser, Clothing Visibility, Capture Position, angle/Z setter,
and capture-location panel were removed. Native isolation is fixed: unrelated
body components and props are emptied, then only the selected item is applied.

Both the disposable capture ped and the hidden real player are frozen throughout
the editor and screenshot. Movement, sprint, jump, combat, and vehicle-exit inputs
are suppressed until the capture confirms, cancels, fails, or the resource stops.
Cleanup restores the real player's original coordinates and original frozen state.

Entity freezing alone does not stop GTA's living-ped animation. Ambient, base-idle,
gesture, viseme, head IK, torso IK and arm IK are disabled and local capture time
is stopped until cleanup. Shirts, Outerwear, and Armor use this transform-only
freeze without a pose clip, because the character-creation animation changes the
apparent shoulder/item angle. Other categories retain one exact frozen frame of
the male/female character-creation pose, reasserted every render tick.

## Category crop

Use **Set Crop for This Category** once. Its left/top/right/bottom crop is saved by
canonical category and silently applied to every drawable and texture in that
category, including adjusted shots and category exports. The editor opens again
only when **Set Crop** is deliberately pressed; **Adjust Position & Take Image**
does not ask for a crop each time. Saved crops are reloaded after restart.
After a crop exists, the button reads **Change Saved Crop**. A crop-editor request
is consumed as soon as that editor opens, so a retry cannot open it again; the
saved crop is applied and the processed image is saved automatically.

Build 2.18 updates the capture preview only after the saved category crop has
been applied. The image shown after a retake is therefore the exact cropped image
sent to PNG/WebP encoding and local saving, rather than the earlier auto-crop.

## Safety

The original visibility, alpha, coordinates, heading, frozen state,
invincibility, and ragdoll state are restored after success or failure. A
45-second screenshot watchdog and `onResourceStop` cleanup delete the temporary
ped and restore the player if a screenshot callback is lost or the resource is
restarted mid-capture.

No image system can remove geometry that is literally authored into the target
clothing drawable itself (for example, a custom shoe mesh containing baked-in
skin). Normal GTA/FiveM freemode clothing separates those body parts, and the
native empty-drawable method removes the supporting ped geometry before capture.

## Build 2.19 — /clothingstore store manager

The publishing model changed:

- `/clothingadmin` now ONLY captures and saves clothes. Every successful capture
  writes the image AND a catalog record, but the record is **unpublished**
  (`enabled = false`). Nothing reaches the player store from capture alone.
  Retaking the image of a clothe that is already published keeps its publish
  state, price, label, and org untouched.
- `/clothingstore` (same admin permission) is the new manager. It lists every
  saved clothe for both genders with its captured image and per-clothe controls:
  **PUBLISH TO STORE / REMOVE FROM STORE**, price, name, org assignment,
  **PREVIEW ON PED**, and **RETAKE IMAGE**. Retake closes the manager and opens
  `/clothingadmin` with that exact clothe preselected (swapping the admin's ped
  model first when the clothe belongs to the other gender; the original model
  and outfit are restored when the admin panel closes).
- The MALE/FEMALE tabs in `/clothingstore` swap the admin's ped so both
  catalogs can be previewed live. Drag on the open game area to rotate the ped.
- Org clothes: assigning an org (Config.OrgShops — ems, police, sahp by
  default, extensible) moves the clothe to shop `org_<key>` with
  `required_job = <key>`. It leaves the public store and appears only in that
  org's locker, opened with `/orgcloset` by players whose job matches. Moving a
  clothe between shops disables the old shop's row so it never shows twice.
- The player store (`/clothing` shops) only ever shows rows that were published
  in `/clothingstore`.

Historical 2.19 behavior: torso fitting briefly lived in `/clothingadmin`.
Build 2.21 removes it from that panel; current torso fitting is exclusively in
`/clothingstore`.

### Build 2.19.1 restart/manager fix

- Schema upgrades now check `information_schema.COLUMNS` before adding a column,
  so normal restarts no longer print duplicate-column errors.
- Store-manager helpers are forward-declared before the older admin-save handler;
  `SAVE TORSO` and capture persistence no longer crash on a nil helper.
- `/clothingstore` now closes any still-open clothing/admin panel and continues
  opening the manager instead of silently returning.

### Build 2.20 — gender models, torso fit masters, stable IDs

- `/clothingadmin` has MALE and FEMALE buttons that swap the actual freemode
  player model. Counts, previews, captures and saves now use the selected model;
  closing the panel restores the original model, face settings, clothes and props.
- Outerwear arms (component 3) and undershirt (component 8) use a
  gender-specific `texture = -1` fit-master row. Build 2.21 makes
  `/clothingstore` the only workflow that writes this row.
- Every clothing catalog row and inventory metadata record receives a stable
  deterministic ID: gender + category + component/prop slot + drawable +
  texture. Retakes and restarts keep the same ID; `texture = -1` uses `tall`.
- Store-manager cards combine management/fit data from the fit-master row with
  the picture from an exact texture row, avoiding false MISSING IMAGE cards.

### Build 2.21 — capture-only admin, manager torso fit and live preview

- `/clothingadmin` is now image capture only. Its torso-fit controls and direct
  catalog-save callback were removed; naming/pricing/restriction fields are no
  longer shown. Capturing Outerwear does not create or change torso-fit data.
- `/clothingstore` owns torso fitting. Selecting an Outerwear card immediately
  previews it, provides body/arms and undershirt controls, and **SAVE TORSO FIT**
  updates the existing gender/drawable `texture=-1` clothing ID for all colours.
- Every manager card now live-previews on selection; the manual preview button
  remains as a retry.
- Male/female catalog rows are cloned before gender normalisation, preventing
  the female collection pass from mutating and hiding rows already collected
  for the MALE tab. Switching gender refreshes the manager catalog.
- Admin close rejects delayed capture-preview restoration and reapplies the
  opening appearance after camera cleanup, so photographed clothes cannot stay
  equipped after leaving the panel.
