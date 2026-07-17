# cm-house v1.6.1 — Public Admin Development + Google Interaction Font

## Temporary public house admin

- Added `Config.DevelopmentPublicAdmin`.
- It defaults to `true` in this local-development build.
- Every connected player can open every cm-house admin tab, run the creator,
  edit templates, pricing, photos, recovery and property records.
- The bypass does not make players owners or family members during ordinary
  house gameplay. Owner/family checks for doors, garages, storage and weapon
  storage remain unchanged.
- Set the option to `false` before normal players join the server.

## Interaction typography

- Added Google Sans Flex from Google Fonts to the house NUI.
- The centered transparent cyan E prompt now uses Google Sans Flex.
- Reduced excessive letter spacing and slightly increased text size for better
  readability while preserving the liquid-glass cyan text effect.

## Database

- No SQL migration is required.
