while not Config do Citizen.Wait(1) end

Config.Interactions = {
    ---@field Enabled: boolean [master toggle for all police interactions]
    Enabled = true,

    ---@field Jobs: table [jobs that can use police interactions (cuff, drag, search) - { jobName = minGrade }]
    Jobs = {
        ['police'] = 1, -- KADET
        -- ['sheriff'] = 1,
    },

    ---@field Cuffs: table [handcuff / cable-tie settings]
    Cuffs = {
        ---@field usableItem: boolean [allow handcuffs to be used as an inventory item]
        usableItem = true,
        ---@field cuffKeys: boolean [require the cuffs_key item to uncuff (key given on cuff)]
        cuffKeys = false,
        ---@field saveAfterLogout: boolean [QB/QBX - persist cuff state across reconnects]
        saveAfterLogout = true,
        ---@field cuffAnimation: string [cuff process style - 'basic' or 'advanced']
        cuffAnimation = 'advanced',

        ---@field Models: table [cuff prop models + attachment offsets per type - keyed by 'cuffs'/'cable_ties' = { model, coords: {front,rear}, rotation: {front,rear} }]
        Models = {
            ['cuffs'] = {
                model = 'p_cs_cuffs_02_s',
                coords = {
                    ['front'] = vector3(-0.072869487526759, -0.0012296267491397, 0.086429102235542),
                    ['rear']  = vector3(-0.028522114396424, 0.065937974578837, 0.022246163694372),
                },
                rotation = {
                    ['front'] = vector3(5.240962220783, 72.673622220404, 3.6396119385612),
                    ['rear']  = vector3(-10.023743323143, -79.258320930337, 57.986604251941),
                },
            },
            ['cable_ties'] = {
                model = 'police_zip_tie_positioned',
                coords = {
                    ['front'] = vector3(-0.080001169766206, -0.0036196277495717, 0.081534692290769),
                    ['rear']  = vector3(-0.048201313893628, 0.049896089087137, 0.039492829067451),
                },
                rotation = {
                    ['front'] = vector3(116.5540931415, 71.055636774481, 178.76123748207),
                    ['rear']  = vector3(-112.36719137777, -59.482776307032, 58.845921533542),
                },
            },
        },

        ---@field Animations: table [cuff idle loops + cuff/uncuff process animations]
        Animations = {
            ---@field idle: table [looped idle anims while cuffed, keyed by 'rear'/'front' = { dict, clip, flag }]
            idle = {
                ['rear']  = { dict = 'mp_arresting', clip = 'idle', flag = 49 },
                ['front'] = { dict = 'anim@move_m@prisoner_cuffed', clip = 'idle', flag = 49 },
            },

            ---@field cuff: table [cuffing process anims - { arrested: table, officer: table }]
            cuff = {
                -- Arrested player perspective
                arrested = {
                    rearAlive = {
                        dict = 'mp_arrest_paired', clip = 'crook_p2_fwd_left', flag = 33,
                        attach = { offset = vector3(-0.1, 0.45, 0.0), rotation = vector3(0.0, 0.0, 30.0) },
                    },
                    rearDead = {
                        dict = 'mp_arrest_paired', clip = 'arrest_on_floor_back_left_b', flag = 33,
                        attach = { offset = vector3(0.3, 0.5, 0.0), rotation = vector3(0.0, 0.0, 0.0) },
                    },
                    frontBasic = {
                        attach = { offset = vector3(0.0, 0.6, 0.0), rotation = vector3(0.0, 0.0, 0.0), type = 20, fixedRot = false },
                    },
                    frontAdvanced = {
                        attach = { offset = vector3(0.0, 0.6, 0.0), rotation = vector3(0.0, 0.0, 180.0) },
                    },
                },
                -- Officer perspective
                officer = {
                    rearAlive  = { dict = 'mp_arrest_paired', clip = 'cop_p2_fwd_left', flag = 33, duration = 4500 },
                    rearDead   = { dict = 'mp_arrest_paired', clip = 'arrest_on_floor_back_left_a', flag = 33, duration = 4100 },
                    frontAlive = { dict = 'mp_arresting', clip = 'a_uncuff', flag = 33, duration = 2500 },
                },
            },

            ---@field uncuff: table [uncuffing process anims - { arrested: table, officer: table }]
            uncuff = {
                -- Arrested player perspective
                arrested = {
                    rear = {
                        dict = 'mp_arresting', clip = 'b_uncuff', flag = 33,
                        attach = { offset = vector3(0.0, 0.6, 0.0), rotation = vector3(0.0, 0.0, 0.0), type = 20, fixedRot = false },
                        duration = 4500,
                    },
                    front = {
                        attach = { offset = vector3(0.0, 0.6, 0.0), rotation = vector3(0.0, 0.0, 180.0), type = 20, fixedRot = false },
                        duration = 4500,
                    },
                    deadDuration = 3000,
                },
                -- Officer perspective
                officer = {
                    alive = { dict = 'mp_arresting', clip = 'a_uncuff', flag = 33, duration = 6000 },
                    dead  = { dict = 'mp_arresting', clip = 'a_uncuff', flag = 33, duration = 2500 },
                },
            },
        },

        ---@field cableTieTimer: number [cable-tie auto-release timer (ms); 0 to disable]
        cableTieTimer = 60 * 1000,

        ---@field cuffGame: function [minigame run when the arrested player is cuffed; return true = escaped, false = cuffed - (isHard: boolean)]
        cuffGame = function(isHard)
            return false
        end,

        ---@field cuffItemCheck: function [decides the action when using handcuffs on a player; return 'cuff'/'uncuff'/false - (entity: number, playerId: number)]
        cuffItemCheck = function(entity, playerId)
            local localState = LocalPlayer.state
            if localState.draggingPlayer or localState.carryingPlayer then return false end

            local targetState = Player(playerId).state
            if targetState.draggedBy or targetState.carriedBy then return false end

            if targetState.isCuffed then
                return 'uncuff'
            else
                local playerJob = Bridge.Framework.fetchPlayerJob()
                if targetState.isDead or IsEntityPlayingAnim(entity, 'random@mugging3', 'handsup_standing_base', 3) or Config.Jobs[playerJob.name] then
                    return 'cuff'
                end
            end
            return false
        end,
    },

    ---@field LockpickCuffs: table [lockpicking handcuffs - { miniGame: function, animation: { enabled, dict, clip, flag } }]
    LockpickCuffs = {
        miniGame = function()
            return lib.skillCheck(
                {
                    { areaSize = 30, speedMultiplier = 1.5 },
                    { areaSize = 30, speedMultiplier = 1.5 },
                    { areaSize = 30, speedMultiplier = 1.5 },
                    { areaSize = 30, speedMultiplier = 1.5 },
                    { areaSize = 30, speedMultiplier = 1.5 },
                },
                { '1', '2', '3', '4' }
            )
        end,
        animation = {
            enabled = true,
            dict = 'anim@amb@clubhouse@tutorial@bkr_tut_ig3@',
            clip = 'machinic_loop_mechandplayer',
            flag = 49,
        },
    },

    ---@field GunPowder: table [gunshot residue test - { WindowMs: number (how long the GSR test stays positive after firing; swimming clears it sooner) }]
    GunPowder = {
        WindowMs = 5 * 60 * 1000,
    },

    ---@field Drag: table [drag/escort settings]
    Drag = {
        ---@field cancelKey: number [control id to cancel drag for non-target users (73 = X)]
        cancelKey = 73,
        ---@field animation: table [drag animation - { dict: string, clip: string, flag: number }]
        animation = {
            dict = 'amb@world_human_drinking@coffee@male@base',
            clip = 'base',
            flag = 49,
        },
    },

    ---@field Carry: table [fireman carry settings]
    Carry = {
        ---@field useRequest: boolean [if true the target must accept the carry request]
        useRequest = true,
        ---@field stopCarryKey: string [key to stop carrying]
        stopCarryKey = 'E',

        ---@field animation: table [carry anims - { carried: { dict, clip, flag, offset }, carrying: { dict, clip, flag } }]
        animation = {
            carried = {
                dict = 'nm',
                clip = 'firemans_carry',
                flag = 33,
                offset = {
                    coords   = vector3(0.25, -0.05, 0.63),
                    rotation = vector3(0.25, 0.0, 180.0),
                },
            },
            carrying = {
                dict = 'missfinale_c2mcs_1',
                clip = 'fin_c2_mcs_1_camman',
                flag = 49,
            },
        },

        ---@field onRequest: function [target-side carry request prompt; return true to accept - (playerId: number)]
        onRequest = function(playerId)
            local result = false
            local timer = 0
            Bridge.Notify.showNotify(locale('player_request_carry', playerId))
            while timer < 500 do
                Citizen.Wait(1)
                timer += 1
                if IsControlJustReleased(0, 38) then -- E
                    result = true
                    break
                end
            end
            return result
        end,
    },

    ---@field HeadBag: table [head bag prop attachment - { model: string, bone: number, coords: vector3, rotation: vector3 }]
    HeadBag = {
        model = 'prop_money_bag_01',
        bone  = 12844,
        coords   = vector3(0.2, 0.04, 0.0),
        rotation = vector3(0.0, 270.0, 60.0),
    },

    ---@field MouthTape: table [mouth tape prop + tape/remove animation]
    MouthTape = {
        ---@field model: string [tape prop model]
        model = 'e_ducktape',
        ---@field bone: number [bone index to attach to]
        bone  = 20623,
        ---@field coords: vector3 [attachment offset]
        coords   = vector3(0.02, 0.0, 0.0),
        ---@field rotation: vector3 [attachment rotation]
        rotation = vector3(-98.18, -8.4, 85.04),
        ---@field progressAnim: table [animation while taping/removing - { dict, clip, flag }]
        progressAnim = { dict = 'random@train_tracks', clip = 'idle_e', flag = 1 },
        ---@field progressTime: number [tape/remove progress duration in milliseconds]
        progressTime = 5000,
    },

    ---@field Search: table [player search - { duration: number(ms), animation: { dict, clip } }]
    Search = {
        duration = 5500,
        animation = {
            dict = 'anim@gangops@facility@servers@bodysearch@',
            clip = 'player_search',
        },
    },

    ---@field DisableKeys: table [control ids handled per state, keyed by 'hardcuff'/'cuff'/'drag' = number[] (hardcuff lists ENABLED keys, others list DISABLED keys)]
    DisableKeys = {
        ['hardcuff'] = {
            0, 1, 2, 249,
        },
        ['cuff'] = {
            24, 257, 25, 263, 45, 22, 44, 37, 23, 21, 288, 289, 170, 75,
            167, 73, 199, 59, 71, 72, 47, 264, 257, 140, 141, 142, 143,
        },
        ['drag'] = {
            24, 257, 25, 263, 45, 22, 44, 37, 23, 21, 288, 289, 170, 75,
            167, 73, 199, 59, 71, 72, 47, 264, 257, 140, 141, 142, 143,
        },
    },

    ---@field PoliceMenu: table [radial/command police menu - { enabled: boolean, key: string, command: string }]
    PoliceMenu = {
        enabled = true,
        key = 'F6',
        command = 'policemenu',
    },

    ---@field Targets: table [ox_target/qb-target options shown on players, keyed by a unique name (add/remove/reorder freely)]
    ---@field Targets.entry: table [{ label: string, icon: string, distance: number, groups?: table, items?: string, type?: string, canInteract: fun(entity, seat?): boolean, onSelect: fun(data, seat?) }]
    Targets = {
        ['HardCuffPlayer'] = {
            label = locale('hard_cuff_player'),
            icon = 'fa-solid fa-handcuffs',
            distance = 2,
            groups = nil,
            canInteract = function(entity)
                local I = Interactions
                local cf = I.resolve(entity)
                if not cf.canAct or cf.id == 0 then return false end
                local s = cf.s
                if s.isCuffed or s.draggedBy or s.carriedBy then return false end
                if not (s.isDead or I.isHandsUp(cf) or Config.Jobs[I.getJob(cf).name]) then return false end
                return I.getItemCount(cf, 'handcuffs') >= 1
            end,
            onSelect = function(data)
                local entity = type(data) == 'number' and data or data.entity
                local targetId = GetPlayerServerId(NetworkGetPlayerIndexFromPed(entity))
                local isInFront = Interactions:isInFront(entity)
                TriggerServerEvent('p_policejob/server/interactions/HandCuffs', {
                    type = 'cuffs', state = true, player = targetId, front = isInFront, isHard = true,
                })
            end,
        },
        ['CuffPlayer'] = {
            label = locale('cuff_player'),
            icon = 'fa-solid fa-handcuffs',
            distance = 2,
            canInteract = function(entity)
                local I = Interactions
                local cf = I.resolve(entity)
                if not cf.canAct or cf.id == 0 then return false end
                local s = cf.s
                if s.isCuffed or s.draggedBy or s.carriedBy then return false end
                if not (s.isDead or I.isHandsUp(cf) or Config.Jobs[I.getJob(cf).name]) then return false end
                return I.getItemCount(cf, 'handcuffs') >= 1
            end,
            onSelect = function(data)
                local entity = type(data) == 'number' and data or data.entity
                local targetId = GetPlayerServerId(NetworkGetPlayerIndexFromPed(entity))
                local isInFront = Interactions:isInFront(entity)
                TriggerServerEvent('p_policejob/server/interactions/HandCuffs', {
                    type = 'cuffs', state = true, player = targetId, front = isInFront,
                })
            end,
        },
        ['UnCuffPlayer'] = {
            label = locale('uncuff_player'),
            icon = 'fa-solid fa-handcuffs',
            distance = 2,
            canInteract = function(entity)
                local I = Interactions
                local cf = I.resolve(entity)
                if not cf.canAct or cf.id == 0 then return false end
                local s = cf.s
                if s.draggedBy then return false end
                if not s.isCuffed or s.cuffType == 'cable_ties' then return false end
                if Config.Interactions.Cuffs.cuffKeys then
                    return I.getItemCount(cf, 'cuffs_key', tonumber(cf.id)) >= 1
                end
                return I.getItemCount(cf, 'handcuffs') >= 1
            end,
            onSelect = function(data)
                local entity = type(data) == 'number' and data or data.entity
                local targetId = GetPlayerServerId(NetworkGetPlayerIndexFromPed(entity))
                TriggerServerEvent('p_policejob/server/interactions/HandCuffs', {
                    type = 'cuffs', state = false, player = targetId,
                })
            end,
        },
        ['ZipPlayer'] = {
            label = locale('zip_player'),
            icon = 'fa-solid fa-handcuffs',
            distance = 2,
            canInteract = function(entity)
                local I = Interactions
                local cf = I.resolve(entity)
                if not cf.canAct or cf.id == 0 then return false end
                local s = cf.s
                if s.isCuffed or s.draggedBy then return false end
                if not (I.isHandsUp(cf) or Config.Jobs[I.getJob(cf).name]) then return false end
                return I.getItemCount(cf, 'cable_ties') >= 1
            end,
            onSelect = function(data)
                local entity = type(data) == 'number' and data or data.entity
                local targetId = GetPlayerServerId(NetworkGetPlayerIndexFromPed(entity))
                local isInFront = Interactions:isInFront(entity)
                TriggerServerEvent('p_policejob/server/interactions/HandCuffs', {
                    type = 'cable_ties', state = true, player = targetId,
                    timer = true, time = Config.Interactions.Cuffs.cableTieTimer, front = isInFront,
                })
            end,
        },
        ['UnZipPlayer'] = {
            label = locale('unzip_player'),
            icon  = 'fa-solid fa-handcuffs',
            distance = 2,
            canInteract = function(entity)
                local I = Interactions
                local cf = I.resolve(entity)
                if not cf.canAct or cf.id == 0 then return false end
                local s = cf.s
                if s.draggedBy then return false end
                return s.isCuffed and s.cuffType == 'cable_ties'
            end,
            onSelect = function(data)
                local entity = type(data) == 'number' and data or data.entity
                local targetId = GetPlayerServerId(NetworkGetPlayerIndexFromPed(entity))
                TriggerServerEvent('p_policejob/server/interactions/HandCuffs', {
                    type = 'cable_ties', state = false, player = targetId,
                })
            end,
        },
        ['LockpickHandcuffs'] = {
            label = locale('open_cuffs'),
            icon  = 'fa-solid fa-lock-open',
            distance = 2,
            canInteract = function(entity)
                local I = Interactions
                local cf = I.resolve(entity)
                if not cf.canAct or cf.id == 0 then return false end
                local s = cf.s
                if s.draggedBy then return false end
                if not s.isCuffed or s.cuffType == 'cable_ties' then return false end
                return I.getItemCount(cf, 'lockpick') >= 1
            end,
            onSelect = function(data)
                local entity = type(data) == 'number' and data or data.entity
                local targetId = GetPlayerServerId(NetworkGetPlayerIndexFromPed(entity))
                TriggerServerEvent('p_policejob/server/interactions/OpenCuffs', { player = targetId })
            end,
        },
        ['SearchPlayer'] = {
            label = locale('search_player'),
            icon  = 'fa-solid fa-wallet',
            distance = 2,
            canInteract = function(entity)
                local I = Interactions
                local cf = I.resolve(entity)
                if not cf.canAct or cf.id == 0 then return false end
                local s = cf.s
                if s.draggedBy then return false end
                return s.isCuffed or I.isTargetDead(s) or I.isHandsUp(cf)
            end,
            onSelect = function(data)
                local entity = type(data) == 'number' and data or data.entity
                local targetId = GetPlayerServerId(NetworkGetPlayerIndexFromPed(entity))
                Interactions:searchPlayer(entity, targetId)
            end,
        },
        ['StartDragPlayer'] = {
            label = locale('start_drag'),
            icon  = 'fa-solid fa-people-pulling',
            distance = 2,
            canInteract = function(entity)
                local I = Interactions
                local cf = I.resolve(entity)
                if not cf.canAct or cf.id == 0 then return false end
                local s = cf.s
                if s.draggedBy then return false end
                return s.isCuffed or I.isTargetDead(s)
            end,
            onSelect = function(data)
                local entity = type(data) == 'number' and data or data.entity
                local targetId = GetPlayerServerId(NetworkGetPlayerIndexFromPed(entity))
                TriggerServerEvent('p_policejob/server/interactions/DragPlayer', { state = true, player = targetId })
            end,
        },
        ['StopDragPlayer'] = {
            label = locale('stop_drag'),
            icon  = 'fa-solid fa-people-pulling',
            distance = 2,
            canInteract = function(entity)
                local cf = Interactions.resolve(entity)
                if cf.id == 0 then return false end
                return cf.s.draggedBy == cache.serverId
            end,
            onSelect = function(data)
                local entity = type(data) == 'number' and data or data.entity
                local targetId = GetPlayerServerId(NetworkGetPlayerIndexFromPed(entity))
                TriggerServerEvent('p_policejob/server/interactions/DragPlayer', { state = false, player = targetId })
            end,
        },
        ['PutMouthTape'] = {
            label = locale('put_mouth_tape'),
            icon  = 'fa-solid fa-tape',
            distance = 2,
            canInteract = function(entity)
                local I = Interactions
                local cf = I.resolve(entity)
                if not cf.canAct or cf.id == 0 then return false end
                local s = cf.s
                if s.draggedBy or s.carriedBy then return false end
                if not s.isCuffed or s.mouthTaped then return false end
                return I.getItemCount(cf, 'mouthtape') >= 1
            end,
            onSelect = function(data)
                local entity = type(data) == 'number' and data or data.entity
                local targetId = GetPlayerServerId(NetworkGetPlayerIndexFromPed(entity))
                local anim = Config.Interactions.MouthTape.progressAnim
                if not Bridge.Progress.Start({
                    duration = Config.Interactions.MouthTape.progressTime,
                    label = locale('putting_mouth_tape'),
                    useWhileDead = false,
                    canCancel = true,
                    disable = { car = true, move = true, combat = true },
                    anim = anim,
                }) then return end
                TriggerServerEvent('p_policejob/server/interactions/ToggleMouthTape', { player = targetId, state = true })
            end,
        },
        ['RemoveMouthTape'] = {
            label = locale('remove_mouth_tape'),
            icon  = 'fa-solid fa-tape',
            distance = 2,
            canInteract = function(entity)
                local I = Interactions
                local cf = I.resolve(entity)
                if not cf.canAct or cf.id == 0 then return false end
                local s = cf.s
                if s.draggedBy or s.carriedBy then return false end
                return s.mouthTaped == true
            end,
            onSelect = function(data)
                local entity = type(data) == 'number' and data or data.entity
                local targetId = GetPlayerServerId(NetworkGetPlayerIndexFromPed(entity))
                local anim = Config.Interactions.MouthTape.progressAnim
                if not Bridge.Progress.Start({
                    duration = Config.Interactions.MouthTape.progressTime,
                    label = locale('removing_mouth_tape'),
                    useWhileDead = false,
                    canCancel = true,
                    disable = { car = true, move = true, combat = true },
                    anim = anim,
                }) then return end
                TriggerServerEvent('p_policejob/server/interactions/ToggleMouthTape', { player = targetId, state = false })
            end,
        },
        ['PutPlayerHeadBag'] = {
            label = locale('put_player_headbag'),
            icon  = 'fa-solid fa-eye-slash',
            distance = 2,
            canInteract = function(entity)
                local I = Interactions
                local cf = I.resolve(entity)
                if not cf.canAct or cf.id == 0 then return false end
                local s = cf.s
                if s.draggedBy or s.hasHeadBag then return false end
                if not (s.isCuffed or I.isHandsUp(cf)) then return false end
                return I.getItemCount(cf, 'headbag') >= 1
            end,
            onSelect = function(data)
                local entity = type(data) == 'number' and data or data.entity
                local targetId = GetPlayerServerId(NetworkGetPlayerIndexFromPed(entity))
                TriggerServerEvent('p_policejob/server/interactions/ToggleHeadBag', { state = true, player = targetId })
            end,
        },
        ['TakeOffPlayerHeadBag'] = {
            label = locale('take_off_player_headbag'),
            icon  = 'fa-solid fa-eye',
            distance = 2,
            canInteract = function(entity)
                local I = Interactions
                local cf = I.resolve(entity)
                if not cf.canAct or cf.id == 0 then return false end
                local s = cf.s
                return not s.draggedBy and s.hasHeadBag == true
            end,
            onSelect = function(data)
                local entity = type(data) == 'number' and data or data.entity
                local targetId = GetPlayerServerId(NetworkGetPlayerIndexFromPed(entity))
                TriggerServerEvent('p_policejob/server/interactions/ToggleHeadBag', { state = false, player = targetId })
            end,
        },
        ['StartCarryPlayer'] = {
            label = locale('start_carry_player'),
            icon  = 'fa-solid fa-hands-holding',
            distance = 2,
            canInteract = function(entity)
                local cf = Interactions.resolve(entity)
                if not cf.canAct or cf.id == 0 then return false end
                return not cf.s.draggedBy
            end,
            onSelect = function(data)
                local entity = type(data) == 'number' and data or data.entity
                local targetId = GetPlayerServerId(NetworkGetPlayerIndexFromPed(entity))
                TriggerServerEvent('p_policejob/server/interactions/StartCarryPlayer', targetId)
            end,
        },
        ['StopCarryPlayer'] = {
            label = locale('stop_carry_player'),
            icon  = 'fa-solid fa-hands-holding',
            distance = 2,
            canInteract = function(entity)
                local cf = Interactions.resolve(entity)
                if cf.id == 0 then return false end
                return cf.s.carriedBy == cache.serverId
            end,
            onSelect = function(data)
                local entity = type(data) == 'number' and data or data.entity
                local targetId = GetPlayerServerId(NetworkGetPlayerIndexFromPed(entity))
                TriggerServerEvent('p_policejob/server/interactions/StopCarryPlayer', targetId)
            end,
        },
        ['CheckGunPowder'] = {
            label = locale('check_gun_powder'),
            icon  = 'fa-solid fa-gun',
            distance = 2,
            groups = Config.Jobs,
            canInteract = function(entity)
                local I = Interactions
                local cf = I.resolve(entity)
                if not cf.canAct or cf.id == 0 then return false end
                local s = cf.s
                if s.draggedBy then return false end
                if not (s.isCuffed or I.isTargetDead(s) or I.isHandsUp(cf)) then return false end
                return Config.Jobs[I.getJob(cf).name] ~= nil
            end,
            onSelect = function(data)
                local entity = type(data) == 'number' and data or data.entity
                local targetId = GetPlayerServerId(NetworkGetPlayerIndexFromPed(entity))
                if not Bridge.Progress.Start({
                    duration = 10000,
                    label = locale('checking_gun_powder'),
                    useWhileDead = false,
                    canCancel = true,
                    disable = { car = true, move = true, combat = true },
                    anim = { dict = 'random@train_tracks', clip = 'idle_e', flag = 1 },
                }) then return end
                TriggerServerEvent('p_policejob/server/interactions/CheckGunPowder', targetId)
            end,
        },
        ['TakeBloodSample'] = {
            label = locale('fetch_blood'),
            icon  = 'fa-solid fa-droplet',
            distance = 2,
            groups = Config.Jobs,
            canInteract = function(entity)
                local I = Interactions
                local cf = I.resolve(entity)
                if not cf.canAct or cf.id == 0 then return false end
                local s = cf.s
                if s.draggedBy then return false end
                if not (s.isCuffed or I.isTargetDead(s) or I.isHandsUp(cf)) then return false end
                if Config.Jobs[I.getJob(cf).name] ~= nil then return false end
                return I.getItemCount(cf, 'evidence_kit') >= 1 and I.getItemCount(cf, 'swab_kit') >= 1
            end,
            onSelect = function(data)
                local entity = type(data) == 'number' and data or data.entity
                local targetId = GetPlayerServerId(NetworkGetPlayerIndexFromPed(entity))
                if not Bridge.Progress.Start({
                    duration = 5000,
                    label = locale('fetching_blood'),
                    useWhileDead = false,
                    canCancel = true,
                    disable = { car = true, move = true, combat = true },
                    anim = { dict = 'amb@medic@standing@kneel@base', clip = 'base', flag = 1 },
                }) then return end
                TriggerServerEvent('p_policejob/server/interactions/TakeBloodSample', targetId)
            end,
        },
        ['TakeFingerprintSample'] = {
            label = locale('fetch_finger_print'),
            icon  = 'fa-solid fa-fingerprint',
            distance = 2,
            groups = Config.Jobs,
            canInteract = function(entity)
                local I = Interactions
                local cf = I.resolve(entity)
                if not cf.canAct or cf.id == 0 then return false end
                local s = cf.s
                if s.draggedBy then return false end
                if not (s.isCuffed or I.isTargetDead(s) or I.isHandsUp(cf)) then return false end
                if Config.Jobs[I.getJob(cf).name] ~= nil then return false end
                return I.getItemCount(cf, 'evidence_kit') >= 1 and I.getItemCount(cf, 'fingerprint_kit') >= 1
            end,
            onSelect = function(data)
                local entity = type(data) == 'number' and data or data.entity
                local targetId = GetPlayerServerId(NetworkGetPlayerIndexFromPed(entity))
                if not Bridge.Progress.Start({
                    duration = 5000,
                    label = locale('fetching_finger_print'),
                    useWhileDead = false,
                    canCancel = true,
                    disable = { car = true, move = true, combat = true },
                    anim = { dict = 'amb@medic@standing@kneel@base', clip = 'base', flag = 1 },
                }) then return end
                TriggerServerEvent('p_policejob/server/interactions/TakeFingerprintSample', targetId)
            end,
        },
        ['ScanFingerprint'] = {
            label = locale('scan_fingerprint'),
            icon  = 'fa-solid fa-fingerprint',
            distance = 2,
            groups = Config.Jobs,
            canInteract = function(entity)
                local I = Interactions
                local cf = I.resolve(entity)
                if not cf.canAct or cf.id == 0 then return false end
                local s = cf.s
                if s.draggedBy then return false end
                -- Target must be restrained / subdued to be scanned.
                if not (s.isCuffed or I.isTargetDead(s) or I.isHandsUp(cf)) then return false end
                if Config.Scanner and Config.Scanner.requireItem
                    and I.getItemCount(cf, Config.Scanner.item) < 1 then return false end
                return true
            end,
            onSelect = function(data)
                local entity = type(data) == 'number' and data or data.entity
                local targetId = GetPlayerServerId(NetworkGetPlayerIndexFromPed(entity))
                TriggerEvent('p_policejob/scanner/scan', targetId, entity)
            end,
        },
        ['SetPlayerBand'] = {
            label = locale('set_gps_band'),
            icon  = 'fa-solid fa-hands-bound',
            distance = 2,
            groups = Config.Jobs,
            canInteract = function(entity)
                local I = Interactions
                local cf = I.resolve(entity)
                if not cf.canAct or cf.id == 0 then return false end
                -- A player who is wearing a tracking band cannot apply one to others.
                if LocalPlayer.state.hasTrackingBand then return false end
                local s = cf.s
                if s.draggedBy or s.hasTrackingBand then return false end
                if not (s.isCuffed or I.isHandsUp(cf)) then return false end
                if I.getItemCount(cf, 'tracking_band') < 1 then return false end
                return Config.Jobs[I.getJob(cf).name] ~= nil
            end,
            onSelect = function(data)
                local entity = type(data) == 'number' and data or data.entity
                local targetId = GetPlayerServerId(NetworkGetPlayerIndexFromPed(entity))
                if not Bridge.Progress.Start({
                    duration = 10000,
                    label = locale('setting_gps_band'),
                    useWhileDead = false,
                    canCancel = true,
                    disable = { car = true, move = true, combat = true },
                    anim = Config.Band.ApplyAnim,
                }) then return end
                TriggerServerEvent('p_policejob/server/band/SetPlayerBand', { player = targetId, state = true })
            end,
        },
        ['RemovePlayerBand'] = {
            label = locale('remove_gps_band'),
            icon  = 'fa-solid fa-hands-bound',
            distance = 2,
            canInteract = function(entity)
                local I = Interactions
                local cf = I.resolve(entity)
                if not cf.canAct or cf.id == 0 then return false end
                local s = cf.s
                if s.draggedBy then return false end
                if not s.hasTrackingBand then return false end
                return true
            end,
            onSelect = function(data)
                local entity = type(data) == 'number' and data or data.entity
                local targetId = GetPlayerServerId(NetworkGetPlayerIndexFromPed(entity))
                local playerJob = Interactions:getJob(entity)
                local bandConfig = Config.Jobs
                
                if bandConfig and bandConfig[playerJob.name] and tonumber(playerJob.grade) >= bandConfig[playerJob.name] then
                    if not Bridge.Progress.Start({
                        duration = 10000,
                        label = locale('removing_gps_band'),
                        useWhileDead = false,
                        canCancel = true,
                        disable = { car = true, move = true, combat = true },
                        anim = Config.Band.RemoveAnim,
                    }) then return end
                    TriggerServerEvent('p_policejob/server/band/SetPlayerBand', { player = targetId, state = false })
                else
                    TriggerServerEvent('p_policejob/server/band/BandAlert', targetId)
                    local game = lib.skillCheck({
                        { areaSize = 30, speedMultiplier = 1.5 },
                    }, { '1', '2', '3', '4' })
                    
                    if game then
                        if not Bridge.Progress.Start({
                            duration = 10000,
                            label = locale('removing_gps_band'),
                            useWhileDead = false,
                            canCancel = true,
                            disable = { car = true, move = true, combat = true },
                            anim = { dict = 'random@train_tracks', clip = 'idle_e', flag = 1 },
                        }) then return end
                        TriggerServerEvent('p_policejob/server/band/SetPlayerBand', { player = targetId, state = false })
                    end
                end
            end,
        },
        ['UseBreathalyzer'] = {
            label = locale('breathalyzer_target_label'),
            icon  = 'fa-solid fa-wine-bottle',
            distance = 2,
            items = 'breathalyzer',
            groups = Config.Jobs,
            canInteract = function(entity)
                local I = Interactions
                local cf = I.resolve(entity)
                if not cf.canAct or cf.id == 0 then return false end
                local s = cf.s
                if s.draggedBy then return false end
                if I.isTargetDead(s) then return false end
                if not (Config.Breathalyzer and Config.Breathalyzer.Enabled) then return false end
                return Config.Jobs[I.getJob(cf).name] ~= nil
            end,
            onSelect = function(data)
                local entity = type(data) == 'number' and data or data.entity
                local targetId = GetPlayerServerId(NetworkGetPlayerIndexFromPed(entity))
                TriggerServerEvent('p_policejob/server/breathalyzer/use', targetId)
            end,
        },
        ['UseDrugTestKit'] = {
            label = locale('drug_test_target_label'),
            icon  = 'fa-solid fa-vial',
            distance = 2,
            items = 'drug_test_kit',
            groups = Config.Jobs,
            canInteract = function(entity)
                local I = Interactions
                local cf = I.resolve(entity)
                if not cf.canAct or cf.id == 0 then return false end
                local s = cf.s
                if s.draggedBy then return false end
                if I.isTargetDead(s) then return false end
                if not (Config.DrugTestKit and Config.DrugTestKit.enabled) then return false end
                return Config.Jobs[I.getJob(cf).name] ~= nil
            end,
            onSelect = function(data)
                local entity = type(data) == 'number' and data or data.entity
                local targetId = GetPlayerServerId(NetworkGetPlayerIndexFromPed(entity))
                DrugTestKit:runTargetTest(targetId)
            end,
        },
        ['OutFromVehicle'] = {
            label = locale('out_player_menu'),
            icon  = 'fa-solid fa-car',
            distance = 2,
            type = 'vehicle',
            canInteract = function(entity)
                if not NetworkGetEntityIsNetworked(entity) then return false end
                local I = Interactions
                for seat = -1, 6 do
                    local ped = GetPedInVehicleSeat(entity, seat)
                    if ped and ped ~= 0 and ped ~= cache.ped then
                        local cf = I.resolve(ped)
                        if cf.id ~= 0 and (cf.s.isCuffed or I.isTargetDead(cf.s)) then
                            return true
                        end
                    end
                end
                return false
            end,
            onSelect = function(data)
                local vehicle = type(data) == 'number' and data or data.entity
                if not vehicle or vehicle == 0 then return end

                local seatLabels = {
                    [-1] = locale('driver_seat'),
                    [0]  = locale('passenger_seat'),
                    [1]  = locale('back_left_passenger'),
                    [2]  = locale('back_right_passenger'),
                }

                local options = {}
                for seat = -1, 6 do
                    local ped = GetPedInVehicleSeat(vehicle, seat)
                    if ped and ped ~= 0 and ped ~= cache.ped then
                        local targetId = GetPlayerServerId(NetworkGetPlayerIndexFromPed(ped))
                        if targetId ~= 0 then
                            local tState = Player(targetId).state
                            if tState.isCuffed or Editable:isPlayerDead(targetId) then
                                options[#options + 1] = {
                                    title = seatLabels[seat] or locale('addon_seat'),
                                    icon = 'fa-solid fa-car',
                                    onSelect = function()
                                        TriggerServerEvent('p_policejob/server/interactions/OutVehicle', { seat = seat, player = targetId })
                                    end,
                                }
                            end
                        end
                    end
                end

                if #options == 0 then
                    return Bridge.Notify.showNotify(locale('no_players_nearby'), 'error')
                end

                lib.registerContext({
                    id = 'p_policejob_out_vehicle',
                    title = locale('select_seat'),
                    options = options,
                })
                lib.showContext('p_policejob_out_vehicle')
            end,
        },
        ['PutInVehicle'] = {
            label = locale('put_player_in_vehicle'),
            icon  = 'fa-solid fa-car',
            distance = 2,
            canInteract = function(entity)
                local I = Interactions
                local cf = I.resolve(entity)
                if not cf.canAct or cf.id == 0 then return false end
                local s = cf.s
                if not (s.isCuffed or s.draggedBy == cache.serverId or I.isTargetDead(s)) then return false end
                local vehicle = lib.getClosestVehicle(GetEntityCoords(cache.ped), 4.0, false)
                if not vehicle or vehicle == 0 or not NetworkGetEntityIsNetworked(vehicle) then return false end
                for i = -1, 6 do
                    if IsVehicleSeatFree(vehicle, i) then return true end
                end
                return false
            end,
            onSelect = function(data)
                local entity = type(data) == 'number' and data or data.entity
                local targetId = GetPlayerServerId(NetworkGetPlayerIndexFromPed(entity))
                local vehicle = lib.getClosestVehicle(GetEntityCoords(cache.ped), 4.0, false)
                if not vehicle or vehicle == 0 then return end

                local seatLabels = {
                    [-1] = locale('driver_seat'),
                    [0]  = locale('passenger_seat'),
                    [1]  = locale('back_left_passenger'),
                    [2]  = locale('back_right_passenger'),
                }

                local options = {}
                for i = -1, 6 do
                    if IsVehicleSeatFree(vehicle, i) then
                        options[#options + 1] = {
                            title = seatLabels[i] or locale('addon_seat'),
                            icon = 'fa-solid fa-car',
                            onSelect = function()
                                TriggerServerEvent('p_policejob/server/interactions/PutInVehicle', { seat = i, player = targetId })
                            end,
                        }
                    end
                end

                lib.registerContext({
                    id = 'p_policejob_put_in_vehicle',
                    title = locale('select_seat'),
                    options = options,
                })
                lib.showContext('p_policejob_put_in_vehicle')
            end,
        },
    },

    ---@field OnPlayerCuff: function [CLIENT - runs on the cuffed player when cuffing starts (lock down controls/targeting/phone)]
    OnPlayerCuff = function()
        local ped = cache.ped
        SetEnableHandcuffs(ped, true)
        DisablePlayerFiring(ped, true)
        SetCurrentPedWeapon(ped, `WEAPON_UNARMED`, true)
        SetPedCanPlayGestureAnims(ped, false)
        LocalPlayer.state.invBusy = true
        LocalPlayer.state.invHotkeys = false
        LocalPlayer.state.canUseWeapons = false
        if lib.disableRadial then lib.disableRadial(true) end
        if GetResourceState('ox_target') == 'started' then
            exports['ox_target']:disableTargeting(true)
        elseif GetResourceState('qb-target') == 'started' then
            exports['qb-target']:AllowTargeting(false)
        end
        if GetResourceState('lb-phone') == 'started' then
            exports['lb-phone']:ToggleDisabled(true)
        end
    end,

    ---@field OnPlayerUnCuff: function [CLIENT - runs on the player when uncuffed (restore controls/targeting/phone)]
    OnPlayerUnCuff = function()
        local ped = cache.ped
        SetEnableHandcuffs(ped, false)
        DisablePlayerFiring(ped, false)
        SetPedCanPlayGestureAnims(ped, true)
        LocalPlayer.state.invBusy = false
        LocalPlayer.state.invHotkeys = true
        LocalPlayer.state.canUseWeapons = true
        if lib.disableRadial then lib.disableRadial(false) end
        if GetResourceState('ox_target') == 'started' then
            exports['ox_target']:disableTargeting(false)
        elseif GetResourceState('qb-target') == 'started' then
            exports['qb-target']:AllowTargeting(true)
        end
        if GetResourceState('lb-phone') == 'started' then
            exports['lb-phone']:ToggleDisabled(false)
        end
    end,

    ---@field OnStartPlayerDrag: function [CLIENT - runs on the dragged player when a drag starts]
    OnStartPlayerDrag = function()
        LocalPlayer.state.invBusy = true
        LocalPlayer.state.invHotkeys = false
        LocalPlayer.state.canUseWeapons = false
        if lib.disableRadial then lib.disableRadial(true) end
        if GetResourceState('ox_target') == 'started' then
            exports['ox_target']:disableTargeting(true)
        elseif GetResourceState('qb-target') == 'started' then
            exports['qb-target']:AllowTargeting(false)
        end
        if GetResourceState('lb-phone') == 'started' then
            exports['lb-phone']:ToggleDisabled(true)
        end
    end,

    ---@field OnStopPlayerDrag: function [CLIENT - runs on the dragged player when a drag stops]
    OnStopPlayerDrag = function()
        LocalPlayer.state.invBusy = LocalPlayer.state.isCuffed and true or false
        LocalPlayer.state.invHotkeys = true
        LocalPlayer.state.canUseWeapons = true
        if lib.disableRadial then lib.disableRadial(false) end
        if GetResourceState('ox_target') == 'started' then
            exports['ox_target']:disableTargeting(false)
        elseif GetResourceState('qb-target') == 'started' then
            exports['qb-target']:AllowTargeting(true)
        end
        if GetResourceState('lb-phone') == 'started' then
            exports['lb-phone']:ToggleDisabled(false)
        end
    end,

    ---@field onCuff_Server: function [SERVER - called when cuffing starts - (playerId: number, targetId: number, cuffType: string)]
    onCuff_Server = function(playerId, targetId, cuffType) end,

    ---@field onUnCuff_Server: function [SERVER - called when uncuffing - (playerId: number, targetId: number, cuffType: string)]
    onUnCuff_Server = function(playerId, targetId, cuffType) end,
}