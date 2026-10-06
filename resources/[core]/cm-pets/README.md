# cm-pets

`cm-pets` is a standalone cosmetic companion-pet resource. It is intentionally
separate from police K9, gangs, clubs, families, jobs, economy, inventory,
vehicles, and other animal systems.

## Install and persistence

`server.cfg` is the startup authority. The resource is ensured after
`cm-admin`, which is after `cm-playerdata`. Apply
[`sql/001_cm_pets.sql`](sql/001_cm_pets.sql) manually before granting pets.
The resource does not create or migrate tables automatically.

`cm_pet_types` is the admin-managed allowlisted catalog. A type has a stable
`type_id`, display name, species, approved model, bounded description, and
enabled state. A model must also exist in `shared/config.lua` under
`ApprovedModels`; the client never chooses a model.

`cm_pets` stores one row per Character ID. Its unique Character ID key prevents
duplicate ownership. `enabled = 1, revoked = 0` is the only usable ownership
state. Re-granting an existing Character ID updates that row; it does not create
a second pet. Metadata is a bounded flat JSON object and is not exposed to the
player UI.

Adoption centers are optional and remain absent until configured. Apply
[`sql/002_cm_pets_adoption.sql`](sql/002_cm_pets_adoption.sql) manually before
using the center exports. The migration seeds no coordinates and no enabled
center. `ApprovedNpcModels` is the NPC model allowlist; `AdoptionCenters` is an
empty disabled-by-default configuration fixture. Center records persist only
bounded identity, location, heading, interaction distance, optional routing
bucket, allowlisted NPC model, and enabled state.

At a valid enabled center, `/pets` shows enabled catalog types. The server
revalidates Character ID, alive/player entity, center distance, routing bucket,
session token, enabled pet type/model, cooldown, and the one-pet rule. Adoption
is atomic against the unique Character ID key and stores bounded adoption
metadata in the existing `metadata_json` field. A successful adoption remains
hidden until the player explicitly summons it. There are no prices, items,
economy, progression, breeding, hunger, or veterinary flows.

## Player API

`/pets` opens the small NUI panel. A player can view the owned pet, summon or
hide it, rename it, and set follow/stay. Rename input is bounded to 32 bytes and
control characters are removed. All callbacks resolve the Character ID from
`cm-playerdata`; client payloads cannot select the owner, model, or state.

## Admin exports

These are server exports and require `GetInvokingResource() == 'cm-admin'` plus
the existing `cm-admin` permission `players.manage` for the supplied admin
source. `cm-admin` is not modified by this resource.

`AdminSetAdoptionCenter` accepts bounded `centerId`, `displayName`,
`interactionLabel`, `npcModel`, `enabled`, `x`, `y`, `z`, `heading`,
`interactionDistance`, and optional `routingBucket`. Enabled centers require
coordinates, an allowlisted NPC model, and valid bounded distance/heading
values. Disabled centers clear their location and cannot be used by players.
No admin UI or new permission authority is introduced.

- `exports['cm-pets']:AddOrUpdatePetType(adminSource, data)`
- `exports['cm-pets']:SetPetTypeEnabled(adminSource, typeId, enabled)`
- `exports['cm-pets']:GrantPet(adminSource, characterId, typeId, petName, metadata)`
- `exports['cm-pets']:RevokePet(adminSource, characterId)`
- `exports['cm-pets']:ListOwnedPets(adminSource, characterId?, limit?)`
- `exports['cm-pets']:AdminSetAdoptionCenter(adminSource, data)`
- `exports['cm-pets']:AdminEnableAdoptionCenter(adminSource, centerId, enabled)`
- `exports['cm-pets']:AdminListAdoptionCenters(adminSource)`

Successful admin mutations are sent through the existing `cm-admin:AddLog`
audit bridge. The exports do not accept a client-supplied owner source as the
ownership identity; `adminSource` identifies only the authorized administrator.

## Entity and lifecycle safety

Only the server creates networked pet peds, using the catalog model after checking
the database row, approved model map, loaded Character ID, alive state, session
generation, routing bucket, and duplicate state. Active entities are tracked
by source plus Character ID/session generation and carry an internal statebag
marker. Follow/stay requires client network control; if control cannot be
obtained, the action fails closed and the server hides the pet. Clients never
spawn arbitrary models. Adoption-center NPCs are local, frozen, invincible,
non-networked cosmetic peds created only from server-provided center records
whose model is checked against `ApprovedNpcModels`. If a routing bucket cannot
be safely resolved on the client, bucket-specific center NPCs are not streamed;
the server still revalidates the bucket on every adoption request.

Pets are removed on death/non-alive state, Character ID unload, disconnect,
resource stop, revoke, disabled type, invalid configuration, stale session,
invalid entity, and duplicate/replacement grant. Resource restart does not
automatically respawn a pet.

## Validation

From this directory, run `lua tests/catalog_selftest.lua` and
`lua tests/adoption_selftest.lua` for deterministic catalog/adoption checks.
Static validation should also cover Lua syntax, JavaScript syntax, manifest
paths, SQL review, `git diff --check`, and the CM contract-map and Graphify
checks. Runtime/gameplay testing is intentionally external to this task; no
FiveM restart or gameplay QA is performed by this resource change.
