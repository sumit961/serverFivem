-- nv_cloth/client/cl_shopdev.lua
-- Admin helper to set up each store correctly. Output goes to the F8 console.
-- Restricted: add to server.cfg ->  add_ace group.admin command.clothdev allow
--
--   /clothdev clerk          stand behind the counter facing the customer
--   /clothdev interact       stand on the customer side of the counter
--   /clothdev dressing       stand on open floor, back to the wall, facing the room
--   /clothdev test           spins every camera preset 360deg here and reports wall clipping
--   /clothdev goto <shopId>  teleport to a shop's dressing spot to check it

local function f(n) return ('%.3f'):format(n) end

local function testCamera()
    local me = PlayerPedId()
    local oldDebug = Config.CameraDebug
    Config.CameraDebug = true
    FreezeEntityPosition(me, true)
    if ClothCam and ClothCam.Start then
        ClothCam.Start(me, 'full')
    end

    local report = {}
    for name in pairs(Config.CameraPresets or {}) do
        if ClothCam and ClothCam.SetPreset then
            ClothCam.SetPreset(name)
            ClothCam.Reset()
            Wait(400)
            ClothCam.BeginStats()
            for _ = 1, 72 do            -- full circle, 5deg steps
                ClothCam.Rotate(5.0, 0.0)
                Wait(40)
            end
            local s = ClothCam.EndStats()
            report[#report + 1] = { name = name, ratio = s and s.minRatio or 1.0 }
        end
    end

    if ClothCam and ClothCam.Stop then
        ClothCam.Stop()
    end
    FreezeEntityPosition(me, false)
    Config.CameraDebug = oldDebug

    print('^5[clothdev] camera test (100% = never blocked)^0')
    for _, r in ipairs(report) do
        local pct = math.floor(r.ratio * 100)
        local col = pct >= 80 and '^2' or (pct >= 50 and '^3' or '^1')
        print(('  %s%-6s %3d%%^0'):format(col, r.name, pct))
    end
    print('  Red/yellow is fine from some angles (auto-orbit handles it); if "full" is red,')
    print('  move the dressing spot further from walls.')
end

RegisterCommand('clothdev', function(_, args)
    local sub = args[1]
    local me = PlayerPedId()
    local c, h = GetEntityCoords(me), GetEntityHeading(me)

    if sub == 'clerk' then
        -- peds spawn at ground level, entity coords are ~1m above it
        local line = ('clerk = { model = \'s_f_y_shop_low\', coords = vector4(%s, %s, %s, %s), scenario = \'WORLD_HUMAN_STAND_IMPATIENT\' },')
            :format(f(c.x), f(c.y), f(c.z - 1.0), f(h))
        print(line)
        TriggerEvent('chat:addMessage', { args = { 'clothdev', line } })
    elseif sub == 'interact' then
        local line = ('interact = vector3(%s, %s, %s),'):format(f(c.x), f(c.y), f(c.z))
        print(line)
        TriggerEvent('chat:addMessage', { args = { 'clothdev', line } })
    elseif sub == 'dressing' then
        local line = ('dressing = vector4(%s, %s, %s, %s),'):format(f(c.x), f(c.y), f(c.z), f(h))
        print(line)
        TriggerEvent('chat:addMessage', { args = { 'clothdev', line } })
    elseif sub == 'test' then
        CreateThread(testCamera)
    elseif sub == 'goto' and args[2] then
        if type(Config.Shops) == 'table' then
            for _, s in ipairs(Config.Shops) do
                if s.id == args[2] and s.dressing and (s.dressing.x ~= 0.0 or s.dressing.y ~= 0.0) then
                    SetEntityCoordsNoOffset(me, s.dressing.x, s.dressing.y, s.dressing.z, false, false, false)
                    SetEntityHeading(me, s.dressing.w)
                    return
                end
            end
        end
        print('^1[clothdev] unknown shop id or no dressing set^0')
    else
        print('/clothdev clerk | interact | dressing | test | goto <shopId>')
        TriggerEvent('chat:addMessage', { args = { 'clothdev', '/clothdev clerk | interact | dressing | test | goto <shopId>' } })
    end
end, true)
