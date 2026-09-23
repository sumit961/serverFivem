
--the following events are available to trigger 'getintrunk' and 'getouttrunk', by any means you would like, whether thats radial menu or another "third eye" script other than qtarget.

--Client.lua example
--TriggerEvent('getintrunk')
--TriggerEvent('getouttrunk')

--Server.lua example
--TriggerClientEvent('getintrunk', source)
--TriggerClientEvent('getouttrunk', source)

Config = {}

Config.textui = false -- requires Config.AllowCommandUse to be true

Config.textuikey = "J"

Config.textuiIn = "Press [%s] to get in trunk"

Config.textuiOut = "Press [%s] to get out trunk"

Config.target = true --if not using or you are using another target system. set to false.
Config.targetSystem = 'ox_target' -- Qtarget | ox_target | Qb-target

Config.Usebones = false --set this to true to target the vehicles trunk only

Config.AllowCommandUse = true

Config.GetInLockedVehicles = false --stop players getting in and out of locked trunks

Config.LimitPeople = true -- If false you can use the script without a framework.

Config.MaxDistance = 2.5 --max distance player can be from trunk to get in

Config.Outtrunkicon = "fas fa-box-circle-check"

Config.Outtrunkcmd = "outtrunk"

Config.Intrunkicon = "fas fa-box-circle-check"

Config.Intrunkcmd = "intrunk"

Config.CanRemoveFromTrunk = true

Config.removefromtrunkicon = "fas fa-box-circle-check"

Config.removefromtrunkcmd = "pullouttrunk"

Config.putintrunkcmd = "putintrunk"

Config.putintrunkicon = "fas fa-box-circle-check"

Config.CamOffsets = {
   [0] = {
      x = 0.0, y = -2.85, z = 0.25 --Compacts
   },
   [1] = {
      x = 0.0, y = -2.95, z = 0.25 --Sedans
   },
   [2] = {
      x = 0.0, y = -3.5, z = 0.25 --SUVs
   },
   [3] = {
      x = 0.0, y = -2.85, z = 0.25 --Coupes
   },
   [4] = {
      x = 0.0, y = -2.85, z = 0.25 --Muscle
   },
   [5] = {
      x = 0.0, y = -2.85, z = 0.25 --Sports classics
   },
   [6] = {
      x = 0.0, y = -2.85, z = 0.25 --Sports
   },
   [7] = {
      x = 0.0, y = -2.85, z = 0.25 --Super
   },
   [9] = {
      x = 0.0, y = -2.85, z = 0.25 --Off-road
   },
   [10] = {
      x = 0.0, y = -2.85, z = 0.25 --Industrial
   },
   [11] = {
      x = 0.0, y = -2.85, z = 0.25 --Utility
   },
   [12] = {
      x = 0.0, y = -2.85, z = 0.25 --Vans
   },
   [17] = {
      x = 0.0, y = -2.85, z = 0.25 --Service
   },
   [18] = {
      x = 0.0, y = -2.85, z = 0.25 --Emergency
   },
   [19] = {
      x = 0.0, y = -2.85, z = 0.25 --Military
   },
   [20] = {
      x = 0.0, y = -2.85, z = 0.25 --Commercial
   }
}

Config.blacklist = {
   [`police`] = true
}