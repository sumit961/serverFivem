CMCityBulletin = CMCityBulletin or {}
CMCityBulletin.DatabaseReady = false

local requiredTables = {
    'cm_citybulletin_notices',
    'cm_citybulletin_reads',
}

local requiredKeys = {
    { tableName = 'cm_citybulletin_notices', indexName = 'PRIMARY', columns = 1 },
    { tableName = 'cm_citybulletin_reads', indexName = 'PRIMARY', columns = 2 },
}

CreateThread(function()
    for _, tableName in ipairs(requiredTables) do
        local row = MySQL.single.await([[SELECT COUNT(*) AS present
            FROM information_schema.tables
            WHERE table_schema = DATABASE() AND table_name = ?]], { tableName })
        if not row or tonumber(row.present) ~= 1 then
            print(('[cm-citybulletin] database unavailable: apply sql/001_cm_citybulletin.sql (%s missing)'):format(tableName))
            return
        end
    end

    for _, key in ipairs(requiredKeys) do
        local row = MySQL.single.await([[SELECT COUNT(DISTINCT column_name) AS present
            FROM information_schema.statistics
            WHERE table_schema = DATABASE() AND table_name = ? AND index_name = ?]], {
            key.tableName, key.indexName,
        })
        if not row or tonumber(row.present) ~= key.columns then
            print(('[cm-citybulletin] database unavailable: %s requires %s key columns (%s)'):format(
                key.tableName, key.columns, key.indexName))
            return
        end
    end

    CMCityBulletin.DatabaseReady = true
    print('[cm-citybulletin] database contract ready')
end)
