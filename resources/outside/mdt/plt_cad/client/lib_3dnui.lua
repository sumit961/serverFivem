CR3D = {}

-- ----------------------------------------------------------
-- CONFIG  -  library-wide defaults
-- ----------------------------------------------------------
CR3D.CONFIG = {
    renderDistance = 10.0,  -- metres; panels beyond this are skipped
    activeWait     = 0,     -- Wait() ms when panels are visible (per-frame)
    idleWait       = 100,   -- Wait() ms when no panels are in range
}

-- ----------------------------------------------------------
-- PANELS  -  registry of all live panels
-- Key = tostring(panelId), Value = panel data table
-- ----------------------------------------------------------
CR3D.PANELS = {}

-- ----------------------------------------------------------
-- ATTACHMENTS  -  optional entity attachment data per panel
-- Key = tostring(panelId), Value = attachment table
-- ----------------------------------------------------------
CR3D.ATTACHMENTS = {}

-- Auto-incrementing panel ID counter
CR3D.NEXT_ID = 1


-- ============================================================
-- SECTION 1 - Vector math helpers
-- All helpers operate on vector3 values and return vector3.
-- ============================================================

-- vecAdd(a, b) -> a + b
function CR3D.vecAdd(vecA, vecB)
    return vector3(
        vecA.x + vecB.x,
        vecA.y + vecB.y,
        vecA.z + vecB.z
    )
end

-- vecSub(a, b) -> a - b
function CR3D.vecSub(vecA, vecB)
    return vector3(
        vecA.x - vecB.x,
        vecA.y - vecB.y,
        vecA.z - vecB.z
    )
end

-- vecMul(v, scalar) -> v * scalar
function CR3D.vecMul(vec, scalar)
    return vector3(
        vec.x * scalar,
        vec.y * scalar,
        vec.z * scalar
    )
end

-- vecDot(a, b) -> dot product (scalar)
function CR3D.vecDot(vecA, vecB)
    return (vecA.x * vecB.x)
         + (vecA.y * vecB.y)
         + (vecA.z * vecB.z)
end

-- vecCross(a, b) -> cross product (vector3)
function CR3D.vecCross(vecA, vecB)
    return vector3(
        (vecA.y * vecB.z) - (vecA.z * vecB.y),
        (vecA.z * vecB.x) - (vecA.x * vecB.z),
        (vecA.x * vecB.y) - (vecA.y * vecB.x)
    )
end

-- vecLen(v) -> Euclidean length (scalar)
function CR3D.vecLen(vec)
    return math.sqrt(
        (vec.x * vec.x) +
        (vec.y * vec.y) +
        (vec.z * vec.z)
    )
end

-- vecDistSq(a, b) -> squared distance (scalar, cheaper than vecLen)
function CR3D.vecDistSq(vecA, vecB)
    local dx = vecA.x - vecB.x
    local dy = vecA.y - vecB.y
    local dz = vecA.z - vecB.z
    return (dx * dx) + (dy * dy) + (dz * dz)
end

-- vecNorm(v) -> unit vector in the direction of v.
-- Returns vector3(0,0,0) if v is effectively zero-length.
function CR3D.vecNorm(vec)
    local len = CR3D.vecLen(vec)
    if len < 1e-4 then
        return vector3(0.0, 0.0, 0.0)
    end
    return vector3(
        vec.x / len,
        vec.y / len,
        vec.z / len
    )
end


-- ============================================================
-- SECTION 2 - Panel basis computation
-- Builds an oriented coordinate frame (center, normal, right, up)
-- for a rectangular panel in world space, used by the render
-- thread and the raycast helper.
-- ============================================================

-- makePanelBasis(pos, normal, width, height, zOffset, _unused1, _unused2, depthMode, upHint)
--   pos         - world-space centre position of the panel
--   normal      - surface normal (which way the panel faces)
--   width       - panel width in metres
--   height      - panel height in metres
--   zOffset     - optional scalar offset along the normal
--   _unused1    - reserved (false)
--   _unused2    - reserved (false)
--   depthMode   - "screen" uses 0.004 z-nudge; anything else uses 0.002
--   upHint      - optional preferred "up" vector for orientation
--
-- Returns a table:
--   { center, normal, right, up, halfW, halfH }
function CR3D.makePanelBasis(pos, normal, width, height, zOffset, _unused1, _unused2, depthMode, upHint)
    -- Normalise the surface normal
    local normDir = CR3D.vecNorm(normal)

    -- Determine z-nudge: push the panel slightly towards the viewer
    -- to avoid z-fighting with geometry behind it.
    local nudge = zOffset
    if not zOffset then
        if depthMode == "screen" then
            nudge = 0.004
        else
            nudge = 0.002
        end
    end

    -- Compute the panel centre (pos + normDir * nudge)
    local center = CR3D.vecAdd(pos, CR3D.vecMul(normDir, nudge))

    -- Resolve the "up" hint into a normalised vector.
    -- Fall back to world-up (0, 0, 1) if none provided.
    local upVec
    if upHint then
        upVec = CR3D.vecNorm(upHint)
    end
    if not upVec then
        upVec = vector3(0.0, 0.0, 1.0)
    end

    -- Compute the "right" axis: cross(normal, upHint)
    local rightVec = CR3D.vecCross(normDir, upVec)
    local rightLen = CR3D.vecLen(rightVec)

    -- If normal and upHint are nearly parallel, the cross product
    -- degenerates.  Fall back to world-right (0, 1, 0) as up hint.
    if rightLen < 0.001 then
        upVec    = vector3(0.0, 1.0, 0.0)
        rightVec = CR3D.vecCross(normDir, upVec)
    end

    -- Normalise right, then recompute a clean up from cross(right, normal)
    rightVec = CR3D.vecNorm(rightVec)
    local upFinal = CR3D.vecNorm(CR3D.vecCross(rightVec, normDir))

    -- If an upHint was given, ensure our computed up agrees with it
    -- (flip both right and up if the dot product is negative).
    if upHint then
        local upHintNorm = CR3D.vecNorm(upHint)
        if CR3D.vecDot(upFinal, upHintNorm) < 0.0 then
            upFinal  = CR3D.vecMul(upFinal,  -1.0)
            rightVec = CR3D.vecMul(rightVec, -1.0)
        end
    end

    return {
        center = center,
        normal = normDir,
        right  = rightVec,
        up     = upFinal,
        halfW  = width  * 0.5,
        halfH  = height * 0.5,
    }
end


-- ============================================================
-- SECTION 3 - DUI texture helpers (internal)
-- ============================================================

-- initDui(panel)
-- Creates a DUI surface and binds it to a runtime texture for
-- the given panel table.  Safe to call more than once; skips if
-- panel.dui already exists.
local function initDui(panel)
    if panel.dui then
        return  -- already initialised
    end

    -- Default resolution 10241024 if not specified
    local resW = panel.resW or 1024
    local resH = panel.resH or 1024

    -- Create the DUI (browser surface)
    panel.dui = CreateDui(panel.url, resW, resH)

    -- Get the raw DUI handle needed for CreateRuntimeTextureFromDuiHandle
    local duiHandle = GetDuiHandle(panel.dui)

    -- Build unique texture dictionary / texture names from the panel id
    panel.txdName = ("plt_txd_%s"):format(panel.id)
    panel.texName = ("plt_tex_%s"):format(panel.id)

    -- Create a runtime TXD and bind the DUI surface to it
    local txd = CreateRuntimeTxd(panel.txdName)
    CreateRuntimeTextureFromDuiHandle(txd, panel.texName, duiHandle)
end

-- destroyDui(panel)
-- Destroys the DUI surface for a panel and clears panel.dui.
local function destroyDui(panel)
    if panel and panel.dui then
        DestroyDui(panel.dui)
        panel.dui = nil
    end
end


-- ============================================================
-- SECTION 4 - Public panel API
-- ============================================================

-- CR3D.CreatePanel(opts) -> panelId
-- Creates and registers a new 3D NUI panel.
-- opts fields:
--   id                - (optional) forced ID; auto-assigned if nil
--   url               - DUI browser URL
--   resW, resH        - DUI resolution (default 1024)
--   pos               - vector3 world position (default 0,0,0)
--   normal            - vector3 surface normal (default 0,0,1)
--   up                - optional vector3 up hint
--   width, height     - panel size in metres (default 1.0)
--   alpha             - 0-255 transparency (default 255)
--   enabled           - bool; panel renders when true (default false)
--   zOffset           - depth compensation scalar
--   depthCompensation - "screen" or other string (affects z-nudge)
function CR3D.CreatePanel(opts)
    -- Determine panel ID
    local panelId = opts.id or CR3D.NEXT_ID
    CR3D.NEXT_ID  = CR3D.NEXT_ID + 1

    -- Build the panel data table with defaults
    local panel = {
        id     = panelId,
        url    = opts.url,
        resW   = opts.resW  or 1024,
        resH   = opts.resH  or 1024,
        pos    = opts.pos    or vector3(0, 0, 0),
        normal = opts.normal or vector3(0, 0, 1),
        up     = opts.up,
        width  = opts.width  or 1.0,
        height = opts.height or 1.0,
        alpha  = opts.alpha  or 255,
        -- Convert to explicit bool: false ~= false -> true; false ~= nil -> true; false ~= false -> false
        enabled           = (false ~= opts.enabled),
        zOffset           = opts.zOffset,
        depthCompensation = opts.depthCompensation,
    }

    -- Initialise the DUI surface immediately
    initDui(panel)

    -- Register in the global panel table (key is string for consistency)
    CR3D.PANELS[tostring(panelId)] = panel

    return panelId
end

-- CR3D.DestroyPanel(panelId)
-- Removes a panel, destroys its DUI, and clears its attachment.
function CR3D.DestroyPanel(panelId)
    local key = tostring(panelId)
    local panel = CR3D.PANELS[key]
    if panel then
        destroyDui(CR3D.PANELS[key])
        CR3D.PANELS[key]      = nil
        CR3D.ATTACHMENTS[key] = nil
    end
end

-- CR3D.SendMessage(panelId, msgTable)
-- Sends a JSON-encoded message to the DUI browser of the panel.
function CR3D.SendMessage(panelId, msgTable)
    local key   = tostring(panelId)
    local panel = CR3D.PANELS[key]
    if panel and panel.dui then
        SendDuiMessage(panel.dui, json.encode(msgTable))
    end
end

-- CR3D.SendMouseMove(panelId, normX, normY)
-- Sends a mouse-move event to the DUI browser.
-- normX, normY are normalised panel UV coordinates (0.0-1.0).
-- They are scaled to pixel coordinates using the panel resolution.
function CR3D.SendMouseMove(panelId, normX, normY)
    local key   = tostring(panelId)
    local panel = CR3D.PANELS[key]
    if panel and panel.dui then
        local pixelX = math.floor(normX * (panel.resW or 1024))
        local pixelY = math.floor(normY * (panel.resH or 1024))
        SendDuiMouseMove(panel.dui, pixelX, pixelY)
    end
end

-- CR3D.SendMouseDown(panelId, button)
-- Sends a mouse-button-down event.  button defaults to "left".
function CR3D.SendMouseDown(panelId, button)
    local key   = tostring(panelId)
    local panel = CR3D.PANELS[key]
    if panel and panel.dui then
        SendDuiMouseDown(panel.dui, button or "left")
    end
end

-- CR3D.SendMouseUp(panelId, button)
-- Sends a mouse-button-up event.  button defaults to "left".
function CR3D.SendMouseUp(panelId, button)
    local key   = tostring(panelId)
    local panel = CR3D.PANELS[key]
    if panel and panel.dui then
        SendDuiMouseUp(panel.dui, button or "left")
    end
end


-- ============================================================
-- SECTION 5 - Raycast helper
-- ============================================================

-- CR3D.raycastPanel(panel, rayOrigin, rayDir)
--   -> false                           (ray misses the panel)
--   -> true, hitPos, hitNormal, u, v   (ray hits; u,v are 0-1 UVs)
--
-- Performs a ray-plane intersection test against a panel's surface,
-- then checks whether the hit point falls within the panel bounds.
-- Returns UV coordinates suitable for SendMouseMove if it hits.
function CR3D.raycastPanel(panel, rayOrigin, rayDir)
    local panelPos  = panel.pos
    local normDir   = CR3D.vecNorm(panel.normal)

    -- Ray-plane intersection: t = dot(planePos - rayOrigin, normal) / dot(rayDir, normal)
    local denom = CR3D.vecDot(normDir, rayDir)

    -- Ray is nearly parallel to the panel surface -> no hit
    if math.abs(denom) < 1e-6 then
        return false
    end

    local t = CR3D.vecDot(panelPos - rayOrigin, normDir) / denom

    -- Hit is behind the ray origin -> no hit
    if t < 0 then
        return false
    end

    -- World-space hit position
    local hitPos = rayOrigin + rayDir * t

    -- Vector from panel centre to hit point
    local hitOffset = hitPos - panelPos

    -- Build a fresh basis for this panel (without z-nudge: zOffset=0)
    local basis = CR3D.makePanelBasis(
        panelPos, normDir,
        panel.width, panel.height,
        0, false, false, "none",
        panel.up
    )

    -- Project hit offset onto right and up axes
    local localU = CR3D.vecDot(hitOffset, basis.right)
    local localV = CR3D.vecDot(hitOffset, basis.up)

    -- Check that the hit is within the panel rectangle
    if math.abs(localU) > basis.halfW or math.abs(localV) > basis.halfH then
        return false
    end

    -- Convert to normalised UV (0.0 = left/top, 1.0 = right/bottom)
    local u = 0.5 - (localU / panel.width)
    local v = 0.5 + (localV / panel.height)

    return true, hitPos, normDir, u, v
end


-- ============================================================
-- SECTION 6 - Per-frame render thread
-- Iterates all registered panels every frame, resolves entity-
-- attachment positions, checks render distance, and calls
-- DrawSpritePoly twice per panel (two triangles = one quad).
-- ============================================================
CreateThread(function()
    while true do
        local playerPed   = PlayerPedId()
        local playerPos   = GetEntityCoords(playerPed)

        -- Honour Config.RenderDistance if the global Config table is
        -- present, otherwise fall back to CR3D.CONFIG.renderDistance.
        local renderDist
        if Config and Config.RenderDistance then
            renderDist = Config.RenderDistance
        else
            renderDist = CR3D.CONFIG.renderDistance
        end
        local renderDistSq = renderDist ^ 2  -- work in squared distance

        for panelKey, panel in pairs(CR3D.PANELS) do
            if panel.enabled and panel.dui then
                local attachment = CR3D.ATTACHMENTS[panelKey]

                -- Resolve current world position / normal / up.
                -- These may be overridden by entity attachment logic below.
                local panelPos    = panel.pos
                local panelNormal = panel.normal
                local panelUp     = panel.up

                -- -- Entity attachment ----------------------------------
                if attachment then
                    if DoesEntityExist(attachment.entity) then
                        local entityPos = GetEntityCoords(attachment.entity)

                        -- Skip if entity is beyond render distance + 5m buffer
                        if CR3D.vecDistSq(playerPos, entityPos) <= (renderDist + 5.0) ^ 2 then
                            -- Get the entity's world-space matrix columns
                            local matRight, matForward, matUp, matPos =
                                GetEntityMatrix(attachment.entity)

                            -- Determine panel world position
                            if attachment.boneIndex and attachment.boneIndex ~= -1 then
                                local bonePos = GetWorldPositionOfEntityBone(
                                    attachment.entity, attachment.boneIndex
                                )
                                panelPos = bonePos
                                         + matRight   * attachment.offset.x
                                         + matForward * attachment.offset.y
                                         + matUp      * attachment.offset.z
                            else
                                panelPos = matPos
                                         + matRight   * attachment.offset.x
                                         + matForward * attachment.offset.y
                                         + matUp      * attachment.offset.z
                            end

                            -- Rotate the panel's local normal into world space
                            if attachment.rotateNormal then
                                panelNormal = matRight   * attachment.localNormal.x
                                           + matForward * attachment.localNormal.y
                                           + matUp      * attachment.localNormal.z

                                if attachment.localUp then
                                    panelUp = matRight   * attachment.localUp.x
                                            + matForward * attachment.localUp.y
                                            + matUp      * attachment.localUp.z
                                end
                            end

                            -- Write computed world-space values back to the panel
                            panel.pos    = panelPos
                            panel.normal = panelNormal
                            panel.up     = panelUp
                        else
                            goto continueNextPanel
                        end
                    else
                        -- Attached entity no longer exists -> destroy the panel
                        CR3D.DestroyPanel(panelKey)
                        goto continueNextPanel
                    end

                -- -- Static panel (no attachment) ----------------------
                else
                    -- Distance cull: skip panels that are too far away
                    if CR3D.vecDistSq(playerPos, panel.pos) > renderDistSq then
                        goto continueNextPanel
                    end
                end

                -- -- Render panel (both attached and static) -----------
                if CR3D.vecDistSq(playerPos, panel.pos) <= renderDistSq then

                    -- Build the four corner vertices of the panel quad
                    local basis = CR3D.makePanelBasis(
                        panelPos, panelNormal,
                        panel.width, panel.height,
                        panel.zOffset,
                        false, false,
                        panel.depthCompensation,
                        panelUp
                    )

                    -- Corner A: top-right
                    local cornerTopRight = CR3D.vecAdd(
                        basis.center,
                        CR3D.vecAdd(
                            CR3D.vecMul(basis.right,  basis.halfW),
                            CR3D.vecMul(basis.up,     basis.halfH)
                        )
                    )

                    -- Corner B: top-left
                    local cornerTopLeft = CR3D.vecAdd(
                        basis.center,
                        CR3D.vecAdd(
                            CR3D.vecMul(basis.right, -basis.halfW),
                            CR3D.vecMul(basis.up,     basis.halfH)
                        )
                    )

                    -- Corner C: bottom-left
                    local cornerBottomLeft = CR3D.vecAdd(
                        basis.center,
                        CR3D.vecAdd(
                            CR3D.vecMul(basis.right, -basis.halfW),
                            CR3D.vecMul(basis.up,    -basis.halfH)
                        )
                    )

                    -- Corner D: bottom-right
                    local cornerBottomRight = CR3D.vecAdd(
                        basis.center,
                        CR3D.vecAdd(
                            CR3D.vecMul(basis.right,  basis.halfW),
                            CR3D.vecMul(basis.up,    -basis.halfH)
                        )
                    )

                    -- Triangle 1: A (TopRight), B (TopLeft), C (BottomLeft)
                    DrawSpritePoly(
                        cornerTopRight.x,    cornerTopRight.y,    cornerTopRight.z,
                        cornerTopLeft.x,     cornerTopLeft.y,     cornerTopLeft.z,
                        cornerBottomLeft.x,  cornerBottomLeft.y,  cornerBottomLeft.z,
                        255, 255, 255, panel.alpha,
                        panel.txdName, panel.texName,
                        0.0,  1.0, 1.0,
                        1.0,  1.0, 1.0,
                        1.0,  0.0, 1.0
                    )

                    -- Triangle 2: A (TopRight), C (BottomLeft), D (BottomRight)
                    DrawSpritePoly(
                        cornerTopRight.x,    cornerTopRight.y,    cornerTopRight.z,
                        cornerBottomLeft.x,  cornerBottomLeft.y,  cornerBottomLeft.z,
                        cornerBottomRight.x, cornerBottomRight.y, cornerBottomRight.z,
                        255, 255, 255, panel.alpha,
                        panel.txdName, panel.texName,
                        0.0,  1.0, 1.0,
                        1.0,  0.0, 1.0,
                        0.0,  0.0, 1.0
                    )
                end
            end

            ::continueNextPanel::
        end

        Wait(0)  -- yield every frame while panels may be visible
    end
end)