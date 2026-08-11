return {
    jobs = {
        ['police'] = 1, -- KADET
        ['sheriff'] = 1,
    },
    blips = {
        {label = 'LSPD Dept.', coords = vec3(430.28, -981.30, 30.71), sprite = 60, color = 29, scale = 0.95},
        {label = 'Police Armoury', coords = vec3(452.28, -980.30, 30.71), sprite = 110, color = 29, scale = 0.95, jobOnly = true},
    },
    -- Trash bins. Each entry creates a sphere zone with "Open Trash" (a shared
    -- disposal stash you can drop items into) and "Empty Trash" (wipes it).
    trashes = {
        { coords = vec3(446.34, -1004.23, 30.77), radius = 1.0, distance = 2.0 },
    },

    -- Locker access points. Each entry creates a sphere zone with an "Open
    -- Locker" target that opens the locker input dialog (type your locker ID).
    lockers = {
        { coords = vec3(449.91, -997.79, 30.97), radius = 1.0, distance = 2.0 },
    },

    -- CCTV control point(s). Each entry creates a sphere-zone target with a
    -- "Watch cameras" option that opens the CCTV viewing menu. This replaces the
    -- old /cctv and /cctv_menu chat commands. Access is still gated by
    -- Config.CCTV.defaultJobs. Adjust coords to your CCTV room.
    cctv = {
        { coords = vec3(441.88, -974.39, 30.84), radius = 1.0, distance = 2.0, label = 'Watch cameras' },
    },

    duty = {
        {
            coords = vec4(449.92, -987.29, 30.71, 183.00),
            radius = 1.2,
            distance = 2.0,
            ped = {
                model = 's_m_y_cop_01',
                scenario = 'WORLD_HUMAN_CLIPBOARD',
            },
        },
    },

    armouries = {
        {
            coords = vec4(449.33, -1005.42, 30.71, 0.00),
            ped = {
                model = 's_m_y_cop_01',
                scenario = 'WORLD_HUMAN_GUARD_STAND',
                -- anim = {
                --     dict = 'missheistdockssetup1ig_10@idle_a',
                --     name = 'idle_a',
                -- },
                onCreate = function(ped)
                end
            },
            items = {
                {name = 'WEAPON_PISTOL', price = 100, category = 'weapons'},
                {name = 'WEAPON_COMBATPISTOL', price = 100, category = 'weapons'},
                {name = 'WEAPON_PUMPSHOTGUN', price = 100, category = 'weapons'},
                {name = 'WEAPON_CARBINERIFLE', price = 1000, category = 'weapons'},
                {name = 'WEAPON_STUNGUN', price = 100, category = 'weapons'},
                {name = 'WEAPON_FLASHLIGHT', price = 0, category = 'weapons'},
                {name = 'WEAPON_NIGHTSTICK', price = 100, category = 'weapons'},
                {name = 'handcuffs', price = 100, category = 'misc'},
                {name = 'body_cam', price = 100, category = 'misc'},
                {name = 'radio', price = 50, category = 'misc'},
            }
        }
    },

    extras = {
        {coords = vector3(419.6291, -1020.9120, 29.0104), size = 10.0, label = 'MRPD Garage'},
    },

    garages = {
        ['mrpd'] = {
            label = 'Mission Row Garage',
            blip = { enabled = true, coords = vector3(434.68, -1029.12, 28.99), sprite = 357, color = 3, scale = 0.75, label = 'Police Garage' },
            ped = { model = 's_m_y_cop_01', coords = vec4(434.6770, -1029.1232, 28.9886, 0.0), anim = { dict = 'amb@world_human_cop_idles@male@idle_b', clip = 'idle_e' }, onCreate = function(ped) end },
            allowedJobs = { ['police'] = 1, ['sheriff'] = 1 },
            spawnPoints = {
                vector4(431.7113, -1027.2172, 28.9471, 179.8748),
                vector4(427.6960, -1027.6909, 28.9821, 182.6840),
                vector4(424.0269, -1028.0519, 29.0469, 184.6641),
                vector4(420.0333, -1028.3597, 29.1166, 186.3764),
                vector4(416.5734, -1028.6340, 29.1769, 185.2027),
            },

            -- Darmowe radiowozy służbowe (addon Gabz) — dostępne w garażu wg rangi
            vehicles = {
                ['police'] = {
                    [1] = {
                        ['gbpolstanier'] = 'Stanier LE Patrol',
                        ['gbpoladmiral'] = 'Admiral Patrol',
                    },
                    [2] = {
                        ['gbpolimpaler'] = 'Impaler Patrol',
                    },
                    [3] = {
                        ['gbpolargento7f'] = 'Argento 7F Patrol',
                    },
                    [4] = {
                        ['gbpolesperta'] = 'Esperta Patrol',
                        ['gbpolsteedvan'] = 'Steed Van Patrol',
                    },
                    [6] = {
                        ['gbpolscoutgsx'] = 'Scout GSX Patrol',
                        ['gbpolgresley'] = 'Gresley Patrol',
                    },
                    [8] = {
                        ['gbpolbisonstx'] = 'Bison STX Patrol',
                        ['gbpolbisonhf'] = 'Bison HF Patrol',
                    },
                    [10] = {
                        ['gbpolhedra'] = 'Hedra Patrol',
                        ['gbpolmojave'] = 'Mojave Patrol',
                    },
                    [12] = {
                        ['gbpolsultanrsx'] = 'Sultan RSx Interceptor',
                        ['gbpoldomgsx'] = 'Dominator GSX Interceptor',
                    },
                    [14] = {
                        ['gbpolcomets2r'] = 'Comet S2R Interceptor',
                        ['gbpolprospero'] = 'Prospero Tactical',
                    },
                    [16] = {
                        ['gbpoltr3s'] = 'TR3-S Interceptor',
                        ['gbpolterrorizer'] = 'Terrorizer SWAT',
                    },
                },
                ['sheriff'] = {
                    [1] = {
                        ['gbpolstanier'] = 'Stanier LE Patrol',
                        ['gbpoladmiral'] = 'Admiral Patrol',
                    },
                    [6] = {
                        ['gbpolscoutgsx'] = 'Scout GSX Patrol',
                        ['gbpolmojave'] = 'Mojave Patrol',
                    },
                },
            },
        },
    },

    laboratories = {
        {
            coords = vec3(467.16, -1001.60, 34.25),
            heading = 180.0,
            label = 'LSPD Crime Lab',
            jobs = {['police'] = 6, ['sheriff'] = 6}, -- SIERZANT I
            blip = {sprite = 458, color = 38, scale = 0.7, label = 'Crime Lab'},
        },
    },

    vehicleShops = {
        ['mrpd'] = {
            label = 'MRPD Fleet Management',
            blip = {
                enabled = true,
                coords = vector3(458.5, -1017.5, 28.0),
                sprite = 326,
                color = 29,
                scale = 0.8,
                label = 'Police Vehicle Shop',
            },
            ped = {
                model = 's_m_y_cop_01',
                coords = vec4(456.87, -1005.11, 24.45, 79.00),
                scenario = 'WORLD_HUMAN_CLIPBOARD',
            },
            camera = {
                coords = vector3(452.8807, -1008.0911, 25.4525),
                pointAt = vector3(447.0822, -1007.7623, 24.2025),
                fov = 60.0,
            },
            vehicleSpawn = vector4(447.0822, -1007.7623, 24.4525, 232.5105),
            purchaseSpawn = vector4(447.1640, -1019.9455, 24.4525, 355.5745),
            allowedJobs = {
                ['police']  = 6, -- SIERZANT I (zakup floty)
                ['sheriff'] = 6,
            },
        },
    },

    mugshots = {
        ['Mission_Row'] = {
            coords = vector3(454.47, -980.56, 27.5),
            photoCoords = vector3(451.0381, -980.3453, 27.8340),
            cameraCoords = vector3(452.9016, -980.3027, 28.3120),
            cameraFov = 40.0,
            jobs = {
                ['police'] = 2, -- OFICER I
            },
        },
    },

    bodycams = {
        ['Mission_Row'] = {
            coords = vector3(447.39, -992.86, 30.69),
            radius = 0.5,
            jobs = {
                ['police']  = 1, -- KADET
                ['sheriff'] = 1,
            },
        },
    },
}