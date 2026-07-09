# v1.3.1 - CM Items Preview Button Visibility Fix

Fixed the `/cmitempreview` card layout where `Get` and `Delete` buttons could be hidden under the card because clothing metadata and price text pushed the action row outside the fixed card height.

Changes:
- Action row is now pinned to the bottom of every preview card.
- Card height and thumbnail height were adjusted so buttons stay visible on all rows.
- Button row now has its own safe bottom area and separator.
- Added CSS/JS query version in `preview.html` to avoid stale NUI cache loading old layout files.
