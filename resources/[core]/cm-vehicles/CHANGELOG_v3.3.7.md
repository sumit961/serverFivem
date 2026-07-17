# v3.3.7

CreateVehicleForPlayer accepts an explicit routing bucket and publishes a deferred trusted-finalization payload. This allows cm-house to create a world-bucket vehicle while the owner is still inside an instanced garage; condition and mods finalize when a world client streams the entity.
