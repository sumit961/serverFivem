# CM Command 2.6 — visual redesign

This release redesigns the organisation interface around the six supplied screenshots. It builds on 2.5.0, preserving Daily Desk and the previous interaction fixes.

## What changed

- Replaced the loaded command-center 2.3, record-rail and older decorative dashboard styles with a new command UI stylesheet. Older files remain in the archive for reference but are no longer linked by either dashboard.
- Native-size body text, larger controls, readable mixed-case labels and navy/cyan surfaces replace tiny terminal-style labels.
- Two-column dashboard layout: navigation and workspace. The persistent right-hand record rail is hidden; its existing character artwork moves into an overview hero.
- Overview separates identity, four statistics, a restrained readiness bar, passive capability labels and recent activity. Capability labels are deliberately informational rather than fake action buttons.
- Members uses full-width rows. Ranks uses consistent cards with expandable permission details; the existing edit/delete callbacks are retained.
- Fleet has a designed empty state when no vehicles are configured. No sample vehicles are introduced to the live resource.
- Shared MDT has labelled citizen/vehicle search groups, Enter-to-search, a focused window and a useful starting screen. Existing result and enforcement handlers remain attached to their original IDs.
- Quick Actions uses numbered two-column cards, an explicit close button and an Escape footer. Its existing choice callbacks and authority checks are unchanged.
- Police MDT colours and text styling follow the same interface palette.
- No backdrop-filter or new remote artwork/font dependency.

## Preview

After extracting, open PREVIEW.html in a desktop browser. It includes Overview, Members, Ranks, Fleet, MDT and Quick Actions with clearly labelled sample data. The preview is not listed in the FiveM manifest and cannot run server actions. Keep its preview folder beside the html folder when viewing it.

## Install

Back up cm-law and retain your configuration values. Stop the resource, replace the cm-law folder, merge your configuration values if necessary, then start cm-law. Keep standalone cm-police stopped. No new SQL migration is required.

## Validation and limits

82 Lua files and 8 production JavaScript files passed syntax checks. Mocked initialization checks passed for both redesign scripts and both existing app scripts. Existing Escape, request routing, Daily Desk persistence and NPC race/error checks also passed.

The preview browser rejected local-file navigation, so this release has not been visually rendered in that browser or tested in FiveM here. Check the final appearance at your game resolution, particularly external cm-ui interactions, wardrobe/armory views and smaller screens. The included preview helps review the main layouts before starting the resource.
