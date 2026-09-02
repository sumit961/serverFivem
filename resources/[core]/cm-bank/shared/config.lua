CMBank = CMBank or {}

CMBank.Config = {
    Debug = false,

    interactKey = 38, -- E / INPUT_CONTEXT
    interactKeyLabel = 'E',
    interactDistance = 1.6, -- how close to a real ATM prop before the prompt shows
    detectDistance = 20.0,  -- how far the client scans for the nearest ATM prop

    -- Real in-world ATM/Fleeca props. Clients discover these automatically,
    -- but v1.4 treats a brand-new coordinate as advisory only. An admin must
    -- verify a newly discovered ATM once before it can authorize banking or
    -- ownership. Previously saved ATM rows remain trusted during the upgrade.
    AtmModels = {
        'prop_atm_01',
        'prop_atm_02',
        'prop_atm_03',
        'prop_fleeca_atm',
    },

    Interaction = {
        title = 'ATM',
        hint = 'Deposit, withdraw or send money',
    },

    Perf = {
        farSleep = 1500, -- ms between scans when no ATM is within detectDistance
        nearSleep = 400, -- ms when an ATM is nearby but out of interactDistance
        activeSleep = 0, -- ms when standing at the ATM (responsive E press)
    },

    -- v1.7.0: cm-bank is a gameplay banking system, not a realistic banking
    -- simulator. There is deliberately no maximum deposit/withdraw/transfer
    -- amount, no daily/weekly/monthly cap, and no ATM-vs-teller amount
    -- distinction — a player may move any amount they can actually afford.
    -- `minAmount` is a positive-integer floor, not a gameplay restriction.
    Limits = {
        minAmount = 1,
        transferFeePercent = 0, -- 0 = no fee, e.g. 2 = 2% fee taken from the sender on transfers
    },

    Security = {
        actionCooldownMs = 900,    -- per-player cooldown between deposit/withdraw/transfer requests
        transferCooldownMs = 3000, -- extra cooldown specifically between player-to-player transfers
        atmReportCooldownMs = 2000, -- per-player cooldown on ATM-location discovery reports
        atmReportMaxPlayerDistance = 23.0, -- discovery reports farther than this from the server-known player position are rejected
    },

    -- v1.5.0: character-ID transfer spam/abuse controls. Server-authoritative —
    -- enforced inside the locked transfer handler regardless of what the NUI
    -- submit button allows, so a modified/replayed client can't bypass this.
    -- These are anti-spam/anti-double-click protections, not amount limits —
    -- they never block or reduce how much money a transfer moves.
    TransferSecurity = {
        cooldownMs = 1500,          -- minimum time between transfer requests for one player (on top of Security.transferCooldownMs)
        maxTransfersPerMinute = 10, -- sliding-window cap per player, tracked server-side only
        largeTransferWarning = 100000, -- NUI-only "please double-check the recipient" prompt above this amount; 0 disables it. Never blocks the transfer.
    },

    -- v1.7.0: the amount floor for character-ID transfers. There is
    -- deliberately no maximumPerTransfer or dailyLimit here anymore — v1.5
    -- shipped both, and this release removes them as a gameplay decision
    -- (see CHANGELOG_v1.7.0.md). Kept as its own table for compatibility
    -- with anything still reading `Config.TransferLimits.minimum`.
    TransferLimits = {
        minimum = 1,
    },


    -- v1.7.0: saved Character ID payees. Nickname is only a personal label —
    -- the actual transfer always uses the authoritative Character ID.
    Payees = {
        maxPayees = 30,
        maxFavourites = 6,
        nicknameMaxLength = 40,
    },

    -- v1.6.0: player-owned ATMs now have a physical cash reserve that
    -- withdrawals actually consume (separate from the withdrawal fee, which
    -- still goes straight to pending_earnings). All figures are per-ATM in
    -- the DB (bank_atm_locations.cash_reserve/cash_capacity); these are only
    -- the defaults applied when a value has never been initialized.
    ATMBusiness = {
        defaultCashCapacity = 100000,     -- capacity newly-migrated owned ATMs get
        startingCashReserve = 50000,      -- reserve newly-migrated owned ATMs get
        purchaseStartingReserve = 25000,  -- government-provided reserve on purchase; NOT counted as owner contribution
        reserveStatus = {
            lowPercent = 25,     -- reserve/capacity <= this % => "low"
            criticalPercent = 10, -- reserve/capacity <= this % => "critical"
        },
    },

    -- v1.6.0: unowned/public ATMs also track a cash reserve so the same
    -- "not enough cash" rule can apply everywhere, but they should not be
    -- annoying to use. `automaticRestock` tops them up on a server-only
    -- timer (never via a client-triggered event). Setting `infiniteCash`
    -- (or `useCashReserve = false`) skips reserve checks entirely for
    -- public ATMs if the restock system is more than a server wants —
    -- player-owned ATMs are NEVER allowed to use this escape hatch.
    PublicATM = {
        useCashReserve = true,
        defaultCashCapacity = 250000,
        automaticRestock = true,
        restockThreshold = 50000,
        restockTarget = 250000,
        infiniteCash = false,
    },

    -- Small cash-icon blip shown on the map for every ATM location once it has
    -- been discovered and verified (see AtmBlip discovery below). Locations
    -- are learned as players walk near real props, then shared with everyone
    -- only after server-side approval via /atmverify.
    AtmBlip = {
        enabled = true,
        sprite = 500, -- radar_production_mo
        color = 2,    -- green
        scale = 0.7,  -- small
        label = 'ATM',
        shortRange = true,
    },

    -- Player-ownable ATMs. `enabled` is only the fallback used until the live
    -- value is loaded from cm_bank_settings (admins flip it at runtime with
    -- no restart via /atmownership on|off).
    --
    -- v1.4 charges ATM business fees on WITHDRAWALS only. Deposits and
    -- character-ID transfers do not pay an ATM-owner fee; bank tellers are free.
    -- An unowned ATM uses unownedFeePercent as a withdrawal service fee that is
    -- not collected by anyone. An owned ATM lets its owner choose 1/2/3/4%;
    -- that withdrawal fee accrues into the ATM business balance.
    Ownership = {
        enabled = true,
        purchasePrice = 15000,       -- paid from the buyer's bank balance
        unownedFeePercent = 2,       -- withdrawal fee at an ATM nobody owns; burned rather than collected
        feeChoices = { 1, 2, 3, 4 }, -- owner-selectable withdrawal fee options
        governmentSellPercent = 80,  -- % of purchasePrice paid back when an owner sells to the government
        maxOwnedPerCharacter = 1,    -- an owner must sell their current ATM before buying another
    },

    -- Bank tellers: NPCs that open the same deposit/withdraw/transfer panel
    -- as an ATM (never the Own tab — there's no ATM to buy at a teller).
    -- Unlike ATMs there's no real world prop to scan for, so locations are
    -- never auto-discovered. Two ways a teller ends up in bank_tellers:
    --   1. Seeded once from BankLocations below (server/main.lua skips a
    --      branch whose name already exists, so removing/renaming one in
    --      game sticks across restarts instead of being recreated).
    --   2. An admin adds one anywhere else with /addbankteller <name> while
    --      standing where the NPC should stand, and removes one with
    --      /removebankteller while standing next to it.
    Tellers = {
        enabled = true,
        model = 'a_m_m_business_01', -- a universally-valid ambient ped; client falls back to this automatically if a custom model fails to load
        scenario = 'WORLD_HUMAN_STAND_IMPATIENT',
        speakDistance = 6.0,     -- how far away their floating name tag is visible / greeting sound triggers
        interactDistance = 1.8,  -- how close before E opens the bank panel

        -- Played once via PlaySoundFrontend when you first come within
        -- speakDistance (not repeated until you leave and come back).
        greetSound = { name = 'CHECKPOINT_NORMAL', set = 'HUD_MINI_GAME_SOUNDSET' },

        -- Map blip for every teller location — a distinct sprite/colour from
        -- the street ATM blips (AtmBlip above) so a full branch reads
        -- distinct from a lone ATM at a glance.
        Blip = {
            enabled = true,
            sprite = 605, -- radar_nhp_starterpac
            color = 3,   -- blue
            scale = 0.85,
            shortRange = true,
        },
    },

    -- Default CM Bank branches (the standard Fleeca-style building
    -- locations). Each is seeded once as a teller named "<name> Teller".
    BankLocations = {
        { name = 'Legion Square',       coords = vector4(149.4113, -1042.0449, 29.3680, 342.9182) },
        { name = 'Rockford Hills',      coords = vector4(-1211.8585, -331.9854, 37.7809, 28.5983) },
        { name = 'Great Ocean Highway', coords = vector4(-2961.0720, 483.1107, 15.6970, 88.1986) },
        { name = 'Paleto Bay',          coords = vector4(-112.2223, 6471.1128, 31.6267, 132.7517) },
        { name = 'Pillbox Hill',        coords = vector4(313.8176, -280.5338, 54.1647, 339.1609) },
        { name = 'Burton',              coords = vector4(-351.3247, -51.3466, 49.0365, 339.3305) },
        { name = 'Sandy Shores',        coords = vector4(1174.9718, 2708.2034, 38.0879, 178.2974) },
        { name = 'Vinewood',            coords = vector4(247.0348, 225.1851, 106.2875, 158.7528) },
    },
}

-- Shared coordinate-rounding key so client discovery reports and the server's
-- dedupe/storage agree on what counts as "the same ATM".
function CMBank.CoordKey(x, y, z)
    return ('%d_%d_%d'):format(
        math.floor((tonumber(x) or 0) * 10 + 0.5),
        math.floor((tonumber(y) or 0) * 10 + 0.5),
        math.floor((tonumber(z) or 0) * 10 + 0.5)
    )
end
