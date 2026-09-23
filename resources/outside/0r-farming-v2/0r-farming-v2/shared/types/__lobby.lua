---@class LobbyMember
---@field source number
---@field level number

---@class Lobby
---@field id number
---@field members LobbyMember[]
---@field owner number
---@field currentTask CurrentTask

---@class CurrentTask
---@field moduleName string
---@field startTime number
---@field infoBoxTable string[]
---@field game table
