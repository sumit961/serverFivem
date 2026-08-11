return {
    blips = {
        { label = 'Bolingbroke Penitentiary', coords = vec3(1845.0, 2585.0, 45.67), sprite = 188, color = 1, scale = 0.85 },
    },
    location = {
        entrance = vector4(1845.0, 2585.0, 45.67, 270.0),
        spawn = vector4(1765.0, 2565.0, 45.56, 180.0),
        release = vector4(1847.96, 2586.02, 45.67, 272.25),
    },
    cells = {
        { id = 1,  label = 'Cell 7-1', coords = vec4(1755.16, 2493.21, 45.65, 221.00) },
        { id = 2,  label = 'Cell 7-2', coords = vec4(1751.99, 2491.55, 45.65, 210.00) },
        { id = 3,  label = 'Cell 7-3', coords = vec4(1749.04, 2489.88, 45.65, 204.00) },
        { id = 4,  label = 'Cell 7-4', coords = vec4(1744.41, 2480.67, 45.65, 296.00) },
        { id = 5,  label = 'Cell 7-5', coords = vec4(1746.09, 2477.86, 45.65, 300.00) },
        { id = 6,  label = 'Cell 7-6', coords = vec4(1747.95, 2474.81, 45.65, 296.00) },
        { id = 7,  label = 'Cell 7-7', coords = vec4(1749.75, 2471.72, 45.65, 296.00) },
        { id = 8,  label = 'Cell 7-8', coords = vec4(1756.50, 2469.24, 45.65, 26.00) },
        { id = 9,  label = 'Cell 7-9', coords = vec4(1759.59, 2471.04, 45.65, 25.00) },
        { id = 10, label = 'Cell 7-10', coords = vec4(1762.74, 2472.70, 45.65, 26.00) },
        { id = 11, label = 'Cell 7-11', coords = vec4(1765.62, 2474.50, 45.65, 38.00) },
        { id = 12, label = 'Cell 7-12', coords = vec4(1771.63, 2477.82, 45.65, 37.00) },
        { id = 13, label = 'Cell 7-13', coords = vec4(1774.70, 2479.55, 45.65, 25.00) },
        { id = 14, label = 'Cell 7-14', coords = vec4(1777.99, 2481.69, 45.65, 33.00) },
        { id = 15, label = 'Cell 7-15', coords = vec4(1780.89, 2483.02, 45.65, 29.00) },
        { id = 16, label = 'Cell 7-16', coords = vec4(1782.54, 2490.69, 45.65, 122.00) },
        { id = 17, label = 'Cell 7-17', coords = vec4(1778.97, 2496.42, 45.65, 119.00) },
        { id = 18, label = 'Cell 7-18', coords = vec4(1777.35, 2499.52, 45.65, 125.00) },
        { id = 19, label = 'Cell 7-19', coords = vec4(1767.42, 2500.68, 45.65, 218.00) },
        { id = 20, label = 'Cell 7-20', coords = vec4(1764.42, 2498.86, 45.65, 217.00) },
        { id = 21, label = 'Cell 7-21', coords = vec4(1761.25, 2496.78, 45.65, 220.00) },
    },

    solitary = {
        vector4(1665.2589, 2574.8105, 45.6676, 270.9410),
        vector4(1665.0786, 2579.6890, 45.6676, 287.1649),
        vector4(1665.2544, 2584.4248, 45.6676, 283.2513),
        vector4(1665.3724, 2589.3093, 45.6676, 271.2954)
    },

    mugshot = {
        peds = {
            {
                model = 's_m_y_cop_01',
                coords = vec4(401.9592, -999.5038, -99.0042, 333.4357),
                anim = {dict = 'anim@amb@nightclub@peds@', clip = 'rcmme_amanda1_stand_loop_cop', flag = 1}
            }
        },
        camera = {
            coords = vector3(402.6915, -1002.3336, -98.7088),
            rotation = vector3(0.0, 0.0, 358.3614),
            fov = 40.0,
        },
        pedCoords = vector4(402.8527, -996.8629, -99.0003, 177.3515),
    },

    commissary = {
        model = 'mp_m_shopkeep_01',
        coords = vec4(1734.14, 2586.84, 45.42, 178.00),
        scenario = 'WORLD_HUMAN_STAND_IMPATIENT',
        -- anim = { dict = 'mp_common', clip = 'givetake1_a', flag = 1 },
    },
    illegalShop = {
        model = 's_m_y_dealer_01',
        coords = vec4(1785.44, 2515.96, 45.57, 184.00),
        scenario = 'WORLD_HUMAN_DRUG_DEALER',
        -- anim = { dict = 'mp_common', clip = 'givetake1_a', flag = 1 },
    },

    jobLocations = {
        cleaning = {
            vec3(1739.63, 2568.62, 44.42),
            vec3(1732.99, 2576.31, 44.42),
            vec3(1725.34, 2573.70, 44.42),
            vec3(1728.78, 2585.59, 44.42),
            vec3(1743.39, 2586.06, 44.42),
            vec3(1747.64, 2575.91, 44.42),
            vec3(1740.05, 2576.50, 44.42),
        },
        laundry = {
            vec3(1591.48, 2540.77, 45.76),
            vec3(1588.73, 2539.44, 45.63),
            vec3(1590.86, 2543.02, 45.92),
            vec3(1595.63, 2549.77, 45.87),
            vec3(1591.67, 2549.59, 45.90),
        },
        kitchen = {
            vec3(1737.45, 2593.33, 45.34),
            vec3(1731.74, 2592.40, 45.38),
            vec3(1732.72, 2601.00, 45.38),
            vec3(1734.73, 2600.88, 45.32),
            vec3(1739.11, 2600.89, 45.34),
            vec3(1739.98, 2589.04, 45.33),
        },
    },

    npcs = {
        {
            label = 'Inmate Tony',
            model = 'a_m_y_musclbeac_02',
            coords = vec4(1780.66, 2483.55, 48.80, 38.00),
            scenario = 'WORLD_HUMAN_STAND_IMPATIENT',
            dialogue = {
                { text = 'Hey, new fish. Want to trade?', action = 'trade' },
                { text = 'I heard the guards are doing inspections tonight.', action = 'info' },
                { text = 'Leave me alone.', action = 'close' },
            },
            -- Items this NPC can trade/sell
            tradeItems = {
                { name = 'burger', label = 'Burger', price = 8, description = 'Fresh from the cafeteria' },
                { name = 'water', label = 'Water Bottle', price = 5, description = 'Clean water' },
                { name = 'cigarette', label = 'Cigarettes', price = 30, description = 'Premium smokes' },
                { name = 'bandage', label = 'Bandage', price = 20, description = 'For emergencies' },
            },
        },
        {
            label = 'Old Man Pete',
            model = 's_m_y_prismuscl_01',
            coords = vec4(1767.91, 2481.79, 45.65, 125.00),
            scenario = 'WORLD_HUMAN_STAND_MOBILE',
            dialogue = {
                { text = 'I can get you what you need, for a price...', action = 'illegal_shop' },
                { text = 'Nothing, forget it.', action = 'close' },
            },
        },
        {
            label = 'Guard Wilson',
            model = 's_m_y_cop_01',
            coords = vec4(1755.18, 2497.32, 45.65, 301.00),
            scenario = 'WORLD_HUMAN_COP_IDLES',
            dialogue = {
                { text = 'I want to work for time reduction.', action = 'prison_jobs' },
                { text = 'When am I getting released?', action = 'check_sentence' },
                { text = 'Nothing, sir.', action = 'close' },
            },
        },
    },

    communityService = {
        location = vector4(121.0037, -1309.7438, 29.2308, 213.7030),
        -- Optional: where the player is placed when released (defaults to location)
        -- release = vector4(228.28, -1371.96, 30.14, 0.0),
        dumpster = vec4(125.39, -1324.88, 29.32, 44.00),
        taskLocations = {
            trash_pickup = {
                vec3(133.82, -1314.48, 28.20),
                vec3(132.45, -1328.10, 28.20),
                vec3(150.61, -1325.35, 28.23),
                vec3(140.88, -1338.79, 28.22),
                vec3(107.40, -1314.75, 28.22),
                vec3(114.37, -1338.63, 28.40),
                vec3(121.08, -1346.60, 28.29),
            },
        },
    },

    officerPatrolWaypoints = {
        vector3(1765.0, 2560.0, 45.56),
        vector3(1770.0, 2570.0, 45.56),
        vector3(1775.0, 2580.0, 45.56),
        vector3(1765.0, 2585.0, 45.56),
        vector3(1755.0, 2575.0, 45.56),
    },
}
