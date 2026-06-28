UI GAP TIGHTEN PATCH
====================

This patch reduces the horizontal spacing between:
- Fast Access
- Backpack / Pockets
- Equipment

Implementation:
- Reduced --layout-gap
- Pulled FAST ACCESS inward with a small positive translateX
- Pulled EQUIPMENT inward with a small negative translateX
- Tightened the unified glass plate around the inventory cluster
- Added small-screen safety overrides
