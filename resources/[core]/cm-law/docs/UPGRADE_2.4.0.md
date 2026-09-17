# CM Law 2.4.0

> Hotfix 2.4.1 embeds the compact overview rules in the proven dashboard stylesheet and loads it last, preventing partial/raw overview rendering in FiveM NUI.

## Unified organization dashboard

- Police, Sheriff, SAHP, FIB, Army, and future generic legal organizations now use the same compact three-column command UI.
- The overview includes the member identity and tier card, live readiness strip, permission-driven agency tools, command tools, available units, organization feed, shortcut bar, and member record rail.
- Organization names, emblems, character art, accent colors, ranks, permissions, rosters, fleet counts, calls, and activity remain driven by each organization’s live data.
- Police keeps its separate operational callbacks and all existing enforcement, MDT, dispatch, armory, fleet, wardrobe, administration, and live incident functionality.
- The v2.3 ESC/NUI focus release hardening remains active for both the generic law dashboard and embedded Police dashboard.

## Upgrade

Replace the previous `cm-law` folder, make sure the old standalone `cm-police` resource is disabled or removed, and perform a full server restart. Only `ensure cm-law` should be used for these combined resources.
