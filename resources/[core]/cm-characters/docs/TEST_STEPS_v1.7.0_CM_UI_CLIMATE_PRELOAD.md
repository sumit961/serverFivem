# Test steps - cm-characters v1.7.0

## Required start order
```cfg
ensure cm-ui
ensure oxmysql
ensure cm-core
ensure cm-auth
ensure cm-playerdata
ensure cm-characters
ensure cm-climatime
ensure cm-spawn
ensure cm-hud
ensure cm-admin
```

## Selector UI
1. Restart in the order above.
2. Login through `cm-auth`.
3. Confirm the character selector opens with the blue/cyan CM theme.
4. Confirm cards, details panel, buttons, music toggle, creator modal, and loading progress use the same CM style as `cm-auth`.
5. Confirm there is no black NUI background.
6. Confirm no browser console error appears for duplicate `const` or duplicate `let` declarations.

## Existing character -> spawn page climate
1. Select an existing character.
2. Screen should fade/hold black briefly.
3. `cm-characters` should release selector world lock before `cm-spawn` takes over.
4. `cm-climatime` should apply live synced weather/time during this black transition.
5. Spawn page/reveal should not show an obvious sky/weather snap after the player appears.

## New character -> first spawn climate
1. Create a new character.
2. Save appearance.
3. Confirm the screen remains hidden while `cm-climatime` prepares live weather/time.
4. Confirm first spawn opens in the correct climate without a visible selector-night flash.

## Performance checks
1. Open F8 console and confirm normal production logs stay quiet.
2. Confirm no continuous NUI spam appears while idling on selector.
3. Confirm no extra weather loop was added by this patch; climate aliases fire only during spawn handoff.
4. Confirm no external Google Fonts or jQuery CDN request is required by the active character page.
