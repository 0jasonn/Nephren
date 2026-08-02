local Nephren = loadstring(readfile("src/Nephren.lua"))()

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local player = Players.LocalPlayer
local globals = getgenv()
local previousMain = globals.__NephrenMain
local DEFAULT_TARGET_RPM = 1200
local DEFAULT_TARGET_DELAY = 60 / DEFAULT_TARGET_RPM
local DEFAULT_FIRE_DELAY = 0.08
local DEFAULT_SPREAD_MULTIPLIER = 0.013
local INFINITE_GRENADES_RENDER_NAME = "__InfiniteGrenadesPreserveView"
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

local function getMachineGun()
    local character = player.Character
    local tool = (character and character:FindFirstChild("Machine Gun"))
        or player.Backpack:FindFirstChild("Machine Gun")

    assert(tool, "Machine gun not found")

    local weaponScript = tool:FindFirstChild("ThompsonLocalScript")
    assert(weaponScript, "Machine gun script not found")

    return tool, weaponScript
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
    local state = globals.__MachineGunInfiniteAmmo

    if not state then
        return
    end

    if type(state.activate) == "function"
        and type(state.ammoUpvalue) == "number"
        and type(state.originalAmmo) == "number"
    then
        debug.setupvalue(state.activate, state.ammoUpvalue, state.originalAmmo)
    end

    globals.__MachineGunInfiniteAmmo = nil
    print("Machine gun infinite ammo disabled")
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
    local state = globals.__MachineGunNoSpread

    if not state then
        return
    end

    if type(state.activate) == "function"
        and type(state.constantIndex) == "number"
        and type(state.originalSpread) == "number"
    then
        debug.setconstant(state.activate, state.constantIndex, state.originalSpread)
    end

    globals.__MachineGunNoSpread = nil
    print("Machine gun spread restored")
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

local function enableInfiniteAmmo()
    local _, weaponScript = getMachineGun()

    local environment = getsenv(weaponScript)
    assert(environment, "Weapon environment unavailable")

    local matches = filtergc("function", {
        Name = "Activate",
        Constants = { "FireServer", "Reloading..." },
        Environment = environment,
    }, false)

    assert(
        #matches == 1,
        "Expected one machine gun Activate closure, found " .. tostring(#matches)
    )

    local activate = matches[1]
    local ammoUpvalue = 1
    local originalAmmo = debug.getupvalue(activate, ammoUpvalue)

    assert(type(originalAmmo) == "number", "Unexpected ammo upvalue")

    debug.setupvalue(activate, ammoUpvalue, math.huge)

    globals.__MachineGunInfiniteAmmo = {
        script = weaponScript,
        activate = activate,
        ammoUpvalue = ammoUpvalue,
        originalAmmo = originalAmmo,
    }

    print("Machine gun infinite ammo enabled")
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
    local _, weaponScript = getMachineGun()
    local environment = getsenv(weaponScript)

    assert(environment, "Weapon environment unavailable")

    local matches = filtergc("function", {
        Name = "Activate",
        Constants = { DEFAULT_SPREAD_MULTIPLIER, "Exclude" },
        Environment = environment,
    }, false)

    assert(
        #matches == 1,
        "Expected one machine gun Activate closure, found " .. tostring(#matches)
    )

    local activate = matches[1]
    local changed = 0
    local constantIndex

    for index, value in pairs(debug.getconstants(activate)) do
        if value == DEFAULT_SPREAD_MULTIPLIER then
            changed = changed + 1
            constantIndex = index
        end
    end

    assert(
        changed == 1,
        "Expected one spread multiplier, found " .. tostring(changed)
    )

    debug.setconstant(activate, constantIndex, 0)

    globals.__MachineGunNoSpread = {
        activate = activate,
        constantIndex = constantIndex,
        originalSpread = DEFAULT_SPREAD_MULTIPLIER,
    }

    print("Machine gun spread disabled")
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

local window = Nephren:CreateWindow({
    Title = "Nephren",
    Size = Vector2.new(420, 300),
    ToggleKey = Enum.KeyCode.RightShift,
})

local mainTab = window:AddTab("Main")
local weaponSection = mainTab:AddSection({
    Title = "Weapon",
    Side = "Left",
    Height = 195,
})

weaponSection:AddToggle({
    Text = "Infinite Ammo",
    Default = false,
    Flag = "MachineGunInfiniteAmmo",
    Callback = function(enabled, control)
        if not enabled then
            disableInfiniteAmmo()
            return
        end

        local succeeded, failure = pcall(enableInfiniteAmmo)

        if not succeeded then
            control:SetValue(false, true)
            warn("Failed to enable machine gun infinite ammo: " .. tostring(failure))
        end
    end,
})

weaponSection:AddToggle({
    Text = "No Spread",
    Default = false,
    Flag = "MachineGunNoSpread",
    Callback = function(enabled, control)
        if not enabled then
            disableNoSpread()
            return
        end

        local succeeded, failure = pcall(enableNoSpread)

        if not succeeded then
            control:SetValue(false, true)
            warn("Failed to disable machine gun spread: " .. tostring(failure))
        end
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

globals.__NephrenMain = {
    library = Nephren,
    window = window,
    connections = mainConnections,
    session = mainSession,
}
