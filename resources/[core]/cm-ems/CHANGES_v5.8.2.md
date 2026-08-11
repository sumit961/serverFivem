# cm-ems v5.8.2

- Only the assigned pushing medic can control and reposition the networked
  stretcher, preventing ownership fights between nearby clients.
- Ground height is sampled at a controlled interval, rejects the stretcher's
  own higher surface, and applies a capped vertical step to remove rapid
  up/down jitter.
