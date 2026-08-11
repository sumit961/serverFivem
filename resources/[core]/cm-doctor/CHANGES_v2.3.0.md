# cm-doctor v2.3.0 — Shared Medicine Stock

- Added Pillbox supply doctor Dr. Morgan at `301.5257, -579.6008, 28.8474, 279.7823`.
- Added live shared-stock percentage and unit meter.
- Pharmacy purchases now consume `cm-ems` medicine stock.
- Purchases are blocked when stock is insufficient.
- Money and stock are restored if inventory delivery fails.
- Supply-run task appears only when stock is 40% or lower.
- Supply doctor validates proximity and delegates all task authority to `cm-ems`.
- Other doctors retain treatment and pharmacy services.
