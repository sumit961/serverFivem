CMClubs = CMClubs or {}
CMClubs.DatabaseReady = false

CreateThread(function()
    local required = {
        'cm_clubs',
        'cm_club_ranks',
        'cm_club_members',
        'cm_club_invites',
        'cm_club_activity',
    }

    local requiredClubhouseColumns = {
        'clubhouse_enabled', 'clubhouse_x', 'clubhouse_y', 'clubhouse_z',
        'clubhouse_heading', 'clubhouse_npc_model', 'clubhouse_display_name',
        'clubhouse_interaction_label', 'clubhouse_interaction_distance',
        'clubhouse_routing_bucket',
    }

    for _, tableName in ipairs(required) do
        local row = MySQL.single.await('SELECT COUNT(*) AS present FROM information_schema.tables WHERE table_schema = DATABASE() AND table_name = ?', { tableName })
        if not row or tonumber(row.present) ~= 1 then
            print(('[cm-clubs] database unavailable: apply sql/001_cm_clubs.sql before enabling club mutations (%s missing)'):format(tableName))
            return
        end
    end

    for _, columnName in ipairs(requiredClubhouseColumns) do
        local row = MySQL.single.await([[SELECT COUNT(*) AS present FROM information_schema.columns
            WHERE table_schema = DATABASE() AND table_name = 'cm_clubs' AND column_name = ?]], { columnName })
        if not row or tonumber(row.present) ~= 1 then
            print(('[cm-clubs] clubhouse database unavailable: apply sql/002_cm_clubhouses.sql (%s missing)'):format(columnName))
            return
        end
    end

    CMClubs.DatabaseReady = true
    print('[cm-clubs] database contract ready')
end)
