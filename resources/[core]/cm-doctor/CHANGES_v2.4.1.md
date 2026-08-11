# CM Doctor 2.4.1

- Medicine effects now register through a named `UseMedicineItem` export
  instead of passing Lua closures across a resource boundary.
- Uses canonical dot-style exports for readiness and registration.
- Startup failures identify the exact medicine item and returned result.
