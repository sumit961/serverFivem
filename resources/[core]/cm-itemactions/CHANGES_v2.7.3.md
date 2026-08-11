# CM Item Actions 2.7.3

- Added `RegisterExternalItem(itemName, resourceName, exportName)`.
- External item effects are invoked through stable named exports instead of
  cross-resource Lua closure references.
