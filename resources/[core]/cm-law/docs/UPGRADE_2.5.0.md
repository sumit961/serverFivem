# CM Law 2.5.0 — Daily Desk and shared UI refresh

## Install

Back up cm-law and preserve your local configuration values. Stop cm-law, replace its folder with this release, merge your configuration values if needed, and start cm-law again. Keep standalone cm-police stopped because Police is already embedded. No new SQL migration is needed.

## Daily Desk

Available from the organisation sidebar and the overview shortcut for members of Police and legal organisations.

- Six manually checked daily tasks: equipment, communications, vehicle inspection, assignment review, records and handover.
- Personal shift notes up to 2,000 characters. Use Save desk before leaving; unsaved changes are clearly indicated.
- Checklist and notes persist on the server across resource restarts, scoped separately to each character and organisation.
- The new day starts at midnight UTC. Six previous days plus today form the seven-day history.
- Previous notes can be expanded without changing today's work.
- Permission-aware shortcuts open existing dashboard tools. A shortcut does not grant extra access.
- Reload requires confirmation when you have unsaved edits. Conflicting saves are rejected rather than overwriting a newer version.
- These are personal, self-reported work reminders, not paid missions or automatically verified achievements.
- Storage uses the server's resource KVP store, not SQL tables. Include that store in server backups if these personal notes need to be retained.

## UI refresh

Both interfaces load one shared operations stylesheet. Deep navy surfaces, restrained cyan action accents, mint completion status, readable labels, clearer form fields, consistent cards and focus outlines extend across the dashboard, NPC dialogues, confirmation prompts, quick menus, wardrobe, armory and MDT inputs.

The Daily Desk has responsive cards, a progress indicator, saved/unsaved/error states and expandable history. Smaller screens stack its columns. NPC choices scroll within the viewport rather than extending below it. Reduced-motion preferences are respected. No backdrop-filter is used.

All app requests share a visible working/error indicator and mark the clicked button busy. Failed requests return actionable errors; requests have a 45-second response timeout and never automatically retry transactions. A timed-out request may still complete on the server, so check the result before trying again.

## Validation

- 82 Lua files passed Lua 5.4 syntax loading, substituting FiveM backtick hash literals only for the syntax check.
- 7 JavaScript files passed syntax checks.
- Existing menu Escape, focus routing and NPC race/error regression checks passed.
- Daily Desk server harness passed save/read, character and organisation isolation, membership denial, revision conflicts, midnight rollover, history expiry and corrupt-data preservation.
- Both Daily Desk UI variants passed mocked initialization, load/save and character-switch cleanup checks.

These are source and mocked interaction checks. This environment did not have a working browser or a FiveM server, so the final appearance, external cm-ui stylesheet interactions and gameplay integrations still need an in-server check.

Suggested server check: open each organisation's dashboard, open Daily Desk, tick a task, save a note, close/reopen, reconnect, and confirm persistence. Check another character does not see it. Test navigation, NPC Escape, nested confirmations, wardrobe/armory controls and the layout at your normal resolution.
