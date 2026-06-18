# v1.2.3 No Black Screen Fix

This version removes remaining full-screen NUI backgrounds and stops using far/static preview camera scenes for the selector.

The selector now uses the player's already streamed world position as the preview stage. This prevents the black screen caused by unstreamed camera locations or hidden interior scenes.

Client changes:
- forces `DoScreenFadeIn()` while selector is open
- clears timecycle modifiers
- disables artificial black lighting
- keeps real player near current location for streaming
- spawns selected preview ped in the live world
- points camera at the selected ped

UI changes:
- no full-screen selector background
- no center stage box
- no vignette/noise/black overlay
- only cards, details panel, top title, and music button draw
