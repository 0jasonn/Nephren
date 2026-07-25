--[[
    Nephren
    A compact, Drawing-backed Luau UI library.

    Required host globals:
      Drawing.new
      Vector2
      Color3
      Enum
      game:GetService("UserInputService")

    No Roblox GUI instances are created. Every visible element is a Drawing object.
]]

local Nephren = {
    Version = "1.0.0",
    Flags = {},
}

local Window = {}
Window.__index = Window

local Tab = {}
Tab.__index = Tab

local Section = {}
Section.__index = Section

local Control = {}
Control.__index = Control

local KeybindAddon = {}
KeybindAddon.__index = KeybindAddon

local ColorPickerAddon = {}
ColorPickerAddon.__index = ColorPickerAddon

local function derive(base)
    local class = {}
    class.__index = class
    setmetatable(class, { __index = base })
    return class
end

local Button = derive(Control)
local Checkbox = derive(Control)
local Slider = derive(Control)
local Dropdown = derive(Control)
local MultiDropdown = derive(Dropdown)
local Spinner = derive(Control)
local Textbox = derive(Control)
local Listbox = derive(Control)
local Label = derive(Control)
local Separator = derive(Control)
local StandaloneKeybind = derive(Control)
local StandaloneColorPicker = derive(Control)

local function rgb(r, g, b)
    return Color3.fromRGB(r, g, b)
end

local DEFAULT_THEME = {
    Background = rgb(17, 17, 17),
    Topbar = rgb(0, 0, 0),
    Panel = rgb(20, 20, 20),
    Input = rgb(19, 19, 19),
    Control = rgb(37, 37, 37),
    ControlHover = rgb(44, 44, 44),
    ControlActive = rgb(48, 41, 45),
    SliderTrack = rgb(11, 11, 11),
    Border = rgb(0, 0, 0),
    Stroke = rgb(26, 26, 26),
    TabStroke = rgb(28, 28, 28),
    ControlBorder = rgb(11, 11, 11),
    ControlStroke = rgb(49, 49, 49),
    InputStroke = rgb(31, 31, 31),
    InnerBorder = rgb(49, 49, 49),
    Accent = rgb(219, 173, 177),
    AccentEnd = rgb(184, 169, 191),
    AccentDark = rgb(116, 92, 94),
    Text = rgb(255, 255, 255),
    MutedText = rgb(103, 103, 103),
    MenuIcon = rgb(109, 109, 109),
    DisabledText = rgb(73, 73, 73),
    Selection = rgb(52, 43, 46),
    Font = nil,
    TextSize = 14,
    HeaderHeight = 29,
    TitleWidth = 108,
    TabWidth = 57,
    SectionGap = 15,
    SectionPadding = 9,
    ControlWidth = 198,
}

local function copyTable(source)
    local result = {}
    for key, value in pairs(source or {}) do
        result[key] = value
    end
    return result
end

local function merge(base, overrides)
    local result = copyTable(base)
    for key, value in pairs(overrides or {}) do
        result[key] = value
    end
    return result
end

local function arrayCopy(source)
    local result = {}
    for index, value in ipairs(source or {}) do
        result[index] = value
    end
    return result
end

local function setCopy(source)
    local result = {}
    for key, value in pairs(source or {}) do
        if type(key) == "number" then
            result[value] = true
        elseif value then
            result[key] = true
        end
    end
    return result
end

local function clamp(value, minimum, maximum)
    if value < minimum then
        return minimum
    end
    if value > maximum then
        return maximum
    end
    return value
end

local function round(value)
    if value >= 0 then
        return math.floor(value + 0.5)
    end
    return math.ceil(value - 0.5)
end

local function snap(value, minimum, step)
    if not step or step <= 0 then
        return value
    end
    return minimum + round((value - minimum) / step) * step
end

local function pointInRect(point, rect)
    return point.X >= rect.X
        and point.Y >= rect.Y
        and point.X <= rect.X + rect.W
        and point.Y <= rect.Y + rect.H
end

local function setRect(rect, x, y, width, height)
    rect.X = x
    rect.Y = y
    rect.W = width
    rect.H = height
end

local function safeCall(callback, ...)
    if type(callback) ~= "function" then
        return
    end

    local ok, message = pcall(callback, ...)
    if not ok then
        warn("[Nephren] callback error: " .. tostring(message))
    end
end

local function optionText(config, fallback)
    return tostring(config.Text or config.Title or config.Name or config.Label or fallback or "")
end

local function getFont(theme)
    if theme.Font ~= nil then
        return theme.Font
    end
    if Drawing.Fonts then
        return Drawing.Fonts.Plex or Drawing.Fonts.UI or 2
    end
    return 2
end

local function centeredTextY(top, height, textSize)
    return math.floor(top + (height - textSize) * 0.5 + 0.5)
end

local function truncate(text, width, textSize)
    text = tostring(text or "")
    local approximateCharacterWidth = math.max(5, (textSize or 13) * 0.52)
    local limit = math.max(1, math.floor(width / approximateCharacterWidth))
    if #text <= limit then
        return text
    end
    if limit <= 3 then
        return string.sub(text, 1, limit)
    end
    return string.sub(text, 1, limit - 3) .. "..."
end

local function measuredTextWidth(record, text, textSize)
    local object = record and record.Object
    if object then
        local ok, bounds = pcall(function()
            return object.TextBounds
        end)
        if ok and bounds then
            local width = tonumber(bounds.X)
            if width and (width > 0 or text == "") then
                return width
            end
        end
    end
    return #text * ((textSize or 13) * 0.52)
end

local function decimalPlaces(step)
    local text = tostring(step or 1)
    local dot = string.find(text, ".", 1, true)
    if not dot then
        return 0
    end
    return math.min(6, #text - dot)
end

local function formatNumber(value, step)
    local places = decimalPlaces(step)
    if places == 0 then
        return tostring(round(value))
    end
    return string.format("%." .. tostring(places) .. "f", value)
end

local function valueExists(values, wanted)
    for _, value in ipairs(values) do
        if value == wanted then
            return true
        end
    end
    return false
end

local function removeFromArray(array, wanted)
    for index = #array, 1, -1 do
        if array[index] == wanted then
            table.remove(array, index)
            return
        end
    end
end

local function keyName(token)
    if token == nil then
        return "None"
    end
    local ok, name = pcall(function()
        return token.Name
    end)
    if ok and name then
        local replacements = {
            LeftControl = "LCtrl",
            RightControl = "RCtrl",
            LeftShift = "LShift",
            RightShift = "RShift",
            LeftAlt = "LAlt",
            RightAlt = "RAlt",
            MouseButton1 = "MB1",
            MouseButton2 = "MB2",
            MouseButton3 = "MB3",
            Backspace = "Bksp",
            CapsLock = "Caps",
            PageUp = "PgUp",
            PageDown = "PgDn",
        }
        return replacements[name] or name
    end
    return tostring(token)
end

local NORMAL_KEYS = {
    Zero = "0",
    One = "1",
    Two = "2",
    Three = "3",
    Four = "4",
    Five = "5",
    Six = "6",
    Seven = "7",
    Eight = "8",
    Nine = "9",
    Space = " ",
    Minus = "-",
    Equals = "=",
    LeftBracket = "[",
    RightBracket = "]",
    BackSlash = "\\",
    Semicolon = ";",
    Quote = "'",
    Comma = ",",
    Period = ".",
    Slash = "/",
    Backquote = "`",
}

local SHIFT_KEYS = {
    Zero = ")",
    One = "!",
    Two = "@",
    Three = "#",
    Four = "$",
    Five = "%",
    Six = "^",
    Seven = "&",
    Eight = "*",
    Nine = "(",
    Minus = "_",
    Equals = "+",
    LeftBracket = "{",
    RightBracket = "}",
    BackSlash = "|",
    Semicolon = ":",
    Quote = "\"",
    Comma = "<",
    Period = ">",
    Slash = "?",
    Backquote = "~",
}

local DELETE_REPEAT_DELAY = 0.42
local DELETE_REPEAT_INTERVAL = 0.12
local DELETE_REPEAT_MIN_INTERVAL = 0.03
local DELETE_REPEAT_ACCELERATION = 0.86

local function isDeleteKey(keyCode)
    return keyCode == Enum.KeyCode.Backspace
        or keyCode == Enum.KeyCode.Delete
end

local function inputToken(input)
    if input.UserInputType == Enum.UserInputType.Keyboard then
        return input.KeyCode
    end
    return input.UserInputType
end

local function keyIsDown(library, keyCode)
    if library._keysDown[keyCode] then
        return true
    end

    local userInputService = library._userInputService
    if not userInputService then
        return false
    end

    local ok, down = pcall(function()
        return userInputService:IsKeyDown(keyCode)
    end)
    return ok and down == true
end

local function inputCharacter(library, keyCode)
    local name = keyCode.Name
    local shifted = keyIsDown(library, Enum.KeyCode.LeftShift)
        or keyIsDown(library, Enum.KeyCode.RightShift)

    if #name == 1 and string.match(name, "%a") then
        if shifted ~= library._capsLock then
            return string.upper(name)
        end
        return string.lower(name)
    end

    if shifted and SHIFT_KEYS[name] then
        return SHIFT_KEYS[name]
    end
    return NORMAL_KEYS[name]
end

local function defaultPosition(size)
    local viewport = Vector2.new(1920, 1080)
    local ok, camera = pcall(function()
        return workspace.CurrentCamera
    end)
    if ok and camera then
        viewport = camera.ViewportSize
    end
    return Vector2.new(
        math.floor((viewport.X - size.X) * 0.5),
        math.floor((viewport.Y - size.Y) * 0.5)
    )
end

local function normalizeConfig(config, callback)
    if type(config) == "string" then
        return {
            Text = config,
            Callback = callback,
        }
    end
    return copyTable(config or {})
end

local function toHSV(color)
    local ok, h, s, v = pcall(function()
        return color:ToHSV()
    end)
    if ok then
        return h, s, v
    end

    local r, g, b = color.R, color.G, color.B
    local maximum = math.max(r, g, b)
    local minimum = math.min(r, g, b)
    local delta = maximum - minimum
    local hue = 0

    if delta > 0 then
        if maximum == r then
            hue = ((g - b) / delta) % 6
        elseif maximum == g then
            hue = ((b - r) / delta) + 2
        else
            hue = ((r - g) / delta) + 4
        end
        hue = hue / 6
    end

    local saturation = maximum == 0 and 0 or delta / maximum
    return hue, saturation, maximum
end

local function fromHSV(h, s, v)
    local ok, color = pcall(function()
        return Color3.fromHSV(h, s, v)
    end)
    if ok then
        return color
    end

    local i = math.floor(h * 6)
    local f = h * 6 - i
    local p = v * (1 - s)
    local q = v * (1 - f * s)
    local t = v * (1 - (1 - f) * s)
    i = i % 6
    if i == 0 then
        return Color3.new(v, t, p)
    elseif i == 1 then
        return Color3.new(q, v, p)
    elseif i == 2 then
        return Color3.new(p, v, t)
    elseif i == 3 then
        return Color3.new(p, q, v)
    elseif i == 4 then
        return Color3.new(t, p, v)
    end
    return Color3.new(v, p, q)
end

local function lerpColor(first, second, alpha)
    return Color3.new(
        first.R + (second.R - first.R) * alpha,
        first.G + (second.G - first.G) * alpha,
        first.B + (second.B - first.B) * alpha
    )
end

local function multiplyColor(color, amount)
    return Color3.new(
        clamp(color.R * amount, 0, 1),
        clamp(color.G * amount, 0, 1),
        clamp(color.B * amount, 0, 1)
    )
end

local function activeAccentGradient(theme)
    return multiplyColor(theme.Accent, 0.20),
        multiplyColor(theme.AccentEnd, 0.30)
end

local function newRoundedRect(window, bucket, color, localZ, radius, reinforceCorners)
    local group = {
        _kind = "RoundedRect",
        Parts = {},
        Position = window.Position,
        Size = Vector2.new(1, 1),
        Radius = radius or 3,
        ReinforceCorners = reinforceCorners == true,
        Color = color,
    }

    for _ = 1, 2 do
        table.insert(group.Parts, window:_newDrawing("Square", {
            Filled = true,
            Color = color,
            Position = window.Position,
            Size = Vector2.new(1, 1),
            ZIndex = window:_z(localZ),
            Transparency = 1,
            Visible = false,
        }, bucket))
    end
    for _ = 1, 4 do
        table.insert(group.Parts, window:_newDrawing("Circle", {
            Filled = true,
            Color = color,
            Position = window.Position,
            Radius = 1,
            NumSides = 16,
            Thickness = 1,
            ZIndex = window:_z(localZ),
            Transparency = 1,
            Visible = false,
        }, bucket))
    end
    if group.ReinforceCorners then
        for _ = 1, 4 do
            table.insert(group.Parts, window:_newDrawing("Circle", {
                Filled = false,
                Color = color,
                Position = window.Position,
                Radius = 1,
                NumSides = 16,
                Thickness = 1,
                ZIndex = window:_z(localZ),
                Transparency = 1,
                Visible = false,
            }, bucket))
        end
    end
    return group
end

local function layoutRoundedRect(window, group)
    local position = group.Position
    local size = group.Size
    local radius = math.max(
        0,
        math.min(group.Radius or 0, math.floor(size.X * 0.5), math.floor(size.Y * 0.5))
    )
    local x, y = position.X, position.Y
    local width, height = size.X, size.Y

    window:_set(group.Parts[1], {
        Position = Vector2.new(x + radius, y),
        Size = Vector2.new(math.max(0, width - radius * 2), height),
    })
    window:_set(group.Parts[2], {
        Position = Vector2.new(x, y + radius),
        Size = Vector2.new(width, math.max(0, height - radius * 2)),
    })

    local centers = {
        Vector2.new(x + radius, y + radius),
        Vector2.new(x + width - radius, y + radius),
        Vector2.new(x + radius, y + height - radius),
        Vector2.new(x + width - radius, y + height - radius),
    }
    for index = 1, 4 do
        window:_set(group.Parts[index + 2], {
            Position = centers[index],
            Radius = radius,
        })
        if group.ReinforceCorners then
            window:_set(group.Parts[index + 6], {
                Position = centers[index],
                Radius = radius,
            })
        end
    end
end

local function setRoundedColor(window, group, color)
    group.Color = color
    for _, part in ipairs(group.Parts) do
        window:_set(part, { Color = color })
    end
end

local function newGradient(
    window,
    bucket,
    localZ,
    startColor,
    endColor,
    segments,
    direction,
    radius
)
    local group = {
        _kind = "Gradient",
        Parts = {},
        Position = window.Position,
        Size = Vector2.new(1, 1),
        StartColor = startColor,
        EndColor = endColor,
        Segments = math.max(2, segments or 24),
        Direction = direction or "Horizontal",
        Radius = radius or 0,
    }
    for index = 1, group.Segments do
        local alpha = (index - 1) / (group.Segments - 1)
        table.insert(group.Parts, window:_newDrawing("Square", {
            Filled = true,
            Color = lerpColor(startColor, endColor, alpha),
            Position = window.Position,
            Size = Vector2.new(1, 1),
            ZIndex = window:_z(localZ),
            Transparency = 1,
            Visible = false,
        }, bucket))
    end
    if group.Direction == "Horizontal" and group.Radius > 0 then
        group.StartCap = window:_newDrawing("Circle", {
            Filled = true,
            Color = startColor,
            Position = window.Position,
            Radius = group.Radius,
            NumSides = 16,
            Thickness = 1,
            ZIndex = window:_z(localZ),
            Transparency = 1,
            Visible = false,
        }, bucket)
        group.EndCap = window:_newDrawing("Circle", {
            Filled = true,
            Color = endColor,
            Position = window.Position,
            Radius = group.Radius,
            NumSides = 16,
            Thickness = 1,
            ZIndex = window:_z(localZ),
            Transparency = 1,
            Visible = false,
        }, bucket)
        table.insert(group.Parts, group.StartCap)
        table.insert(group.Parts, group.EndCap)
    end
    return group
end

local function layoutGradient(window, group)
    local position = group.Position
    local size = group.Size
    local radius = math.max(
        0,
        math.min(group.Radius or 0, math.floor(size.X * 0.5), math.floor(size.Y * 0.5))
    )

    if group.Direction == "Vertical" then
        local sliceHeight = size.Y / group.Segments
        for index = 1, group.Segments do
            local inset = 0
            if radius > 0 then
                local edgeDistance = math.min(index - 1, group.Segments - index)
                inset = math.max(0, radius - edgeDistance)
            end
            window:_set(group.Parts[index], {
                Position = Vector2.new(
                    position.X + inset,
                    position.Y + (index - 1) * sliceHeight
                ),
                Size = Vector2.new(
                    math.max(0, size.X - inset * 2),
                    math.ceil(sliceHeight)
                ),
            })
        end
        return
    end

    local contentX = position.X + radius
    local contentWidth = math.max(0, size.X - radius * 2)
    local sliceWidth = contentWidth / group.Segments
    for index = 1, group.Segments do
        window:_set(group.Parts[index], {
            Position = Vector2.new(contentX + (index - 1) * sliceWidth, position.Y),
            Size = Vector2.new(math.ceil(sliceWidth), size.Y),
        })
    end
    if group.StartCap then
        local capY = position.Y + size.Y * 0.5
        window:_set(group.StartCap, {
            Position = Vector2.new(position.X + radius, capY),
            Radius = radius,
        })
        window:_set(group.EndCap, {
            Position = Vector2.new(
                position.X + size.X - radius,
                capY
            ),
            Radius = radius,
        })
    end
end

local function setGradientColors(window, group, startColor, endColor)
    group.StartColor = startColor
    group.EndColor = endColor
    for index = 1, group.Segments do
        local alpha = (index - 1) / (group.Segments - 1)
        window:_set(group.Parts[index], {
            Color = lerpColor(startColor, endColor, alpha),
        })
    end
    if group.StartCap then
        window:_set(group.StartCap, { Color = startColor })
        window:_set(group.EndCap, { Color = endColor })
    end
end

Nephren.Theme = DEFAULT_THEME
Nephren._windows = {}
Nephren._connections = {}
Nephren._keybinds = {}
Nephren._rainbowPickers = {}
Nephren._started = false
Nephren._focusedTextbox = nil
Nephren._bindingKeybind = nil
Nephren._capture = nil
Nephren._hoveredRegion = nil
Nephren._keysDown = {}
Nephren._capsLock = false
Nephren._deleteRepeat = nil

function Nephren:_mousePosition(input)
    if self._userInputService then
        local ok, position = pcall(function()
            return self._userInputService:GetMouseLocation()
        end)
        if ok and position then
            return position
        end
    end
    return Vector2.new(input.Position.X, input.Position.Y)
end

function Nephren:_setFocusedTextbox(textbox)
    if self._focusedTextbox and self._focusedTextbox ~= textbox then
        self:_stopDeleteRepeat(self._focusedTextbox)
        self._focusedTextbox:Blur(true)
    end
    self._focusedTextbox = textbox
end

function Nephren:_startDeleteRepeat(target, keyCode)
    if target ~= self._focusedTextbox
        or type(target._editText) ~= "string"
        or target._editText == ""
    then
        self._deleteRepeat = nil
        return
    end

    self._deleteRepeat = {
        Target = target,
        KeyCode = keyCode,
        TimeUntilNext = DELETE_REPEAT_DELAY,
        Interval = DELETE_REPEAT_INTERVAL,
    }
end

function Nephren:_stopDeleteRepeat(target)
    local repeatState = self._deleteRepeat
    if repeatState and (not target or repeatState.Target == target) then
        self._deleteRepeat = nil
    end
end

function Nephren:_stepDeleteRepeat(deltaTime)
    local repeatState = self._deleteRepeat
    if not repeatState then
        return
    end

    local target = repeatState.Target
    if target ~= self._focusedTextbox
        or target._destroyed
        or not self._keysDown[repeatState.KeyCode]
        or type(target._editText) ~= "string"
        or target._editText == ""
    then
        self._deleteRepeat = nil
        return
    end

    repeatState.TimeUntilNext =
        repeatState.TimeUntilNext - math.max(0, tonumber(deltaTime) or 0)
    local repeatCount = 0
    while repeatState.TimeUntilNext <= 0 and repeatCount < 32 do
        target:_onKey(repeatState.KeyCode)
        repeatCount = repeatCount + 1

        if self._deleteRepeat ~= repeatState
            or target ~= self._focusedTextbox
            or type(target._editText) ~= "string"
            or target._editText == ""
        then
            self._deleteRepeat = nil
            return
        end

        repeatState.Interval = math.max(
            DELETE_REPEAT_MIN_INTERVAL,
            repeatState.Interval * DELETE_REPEAT_ACCELERATION
        )
        repeatState.TimeUntilNext =
            repeatState.TimeUntilNext + repeatState.Interval
    end

    if repeatCount == 32 and repeatState.TimeUntilNext <= 0 then
        repeatState.TimeUntilNext = repeatState.Interval
    end
end

function Nephren:_setBindingKeybind(keybind)
    if self._bindingKeybind and self._bindingKeybind ~= keybind then
        self._bindingKeybind:_cancelBinding()
    end
    self._bindingKeybind = keybind
end

function Nephren:_topRegion(point)
    local bestRegion = nil
    local bestWindowIndex = -1
    local bestPriority = -math.huge
    local bestOrder = -1

    for windowIndex, window in ipairs(self._windows) do
        if not window._destroyed and window.Visible then
            for order, region in ipairs(window._regions) do
                local enabled = not region.Dead
                if enabled and region.Enabled then
                    enabled = region.Enabled()
                end
                if enabled and pointInRect(point, region.Rect) then
                    local priority = region.Priority or 0
                    if priority > bestPriority
                        or (priority == bestPriority and windowIndex > bestWindowIndex)
                        or (
                            priority == bestPriority
                            and windowIndex == bestWindowIndex
                            and order > bestOrder
                        )
                    then
                        bestRegion = region
                        bestWindowIndex = windowIndex
                        bestPriority = priority
                        bestOrder = order
                    end
                end
            end
        end
    end

    return bestRegion
end

function Nephren:_updateHover(point)
    local region = self:_topRegion(point)
    if region == self._hoveredRegion then
        return
    end

    if self._hoveredRegion and self._hoveredRegion.OnHover then
        self._hoveredRegion.OnHover(false)
    end
    self._hoveredRegion = region
    if region and region.OnHover then
        region.OnHover(true)
    end
end

function Nephren:_closeForeignPopups(region)
    for _, window in ipairs(self._windows) do
        local popup = window._openPopup
        if popup and (not region or region.PopupOwner ~= popup) then
            popup:Close()
        end
    end
end

function Nephren:_handleInputBegan(input, gameProcessed)
    local token = inputToken(input)
    local keyAlreadyDown = false

    if input.UserInputType == Enum.UserInputType.Keyboard then
        keyAlreadyDown = self._keysDown[token] == true
        self._keysDown[token] = true
        if token == Enum.KeyCode.CapsLock and not keyAlreadyDown then
            self._capsLock = not self._capsLock
        end
    end

    if self._bindingKeybind then
        if input.UserInputType == Enum.UserInputType.Keyboard
            or input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.MouseButton2
            or input.UserInputType == Enum.UserInputType.MouseButton3
        then
            local binding = self._bindingKeybind
            self._bindingKeybind = nil
            binding:_finishBinding(token)
            return
        end
    end

    if input.UserInputType == Enum.UserInputType.Keyboard then
        for _, window in ipairs(self._windows) do
            if not window._destroyed and window.ToggleKey == token then
                window:SetVisible(not window.Visible)
                return
            end
        end
    end

    if self._focusedTextbox and input.UserInputType == Enum.UserInputType.Keyboard then
        if isDeleteKey(input.KeyCode) and keyAlreadyDown then
            return
        end
        local focusedTextbox = self._focusedTextbox
        focusedTextbox:_onKey(input.KeyCode)
        if isDeleteKey(input.KeyCode) then
            self:_startDeleteRepeat(focusedTextbox, input.KeyCode)
        end
        return
    end

    if not gameProcessed then
        for _, keybind in ipairs(self._keybinds) do
            if not keybind._destroyed and not keybind._binding and keybind.Value == token then
                keybind:_inputBegan()
            end
        end
    end

    local isPrimary = input.UserInputType == Enum.UserInputType.MouseButton1
    if not isPrimary then
        return
    end

    local point = self:_mousePosition(input)
    local region = self:_topRegion(point)

    if self._focusedTextbox and (not region or region.Owner ~= self._focusedTextbox) then
        self._focusedTextbox:Blur(true)
    end
    self:_closeForeignPopups(region)

    if region and region.OnPress then
        local capture = region.OnPress(point, input)
        if capture then
            self._capture = region
        end
    end
    self:_updateHover(point)
end

function Nephren:_handleInputChanged(input)
    local inputType = input.UserInputType
    if inputType == Enum.UserInputType.MouseMovement then
        local point = self:_mousePosition(input)
        if self._capture and self._capture.OnMove then
            self._capture.OnMove(point, input)
        end
        self:_updateHover(point)
    elseif inputType == Enum.UserInputType.MouseWheel then
        local point = self:_mousePosition(input)
        local region = self:_topRegion(point)
        if region and region.OnWheel then
            region.OnWheel(input.Position.Z, point)
        end
    end
end

function Nephren:_handleInputEnded(input)
    local token = inputToken(input)
    if input.UserInputType == Enum.UserInputType.Keyboard then
        self._keysDown[token] = nil
        local repeatState = self._deleteRepeat
        if repeatState and repeatState.KeyCode == token then
            self:_stopDeleteRepeat(repeatState.Target)
        end
    end

    if input.UserInputType == Enum.UserInputType.MouseButton1 and self._capture then
        local capture = self._capture
        self._capture = nil
        if capture.OnRelease then
            capture.OnRelease(self:_mousePosition(input), input)
        end
    end

    for _, keybind in ipairs(self._keybinds) do
        if not keybind._destroyed and keybind.Value == token then
            keybind:_inputEnded()
        end
    end
end

function Nephren:_start()
    if self._started then
        return
    end

    assert(Drawing and Drawing.new, "Nephren requires Drawing.new")
    assert(game and game.GetService, "Nephren requires Roblox-style game:GetService")

    self._userInputService = game:GetService("UserInputService")
    self._runService = game:GetService("RunService")
    self._started = true

    table.insert(
        self._connections,
        self._userInputService.InputBegan:Connect(function(input, gameProcessed)
            self:_handleInputBegan(input, gameProcessed)
        end)
    )
    table.insert(
        self._connections,
        self._userInputService.InputChanged:Connect(function(input)
            self:_handleInputChanged(input)
        end)
    )
    table.insert(
        self._connections,
        self._userInputService.InputEnded:Connect(function(input)
            self:_handleInputEnded(input)
        end)
    )
    table.insert(
        self._connections,
        self._runService.RenderStepped:Connect(function(deltaTime)
            for _, picker in ipairs(self._rainbowPickers) do
                picker:_rainbowStep(deltaTime)
            end
            self:_stepDeleteRepeat(deltaTime)
        end)
    )
end

function Window:_z(localZ)
    return self.BaseZIndex + localZ
end

function Window:_newDrawing(kind, properties, bucket)
    local object = Drawing.new(kind)
    local record = {
        Object = object,
        WantedVisible = properties.Visible ~= false,
        Dead = false,
    }

    for property, value in pairs(properties) do
        if property ~= "Visible" then
            object[property] = value
        end
    end
    object.Visible = self.Visible and record.WantedVisible

    table.insert(self._drawings, record)
    if bucket then
        table.insert(bucket, record)
    end
    return record
end

function Window:_set(record, properties)
    if not record or record.Dead then
        return
    end
    if record._kind == "RoundedRect" then
        local needsLayout = false
        for property, value in pairs(properties) do
            if property == "Position" or property == "Size" or property == "Radius" then
                record[property] = value
                needsLayout = true
            elseif property == "Color" then
                setRoundedColor(self, record, value)
            elseif property == "Visible" then
                self:_show(record, value)
            else
                for _, part in ipairs(record.Parts) do
                    self:_set(part, { [property] = value })
                end
            end
        end
        if needsLayout then
            layoutRoundedRect(self, record)
        end
        return
    elseif record._kind == "Gradient" then
        local needsLayout = false
        local recolor = false
        for property, value in pairs(properties) do
            if property == "Position" or property == "Size" or property == "Radius" then
                record[property] = value
                needsLayout = true
            elseif property == "StartColor" or property == "EndColor" then
                record[property] = value
                recolor = true
            elseif property == "Visible" then
                self:_show(record, value)
            else
                for _, part in ipairs(record.Parts) do
                    self:_set(part, { [property] = value })
                end
            end
        end
        if recolor then
            setGradientColors(self, record, record.StartColor, record.EndColor)
        end
        if needsLayout then
            layoutGradient(self, record)
        end
        return
    end
    for property, value in pairs(properties) do
        if property == "Visible" then
            self:_show(record, value)
        else
            record.Object[property] = value
        end
    end
end

function Window:_show(record, visible)
    if not record or record.Dead then
        return
    end
    if record._kind == "RoundedRect" or record._kind == "Gradient" then
        for _, part in ipairs(record.Parts) do
            self:_show(part, visible)
        end
        return
    end
    record.WantedVisible = visible and true or false
    record.Object.Visible = self.Visible and record.WantedVisible
end

function Window:_removeDrawing(record)
    if not record or record.Dead then
        return
    end
    record.Dead = true
    pcall(function()
        record.Object:Remove()
    end)
end

function Window:_newRegion(owner, priority)
    local region = {
        Owner = owner,
        Rect = { X = 0, Y = 0, W = 0, H = 0 },
        Priority = priority or 0,
        Dead = false,
    }
    table.insert(self._regions, region)
    return region
end

function Window:_baseDrawing(kind, properties)
    return self:_newDrawing(kind, properties, self._baseDrawings)
end

function Window:_registerFlag(control, flag)
    if not flag then
        return
    end
    self._flagControls[flag] = control
    local value = control:GetValue()
    self.Flags[flag] = value
    Nephren.Flags[flag] = value
end

function Window:_setFlag(flag, value)
    if not flag then
        return
    end
    self.Flags[flag] = value
    Nephren.Flags[flag] = value
end

function Window:GetValue(flag)
    return self.Flags[flag]
end

function Window:SetValue(flag, value, silent)
    local control = self._flagControls[flag]
    if not control then
        return false
    end
    control:SetValue(value, silent)
    return true
end

function Window:_createBase()
    local theme = self.Theme
    local font = getFont(theme)

    self._outer = newRoundedRect(self, self._baseDrawings, theme.Border, 1, 4, true)
    self._windowStroke = newRoundedRect(
        self,
        self._baseDrawings,
        theme.Stroke,
        2,
        3,
        true
    )
    self._body = newRoundedRect(self, self._baseDrawings, theme.Background, 3, 2)
    self._topbar = newRoundedRect(self, self._baseDrawings, theme.Topbar, 4, 2)
    self:_show(self._outer, true)
    self:_show(self._windowStroke, true)
    self:_show(self._body, true)
    self:_show(self._topbar, true)
    self._headerLine = self:_baseDrawing("Line", {
        From = self.Position + Vector2.new(1, theme.HeaderHeight - 1),
        To = self.Position + Vector2.new(self.Size.X - 1, theme.HeaderHeight - 1),
        Color = theme.Border,
        Thickness = 1,
        ZIndex = self:_z(5),
        Transparency = 1,
        Visible = true,
    })
    self._titleDrawing = self:_baseDrawing("Text", {
        Text = self.Title,
        Font = font,
        Size = theme.TextSize,
        Position = self.Position + Vector2.new(
            7,
            centeredTextY(4, 25, theme.TextSize)
        ),
        Color = theme.Text,
        Outline = true,
        OutlineColor = theme.Border,
        OutlineOpacity = 1,
        ZIndex = self:_z(6),
        Transparency = 1,
        Visible = true,
    })

    self._dragRegion = self:_newRegion(self, 1)
    self._dragRegion.Enabled = function()
        return self.Visible and self.Draggable and not self._destroyed
    end
    self._dragRegion.OnPress = function(point)
        self._dragOffset = point - self.Position
        return true
    end
    self._dragRegion.OnMove = function(point)
        local position = point - self._dragOffset
        self:SetPosition(Vector2.new(math.floor(position.X), math.floor(position.Y)))
    end
    self._dragRegion.OnRelease = function()
        self._dragOffset = nil
    end
end

function Window:_layoutBase()
    local theme = self.Theme
    local position = self.Position
    local size = self.Size

    self:_set(self._outer, {
        Position = position,
        Size = size,
    })
    self:_set(self._windowStroke, {
        Position = position + Vector2.new(1, 1),
        Size = size - Vector2.new(2, 2),
    })
    self:_set(self._body, {
        Position = position + Vector2.new(2, 2),
        Size = size - Vector2.new(4, 4),
    })
    self:_set(self._topbar, {
        Position = position + Vector2.new(2, 2),
        Size = Vector2.new(size.X - 4, theme.HeaderHeight - 2),
    })
    self:_set(self._headerLine, {
        From = position + Vector2.new(1, theme.HeaderHeight - 1),
        To = position + Vector2.new(size.X - 1, theme.HeaderHeight - 1),
    })
    self:_set(self._titleDrawing, {
        Text = self.Title,
        Position = position + Vector2.new(
            7,
            centeredTextY(4, 25, theme.TextSize)
        ),
    })
    setRect(self._dragRegion.Rect, position.X + 1, position.Y + 1, size.X - 2, theme.HeaderHeight - 2)
end

function Window:_layout()
    if self._destroyed then
        return
    end

    self:_layoutBase()
    local tabX = self.Position.X + self.Theme.TitleWidth
    for _, tab in ipairs(self.Tabs) do
        tab:_layoutHeader(tabX, self.Position.Y)
        tabX = tabX + tab.Width
        tab:_layoutContent()
        tab:_syncVisibility()
    end
end

function Window:SetPosition(position)
    self.Position = position
    self:_layout()
    return self
end

function Window:SetSize(size)
    self.Size = Vector2.new(math.max(360, size.X), math.max(260, size.Y))
    self:_layout()
    return self
end

function Window:SetTitle(title)
    self.Title = tostring(title)
    self:_set(self._titleDrawing, { Text = self.Title })
    return self
end

function Window:SetVisible(visible)
    self.Visible = visible and true or false
    if not self.Visible then
        if self._openPopup then
            self._openPopup:Close()
        end
        if Nephren._focusedTextbox and Nephren._focusedTextbox._window == self then
            Nephren._focusedTextbox:Blur(true)
        end
    else
        self:_layout()
    end

    for _, record in ipairs(self._drawings) do
        if not record.Dead then
            record.Object.Visible = self.Visible and record.WantedVisible
        end
    end
    return self
end

Window.Show = function(self)
    return self:SetVisible(true)
end

Window.Hide = function(self)
    return self:SetVisible(false)
end

function Window:Toggle()
    return self:SetVisible(not self.Visible)
end

function Window:SelectTab(tabOrName)
    local selected = nil
    if type(tabOrName) == "string" then
        for _, tab in ipairs(self.Tabs) do
            if tab.Name == tabOrName then
                selected = tab
                break
            end
        end
    else
        selected = tabOrName
    end

    if not selected or selected._window ~= self then
        return false
    end

    if self._openPopup then
        self._openPopup:Close()
    end
    self.SelectedTab = selected
    self:_layout()
    return true
end

function Window:AddTab(config)
    if type(config) == "string" then
        config = { Name = config }
    else
        config = copyTable(config or {})
    end

    local tab = setmetatable({
        _window = self,
        Name = optionText(config, "Tab"),
        Width = config.Width or self.Theme.TabWidth,
        Sections = {},
        _drawings = {},
        _destroyed = false,
    }, Tab)

    tab:_createHeader()
    table.insert(self.Tabs, tab)
    if not self.SelectedTab then
        self.SelectedTab = tab
    end
    self:_layout()
    return tab
end

Window.Tab = Window.AddTab
Window.CreateTab = Window.AddTab

function Window:Destroy()
    if self._destroyed then
        return
    end
    self._destroyed = true

    if self._openPopup then
        self._openPopup:Close()
    end
    if Nephren._focusedTextbox and Nephren._focusedTextbox._window == self then
        Nephren._focusedTextbox:Blur(false)
    end
    if Nephren._bindingKeybind and Nephren._bindingKeybind._window == self then
        Nephren._bindingKeybind = nil
    end
    if Nephren._capture
        and Nephren._capture.Owner
        and Nephren._capture.Owner._window == self
    then
        Nephren._capture = nil
    end
    if Nephren._hoveredRegion
        and Nephren._hoveredRegion.Owner
        and Nephren._hoveredRegion.Owner._window == self
    then
        Nephren._hoveredRegion = nil
    end

    for _, tab in ipairs(self.Tabs) do
        tab._destroyed = true
        for _, section in ipairs(tab.Sections) do
            section._destroyed = true
            for _, control in ipairs(section.Controls) do
                if not control._destroyed then
                    control:Destroy()
                end
            end
        end
    end

    for _, region in ipairs(self._regions) do
        region.Dead = true
    end
    for _, record in ipairs(self._drawings) do
        self:_removeDrawing(record)
    end
    for flag in pairs(self.Flags) do
        if Nephren.Flags[flag] == self.Flags[flag] then
            Nephren.Flags[flag] = nil
        end
    end
    self.Flags = {}
    self._flagControls = {}
    removeFromArray(Nephren._windows, self)
end

Window.Remove = Window.Destroy

function Tab:_createHeader()
    local window = self._window
    local theme = window.Theme
    local font = getFont(theme)

    self._accent = newGradient(
        window,
        self._drawings,
        5,
        theme.Topbar,
        theme.Topbar,
        24,
        "Horizontal",
        3
    )
    self._stroke = newRoundedRect(window, self._drawings, theme.Topbar, 6, 3, true)
    self._inner = newRoundedRect(window, self._drawings, theme.Topbar, 7, 2)
    window:_show(self._stroke, false)
    window:_show(self._inner, false)
    window:_show(self._accent, false)
    self._bottomMask = window:_newDrawing("Square", {
        Filled = true,
        Position = window.Position,
        Size = Vector2.new(1, 1),
        Color = theme.Topbar,
        ZIndex = window:_z(8),
        Transparency = 1,
        Visible = false,
    }, self._drawings)
    self._text = window:_newDrawing("Text", {
        Text = self.Name,
        Font = font,
        Size = theme.TextSize,
        Center = true,
        Position = window.Position,
        Color = theme.MutedText,
        Outline = true,
        OutlineColor = theme.Border,
        OutlineOpacity = 1,
        ZIndex = window:_z(9),
        Transparency = 1,
        Visible = true,
    }, self._drawings)

    self._region = window:_newRegion(self, 10)
    self._region.Enabled = function()
        return window.Visible and not self._destroyed
    end
    self._region.OnPress = function()
        window:SelectTab(self)
        return false
    end
    self._region.OnHover = function(hovered)
        self._hovered = hovered
        self:_updateHeader()
    end
end

function Tab:_updateHeader()
    local window = self._window
    local theme = window.Theme
    local selected = window.SelectedTab == self

    window:_set(self._inner, {
        Color = selected and theme.Background or theme.Topbar,
    })
    window:_set(self._stroke, {
        Color = selected and theme.TabStroke or theme.Topbar,
    })
    window:_set(self._accent, {
        StartColor = selected and theme.Accent or theme.Topbar,
        EndColor = selected and theme.AccentEnd or theme.Topbar,
    })
    window:_set(self._bottomMask, {
        Color = selected and theme.Background or theme.Topbar,
    })
    window:_show(self._accent, selected)
    window:_show(self._stroke, selected)
    window:_show(self._inner, selected)
    window:_show(self._bottomMask, selected and window.Visible)
    window:_set(self._text, {
        Color = selected and theme.Text or (self._hovered and theme.Text or theme.MutedText),
    })
end

function Tab:_layoutHeader(x, y)
    local window = self._window
    local headerHeight = window.Theme.HeaderHeight
    window:_set(self._accent, {
        Position = Vector2.new(x, y + 3),
        Size = Vector2.new(self.Width, 6),
    })
    window:_set(self._stroke, {
        Position = Vector2.new(x, y + 5),
        Size = Vector2.new(self.Width, headerHeight - 4),
    })
    window:_set(self._inner, {
        Position = Vector2.new(x + 1, y + 6),
        Size = Vector2.new(self.Width - 2, headerHeight - 5),
    })
    window:_set(self._bottomMask, {
        Position = Vector2.new(x, y + headerHeight - 1),
        Size = Vector2.new(self.Width - 2, 1),
    })
    window:_set(self._text, {
        Position = Vector2.new(
            x + self.Width * 0.5,
            y + centeredTextY(4, 25, window.Theme.TextSize)
        ),
    })
    setRect(self._region.Rect, x, y + 1, self.Width, headerHeight - 1)
    self:_updateHeader()
end

function Tab:_layoutContent()
    local window = self._window
    local theme = window.Theme
    local padding = theme.SectionPadding
    local gap = theme.SectionGap
    local contentX = window.Position.X + 1
    local contentY = window.Position.Y + 1
    local contentWidth = window.Size.X - 2
    local available = contentWidth - padding * 2 - gap
    local leftWidth = math.floor(available * 0.5)
    local rightWidth = available - leftWidth
    local leftX = contentX + padding
    local rightX = leftX + leftWidth + gap
    local top = contentY + theme.HeaderHeight + 15
    local cursors = {
        Left = top,
        Right = top,
    }

    for _, section in ipairs(self.Sections) do
        local side = section.Side
        local width = side == "Right" and rightWidth or leftWidth
        local x = side == "Right" and rightX or leftX
        section:_layout(x, cursors[side], width)
        cursors[side] = cursors[side] + section:_totalHeight() + 10
    end
end

function Tab:_syncVisibility()
    local active = self._window.SelectedTab == self and self._window.Visible
    for _, section in ipairs(self.Sections) do
        section:_syncVisibility(active)
    end
end

function Tab:AddSection(config)
    if type(config) == "string" then
        config = { Name = config }
    else
        config = copyTable(config or {})
    end

    local side = config.Side or config.Column or "Left"
    if side == 2 or string.lower(tostring(side)) == "right" then
        side = "Right"
    else
        side = "Left"
    end

    local section = setmetatable({
        _tab = self,
        _window = self._window,
        Name = optionText(config, "Container"),
        Side = side,
        Height = config.Height,
        ControlWidth = config.ControlWidth,
        Controls = {},
        _drawings = {},
        _destroyed = false,
        _parentVisible = false,
    }, Section)

    section:_createFrame()
    table.insert(self.Sections, section)
    self._window:_layout()
    return section
end

Tab.Section = Tab.AddSection
Tab.CreateSection = Tab.AddSection

function Tab:Select()
    self._window:SelectTab(self)
    return self
end

function Section:_createFrame()
    local window = self._window
    local theme = window.Theme
    local font = getFont(theme)

    self._outer = newRoundedRect(window, self._drawings, theme.Border, 4, 2, true)
    self._stroke = newRoundedRect(window, self._drawings, theme.Stroke, 6, 3, true)
    self._inner = newRoundedRect(window, self._drawings, theme.Panel, 7, 2)
    self._accent = newGradient(
        window,
        self._drawings,
        5,
        theme.Accent,
        theme.AccentEnd,
        24,
        "Horizontal",
        3
    )
    self._title = window:_newDrawing("Text", {
        Text = self.Name,
        Font = font,
        Size = theme.TextSize,
        Position = window.Position,
        Color = theme.Text,
        Outline = true,
        OutlineColor = theme.Border,
        OutlineOpacity = 1,
        ZIndex = window:_z(9),
        Transparency = 1,
        Visible = false,
    }, self._drawings)
end

function Section:_contentHeight()
    local total = 12
    for _, control in ipairs(self.Controls) do
        if not control._destroyed then
            total = total + control._height
        end
    end
    return total + 5
end

function Section:_bodyHeight()
    return self.Height or math.max(38, self:_contentHeight())
end

function Section:_totalHeight()
    return 20 + self:_bodyHeight()
end

function Section:_layout(x, y, width)
    local window = self._window
    local bodyY = y + 20
    local bodyHeight = self:_bodyHeight()
    self._x = x
    self._y = y
    self._width = width
    self._bodyY = bodyY

    window:_set(self._outer, {
        Position = Vector2.new(x - 1, bodyY - 1),
        Size = Vector2.new(width + 2, bodyHeight + 2),
    })
    window:_set(self._stroke, {
        Position = Vector2.new(x, bodyY + 2),
        Size = Vector2.new(width, bodyHeight - 2),
    })
    window:_set(self._inner, {
        Position = Vector2.new(x + 1, bodyY + 3),
        Size = Vector2.new(width - 2, bodyHeight - 4),
    })
    window:_set(self._accent, {
        Position = Vector2.new(x, bodyY),
        Size = Vector2.new(width, 4),
    })
    window:_set(self._title, {
        Text = self.Name,
        Position = Vector2.new(
            x + 12,
            centeredTextY(y - 2, 22, window.Theme.TextSize)
        ),
    })

    local controlWidth = self.ControlWidth
        or math.min(window.Theme.ControlWidth, math.max(80, width - 20))
    local cursor = bodyY + 12
    for _, control in ipairs(self.Controls) do
        if not control._destroyed then
            control._rowWidth = math.max(controlWidth, width - 25)
            control:_layout(x + 9, cursor, controlWidth)
            cursor = cursor + control._height
        end
    end
end

function Section:_syncVisibility(parentVisible)
    self._parentVisible = parentVisible and not self._destroyed
    for _, drawing in ipairs(self._drawings) do
        self._window:_show(drawing, self._parentVisible)
    end
    for _, control in ipairs(self.Controls) do
        control:_syncVisibility(self._parentVisible)
    end
end

function Section:_add(control)
    table.insert(self.Controls, control)
    self._window:_registerFlag(control, control.Flag)
    self._window:_layout()
    return control
end

function Section:SetTitle(title)
    self.Name = tostring(title)
    self._window:_set(self._title, { Text = self.Name })
    return self
end

function Section:SetHeight(height)
    self.Height = height
    self._window:_layout()
    return self
end

function Control:_init(section, config, height)
    self._section = section
    self._tab = section._tab
    self._window = section._window
    self._library = Nephren
    self._config = config
    self._drawings = {}
    self._regions = {}
    self._height = height
    self._destroyed = false
    self._parentVisible = false
    self._hovered = false
    self.Text = optionText(config)
    self.Flag = config.Flag
    self.Callback = config.Callback
end

function Control:_draw(kind, properties, bucket)
    return self._window:_newDrawing(kind, properties, bucket or self._drawings)
end

function Control:_region(priority)
    local region = self._window:_newRegion(self, priority or 20)
    region.Enabled = function()
        return self._parentVisible and not self._destroyed
    end
    table.insert(self._regions, region)
    return region
end

function Control:_syncVisibility(parentVisible)
    self._parentVisible = parentVisible and not self._destroyed
    for _, drawing in ipairs(self._drawings) do
        self._window:_show(drawing, self._parentVisible)
    end
end

function Control:_changed(value, silent)
    self._window:_setFlag(self.Flag, value)
    if not silent then
        safeCall(self.Callback, value, self)
    end
end

function Control:GetValue()
    return self.Value
end

Control.Get = Control.GetValue

function Control:SetCallback(callback)
    self.Callback = callback
    return self
end

function Control:SetText(text)
    self.Text = tostring(text)
    if self._label then
        self._window:_set(self._label, { Text = self.Text })
    elseif self._text then
        self._window:_set(self._text, { Text = self.Text })
    end
    return self
end

function Control:Destroy()
    if self._destroyed then
        return
    end
    self._destroyed = true
    for _, region in ipairs(self._regions) do
        region.Dead = true
    end
    for _, drawing in ipairs(self._drawings) do
        self._window:_removeDrawing(drawing)
    end
    if self.Flag then
        self._window._flagControls[self.Flag] = nil
        self._window.Flags[self.Flag] = nil
        Nephren.Flags[self.Flag] = nil
    end
    self._window:_layout()
end

Control.Remove = Control.Destroy

local function createBox(control, z, fillColor, radius, innerRadius, strokeColor)
    local theme = control._window.Theme
    local window = control._window
    local rounding = radius or 4
    local innerRounding = innerRadius
    if innerRounding == nil then
        innerRounding = 1
    end
    local outer = newRoundedRect(
        window,
        control._drawings,
        theme.ControlBorder,
        z or 10,
        rounding
    )
    local stroke = newRoundedRect(
        window,
        control._drawings,
        strokeColor or theme.ControlStroke,
        (z or 10) + 1,
        math.max(0, innerRounding + 1)
    )
    local inner = newRoundedRect(
        window,
        control._drawings,
        fillColor or theme.Control,
        (z or 10) + 2,
        innerRounding
    )
    return outer, inner, stroke
end

local function layoutBox(window, outer, inner, stroke, x, y, width, height)
    window:_set(outer, {
        Position = Vector2.new(x, y),
        Size = Vector2.new(width, height),
    })
    window:_set(stroke, {
        Position = Vector2.new(x + 1, y + 1),
        Size = Vector2.new(width - 2, height - 2),
    })
    window:_set(inner, {
        Position = Vector2.new(x + 2, y + 2),
        Size = Vector2.new(width - 4, height - 4),
    })
end

local function createLabelDrawing(control, text, z)
    local theme = control._window.Theme
    return control:_draw("Text", {
        Text = text,
        Font = getFont(theme),
        Size = theme.TextSize,
        Position = control._window.Position,
        Color = theme.Text,
        Outline = true,
        OutlineColor = theme.Border,
        OutlineOpacity = 1,
        ZIndex = control._window:_z(z or 14),
        Transparency = 1,
        Visible = false,
    })
end

local function newButton(section, config, callback)
    config = normalizeConfig(config, callback)
    local self = setmetatable({}, Button)
    Control._init(self, section, config, config.Height or 37)

    self._outer, self._inner, self._highlight = createBox(self, 10)
    self._text = createLabelDrawing(self, self.Text, 14)
    self._window:_set(self._text, { Center = true })
    self._region = self:_region(20)
    self._region.OnPress = function()
        self._pressed = true
        self:_updateStyle()
        return true
    end
    self._region.OnRelease = function(point)
        local wasPressed = self._pressed
        self._pressed = false
        self:_updateStyle()
        if wasPressed and pointInRect(point, self._region.Rect) then
            safeCall(self.Callback, self)
        end
    end
    self._region.OnHover = function(hovered)
        self._hovered = hovered
        self:_updateStyle()
    end

    return section:_add(self)
end

function Button:_updateStyle()
    local theme = self._window.Theme
    local color = theme.Control
    if self._pressed then
        color = theme.ControlActive
    elseif self._hovered then
        color = theme.ControlHover
    end
    self._window:_set(self._inner, { Color = color })
end

function Button:_layout(x, y, width)
    local actualWidth = width + 2
    layoutBox(self._window, self._outer, self._inner, self._highlight, x, y, actualWidth, 27)
    self._window:_set(self._text, {
        Text = self.Text,
        Position = Vector2.new(
            x + actualWidth * 0.5,
            centeredTextY(y + 2, 25, self._window.Theme.TextSize)
        ),
    })
    setRect(self._region.Rect, x, y, actualWidth, 27)
end

function Button:Press()
    safeCall(self.Callback, self)
    return self
end

function Button:GetValue()
    return nil
end

local function newCheckbox(section, config)
    config = normalizeConfig(config)
    local self = setmetatable({}, Checkbox)
    Control._init(self, section, config, config.Height or 26)
    self.Value = config.Default == true or config.Value == true
    self._addons = {}

    local theme = self._window.Theme
    self._boxOuter = newRoundedRect(
        self._window,
        self._drawings,
        theme.ControlBorder,
        10,
        3
    )
    self._boxStroke = newRoundedRect(
        self._window,
        self._drawings,
        theme.ControlStroke,
        11,
        1
    )
    self._boxInner = newRoundedRect(
        self._window,
        self._drawings,
        theme.Input,
        12,
        0
    )
    self._check = newGradient(
        self._window,
        self._drawings,
        13,
        theme.Accent,
        theme.AccentEnd,
        8,
        "Horizontal",
        0
    )
    self._checkCorners = {}
    for _ = 1, 4 do
        table.insert(self._checkCorners, self:_draw("Square", {
            Filled = true,
            Color = theme.Control,
            Position = self._window.Position,
            Size = Vector2.new(1, 1),
            ZIndex = self._window:_z(14),
            Transparency = 1,
            Visible = false,
        }))
    end
    self._label = createLabelDrawing(self, self.Text, 14)

    self._region = self:_region(20)
    self._region.OnPress = function()
        self:SetValue(not self.Value)
        return false
    end
    self._region.OnHover = function(hovered)
        self._hovered = hovered
        self:_updateStyle()
    end
    self:_updateStyle()

    return section:_add(self)
end

function Checkbox:_updateStyle()
    local theme = self._window.Theme
    local innerColor = self._hovered and theme.ControlHover or theme.Control
    local checkedVisible = self._parentVisible and self.Value
    self._window:_set(self._boxInner, { Color = innerColor })
    self._window:_set(self._check, {
        StartColor = theme.Accent,
        EndColor = theme.AccentEnd,
    })
    self._window:_show(self._check, checkedVisible)
    for _, corner in ipairs(self._checkCorners) do
        self._window:_set(corner, { Color = innerColor })
        self._window:_show(corner, checkedVisible)
    end
end

function Checkbox:_layout(x, y, width)
    self._x = x
    self._y = y
    self._width = width
    self._window:_set(self._boxOuter, {
        Position = Vector2.new(x, y + 4),
        Size = Vector2.new(14, 14),
    })
    self._window:_set(self._boxStroke, {
        Position = Vector2.new(x + 1, y + 5),
        Size = Vector2.new(12, 12),
    })
    self._window:_set(self._boxInner, {
        Position = Vector2.new(x + 2, y + 6),
        Size = Vector2.new(10, 10),
    })
    self._window:_set(self._check, {
        Position = Vector2.new(x + 3, y + 7),
        Size = Vector2.new(8, 8),
    })
    local checkRight = x + 10
    local checkBottom = y + 14
    local cornerPositions = {
        Vector2.new(x + 3, y + 7),
        Vector2.new(checkRight, y + 7),
        Vector2.new(x + 3, checkBottom),
        Vector2.new(checkRight, checkBottom),
    }
    for index, position in ipairs(cornerPositions) do
        self._window:_set(self._checkCorners[index], {
            Position = position,
        })
    end
    self._window:_set(self._label, {
        Text = self.Text,
        Position = Vector2.new(
            x + 21,
            centeredTextY(y + 5, 14, self._window.Theme.TextSize)
        ),
    })
    setRect(self._region.Rect, x, y + 3, math.min(width, 21 + #self.Text * 7), 16)

    local addonX = x + (self._rowWidth or width)
    for index = #self._addons, 1, -1 do
        local addon = self._addons[index]
        addonX = addonX - addon:_preferredWidth()
        addon:_layout(addonX, y, addon:_preferredWidth())
        addonX = addonX - 6
    end
end

function Checkbox:_syncVisibility(parentVisible)
    Control._syncVisibility(self, parentVisible)
    self:_updateStyle()
    for _, addon in ipairs(self._addons) do
        addon:_syncVisibility(self._parentVisible)
    end
end

function Checkbox:SetValue(value, silent)
    self.Value = value and true or false
    for _, addon in ipairs(self._addons) do
        if addon._checkbox == self and addon.Mode == "Toggle" then
            addon.State = self.Value
        end
    end
    self:_updateStyle()
    self:_changed(self.Value, silent)
    return self
end

Checkbox.Set = Checkbox.SetValue

function Checkbox:Destroy()
    if self._destroyed then
        return
    end
    for _, addon in ipairs(self._addons) do
        addon:Destroy()
    end
    Control.Destroy(self)
end

local function initializeKeybind(target, parent, config)
    config = normalizeConfig(config)
    target._parent = parent
    target._window = parent._window
    target._library = Nephren
    target._drawings = {}
    target._regions = {}
    target._destroyed = false
    target._parentVisible = false
    target._binding = false
    target.Value = config.Default or config.Value or config.Key
    target.Mode = config.Mode or "Press"
    target.Callback = config.Callback
    target.Changed = config.Changed
    target.Flag = config.Flag
    target.State = false

    local theme = target._window.Theme
    target._text = target._window:_newDrawing("Text", {
        Text = "",
        Font = getFont(theme),
        Size = 12,
        Position = target._window.Position,
        Color = theme.MutedText,
        Outline = true,
        OutlineColor = theme.Border,
        OutlineOpacity = 1,
        ZIndex = target._window:_z(16),
        Transparency = 1,
        Visible = false,
    }, target._drawings)

    target._region = target._window:_newRegion(target, 30)
    target._region.Enabled = function()
        return target._parentVisible and not target._destroyed
    end
    target._region.OnPress = function()
        target:_startBinding()
        return false
    end
    target._region.OnHover = function(hovered)
        target._hovered = hovered
        target:_updateText()
    end

    table.insert(Nephren._keybinds, target)
    target:_updateText()
end

function KeybindAddon:_preferredWidth()
    local display = self._binding and "..." or keyName(self.Value)
    return math.max(14, math.min(52, #display * 6 + 6))
end

function KeybindAddon:_updateText()
    local theme = self._window.Theme
    local display
    if self._binding then
        display = "..."
    elseif self.Value then
        display = "[" .. keyName(self.Value) .. "]"
    else
        display = "[-]"
    end
    self._window:_set(self._text, {
        Text = display,
        Color = self._binding and theme.Accent or (self._hovered and theme.Text or theme.MutedText),
    })
end

function KeybindAddon:_layout(x, y, width)
    self._x = x
    self._y = y
    self._width = width
    self._window:_set(self._text, {
        Position = Vector2.new(x, y + 5),
    })
    setRect(self._region.Rect, x - 2, y + 3, width + 4, 15)
end

function KeybindAddon:_syncVisibility(parentVisible)
    self._parentVisible = parentVisible and not self._destroyed
    for _, drawing in ipairs(self._drawings) do
        self._window:_show(drawing, self._parentVisible)
    end
end

function KeybindAddon:_startBinding()
    self._binding = true
    self._library:_setBindingKeybind(self)
    self:_updateText()
end

function KeybindAddon:_cancelBinding()
    self._binding = false
    self:_updateText()
end

function KeybindAddon:_finishBinding(token)
    self._binding = false
    if token == Enum.KeyCode.Escape then
        self:_updateText()
        return
    end
    if token == Enum.KeyCode.Backspace or token == Enum.KeyCode.Delete then
        token = nil
    end
    self.Value = token
    self:_updateText()
    if self.Flag then
        self._window:_setFlag(self.Flag, self.Value)
    end
    safeCall(self.Changed, self.Value, self)
    if self._parent and self._parent._window then
        self._parent._window:_layout()
    end
end

function KeybindAddon:_inputBegan()
    if self.Mode == "Hold" then
        if not self.State then
            self.State = true
            if self._checkbox then
                self._checkbox:SetValue(true)
            end
            safeCall(self.Callback, true, self)
        end
    elseif self.Mode == "Toggle" then
        self.State = not self.State
        if self._checkbox then
            self._checkbox:SetValue(self.State)
        end
        safeCall(self.Callback, self.State, self)
    else
        if self._checkbox then
            self.State = not self._checkbox.Value
            self._checkbox:SetValue(self.State)
        end
        safeCall(self.Callback, self)
    end
end

function KeybindAddon:_inputEnded()
    if self.Mode == "Hold" and self.State then
        self.State = false
        if self._checkbox then
            self._checkbox:SetValue(false)
        end
        safeCall(self.Callback, false, self)
    end
end

function KeybindAddon:SetValue(value, silent)
    self.Value = value
    self:_updateText()
    if self.Flag then
        self._window:_setFlag(self.Flag, value)
    end
    if not silent then
        safeCall(self.Changed, value, self)
    end
    return self
end

KeybindAddon.Set = KeybindAddon.SetValue

function KeybindAddon:GetValue()
    return self.Value
end

function KeybindAddon:Destroy()
    if self._destroyed then
        return
    end
    self._destroyed = true
    if Nephren._bindingKeybind == self then
        Nephren._bindingKeybind = nil
    end
    self._region.Dead = true
    for _, drawing in ipairs(self._drawings) do
        self._window:_removeDrawing(drawing)
    end
    if self.Flag and self._window._flagControls[self.Flag] == self then
        self._window._flagControls[self.Flag] = nil
        self._window.Flags[self.Flag] = nil
        Nephren.Flags[self.Flag] = nil
    end
    removeFromArray(Nephren._keybinds, self)
end

KeybindAddon.Remove = KeybindAddon.Destroy

function Checkbox:AddKeybind(config)
    config = copyTable(config or {})
    if config.Mode == nil then
        config.Mode = "Toggle"
    end
    local addon = setmetatable({}, KeybindAddon)
    initializeKeybind(addon, self, config)
    addon._checkbox = self
    addon.State = self.Value
    table.insert(self._addons, addon)
    if addon.Flag then
        self._window._flagControls[addon.Flag] = addon
        self._window:_setFlag(addon.Flag, addon.Value)
    end
    self._window:_layout()
    return addon
end

local COLOR_FIELD_COLUMNS = 32
local COLOR_FIELD_ROWS = 20
local COLOR_VALUE_SEGMENTS = 32
local COLOR_PICKER_POPUP_WIDTH = 180
local COLOR_PICKER_POPUP_HEIGHT = 224

local function initializeColorPicker(target, parent, config)
    config = normalizeConfig(config)
    target._parent = parent
    target._window = parent._window
    target._library = Nephren
    target._drawings = {}
    target._popupDrawings = {}
    target._regions = {}
    target._destroyed = false
    target._parentVisible = false
    target.Open = false
    target.Value = config.Default or config.Value or target._window.Theme.Accent
    target.Callback = config.Callback
    target.Flag = config.Flag
    target.Rainbow = config.Rainbow == true
    target.RainbowSpeed = tonumber(config.RainbowSpeed) or 0.12
    target.Hue, target.Saturation, target.Brightness = toHSV(target.Value)

    local window = target._window
    local theme = window.Theme
    target._swatchOuter = window:_newDrawing("Square", {
        Filled = true,
        Color = theme.Border,
        Position = window.Position,
        Size = Vector2.new(1, 1),
        ZIndex = window:_z(15),
        Transparency = 1,
        Visible = false,
    }, target._drawings)
    target._swatchInner = newGradient(
        window,
        target._drawings,
        16,
        target.Value,
        multiplyColor(target.Value, 0.554),
        6,
        "Vertical",
        0
    )

    local function popupDraw(kind, properties)
        return window:_newDrawing(kind, properties, target._popupDrawings)
    end

    target._popupOuter = newRoundedRect(
        window,
        target._popupDrawings,
        theme.ControlBorder,
        200,
        4
    )
    target._popupStroke = newRoundedRect(
        window,
        target._popupDrawings,
        theme.InputStroke,
        201,
        2
    )
    target._popupInner = newRoundedRect(
        window,
        target._popupDrawings,
        theme.Input,
        202,
        1
    )
    target._fieldBorder = popupDraw("Square", {
        Filled = true,
        Color = theme.ControlBorder,
        Position = window.Position,
        Size = Vector2.new(1, 1),
        ZIndex = window:_z(203),
        Transparency = 1,
        Visible = false,
    })
    target._fieldTiles = {}
    for row = 1, COLOR_FIELD_ROWS do
        target._fieldTiles[row] = {}
        local saturation = 1 - (row - 1) / (COLOR_FIELD_ROWS - 1)
        for column = 1, COLOR_FIELD_COLUMNS do
            local hue = (column - 1) / (COLOR_FIELD_COLUMNS - 1)
            target._fieldTiles[row][column] = popupDraw("Square", {
                Filled = true,
                Color = fromHSV(hue, saturation, 1),
                Position = window.Position,
                Size = Vector2.new(1, 1),
                ZIndex = window:_z(205),
                Transparency = 1,
                Visible = false,
            })
        end
    end

    target._crosshairOuterH = popupDraw("Line", {
        From = window.Position,
        To = window.Position,
        Color = theme.Border,
        Thickness = 3,
        ZIndex = window:_z(208),
        Transparency = 1,
        Visible = false,
    })
    target._crosshairOuterV = popupDraw("Line", {
        From = window.Position,
        To = window.Position,
        Color = theme.Border,
        Thickness = 3,
        ZIndex = window:_z(208),
        Transparency = 1,
        Visible = false,
    })
    target._crosshairH = popupDraw("Line", {
        From = window.Position,
        To = window.Position,
        Color = theme.Text,
        Thickness = 1,
        ZIndex = window:_z(209),
        Transparency = 1,
        Visible = false,
    })
    target._crosshairV = popupDraw("Line", {
        From = window.Position,
        To = window.Position,
        Color = theme.Text,
        Thickness = 1,
        ZIndex = window:_z(209),
        Transparency = 1,
        Visible = false,
    })

    target._valueBorder = popupDraw("Square", {
        Filled = true,
        Color = theme.ControlBorder,
        Position = window.Position,
        Size = Vector2.new(1, 1),
        ZIndex = window:_z(203),
        Transparency = 1,
        Visible = false,
    })
    target._valueSegments = {}
    for segment = 1, COLOR_VALUE_SEGMENTS do
        local value = 1 - (segment - 1) / (COLOR_VALUE_SEGMENTS - 1)
        target._valueSegments[segment] = popupDraw("Square", {
            Filled = true,
            Color = Color3.new(value, value, value),
            Position = window.Position,
            Size = Vector2.new(1, 10),
            ZIndex = window:_z(205),
            Transparency = 1,
            Visible = false,
        })
    end
    target._valueMarkerOuter = popupDraw("Line", {
        From = window.Position,
        To = window.Position,
        Color = theme.Border,
        Thickness = 3,
        ZIndex = window:_z(208),
        Transparency = 1,
        Visible = false,
    })
    target._valueMarker = popupDraw("Line", {
        From = window.Position,
        To = window.Position,
        Color = theme.Text,
        Thickness = 1,
        ZIndex = window:_z(209),
        Transparency = 1,
        Visible = false,
    })

    target._rainbowOuter = newRoundedRect(
        window,
        target._popupDrawings,
        theme.ControlBorder,
        204,
        3
    )
    target._rainbowStroke = newRoundedRect(
        window,
        target._popupDrawings,
        theme.ControlStroke,
        205,
        1
    )
    target._rainbowInner = newRoundedRect(
        window,
        target._popupDrawings,
        theme.Control,
        206,
        1
    )
    target._rainbowCheck = newRoundedRect(
        window,
        target._popupDrawings,
        theme.Accent,
        207,
        1
    )
    target._rainbowText = popupDraw("Text", {
        Text = "Rainbow",
        Font = getFont(theme),
        Size = theme.TextSize,
        Position = window.Position,
        Color = theme.Text,
        Outline = true,
        OutlineColor = theme.Border,
        OutlineOpacity = 1,
        ZIndex = window:_z(207),
        Transparency = 1,
        Visible = false,
    })

    target._rgbOuter = newRoundedRect(
        window,
        target._popupDrawings,
        theme.ControlBorder,
        204,
        4
    )
    target._rgbStroke = newRoundedRect(
        window,
        target._popupDrawings,
        theme.InputStroke,
        205,
        2
    )
    target._rgbInner = newRoundedRect(
        window,
        target._popupDrawings,
        theme.Input,
        206,
        1
    )
    target._rgbText = popupDraw("Text", {
        Text = "RGB Value",
        Font = getFont(theme),
        Size = theme.TextSize,
        Position = window.Position,
        Color = theme.Text,
        Outline = true,
        OutlineColor = theme.Border,
        OutlineOpacity = 1,
        ZIndex = window:_z(207),
        Transparency = 1,
        Visible = false,
    })
    target._hexOuter = newRoundedRect(
        window,
        target._popupDrawings,
        theme.ControlBorder,
        204,
        4
    )
    target._hexStroke = newRoundedRect(
        window,
        target._popupDrawings,
        theme.InputStroke,
        205,
        2
    )
    target._hexInner = newRoundedRect(
        window,
        target._popupDrawings,
        theme.Input,
        206,
        1
    )
    target._hexText = popupDraw("Text", {
        Text = "HEX Value",
        Font = getFont(theme),
        Size = theme.TextSize,
        Position = window.Position,
        Color = theme.Text,
        Outline = true,
        OutlineColor = theme.Border,
        OutlineOpacity = 1,
        ZIndex = window:_z(207),
        Transparency = 1,
        Visible = false,
    })

    target._popupRegion = window:_newRegion(target, 210)
    target._popupRegion.PopupOwner = target
    target._popupRegion.Enabled = function()
        return target._parentVisible and target.Open and not target._destroyed
    end
    target._swatchRegion = window:_newRegion(target, 30)
    target._swatchRegion.PopupOwner = target
    target._swatchRegion.Enabled = function()
        return target._parentVisible and not target._destroyed
    end
    target._swatchRegion.OnPress = function()
        if target.Open then
            target:Close()
        else
            target:OpenPopup()
        end
        return false
    end

    target._fieldRegion = window:_newRegion(target, 230)
    target._fieldRegion.PopupOwner = target
    target._fieldRegion.Enabled = target._popupRegion.Enabled
    target._fieldRegion.OnPress = function(point)
        if target._editing then
            target:Blur(true)
        end
        target:_setFieldFromPoint(point)
        target._draggingField = true
        return true
    end
    target._fieldRegion.OnMove = function(point)
        if target._draggingField then
            target:_setFieldFromPoint(point)
        end
    end
    target._fieldRegion.OnRelease = function()
        target._draggingField = false
    end

    target._valueRegion = window:_newRegion(target, 230)
    target._valueRegion.PopupOwner = target
    target._valueRegion.Enabled = target._popupRegion.Enabled
    target._valueRegion.OnPress = function(point)
        if target._editing then
            target:Blur(true)
        end
        target:_setBrightnessFromPoint(point)
        target._draggingValue = true
        return true
    end
    target._valueRegion.OnMove = function(point)
        if target._draggingValue then
            target:_setBrightnessFromPoint(point)
        end
    end
    target._valueRegion.OnRelease = function()
        target._draggingValue = false
    end

    target._rainbowRegion = window:_newRegion(target, 230)
    target._rainbowRegion.PopupOwner = target
    target._rainbowRegion.Enabled = target._popupRegion.Enabled
    target._rainbowRegion.OnPress = function()
        if target._editing then
            target:Blur(true)
        end
        target:SetRainbow(not target.Rainbow)
        return false
    end

    target._rgbRegion = window:_newRegion(target, 230)
    target._rgbRegion.PopupOwner = target
    target._rgbRegion.Enabled = target._popupRegion.Enabled
    target._rgbRegion.OnPress = function()
        target:_focusField("RGB")
        return false
    end
    target._hexRegion = window:_newRegion(target, 230)
    target._hexRegion.PopupOwner = target
    target._hexRegion.Enabled = target._popupRegion.Enabled
    target._hexRegion.OnPress = function()
        target:_focusField("HEX")
        return false
    end

    for _, region in ipairs({
        target._popupRegion,
        target._swatchRegion,
        target._fieldRegion,
        target._valueRegion,
        target._rainbowRegion,
        target._rgbRegion,
        target._hexRegion,
    }) do
        table.insert(target._regions, region)
    end
    table.insert(Nephren._rainbowPickers, target)
    target:_updateVisual()
end

function ColorPickerAddon:_preferredWidth()
    return 18
end

function ColorPickerAddon:_rgbString()
    return string.format(
        "%d, %d, %d",
        round(self.Value.R * 255),
        round(self.Value.G * 255),
        round(self.Value.B * 255)
    )
end

function ColorPickerAddon:_hexString()
    return string.format(
        "#%02X%02X%02X",
        round(self.Value.R * 255),
        round(self.Value.G * 255),
        round(self.Value.B * 255)
    )
end

function ColorPickerAddon:_updateReadouts()
    local theme = self._window.Theme
    self._window:_set(self._rgbText, {
        Text = self._editing == "RGB" and self._editText or "RGB Value",
        Color = self._editing == "RGB" and theme.Accent or theme.Text,
    })
    self._window:_set(self._hexText, {
        Text = self._editing == "HEX" and self._editText or "HEX Value",
        Color = self._editing == "HEX" and theme.Accent or theme.Text,
    })
    self._window:_set(self._rgbInner, {
        Color = self._editing == "RGB" and theme.ControlActive or theme.Input,
    })
    self._window:_set(self._hexInner, {
        Color = self._editing == "HEX" and theme.ControlActive or theme.Input,
    })
end

function ColorPickerAddon:_updateVisual()
    local window = self._window
    local theme = window.Theme
    window:_set(self._swatchInner, {
        StartColor = self.Value,
        EndColor = multiplyColor(self.Value, 0.554),
    })
    window:_set(self._rainbowInner, {
        Color = self.Rainbow and theme.AccentDark or theme.Control,
    })
    window:_show(self._rainbowCheck, self._parentVisible and self.Open and self.Rainbow)

    if self._fieldX then
        local crossX = self._fieldX + self.Hue * self._fieldWidth
        local crossY = self._fieldY + (1 - self.Saturation) * self._fieldHeight
        local horizontal = {
            From = Vector2.new(crossX - 5, crossY),
            To = Vector2.new(crossX + 5, crossY),
        }
        local vertical = {
            From = Vector2.new(crossX, crossY - 5),
            To = Vector2.new(crossX, crossY + 5),
        }
        window:_set(self._crosshairOuterH, horizontal)
        window:_set(self._crosshairH, horizontal)
        window:_set(self._crosshairOuterV, vertical)
        window:_set(self._crosshairV, vertical)

        local markerX = self._valueX + (1 - self.Brightness) * self._valueWidth
        local marker = {
            From = Vector2.new(markerX, self._valueY - 2),
            To = Vector2.new(markerX, self._valueY + 11),
        }
        window:_set(self._valueMarkerOuter, marker)
        window:_set(self._valueMarker, marker)
    end
    self:_updateReadouts()
end

function ColorPickerAddon:_commitColor(silent)
    self.Value = fromHSV(self.Hue, self.Saturation, self.Brightness)
    self:_updateVisual()
    if self.Flag then
        self._window:_setFlag(self.Flag, self.Value)
    end
    if not silent then
        safeCall(self.Callback, self.Value, self)
    end
end

function ColorPickerAddon:_setFieldFromPoint(point)
    self.Hue = clamp((point.X - self._fieldX) / self._fieldWidth, 0, 1)
    self.Saturation = 1 - clamp((point.Y - self._fieldY) / self._fieldHeight, 0, 1)
    self:_commitColor(false)
end

function ColorPickerAddon:_setBrightnessFromPoint(point)
    self.Brightness = 1 - clamp((point.X - self._valueX) / self._valueWidth, 0, 1)
    self:_commitColor(false)
end

function ColorPickerAddon:_layout(x, y)
    local window = self._window
    local theme = window.Theme
    self._x = x
    self._y = y
    window:_set(self._swatchOuter, {
        Position = Vector2.new(x, y + 7),
        Size = Vector2.new(18, 8),
    })
    window:_set(self._swatchInner, {
        Position = Vector2.new(x + 1, y + 8),
        Size = Vector2.new(16, 6),
    })
    setRect(self._swatchRegion.Rect, x - 2, y + 3, 22, 15)

    local popupX = x + self:_preferredWidth() + 5 - COLOR_PICKER_POPUP_WIDTH
    local popupY = y + 19
    self._popupX = popupX
    self._popupY = popupY
    self._fieldX = popupX + 11
    self._fieldY = popupY + 13
    self._fieldWidth = 160
    self._fieldHeight = 100
    self._valueX = popupX + 12
    self._valueY = popupY + 120
    self._valueWidth = 160

    window:_set(self._popupOuter, {
        Position = Vector2.new(popupX, popupY),
        Size = Vector2.new(COLOR_PICKER_POPUP_WIDTH, COLOR_PICKER_POPUP_HEIGHT),
    })
    window:_set(self._popupStroke, {
        Position = Vector2.new(popupX + 1, popupY + 1),
        Size = Vector2.new(178, 222),
    })
    window:_set(self._popupInner, {
        Position = Vector2.new(popupX + 2, popupY + 2),
        Size = Vector2.new(176, 220),
    })
    window:_set(self._fieldBorder, {
        Position = Vector2.new(self._fieldX - 1, self._fieldY - 1),
        Size = Vector2.new(162, 102),
    })

    local tileWidth = self._fieldWidth / COLOR_FIELD_COLUMNS
    local tileHeight = self._fieldHeight / COLOR_FIELD_ROWS
    for row = 1, COLOR_FIELD_ROWS do
        for column = 1, COLOR_FIELD_COLUMNS do
            window:_set(self._fieldTiles[row][column], {
                Position = Vector2.new(
                    self._fieldX + (column - 1) * tileWidth,
                    self._fieldY + (row - 1) * tileHeight
                ),
                Size = Vector2.new(math.ceil(tileWidth), math.ceil(tileHeight)),
            })
        end
    end

    window:_set(self._valueBorder, {
        Position = Vector2.new(self._valueX - 1, self._valueY - 1),
        Size = Vector2.new(162, 11),
    })
    local valueWidth = self._valueWidth / COLOR_VALUE_SEGMENTS
    for segment = 1, COLOR_VALUE_SEGMENTS do
        window:_set(self._valueSegments[segment], {
            Position = Vector2.new(self._valueX + (segment - 1) * valueWidth, self._valueY),
            Size = Vector2.new(math.ceil(valueWidth), 9),
        })
    end

    window:_set(self._rainbowOuter, {
        Position = Vector2.new(popupX + 10, popupY + 136),
        Size = Vector2.new(14, 14),
    })
    window:_set(self._rainbowStroke, {
        Position = Vector2.new(popupX + 11, popupY + 137),
        Size = Vector2.new(12, 12),
    })
    window:_set(self._rainbowInner, {
        Position = Vector2.new(popupX + 12, popupY + 138),
        Size = Vector2.new(10, 10),
    })
    window:_set(self._rainbowCheck, {
        Position = Vector2.new(popupX + 13, popupY + 139),
        Size = Vector2.new(8, 8),
    })
    window:_set(self._rainbowText, {
        Position = Vector2.new(
            popupX + 31,
            centeredTextY(popupY + 137, 14, theme.TextSize)
        ),
    })
    window:_set(self._rgbOuter, {
        Position = Vector2.new(popupX + 10, popupY + 158),
        Size = Vector2.new(162, 27),
    })
    window:_set(self._rgbStroke, {
        Position = Vector2.new(popupX + 11, popupY + 159),
        Size = Vector2.new(160, 25),
    })
    window:_set(self._rgbInner, {
        Position = Vector2.new(popupX + 12, popupY + 160),
        Size = Vector2.new(158, 23),
    })
    window:_set(self._rgbText, {
        Position = Vector2.new(
            popupX + 21,
            centeredTextY(popupY + 160, 23, theme.TextSize)
        ),
    })
    window:_set(self._hexOuter, {
        Position = Vector2.new(popupX + 10, popupY + 190),
        Size = Vector2.new(162, 27),
    })
    window:_set(self._hexStroke, {
        Position = Vector2.new(popupX + 11, popupY + 191),
        Size = Vector2.new(160, 25),
    })
    window:_set(self._hexInner, {
        Position = Vector2.new(popupX + 12, popupY + 192),
        Size = Vector2.new(158, 23),
    })
    window:_set(self._hexText, {
        Position = Vector2.new(
            popupX + 21,
            centeredTextY(popupY + 192, 23, theme.TextSize)
        ),
    })

    setRect(
        self._popupRegion.Rect,
        popupX,
        popupY,
        COLOR_PICKER_POPUP_WIDTH,
        COLOR_PICKER_POPUP_HEIGHT
    )
    setRect(self._fieldRegion.Rect, self._fieldX, self._fieldY, 160, 100)
    setRect(self._valueRegion.Rect, self._valueX, self._valueY - 1, 160, 11)
    setRect(self._rainbowRegion.Rect, popupX + 2, popupY + 131, 168, 21)
    setRect(self._rgbRegion.Rect, popupX + 10, popupY + 158, 162, 27)
    setRect(self._hexRegion.Rect, popupX + 10, popupY + 190, 162, 27)
    self:_updateVisual()
end

function ColorPickerAddon:_syncVisibility(parentVisible)
    self._parentVisible = parentVisible and not self._destroyed
    for _, drawing in ipairs(self._drawings) do
        self._window:_show(drawing, self._parentVisible)
    end
    for _, drawing in ipairs(self._popupDrawings) do
        self._window:_show(drawing, self._parentVisible and self.Open)
    end
    self._window:_show(
        self._rainbowCheck,
        self._parentVisible and self.Open and self.Rainbow
    )
    if not self._parentVisible and self.Open then
        self:Close()
    end
end

function ColorPickerAddon:OpenPopup()
    if self._destroyed or not self._parentVisible then
        return self
    end
    if self._window._openPopup and self._window._openPopup ~= self then
        self._window._openPopup:Close()
    end
    self.Open = true
    self._window._openPopup = self
    self:_syncVisibility(true)
    self:_updateVisual()
    return self
end

function ColorPickerAddon:Close()
    if self._editing then
        self:Blur(true)
    end
    self.Open = false
    if self._window._openPopup == self then
        self._window._openPopup = nil
    end
    for _, drawing in ipairs(self._popupDrawings) do
        self._window:_show(drawing, false)
    end
    return self
end

function ColorPickerAddon:SetRainbow(enabled)
    self.Rainbow = enabled and true or false
    self:_updateVisual()
    return self
end

function ColorPickerAddon:_rainbowStep(deltaTime)
    if not self.Rainbow or self._destroyed then
        return
    end
    self.Hue = (self.Hue + deltaTime * self.RainbowSpeed) % 1
    self:_commitColor(false)
end

function ColorPickerAddon:_focusField(kind)
    if self._editing == kind then
        return
    end
    if self._editing and self._editing ~= kind then
        self:Blur(true)
    end
    self._editing = kind
    self._editText = kind == "RGB" and self:_rgbString() or self:_hexString()
    self._library:_setFocusedTextbox(self)
    self:_updateReadouts()
end

function ColorPickerAddon:_parseEdit()
    if self._editing == "RGB" then
        local values = {}
        for number in string.gmatch(self._editText, "%d+") do
            table.insert(values, tonumber(number))
        end
        if #values == 3 then
            return Color3.fromRGB(
                clamp(values[1], 0, 255),
                clamp(values[2], 0, 255),
                clamp(values[3], 0, 255)
            )
        end
    elseif self._editing == "HEX" then
        local text = string.gsub(self._editText, "#", "")
        if #text == 3 then
            text = string.sub(text, 1, 1) .. string.sub(text, 1, 1)
                .. string.sub(text, 2, 2) .. string.sub(text, 2, 2)
                .. string.sub(text, 3, 3) .. string.sub(text, 3, 3)
        end
        if #text == 6 and string.match(text, "^[%da-fA-F]+$") then
            return Color3.fromRGB(
                tonumber(string.sub(text, 1, 2), 16),
                tonumber(string.sub(text, 3, 4), 16),
                tonumber(string.sub(text, 5, 6), 16)
            )
        end
    end
    return nil
end

function ColorPickerAddon:_onKey(keyCode)
    if keyCode == Enum.KeyCode.Return or keyCode == Enum.KeyCode.KeypadEnter then
        self:Blur(true)
        return
    elseif keyCode == Enum.KeyCode.Escape then
        self:Blur(false)
        return
    elseif isDeleteKey(keyCode) then
        self._editText = string.sub(self._editText, 1, math.max(0, #self._editText - 1))
        self:_updateReadouts()
        return
    end

    local character = inputCharacter(self._library, keyCode)
    if not character then
        return
    end
    local allowed
    if self._editing == "RGB" then
        allowed = string.match(character, "[%d, ]") ~= nil
    else
        allowed = string.match(character, "[%da-fA-F#]") ~= nil
    end
    if allowed and #self._editText < 18 then
        self._editText = self._editText .. character
        self:_updateReadouts()
    end
end

function ColorPickerAddon:Blur(commit)
    if not self._editing then
        return self
    end
    self._library:_stopDeleteRepeat(self)
    if commit then
        local color = self:_parseEdit()
        if color then
            self:SetValue(color)
        end
    end
    self._editing = nil
    self._editText = nil
    if self._library._focusedTextbox == self then
        self._library._focusedTextbox = nil
    end
    self:_updateReadouts()
    return self
end

function ColorPickerAddon:SetValue(value, silent)
    self.Value = value
    self.Hue, self.Saturation, self.Brightness = toHSV(value)
    self:_updateVisual()
    if self.Flag then
        self._window:_setFlag(self.Flag, value)
    end
    if not silent then
        safeCall(self.Callback, value, self)
    end
    return self
end

ColorPickerAddon.Set = ColorPickerAddon.SetValue

function ColorPickerAddon:GetValue()
    return self.Value
end

function ColorPickerAddon:Destroy()
    if self._destroyed then
        return
    end
    self:Close()
    self._destroyed = true
    for _, region in ipairs(self._regions) do
        region.Dead = true
    end
    for _, drawing in ipairs(self._drawings) do
        self._window:_removeDrawing(drawing)
    end
    for _, drawing in ipairs(self._popupDrawings) do
        self._window:_removeDrawing(drawing)
    end
    if self.Flag and self._window._flagControls[self.Flag] == self then
        self._window._flagControls[self.Flag] = nil
        self._window.Flags[self.Flag] = nil
        Nephren.Flags[self.Flag] = nil
    end
    removeFromArray(Nephren._rainbowPickers, self)
end

ColorPickerAddon.Remove = ColorPickerAddon.Destroy

function Checkbox:AddColorPicker(config)
    local addon = setmetatable({}, ColorPickerAddon)
    initializeColorPicker(addon, self, config)
    table.insert(self._addons, addon)
    if addon.Flag then
        self._window._flagControls[addon.Flag] = addon
        self._window:_setFlag(addon.Flag, addon.Value)
    end
    self._window:_layout()
    return addon
end

local function newSlider(section, config)
    config = normalizeConfig(config)
    local self = setmetatable({}, Slider)
    Control._init(self, section, config, config.Height or 33)

    self.Minimum = tonumber(config.Min or config.Minimum) or 0
    self.Maximum = tonumber(config.Max or config.Maximum) or 100
    if self.Maximum < self.Minimum then
        self.Minimum, self.Maximum = self.Maximum, self.Minimum
    end
    self.Step = tonumber(config.Step or config.Increment) or 1
    self.Prefix = tostring(config.Prefix or "")
    self.Suffix = tostring(config.Suffix or "")
    self.Value = clamp(
        snap(tonumber(config.Default or config.Value) or self.Minimum, self.Minimum, self.Step),
        self.Minimum,
        self.Maximum
    )

    local theme = self._window.Theme
    self._label = createLabelDrawing(self, self.Text, 14)
    self._trackOuter = newRoundedRect(
        self._window,
        self._drawings,
        theme.ControlBorder,
        10,
        6
    )
    self._trackInner = newRoundedRect(
        self._window,
        self._drawings,
        theme.ControlStroke,
        11,
        3
    )
    self._trackBackground = newRoundedRect(
        self._window,
        self._drawings,
        theme.SliderTrack,
        12,
        2
    )
    self._fill = newGradient(
        self._window,
        self._drawings,
        13,
        theme.Accent,
        theme.AccentEnd,
        32,
        "Horizontal",
        2
    )
    self._valueText = createLabelDrawing(self, "", 14)
    self._window:_set(self._valueText, {
        Center = true,
        Size = 14,
    })

    self._region = self:_region(20)
    self._region.OnPress = function(point)
        self._sliding = true
        self:_setFromPoint(point)
        return true
    end
    self._region.OnMove = function(point)
        if self._sliding then
            self:_setFromPoint(point)
        end
    end
    self._region.OnRelease = function()
        self._sliding = false
    end
    self._region.OnHover = function(hovered)
        self._hovered = hovered
        self._window:_set(self._trackInner, {
            Color = theme.ControlStroke,
        })
    end
    self:_updateVisual()

    return section:_add(self)
end

function Slider:_ratio()
    local range = self.Maximum - self.Minimum
    if range <= 0 then
        return 0
    end
    return clamp((self.Value - self.Minimum) / range, 0, 1)
end

function Slider:_displayValue()
    local raw = formatNumber(self.Value, self.Step)
    if type(self._config.Format) == "function" then
        local ok, formatted = pcall(self._config.Format, self.Value)
        if ok and formatted ~= nil then
            return tostring(formatted)
        end
    end
    return self.Prefix .. raw .. self.Suffix
end

function Slider:_updateVisual()
    if not self._x then
        return
    end
    local theme = self._window.Theme
    local ratio = self:_ratio()
    local innerWidth = math.max(0, self._width - 4)
    local fillWidth = math.floor(innerWidth * ratio + 0.5)
    local fillX = self._x + 2
    local display = self:_displayValue()
    local textWidth = math.max(6, #display * (14 * 0.52))
    local valueX = clamp(
        fillX + fillWidth - 3,
        self._x + textWidth * 0.5,
        self._x + self._width - textWidth * 0.5
    )

    self._window:_set(self._fill, {
        Position = Vector2.new(fillX, self._y + 15),
        Size = Vector2.new(fillWidth, 4),
    })
    self._window:_show(self._fill, self._parentVisible and fillWidth > 0)
    self._window:_set(self._valueText, {
        Text = display,
        Position = Vector2.new(
            valueX,
            centeredTextY(self._y + 21, 12, 14)
        ),
    })
end

function Slider:_setFromPoint(point)
    local innerWidth = math.max(1, self._width - 4)
    local ratio = clamp((point.X - (self._x + 2)) / innerWidth, 0, 1)
    self:SetValue(self.Minimum + (self.Maximum - self.Minimum) * ratio)
end

function Slider:_layout(x, y, width)
    self._x = x
    self._y = y
    self._width = width
    self._window:_set(self._label, {
        Text = self.Text,
        Position = Vector2.new(
            x,
            centeredTextY(y, 10, self._window.Theme.TextSize)
        ),
    })
    self._window:_set(self._trackOuter, {
        Position = Vector2.new(x, y + 13),
        Size = Vector2.new(width, 8),
    })
    self._window:_set(self._trackInner, {
        Position = Vector2.new(x + 1, y + 14),
        Size = Vector2.new(width - 2, 6),
    })
    self._window:_set(self._trackBackground, {
        Position = Vector2.new(x + 2, y + 15),
        Size = Vector2.new(width - 4, 4),
    })
    setRect(self._region.Rect, x, y + 12, width, 14)
    self:_updateVisual()
end

function Slider:_syncVisibility(parentVisible)
    Control._syncVisibility(self, parentVisible)
    self:_updateVisual()
end

function Slider:SetValue(value, silent)
    value = tonumber(value) or self.Minimum
    self.Value = clamp(snap(value, self.Minimum, self.Step), self.Minimum, self.Maximum)
    self:_updateVisual()
    self:_changed(self.Value, silent)
    return self
end

Slider.Set = Slider.SetValue

local function initializeDropdown(self, section, config, isMulti)
    Control._init(self, section, config, config.Height or (isMulti and 57 or 60))
    self.Values = arrayCopy(config.Values or config.Options or {})
    self.Placeholder = tostring(config.Placeholder or self.Text)
    self.PopupHeight = math.max(42, math.floor(config.PopupHeight or config.DropdownHeight or 110))
    self.MaxVisible = math.max(
        1,
        math.floor(config.MaxVisible or ((self.PopupHeight - 2) / 20))
    )
    self.Open = false
    self.ScrollOffset = 1
    self._isMulti = isMulti
    self._popupDrawings = {}
    self._optionRows = {}

    if isMulti then
        self.Selected = setCopy(config.Default or config.Value or {})
        self.Value = nil
    else
        local default = config.Default
        if default == nil then
            default = config.Value
        end
        self.Value = default
    end

    local window = self._window
    local theme = window.Theme
    self._label = createLabelDrawing(self, self.Text, 14)
    self._outer, self._inner, self._highlight = createBox(self, 10)
    local activeGradientDark, activeGradientLight =
        activeAccentGradient(theme)
    self._activeGradient = newGradient(
        window,
        self._drawings,
        13,
        activeGradientDark,
        activeGradientLight,
        32,
        "Horizontal",
        0
    )
    self._activeGradientCorners = {}
    for _ = 1, 4 do
        table.insert(self._activeGradientCorners, self:_draw("Square", {
            Filled = true,
            Color = theme.ControlStroke,
            Position = window.Position,
            Size = Vector2.new(1, 1),
            ZIndex = window:_z(14),
            Transparency = 1,
            Visible = false,
        }))
    end
    self._glyph = nil
    self._glyphLines = {}
    self._glyphOutlineLines = {}

    if isMulti then
        for _ = 1, 3 do
            table.insert(self._glyphOutlineLines, self:_draw("Line", {
                From = window.Position,
                To = window.Position,
                Color = theme.ControlBorder,
                Thickness = 3,
                ZIndex = window:_z(14),
                Transparency = 1,
                Visible = false,
            }))
            table.insert(self._glyphLines, self:_draw("Line", {
                From = window.Position,
                To = window.Position,
                Color = theme.MenuIcon,
                Thickness = 1,
                ZIndex = window:_z(15),
                Transparency = 1,
                Visible = false,
            }))
        end
    else
        self._glyph = createLabelDrawing(self, "v", 14)
        window:_set(self._glyph, {
            Size = theme.TextSize,
            Color = theme.MutedText,
        })
    end

    self._valueText = createLabelDrawing(self, "", 14)

    local function popupDraw(kind, properties)
        return window:_newDrawing(kind, properties, self._popupDrawings)
    end

    self._popupOuter = newRoundedRect(
        window,
        self._popupDrawings,
        theme.Border,
        200,
        4
    )
    self._popupStroke = newRoundedRect(
        window,
        self._popupDrawings,
        theme.ControlStroke,
        201,
        2
    )
    self._popupInner = newRoundedRect(
        window,
        self._popupDrawings,
        theme.Control,
        202,
        1
    )

    self._region = self:_region(20)
    self._region.PopupOwner = self
    self._region.OnPress = function()
        if self.Open then
            self:Close()
        else
            self:OpenPopup()
        end
        return false
    end
    self._region.OnHover = function(hovered)
        self._hovered = hovered
        self:_updateStyle()
    end

    self._popupRegion = window:_newRegion(self, 210)
    self._popupRegion.PopupOwner = self
    self._popupRegion.Enabled = function()
        return self._parentVisible and self.Open and not self._destroyed
    end
    self._popupRegion.OnWheel = function(delta)
        self:_scroll(delta)
    end
    table.insert(self._regions, self._popupRegion)

    for rowIndex = 1, self.MaxVisible do
        local row = {}
        row.Background = popupDraw("Square", {
            Filled = true,
            Color = theme.Control,
            Position = window.Position,
            Size = Vector2.new(1, 1),
            ZIndex = window:_z(204),
            Transparency = 1,
            Visible = false,
        })
        row.Text = popupDraw("Text", {
            Text = "",
            Font = getFont(theme),
            Size = theme.TextSize,
            Position = window.Position,
            Color = theme.Text,
            Outline = true,
            OutlineColor = theme.Border,
            OutlineOpacity = 1,
            ZIndex = window:_z(206),
            Transparency = 1,
            Visible = false,
        })
        row.Mark = popupDraw("Text", {
            Text = "",
            Font = getFont(theme),
            Size = theme.TextSize - 2,
            Position = window.Position,
            Color = theme.Accent,
            Outline = true,
            OutlineColor = theme.Border,
            OutlineOpacity = 1,
            ZIndex = window:_z(207),
            Transparency = 1,
            Visible = false,
        })
        row.Region = window:_newRegion(self, 220)
        row.Region.PopupOwner = self
        row.Region.Enabled = function()
            return self._parentVisible and self.Open and not self._destroyed and row.Value ~= nil
        end
        row.Region.OnPress = function()
            if row.Value ~= nil then
                self:_selectOption(row.Value)
            end
            return false
        end
        row.Region.OnHover = function(hovered)
            row.Hovered = hovered
            self:_updatePopupRows()
        end
        row.Region.OnWheel = function(delta)
            self:_scroll(delta)
        end
        table.insert(self._regions, row.Region)
        table.insert(self._optionRows, row)
    end

    self:_updateDisplay()
end

local function newDropdown(section, config)
    config = normalizeConfig(config)
    local self = setmetatable({}, Dropdown)
    initializeDropdown(self, section, config, false)
    return section:_add(self)
end

local function newMultiDropdown(section, config)
    config = normalizeConfig(config)
    local self = setmetatable({}, MultiDropdown)
    initializeDropdown(self, section, config, true)
    return section:_add(self)
end

function Dropdown:_selected(value)
    if self._isMulti then
        return self.Selected[value] == true
    end
    return self.Value == value
end

function Dropdown:_displayText()
    if not self._isMulti then
        if self.Value == nil then
            return self.Placeholder
        end
        return tostring(self.Value)
    end

    local selected = {}
    for _, value in ipairs(self.Values) do
        if self.Selected[value] then
            table.insert(selected, tostring(value))
        end
    end
    if #selected == 0 then
        return self.Placeholder
    end
    return table.concat(selected, ", ")
end

function Dropdown:_updateDisplay()
    local width = self._width or self._window.Theme.ControlWidth
    self._window:_set(self._valueText, {
        Text = truncate(self:_displayText(), width - 29, self._window.Theme.TextSize),
    })
end

function Dropdown:_updateStyle()
    local theme = self._window.Theme
    local color = theme.Control
    if self.Open and not self._isMulti then
        color = theme.ControlActive
    elseif self._hovered then
        color = theme.ControlHover
    end
    self._window:_set(self._inner, { Color = color })

    if self._activeGradient then
        local activeGradientDark, activeGradientLight =
            activeAccentGradient(theme)
        local activeGradientVisible = self._parentVisible and self.Open
        self._window:_set(self._activeGradient, {
            StartColor = activeGradientDark,
            EndColor = activeGradientLight,
        })
        self._window:_show(self._activeGradient, activeGradientVisible)
        for _, corner in ipairs(self._activeGradientCorners) do
            self._window:_set(corner, { Color = theme.ControlStroke })
            self._window:_show(corner, activeGradientVisible)
        end
    end

    if self._glyph then
        self._window:_set(self._glyph, {
            Color = self.Open and theme.Accent or theme.MutedText,
        })
    else
        for _, line in ipairs(self._glyphLines) do
            self._window:_set(line, { Color = theme.MenuIcon })
        end
    end

    self._window:_set(self._valueText, {
        Color = theme.Text,
    })
end

function Dropdown:_visibleRowCount()
    return math.min(#self.Values, self.MaxVisible)
end

function Dropdown:_maxOffset()
    return math.max(1, #self.Values - self:_visibleRowCount() + 1)
end

function Dropdown:_scroll(delta)
    if #self.Values <= self.MaxVisible then
        return
    end
    if delta > 0 then
        self.ScrollOffset = self.ScrollOffset - 1
    elseif delta < 0 then
        self.ScrollOffset = self.ScrollOffset + 1
    end
    self.ScrollOffset = clamp(self.ScrollOffset, 1, self:_maxOffset())
    self:_updatePopupRows()
end

function Dropdown:_updatePopupRows()
    local window = self._window
    local theme = window.Theme
    local visibleRows = self:_visibleRowCount()

    for rowIndex, row in ipairs(self._optionRows) do
        local valueIndex = self.ScrollOffset + rowIndex - 1
        local value = rowIndex <= visibleRows and self.Values[valueIndex] or nil
        row.Value = value
        local visible = self._parentVisible and self.Open and value ~= nil
        local selected = value ~= nil and self:_selected(value)
        window:_show(row.Background, visible)
        window:_show(row.Text, visible)
        window:_show(row.Mark, visible and self._isMulti)
        if value ~= nil then
            window:_set(row.Background, {
                Color = selected and theme.Selection
                    or (row.Hovered and theme.ControlHover or theme.Control),
            })
            window:_set(row.Text, {
                Text = truncate(tostring(value), (self._width or 100) - 26, theme.TextSize),
                Color = selected and theme.Accent or theme.Text,
            })
            window:_set(row.Mark, {
                Text = selected and "x" or "",
            })
        end
    end
end

function Dropdown:_layoutPopup()
    if not self._x then
        return
    end
    local window = self._window
    local height = self.PopupHeight
    local x = self._x
    local y = self._y + 48
    local width = self._width

    window:_set(self._popupOuter, {
        Position = Vector2.new(x, y),
        Size = Vector2.new(width, height),
    })
    window:_set(self._popupStroke, {
        Position = Vector2.new(x + 1, y + 1),
        Size = Vector2.new(width - 2, height - 2),
    })
    window:_set(self._popupInner, {
        Position = Vector2.new(x + 2, y + 2),
        Size = Vector2.new(width - 4, height - 4),
    })
    setRect(self._popupRegion.Rect, x, y, width, height)

    for rowIndex, row in ipairs(self._optionRows) do
        local rowY = y + 2 + (rowIndex - 1) * 20
        window:_set(row.Background, {
            Position = Vector2.new(x + 2, rowY),
            Size = Vector2.new(width - 4, 20),
        })
        window:_set(row.Text, {
            Position = Vector2.new(
                x + 8,
                centeredTextY(rowY, 25, window.Theme.TextSize)
            ),
        })
        window:_set(row.Mark, {
            Position = Vector2.new(
                x + width - 14,
                centeredTextY(rowY, 25, window.Theme.TextSize - 2)
            ),
        })
        setRect(row.Region.Rect, x + 2, rowY, width - 4, 20)
    end
    self:_updatePopupRows()
end

function Dropdown:_layout(x, y, width)
    local actualWidth = width + 2
    self._x = x
    self._y = y
    self._width = actualWidth
    self._window:_set(self._label, {
        Text = self.Text,
        Position = Vector2.new(
            x,
            centeredTextY(y + 6, 10, self._window.Theme.TextSize)
        ),
    })
    layoutBox(
        self._window,
        self._outer,
        self._inner,
        self._highlight,
        x,
        y + 20,
        actualWidth,
        27
    )
    self._window:_set(self._valueText, {
        Position = Vector2.new(
            x + 10,
            centeredTextY(y + 30, 10, self._window.Theme.TextSize)
        ),
    })
    self._window:_set(self._activeGradient, {
        Position = Vector2.new(x + 2, y + 22),
        Size = Vector2.new(actualWidth - 4, 23),
    })
    local gradientRight = x + actualWidth - 3
    local gradientBottom = y + 44
    local cornerPositions = {
        Vector2.new(x + 2, y + 22),
        Vector2.new(gradientRight, y + 22),
        Vector2.new(x + 2, gradientBottom),
        Vector2.new(gradientRight, gradientBottom),
    }
    for index, position in ipairs(cornerPositions) do
        self._window:_set(self._activeGradientCorners[index], {
            Position = position,
        })
    end
    if self._glyph then
        self._window:_set(self._glyph, {
            Position = Vector2.new(
                x + actualWidth - 13,
                centeredTextY(y + 27, 10, self._window.Theme.TextSize)
            ),
        })
    else
        local lineX = x + actualWidth - 16
        for index = 1, 3 do
            local lineY = y + 31 + (index - 1) * 2
            local properties = {
                From = Vector2.new(lineX, lineY),
                To = Vector2.new(lineX + 5, lineY),
            }
            self._window:_set(self._glyphOutlineLines[index], properties)
            self._window:_set(self._glyphLines[index], properties)
        end
    end
    setRect(self._region.Rect, x, y + 20, actualWidth, 27)
    self:_updateDisplay()
    self:_layoutPopup()
    self:_updateStyle()
end

function Dropdown:_syncVisibility(parentVisible)
    Control._syncVisibility(self, parentVisible)
    for _, drawing in ipairs(self._popupDrawings) do
        self._window:_show(drawing, self._parentVisible and self.Open)
    end
    if not self._parentVisible and self.Open then
        self:Close()
    end
    self:_updatePopupRows()
    self:_updateStyle()
end

function Dropdown:OpenPopup()
    if self._destroyed or not self._parentVisible then
        return self
    end
    if self._window._openPopup and self._window._openPopup ~= self then
        self._window._openPopup:Close()
    end
    self.Open = true
    self._window._openPopup = self
    self:_layoutPopup()
    self:_syncVisibility(true)
    self:_updateStyle()
    return self
end

function Dropdown:Close()
    self.Open = false
    if self._window._openPopup == self then
        self._window._openPopup = nil
    end
    for _, drawing in ipairs(self._popupDrawings) do
        self._window:_show(drawing, false)
    end
    self:_updateStyle()
    return self
end

function Dropdown:_selectOption(value)
    self:SetValue(value)
    self:Close()
end

function Dropdown:SetValue(value, silent)
    if value ~= nil and not valueExists(self.Values, value) and not self._config.AllowUnknown then
        return self
    end
    self.Value = value
    self:_updateDisplay()
    self:_updatePopupRows()
    self:_changed(self.Value, silent)
    return self
end

Dropdown.Set = Dropdown.SetValue

function Dropdown:SetValues(values, preserveValue)
    self.Values = arrayCopy(values)
    self.ScrollOffset = 1
    if not preserveValue and self.Value ~= nil and not valueExists(self.Values, self.Value) then
        self.Value = nil
    end
    self:_updateDisplay()
    self:_layoutPopup()
    return self
end

Dropdown.SetOptions = Dropdown.SetValues

function Dropdown:Destroy()
    if self._destroyed then
        return
    end
    self:Close()
    for _, drawing in ipairs(self._popupDrawings) do
        self._window:_removeDrawing(drawing)
    end
    Control.Destroy(self)
end

function MultiDropdown:_selectedValues()
    local result = {}
    for _, value in ipairs(self.Values) do
        if self.Selected[value] then
            table.insert(result, value)
        end
    end
    return result
end

function MultiDropdown:GetValue()
    return self:_selectedValues()
end

function MultiDropdown:_selectOption(value)
    self.Selected[value] = not self.Selected[value]
    self:_updateDisplay()
    self:_updatePopupRows()
    self:_changed(self:_selectedValues(), false)
end

function MultiDropdown:SetValue(values, silent)
    self.Selected = setCopy(values)
    if not self._config.AllowUnknown then
        for value in pairs(self.Selected) do
            if not valueExists(self.Values, value) then
                self.Selected[value] = nil
            end
        end
    end
    self:_updateDisplay()
    self:_updatePopupRows()
    self:_changed(self:_selectedValues(), silent)
    return self
end

MultiDropdown.Set = MultiDropdown.SetValue

function MultiDropdown:SetValues(values, preserveValue)
    local previous = self.Selected
    self.Values = arrayCopy(values)
    self.ScrollOffset = 1
    if preserveValue then
        self.Selected = previous
    else
        for value in pairs(self.Selected) do
            if not valueExists(self.Values, value) then
                self.Selected[value] = nil
            end
        end
    end
    self:_updateDisplay()
    self:_layoutPopup()
    return self
end

MultiDropdown.SetOptions = MultiDropdown.SetValues

local function newSpinner(section, config)
    config = normalizeConfig(config)
    local self = setmetatable({}, Spinner)
    Control._init(self, section, config, config.Height or 51)

    self.Minimum = tonumber(config.Min or config.Minimum) or -math.huge
    self.Maximum = tonumber(config.Max or config.Maximum) or math.huge
    self.Step = tonumber(config.Step or config.Increment) or 1
    self.SnapBase = self.Minimum == -math.huge and 0 or self.Minimum
    self.Value = clamp(
        snap(tonumber(config.Default or config.Value) or 0, self.SnapBase, self.Step),
        self.Minimum,
        self.Maximum
    )

    local theme = self._window.Theme
    self._label = createLabelDrawing(self, self.Text, 14)
    self._valueOuter, self._valueInner, self._valueHighlight = createBox(
        self,
        10,
        theme.Input,
        4,
        1,
        theme.InputStroke
    )
    self._minusOuter, self._minusInner, self._minusHighlight = createBox(self, 10)
    self._plusOuter, self._plusInner, self._plusHighlight = createBox(self, 10)
    self._valueText = createLabelDrawing(self, "", 14)
    self._minusText = createLabelDrawing(self, "-", 14)
    self._plusText = createLabelDrawing(self, "+", 14)
    self._window:_set(self._minusText, {
        Center = true,
        Size = theme.TextSize,
    })
    self._window:_set(self._plusText, {
        Center = true,
        Size = theme.TextSize,
    })

    self._valueRegion = self:_region(20)
    self._minusRegion = self:_region(21)
    self._plusRegion = self:_region(21)
    self._valueRegion.OnPress = function()
        self:Focus()
        return false
    end
    self._valueRegion.OnWheel = function(delta)
        self:SetValue(self.Value + (delta > 0 and self.Step or -self.Step))
    end
    self._minusRegion.OnPress = function()
        if self._editing then
            self:Blur(true)
        end
        self:SetValue(self.Value - self.Step)
        return false
    end
    self._plusRegion.OnPress = function()
        if self._editing then
            self:Blur(true)
        end
        self:SetValue(self.Value + self.Step)
        return false
    end
    self._minusRegion.OnHover = function(hovered)
        self._minusHovered = hovered
        self:_updateStyle()
    end
    self._plusRegion.OnHover = function(hovered)
        self._plusHovered = hovered
        self:_updateStyle()
    end
    self._valueRegion.OnHover = function(hovered)
        self._hovered = hovered
        self:_updateStyle()
    end
    self:_updateStyle()

    return section:_add(self)
end

function Spinner:_updateStyle()
    local theme = self._window.Theme
    self._window:_set(self._valueInner, {
        Color = self._editing and theme.ControlActive
            or (self._hovered and theme.ControlHover or theme.Input),
    })
    self._window:_set(self._minusInner, {
        Color = self._minusHovered and theme.ControlHover or theme.Control,
    })
    self._window:_set(self._plusInner, {
        Color = self._plusHovered and theme.ControlHover or theme.Control,
    })
    local text = self._editing and self._editText or formatNumber(self.Value, self.Step)
    self._window:_set(self._valueText, {
        Text = text,
        Color = self._editing and theme.Accent or theme.Text,
    })
end

function Spinner:_layout(x, y, width)
    local actualWidth = width + 2
    local buttonWidth = 27
    local gap = 1
    local valueWidth = actualWidth - buttonWidth * 2 - gap * 2
    local fieldY = y + 16
    self._window:_set(self._label, {
        Text = self.Text,
        Position = Vector2.new(
            x,
            centeredTextY(y + 3, 10, self._window.Theme.TextSize)
        ),
    })
    layoutBox(
        self._window,
        self._valueOuter,
        self._valueInner,
        self._valueHighlight,
        x,
        fieldY,
        valueWidth,
        27
    )
    layoutBox(
        self._window,
        self._minusOuter,
        self._minusInner,
        self._minusHighlight,
        x + valueWidth + gap,
        fieldY,
        buttonWidth,
        27
    )
    layoutBox(
        self._window,
        self._plusOuter,
        self._plusInner,
        self._plusHighlight,
        x + valueWidth + gap + buttonWidth + gap,
        fieldY,
        buttonWidth,
        27
    )
    self._window:_set(self._valueText, {
        Position = Vector2.new(
            x + 10,
            centeredTextY(y + 19, 22, self._window.Theme.TextSize)
        ),
    })
    self._window:_set(self._minusText, {
        Position = Vector2.new(
            x + valueWidth + gap + buttonWidth * 0.5,
            centeredTextY(fieldY + 2, 23, self._window.Theme.TextSize)
        ),
    })
    self._window:_set(self._plusText, {
        Position = Vector2.new(
            x + valueWidth + gap + buttonWidth + gap + buttonWidth * 0.5,
            centeredTextY(fieldY + 2, 23, self._window.Theme.TextSize)
        ),
    })
    setRect(self._valueRegion.Rect, x, fieldY, valueWidth, 27)
    setRect(self._minusRegion.Rect, x + valueWidth + gap, fieldY, buttonWidth, 27)
    setRect(
        self._plusRegion.Rect,
        x + valueWidth + gap + buttonWidth + gap,
        fieldY,
        buttonWidth,
        27
    )
end

function Spinner:Focus()
    if self._destroyed then
        return self
    end
    if self._editing then
        return self
    end
    self._editing = true
    self._editText = formatNumber(self.Value, self.Step)
    self._library:_setFocusedTextbox(self)
    self:_updateStyle()
    return self
end

function Spinner:Blur(commit)
    if not self._editing then
        return self
    end
    self._library:_stopDeleteRepeat(self)
    if commit then
        local value = tonumber(self._editText)
        if value then
            self:SetValue(value)
        end
    end
    self._editing = false
    self._editText = nil
    if self._library._focusedTextbox == self then
        self._library._focusedTextbox = nil
    end
    self:_updateStyle()
    return self
end

function Spinner:_onKey(keyCode)
    if keyCode == Enum.KeyCode.Return or keyCode == Enum.KeyCode.KeypadEnter then
        self:Blur(true)
        return
    elseif keyCode == Enum.KeyCode.Escape then
        self:Blur(false)
        return
    elseif isDeleteKey(keyCode) then
        self._editText = string.sub(self._editText, 1, math.max(0, #self._editText - 1))
        self:_updateStyle()
        return
    elseif keyCode == Enum.KeyCode.Up then
        self:SetValue(self.Value + self.Step)
        self._editText = formatNumber(self.Value, self.Step)
        self:_updateStyle()
        return
    elseif keyCode == Enum.KeyCode.Down then
        self:SetValue(self.Value - self.Step)
        self._editText = formatNumber(self.Value, self.Step)
        self:_updateStyle()
        return
    end

    local character = inputCharacter(self._library, keyCode)
    if character and string.match(character, "[%d%.%-]") and #self._editText < 16 then
        self._editText = self._editText .. character
        self:_updateStyle()
    end
end

function Spinner:SetValue(value, silent)
    value = tonumber(value) or self.Value
    self.Value = clamp(snap(value, self.SnapBase, self.Step), self.Minimum, self.Maximum)
    self:_updateStyle()
    self:_changed(self.Value, silent)
    return self
end

Spinner.Set = Spinner.SetValue

function Spinner:Destroy()
    if self._editing then
        self:Blur(false)
    end
    Control.Destroy(self)
end

local function newTextbox(section, config)
    config = normalizeConfig(config)
    local self = setmetatable({}, Textbox)
    Control._init(self, section, config, config.Height or 51)

    self.Value = tostring(config.Default or config.Value or "")
    self.Placeholder = tostring(config.Placeholder or "")
    self.MaxLength = math.max(1, math.floor(config.MaxLength or 256))
    self.Numeric = config.Numeric == true
    self.ClearOnFocus = config.ClearOnFocus == true
    self.Live = config.Live ~= false
    self.Finished = config.Finished

    local theme = self._window.Theme
    self._label = createLabelDrawing(self, self.Text, 14)
    self._outer, self._inner, self._highlight = createBox(
        self,
        10,
        theme.Input,
        4,
        1,
        theme.InputStroke
    )
    self._valueText = createLabelDrawing(self, "", 14)
    self._caret = self:_draw("Line", {
        From = self._window.Position,
        To = self._window.Position,
        Color = theme.Accent,
        Thickness = 1,
        ZIndex = self._window:_z(16),
        Transparency = 1,
        Visible = false,
    })

    self._region = self:_region(20)
    self._region.OnPress = function()
        self:Focus()
        return false
    end
    self._region.OnHover = function(hovered)
        self._hovered = hovered
        self:_updateVisual()
    end
    self:_updateVisual()

    return section:_add(self)
end

function Textbox:_displayText()
    if self._editing then
        return self._editText
    end
    if self.Value == "" then
        return self.Placeholder
    end
    return self.Value
end

function Textbox:_updateVisual()
    local theme = self._window.Theme
    local value = self:_displayText()
    local width = self._width or theme.ControlWidth
    local displayValue = truncate(value, width - 18, theme.TextSize)
    self._window:_set(self._inner, {
        Color = self._editing and theme.ControlActive
            or (self._hovered and theme.ControlHover or theme.Input),
    })
    self._window:_set(self._valueText, {
        Text = displayValue,
        Color = self._editing and theme.Text
            or (self.Value == "" and theme.MutedText or theme.Text),
    })
    self._window:_show(self._caret, self._parentVisible and self._editing)

    if self._x then
        local textWidth = measuredTextWidth(
            self._valueText,
            displayValue,
            theme.TextSize
        )
        local caretX = math.min(
            self._x + width - 6,
            self._x + 13 + textWidth
        )
        self._window:_set(self._caret, {
            From = Vector2.new(caretX, self._y + 21),
            To = Vector2.new(caretX, self._y + 37),
        })
    end
end

function Textbox:_layout(x, y, width)
    self._x = x
    self._y = y
    self._width = width
    self._window:_set(self._label, {
        Text = self.Text,
        Position = Vector2.new(
            x,
            centeredTextY(y + 3, 10, self._window.Theme.TextSize)
        ),
    })
    layoutBox(self._window, self._outer, self._inner, self._highlight, x, y + 16, width, 27)
    self._window:_set(self._valueText, {
        Position = Vector2.new(
            x + 13,
            centeredTextY(y + 18, 23, self._window.Theme.TextSize)
        ),
    })
    setRect(self._region.Rect, x, y + 16, width, 27)
    self:_updateVisual()
end

function Textbox:_syncVisibility(parentVisible)
    Control._syncVisibility(self, parentVisible)
    self:_updateVisual()
    if not self._parentVisible and self._editing then
        self:Blur(true)
    end
end

function Textbox:Focus()
    if self._destroyed then
        return self
    end
    if self._editing then
        return self
    end
    self._editing = true
    self._editText = self.ClearOnFocus and "" or self.Value
    self._library:_setFocusedTextbox(self)
    self:_updateVisual()
    return self
end

function Textbox:Blur(commit)
    if not self._editing then
        return self
    end
    self._library:_stopDeleteRepeat(self)
    if commit then
        self:SetValue(self._editText, self.Live)
    end
    self._editing = false
    self._editText = nil
    if self._library._focusedTextbox == self then
        self._library._focusedTextbox = nil
    end
    self:_updateVisual()
    return self
end

function Textbox:_onKey(keyCode)
    if keyCode == Enum.KeyCode.Return or keyCode == Enum.KeyCode.KeypadEnter then
        local submitted = self._editText
        self:Blur(true)
        safeCall(self.Finished, submitted, self)
        return
    elseif keyCode == Enum.KeyCode.Escape then
        self:Blur(false)
        return
    elseif keyCode == Enum.KeyCode.Tab then
        self:Blur(true)
        return
    elseif isDeleteKey(keyCode) then
        self._editText = string.sub(self._editText, 1, math.max(0, #self._editText - 1))
        if self.Live then
            self.Value = self._editText
            self:_changed(self.Value, false)
        end
        self:_updateVisual()
        return
    end

    local character = inputCharacter(self._library, keyCode)
    if not character or #self._editText >= self.MaxLength then
        return
    end
    if self.Numeric and not string.match(character, "[%d%.%-]") then
        return
    end
    self._editText = self._editText .. character
    if self.Live then
        self.Value = self._editText
        self:_changed(self.Value, false)
    end
    self:_updateVisual()
end

function Textbox:SetValue(value, silent)
    self.Value = string.sub(tostring(value or ""), 1, self.MaxLength)
    if self._editing then
        self._editText = self.Value
    end
    self:_updateVisual()
    self:_changed(self.Value, silent)
    return self
end

Textbox.Set = Textbox.SetValue

function Textbox:Destroy()
    if self._editing then
        self:Blur(false)
    end
    Control.Destroy(self)
end

local function newListbox(section, config)
    config = normalizeConfig(config)
    local self = setmetatable({}, Listbox)
    self.BoxHeight = math.max(42, math.floor(config.Height or config.ListHeight or 127))
    Control._init(self, section, config, config.TotalHeight or (self.BoxHeight + 21))

    self.Values = arrayCopy(config.Values or config.Options or {})
    self.Value = config.Default
    if self.Value == nil then
        self.Value = config.Value
    end
    self.ScrollOffset = 1
    self.RowHeight = math.max(16, math.floor(config.RowHeight or 20))
    self.VisibleRows = math.max(1, math.floor((self.BoxHeight - 2) / self.RowHeight))
    self._rows = {}

    local theme = self._window.Theme
    self._label = createLabelDrawing(self, self.Text, 14)
    self._outer = newRoundedRect(self._window, self._drawings, theme.ControlBorder, 10, 4)
    self._stroke = newRoundedRect(self._window, self._drawings, theme.InputStroke, 11, 2)
    self._inner = newRoundedRect(self._window, self._drawings, theme.Input, 12, 1)

    for rowIndex = 1, self.VisibleRows do
        local row = {}
        row.Background = self:_draw("Square", {
            Filled = true,
            Color = theme.Input,
            Position = self._window.Position,
            Size = Vector2.new(1, 1),
            ZIndex = self._window:_z(13),
            Transparency = 1,
            Visible = false,
        })
        row.Text = createLabelDrawing(self, "", 14)
        row.Region = self:_region(21)
        row.Region.Enabled = function()
            return self._parentVisible and not self._destroyed and row.Value ~= nil
        end
        row.Region.OnPress = function()
            if row.Value ~= nil then
                self:SetValue(row.Value)
            end
            return false
        end
        row.Region.OnHover = function(hovered)
            row.Hovered = hovered
            self:_updateRows()
        end
        row.Region.OnWheel = function(delta)
            self:_scroll(delta)
        end
        table.insert(self._rows, row)
    end

    self._scrollRegion = self:_region(20)
    self._scrollRegion.OnWheel = function(delta)
        self:_scroll(delta)
    end
    self:_updateRows()

    return section:_add(self)
end

function Listbox:_maxOffset()
    return math.max(1, #self.Values - self.VisibleRows + 1)
end

function Listbox:_scroll(delta)
    if delta > 0 then
        self.ScrollOffset = self.ScrollOffset - 1
    elseif delta < 0 then
        self.ScrollOffset = self.ScrollOffset + 1
    end
    self.ScrollOffset = clamp(self.ScrollOffset, 1, self:_maxOffset())
    self:_updateRows()
end

function Listbox:_updateRows()
    local theme = self._window.Theme
    for rowIndex, row in ipairs(self._rows) do
        local value = self.Values[self.ScrollOffset + rowIndex - 1]
        row.Value = value
        local visible = self._parentVisible and value ~= nil
        self._window:_show(row.Background, visible)
        self._window:_show(row.Text, visible)
        if value ~= nil then
            local selected = self.Value == value
            self._window:_set(row.Background, {
                Color = selected and theme.Selection
                    or (row.Hovered and theme.ControlHover or theme.Input),
            })
            self._window:_set(row.Text, {
                Text = tostring(value),
                Color = selected and theme.Accent or theme.Text,
            })
        end
    end
end

function Listbox:_layout(x, y, width)
    self._x = x
    self._y = y
    self._width = width
    local boxY = y + 16
    self._window:_set(self._label, {
        Text = self.Text,
        Position = Vector2.new(
            x,
            centeredTextY(y + 3, 10, self._window.Theme.TextSize)
        ),
    })
    self._window:_set(self._outer, {
        Position = Vector2.new(x, boxY),
        Size = Vector2.new(width, self.BoxHeight),
    })
    self._window:_set(self._stroke, {
        Position = Vector2.new(x + 1, boxY + 1),
        Size = Vector2.new(width - 2, self.BoxHeight - 2),
    })
    self._window:_set(self._inner, {
        Position = Vector2.new(x + 2, boxY + 2),
        Size = Vector2.new(width - 4, self.BoxHeight - 4),
    })
    setRect(self._scrollRegion.Rect, x, boxY, width, self.BoxHeight)

    for rowIndex, row in ipairs(self._rows) do
        local rowY = boxY + 2 + (rowIndex - 1) * self.RowHeight
        self._window:_set(row.Background, {
            Position = Vector2.new(x + 2, rowY),
            Size = Vector2.new(width - 4, self.RowHeight),
        })
        self._window:_set(row.Text, {
            Position = Vector2.new(
                x + 14,
                centeredTextY(rowY, 25, self._window.Theme.TextSize)
            ),
        })
        setRect(row.Region.Rect, x + 2, rowY, width - 4, self.RowHeight)
    end
    self:_updateRows()
end

function Listbox:_syncVisibility(parentVisible)
    Control._syncVisibility(self, parentVisible)
    self:_updateRows()
end

function Listbox:SetValue(value, silent)
    if value ~= nil and not valueExists(self.Values, value) and not self._config.AllowUnknown then
        return self
    end
    self.Value = value
    self:_updateRows()
    self:_changed(self.Value, silent)
    return self
end

Listbox.Set = Listbox.SetValue

function Listbox:SetValues(values, preserveValue)
    self.Values = arrayCopy(values)
    self.ScrollOffset = 1
    if not preserveValue and self.Value ~= nil and not valueExists(self.Values, self.Value) then
        self.Value = nil
    end
    self:_updateRows()
    return self
end

Listbox.SetOptions = Listbox.SetValues

local function newLabel(section, config)
    config = normalizeConfig(config)
    local self = setmetatable({}, Label)
    Control._init(self, section, config, config.Height or 23)
    self.Value = self.Text
    self._text = createLabelDrawing(self, self.Text, 14)
    self._window:_set(self._text, {
        Color = config.Color or self._window.Theme.Text,
        Size = config.Size or self._window.Theme.TextSize,
    })
    return section:_add(self)
end

function Label:_layout(x, y)
    self._window:_set(self._text, {
        Text = self.Text,
        Position = Vector2.new(
            x,
            centeredTextY(
                y,
                self._height,
                self._config.Size or self._window.Theme.TextSize
            )
        ),
    })
end

function Label:SetValue(value)
    self.Value = tostring(value)
    self.Text = self.Value
    self._window:_set(self._text, { Text = self.Value })
    return self
end

Label.Set = Label.SetValue

local function newSeparator(section, config)
    config = normalizeConfig(config)
    local self = setmetatable({}, Separator)
    Control._init(self, section, config, config.Height or 16)
    self._line = self:_draw("Line", {
        From = self._window.Position,
        To = self._window.Position,
        Color = config.Color or self._window.Theme.InnerBorder,
        Thickness = 1,
        ZIndex = self._window:_z(12),
        Transparency = 1,
        Visible = false,
    })
    if self.Text ~= "" then
        self._text = createLabelDrawing(self, self.Text, 14)
        self._window:_set(self._text, {
            Color = self._window.Theme.MutedText,
            Center = true,
            Size = self._window.Theme.TextSize - 1,
        })
    end
    return section:_add(self)
end

function Separator:_layout(x, y, width)
    self._window:_set(self._line, {
        From = Vector2.new(x, y + 7),
        To = Vector2.new(x + width, y + 7),
    })
    if self._text then
        self._window:_set(self._text, {
            Position = Vector2.new(x + width * 0.5, y),
        })
    end
end

local function newStandaloneKeybind(section, config)
    config = normalizeConfig(config)
    local self = setmetatable({}, StandaloneKeybind)
    Control._init(self, section, config, config.Height or 23)
    self._label = createLabelDrawing(self, self.Text, 14)
    self._addon = setmetatable({}, KeybindAddon)
    initializeKeybind(self._addon, self, config)
    return section:_add(self)
end

function StandaloneKeybind:_layout(x, y, width)
    self._window:_set(self._label, {
        Text = self.Text,
        Position = Vector2.new(
            x,
            centeredTextY(y, self._height, self._window.Theme.TextSize)
        ),
    })
    local addonWidth = self._addon:_preferredWidth()
    self._addon:_layout(x + (self._rowWidth or width) - addonWidth, y, addonWidth)
end

function StandaloneKeybind:_syncVisibility(parentVisible)
    Control._syncVisibility(self, parentVisible)
    self._addon:_syncVisibility(self._parentVisible)
end

function StandaloneKeybind:GetValue()
    return self._addon:GetValue()
end

function StandaloneKeybind:SetValue(value, silent)
    self._addon:SetValue(value, silent)
    self._window:_setFlag(self.Flag, value)
    return self
end

StandaloneKeybind.Set = StandaloneKeybind.SetValue

function StandaloneKeybind:Destroy()
    if self._destroyed then
        return
    end
    self._addon:Destroy()
    Control.Destroy(self)
end

local function newStandaloneColorPicker(section, config)
    config = normalizeConfig(config)
    local self = setmetatable({}, StandaloneColorPicker)
    Control._init(self, section, config, config.Height or 23)
    self._label = createLabelDrawing(self, self.Text, 14)
    self._addon = setmetatable({}, ColorPickerAddon)
    initializeColorPicker(self._addon, self, config)
    return section:_add(self)
end

function StandaloneColorPicker:_layout(x, y, width)
    self._window:_set(self._label, {
        Text = self.Text,
        Position = Vector2.new(
            x,
            centeredTextY(y, self._height, self._window.Theme.TextSize)
        ),
    })
    self._addon:_layout(
        x + (self._rowWidth or width) - self._addon:_preferredWidth(),
        y
    )
end

function StandaloneColorPicker:_syncVisibility(parentVisible)
    Control._syncVisibility(self, parentVisible)
    self._addon:_syncVisibility(self._parentVisible)
end

function StandaloneColorPicker:GetValue()
    return self._addon:GetValue()
end

function StandaloneColorPicker:SetValue(value, silent)
    self._addon:SetValue(value, silent)
    return self
end

StandaloneColorPicker.Set = StandaloneColorPicker.SetValue

function StandaloneColorPicker:SetRainbow(enabled)
    self._addon:SetRainbow(enabled)
    return self
end

function StandaloneColorPicker:OpenPopup()
    self._addon:OpenPopup()
    return self
end

function StandaloneColorPicker:Close()
    self._addon:Close()
    return self
end

function StandaloneColorPicker:Destroy()
    if self._destroyed then
        return
    end
    self._addon:Destroy()
    Control.Destroy(self)
end

function Section:AddButton(config, callback)
    return newButton(self, config, callback)
end

Section.Button = Section.AddButton

function Section:AddCheckbox(config)
    return newCheckbox(self, config)
end

Section.Checkbox = Section.AddCheckbox
Section.AddToggle = Section.AddCheckbox
Section.Toggle = Section.AddCheckbox

function Section:AddSlider(config)
    return newSlider(self, config)
end

Section.Slider = Section.AddSlider

function Section:AddDropdown(config)
    return newDropdown(self, config)
end

Section.Dropdown = Section.AddDropdown
Section.AddCombobox = Section.AddDropdown
Section.Combobox = Section.AddDropdown
Section.AddComboBox = Section.AddDropdown
Section.ComboBox = Section.AddDropdown

function Section:AddMultiDropdown(config)
    return newMultiDropdown(self, config)
end

Section.MultiDropdown = Section.AddMultiDropdown
Section.AddMultibox = Section.AddMultiDropdown
Section.Multibox = Section.AddMultiDropdown
Section.AddMultiBox = Section.AddMultiDropdown
Section.MultiBox = Section.AddMultiDropdown

function Section:AddSpinner(config)
    return newSpinner(self, config)
end

Section.Spinner = Section.AddSpinner

function Section:AddTextbox(config)
    return newTextbox(self, config)
end

Section.Textbox = Section.AddTextbox
Section.AddInput = Section.AddTextbox
Section.Input = Section.AddTextbox
Section.AddTextBox = Section.AddTextbox
Section.TextBox = Section.AddTextbox

function Section:AddListbox(config)
    return newListbox(self, config)
end

Section.Listbox = Section.AddListbox
Section.AddListBox = Section.AddListbox
Section.ListBox = Section.AddListbox

function Section:AddLabel(config)
    return newLabel(self, config)
end

Section.Label = Section.AddLabel

function Section:AddSeparator(config)
    return newSeparator(self, config)
end

Section.Separator = Section.AddSeparator
Section.AddDivider = Section.AddSeparator

function Section:AddKeybind(config)
    return newStandaloneKeybind(self, config)
end

Section.Keybind = Section.AddKeybind

function Section:AddColorPicker(config)
    return newStandaloneColorPicker(self, config)
end

Section.ColorPicker = Section.AddColorPicker

function Nephren:CreateWindow(config)
    config = copyTable(config or {})
    self:_start()

    local size = config.Size
        or Vector2.new(tonumber(config.Width) or 587, tonumber(config.Height) or 563)
    size = Vector2.new(math.max(360, size.X), math.max(260, size.Y))

    local position = config.Position
    if not position then
        if config.Center == false then
            position = Vector2.new(40, 40)
        else
            position = defaultPosition(size)
        end
    end

    local toggleKey = config.ToggleKey
    if toggleKey == nil then
        toggleKey = Enum.KeyCode.RightShift
    elseif toggleKey == false then
        toggleKey = nil
    end

    local window = setmetatable({
        Title = tostring(config.Title or config.Name or "Nephren"),
        Position = position,
        Size = size,
        Visible = config.Visible ~= false,
        Draggable = config.Draggable ~= false,
        ToggleKey = toggleKey,
        BaseZIndex = config.ZIndex or (#self._windows * 1000),
        Theme = merge(DEFAULT_THEME, config.Theme),
        Tabs = {},
        SelectedTab = nil,
        Flags = {},
        _flagControls = {},
        _drawings = {},
        _baseDrawings = {},
        _regions = {},
        _destroyed = false,
        _openPopup = nil,
    }, Window)

    window:_createBase()
    table.insert(self._windows, window)
    window:_layout()
    return window
end

Nephren.Window = Nephren.CreateWindow

function Nephren:GetWindow(index)
    return self._windows[index or 1]
end

function Nephren:Unload()
    local windows = arrayCopy(self._windows)
    for _, window in ipairs(windows) do
        window:Destroy()
    end

    for _, connection in ipairs(self._connections) do
        pcall(function()
            connection:Disconnect()
        end)
    end

    self._connections = {}
    self._windows = {}
    self._keybinds = {}
    self._rainbowPickers = {}
    self._focusedTextbox = nil
    self._bindingKeybind = nil
    self._capture = nil
    self._hoveredRegion = nil
    self._keysDown = {}
    self._capsLock = false
    self._deleteRepeat = nil
    self._started = false
    for flag in pairs(self.Flags) do
        self.Flags[flag] = nil
    end
end

Nephren.Destroy = Nephren.Unload

return Nephren
