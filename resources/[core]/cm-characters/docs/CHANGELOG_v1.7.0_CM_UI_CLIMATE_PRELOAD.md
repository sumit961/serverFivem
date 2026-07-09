# cm-characters v1.7.0 - CM UI + climate preload handoff

## Changed
- Added `cm-ui` dependency and loaded the central `cm-theme.css`, `cm-components.css`, and `cm-ui.js` in the character NUI page.
- Updated selector, creator, scene editor, and disabled legacy character-admin markup to consume CM UI button, panel, card, input, scrollbar, toast, and progress styling where safe.
- Kept resource-specific layout in `ui/style.css` and `ui/appearance/style.css`.
- Removed external Google Fonts from the active NUI page.
- Replaced external jQuery CDN with a small local `ui/vendor/cm-miniquery.js` compatibility shim used only by the appearance editor.
- Removed FontAwesome dependency from the standalone appearance page fallback.
- Removed duplicate JavaScript declarations that could break NUI parsing in strict browsers.
- Removed the small CSS blur effect from character cards for cheaper NUI rendering.

## Climate / spawn handoff
- Hardened the selector-to-spawn climate prepare step.
- `cm-characters` now marks pre-spawn climate state, releases the character world lock while the screen is black, calls supported `cm-climatime` export aliases, emits safe local climate preload aliases, waits for the configured prepare window, then allows `cm-spawn`/playerdata to continue.
- The intent is: click character -> black transition -> `cm-climatime` applies real synced weather/time -> `cm-spawn` page/reveal continues with climate already prepared.

## Unchanged
- No auth, money, character ownership, slot validation, or appearance-save server logic was rewritten.
- Legacy character admin UI remains disabled by default through config; real admin menus should continue moving into `cm-admin`.
- No `backdrop-filter` is used.
