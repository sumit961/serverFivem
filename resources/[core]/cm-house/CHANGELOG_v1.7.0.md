# cm-house v1.7.0 — Admin Templates, Simple Garage, Safe Weapon Storage

- Removed the garage settings/customization point, appearance UI, runtime props/lights and writable customization API.
- Added SQL migration `015_remove_garage_settings_v1.7.0.sql` to remove legacy customization data.
- Reduced garage exit interaction distance from 2.25 m to 1.35 m.
- Added server-side proximity validation for drivers and players leaving on foot.
- Interior and garage templates are now created only from the house module opened through `cm-admin`.
- The property wizard can only select existing templates and stops when no compatible interior exists.
- Garage capacity is exactly the number of placement cars saved in the selected garage template.
- The property wizard never invents a capacity from pricing/minimum settings.
- Weapon storage accepts a gun only when its durability/condition is confirmed at 100%.
- Depositing a gun recursively removes serial metadata before permanent storage.
- Existing locker weapons containing serial metadata are sanitized at resource startup.
- Ammunition storage behaviour is unchanged.
- Replaced the interaction prompt with a simple, clean, centered cyan Google Sans Flex style.
