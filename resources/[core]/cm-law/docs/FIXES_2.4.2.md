# CM Law 2.4.2 — menu interaction fixes

## Installation

1. Back up your current cm-law folder and any local configuration edits.
2. Stop cm-law, replace it with the cm-law folder from this ZIP, and retain your local configuration values where needed.
3. Start cm-law. Do not also start the standalone cm-police resource: Police is already embedded here.

No database migration is introduced by this patch.

## Fixed

- Removed duplicate facility Continue/Close requests caused by inline and delegated handlers firing together.
- Fixed the undefined resource name in front-desk public-service requests and added a resource-name fallback for the law iframe.
- Replaced competing Escape listeners with one handler per UI. The parent shell also forwards Escape when it receives keyboard focus.
- Explicitly focus the active iframe when opening an interactive menu.
- Prevent passive prompts, hints and notifications from taking over an open interactive interface.
- Restore an underlying interface after a cross-interface modal closes.
- Route Police closet opens to the correct interface.
- Put the Police quick menu above NPC cinematics; Escape dismisses the quick menu before the conversation below it.
- Stop prompt-input Escape from also closing the underlying menu.
- Preserve focus after Lua confirmations/quick menus over law dashboards, Police wardrobes, MDT terminals and impound menus.
- Fix Refresh, End Duty and Police armory-stock handlers accessing event.currentTarget after an await.
- Recover Police request failures and re-enable dialogue choices. Re-enable law armory checkout after an unsuccessful refresh.
- Reject duplicate in-flight NPC choices and public-service requests.
- Protect NPC camera timers and delayed responses from acting on a different, newly opened dialogue.
- Catch NPC service-handler errors so a failed action does not leave the choice permanently pending.
- Remove the per-frame law NPC focus override and redundant inline dialogue CSS overrides.
- Escape quotes in dynamic law HTML attributes.
- Remove temporary per-click/per-message diagnostic traffic and its server event.

## Verification

- All 80 Lua files passed Lua 5.4 syntax loading (FiveM backtick hashes substituted with integer literals for this check).
- All 5 JavaScript files passed Node syntax checks.
- Both UI scripts initialized in a mocked DOM harness.
- Interaction harness passed Escape routes for law facilities, wardrobe, armory, Police NPCs, quick menus, MDT, impound and cinematic preferences.
- Passed public-service request dispatch, asynchronous refresh and submenu Escape priority checks.
- Shell harness passed pre-load message delivery, passive-message focus isolation, modal handoff, restoration and parent Escape forwarding.
- Lua NPC harness passed player/focus cleanup, handler-error recovery, duplicate-choice rejection and stale-session isolation.

These are source and mocked interaction checks, not a live FiveM session or a rendered browser validation. Browser installation was unavailable in the test environment. External cm-ui assets and server integrations were not included in this upload and could not be verified here.

## In-server checks

- Open a law facility NPC and a Police NPC. Test Continue, each permitted service, Cancel and Escape. Confirm camera, HUD, mouse focus and player movement restore.
- Open a submenu or confirmation from an NPC. Cancel it, then use the underlying menu again.
- Open a dashboard near NPCs while hints/notifications arrive. Its controls should remain active.
- Test Refresh, End Duty and armory stock loading more than once.
- Close and reopen an NPC while a service request is pending; an old response should not dismiss the new dialogue.
- Check fleet, wardrobe, MDT and impound with the appropriate rank and duty state. Server permission checks remain authoritative.

This patch addresses the reproducible interaction defects found in this resource. It does not certify that every gameplay/database/integration issue is resolved.
