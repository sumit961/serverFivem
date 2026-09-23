---@class MultiplayerTask
---@field moduleName string -- The module this task belongs to
---@field requiredLevel? number -- Minimum level required to start the task
---@field requiredJobNames string[] -- Job names required to start the task
---@field infoBoxTable string[] -- Table of strings for the task info box
---@field teamSize TeamSize -- Minimum and maximum team size for the task

---@class TeamSize
---@field min number -- Minimum number of players required to start the task
---@field max number -- Maximum number of players allowed to start the task

---@class FreelanceField
---@field center vector3 -- The center coordinates of the farming zone
---@field radius number -- The radius for "sphere" shape or half-width for "box" shape
---@field maxCrops number -- Maximum number of crops allowed in the field
---@field tractor VehicleSpawnPoint -- Tractor spawn point
---@field harvester VehicleSpawnPoint -- Harvester spawn point
---@field trailer VehicleSpawnPoint -- Trailer spawn point

---@class BlipConfig
---@field sprite number -- The sprite ID for the blip
---@field color number -- The color ID for the blip
---@field scale number -- The scale of the blip
---@field name string -- The name of the blip

---@class CropConfig
---@field label string -- The label for the crop
---@field growthTime number -- Time in seconds for the crop to grow
---@field harvestAmount number -- Amount of crop harvested per action
---@field seedItem string -- Item used to plant the crop
---@field harvestItem string -- Item received when harvesting the crop
---@field baleItem string -- Item used for bales of the crop

---@class FieldBlip
---@field center number -- ID of the blip for the field center
---@field radius number -- ID of the blip for the field radius

---@class VehicleSpawnPoint
---@field model string -- The model of the vehicle to spawn
---@field coords vector4 -- Coordinates where the vehicle is spawned

---@class PlantingPoint
---@field coords vector3 -- Coordinates where the planting point is located
---@field groundZ number? -- Ground Z coordinate for the planting point, optional
---@field planted boolean? -- Whether the point has been planted
---@field plantingTime number? -- Time in seconds when the point was planted, optional
---@field cropGrowthTime number? -- Time in seconds for the crop to grow, optional
---@field targetName string? -- Name of the target, optional
---@field cropGrowth number? -- Growth stage of the crop, optional
---@field watered boolean? -- Whether the point has been watered
---@field cropHarvested boolean? -- Whether the crop has been harvested

---@class MelonPumpkinField
---@field center vector3 -- The center coordinates of the farming zone
---@field radius number -- The radius for "sphere" shape or half-width for "box" shape
---@field deliveryVehicle VehicleSpawnPoint -- vehicle spawn point
---@field maxPoints number  -- Maximum number of planting points
---@field rotation number -- Rotation of the field
