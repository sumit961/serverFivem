# Private and external assets

Git intentionally excludes `resources/[mlo]/` and `resources/[clothes]/`. A Git checkout alone is therefore not a complete runnable server. Obtain licensed assets through their legitimate source; this repository does not provide or invent download links.

## A. Tracked repository resources

Framework and ordinary dependencies under groups such as `resources/[core]/`, `resources/[standalone]/`, and the Cfx default resource groups are tracked unless separately ignored.

## B. Ignored/private resources currently enabled

The local checkout contains valid resource manifests and `server.cfg` enables:

- `bob74_ipl`
- `energy_hpsandyshores`
- `map4all-pillbox`
- `vStudios_PacificBluffsDealership_Ultimate`
- `prisonprops` (legacy `__resource.lua`)
- `int_prisonfull` (legacy `__resource.lua`)

These must be installed separately on another machine or CI deployment.

## C. Commented/disabled private resources

These are present locally with a manifest but are not actively ensured:

- `600-DebadgedCars`
- `eup-stream`
- `sClothesV9` (legacy `__resource.lua`)
- `zpack_1`

## D. Broken/missing-manifest resource

- `gn_dual_mediccenter` contains asset files but has neither `fxmanifest.lua` nor `__resource.lua`. It is disabled in `server.cfg`. Do not enable it until a correct vendor-supplied manifest and any required `data_file` declarations are known and validated.
