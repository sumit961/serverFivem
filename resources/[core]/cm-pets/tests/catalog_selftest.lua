CM_PETS = {}
dofile('shared/config.lua')

local config = CM_PETS.Config
assert(config.AdminPermission == 'players.manage')
assert(type(config.ApprovedModels) == 'table')
assert(#config.Catalog == 3)

local seenTypes, seenModels = {}, {}
for _, pet in ipairs(config.Catalog) do
    assert(type(pet.typeId) == 'string' and #pet.typeId <= config.Limits.TypeId)
    assert(not seenTypes[pet.typeId], 'duplicate catalog type')
    assert(config.ApprovedModels[pet.model], 'catalog model is not approved')
    assert(config.ApprovedModels[pet.model].species == pet.species, 'catalog species mismatch')
    assert(not seenModels[pet.model] or seenModels[pet.model] == pet.species, 'model species mismatch')
    seenTypes[pet.typeId], seenModels[pet.model] = true, pet.species
end

print('cm-pets catalog self-test: PASS')
