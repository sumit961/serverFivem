# cm-ems v2.0.1

- Fixed `/ambulance` feedback calling a helper that was local to another server file.
- Removed a redundant replicated-state duty check that could discard a server-authorized call immediately after going on duty.
- EMS duty is still validated server-side when distributing and accepting dispatch calls.
