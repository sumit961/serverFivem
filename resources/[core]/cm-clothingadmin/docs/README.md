# CM Clothing Admin

This resource lets admins manage clothing names, prices, categories, shops, and torso fit from inside the game.

## Install

1. Ensure `cm-items` includes the SQL-backed catalog update.
2. Add the resource:

```cfg
ensure cm-items
ensure cm-clothingadmin
ensure cm-inventory
ensure cm-characters
ensure nv_cloth
```

3. Give admin permission:

```cfg
add_ace group.admin cm.clothingadmin allow
```

## Basic workflow

Wear or preview a clothing piece in game, then save it:

```text
/cmclothcapture torso
/cmclothset name Black Tech Hoodie
/cmclothset price 450
/cmclothset category hoodies
/cmclothset shop city
/cmclothfit
/cmclothsave
```

For full sleeve / half sleeve shortcuts:

```text
/cmclothset sleeve full   -- arms 6
/cmclothset sleeve half   -- arms 5
```

For custom fit, manually set the arms/undershirt in your clothing menu or commands, then run:

```text
/cmclothfit
```

## Texture-specific vs all textures

By default `/cmclothcapture` saves the current texture. To make the entry apply to all textures of that drawable:

```text
/cmclothset texture -1
/cmclothsave
```

## Useful commands

```text
/cmclothingadmin
/cmclothcapture <torso|tshirt|pants|shoes|hat|glasses|chain|bag|watch|earrings>
/cmclothset name <label>
/cmclothset price <amount>
/cmclothset category <category>
/cmclothset shop <shop>
/cmclothset sleeve <full|half|custom|none>
/cmclothset enabled <yes|no>
/cmclothfit
/cmclothpreview
/cmclothsave
/cmclothdelete <male|female> <componentIndex> <drawableId> [textureId|-1]
/cmclothreload
```
