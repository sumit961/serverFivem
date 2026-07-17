# cm-vehicles v3.2.6

- Garage vehicles are hidden, collision-disabled, frozen and protected from the first creation frame.
- Cars are revealed only after mods and saved health are applied and verified.
- Parked condition reads use authoritative state bags instead of transient server-native zero values.
- Live condition state bags are refreshed after persistence.
- Repairs only stored legacy records where engine/body/tank were all corrupted to 0/1.
- Vehicle information no longer flashes false 0% health during garage stream-in.
