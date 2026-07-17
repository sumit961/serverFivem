# v3.2.5 - Client-owned garage condition bootstrap

- Removed CreateVehicleServerSetter from house-garage spawning.
- Applies engine/body/tank health before OneSync handoff.
- Rejects vehicles whose physical health nodes remain at zero.
- Protects parked garage cars from collision damage.
- Trusted repair/service changes update state bags and the controlling client.
- Prevents transient server-native zero readings from corrupting database health.
