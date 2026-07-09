# Test steps - cm-climatime v1.7.1

Restart in this order:

```cfg
restart cm-ui
restart cm-core
restart cm-auth
restart cm-playerdata
restart cm-characters
restart cm-climatime
restart cm-spawn
restart cm-hud
```

## Spawn overflow test
1. Clear FiveM client cache if the client crashed previously.
2. Join server and login.
3. Select character and wait for cm-spawn page.
4. Do not click any card for 5-10 seconds. Confirm there is no `Reliable network event overflow`.
5. Click Hotel. Rejoin and click Last Location. Confirm no crash/overflow.

## Weather before spawn test
1. Set weather to RAIN or THUNDER in Climatime admin.
2. Relog to character selector.
3. Open spawn page and click a spawn.
4. Weather/time should already be prepared before reveal, with no post-spawn notification.

## Time speed test
1. Set manual time speed to x10.
2. Watch clock for more than one sync interval.
3. Confirm time progresses smoothly and does not snap every sync.

## Weather race test
1. Change weather quickly between CLEAR, RAIN, THUNDER, and FOGGY.
2. Move across a zone border while weather is transitioning.
3. Confirm old weather transitions do not snap back over the newest weather.
