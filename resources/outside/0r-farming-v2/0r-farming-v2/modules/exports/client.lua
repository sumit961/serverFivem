local Utils = require "modules.utils.client"

---@param source number
---@param task MultiplayerTask
---@return boolean
---Called before a task starts.
---Return `true` to allow the task to start, or `false` to block it.
function client.exports.beforeTaskStart(source, task)
    -- ? You can use this to check if the player has the required items, permissions, or conditions to start the task.
    -- ? If you return `false`, the task will not start and the player will be notified.

    return true
end

---@param source number
---@param task MultiplayerTask
---Called after a task has successfully started.
---You can use this to set up task data, targets, or notify the player.
function client.exports.onTaskStarted(source, task)
    -- ? You can use this to set up task data, targets, or notify the player.
    -- ? This is where you can initialize any UI elements or client-side data related to the task.
end

---@param source number
---@param lastTask MultiplayerTask
---Called after a task has been successfully stopped.
---Use this to clean up, give rewards, or log the completion.
function client.exports.onTaskStopped(source, lastTask)
    -- ? This is where you can give rewards, log the completion, or clean up any task-related data.
    -- ? You can also use this to notify the player of their rewards or task completion status
end
