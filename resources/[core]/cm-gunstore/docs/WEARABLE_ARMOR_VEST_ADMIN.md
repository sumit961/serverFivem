# Wearable Armor Vest Admin

This upgrade makes armor items work like clothing vests:

- Admin opens `/gunadmin`.
- Choose `Wearable Vest / Armor`.
- Click `Load Vest List` to list GTA component 9 vest drawables/textures for the current ped.
- Select a vest to preview it on the player.
- Set armor health, name, price, stock, and Store/Hidden.
- Click `Take Vest PNG` to capture the equipped vest image.
- Create item in Store or Hidden.

When a player uses an armor item, `cm-itemactions` applies:

- component 9 drawable/texture to the character
- armor health value to the player
- saves appearance through `cm-characters` when available

Run `install/cm_gun_catalog_upgrade_v3_wearable_vests.sql` once on existing databases.
