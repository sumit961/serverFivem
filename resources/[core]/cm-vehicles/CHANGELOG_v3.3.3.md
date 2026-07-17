# cm-vehicles v3.3.3

## Garage call visibility fix

- Added persistent replicated `cmGarageReleased` state for vehicles promoted from a house garage.
- Every client reapplies visibility, alpha 255, collision, gravity, unfreeze, handbrake release, and unlocked doors whenever the released entity streams.
- The one-shot release acknowledgement no longer determines whether later clients can recover the vehicle.
- Garage protection exits immediately when release is pending or persistent release is active.
- Returning a vehicle to a garage clears all release state.
