# CM Car Wash v2.0.2

- Fixed invisible NUI where the cursor appeared and the vehicle was held but the panel did not render.
- Removed optional chaining and object spread from the UI for older FiveM CEF compatibility.
- Added persistent NUI-ready retries.
- Added repeated open-message delivery and a rendered-panel acknowledgement.
- Added a 3.5-second fail-safe that releases focus and the vehicle if NUI cannot render.
- Kept car-wash interaction strictly driver-seat only.
