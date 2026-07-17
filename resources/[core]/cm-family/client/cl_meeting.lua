-- Permission-gated family meeting waypoint receiver.
RegisterNetEvent('cm-family:client:setMeetingPoint', function(data)
    if type(data) ~= 'table' then return end
    local x, y = tonumber(data.x), tonumber(data.y)
    if not x or not y then return end

    SetNewWaypoint(x + 0.0, y + 0.0)
    PlaySoundFrontend(-1, 'WAYPOINT_SET', 'HUD_FRONTEND_DEFAULT_SOUNDSET', true)

    local setter = tostring(data.setterName or 'A family member')
    if lib and lib.notify then
        lib.notify({
            title = 'Family meeting point',
            description = setter .. ' set a meeting point. Your GPS has been updated.',
            type = 'inform',
            duration = 7000,
        })
    end
end)
