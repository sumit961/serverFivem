CM Zero-Code Clothing Update

Replace this nv_cloth folder and cm-items folder from the ZIP.

server.cfg order:
ensure oxmysql
ensure screenshot-basic
ensure cm-items
ensure cm-inventory
ensure cm-itemactions
ensure nv_cloth

Remove if still present:
ensure cm-clothingadmin

Admin permission:
add_ace group.admin cm.clothing.admin allow
add_principal identifier.fivem:1494046 group.admin

Main workflow:
/clothingadmin -> airport green-prop admin studio -> select clothing -> custom name -> Public Store or Hidden -> Capture Icon + Save.

Admin helper commands:
/cmpos or /getpos -> prints copy-ready vec3/vec4 player coordinates in F8 and chat.

Notes:
- Public Store items save as shop='clothes' and enabled=true.
- Hidden/Event items save as shop='hidden_event' and enabled=false, so they do not appear in the public shop.
- Inventory icons save into cm-items/ui/images/clothing/custom/.
- The icon processor removes green pixels and also has an edge-background fallback if GTA lighting/object texture is not pure green.
- Admin mode now teleports to Config.AdminStudio.StudioCoords at LSIA airport.
- Config.AdminStudio.Backdrop.model defaults to cs_dry_ice_freezer_floor and spawns 3 rotated green prop pieces behind the player.
- The old side reference mannequin is disabled by default so admin capture has no naked NPC in the frame.
- If that prop model is invalid on your build, nv_cloth falls back to the old DrawBox chroma wall instead of breaking capture.


CUSTOM GREENSCREEN PROP TEST
----------------------------
1. Put your custom prop file here:
   nv_cloth/stream/prop_ld_greenscreen_01.ydr

2. Restart the resource:
   restart nv_cloth

3. In-game, stand anywhere and run:
   /cmtestprop

4. If you want to test another model name:
   /cmtestprop model_name_here

5. Clear spawned test props:
   /cmclearprop

6. Get your exact position/heading for studio placement:
   /cmpos

If /cmtestprop says the model is invalid, the .ydr is not enough for a brand-new model.
You need a matching .ytyp archetype, or use/replace an existing GTA prop name.
