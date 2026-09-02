-- Police-owned configuration adapter for the barricade model catalog.
-- World deployment authority lives exclusively in cm-law.
local ready = false

local function manager(src)
    local characterId = cid(src)
    local member = characterId and memberFor(characterId)
    local admin = false
    pcall(function() admin = exports[Config.AdminResource]:HasPermission(src, Config.AdminPermission) == true end)
    if admin then return true, characterId end
    if not member or dbBoolean(member.is_suspended) or not has(member, 'police.manage_barricades') then return false, characterId end
    return true, characterId
end

local function catalog()
    if not ready then return {} end
    local rows = MySQL.query.await('SELECT id, model_name FROM cm_police_barricade_catalog ORDER BY id ASC') or {}
    local out = {}
    for _, row in ipairs(rows) do out[#out + 1] = { id = tonumber(row.id), modelName = row.model_name } end
    return out
end

local function broadcast()
    TriggerClientEvent('cm-police:client:barricadeCatalogUpdated', -1, catalog())
end

lib.callback.register('cm-police:server:barricadeCatalogList', function() return catalog() end)
lib.callback.register('cm-police:server:addBarricadeModel', function(src, modelName)
    local allowed, actorCid = manager(src)
    if not allowed then return false, 'Your rank cannot manage barricade models.' end
    local clean = tostring(modelName or ''):gsub('%s+', '')
    if clean == '' or #clean > 64 or not clean:match('^[%a_][%w_]*$') then return false, 'Invalid model name.' end
    MySQL.insert.await('INSERT INTO cm_police_barricade_catalog (model_name, added_by) VALUES (?, ?)', { clean, actorCid })
    log(actorCid, 'barricade_model_added', { model = clean }); broadcast()
    return true, 'Barricade model added.'
end)
lib.callback.register('cm-police:server:removeBarricadeModel', function(src, catalogId)
    local allowed, actorCid = manager(src)
    catalogId = tonumber(catalogId)
    if not allowed then return false, 'Your rank cannot manage barricade models.' end
    if not catalogId then return false, 'Invalid model.' end
    MySQL.update.await('DELETE FROM cm_police_barricade_catalog WHERE id = ?', { catalogId })
    log(actorCid, 'barricade_model_removed', { catalogId = catalogId }); broadcast()
    return true, 'Barricade model removed.'
end)

exports('AdminGetBarricades', function(src)
    local permitted = manager(tonumber(src))
    return permitted and { ok=true, items=catalog() } or { ok=false, error='Permission denied.' }
end)

exports('AdminConfigureBarricade', function(src, _, data)
    src, data = tonumber(src), type(data)=='table' and data or {}
    local permitted, actorCid = manager(src)
    if not permitted then return false, 'Permission denied.' end
    if tostring(data.operation)=='remove' then
        local id=tonumber(data.catalogId); if not id then return false,'Invalid model.' end
        MySQL.update.await('DELETE FROM cm_police_barricade_catalog WHERE id=?',{id})
        log(actorCid,'barricade_model_removed',{catalogId=id}); broadcast(); return true,'Barricade model removed.'
    end
    local clean=tostring(data.modelName or ''):lower():gsub('%s+','')
    if clean=='' or #clean>64 or not clean:match('^[%a_][%w_]*$') then return false,'Invalid model name.' end
    MySQL.insert.await('INSERT IGNORE INTO cm_police_barricade_catalog (model_name,added_by) VALUES (?,?)',{clean,actorCid})
    log(actorCid,'barricade_model_added',{model=clean}); broadcast(); return true,'Barricade model added.'
end)

CreateThread(function()
    MySQL.query.await([[CREATE TABLE IF NOT EXISTS cm_police_barricade_catalog (
        id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT, model_name VARCHAR(64) NOT NULL,
        added_by VARCHAR(64) NULL, created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (id), UNIQUE KEY uq_cm_police_barricade_model (model_name)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]])
    if tonumber(MySQL.scalar.await('SELECT COUNT(*) FROM cm_police_barricade_catalog') or 0) == 0 then
        for _, model in ipairs(Config.Barricades.DefaultModels or {}) do
            MySQL.insert.await('INSERT IGNORE INTO cm_police_barricade_catalog (model_name) VALUES (?)', { model })
        end
    end
    ready = true
    PoliceSchemaMarkReady('barricades')
end)
