---@class PersonalChallenge
---@field id string
---@field label string
---@field description string
---@field objective PersonalChallengeObjective
---@field reward ChallengeReward
---@field currentLevel integer

---@class ChallengeReward
---@field exp integer
---@field money integer

---@class PersonalChallengeObjective
---@field label string
---@field targetName string | "any"
---@field type "planted" | "watered" | "harvested" | "harvested_bale"
---@field baseTarget integer -- Temel hedef değeri
---@field target integer -- Mevcut seviye için hesaplanmış hedef
---@field progress integer
---@field scalingMultiplier number -- Her level için artış katsayısı (örn: 1.2 = %20 artış)
