# cm-playerdata v1.9.16

- Adds synchronous target-change hook for dynamic extension G-menu actions.
- Displays `[FamilyTag] Rank/Title` directly above the existing player name.
- Supports both native overhead rendering and the optional NUI label renderer.
- Mirrors authoritative cm-family identity in `Player(source).state.cmFamily`.
- Keeps server ID hidden; all visible identity continues to use database character ID.
- Family actions still pass through cm-playerdata's server distance/death/rate validation before cm-family validates permissions and hierarchy.
