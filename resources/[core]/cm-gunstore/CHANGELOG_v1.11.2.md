# cm-gunstore v1.11.1 / v1.11.2 — admin card clipping + vest visual-equip fix

Two more bugs found while chasing the original "can't add vest to store"
report, both now fixed.

## v1.11.1 — admin cards were clipped, hiding Store/Save/Delete entirely
`.admin-item` (every card on the `/gunadmin` **All**/**Armor** tabs) is a flex
child of a scrolling list, and had `overflow: hidden` but no
`flex-shrink: 0`. That combination lets flexbox shrink a card below its own
content height (removing the usual "don't shrink past your content" floor
that `overflow: hidden` specifically disables) and then clip whatever
doesn't fit via its own `overflow: hidden` — instead of the outer list simply
scrolling further. Vests have the most fields of any item type, so they hit
this ceiling first: everything past the 6th field (Gender, Stock, Access,
Image, Description, and the **Store checkbox / Save / Delete buttons**) was
being cut off, even though it was always present in the HTML.

Fix: added `flex-shrink: 0` to `.admin-item` in `web/style.css`. Cards now
grow to fit all their fields; the list itself scrolls instead.

## v1.11.2 — vest gave armor value but never visually equipped
Root cause: the vest creator form's hidden `drawable_id` field defaulted to
`"0"`, so **every** vest created without first clicking "Capture Vest" (or
where the capture didn't attach a look) was saved with `drawable_id = 0`
instead of no drawable at all. `0` is a legitimate GTA component variation —
usually "nothing equipped" for the Accessories slot armor uses — so
`cm-inventory`'s equip code correctly received a "drawable" value, correctly
ran `SetPedComponentVariation`, and correctly ran `SetPedArmour`... it just
applied variation 0, which is invisible on most ped models. Armor value
applied (looked like it worked), the vest never appeared (looked broken).

Fix:
- The creator form's drawable field now defaults to blank, not `0`.
- Creating an armor item with no captured look now sends `drawable_id: null`
  (not `0`) to the server, which already correctly stores that as "no vest
  visual" — this path just never used to be reachable.
- Clicking "Create In Store"/"Create Hidden" with no captured look now shows
  a confirm dialog ("This item will only give armor value — it will not
  visually equip anything. Create it anyway?") instead of silently creating
  a stat-only vest that looks like a real one.

### Fixing vests you already created
Any vest made before this fix may have `drawable_id = 0` baked in. In
`/gunadmin` → **Armor** or **All** tab, open that vest's card, clear the
**Drawable** field to blank, and click **Save** — an empty Drawable field was
already handled correctly by the edit/save path (only the *create* path had
the bug). Or re-capture it properly: click "Capture Vest (Clothing Studio)"
first, confirm the note says "Vest captured ✓", then Create.

## To apply
1. Restart `cm-gunstore` (picks up the new confirm-dialog logic and the
   corrected default).
2. Hard-refresh `/gunadmin` (the cache-busting version bumped to `1.11.2`,
   a normal resource restart is enough).
