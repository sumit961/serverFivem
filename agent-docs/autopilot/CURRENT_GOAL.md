# Current goal

Build a COMPLETE gang system for this FiveM server.

Repository:

`C:\Users\xumit\Desktop\FIVEM\txData\FiveMBasicServerCFXDefault_23CBE7.base`

This is a NEW gameplay domain.

Preferred authoritative owner:

`resources/[core]/cm-gang`

Do NOT implement four copied gang resources.

There must be ONE generic gang framework serving exactly FOUR fixed gangs.

==================================================
PLANNING FIRST
==============

Before editing gameplay code:

1. Read `AGENTS.md`.
2. Read current project/source-of-truth documentation.
3. Audit:

   * cm-family
   * cm-admin
   * cm-playerdata
   * cm-inventory
   * cm-items
   * cm-weapons
   * cm-vehicles
   * rn-vehicleshop
   * cm-chat
   * cm-ui
   * existing organization dashboards
4. Identify reusable contracts.
5. Identify where gang membership must remain independent from:

   * family
   * EMS
   * Police
   * cm-law organizations
6. Produce the COMPLETE implementation plan.
7. Show me the plan once.

Do NOT start implementation until I approve the plan.

After I approve:

continue autonomously through the complete approved plan.

Do NOT require me to repeatedly type:

* continue
* next
* do part 2
* fix this
* now implement the UI

Implement, validate, repair, and continue automatically.

==================================================
CORE DESIGN
===========

Create exactly FOUR fixed gang slots.

Example internal IDs:

`gang_1`
`gang_2`
`gang_3`
`gang_4`

Do NOT require these final labels.

Gang labels/names can be configured later through cm-admin.

Do NOT dynamically create a fifth gang.

The database must always know there are exactly four gang organizations.

Admins may configure each fixed gang's:

* display name
* short name/tag
* color
* logo/art references
* leader
* headquarters NPC
* facilities
* vehicles
* armory
* ranks
* permissions
* enabled state

Do not allow normal players to create/delete gangs.

==================================================
MEMBERSHIP MODEL
================

Gang membership is CHARACTER based.

Use authoritative character ID.

Never use server ID as persistent identity.

A character may belong to:

* one family
  AND
* one gang
  AND
* an EMS/Police/legal organization where server policy permits

These are separate domains.

But:

ONE CHARACTER MAY BELONG TO ONLY ONE GANG AT A TIME.

Do not make joining a gang automatically remove family or legal-job membership.

==================================================
NO DUTY SYSTEM
==============

Gangs have NO:

* on duty
* off duty
* duty uniform requirement
* duty clock

Once a character is a valid gang member, gang permissions are available immediately.

Do not copy Police/EMS duty checks into cm-gang.

Authorization becomes:

valid gang membership
AND
rank permission
AND
feature rules
AND
server-authoritative target/entity validation

==================================================
GANG RANK SYSTEM
================

Use the same general quality as family/legal organization ranks.

Each gang has:

* Leader
* configurable ranks
* numeric tier
* permissions

Seed sensible initial ranks only once.

After initial creation:

DATABASE becomes authoritative.

Do not overwrite custom ranks every restart.

Example initial conceptual ladder:

Leader
Underboss
Enforcer
Member
Recruit

Names should be editable.

==================================================
RANK PERMISSIONS
================

Create reusable gang permissions, such as:

`gang.view_members`
`gang.manage_members`
`gang.manage_ranks`
`gang.manage_permissions`

`gang.chat`

`gang.vehicle`
`gang.manage_vehicles`

`gang.armory`
`gang.manage_armory`

`gang.stash`
`gang.manage_stash`

`gang.invite`

`gang.search`
`gang.rob_cash`
`gang.rob_items`

`gang.view_logs`

Reuse better naming if existing project conventions suggest it.

Do NOT create permission checks only in UI.

Every protected action must be server-authoritative.

==================================================
LEADER RULES
============

Every fixed gang has exactly one leader at a time.

Leader:

* highest rank
* cannot accidentally be demoted by lower rank
* cannot be kicked by lower/equal rank
* controls ranks/permissions where intended
* may manage existing members

cm-admin must be able to:

* assign leader
* remove/replace leader
* recover broken membership states

Normal gang UI must not bypass hierarchy.

==================================================
RECRUITMENT
===========

NEW GANG MEMBER INVITATION IS G-MENU ONLY.

Reuse existing:

`cm-playerdata` G player interaction

Do NOT create a second player targeting/menu system.

Required flow:

look at nearby player
â†’ G
â†’ Gang
â†’ Invite to Gang
â†’ confirmation
â†’ target Accept / Decline

Do NOT allow dashboard recruitment by:

* Character ID
* Server ID
* search
* offline player
* remote invite

==================================================
GANG INVITE SERVER AUTHORITY
============================

Server validates:

* actor character
* target character
* actor != target
* both online
* same routing bucket
* close physical distance
* actor gang membership
* actor rank permission `gang.invite`
* target has no existing gang
* gang is enabled
* invitation not expired
* invitation not duplicated/rate-limited

The server chooses:

* gang ID
* default entry rank

Client must NOT choose arbitrary gang/rank.

Invite expires after approximately:

60 seconds

Revalidate everything on acceptance.

Insert membership transactionally.

==================================================
GANG PLAYER G-MENU
==================

When a gang member looks at another player, G-menu should conditionally expose a clean Gang section.

Possible actions:

Gang
â”œâ”€ Invite to Gang
â”œâ”€ Search Player
â”œâ”€ Rob Cash
â””â”€ Rob Items

ONLY show actions the actor is authorized to use.

Do not clutter G for civilians.

==================================================
SEARCH / ROBBERY RULES
======================

Do NOT allow a gang member to freely rob any nearby standing player.

A target must be in a valid robbable state according to existing gameplay.

Audit current cm-playerdata/death/cuff/hands-up states.

Prefer valid robbery states such as:

* hands raised / surrender state
* cuffed/restrained
* unconscious/downed
* another explicitly existing robbable state

Do NOT invent a client-only boolean.

Server must verify the state where technically possible.

If existing server cannot authoritatively observe a hands-up state, implement a safe replicated/server-recognized robbery state rather than trusting arbitrary client requests.

==================================================
SEARCH PLAYER
=============

Gang search uses:

`cm-inventory`

as inventory authority.

Do NOT create another inventory implementation.

Server validates:

* actor gang
* `gang.search`
* target state
* same bucket
* close range
* target exists
* actor != target

Search UI must use the existing inventory/search patterns where practical.

Do not expose hidden inventory information to arbitrary clients.

==================================================
STEAL CASH
==========

Gang members with:

`gang.rob_cash`

may steal CASH from a valid robbable nearby player.

Do NOT steal:

bank balance

unless explicitly added in a future feature.

Cash authority must remain server-side.

Client may request an amount or choose available cash through UI, but server must:

* resolve actual target cash
* validate maximum
* prevent negative values
* perform transfer atomically
* prevent duplicate requests
* rate limit

Log the robbery.

Prefer transfer:

target wallet cash
â†’ actor wallet cash

Never spawn money from nothing.

==================================================
STEAL INVENTORY ITEMS
=====================

Gang members with:

`gang.rob_items`

may transfer allowed items from a valid target inventory.

Use cm-inventory authority.

Do NOT:

* copy item rows
* duplicate metadata
* create new items then forget to remove originals

Use an atomic/mutation-safe transfer operation.

Preserve:

* metadata
* durability
* serials
* stack rules
* unique item IDs where applicable

If destination inventory cannot accept the item:

do not remove it from victim.

==================================================
PROTECTED ITEMS
===============

Add configurable robbery protection for items that should not be stealable.

Examples could include:

* identity/system items
* admin/dev items
* protected quest items

Do not make assumptions about current item definitions.

Audit cm-items first.

Default to allowing ordinary inventory items unless explicitly protected by authoritative item configuration.

==================================================
WEAPONS DURING ROBBERY
======================

Do not duplicate weapon state.

If weapons are represented through cm-inventory/cm-weapons:

use their authoritative transfer contracts.

Preserve serial/metadata.

Do not create a separate gang weapon robbery implementation.

If current architecture makes safe weapon transfer impossible:

mark it for runtime/manual decision rather than duplicating weapons.

==================================================
GANG CHAT
=========

Add private gang chat integrated with existing:

`cm-chat`

Do NOT create another chat NUI.

Only members of the same gang receive gang chat.

Use character identity formatting.

Suggested command/channel:

`/g`

or reuse an existing available gang-chat convention after auditing cm-chat.

If `/g` already conflicts with something:

do not overwrite it blindly.

==================================================
GANG DASHBOARD
==============

Create a polished gang dashboard using the same general quality as the current organization F6 UI, but with gang identity.

IMPORTANT:

Do NOT automatically hijack F6 until current organization-key conflicts are audited.

A character may be:

Police + gang
EMS + gang
legal organization + gang

Therefore F6 cannot ambiguously decide which dashboard to open.

Preferred first approach:

* `/gang`
* plus one dedicated unused configurable key

During planning, audit the current key map and choose a conflict-free Gang Dashboard key.

Do NOT break:

F6 = normal organization dashboard
F9 = dispatch
TAB = MDT/records
J = organization quick actions
G = player interaction

==================================================
GANG DASHBOARD OVERVIEW
=======================

Overview should show:

* Gang logo/art
* Gang name
* short tag
* member's rank
* leader
* member count
* vehicle availability
* active member permissions/features
* recent gang activity
* quick gang information

No duty status because gangs do not use duty.

Use the same polished job-menu style we are currently moving toward:

* strong character/art panel
* local transparent image support
* dark polished UI
* CM cyan-compatible UI foundation but gang-specific accent/color
* no purple AI-dashboard look
* no backdrop-filter
* no giant generic stat-card wall

==================================================
DASHBOARD NAVIGATION
====================

Suggested sections:

Overview
Members
Ranks & Access
Vehicles
Armory
Stash
Activity

Do NOT add recruitment to dashboard.

New members:

G menu only.

Dashboard manages EXISTING members.

==================================================
MEMBER MANAGEMENT
=================

Authorized ranks may manage existing members:

* promote
* demote
* assign rank
* remove
* inspect rank

Hierarchy rules:

* cannot modify equal/higher tier
* cannot remove leader
* lower rank cannot modify higher
* leader protections
* server-side validation

==================================================
GANG NPC
========

Each of the four fixed gangs has a configurable headquarters/contact NPC.

NPC configuration includes:

* enabled
* model
* name
* role/subtitle
* location
* heading

The Gang NPC may provide member services such as:

* Open Gang Dashboard
* Gang Vehicles
* Armory
* Stash

Only expose services that belong there.

Do NOT use NPC recruitment.

Recruitment remains G-menu player-to-player.

==================================================
NPC CONFIGURATION
=================

Configure through:

cm-admin
â†’ Gangs
â†’ [Gang]
â†’ Headquarters / NPC

Admin may:

* enable/disable
* set model
* set display name
* set role
* Set Current Location
* Update Location
* Reset

Coordinates must be captured server-authoritatively from the admin's actual entity/location.

Do not trust arbitrary NUI coordinates.

==================================================
GANG ARMORY
===========

Every gang has its own configurable armory.

Armory uses authoritative definitions from:

`cm-weapons`

Do not duplicate weapon catalog.

IMPORTANT:

GANG ARMORY DOES NOT REQUIRE A FIREARMS LICENSE.

Do NOT call Police/legal license checks.

Authorization is:

gang membership
AND
gang armory permission
AND
minimum rank
AND
gang armory item enabled

Admin controls per gang:

* allowed weapon
* allowed ammo/equipment
* enabled state
* minimum rank/tier
* issue quantity/limit

Use the existing safe armory patterns where possible.

==================================================
ARMORY SECURITY
===============

Never trust:

* client-supplied weapon label
* client-supplied price
* arbitrary hash
* arbitrary ammo amount

Client sends authoritative catalog/item ID only.

Server resolves configuration.

Preserve weapon serial/metadata rules from cm-weapons/cm-inventory.

==================================================
GANG STASH
==========

Add a shared gang stash.

Use:

`cm-inventory`

Do not implement another storage system.

Each gang must have a unique inventory owner:

conceptually:

`gang_stash:<gang_id>`

Support rank permission:

`gang.stash`

and management permission where appropriate.

Admin configures stash location through cm-admin.

==================================================
GANG VEHICLES
=============

Each gang has a fixed persistent fleet similar to organizations.

Use:

`cm-vehicles`

for persistent vehicle authority.

`vehicle_id` remains authoritative.

Do not use plate as persistent identity.

Use the same safe fleet architecture already developed for legal/EMS organizations.

==================================================
VEHICLE CATALOG
===============

Reuse the authoritative vehicle catalog from:

`rn-vehicleshop`

Do NOT duplicate vehicle metadata.

Admin can configure which vehicles belong to each fixed gang.

For each gang vehicle:

* enabled
* minimum rank
* fixed parking location
* persistent vehicle_id
* availability/status

==================================================
FIXED VEHICLE LOCATIONS
=======================

Gang vehicles have fixed configured parking spaces.

Admin flow:

cm-admin
â†’ Gangs
â†’ Gang
â†’ Vehicles
â†’ Vehicle
â†’ Set Location

Safe placement workflow:

1. authorized admin starts placement
2. dummy/placement vehicle created
3. admin positions vehicle
4. confirm
5. server reads authoritative coordinates/heading
6. owner saves location
7. dummy cleans up

Normal gang members cannot arbitrarily move permanent spawn locations.

==================================================
GANG VEHICLE GAMEPLAY
=====================

Authorized gang member can:

* call configured gang vehicle
* return/store vehicle
* access according to minimum rank
* see current availability

No endless duplicate spawning.

If vehicle is already live:

reuse/recall according to existing cm-vehicles organization-fleet convention.

==================================================
GANG VEHICLE KEYS
=================

Integrate with current vehicle-key architecture if present.

Gang member's permission to use vehicle must derive from:

* membership
* rank
* gang.vehicle
* configured minimum tier

Do not create permanent personal ownership for gang vehicles.

==================================================
CM-ADMIN CENTRAL GANG MANAGEMENT
================================

Add:

cm-admin
â†’ Gangs

Show exactly four fixed gangs.

Admin can manage:

Overview
Identity
Leader
NPC / Headquarters
Facilities
Ranks
Permissions
Vehicles
Armory
Stash
Activity / Recovery

Do NOT create a Create Gang button.

Exactly four fixed gangs.

==================================================
GANG IDENTITY ADMIN
===================

Admin may configure:

* display name
* short tag
* color/accent
* logo/art asset reference where safe
* enabled/disabled

Do not accept arbitrary external URLs/scripts.

Use local assets/restricted asset references.

==================================================
ACTIVITY LOGGING
================

Create reliable gang logs.

Log high-value actions:

* invited
* joined
* declined/expired where useful
* promoted
* demoted
* rank changed
* removed
* leader changed
* vehicle called
* vehicle returned
* stash deposit/withdraw
* armory checkout
* player searched
* cash stolen
* item stolen

Record:

* gang_id
* actor CID
* target CID where applicable
* vehicle_id where applicable
* action
* safe detail
* timestamp

Do not log sensitive full inventory contents unnecessarily.

==================================================
GANG DATABASE DESIGN
====================

Use additive/idempotent tables.

Preferred conceptual schema:

`cm_gangs`
`cm_gang_members`
`cm_gang_ranks`
`cm_gang_invites`
`cm_gang_activity`
`cm_gang_facilities`
`cm_gang_fleet_vehicles`
`cm_gang_armory_config`

Use cleaner names if repository conventions indicate otherwise.

Do not reset data on restart.

==================================================
FOUR GANG SEEDING
=================

Seed exactly four gang records using:

INSERT IGNORE
or equivalent idempotent logic.

Never delete/recreate existing gang rows on startup.

If labels have been changed by admin:

do not overwrite them from config.

==================================================
RESOURCE SOURCE OF TRUTH
========================

`cm-gang`
owns:

* gang membership
* gang ranks
* gang permissions
* gang invitations
* gang activity
* gang NPC/facility definitions
* gang fleet authorization/config
* gang armory authorization/config

`cm-playerdata`
owns:

* player identity
* G interaction

`cm-inventory`
owns:

* player inventory
* gang stash
* item transfer

`cm-items`
owns:

* item definitions

`cm-weapons`
owns:

* weapon/ammo definitions

`cm-vehicles`
owns:

* persistent vehicle identity/state

`rn-vehicleshop`
owns:

* vehicle catalog

`cm-chat`
owns:

* chat presentation/channels

`cm-admin`
owns:

* central configuration/control UI

Do not duplicate authority.

==================================================
NO HARD CYCLES
==============

Design exports/events so adding cm-gang does NOT create circular resource dependencies.

Prefer:

owner APIs
soft dependency checks
guarded exports

Preserve server start reliability.

==================================================
SERVER SECURITY
===============

Every sensitive gang action must fail closed.

Audit direct event/callback invocation for:

invite
member management
rank management
search
cash robbery
item robbery
stash
armory
vehicles
admin configuration

A modified client must not gain authority by manually triggering the server event.

==================================================
RATE LIMITING
=============

Add reasonable server-side throttles for:

* invitation
* robbery
* search
* armory requests
* vehicle requests
* member mutations

Do not create callback spam.

==================================================
ROBBERY CONCURRENCY
===================

Prevent two simultaneous mutation requests from duplicating money/items.

Use target/operation locks where required.

Example:

one target robbery transaction at a time.

Do not let two clients steal the same inventory slot simultaneously.

==================================================
PLAYER DISCONNECT SAFETY
========================

Handle:

* inviter disconnect
* target disconnect
* robber disconnect
* victim disconnect
* vehicle placement admin disconnect
* gang resource restart

Never leave:

* permanent busy locks
* orphan placement vehicles
* pending invitations forever

==================================================
UI STYLE
========

Use the same polished direction as the improved organization UI.

Each gang can use its configured color while retaining a consistent CM design system.

Use:

* local transparent gang character artwork
* local gang logo
* strong visual hierarchy
* high readability
* compact useful data
* no backdrop-filter
* no generic AI-card-wall layout

Fallback cleanly when an art/logo asset is missing.

==================================================
POSSIBLE FUTURE GANG FEATURES
=============================

During PLANNING, propose optional future systems separately, such as:

* gang reputation
* gang missions
* territory control
* graffiti/tagging
* rivalry/war
* gang safehouses
* drug runs
* illegal businesses
* gang bank/shared dirty money
* vehicle chop operations
* criminal contracts

DO NOT automatically implement those merely because they are listed here.

Core gang system comes first.

After core completion put them in:

NEXT IDEAS

==================================================
DO NOT TOUCH
============

Do NOT redesign:

* family system
* Police membership
* EMS membership
* cm-law membership
* houses
* existing Spike/Barricade system
* existing organization F6/F9/TAB/J mapping
* existing inventory architecture
* weapon architecture
* vehicle persistence

Do NOT modify:

`server.local.cfg`

Do NOT touch:

`db/`

Do NOT expose secrets.

Do NOT commit.
Do NOT push unless I explicitly request it.

==================================================
VALIDATION
==========

Every implementation cycle must run relevant:

`python tools/cm-validate/validate.py`

`python tools/cm-fivem-map/scan.py --root . --out cm-agent-out --check`

`git diff --check`

plus:

Lua syntax
JavaScript syntax
fxmanifest validation
dependency cycle validation
cross-resource event/export/callback validation

Regenerate scanner output safely if required.

==================================================
FIVEM RUNTIME RULE
==================

Do not claim runtime success from static validation.

Create exact manual runtime tests for:

* invite
* accept
* decline
* one-gang-only rule
* rank management
* chat
* NPC
* dashboard
* stash
* armory
* gang vehicle spawn/store
* persistent vehicle_id
* player search
* cash robbery
* item robbery
* invalid robbery state
* distance
* routing bucket
* simultaneous robbery requests
* disconnect cleanup

If a problem genuinely requires FXServer/OneSync runtime testing:

mark it for runtime testing.

Do not endlessly make speculative fixes.

==================================================
CORE ACCEPTANCE CONDITIONS
==========================

Do not call the core system complete until:

1. Exactly four fixed gangs exist.
2. No dynamic fifth-gang creation exists.
3. Character may belong to only one gang.
4. Gang can coexist with family/job organization.
5. No duty system exists.
6. G-menu invitation works.
7. Dashboard cannot remotely recruit.
8. Rank hierarchy works.
9. Gang chat works.
10. One NPC/headquarters works per gang.
11. Admin can configure all four gangs.
12. Gang stash uses cm-inventory.
13. Gang armory uses cm-weapons and requires no firearms license.
14. Gang vehicles use rn-vehicleshop + cm-vehicles.
15. Gang vehicle locations are persistent.
16. vehicle_id remains authoritative.
17. Search is server protected.
18. Cash robbery is server protected.
19. Item robbery is safe and non-duplicating.
20. Activity logs exist.
21. Validator has zero errors.
22. No dependency cycles added.

==================================================
FINAL REPORT
============

Return:

A. ARCHITECTURE
B. FOUR FIXED GANGS
C. DATABASE SCHEMA
D. MEMBERSHIP MODEL
E. RANKS & PERMISSIONS
F. G-MENU INVITES
G. DASHBOARD
H. NPC / HEADQUARTERS
I. GANG CHAT
J. SEARCH PLAYER
K. CASH ROBBERY
L. ITEM ROBBERY
M. ROBBERY SECURITY
N. STASH
O. ARMORY
P. GANG VEHICLES
Q. VEHICLE_ID SAFETY
R. CM-ADMIN GANG MANAGEMENT
S. ACTIVITY LOGS
T. CROSS-RESOURCE CONTRACTS
U. FILES CREATED/CHANGED
V. DATABASE MIGRATIONS
W. VALIDATOR
X. SCANNER
Y. SYNTAX
Z. git diff --check
AA. git status --short
AB. MANUAL FIVEM TEST PLAN
AC. NEXT GANG IDEAS

Do not commit.
Do not push.
