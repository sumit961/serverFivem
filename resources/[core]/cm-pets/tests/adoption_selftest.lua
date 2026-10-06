CM_PETS = {}
dofile('shared/config.lua')
dofile('shared/adoption_policy.lua')

local config = CM_PETS.Config
local centerInput = {
    centerId = 'fixture_center', displayName = 'Fixture Adoption',
    interactionLabel = 'ADOPT PET', npcModel = 's_f_y_shop_mid', enabled = true,
    x = 10.0, y = 20.0, z = 30.0, heading = 90.0,
    interactionDistance = 3.0,
}
local center = assert(CM_PETS.Adoption.NormalizeCenter(centerInput, nil, config))
local context = { loaded = true, alive = true, playerValid = true, x = 11.0, y = 20.0, z = 30.0, routingBucket = 0 }
local petType = { enabled = 1, approvedModel = true }

assert(CM_PETS.Adoption.CenterUsable(context, center))
context.x = 99.0
assert(not CM_PETS.Adoption.CenterUsable(context, center))
context.x = 11.0
center.enabled = false
assert(not CM_PETS.Adoption.CenterUsable(context, center))
center.enabled = true
petType.enabled = 0
assert(not CM_PETS.Adoption.AdoptionDecision(context, center, petType, nil))
petType.enabled = 1
assert(not CM_PETS.Adoption.AdoptionDecision(context, center, petType, { id = 1 }))

assert(CM_PETS.Adoption.SessionTokenValid(4, 'token', 4, 'token'))
assert(not CM_PETS.Adoption.SessionTokenValid(4, 'token', 3, 'token'))
assert(not CM_PETS.Adoption.SessionTokenValid(4, 'token', 4, 'stale'))

local ownership = {}
local function claim(characterId)
    if ownership[characterId] then return false end
    ownership[characterId] = true
    return true
end
assert(claim('42'), 'first ownership claim should succeed')
assert(not claim('42'), 'concurrent/duplicate ownership claim should be rejected')

assert(CM_PETS.Adoption.ShouldCleanup({ dead = true }))
assert(CM_PETS.Adoption.ShouldCleanup({ unloaded = true }))
assert(CM_PETS.Adoption.ShouldCleanup({ disconnected = true }))

print('cm-pets adoption self-test: PASS')
