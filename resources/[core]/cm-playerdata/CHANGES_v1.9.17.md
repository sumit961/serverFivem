# cm-playerdata v1.9.17

- Replaced overhead family text with one cached rank-controlled symbol.
- Added Crown, Flower, Star, Shield and Diamond texture assets.
- Added per-symbol colour rendering with native DrawSprite and a text-glyph fallback.
- Family symbols remain visible above Stranger names without revealing identity.
- Family symbols are hidden while masked by default.
- Family symbols are hidden in admin mode by default and configurable.
- No database queries are performed by the overhead render loop; data comes from the replicated `cmFamily` state bag.
