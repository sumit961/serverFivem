# CM Car Wash v2.0.1

- Kept car-wash use strictly driver-seat only.
- Hidden interaction prompts from walking players and passengers.
- Fixed the custom E prompt/UI sometimes not appearing because the first NUI message was sent before Chromium finished loading.
- Added NUI ready retries and open-message replay.
- Uses vehicle coordinates for wash-bay detection.
- Increased the configurable bay interaction radius to 8 metres to match server validation.
- Server now validates the exact bay index selected by the client.
