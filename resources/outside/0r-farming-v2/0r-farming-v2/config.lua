--[[
    All script settings are found and edited in this file.
    Make sure to configure everything properly before running the script.
]]

Config = {}

---[[ The images folder path of your inventory script ]]
--- So that item names and images will match your inventory - images only PNG !
Config.InventoryImagesFolder = "ox_inventory/web/images/"

--[[ Menu Command ]]
Config.FarmingMenu = {
    -- Command to open the menu.
    openWithCommand = {
        active = true, -- Set to true to enable command-based menu opening.
        command = "farmingmenu",
    },
    -- Keybind to open the menu.
    openWithKey = {
        active = true, -- Set to true to enable keybind-based menu opening.
        key = "F7",
    },
    -- Item to open the menu.
    -- This allows players to open the menu by using a specific item.
    openWithItem = {
        active = true,               -- Set to true to enable item-based menu opening.
        itemName = "farming_tablet", -- The name of the item that opens the menu.
    },
    -- Jobs allowed to open the menu.
    -- If table is empty, all jobs can access the menu.
    -- If you want to restrict access, add specific job names.
    allowedJobs = {
        -- "job-name", -- Replace "job-name" with the actual job names that can access the menu.
    },
}

--[[ Level experience ]]
Config.Levels = { 0, 1000, 2000, 4000, 8000, 10000, 15000 } -- Experience experience for each level. You can adjust or expand as needed.

--[[ Task Info Box Expansion Key ]]
Config.InfoBoxAlign = "left"  -- Alignment of the task info box (left or right).
Config.ToggleInfoBoxKey = "B" -- Key used to toggle additional tasks-related info (e.g., stats, details).

---[[ Money Configuration ]]
Config.CleanMoney = {
    isItem = true,        -- If set to true, clean money will be treated as an item.
    itemName = "cash",    -- The name of the clean money item (if isItem is true).
    accountName = "cash", -- The account name used for dirty money transactions.
    label = "Cash",
}

--[[ Sell NPC Configuration ]]
Config.SellNpc = {
    model = "a_m_m_farmer_01",                                                             -- NPC model for selling harvested bales
    blip = { active = true, sprite = 237, color = 5, scale = 0.8, name = "Farming NPC", }, -- Whether to show a blip for the NPC
    locations = {
        [1] = vector4(2416.1697, 4993.7061, 45.25, 135.0),                                 -- NPC spawn location
    },
}

--[[ Help Text ]]
Config.HelpText = {
    {
        title = "How do I start farming?",
        description =
        "You can start farming by using the command `/farmingmenu`, pressing F7, or using the farming tablet item.",
    },
    {
        title = "How do I use the farming menu?",
        description =
        "The farming menu allows you to manage your farming tasks, view your inventory, and access various farming-related features.",
    },
    {
        title = "What are personal challenges?",
        description =
        "Personal challenges are tasks that you can complete to earn rewards and improve your farming skills.",
    },
    {
        title = "How do I view my current level?",
        description =
        "You can view your current level in the farming menu.",
    },
    {
        title = "How do I start a multiplayer task?",
        description =
        "You can start a multiplayer task in the farming menu.",
    },
    {
        title = "How do I gain experience?",
        description =
        "You gain experience by completing farming tasks, harvesting crops, and finishing personal challenges. Each completed task rewards you with XP.",
    },
    {
        title = "Where can I sell my harvest?",
        description =
        "You can sell your harvested crops and bales to the farming NPC located on the map (look for the farming NPC blip).",
    },
    {
        title = "What is the farming tablet?",
        description =
        "The farming tablet is a special item that allows you to access the farming menu anywhere. Make sure you have it in your inventory.",
    },
    {
        title = "How do I check task information?",
        description =
        "Press the 'B' key to toggle additional task information and view detailed stats about your current farming activities.",
    },
    {
        title = "What happens when I level up?",
        description =
        "When you level up, you unlock new farming opportunities, better rewards, and access to more challenging tasks that yield higher profits.",
    },
    {
        title = "Can I farm with friends?",
        description =
        "Yes! You can participate in multiplayer farming tasks with other players to complete larger projects and earn bonus rewards.",
    },
    {
        title = "How does the money system work?",
        description =
        "Completed farming tasks reward you with cash that goes directly to your account. Some tasks may provide items that can be sold for additional profit.",
    },
    {
        title = "What if I don't have the required job?",
        description =
        "If job restrictions are enabled, you need to have one of the allowed jobs to access the farming system. Contact an administrator for job assignments.",
    },
    {
        title = "How do I track my progress?",
        description =
        "Your farming progress, including experience, level, and completed tasks, is automatically saved and can be viewed in the farming menu.",
    },
    {
        title = "What should I do if the menu won't open?",
        description =
        "Make sure you have the farming tablet item, try using the command `/farmingmenu` or the F7 key. Check if you have the required job permissions.",
    },
}

Config.DisableCustomProps = false -- Set to true to disable custom props/markers for farming locations.

--[[ Debug Mode ]]
Config.debug = false -- Enable (true) or disable (false) debug mode for development/testing.
