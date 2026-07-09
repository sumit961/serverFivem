# Single-prompt interaction arbiter (player menu <-> vehicle menu)

Goal: when a player **and** a vehicle are both in view, show only ONE G prompt,
without merging the two resources. Each resource keeps its own menu; they just
agree on who owns the prompt this frame via a shared local statebag.

cm-playerdata's half is already wired (v1.9.13+). You only need to add the mirror
to your **vehicle interaction resource**.

## How it works
- cm-playerdata publishes `LocalPlayer.state.cmPlayerInteractDist` = distance to
  its current player target (or `false` when it has none).
- Your vehicle resource publishes `LocalPlayer.state.cmVehicleInteractDist` = the
  distance to its current vehicle target (or `false`).
- Each side hides its own G (and refuses to open on G) when the other side wins.
- Tie-break is fixed so near-ties always go to the **player** — this is what
  prevents both prompts showing at the same distance.

Keep `mode` and `tie` below equal to cm-playerdata's
`Interactions.InteractionPriority` and `Interactions.InteractionArbiterTie`.

## Add to your vehicle resource (client)

```lua
-- 1) Publish your vehicle target's distance every frame (false when none).
--    Put this where you decide your vehicle target each frame:
local lastVehDist = false
local function PublishVehicleInteractDist(dist)
    local v = (type(dist) == 'number') and dist or false
    if v ~= lastVehDist then
        lastVehDist = v
        LocalPlayer.state:set('cmVehicleInteractDist', v, false) -- local only
    end
end

-- 2) Decide whether to yield to the player menu.
local function VehicleShouldYield(myVehDist)
    local pDist = LocalPlayer.state.cmPlayerInteractDist
    if type(pDist) ~= 'number' then return false end   -- player has no target

    local mode = 'closest'  -- MUST match Interactions.InteractionPriority
    if mode == 'player'  then return true  end          -- player always wins
    if mode == 'vehicle' then return false end          -- vehicle always wins

    if type(myVehDist) ~= 'number' then return true end
    local tie = 0.1         -- MUST match Interactions.InteractionArbiterTie
    return pDist <= (myVehDist + tie)                    -- player wins ties
end
```

Then in your vehicle loop / prompt draw:

```lua
local dist = <distance from player ped to your target vehicle> -- or nil
PublishVehicleInteractDist(dist)

if myVehicleTarget and not VehicleShouldYield(dist) then
    DrawYourVehicleGPrompt()      -- only draw when you own the prompt
end
```

And in your vehicle G key handler:

```lua
if myVehicleTarget and not VehicleShouldYield(dist) then
    OpenYourVehicleMenu()
end
```

That's it. No cross-resource edits, no merged files — both menus stay in their own
resource and only one G ever shows.

## Notes
- If your vehicle prompt is proximity-based (shows whenever near a car, no aim),
  set `Interactions.InteractionPriority = 'player'` so aiming at a person always
  wins over merely standing next to a car. Use `'closest'` if your vehicle prompt
  is aim-gated like the player one.
- The bags are local (`false` replication) — nothing is sent to the server.
- To disable the arbiter entirely, set `Interactions.InteractionArbiter = false`.
