# v1.3.8 Fast Preview + Private Selector Bucket

Changes:

- Selector now requests a private routing bucket/dimension from server.
- Bucket uses the player's server ID: `SetPlayerRoutingBucket(src, src)`.
- Bucket resets to `0` before the real character is selected/spawned.
- Hidden real player is moved to the selector stream point and placed on ground.
- Freemode preview models are preloaded when selector opens.
- Character preview click now deletes only the tracked dummy ped, not every nearby ped, making selection faster.
- `/charpreviewclear` still aggressively removes old dummy peds near the selector scene.

Install:

```cfg
restart cm-characters
```

Test:

```text
/charpreviewclear
```

Then select character cards. The dummy should appear faster and only inside your private selector dimension.
