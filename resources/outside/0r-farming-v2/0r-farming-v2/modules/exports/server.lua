local Utils = require "modules.utils.server"

---@param lobby Lobby
---@param task Task
---@return boolean
---Called before a task starts in the given lobby.
---Return `true` to allow the task to start, or `false` to prevent it.
function server.exports.beforeTaskStart(lobby, task)
    -- ? You can use this to check if the lobby has the required items, permissions, or conditions to start the task.
    -- ? If you return `false`, the task will not start and the players will be notified.
    return true
end

---@param lobby Lobby
---@param task Task
---Called after a task has successfully started in the given lobby.
---Use this to initialize task-related server-side logic.
function server.exports.onTaskStarted(lobby, task)
    -- ? This is where you can set up task data, targets, or notify players.
    -- ? You can also use this to initialize any server-side data related to the task.
end

---@param lobby Lobby
---@param lastTask Task
---Called after a task has successfully stopped in the given lobby.
---Use this to finalize task data, give rewards, or clean up.
function server.exports.onTaskStopped(lobby, lastTask)
    -- ? This is where you can finalize task data, give rewards, or clean up.
end
