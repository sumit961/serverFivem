# CM Bank v1.9.0 — Gameplay UI Refresh

## Interface

- Rebuilt the main banking screen around the most-used player actions.
- Added stronger electric-cyan, blue, green, red, and amber contrast.
- Reduced the visual height and removed dashboard-like clutter from the main flow.
- Bank balance and cash on hand are now visible together at all times.
- Deposit, withdrawal, transfer, payee, and ATM ownership views remain available.
- Recent activity remains visible; full transaction history stays behind **View All**.
- Added clearer focus states and a reduced-motion fallback.
- Preserved the CM interaction prompt and the existing NUI callback contract.

## Performance

- Replaced three oversized PNG files with correctly sized WebP assets.
- Reduced loaded image assets from approximately 6.9 MB to approximately 230 KB.
- Removed external Google Fonts network requests from the FiveM NUI.
- Replaced repeated balance animation work with a direct balance render.
- The header clock now runs only while the banking interface is open.

## Compatibility

- No server events, NUI callback names, database behavior, or economy logic changed.
- Existing deposit, withdrawal, transfer, saved payee, statement, ATM ownership,
  restock, earnings, sale, and business-history behavior is retained.
