# Local Property Photos — cm-house 1.4.2

Property photos are stored as normal files inside the resource:

```text
cm-house/html/img/houses/house_<propertyId>.jpg
```

No Discord webhook, remote image host, replicated convar, or client-supplied URL is used.

## Requirements

Start `screenshot-basic` before `cm-house`:

```cfg
ensure screenshot-basic
ensure cm-house
```

The server requests the screenshot and chooses the destination filename. The client receives only a short-lived capture token and cannot choose a server path.

## New property flow

1. The admin frames the property and presses `H`.
2. The server saves a short-lived `pending_<token>.jpg` file.
3. The property is inserted and receives its database ID.
4. The pending image becomes `house_<propertyId>.jpg`.
5. `cm_houses.image_url` is updated to the local NUI path.
6. The door menu displays the saved image immediately. When a newly written file is not yet available through the active NUI packfile, a rate-limited server callback reads the same local JPG and supplies it to the open door card as a JPEG data URI.

## Retaking a photo

Use **Retake Photo** in `/cmadminhouse`. The new image is captured into a temporary file first. The previous image is retained until the replacement and database update succeed.

## Backups and updates

The database stores the local reference, not the image bytes. Before replacing the resource, preserve this folder:

```text
cm-house/html/img/houses/
```

Copy the saved `.jpg` files into the same folder in the new resource. Deleting that folder removes the images even though the database rows still reference them.

## Exports

```lua
local imageUrl, camera = exports['cm-house']:GetPropertyPhoto(houseId)
local absolutePath, imageUrl = exports['cm-house']:GetPropertyPhotoFile(houseId)
local dataUri, reason = exports['cm-house']:GetPropertyPhotoData(houseId)
```

`DeleteHousePhoto` is a protected server export intended for authorized admin resources. Normal property deletion calls the internal function automatically.

`GetPropertyPhotoData` reads the same server-side JPG and returns a `data:image/jpeg;base64,...` value for server integrations that need the current image immediately. Door-menu requests are proximity/instance checked and rate limited.
