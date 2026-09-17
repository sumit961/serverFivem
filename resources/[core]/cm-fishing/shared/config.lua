CMFishing = CMFishing or {}

CMFishing.Config = {
    Debug = false,

    interactKey = 38, -- E
    interactKeyLabel = 'E',
    interactDistance = 2.2,

    -- ==========================================================
    -- RODS & BAIT
    -- Sold at the Fishing Store NPC. Rods never break or get consumed --
    -- they're a one-time purchase; only bait is spent per cast.
    -- `waitDivisor` shortens the bite timer (higher = faster bites).
    -- ==========================================================
    Rods = {
        basic_rod = { label = 'Basic Rod', price = 50, image = 'basic_rod.png', waitDivisor = 1.0, requiredLevel = 0, description = 'A reliable starter rod. Never breaks.' },
        rod_2 = { label = 'Rod Level 2', price = 100, image = 'rod_2.png', waitDivisor = 1.5, requiredLevel = 2, description = 'Shortens the wait for a bite. Never breaks.' },
        rod_3 = { label = 'Rod Level 3', price = 150, image = 'rod_3.png', waitDivisor = 2.0, requiredLevel = 3, description = 'The fastest bites in the game. Never breaks.' },
    },

    -- `rarityWeight` multiplies a fish's catch weight when it's that
    -- rarity, biasing the roll toward better fish -- so bait choice
    -- actually changes what you pull in, not just how long you wait.
    -- `saveChance` is the chance (0-1) the bait is NOT used up on a given
    -- cast, so better bait tends to last through more casts on average.
    Bait = {
        worms = {
            label = 'Worms', price = 5, image = 'worms.png',
            waitDivisor = 1.0, saveChance = 0.0,
            rarityWeight = {},
            description = 'Cheap and reliable. No bonus to catch odds, and always used up on every cast.',
        },
        commonbait = {
            label = 'Common Bait', price = 10, image = 'commonbait.png',
            waitDivisor = 2.0, saveChance = 0.2,
            rarityWeight = { Rare = 1.3, Epic = 1.15 },
            description = 'Faster bites and noticeably better odds at Rare+ fish. 1 in 5 casts do not use it up.',
        },
        artificial_bait = {
            label = 'Artificial Bait', price = 15, image = 'artificial_bait.png',
            waitDivisor = 3.5, saveChance = 0.4,
            rarityWeight = { Rare = 1.5, Epic = 1.35, Mythic = 1.2, Legend = 1.1 },
            description = 'The fastest bites and the best odds at rare, high-value fish. Lasts several casts on average -- 2 in 5 casts do not use it up.',
        },
    },

    -- ==========================================================
    -- FISH
    -- chance = weight used for the weighted catch roll (relative,
    -- not a percent). rarity drives the UI badge colour. skillcheck
    -- is a list of difficulties ('easy'|'medium'|'hard') - one is
    -- picked at random when the fish bites.
    -- ==========================================================
    RaritySellPrice = {
        Common = 15,
        Rare = 35,
        Epic = 60,
        Mythic = 100,
        Legend = 180,
    },

    Fish = {
        anchovy     = { label = 'Anchovy', chance = 35, rarity = 'Common', xpReward = 5, requiredLevel = 0, skillcheck = { 'easy', 'medium' }, description = 'A small, plentiful baitfish. Easy skill check, low reward -- good for a first catch.' },
        trout       = { label = 'Trout', chance = 35, rarity = 'Common', xpReward = 4, requiredLevel = 0, skillcheck = { 'easy', 'medium' }, description = 'A common freshwater catch. Easy skill check, low reward.' },
        fish        = { label = 'Fish', chance = 40, rarity = 'Common', xpReward = 3, requiredLevel = 0, skillcheck = { 'easy', 'medium' }, description = 'Just a fish. The most common catch on the coast -- easy, but barely worth anything.' },

        piranha     = { label = 'Piranha', chance = 25, rarity = 'Rare', xpReward = 8, requiredLevel = 1, skillcheck = { 'easy', 'medium', 'hard' }, description = 'Sharp-toothed and quick to bite -- a wider spread of skill checks than Common fish.' },
        grouper     = { label = 'Grouper', chance = 25, rarity = 'Rare', xpReward = 8, requiredLevel = 1, skillcheck = { 'easy', 'medium', 'medium' }, description = 'A stocky reef fish. Decent XP for a moderate fight.' },
        stingray    = { label = 'Stingray', chance = 15, rarity = 'Rare', xpReward = 9, requiredLevel = 1, skillcheck = { 'easy', 'medium', 'medium' }, description = 'Lurks near the sea floor. Uncommon enough to sell for a bit more.' },

        haddock     = { label = 'Haddock', chance = 20, rarity = 'Epic', xpReward = 14, requiredLevel = 2, skillcheck = { 'medium', 'medium' }, description = 'A deeper-water catch -- needs level 2 and a steadier hand on the reel.' },
        salmon      = { label = 'Salmon', chance = 10, rarity = 'Epic', xpReward = 15, requiredLevel = 2, skillcheck = { 'medium', 'medium', 'hard' }, description = 'A strong swimmer that puts up a real fight on the reel. Good XP and a solid sale price.' },

        red_snapper = { label = 'Red Snapper', chance = 20, rarity = 'Mythic', xpReward = 22, requiredLevel = 3, skillcheck = { 'medium', 'hard' }, description = 'A prized catch found at Paleto Bay. Sells well and pays out strong XP.' },
        mahi_mahi   = { label = 'Mahi Mahi', chance = 20, rarity = 'Mythic', xpReward = 22, requiredLevel = 3, skillcheck = { 'medium', 'hard' }, description = 'Fast and colorful open-water fish. High value, needs level 3.' },
        humpback    = { label = 'Humpback Whale', chance = 1, rarity = 'Mythic', xpReward = 30, requiredLevel = 4, skillcheck = { 'hard', 'hard' }, description = 'Extremely rare and a hard fight both skill checks -- but pays out accordingly.' },
        killerwhale = { label = 'Killer Whale', chance = 1, rarity = 'Mythic', xpReward = 30, requiredLevel = 4, skillcheck = { 'hard', 'hard' }, description = 'Only found at the remote spot. As tough to land as it is valuable.' },

        tuna        = { label = 'Tuna', chance = 5, rarity = 'Legend', xpReward = 40, requiredLevel = 5, skillcheck = { 'hard', 'hard' }, description = 'The top-tier open-water catch. Needs max level and a hard skill check, but the payout matches.' },
        shark       = { label = 'Shark', chance = 1, rarity = 'Legend', xpReward = 45, requiredLevel = 5, skillcheck = { 'hard', 'hard' }, description = 'A dangerous, rare trophy catch from the remote spot. Legend rarity -- the best sale price in the game.' },
        tigershark  = { label = 'Tiger Shark', chance = 1, rarity = 'Legend', xpReward = 45, requiredLevel = 5, skillcheck = { 'hard', 'hard' }, description = 'One of the rarest catches on the map. Hard skill check both ways, top-tier reward.' },
        hammershark = { label = 'Hammerhead Shark', chance = 2, rarity = 'Legend', xpReward = 45, requiredLevel = 5, skillcheck = { 'hard', 'hard' }, description = 'A Legend-rarity trophy. Slightly more common than the other sharks, still a hard fight.' },
        dolphin     = { label = 'Dolphin', chance = 3, rarity = 'Legend', xpReward = 45, requiredLevel = 5, skillcheck = { 'hard', 'hard' }, description = 'A rare and prized catch at the remote spot. Top rarity, top payout.' },
    },

    -- ==========================================================
    -- CATCH MINIGAME
    -- A moving target drifts along a 0-100 track; the player slides
    -- a catch window over it with A/D (or Left/Right) to fill the
    -- progress bar before time runs out.
    -- ==========================================================
    MinigameSettings = {
        easy = { windowWidth = 32, targetSpeed = 34, moveSpeed = 55, gainRate = 60, lossRate = 28, timeLimitMs = 13000 },
        medium = { windowWidth = 24, targetSpeed = 50, moveSpeed = 60, gainRate = 48, lossRate = 40, timeLimitMs = 12000 },
        hard = { windowWidth = 17, targetSpeed = 68, moveSpeed = 65, gainRate = 40, lossRate = 55, timeLimitMs = 11000 },
        -- Forced for every heavy-fish catch (see HeavyFish below), regardless
        -- of the fish's own skillcheck list -- tougher than 'hard' since this
        -- is something well above the angler's gear/level tier.
        heavy = { windowWidth = 12, targetSpeed = 85, moveSpeed = 70, gainRate = 34, lossRate = 65, timeLimitMs = 10000 },
    },

    -- ==========================================================
    -- DEPTH
    -- How far the player is casting from shore, derived from distance to
    -- the nearest fishing zone's anchor point (which sits right at the
    -- dock/coastline) relative to that zone's radius. Fishing outside any
    -- configured zone (open ocean) always counts as deep water.
    -- Deeper water biases toward rarer fish, and is the only place a low
    -- level angler can hook something above their normal tier (see
    -- HeavyFish below) or run into a shark.
    -- ==========================================================
    Depth = {
        shallowRadiusFactor = 0.35, -- distance <= radius * this = shallow
        mediumRadiusFactor = 0.7,   -- distance <= radius * this = medium, beyond = deep
        fallbackShallow = 40.0,     -- used outside any zone (shouldn't normally hit -- open water is deep)
        fallbackMedium = 90.0,

        rarityWeight = {
            shallow = {},
            medium = { Rare = 1.2, Epic = 1.1 },
            deep = { Rare = 1.4, Epic = 1.3, Mythic = 1.25, Legend = 1.2 },
        },
    },

    -- ==========================================================
    -- HEAVY FISH
    -- A small chance for a level 0-2 angler fishing in medium/deep water to
    -- hook something above their normal level tier -- "something too big
    -- for your gear". Landing it still works like any other catch, but
    -- risks snapping the rod on the way in (the one exception to rods
    -- otherwise never breaking).
    -- ==========================================================
    HeavyFish = {
        maxAnglerLevel = 2, -- only rollable at or below this level
        chanceByDepth = { shallow = 0.0, medium = 0.08, deep = 0.08 }, -- flat 8% in medium/deep water
        rodBreakChance = 35, -- percent, only rolled for a heavy-fish catch
    },

    -- ==========================================================
    -- SHARK ENCOUNTER
    -- Rolled instead of a normal bite while waiting on a line cast in deep
    -- water. Interrupts the cast (no catch) and briefly puts a hostile
    -- shark ped on the player instead.
    -- ==========================================================
    SharkEncounter = {
        enabled = true,
        chancePerDeepBite = 0.08,
        damage = 25,
        models = { `a_c_sharktiger`, `A_C_SharkHammer` },
    },

    -- ==========================================================
    -- FISHING SPOTS
    -- Reuses real Los Santos/Blaine County coordinates so zones are
    -- usable immediately. Adjust freely for this server's map.
    -- ==========================================================
    FishingAreas = {
        {
            key = 'karnaval',
            label = 'Vespucci Fishing Spot',
            coords = vector3(-1870.6555, -1220.9153, 13.0170),
            radius = 90.0,
            minLevel = 0,
            waitTime = { min = 3, max = 9 },
            fishList = { 'anchovy', 'trout', 'fish', 'salmon', 'piranha' },
            blip = { enabled = true, sprite = 317, color = 29, scale = 0.6, name = 'Fishing Spot' },
        },
        {
            key = 'stabscity',
            label = 'Paleto Bay Fishing Spot',
            coords = vector3(-170.9095, 4153.7803, 31.6733),
            radius = 90.0,
            minLevel = 1,
            waitTime = { min = 4, max = 10 },
            fishList = { 'mahi_mahi', 'tuna', 'salmon', 'stingray', 'grouper', 'red_snapper' },
            blip = { enabled = true, sprite = 317, color = 29, scale = 0.6, name = 'Fishing Spot' },
        },
        {
            key = 'illegalspot',
            label = 'Remote Fishing Spot',
            coords = vector3(3671.7588, 4967.5903, 15.9253),
            radius = 110.0,
            minLevel = 2,
            waitTime = { min = 5, max = 12 },
            fishList = { 'dolphin', 'hammershark', 'tigershark', 'trout', 'fish', 'piranha', 'grouper', 'shark', 'humpback', 'killerwhale' },
            blip = { enabled = false },
        },
    },

    OutsideFishing = {
        enabled = true,
        waitTime = { min = 10, max = 22 },
        fishList = { 'trout', 'anchovy', 'haddock', 'salmon' },
    },

    -- ==========================================================
    -- STORE NPC (buy rods/bait, sell fish, rent a boat - same NPC,
    -- tabbed UI). Placed at the Vespucci dock, right by the water.
    -- ==========================================================
    Store = {
        coords = vector4(-1827.3832, -1246.1781, 13.0173, 320.1692),
        model = 'a_m_m_skater_01',
        interactDistance = 2.2,
        blip = { enabled = true, sprite = 356, color = 2, scale = 0.7, name = 'Fishing Store' },
    },

    -- ==========================================================
    -- BOAT RENTAL
    -- Spawned through cm-vehicles' trusted-placement bridge (see its
    -- Config.Placement.authorizedResources), the same mechanism
    -- cm-electrician uses for its service truck -- the boat comes out
    -- owned by the renting player's own character (lockable, keyed)
    -- instead of a bare admin prop. Rented through the same Fishing
    -- Store NPC/menu above, not a separate NPC. One boat at a time per
    -- player; renting a new one or walking away and asking to return it
    -- deletes whatever they already had out.
    -- ==========================================================
    BoatRental = {
        enabled = true,
        spawnCoords = {
            vector4(-1795.8723, -1227.4860, 0.9236, 139.6530),
            vector4(-1789.5032, -1230.3000, 0.1764, 164.8888),
        },
        list = {
            { name = 'seashark', label = 'Sea Shark', price = 500, image = 'https://docs.fivem.net/vehicles/seashark.webp' },
            { name = 'dinghy', label = 'Dinghy', price = 1000, image = 'https://docs.fivem.net/vehicles/dinghy.webp' },
            { name = 'suntrap', label = 'Suntrap', price = 1500, image = 'https://docs.fivem.net/vehicles/suntrap.webp' },
        },
    },

    LevelXP = {
        [0] = 0,
        [1] = 60,
        [2] = 160,
        [3] = 320,
        [4] = 560,
        [5] = 900, -- max level
    },

    Security = {
        castCooldownMs = 1200,
        actionRangeSlack = 3.0,
    },
}
