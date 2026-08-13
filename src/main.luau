local NEPHREN_LIBRARY_PATH = "Nephren.luau"
local NEPHREN_LIBRARY_URLS = {
    "https://raw.githubusercontent.com/jasonm066/nephren/main/src/ui/Nephren.luau",
    "https://raw.githubusercontent.com/jasonm066/nephren/main/src/Nephren.luau",
}

local function fetchNephrenLibrary()
    assert(type(loadstring) == "function", "executor loadstring API is unavailable")
    assert(type(writefile) == "function", "executor writefile API is unavailable")

    local failures = {}
    local cacheBuster = tostring(os.time()) .. "-" .. tostring(math.floor(os.clock() * 1000000))

    for _, url in ipairs(NEPHREN_LIBRARY_URLS) do
        local downloaded, sourceOrFailure = pcall(function()
            return game:HttpGet(url .. "?cacheBust=" .. cacheBuster)
        end)

        if downloaded and type(sourceOrFailure) == "string" and sourceOrFailure ~= "" then
            local chunk, compileFailure = loadstring(sourceOrFailure)

            if chunk then
                local saved, saveResult = pcall(writefile, NEPHREN_LIBRARY_PATH, sourceOrFailure)
                assert(
                    saved and saveResult ~= false,
                    "failed to save Nephren.luau: " .. tostring(saveResult)
                )
                return chunk
            end

            table.insert(failures, url .. ": " .. tostring(compileFailure))
        else
            table.insert(failures, url .. ": " .. tostring(sourceOrFailure))
        end
    end

    error("failed to download Nephren.luau: " .. table.concat(failures, "; "), 0)
end

local Nephren = fetchNephrenLibrary()()

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local player = Players.LocalPlayer
local globals = getgenv()
local previousMain = globals.__NephrenMain
local DEFAULT_TARGET_RPM = 1200
local DEFAULT_TARGET_DELAY = 60 / DEFAULT_TARGET_RPM
local DEFAULT_FIRE_DELAY = 0.08
local MIN_AIM_SMOOTHNESS = 0.1
local DEFAULT_AIM_SMOOTHNESS = 1
local MAX_AIM_SMOOTHNESS = 1
local AIM_LOCKED_RESPONSE = 0.12
local AIM_LOCKED_MAX_STEP = 10
local ESP_BOX_COLOR = Color3.fromRGB(255, 255, 255)
local ESP_OUTLINE_COLOR = Color3.fromRGB(0, 0, 0)
local ESP_NEAR_PLANE = 0.05
local ESP_CORNER_SCALE = 0.25
local ESP_FILL_DARKEN_FACTOR = 0.2
local ESP_FILL_SEGMENT_COUNT = 12
local ESP_TEXT_SIZE = 13
local ESP_TEXT_OFFSET = 2
local ESP_TEXT_WIDTH_FACTOR = 0.6
local DEFAULT_ESP_FILL_TRANSPARENCY = 75
local DEFAULT_ESP_RENDER_DISTANCE = 2000
local MIN_ESP_RENDER_DISTANCE = 100
local MAX_ESP_RENDER_DISTANCE = 5000
local ESP_BOX_STYLES = {
    "Box",
    "Corner",
    "3D",
}
local ESP_BOUNDING_CORNERS = {
    Vector3.new(-1, -1, -1),
    Vector3.new(-1, -1, 1),
    Vector3.new(-1, 1, -1),
    Vector3.new(-1, 1, 1),
    Vector3.new(1, -1, -1),
    Vector3.new(1, -1, 1),
    Vector3.new(1, 1, -1),
    Vector3.new(1, 1, 1),
}
local ESP_3D_EDGES = {
    { 1, 2 },
    { 1, 3 },
    { 1, 5 },
    { 2, 4 },
    { 2, 6 },
    { 3, 4 },
    { 3, 7 },
    { 4, 8 },
    { 5, 6 },
    { 5, 7 },
    { 6, 8 },
    { 7, 8 },
}
local INFINITE_GRENADES_RENDER_NAME = "__InfiniteGrenadesPreserveView"
local AMMO_WEAPON_NAMES = {
    M1Garand = true,
    Pistol = true,
    Sniper = true,
    Thompson = true,
    ["Machine Gun"] = true,
}
local AMMO_CLOSURE_UPVALUES = {
    Activate = 1,
}
local SPREAD_BY_WEAPON = {
    M1Garand = 0.006,
    Pistol = 0.01,
    Thompson = 0.013,
    ["Machine Gun"] = 0.013,
}
local HIDDEN_GAME_UI = {
    BanHacker = "Always",
    DisableGamepass = "Always",
    WeaponFrame = "DuringGameplay",
}
local PRIMARY_WEAPON_NAMES = {
    M1Garand = true,
    Thompson = true,
    Sniper = true,
    Mortar = true,
    ["Machine Gun"] = true,
}
local selectedFireRate = DEFAULT_TARGET_RPM

if previousMain then
    if type(previousMain.cleanup) == "function" then
        pcall(previousMain.cleanup)
    end

    if previousMain.library then
        previousMain.library:Unload()
    end

    for _, connection in ipairs(previousMain.connections or {}) do
        connection:Disconnect()
    end
end

globals.__NephrenMain = nil

local mainConnections = {}
local mainSession = {}
local aimConnection
local aimAssistMasterEnabled = false
local aimAssistActivationMode = "On Bind Press"
local aimAssistBindHeld = false
local aimTeamCheckEnabled = false
local aimVisibilityCheckEnabled = false
local aimSmoothness = DEFAULT_AIM_SMOOTHNESS
local aimMoveResidualX = 0
local aimMoveResidualY = 0
local aimRaycastParameters = RaycastParams.new()
local aimAssistToggle
local espEnabled = false
local espTeamCheckEnabled = false
local espBoxStyle = "Box"
local espBoxColor = ESP_BOX_COLOR
local espFillEnabled = false
local espFillTransparency = DEFAULT_ESP_FILL_TRANSPARENCY
local espNamesEnabled = false
local espDistanceEnabled = false
local espRenderDistance = DEFAULT_ESP_RENDER_DISTANCE
local espRenderDistanceSquared = espRenderDistance * espRenderDistance
local espRecords = {}
local gameWindowFocused = type(isrbxactive) ~= "function" or isrbxactive()
local window

aimRaycastParameters.FilterType = Enum.RaycastFilterType.Exclude
aimRaycastParameters.IgnoreWater = true

local function getMachineGun()
    local character = player.Character
    local tool = (character and character:FindFirstChild("Machine Gun"))
        or player.Backpack:FindFirstChild("Machine Gun")

    assert(tool, "Machine gun not found")

    local weaponScript = tool:FindFirstChild("ThompsonLocalScript")
    assert(weaponScript, "Machine gun script not found")

    return tool, weaponScript
end

local function getPlayerWeapon(closure)
    local environment = getfenv(closure)
    local weaponScript = environment and rawget(environment, "script")

    if typeof(weaponScript) ~= "Instance" or not weaponScript:IsA("LocalScript") then
        return nil
    end

    local tool = weaponScript:FindFirstAncestorWhichIsA("Tool")
    local character = player.Character
    local backpack = player:FindFirstChildOfClass("Backpack")

    if not tool
        or not (
            (character and tool:IsDescendantOf(character))
            or (backpack and tool:IsDescendantOf(backpack))
        )
    then
        return nil
    end

    return tool, weaponScript
end

local function findFunctions(name)
    local matches = filtergc("function", { Name = name }, false)

    if type(matches) == "function" then
        return { matches }
    end

    return matches or {}
end

local function clearInstantReloadOverride()
    local instantReload = globals.__MachineGunInstantReload

    if instantReload
        and instantReload.script
        and instantReload.replacement
    then
        local environment = getsenv(instantReload.script)

        if environment and rawget(environment, "wait") == instantReload.replacement then
            environment.wait = instantReload.original
        end
    end

    globals.__MachineGunInstantReload = nil
end

local function disableInfiniteAmmo()
    local state = globals.__NephrenInfiniteAmmo

    if state then
        state.enabled = false

        if state.connection then
            state.connection:Disconnect()
        end

        for closure, record in pairs(state.records or {}) do
            pcall(debug.setupvalue, closure, record.upvalueIndex, record.originalAmmo)
        end

        globals.__NephrenInfiniteAmmo = nil
        print("Infinite ammo disabled")
    end

    local legacyState = globals.__MachineGunInfiniteAmmo

    if legacyState
        and type(legacyState.activate) == "function"
        and type(legacyState.ammoUpvalue) == "number"
        and type(legacyState.originalAmmo) == "number"
    then
        pcall(
            debug.setupvalue,
            legacyState.activate,
            legacyState.ammoUpvalue,
            legacyState.originalAmmo
        )
    end

    globals.__MachineGunInfiniteAmmo = nil
end

local function clearLegacyInfiniteMortars()
    local state = globals.__NephrenInfiniteMortars

    if not state then
        return
    end

    state.enabled = false

    if state.connection then
        state.connection:Disconnect()
    end

    for closure, record in pairs(state.records or {}) do
        pcall(debug.setupvalue, closure, record.upvalueIndex, 1)
    end

    globals.__NephrenInfiniteMortars = nil
end

local function disableAimAssist()
    local connection = aimConnection
    aimMoveResidualX = 0
    aimMoveResidualY = 0

    if not connection then
        return
    end

    aimConnection = nil
    connection:Disconnect()

    for index = #mainConnections, 1, -1 do
        if mainConnections[index] == connection then
            table.remove(mainConnections, index)
            break
        end
    end

    print("Aim assist disabled")
end

local function disableFireRate()
    local state = globals.__MachineGunFireRate

    if not state then
        return
    end

    if type(state.proto) == "function"
        and type(state.constantIndex) == "number"
        and type(state.originalDelay) == "number"
    then
        debug.setconstant(state.proto, state.constantIndex, state.originalDelay)
    end

    globals.__MachineGunFireRate = nil
    print("Machine gun fire rate restored")
end

local function disableNoSpread()
    local state = globals.__NephrenNoSpread

    if state then
        state.enabled = false

        if state.connection then
            state.connection:Disconnect()
        end

        for activate, record in pairs(state.records or {}) do
            pcall(debug.setconstant, activate, record.constantIndex, record.originalSpread)
        end

        globals.__NephrenNoSpread = nil
        print("Weapon spread restored")
    end

    local legacyState = globals.__MachineGunNoSpread

    if legacyState
        and type(legacyState.activate) == "function"
        and type(legacyState.constantIndex) == "number"
        and type(legacyState.originalSpread) == "number"
    then
        pcall(
            debug.setconstant,
            legacyState.activate,
            legacyState.constantIndex,
            legacyState.originalSpread
        )
    end

    globals.__MachineGunNoSpread = nil
end

local function disableInfiniteGrenades()
    local state = globals.__InfiniteGrenades

    if state then
        state.enabled = false
        state.viewToken = (state.viewToken or 0) + 1

        for _, connection in ipairs(state.connections or {}) do
            connection:Disconnect()
        end

        for _, name in ipairs({
            "characterConnection",
            "backpackConnection",
            "backpackRemovedConnection",
            "backpackAddedConnection",
        }) do
            local connection = state[name]

            if connection then
                connection:Disconnect()
            end
        end
    end

    pcall(
        RunService.UnbindFromRenderStep,
        RunService,
        INFINITE_GRENADES_RENDER_NAME
    )
    globals.__InfiniteGrenades = nil

    if state then
        print("Infinite grenades disabled")
    end
end

local function updateFireRate(rpm)
    local state = globals.__MachineGunFireRate

    if not state then
        return
    end

    local delay = 60 / rpm
    debug.setconstant(state.proto, state.constantIndex, delay)
    state.rpm = rpm
    state.delay = delay

    print("Machine gun set to " .. rpm .. " RPM")
end

local function playersAreTeammates(otherPlayer)
    local localTeam = player.Team

    return not player.Neutral
        and not otherPlayer.Neutral
        and localTeam ~= nil
        and otherPlayer.Team == localTeam
end

local function canTargetPlayer(otherPlayer)
    return otherPlayer ~= player
        and (not aimTeamCheckEnabled or not playersAreTeammates(otherPlayer))
end

local function targetIsVisible(camera, targetCharacter, targetPart)
    if not aimVisibilityCheckEnabled then
        return true
    end

    local origin = camera.CFrame.Position
    local direction = targetPart.Position - origin

    if direction.Magnitude <= 0.001 then
        return true
    end

    local localCharacter = player.Character

    if localCharacter then
        aimRaycastParameters.FilterDescendantsInstances = {
            localCharacter,
            targetCharacter,
        }
    else
        aimRaycastParameters.FilterDescendantsInstances = { targetCharacter }
    end

    return workspace:Raycast(origin, direction, aimRaycastParameters) == nil
end

local function getNearestPlayerHeadPosition(camera, aimOrigin)
    local nearestPosition
    local nearestDistanceSquared = math.huge

    for _, otherPlayer in ipairs(Players:GetPlayers()) do
        if canTargetPlayer(otherPlayer) then
            local otherCharacter = otherPlayer.Character
            local humanoid = otherCharacter
                and otherCharacter:FindFirstChildOfClass("Humanoid")
            local root = otherCharacter
                and otherCharacter:FindFirstChild("HumanoidRootPart")
            local head = otherCharacter and otherCharacter:FindFirstChild("Head")

            if humanoid and humanoid.Health > 0 and root and head then
                local viewportPosition, onScreen = camera:WorldToViewportPoint(head.Position)

                if onScreen and viewportPosition.Z > 0 then
                    local deltaX = viewportPosition.X - aimOrigin.X
                    local deltaY = viewportPosition.Y - aimOrigin.Y
                    local distanceSquared = deltaX * deltaX + deltaY * deltaY

                    if distanceSquared < nearestDistanceSquared
                        and targetIsVisible(camera, otherCharacter, head)
                    then
                        nearestDistanceSquared = distanceSquared
                        nearestPosition = Vector2.new(viewportPosition.X, viewportPosition.Y)
                    end
                end
            end
        end
    end

    return nearestPosition
end

local function getAimOrigin(camera)
    local mouseBehavior = UserInputService.MouseBehavior

    if mouseBehavior == Enum.MouseBehavior.LockCenter then
        return camera.ViewportSize * 0.5, true
    end

    local mouseLocked = mouseBehavior ~= Enum.MouseBehavior.Default
        or UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton2)

    return UserInputService:GetMouseLocation(), mouseLocked
end

local function moveMouseToward(targetPosition, aimOrigin, mouseLocked)
    local deltaX = targetPosition.X - aimOrigin.X
    local deltaY = targetPosition.Y - aimOrigin.Y
    local response = math.min(1, 1 / aimSmoothness)
    local maximumStep

    if mouseLocked then
        response = math.min(1, AIM_LOCKED_RESPONSE / aimSmoothness)
        maximumStep = AIM_LOCKED_MAX_STEP / aimSmoothness
    end

    deltaX = deltaX * response
    deltaY = deltaY * response

    if maximumStep then
        local distanceSquared = deltaX * deltaX + deltaY * deltaY
        local maximumStepSquared = maximumStep * maximumStep

        if distanceSquared > maximumStepSquared then
            local scale = maximumStep / math.sqrt(distanceSquared)
            deltaX = deltaX * scale
            deltaY = deltaY * scale
        end
    end

    deltaX = deltaX + aimMoveResidualX
    deltaY = deltaY + aimMoveResidualY

    local moveX = math.round(deltaX)
    local moveY = math.round(deltaY)
    aimMoveResidualX = deltaX - moveX
    aimMoveResidualY = deltaY - moveY

    if moveX ~= 0 or moveY ~= 0 then
        mousemoverel(moveX, moveY)
    end
end

local function enableAimAssist()
    disableAimAssist()
    assert(type(mousemoverel) == "function", "mousemoverel is unavailable")

    aimConnection = RunService.RenderStepped:Connect(function()
        if not gameWindowFocused or (window and window.Visible) then
            aimMoveResidualX = 0
            aimMoveResidualY = 0
            return
        end

        local camera = workspace.CurrentCamera

        if not camera then
            aimMoveResidualX = 0
            aimMoveResidualY = 0
            return
        end

        local aimOrigin, mouseLocked = getAimOrigin(camera)
        local targetPosition = getNearestPlayerHeadPosition(camera, aimOrigin)

        if not targetPosition then
            aimMoveResidualX = 0
            aimMoveResidualY = 0
            return
        end

        moveMouseToward(targetPosition, aimOrigin, mouseLocked)
    end)
    table.insert(mainConnections, aimConnection)
    print("Aim assist enabled")
end

local function refreshAimAssist()
    local shouldAim = aimAssistMasterEnabled
        and (
            aimAssistActivationMode == "Always On"
            or aimAssistBindHeld
        )

    if not shouldAim then
        disableAimAssist()
        return
    end

    if aimConnection then
        return
    end

    local succeeded, failure = pcall(enableAimAssist)

    if succeeded then
        return
    end

    disableAimAssist()
    aimAssistMasterEnabled = false

    if aimAssistToggle then
        aimAssistToggle:SetValue(false, true)
    end

    warn("Failed to enable aim assist: " .. tostring(failure))
end

local function removeEspDrawing(drawing)
    if not drawing then
        return
    end

    pcall(function()
        drawing.Visible = false
    end)
    pcall(function()
        drawing:Remove()
    end)
end

local function hideEspRecord(record)
    for drawing in pairs(record.visibleDrawings) do
        pcall(function()
            drawing.Visible = false
        end)
    end

    table.clear(record.visibleDrawings)
    table.clear(record.pendingVisibleDrawings)
end

local function destroyEspRecord(otherPlayer)
    local record = espRecords[otherPlayer]

    if not record then
        return
    end

    espRecords[otherPlayer] = nil
    for _, drawing in ipairs(record.drawings) do
        removeEspDrawing(drawing)
    end
end

local function newEspDrawing(record, kind, zIndex)
    local drawing = Drawing.new(kind)
    table.insert(record.drawings, drawing)
    drawing.Visible = false
    drawing.Transparency = 1
    drawing.ZIndex = zIndex

    return drawing
end

local function getEspGradientColor(index, segmentCount)
    local ratio = segmentCount > 1 and (index - 1) / (segmentCount - 1) or 0
    local scale = 1 - ratio * (1 - ESP_FILL_DARKEN_FACTOR)

    return Color3.new(
        espBoxColor.R * scale,
        espBoxColor.G * scale,
        espBoxColor.B * scale
    )
end

local function getEspFillOpacity()
    return math.clamp(1 - espFillTransparency / 100, 0, 1)
end

local function styleEspFillSegments(record)
    local segmentCount = record.fillActiveSegmentCount or ESP_FILL_SEGMENT_COUNT
    local fillOpacity = getEspFillOpacity()

    for index = 1, math.min(segmentCount, #record.fillSegments) do
        local segment = record.fillSegments[index]
        segment.Color = getEspGradientColor(index, segmentCount)
        segment.Transparency = fillOpacity
    end
end

local function styleEspText(text)
    if not text then
        return
    end

    text.Color = espBoxColor
    text.OutlineColor = ESP_OUTLINE_COLOR
    text.Transparency = 1
end

local function styleEspRecord(record)
    record.outline.Color = ESP_OUTLINE_COLOR
    record.outline.Transparency = 1
    record.box.Color = espBoxColor
    record.box.Transparency = 1

    for _, outline in ipairs(record.lineOutlines) do
        outline.Color = ESP_OUTLINE_COLOR
        outline.Transparency = 1
    end

    for _, line in ipairs(record.lines) do
        line.Color = espBoxColor
        line.Transparency = 1
    end

    styleEspFillSegments(record)
    styleEspText(record.nameText)
    styleEspText(record.distanceText)
end

local function ensureEspLinePairs(record, count)
    local created = false

    while #record.lines < count do
        local outline = newEspDrawing(record, "Line", 1)
        outline.Thickness = 3
        outline.Color = ESP_OUTLINE_COLOR
        outline.From = Vector2.new(0, 0)
        outline.To = Vector2.new(0, 0)
        table.insert(record.lineOutlines, outline)

        local line = newEspDrawing(record, "Line", 2)
        line.Thickness = 1
        line.Color = espBoxColor
        line.From = Vector2.new(0, 0)
        line.To = Vector2.new(0, 0)
        table.insert(record.lines, line)
        created = true
    end

    if created then
        styleEspRecord(record)
    end

    return created
end

local function ensureEspFillSegments(record)
    local created = false

    while #record.fillSegments < ESP_FILL_SEGMENT_COUNT do
        local segment = newEspDrawing(record, "Square", 0)
        segment.Filled = true
        segment.Color = espBoxColor
        segment.Position = Vector2.new(0, 0)
        segment.Size = Vector2.new(1, 1)
        table.insert(record.fillSegments, segment)
        created = true
    end

    if created then
        styleEspRecord(record)
    end

    return created
end

local function ensureEspText(record, field)
    local text = record[field]

    if text then
        return text
    end

    text = newEspDrawing(record, "Text", 3)
    text.Center = true
    text.Font = 2
    text.Outline = true
    text.OutlineColor = ESP_OUTLINE_COLOR
    text.Color = espBoxColor
    text.Size = ESP_TEXT_SIZE
    text.Text = ""
    text.Position = Vector2.new(0, 0)
    record[field] = text
    styleEspText(text)
    return text
end

local function createEspRecord(otherPlayer)
    if otherPlayer == player or espRecords[otherPlayer] then
        return espRecords[otherPlayer]
    end

    local record = {
        drawings = {},
        visibleDrawings = {},
        pendingVisibleDrawings = {},
        lineOutlines = {},
        lines = {},
        fillSegments = {},
    }
    local succeeded, failure = pcall(function()
        record.outline = newEspDrawing(record, "Square", 1)
        record.outline.Filled = false
        record.outline.Thickness = 3
        record.outline.Color = ESP_OUTLINE_COLOR
        record.outline.Position = Vector2.new(0, 0)
        record.outline.Size = Vector2.new(1, 1)

        record.box = newEspDrawing(record, "Square", 2)
        record.box.Filled = false
        record.box.Thickness = 1
        record.box.Color = espBoxColor
        record.box.Position = Vector2.new(0, 0)
        record.box.Size = Vector2.new(1, 1)

        styleEspRecord(record)
    end)

    if not succeeded then
        for _, drawing in ipairs(record.drawings) do
            removeEspDrawing(drawing)
        end

        warn("Failed to create ESP box: " .. tostring(failure))
        return nil
    end

    espRecords[otherPlayer] = record
    return record
end

local function projectCharacterBounds(camera, character, includeProjectedCorners)
    local succeeded, boundingCFrame, boundingSize = pcall(
        character.GetBoundingBox,
        character
    )

    if not succeeded
        or boundingSize.X <= 0
        or boundingSize.Y <= 0
        or boundingSize.Z <= 0
    then
        return nil
    end

    local halfSize = boundingSize * 0.5
    local minimumX = math.huge
    local minimumY = math.huge
    local maximumX = -math.huge
    local maximumY = -math.huge
    local projectedCorners = includeProjectedCorners and {} or nil

    for index, corner in ipairs(ESP_BOUNDING_CORNERS) do
        local worldPosition = boundingCFrame:PointToWorldSpace(Vector3.new(
            halfSize.X * corner.X,
            halfSize.Y * corner.Y,
            halfSize.Z * corner.Z
        ))
        local viewportPosition = camera:WorldToViewportPoint(worldPosition)

        if viewportPosition.Z <= ESP_NEAR_PLANE then
            return nil
        end

        if projectedCorners then
            projectedCorners[index] = Vector2.new(viewportPosition.X, viewportPosition.Y)
        end
        minimumX = math.min(minimumX, viewportPosition.X)
        minimumY = math.min(minimumY, viewportPosition.Y)
        maximumX = math.max(maximumX, viewportPosition.X)
        maximumY = math.max(maximumY, viewportPosition.Y)
    end

    local viewportSize = camera.ViewportSize

    if maximumX < 0
        or maximumY < 0
        or minimumX > viewportSize.X
        or minimumY > viewportSize.Y
    then
        return nil
    end

    minimumX = math.clamp(minimumX, 0, viewportSize.X)
    minimumY = math.clamp(minimumY, 0, viewportSize.Y)
    maximumX = math.clamp(maximumX, 0, viewportSize.X)
    maximumY = math.clamp(maximumY, 0, viewportSize.Y)

    local size = Vector2.new(maximumX - minimumX, maximumY - minimumY)

    if size.X < 2 or size.Y < 2 then
        return nil
    end

    return Vector2.new(minimumX, minimumY), size, projectedCorners
end

local function clipEspLineBoundary(direction, distance, startRatio, endRatio)
    if math.abs(direction) <= 0.000001 then
        return distance >= 0, startRatio, endRatio
    end

    local ratio = distance / direction

    if direction < 0 then
        if ratio > endRatio then
            return false, startRatio, endRatio
        end

        startRatio = math.max(startRatio, ratio)
    else
        if ratio < startRatio then
            return false, startRatio, endRatio
        end

        endRatio = math.min(endRatio, ratio)
    end

    return true, startRatio, endRatio
end

local function clipLineToViewport(fromPoint, toPoint, viewportSize)
    local deltaX = toPoint.X - fromPoint.X
    local deltaY = toPoint.Y - fromPoint.Y
    local startRatio = 0
    local endRatio = 1
    local accepted

    accepted, startRatio, endRatio = clipEspLineBoundary(
        -deltaX,
        fromPoint.X,
        startRatio,
        endRatio
    )

    if not accepted then
        return nil
    end

    accepted, startRatio, endRatio = clipEspLineBoundary(
        deltaX,
        viewportSize.X - fromPoint.X,
        startRatio,
        endRatio
    )

    if not accepted then
        return nil
    end

    accepted, startRatio, endRatio = clipEspLineBoundary(
        -deltaY,
        fromPoint.Y,
        startRatio,
        endRatio
    )

    if not accepted then
        return nil
    end

    accepted, startRatio, endRatio = clipEspLineBoundary(
        deltaY,
        viewportSize.Y - fromPoint.Y,
        startRatio,
        endRatio
    )

    if not accepted then
        return nil
    end

    if startRatio == 0 and endRatio == 1 then
        return fromPoint, toPoint
    end

    return Vector2.new(
        fromPoint.X + deltaX * startRatio,
        fromPoint.Y + deltaY * startRatio
    ), Vector2.new(
        fromPoint.X + deltaX * endRatio,
        fromPoint.Y + deltaY * endRatio
    )
end

local function showEspDrawing(record, drawing)
    record.pendingVisibleDrawings[drawing] = true

    if not record.visibleDrawings[drawing] then
        drawing.Visible = true
    end
end

local function finishEspRecord(record)
    for drawing in pairs(record.visibleDrawings) do
        if not record.pendingVisibleDrawings[drawing] then
            drawing.Visible = false
        end
    end

    local previouslyVisibleDrawings = record.visibleDrawings
    record.visibleDrawings = record.pendingVisibleDrawings
    record.pendingVisibleDrawings = previouslyVisibleDrawings
end

local function showEspLinePair(record, index, fromPoint, toPoint)
    local outline = record.lineOutlines[index]
    local line = record.lines[index]
    outline.From = fromPoint
    outline.To = toPoint
    showEspDrawing(record, outline)
    line.From = fromPoint
    line.To = toPoint
    showEspDrawing(record, line)
end

local function showEspFill(record, position, size)
    if not espFillEnabled or getEspFillOpacity() <= 0 then
        return
    end

    local fillWidth = size.X - 2
    local fillHeight = size.Y - 2

    if fillWidth <= 0 or fillHeight <= 0 then
        return
    end

    local activeSegmentCount = math.min(
        ESP_FILL_SEGMENT_COUNT,
        math.max(1, math.floor(fillHeight))
    )
    local segmentCountChanged = record.fillActiveSegmentCount ~= activeSegmentCount
    record.fillActiveSegmentCount = activeSegmentCount
    local created = ensureEspFillSegments(record)

    if segmentCountChanged and not created then
        styleEspFillSegments(record)
    end

    local fillX = position.X + 1
    local fillY = position.Y + 1

    for index = 1, activeSegmentCount do
        local segment = record.fillSegments[index]
        local top = fillY + fillHeight * ((index - 1) / activeSegmentCount)
        local bottom = fillY + fillHeight * (index / activeSegmentCount)

        segment.Position = Vector2.new(fillX, top)
        segment.Size = Vector2.new(fillWidth, bottom - top)
        showEspDrawing(record, segment)
    end
end

local function showEspBox(record, position, size)
    record.outline.Position = position
    record.outline.Size = size
    showEspDrawing(record, record.outline)
    record.box.Position = position
    record.box.Size = size
    showEspDrawing(record, record.box)
end

local function showEspCorners(record, position, size)
    ensureEspLinePairs(record, 8)

    local left = position.X
    local top = position.Y
    local right = left + size.X
    local bottom = top + size.Y
    local horizontalLength = math.min(size.X * 0.5, math.max(1, size.X * ESP_CORNER_SCALE))
    local verticalLength = math.min(size.Y * 0.5, math.max(1, size.Y * ESP_CORNER_SCALE))

    showEspLinePair(
        record,
        1,
        Vector2.new(left, top),
        Vector2.new(left + horizontalLength, top)
    )
    showEspLinePair(
        record,
        2,
        Vector2.new(left, top),
        Vector2.new(left, top + verticalLength)
    )
    showEspLinePair(
        record,
        3,
        Vector2.new(right, top),
        Vector2.new(right - horizontalLength, top)
    )
    showEspLinePair(
        record,
        4,
        Vector2.new(right, top),
        Vector2.new(right, top + verticalLength)
    )
    showEspLinePair(
        record,
        5,
        Vector2.new(left, bottom),
        Vector2.new(left + horizontalLength, bottom)
    )
    showEspLinePair(
        record,
        6,
        Vector2.new(left, bottom),
        Vector2.new(left, bottom - verticalLength)
    )
    showEspLinePair(
        record,
        7,
        Vector2.new(right, bottom),
        Vector2.new(right - horizontalLength, bottom)
    )
    showEspLinePair(
        record,
        8,
        Vector2.new(right, bottom),
        Vector2.new(right, bottom - verticalLength)
    )
end

local function showEsp3DBox(record, projectedCorners, viewportSize)
    ensureEspLinePairs(record, #ESP_3D_EDGES)

    for index, edge in ipairs(ESP_3D_EDGES) do
        local fromPoint, toPoint = clipLineToViewport(
            projectedCorners[edge[1]],
            projectedCorners[edge[2]],
            viewportSize
        )

        if fromPoint then
            showEspLinePair(record, index, fromPoint, toPoint)
        end
    end
end

local function measureEspTextHalfWidth(text, value)
    local succeeded, width = pcall(function()
        return text.TextBounds.X
    end)

    if not succeeded or type(width) ~= "number" or width <= 0 then
        width = string.len(value) * ESP_TEXT_SIZE * ESP_TEXT_WIDTH_FACTOR
    end

    return width * 0.5
end

local function setEspTextValue(record, field, valueField, widthField, value)
    local text = ensureEspText(record, field)

    if record[valueField] ~= value then
        record[valueField] = value
        text.Text = value
        record[widthField] = measureEspTextHalfWidth(text, value)
    end

    return text, record[widthField]
end

local function showEspText(record, text, halfWidth, centerX, y, viewportWidth)
    local safeHalfWidth = math.min(halfWidth, viewportWidth * 0.5)
    text.Position = Vector2.new(
        math.clamp(centerX, safeHalfWidth, viewportWidth - safeHalfWidth),
        y
    )
    showEspDrawing(record, text)
end

local function showEspPlayerInfo(record, otherPlayer, distance, position, size, viewportSize)
    if not espNamesEnabled and not espDistanceEnabled then
        return
    end

    local centerX = math.clamp(position.X + size.X * 0.5, 0, viewportSize.X)

    if espNamesEnabled then
        local nameText, nameHalfWidth = setEspTextValue(
            record,
            "nameText",
            "nameTextValue",
            "nameTextHalfWidth",
            otherPlayer.Name
        )
        showEspText(
            record,
            nameText,
            nameHalfWidth,
            centerX,
            math.clamp(
                position.Y - ESP_TEXT_SIZE - ESP_TEXT_OFFSET,
                0,
                viewportSize.Y - ESP_TEXT_SIZE
            ),
            viewportSize.X
        )
    end

    if espDistanceEnabled then
        local roundedDistance = math.round(distance)
        local distanceText = ensureEspText(record, "distanceText")

        if record.distanceTextValue ~= roundedDistance then
            record.distanceTextValue = roundedDistance
            local distanceValue = tostring(roundedDistance) .. " studs"
            distanceText.Text = distanceValue
            record.distanceTextHalfWidth = measureEspTextHalfWidth(
                distanceText,
                distanceValue
            )
        end

        showEspText(
            record,
            distanceText,
            record.distanceTextHalfWidth,
            centerX,
            math.clamp(
                position.Y + size.Y + ESP_TEXT_OFFSET,
                0,
                viewportSize.Y - ESP_TEXT_SIZE
            ),
            viewportSize.X
        )
    end
end

local function canShowEspPlayer(otherPlayer)
    return otherPlayer ~= player
        and (not espTeamCheckEnabled or not playersAreTeammates(otherPlayer))
end

local function updateEspRecord(camera, distanceOrigin, otherPlayer, record)
    if not canShowEspPlayer(otherPlayer) then
        hideEspRecord(record)
        return
    end

    local character = otherPlayer.Character
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    local root = character and character:FindFirstChild("HumanoidRootPart")

    if not humanoid or humanoid.Health <= 0 or not root then
        hideEspRecord(record)
        return
    end

    local distanceDelta = root.Position - distanceOrigin
    local distanceSquared = distanceDelta.X * distanceDelta.X
        + distanceDelta.Y * distanceDelta.Y
        + distanceDelta.Z * distanceDelta.Z

    if distanceSquared > espRenderDistanceSquared then
        hideEspRecord(record)
        return
    end

    local distance = espDistanceEnabled and math.sqrt(distanceSquared) or nil

    local position, size, projectedCorners = projectCharacterBounds(
        camera,
        character,
        espBoxStyle == "3D"
    )

    if not position then
        hideEspRecord(record)
        return
    end

    table.clear(record.pendingVisibleDrawings)
    local succeeded = pcall(function()
        showEspFill(record, position, size)

        if espBoxStyle == "Corner" then
            showEspCorners(record, position, size)
        elseif espBoxStyle == "3D" then
            showEsp3DBox(record, projectedCorners, camera.ViewportSize)
        else
            showEspBox(record, position, size)
        end

        showEspPlayerInfo(
            record,
            otherPlayer,
            distance,
            position,
            size,
            camera.ViewportSize
        )

        finishEspRecord(record)
    end)

    if not succeeded then
        destroyEspRecord(otherPlayer)
    end
end

local function hideAllEspRecords()
    for _, record in pairs(espRecords) do
        hideEspRecord(record)
    end
end

local function destroyAllEspRecords()
    espEnabled = false

    for _, record in pairs(espRecords) do
        for _, drawing in ipairs(record.drawings) do
            removeEspDrawing(drawing)
        end
    end

    table.clear(espRecords)
end

local function refreshEspStyles()
    local failedPlayers = {}

    for otherPlayer, record in pairs(espRecords) do
        local succeeded = pcall(styleEspRecord, record)

        if not succeeded then
            table.insert(failedPlayers, otherPlayer)
        end
    end

    for _, otherPlayer in ipairs(failedPlayers) do
        destroyEspRecord(otherPlayer)
    end
end

local function setEspEnabled(enabled)
    espEnabled = enabled

    if not enabled then
        hideAllEspRecords()
        return
    end

    for _, otherPlayer in ipairs(Players:GetPlayers()) do
        createEspRecord(otherPlayer)
    end
end

table.insert(mainConnections, Players.PlayerAdded:Connect(function(otherPlayer)
    if espEnabled then
        createEspRecord(otherPlayer)
    end
end))
table.insert(mainConnections, Players.PlayerRemoving:Connect(function(otherPlayer)
    destroyEspRecord(otherPlayer)
end))
table.insert(mainConnections, RunService.RenderStepped:Connect(function()
    if not espEnabled then
        return
    end

    local camera = workspace.CurrentCamera

    if not gameWindowFocused or not camera then
        hideAllEspRecords()
        return
    end

    local localCharacter = player.Character
    local localHumanoid = localCharacter
        and localCharacter:FindFirstChildOfClass("Humanoid")
    local localRoot = localHumanoid
        and localHumanoid.Health > 0
        and localCharacter:FindFirstChild("HumanoidRootPart")
    local distanceOrigin = localRoot and localRoot.Position or camera.CFrame.Position

    for otherPlayer, record in pairs(espRecords) do
        updateEspRecord(camera, distanceOrigin, otherPlayer, record)
    end
end))

table.insert(mainConnections, UserInputService.WindowFocused:Connect(function()
    gameWindowFocused = true
end))
table.insert(mainConnections, UserInputService.WindowFocusReleased:Connect(function()
    gameWindowFocused = false
end))

local function enableInfiniteAmmo()
    disableInfiniteAmmo()

    local state = {
        enabled = true,
        records = {},
        elapsed = 0,
    }

    globals.__NephrenInfiniteAmmo = state

    local function toolBelongsToPlayer(tool)
        local character = player.Character
        local backpack = player:FindFirstChildOfClass("Backpack")

        return tool
            and (
                (character and tool:IsDescendantOf(character))
                or (backpack and tool:IsDescendantOf(backpack))
            )
    end

    local function scanAmmo()
        if not state.enabled then
            return
        end

        for functionName, upvalueIndex in pairs(AMMO_CLOSURE_UPVALUES) do
            for _, closure in ipairs(findFunctions(functionName)) do
                local tool, weaponScript = getPlayerWeapon(closure)

                if tool
                    and AMMO_WEAPON_NAMES[tool.Name]
                then
                    local ammo = debug.getupvalue(closure, upvalueIndex)

                    if type(ammo) == "number" then
                        local record = state.records[closure]

                        if not record then
                            record = {
                                tool = tool,
                                script = weaponScript,
                                upvalueIndex = upvalueIndex,
                                originalAmmo = ammo,
                            }
                            state.records[closure] = record
                        end

                        if ammo ~= math.huge then
                            debug.setupvalue(closure, upvalueIndex, math.huge)
                        end
                    end
                end
            end
        end

        for closure, record in pairs(state.records) do
            if not toolBelongsToPlayer(record.tool) then
                pcall(
                    debug.setupvalue,
                    closure,
                    record.upvalueIndex,
                    record.originalAmmo
                )
                state.records[closure] = nil
            end
        end
    end

    scanAmmo()
    state.connection = RunService.Heartbeat:Connect(function(deltaTime)
        state.elapsed = state.elapsed + deltaTime

        if state.elapsed >= 0.25 then
            state.elapsed = 0
            local succeeded, failure = pcall(scanAmmo)

            if not succeeded then
                warn("Failed to refresh infinite ammo: " .. tostring(failure))
            end
        end
    end)

    print("Infinite ammo enabled")
end

local function enableFireRate(rpm)
    getMachineGun()

    local targetDelay = 60 / rpm
    local found = 0
    local matchedProto
    local matchedIndex
    local originalDelay

    for _, connection in ipairs(getconnections(player:GetMouse().Button1Down)) do
        local callback = connection.Function

        if connection.LuaConnection and callback then
            local info = debug.getinfo(callback)
            local source = info.short_src or info.source or ""

            if string.find(source, "ThompsonLocalScript", 1, true) then
                for _, proto in ipairs(debug.getprotos(callback)) do
                    for index, value in pairs(debug.getconstants(proto)) do
                        if value == DEFAULT_FIRE_DELAY
                            or value == targetDelay
                            or value == DEFAULT_TARGET_DELAY
                        then
                            found = found + 1
                            matchedProto = proto
                            matchedIndex = index
                            originalDelay = DEFAULT_FIRE_DELAY
                        end
                    end
                end
            end
        end
    end

    assert(
        found == 1,
        "Expected one automatic-fire delay, found " .. tostring(found)
    )

    debug.setconstant(matchedProto, matchedIndex, targetDelay)

    globals.__MachineGunFireRate = {
        proto = matchedProto,
        constantIndex = matchedIndex,
        originalDelay = originalDelay,
        rpm = rpm,
        delay = targetDelay,
    }

    print("Machine gun set to " .. rpm .. " RPM")
end

local function enableNoSpread()
    disableNoSpread()

    local state = {
        enabled = true,
        records = {},
        elapsed = 0,
    }

    globals.__NephrenNoSpread = state

    local function scanSpread()
        if not state.enabled then
            return
        end

        for _, activate in ipairs(findFunctions("Activate")) do
            local tool = getPlayerWeapon(activate)
            local expectedSpread = tool and SPREAD_BY_WEAPON[tool.Name]

            if expectedSpread then
                local record = state.records[activate]

                if not record then
                    local constantIndex

                    for index, value in pairs(debug.getconstants(activate)) do
                        if value == expectedSpread then
                            assert(not constantIndex, "Multiple weapon spread constants found")
                            constantIndex = index
                        end
                    end

                    if constantIndex then
                        record = {
                            tool = tool,
                            constantIndex = constantIndex,
                            originalSpread = expectedSpread,
                        }
                        state.records[activate] = record
                    end
                end

                if record
                    and debug.getconstants(activate)[record.constantIndex] ~= 0
                then
                    debug.setconstant(activate, record.constantIndex, 0)
                end
            end
        end

        for activate, record in pairs(state.records) do
            local character = player.Character
            local backpack = player:FindFirstChildOfClass("Backpack")
            local owned = (character and record.tool:IsDescendantOf(character))
                or (backpack and record.tool:IsDescendantOf(backpack))

            if not owned then
                pcall(
                    debug.setconstant,
                    activate,
                    record.constantIndex,
                    record.originalSpread
                )
                state.records[activate] = nil
            end
        end
    end

    scanSpread()
    state.connection = RunService.Heartbeat:Connect(function(deltaTime)
        state.elapsed = state.elapsed + deltaTime

        if state.elapsed >= 0.25 then
            state.elapsed = 0
            local succeeded, failure = pcall(scanSpread)

            if not succeeded then
                warn("Failed to refresh no spread: " .. tostring(failure))
            end
        end
    end)

    print("Weapon spread disabled")
end

local function enableInfiniteGrenades()
    local ReplicatedStorage = game:GetService("ReplicatedStorage")
    local event = ReplicatedStorage:WaitForChild("Event")
    local renderName = INFINITE_GRENADES_RENDER_NAME

    pcall(RunService.UnbindFromRenderStep, RunService, renderName)

    local cameraModules = filtergc("table", {
        Keys = {
            "activeCameraController",
            "activeOcclusionModule",
        },
    }, false)

    assert(
        #cameraModules == 1,
        "Camera module could not be uniquely identified"
    )

    local state = {
        enabled = true,
        connections = {},
        characterConnection = nil,
        backpackRemovedConnection = nil,
        backpackAddedConnection = nil,
        primaryWeapon = "Machine Gun",
        requestInterval = 0.25,
        lastRequest = 0,
        pending = false,
        workerRunning = false,
        requestCount = 0,
        savedView = nil,
        viewToken = 0,
        viewLockFrames = 2,
        autoSelect = true,
        refreshPending = false,
        refreshRequestAt = nil,
        renderName = renderName,
        cameraModule = cameraModules[1],
    }

    globals.__InfiniteGrenades = state

    local function getBackpack()
        return player:FindFirstChildOfClass("Backpack")
    end

    local function findTool(name)
        local backpack = getBackpack()

        return (backpack and backpack:FindFirstChild(name))
            or (player.Character and player.Character:FindFirstChild(name))
    end

    local function updatePrimaryWeapon()
        for name in pairs(PRIMARY_WEAPON_NAMES) do
            if findTool(name) then
                state.primaryWeapon = name
                return
            end
        end
    end

    local function equipGrenade()
        if not state.enabled
            or not state.autoSelect
            or not state.refreshPending
        then
            return
        end

        task.spawn(function()
            task.wait(0.05)

            if not state.enabled or not state.refreshPending then
                return
            end

            local character = player.Character
            local humanoid = character and character:FindFirstChildOfClass("Humanoid")
            local grenade = findTool("Grenade")

            if grenade and grenade.Parent == character then
                state.refreshPending = false
            elseif humanoid and grenade then
                humanoid:EquipTool(grenade)
                state.refreshPending = false
            end
        end)
    end

    local function captureView(character, root, camera)
        state.savedView = {
            character = character,
            rootRotation = root.CFrame.Rotation,
            cameraRelative = root.CFrame:ToObjectSpace(camera.CFrame),
            cameraRotation = camera.CFrame.Rotation,
            focusRelative = root.CFrame:ToObjectSpace(camera.Focus),
            cameraType = camera.CameraType,
            cameraSubject = camera.CameraSubject,
        }
    end

    local function captureCurrentView()
        local character = player.Character
        local root = character and character:FindFirstChild("HumanoidRootPart")
        local camera = workspace.CurrentCamera

        if character and root and camera then
            captureView(character, root, camera)
        end
    end

    local function restoreView(character)
        local view = state.savedView
        local targetCharacter = character or player.Character

        if not view
            or not state.enabled
            or not targetCharacter
        then
            return
        end

        state.viewToken = state.viewToken + 1
        local token = state.viewToken

        pcall(RunService.UnbindFromRenderStep, RunService, renderName)

        local function apply()
            if not state.enabled
                or state.viewToken ~= token
                or player.Character ~= targetCharacter
            then
                return false
            end

            local root = targetCharacter:FindFirstChild("HumanoidRootPart")
            local camera = workspace.CurrentCamera

            if not root or not camera then
                return false
            end

            root.CFrame = CFrame.new(root.Position) * view.rootRotation

            local relativeCamera = root.CFrame * view.cameraRelative
            local desiredCamera = CFrame.new(relativeCamera.Position)
                * view.cameraRotation
            local desiredFocus = root.CFrame * view.focusRelative

            camera.CameraType = view.cameraType

            if targetCharacter ~= view.character then
                local humanoid = targetCharacter:FindFirstChildOfClass("Humanoid")

                if humanoid then
                    camera.CameraSubject = humanoid
                end
            elseif view.cameraSubject and view.cameraSubject.Parent then
                camera.CameraSubject = view.cameraSubject
            end

            camera.CFrame = desiredCamera
            camera.Focus = desiredFocus

            local controller = state.cameraModule.activeCameraController

            if type(controller) == "table" then
                controller.lastCameraTransform = desiredCamera
                controller.lastCameraFocus = desiredFocus
                controller.lastSubjectPosition = root.Position
                controller.lastSubjectCFrame = nil
                controller.lastUpdate = tick()
                controller.lastUserPanCamera = tick()
                controller.resetCameraAngle = false
            end

            return true
        end

        local appliedFrames = 0

        local function stabilize()
            if apply() then
                appliedFrames = appliedFrames + 1

                if appliedFrames >= state.viewLockFrames
                    and state.viewToken == token
                then
                    pcall(RunService.UnbindFromRenderStep, RunService, renderName)
                end
            end
        end

        apply()

        RunService:BindToRenderStep(
            renderName,
            Enum.RenderPriority.Camera.Value + 1,
            stabilize
        )
    end

    local ensureGrenade

    ensureGrenade = function()
        state.pending = true

        if state.workerRunning then
            return
        end

        state.workerRunning = true

        task.spawn(function()
            task.wait(0.05)

            while state.enabled and not findTool("Grenade") do
                local elapsed = os.clock() - state.lastRequest

                if elapsed < state.requestInterval then
                    task.wait(state.requestInterval - elapsed)
                else
                    local character = player.Character
                    local root = character and character:FindFirstChild("HumanoidRootPart")
                    local camera = workspace.CurrentCamera

                    if character and root and camera then
                        updatePrimaryWeapon()

                        if not state.savedView then
                            captureView(character, root, camera)
                        end

                        state.lastRequest = os.clock()
                        state.requestCount = state.requestCount + 1
                        state.refreshRequestAt = os.clock()

                        event:FireServer("Spawn", {
                            state.primaryWeapon,
                            root.Position,
                        })
                    end

                    task.wait(0.05)
                end
            end

            state.pending = false
            state.workerRunning = false

            if state.enabled and findTool("Grenade") then
                equipGrenade()
            end

            if state.enabled and not findTool("Grenade") then
                ensureGrenade()
            end
        end)
    end

    state.ensureGrenade = ensureGrenade

    local function onToolRemoved(child)
        if child:IsA("Tool") and child.Name == "Grenade" then
            captureCurrentView()
            ensureGrenade()
        end
    end

    local function onToolAdded(child)
        if child:IsA("Tool") and child.Name == "Grenade" then
            equipGrenade()
        end
    end

    local function watchCharacter(character)
        if state.characterConnection then
            state.characterConnection:Disconnect()
        end

        state.characterConnection = character.ChildRemoved:Connect(onToolRemoved)
        restoreView(character)
    end

    local function watchBackpack(backpack, refreshed)
        if state.backpackRemovedConnection then
            state.backpackRemovedConnection:Disconnect()
        end

        if state.backpackAddedConnection then
            state.backpackAddedConnection:Disconnect()
        end

        state.backpackRemovedConnection = backpack.ChildRemoved:Connect(onToolRemoved)
        state.backpackAddedConnection = backpack.ChildAdded:Connect(onToolAdded)

        if refreshed then
            state.refreshPending = true
            restoreView(player.Character)
        end

        if backpack:FindFirstChild("Grenade") then
            equipGrenade()
        end
    end

    table.insert(state.connections, player.CharacterAdded:Connect(function(character)
        state.refreshPending = true
        watchCharacter(character)

        if findTool("Grenade") then
            equipGrenade()
        end
    end))
    table.insert(state.connections, player.ChildAdded:Connect(function(child)
        if child:IsA("Backpack") then
            watchBackpack(child, true)
        end
    end))

    if player.Character then
        watchCharacter(player.Character)
    end

    local backpack = getBackpack()

    if backpack then
        watchBackpack(backpack, false)
    end

    updatePrimaryWeapon()

    if not findTool("Grenade") then
        ensureGrenade()
    end

    print("Infinite grenades enabled")
end

clearInstantReloadOverride()
disableInfiniteAmmo()
clearLegacyInfiniteMortars()
disableFireRate()
disableNoSpread()
disableInfiniteGrenades()

local playerGui = player:WaitForChild("PlayerGui")
local hiddenUiInstances = {}

local function hasPrimaryWeapon()
    local character = player.Character
    local backpack = player:FindFirstChildOfClass("Backpack")

    for name in pairs(PRIMARY_WEAPON_NAMES) do
        if (character and character:FindFirstChild(name))
            or (backpack and backpack:FindFirstChild(name))
        then
            return true
        end
    end

    return false
end

local currentCharacter = player.Character
local currentHumanoid = currentCharacter
    and currentCharacter:FindFirstChildOfClass("Humanoid")
local weaponChooserAllowed = not currentCharacter
    or not currentHumanoid
    or currentHumanoid.Health <= 0
    or not hasPrimaryWeapon()
local weaponChooserWasVisible = false

local function grenadeRefreshIsRecent()
    local state = globals.__InfiniteGrenades

    return state
        and state.enabled
        and state.refreshRequestAt
        and os.clock() - state.refreshRequestAt < 2
end

local function shouldHideGameUi(instance)
    local mode = HIDDEN_GAME_UI[instance.Name]

    return mode == "Always"
        or (mode == "DuringGameplay" and not weaponChooserAllowed)
end

local function hideGameUi(instance)
    local parent = instance.Parent

    if not instance:IsA("GuiObject")
        or not HIDDEN_GAME_UI[instance.Name]
        or not parent
        or parent.Name ~= "StaticScreenGui"
    then
        return
    end

    if not hiddenUiInstances[instance] then
        hiddenUiInstances[instance] = true
        table.insert(
            mainConnections,
            instance:GetPropertyChangedSignal("Visible"):Connect(function()
                if instance.Visible and shouldHideGameUi(instance) then
                    instance.Visible = false
                elseif instance.Name == "WeaponFrame" then
                    if instance.Visible then
                        weaponChooserWasVisible = true
                    elseif weaponChooserWasVisible then
                        weaponChooserWasVisible = false
                        weaponChooserAllowed = false
                    end
                end
            end)
        )
    end

    if shouldHideGameUi(instance) then
        instance.Visible = false
    elseif instance.Name == "WeaponFrame" and instance.Visible then
        weaponChooserWasVisible = true
    end
end

local function hideStaticGameUi(screenGui)
    if not screenGui or screenGui.Name ~= "StaticScreenGui" then
        return
    end

    for name in pairs(HIDDEN_GAME_UI) do
        local instance = screenGui:FindFirstChild(name)

        if instance then
            hideGameUi(instance)
        end
    end
end

hideStaticGameUi(playerGui:FindFirstChild("StaticScreenGui"))
table.insert(mainConnections, playerGui.DescendantAdded:Connect(function(instance)
    if instance:IsA("ScreenGui") then
        hideStaticGameUi(instance)
    else
        hideGameUi(instance)
    end
end))

local function bindWeaponChooserToCharacter(character)
    local function bindHumanoid(humanoid)
        table.insert(mainConnections, humanoid.Died:Connect(function()
            weaponChooserAllowed = true
            weaponChooserWasVisible = false
        end))
    end

    local humanoid = character:FindFirstChildOfClass("Humanoid")

    if humanoid then
        bindHumanoid(humanoid)
        return
    end

    local childAddedConnection
    childAddedConnection = character.ChildAdded:Connect(function(child)
        if child:IsA("Humanoid") then
            childAddedConnection:Disconnect()
            bindHumanoid(child)
        end
    end)
    table.insert(mainConnections, childAddedConnection)
end

local function showWeaponChooserIfAllowed()
    if not weaponChooserAllowed then
        return
    end

    local staticScreenGui = playerGui:FindFirstChild("StaticScreenGui")
    local weaponFrame = staticScreenGui
        and staticScreenGui:FindFirstChild("WeaponFrame")

    if weaponFrame then
        weaponFrame.Visible = true
    end
end

local function scheduleWeaponChooserFallback(character)
    task.delay(0.5, function()
        local activeMain = globals.__NephrenMain

        if not activeMain
            or activeMain.session ~= mainSession
            or player.Character ~= character
            or hasPrimaryWeapon()
        then
            return
        end

        weaponChooserAllowed = true
        weaponChooserWasVisible = false
        showWeaponChooserIfAllowed()
    end)
end

table.insert(mainConnections, player.CharacterAdded:Connect(function(character)
    if not grenadeRefreshIsRecent() then
        weaponChooserAllowed = true
        weaponChooserWasVisible = false
    end

    bindWeaponChooserToCharacter(character)
    showWeaponChooserIfAllowed()
    scheduleWeaponChooserFallback(character)
end))
table.insert(mainConnections, player.CharacterRemoving:Connect(function(character)
    local humanoid = character:FindFirstChildOfClass("Humanoid")

    if not grenadeRefreshIsRecent()
        or not humanoid
        or humanoid.Health <= 0
    then
        weaponChooserAllowed = true
        weaponChooserWasVisible = false
    end
end))

if player.Character then
    bindWeaponChooserToCharacter(player.Character)
    scheduleWeaponChooserFallback(player.Character)
end

showWeaponChooserIfAllowed()

window = Nephren:CreateWindow({
    Title = "Nephren",
    Size = Vector2.new(420, 300),
    ToggleKey = Enum.KeyCode.K,
})

local weaponTab = window:AddTab("Weapon")
local aimbotTab = window:AddTab("Aimbot")
local espTab = window:AddTab("ESP")
local configTab = window:AddTab("Config")
local weaponSection = weaponTab:AddSection({
    Title = "Weapon",
    Side = "Left",
    Height = 169,
})
local aimbotSection = aimbotTab:AddSection({
    Title = "Aimbot",
    Side = "Left",
})
local espSection = espTab:AddSection({
    Title = "Player ESP",
    Side = "Left",
})
local espDetailsSection = espTab:AddSection({
    Title = "Player Info",
    Side = "Right",
})
local configSelectionSection = configTab:AddSection({
    Title = "Configs",
    Side = "Left",
})
local configActionsSection = configTab:AddSection({
    Title = "Actions",
    Side = "Right",
})

weaponSection:AddToggle({
    Text = "Infinite Ammo",
    Default = false,
    Flag = "InfiniteAmmo",
    Callback = function(enabled, control)
        if not enabled then
            disableInfiniteAmmo()
            return
        end

        local succeeded, failure = pcall(enableInfiniteAmmo)

        if not succeeded then
            disableInfiniteAmmo()
            control:SetValue(false, true)
            warn("Failed to enable infinite ammo: " .. tostring(failure))
        end
    end,
})

weaponSection:AddToggle({
    Text = "No Spread",
    Default = false,
    Flag = "NoSpread",
    Callback = function(enabled, control)
        if not enabled then
            disableNoSpread()
            return
        end

        local succeeded, failure = pcall(enableNoSpread)

        if not succeeded then
            disableNoSpread()
            control:SetValue(false, true)
            warn("Failed to disable weapon spread: " .. tostring(failure))
        end
    end,
})

aimAssistToggle = aimbotSection:AddToggle({
    Text = "Enabled",
    Default = false,
    Flag = "AimAssist",
    Callback = function(enabled)
        aimAssistMasterEnabled = enabled
        refreshAimAssist()
    end,
})

aimbotSection:AddToggle({
    Text = "Team Check",
    Default = aimTeamCheckEnabled,
    Flag = "AimAssistTeamCheck",
    Callback = function(enabled)
        aimTeamCheckEnabled = enabled
    end,
})

aimbotSection:AddToggle({
    Text = "Visibility Check",
    Default = aimVisibilityCheckEnabled,
    Flag = "AimAssistVisibilityCheck",
    Callback = function(enabled)
        aimVisibilityCheckEnabled = enabled
    end,
})

aimbotSection:AddSlider({
    Text = "Smoothness",
    Min = MIN_AIM_SMOOTHNESS,
    Max = MAX_AIM_SMOOTHNESS,
    Step = 0.1,
    Default = aimSmoothness,
    Suffix = "x",
    Flag = "AimAssistSmoothness",
    Callback = function(value)
        aimSmoothness = value
        aimMoveResidualX = 0
        aimMoveResidualY = 0
    end,
})

aimbotSection:AddDropdown({
    Text = "Activation Mode",
    Values = {
        "Always On",
        "On Bind Press",
    },
    Default = aimAssistActivationMode,
    Flag = "AimAssistActivationMode",
    Callback = function(value)
        aimAssistActivationMode = value
        refreshAimAssist()
    end,
})

aimbotSection:AddKeybind({
    Text = "Aim Key",
    Default = Enum.UserInputType.MouseButton2,
    Mode = "Hold",
    Flag = "AimAssistKey",
    Callback = function(held)
        aimAssistBindHeld = held
        refreshAimAssist()
    end,
})

espSection:AddToggle({
    Text = "Enabled",
    Default = espEnabled,
    Flag = "ESPEnabled",
    Callback = function(enabled)
        setEspEnabled(enabled)
    end,
})

espSection:AddToggle({
    Text = "Team Check",
    Default = espTeamCheckEnabled,
    Flag = "ESPTeamCheck",
    Callback = function(enabled)
        espTeamCheckEnabled = enabled
    end,
})

espSection:AddDropdown({
    Text = "Box Style",
    Values = ESP_BOX_STYLES,
    Default = espBoxStyle,
    Flag = "ESPBoxStyle",
    Callback = function(value)
        espBoxStyle = value
    end,
})

espSection:AddColorPicker({
    Text = "Box Color",
    Default = espBoxColor,
    Flag = "ESPBoxColor",
    Callback = function(color)
        espBoxColor = color
        refreshEspStyles()
    end,
})

espSection:AddToggle({
    Text = "Filled",
    Default = espFillEnabled,
    Flag = "ESPFillEnabled",
    Callback = function(enabled)
        espFillEnabled = enabled
    end,
})

espSection:AddSlider({
    Text = "Fill Transparency",
    Min = 0,
    Max = 100,
    Step = 1,
    Default = espFillTransparency,
    Suffix = "%",
    Flag = "ESPFillTransparency",
    Callback = function(value)
        espFillTransparency = value
        refreshEspStyles()
    end,
})

espDetailsSection:AddToggle({
    Text = "Names",
    Default = espNamesEnabled,
    Flag = "ESPNamesEnabled",
    Callback = function(enabled)
        espNamesEnabled = enabled
    end,
})

espDetailsSection:AddToggle({
    Text = "Distance",
    Default = espDistanceEnabled,
    Flag = "ESPDistanceEnabled",
    Callback = function(enabled)
        espDistanceEnabled = enabled
    end,
})

espDetailsSection:AddSlider({
    Text = "Render Distance",
    Min = MIN_ESP_RENDER_DISTANCE,
    Max = MAX_ESP_RENDER_DISTANCE,
    Step = 100,
    Default = espRenderDistance,
    Suffix = " studs",
    Flag = "ESPRenderDistance",
    Callback = function(value)
        espRenderDistance = value
        espRenderDistanceSquared = value * value
    end,
})

weaponSection:AddToggle({
    Text = "Infinite Grenades",
    Default = false,
    Flag = "InfiniteGrenades",
    Callback = function(enabled, control)
        if not enabled then
            disableInfiniteGrenades()
            return
        end

        local succeeded, failure = pcall(enableInfiniteGrenades)

        if not succeeded then
            disableInfiniteGrenades()
            control:SetValue(false, true)
            warn("Failed to enable infinite grenades: " .. tostring(failure))
        end
    end,
})

weaponSection:AddToggle({
    Text = "Fire Rate",
    Default = false,
    Flag = "MachineGunFireRate",
    Callback = function(enabled, control)
        if not enabled then
            disableFireRate()
            return
        end

        local succeeded, failure = pcall(enableFireRate, selectedFireRate)

        if not succeeded then
            control:SetValue(false, true)
            warn("Failed to change machine gun fire rate: " .. tostring(failure))
        end
    end,
})

weaponSection:AddSlider({
    Text = "RPM",
    Min = 60,
    Max = 3000,
    Step = 10,
    Default = DEFAULT_TARGET_RPM,
    Flag = "MachineGunRPM",
    Callback = function(value)
        selectedFireRate = value

        if globals.__MachineGunFireRate then
            local succeeded, failure = pcall(updateFireRate, value)

            if not succeeded then
                warn("Failed to update machine gun fire rate: " .. tostring(failure))
            end
        end
    end,
})

local pendingDeleteName
local pendingDeleteUntil = 0
local configNameInput = configSelectionSection:AddTextbox({
    Text = "Config Name",
    Default = "default",
    Placeholder = "default",
    MaxLength = 64,
    Live = false,
    Persist = false,
    Finished = function()
        pendingDeleteName = nil
        pendingDeleteUntil = 0
    end,
})

local configSelector = configSelectionSection:AddDropdown({
    Text = "Saved Config",
    Values = {},
    Placeholder = "Select a config",
    Persist = false,
    Callback = function(value)
        pendingDeleteName = nil
        pendingDeleteUntil = 0

        if value then
            configNameInput:SetValue(value, true)
        end
    end,
})

local configStatus = configSelectionSection:AddLabel({
    Text = "Ready",
})

local configApiAvailable = type(window.SaveConfig) == "function"
    and type(window.LoadConfig) == "function"
    and type(window.ListConfigs) == "function"
    and type(window.DeleteConfig) == "function"

local function setConfigFailure(action, failure)
    configStatus:SetValue(action .. " failed (see console)")
    warn("[Nephren config] " .. action .. " failed: " .. tostring(failure))
end

local function requireConfigApi()
    if configApiAvailable then
        return true
    end

    setConfigFailure("Config", "the loaded Nephren library does not support configs")
    return false
end

local function refreshConfigList(preferredName, announce)
    if not requireConfigApi() then
        return false
    end

    local previousSelection = preferredName or configSelector:GetValue()
    local configs, failure = window:ListConfigs()

    if not configs then
        configSelector:SetValues({}, false)
        configSelector:SetValue(nil, true)
        setConfigFailure("Refresh", failure)
        return false
    end

    configSelector:SetValues(configs, false)

    if previousSelection and table.find(configs, previousSelection) then
        configSelector:SetValue(previousSelection, true)
    else
        configSelector:SetValue(nil, true)
    end

    if announce ~= false then
        configStatus:SetValue(string.format("Found %d configs", #configs))
    end

    return true
end

configActionsSection:AddButton({
    Text = "Save",
    Callback = function()
        pendingDeleteName = nil
        pendingDeleteUntil = 0

        if not requireConfigApi() then
            return
        end

        local saved, countOrFailure, normalizedName = window:SaveConfig(
            configNameInput:GetValue()
        )

        if not saved then
            setConfigFailure("Save", countOrFailure)
            return
        end

        configNameInput:SetValue(normalizedName, true)
        local refreshed = refreshConfigList(normalizedName, false)

        if refreshed then
            configStatus:SetValue(string.format("Saved %d settings", countOrFailure))
        else
            configStatus:SetValue("Saved; refresh failed")
        end
    end,
})

configActionsSection:AddButton({
    Text = "Load",
    Callback = function()
        pendingDeleteName = nil
        pendingDeleteUntil = 0

        if not requireConfigApi() then
            return
        end

        local loaded, appliedOrFailure, skipped = window:LoadConfig(
            configNameInput:GetValue(),
            false
        )

        if not loaded then
            setConfigFailure("Load", appliedOrFailure)
            return
        end

        configStatus:SetValue(
            string.format("Loaded %d, skipped %d", appliedOrFailure, skipped)
        )
    end,
})

configActionsSection:AddButton({
    Text = "Delete",
    Callback = function()
        if not requireConfigApi() then
            return
        end

        local name = configNameInput:GetValue()
        local now = os.clock()

        if pendingDeleteName ~= name or now > pendingDeleteUntil then
            pendingDeleteName = name
            pendingDeleteUntil = now + 3
            configStatus:SetValue("Press Delete again")
            return
        end

        pendingDeleteName = nil
        pendingDeleteUntil = 0
        local deleted, nameOrFailure = window:DeleteConfig(name)

        if not deleted then
            setConfigFailure("Delete", nameOrFailure)
            return
        end

        configNameInput:SetValue("default", true)
        configSelector:SetValue(nil, true)
        local refreshed = refreshConfigList(nil, false)

        if refreshed then
            configStatus:SetValue("Config deleted")
        else
            configStatus:SetValue("Deleted; refresh failed")
        end
    end,
})

configActionsSection:AddButton({
    Text = "Refresh",
    Callback = function()
        pendingDeleteName = nil
        pendingDeleteUntil = 0
        refreshConfigList(nil, true)
    end,
})

refreshConfigList(configNameInput:GetValue(), true)

globals.__NephrenMain = {
    library = Nephren,
    window = window,
    connections = mainConnections,
    session = mainSession,
    cleanup = destroyAllEspRecords,
}
