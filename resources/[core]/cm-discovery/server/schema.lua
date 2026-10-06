CMDiscovery = CMDiscovery or {}
CMDiscovery.DatabaseReady = false

local requiredTables = {
    'cm_discovery_landmarks',
    'cm_discoveries',
}

CreateThread(function()
    for _, tableName in ipairs(requiredTables) do
        local row = MySQL.single.await([[SELECT COUNT(*) AS present
            FROM information_schema.tables
            WHERE table_schema = DATABASE() AND table_name = ?]], { tableName })
        if not row or tonumber(row.present) ~= 1 then
            print(('[cm-discovery] database unavailable: apply sql/001_cm_discovery.sql (%s missing)'):format(tableName))
            return
        end
    end

    local primaryKey = MySQL.single.await([[SELECT COUNT(*) AS present
        FROM information_schema.statistics
        WHERE table_schema = DATABASE()
          AND table_name = 'cm_discoveries'
          AND index_name = 'PRIMARY'
          AND column_name IN ('character_id', 'landmark_id')]], {})
    if not primaryKey or tonumber(primaryKey.present) < 2 then
        print('[cm-discovery] database unavailable: cm_discoveries requires PRIMARY KEY (character_id, landmark_id)')
        return
    end

    CMDiscovery.DatabaseReady = true
    print('[cm-discovery] database contract ready')
end)
