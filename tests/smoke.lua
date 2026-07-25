-- Minimal Roblox/Drawing compatibility layer for exercising Nephren in Lua 5.3.

local vectorMeta = {}
vectorMeta.__index = vectorMeta
vectorMeta.__add = function(left, right)
    return Vector2.new(left.X + right.X, left.Y + right.Y)
end
vectorMeta.__sub = function(left, right)
    return Vector2.new(left.X - right.X, left.Y - right.Y)
end

Vector2 = {}
function Vector2.new(x, y)
    return setmetatable({ X = x, Y = y }, vectorMeta)
end

local colorMeta = {}
colorMeta.__index = colorMeta

Color3 = {}
function Color3.new(r, g, b)
    return setmetatable({ R = r, G = g, B = b }, colorMeta)
end

function Color3.fromRGB(r, g, b)
    return Color3.new(r / 255, g / 255, b / 255)
end

function Color3.fromHSV(h, s, v)
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

function colorMeta:ToHSV()
    local maximum = math.max(self.R, self.G, self.B)
    local minimum = math.min(self.R, self.G, self.B)
    local delta = maximum - minimum
    local hue = 0
    if delta > 0 then
        if maximum == self.R then
            hue = ((self.G - self.B) / delta) % 6
        elseif maximum == self.G then
            hue = ((self.B - self.R) / delta) + 2
        else
            hue = ((self.R - self.G) / delta) + 4
        end
        hue = hue / 6
    end
    return hue, maximum == 0 and 0 or delta / maximum, maximum
end

local function enumGroup()
    return setmetatable({}, {
        __index = function(group, name)
            local item = { Name = name }
            rawset(group, name, item)
            return item
        end,
    })
end

Enum = {
    KeyCode = enumGroup(),
    UserInputType = enumGroup(),
}

local function event()
    local value = { Listeners = {} }
    function value:Connect(callback)
        table.insert(self.Listeners, callback)
        local connected = true
        return {
            Disconnect = function()
                connected = false
            end,
            Connected = function()
                return connected
            end,
        }
    end
    function value:Fire(...)
        for _, callback in ipairs(self.Listeners) do
            callback(...)
        end
    end
    return value
end

local userInputService = {
    InputBegan = event(),
    InputChanged = event(),
    InputEnded = event(),
    MouseLocation = Vector2.new(0, 0),
}

function userInputService:GetMouseLocation()
    return self.MouseLocation
end

function userInputService:IsKeyDown()
    return false
end

local runService = {
    RenderStepped = event(),
}

game = {}
function game:GetService(name)
    if name == "UserInputService" then
        return userInputService
    elseif name == "RunService" then
        return runService
    end
    error("unknown service: " .. tostring(name))
end

workspace = {
    CurrentCamera = {
        ViewportSize = Vector2.new(1920, 1080),
    },
}

local created = 0
local removed = 0
Drawing = {
    Fonts = {
        UI = 0,
        System = 1,
        Plex = 2,
        Monospace = 3,
    },
}

function Drawing.new(kind)
    created = created + 1
    local object = {
        Kind = kind,
        Visible = false,
        __OBJECT_EXISTS = true,
    }
    function object:Remove()
        if self.__OBJECT_EXISTS then
            self.__OBJECT_EXISTS = false
            removed = removed + 1
        end
    end
    object.Destroy = object.Remove
    return setmetatable(object, {
        __index = function(value, property)
            if kind == "Text" and property == "TextBounds" then
                return Vector2.new(
                    #tostring(rawget(value, "Text") or "") * 5,
                    rawget(value, "Size") or 13
                )
            end
        end,
    })
end

warn = print

local Nephren = dofile("src/Nephren.lua")
local window = Nephren:CreateWindow({
    Title = "Smoke",
    Position = Vector2.new(10, 20),
})
assert(window.Theme.TextSize == 14)
assert(window._titleDrawing.Object.Font == Drawing.Fonts.Plex)
assert(window._titleDrawing.Object.Size == 14)
assert(window._titleDrawing.Object.Position.Y == window.Position.Y + 10)
local tab = window:AddTab("Main")
local otherTab = window:AddTab("Other")
local section = tab:AddSection({
    Title = "Controls",
    Side = "Left",
    Height = 490,
})

local dropdown = section:AddCombobox({
    Text = "Combobox",
    Values = { "One", "Two" },
    Default = "One",
    Flag = "Dropdown",
})
local slider = section:AddSlider({
    Text = "Slider",
    Min = 0,
    Max = 10,
    Default = 5,
    Flag = "Slider",
})
local button = section:AddButton("Button", function() end)
local multibox = section:AddMultibox({
    Text = "Multibox",
    Values = { "One", "Two" },
    Default = { "One" },
})
local spinner = section:AddSpinner({
    Text = "Spinner",
    Min = -10,
    Max = 10,
})
local checkbox = section:AddCheckbox({
    Text = "Checkbox",
    Flag = "Checkbox",
})
local checkboxKeybind = checkbox:AddKeybind({
    Default = Enum.KeyCode.H,
})
local picker = checkbox:AddColorPicker({
    Default = Color3.fromRGB(255, 0, 0),
    Flag = "Color",
})
local textbox = section:AddTextbox({
    Text = "Textbox",
    Default = "Text",
})
local listbox = section:AddListbox({
    Text = "Listbox",
    Values = { "One", "Two", "Three" },
})

assert(window.Flags.Dropdown == "One")
assert(window.Flags.Checkbox == false)
assert(math.floor(window.Theme.Stroke.R * 255 + 0.5) == 26)
assert(math.floor(window.Theme.TabStroke.R * 255 + 0.5) == 28)
assert(math.floor(window.Theme.ControlBorder.R * 255 + 0.5) == 11)
assert(math.floor(window.Theme.ControlStroke.R * 255 + 0.5) == 49)
assert(math.floor(window.Theme.InputStroke.R * 255 + 0.5) == 31)
assert(section._outer._kind == "RoundedRect")
assert(section._outer.ReinforceCorners == true)
assert(#section._outer.Parts == 10)
assert(section._outer.Parts[3].Object.Position.X == section._outer.Parts[7].Object.Position.X)
assert(section._outer.Parts[3].Object.Position.Y == section._outer.Parts[7].Object.Position.Y)
assert(section._outer.Parts[3].Object.Radius == section._outer.Parts[7].Object.Radius)
assert(section._outer.Parts[3].Object.Filled == true)
assert(section._outer.Parts[7].Object.Filled == false)
assert(#section._inner.Parts == 6)
assert(section._accent._kind == "Gradient")
assert(section._accent.Radius == 3)
assert(section._accent.Radius == tab._accent.Radius)
assert(section._accent.Segments == tab._accent.Segments)
assert(section._x == window.Position.X + 10)
assert(section._bodyY == window.Position.Y + window.Theme.HeaderHeight + 36)
assert(section._width == 276)
assert(section._outer.Color == window.Theme.Border)
assert(section._outer.Position.X == section._x - 1)
assert(section._outer.Position.Y == section._bodyY - 1)
assert(section._outer.Size.X == section._width + 2)
assert(section._outer.Size.Y == section:_bodyHeight() + 2)
assert(section._accent.Position.X == section._x)
assert(section._accent.Position.Y == section._bodyY)
assert(section._accent.Size.X == section._width)
assert(section._accent.Size.Y == 4)
assert(section._title.Object.Size == 14)
assert(section._title.Object.Position.Y == section._bodyY - 18)
assert(section._accent.StartCap.Object.Radius == 2)
assert(section._accent.StartCap.Object.Position.Y == section._bodyY + 2)
assert(section._outline == nil)
assert(section._stroke.Color == window.Theme.Stroke)
assert(section._stroke.Position.X == section._x)
assert(section._stroke.Position.Y == section._bodyY + 2)
assert(section._stroke.Size.X == section._width)
assert(section._stroke.Size.Y == section:_bodyHeight() - 2)
assert(section._inner.Position.X == section._x + 1)
assert(section._inner.Position.Y == section._bodyY + 3)
assert(tab._accent.Radius == 3)
assert(tab._accent.Position.Y == window.Position.Y + 3)
assert(tab._accent.Size.X == tab.Width)
assert(tab._accent.Size.Y == 6)
assert(tab._stroke.Position.Y == window.Position.Y + 5)
assert(tab._inner.Position.Y == window.Position.Y + 6)
assert(tab._bottomMask.Object.Kind == "Square")
assert(tab._bottomMask.Object.Visible == true)
assert(tab._bottomMask.Object.Color == window.Theme.Background)
assert(tab._bottomMask.Object.Position.X == window.Position.X + window.Theme.TitleWidth)
assert(tab._bottomMask.Object.Position.Y == window.Position.Y + window.Theme.HeaderHeight - 1)
assert(tab._bottomMask.Object.Size.X == tab.Width - 2)
assert(otherTab._accent.Parts[1].Object.Visible == false)
otherTab:Select()
assert(tab._accent.Parts[1].Object.Visible == false)
assert(tab._bottomMask.Object.Visible == false)
assert(otherTab._accent.Parts[1].Object.Visible == true)
assert(otherTab._bottomMask.Object.Visible == true)
tab:Select()
assert(tab._text.Object.Size == 14)
assert(tab._text.Object.Position.Y == window.Position.Y + 10)
assert(slider._fill._kind == "Gradient")
assert(slider._trackOuter._kind == "RoundedRect")
assert(slider._trackBackground._kind == "RoundedRect")
assert(textbox._inner._kind == "RoundedRect")
assert(listbox._outer._kind == "RoundedRect")
assert(textbox._inner.Color == window.Theme.Input)
assert(spinner._valueInner.Color == window.Theme.Input)
assert(listbox._inner.Color == window.Theme.Input)
assert(button._outer.Color == window.Theme.ControlBorder)
assert(button._highlight.Color == window.Theme.ControlStroke)
assert(textbox._highlight.Color == window.Theme.InputStroke)
assert(listbox._stroke.Color == window.Theme.InputStroke)
assert(button._inner.Radius == 1)
assert(dropdown._inner.Radius == 1)
assert(textbox._inner.Radius == 1)
assert(button._outer.Size.X == 200)
assert(button._outer.Size.Y == 27)
assert(dropdown._outer.Size.X == 200)
assert(dropdown._activeGradient._kind == "Gradient")
assert(dropdown._activeGradient.Radius == 0)
assert(#dropdown._activeGradientCorners == 4)
assert(dropdown._activeGradient.Position.X == dropdown._x + 2)
assert(dropdown._activeGradient.Position.Y == dropdown._y + 22)
assert(dropdown._activeGradient.Size.X == dropdown._width - 4)
assert(dropdown._activeGradient.Size.Y == 23)
assert(dropdown._activeGradient.Parts[1].Object.Visible == false)
assert(textbox._outer.Size.X == 198)
assert(listbox._outer.Size.X == 198)
assert(listbox._outer.Size.Y == 127)
assert(multibox._glyph == nil)
assert(#multibox._glyphLines == 3)
assert(#multibox._glyphOutlineLines == 3)
assert(#multibox._activeGradientCorners == 4)
assert(multibox._activeGradient._kind == "Gradient")
assert(multibox._activeGradient.Radius == 0)
assert(multibox._activeGradient.Position.X == multibox._x + 2)
assert(multibox._activeGradient.Position.Y == multibox._y + 22)
assert(multibox._activeGradient.Size.X == multibox._width - 4)
assert(multibox._activeGradient.Size.Y == 23)
for index = 1, 3 do
    assert(multibox._glyphLines[index].Object.Kind == "Line")
    assert(multibox._glyphLines[index].Object.Thickness == 1)
    assert(multibox._glyphOutlineLines[index].Object.Thickness == 3)
    assert(multibox._glyphLines[index].Object.To.X - multibox._glyphLines[index].Object.From.X == 5)
    assert(multibox._glyphLines[index].Object.From.Y == multibox._y + 31 + (index - 1) * 2)
end
assert(picker._swatchOuter.Object.Kind == "Square")
assert(picker._swatchInner.Radius == 0)
assert(picker._swatchOuter.Object.Size.X == 18)
assert(picker._swatchOuter.Object.Size.Y == 8)
assert(checkbox._boxOuter.Size.X == 14)
assert(checkbox._check._kind == "Gradient")
assert(checkbox._check.Size.X == 8)
assert(checkbox._check.Size.Y == 8)
assert(checkbox._check.StartColor == window.Theme.Accent)
assert(checkbox._check.EndColor == window.Theme.AccentEnd)
assert(#checkbox._checkCorners == 4)
assert(checkboxKeybind.Mode == "Toggle")
assert(spinner._valueOuter.Size.X == 144)
assert(spinner._minusOuter.Size.X == 27)
assert(spinner._plusOuter.Size.X == 27)
assert(button._text.Object.Size == 14)
assert(dropdown._label.Object.Size == 14)
assert(dropdown._valueText.Object.Size == 14)
assert(dropdown._glyph.Object.Size == 14)
assert(slider._label.Object.Size == 14)
assert(slider._valueText.Object.Size == 14)
assert(multibox._label.Object.Size == 14)
assert(multibox._valueText.Object.Size == 14)
assert(spinner._label.Object.Size == 14)
assert(spinner._valueText.Object.Size == 14)
assert(spinner._minusText.Object.Size == 14)
assert(spinner._plusText.Object.Size == 14)
assert(checkbox._label.Object.Size == 14)
assert(checkboxKeybind._text.Object.Size == 12)
assert(textbox._label.Object.Size == 14)
assert(textbox._valueText.Object.Size == 14)
assert(listbox._label.Object.Size == 14)
assert(listbox._rows[1].Text.Object.Size == 14)
assert(dropdown._x == section._x + 9)
assert(dropdown._y == section._bodyY + 12)
assert(dropdown._label.Object.Position.Y == dropdown._y + 4)
assert(dropdown._outer.Position.Y == dropdown._y + 20)
assert(dropdown._valueText.Object.Position.Y == dropdown._y + 28)
assert(dropdown._glyph.Object.Position.Y == dropdown._y + 25)
assert(slider._x == section._x + 9)
assert(slider._y == section._bodyY + 72)
assert(slider._label.Object.Position.Y == slider._y - 2)
assert(slider._trackOuter.Position.Y == slider._y + 13)
assert(slider._trackBackground.Position.Y == slider._y + 15)
assert(slider._valueText.Object.Position.Y == slider._y + 20)
assert(button._outer.Position.Y == section._bodyY + 105)
assert(button._text.Object.Position.Y == button._outer.Position.Y + 8)
assert(multibox._y == section._bodyY + 142)
assert(multibox._label.Object.Position.Y == multibox._y + 4)
assert(multibox._valueText.Object.Position.Y == multibox._y + 28)
assert(spinner._label.Object.Position.Y == section._bodyY + 200)
assert(spinner._valueOuter.Position.Y == section._bodyY + 215)
assert(spinner._valueText.Object.Position.Y == section._bodyY + 222)
assert(spinner._minusText.Object.Position.Y == section._bodyY + 222)
assert(spinner._plusText.Object.Position.Y == section._bodyY + 222)
assert(checkbox._y == section._bodyY + 250)
assert(checkbox._rowWidth == 251)
assert(checkbox._boxOuter.Position.Y == checkbox._y + 4)
assert(checkbox._label.Object.Position.X == checkbox._x + 21)
assert(checkbox._label.Object.Position.Y == checkbox._y + 5)
assert(checkboxKeybind._x == checkbox._x + 213)
assert(checkboxKeybind._text.Object.Position.Y == checkbox._y + 5)
assert(picker._x == checkbox._x + 233)
assert(picker._swatchOuter.Object.Position.Y == checkbox._y + 7)
assert(picker._swatchInner.Position.X == checkbox._x + 234)
assert(picker._swatchInner.Position.Y == checkbox._y + 8)
assert(picker._popupX == checkbox._x + 76)
assert(picker._popupY == checkbox._y + 19)
assert(picker._rainbowText.Object.Size == 14)
assert(picker._rainbowText.Object.Position.Y == picker._popupY + 137)
assert(picker._rgbText.Object.Size == 14)
assert(picker._rgbText.Object.Position.Y == picker._popupY + 165)
assert(picker._hexText.Object.Size == 14)
assert(picker._hexText.Object.Position.Y == picker._popupY + 197)
assert(textbox._y == section._bodyY + 276)
assert(textbox._label.Object.Position.Y == textbox._y + 1)
assert(textbox._outer.Position.Y == textbox._y + 16)
assert(textbox._valueText.Object.Position.X == textbox._x + 13)
assert(textbox._valueText.Object.Position.Y == textbox._y + 23)
assert(listbox._y == section._bodyY + 327)
assert(listbox._label.Object.Position.Y == listbox._y + 1)
assert(listbox._outer.Position.Y == listbox._y + 16)
assert(listbox._rows[1].Text.Object.Position.Y == listbox._y + 24)
assert(slider._height == 33)

local halfFill = math.floor((slider._width - 4) * 0.5 + 0.5)
assert(slider._fill.Size.X == halfFill)
assert(slider._valueText.Object.Position.X == slider._x + 2 + halfFill - 3)
slider:SetValue(0, true)
assert(slider._fill.Parts[1].Object.Visible == false)
slider:SetValue(10, true)
assert(slider._fill.Size.X == slider._width - 4)
slider:SetValue(5, true)

assert(multibox._activeGradient.Parts[1].Object.Visible == false)
multibox:OpenPopup()
assert(multibox.Open == true)
assert(multibox._activeGradient.Parts[1].Object.Visible == true)
assert(multibox._activeGradientCorners[1].Object.Visible == true)
assert(math.abs(multibox._activeGradient.StartColor.R - window.Theme.Accent.R * 0.20) < 0.0001)
assert(math.abs(multibox._activeGradient.EndColor.R - window.Theme.AccentEnd.R * 0.30) < 0.0001)
assert(multibox._valueText.Object.Color == window.Theme.Text)
for index = 1, 3 do
    assert(multibox._glyphLines[index].Object.Color == window.Theme.MenuIcon)
end
multibox:Close()
assert(multibox._activeGradient.Parts[1].Object.Visible == false)
assert(multibox._activeGradientCorners[1].Object.Visible == false)

local checkboxPoint = Vector2.new(
    checkbox._region.Rect.X + 2,
    checkbox._region.Rect.Y + 2
)
userInputService.MouseLocation = checkboxPoint
userInputService.InputBegan:Fire({
    UserInputType = Enum.UserInputType.MouseButton1,
    KeyCode = Enum.KeyCode.Unknown,
    Position = { X = checkboxPoint.X, Y = checkboxPoint.Y, Z = 0 },
}, false)
assert(window.Flags.Checkbox == true, "checkbox should respond through UserInputService")
assert(checkbox._check.Parts[1].Object.Visible == true)
assert(checkbox._checkCorners[1].Object.Visible == true)

userInputService.InputBegan:Fire({
    UserInputType = Enum.UserInputType.Keyboard,
    KeyCode = Enum.KeyCode.H,
    Position = { X = 0, Y = 0, Z = 0 },
}, false)
assert(window.Flags.Checkbox == false, "checkbox keybind should update its parent state")
assert(checkbox._check.Parts[1].Object.Visible == false)
userInputService.InputEnded:Fire({
    UserInputType = Enum.UserInputType.Keyboard,
    KeyCode = Enum.KeyCode.H,
    Position = { X = 0, Y = 0, Z = 0 },
})
userInputService.InputBegan:Fire({
    UserInputType = Enum.UserInputType.Keyboard,
    KeyCode = Enum.KeyCode.H,
    Position = { X = 0, Y = 0, Z = 0 },
}, false)
assert(window.Flags.Checkbox == true)
assert(checkbox._check.Parts[1].Object.Visible == true)
userInputService.InputEnded:Fire({
    UserInputType = Enum.UserInputType.Keyboard,
    KeyCode = Enum.KeyCode.H,
    Position = { X = 0, Y = 0, Z = 0 },
})

local textboxPoint = Vector2.new(
    textbox._region.Rect.X + 2,
    textbox._region.Rect.Y + 2
)
userInputService.MouseLocation = textboxPoint
userInputService.InputBegan:Fire({
    UserInputType = Enum.UserInputType.MouseButton1,
    KeyCode = Enum.KeyCode.Unknown,
    Position = { X = textboxPoint.X, Y = textboxPoint.Y, Z = 0 },
}, false)
userInputService.InputBegan:Fire({
    UserInputType = Enum.UserInputType.Keyboard,
    KeyCode = Enum.KeyCode.A,
    Position = { X = 0, Y = 0, Z = 0 },
}, false)
assert(textbox:GetValue() == "Texta", "textbox should receive keyboard input")
assert(textbox._caret.Object.From.X == textbox._x + 13 + 5 * 5)
userInputService.InputEnded:Fire({
    UserInputType = Enum.UserInputType.Keyboard,
    KeyCode = Enum.KeyCode.A,
    Position = { X = 0, Y = 0, Z = 0 },
})
userInputService.InputBegan:Fire({
    UserInputType = Enum.UserInputType.Keyboard,
    KeyCode = Enum.KeyCode.LeftShift,
    Position = { X = 0, Y = 0, Z = 0 },
}, false)
userInputService.InputBegan:Fire({
    UserInputType = Enum.UserInputType.Keyboard,
    KeyCode = Enum.KeyCode.B,
    Position = { X = 0, Y = 0, Z = 0 },
}, false)
assert(textbox:GetValue() == "TextaB", "shift should produce uppercase text")
userInputService.InputEnded:Fire({
    UserInputType = Enum.UserInputType.Keyboard,
    KeyCode = Enum.KeyCode.B,
    Position = { X = 0, Y = 0, Z = 0 },
})
userInputService.InputEnded:Fire({
    UserInputType = Enum.UserInputType.Keyboard,
    KeyCode = Enum.KeyCode.LeftShift,
    Position = { X = 0, Y = 0, Z = 0 },
})
assert(Nephren._keysDown[Enum.KeyCode.LeftShift] == nil)
userInputService.InputBegan:Fire({
    UserInputType = Enum.UserInputType.Keyboard,
    KeyCode = Enum.KeyCode.CapsLock,
    Position = { X = 0, Y = 0, Z = 0 },
}, false)
userInputService.InputEnded:Fire({
    UserInputType = Enum.UserInputType.Keyboard,
    KeyCode = Enum.KeyCode.CapsLock,
    Position = { X = 0, Y = 0, Z = 0 },
})
userInputService.InputBegan:Fire({
    UserInputType = Enum.UserInputType.Keyboard,
    KeyCode = Enum.KeyCode.C,
    Position = { X = 0, Y = 0, Z = 0 },
}, false)
assert(textbox:GetValue() == "TextaBC", "caps lock should produce uppercase text")
userInputService.InputEnded:Fire({
    UserInputType = Enum.UserInputType.Keyboard,
    KeyCode = Enum.KeyCode.C,
    Position = { X = 0, Y = 0, Z = 0 },
})
userInputService.InputBegan:Fire({
    UserInputType = Enum.UserInputType.Keyboard,
    KeyCode = Enum.KeyCode.LeftShift,
    Position = { X = 0, Y = 0, Z = 0 },
}, false)
userInputService.InputBegan:Fire({
    UserInputType = Enum.UserInputType.Keyboard,
    KeyCode = Enum.KeyCode.D,
    Position = { X = 0, Y = 0, Z = 0 },
}, false)
assert(textbox:GetValue() == "TextaBCd", "shift should invert caps lock")
userInputService.InputEnded:Fire({
    UserInputType = Enum.UserInputType.Keyboard,
    KeyCode = Enum.KeyCode.D,
    Position = { X = 0, Y = 0, Z = 0 },
})
userInputService.InputEnded:Fire({
    UserInputType = Enum.UserInputType.Keyboard,
    KeyCode = Enum.KeyCode.LeftShift,
    Position = { X = 0, Y = 0, Z = 0 },
})
userInputService.InputBegan:Fire({
    UserInputType = Enum.UserInputType.Keyboard,
    KeyCode = Enum.KeyCode.CapsLock,
    Position = { X = 0, Y = 0, Z = 0 },
}, false)
userInputService.InputEnded:Fire({
    UserInputType = Enum.UserInputType.Keyboard,
    KeyCode = Enum.KeyCode.CapsLock,
    Position = { X = 0, Y = 0, Z = 0 },
})
assert(Nephren._capsLock == false)
assert(textbox._caret.Object.From.X == textbox._x + 13 + 8 * 5)
textbox:SetValue("abcdefghij", true)
userInputService.InputBegan:Fire({
    UserInputType = Enum.UserInputType.Keyboard,
    KeyCode = Enum.KeyCode.Backspace,
    Position = { X = 0, Y = 0, Z = 0 },
}, false)
assert(textbox:GetValue() == "abcdefghi", "backspace should delete immediately")
assert(Nephren._deleteRepeat ~= nil)
userInputService.InputBegan:Fire({
    UserInputType = Enum.UserInputType.Keyboard,
    KeyCode = Enum.KeyCode.Backspace,
    Position = { X = 0, Y = 0, Z = 0 },
}, false)
assert(textbox:GetValue() == "abcdefghi", "host key repeat should not double-delete")
runService.RenderStepped:Fire(0.30)
assert(textbox:GetValue() == "abcdefghi", "delete repeat should respect its initial delay")
runService.RenderStepped:Fire(0.13)
assert(textbox:GetValue() == "abcdefgh")
assert(Nephren._deleteRepeat.Interval < 0.12)
runService.RenderStepped:Fire(0.30)
assert(#textbox:GetValue() < 8, "held deletion should accelerate")
local valueAfterHeldDelete = textbox:GetValue()
userInputService.InputEnded:Fire({
    UserInputType = Enum.UserInputType.Keyboard,
    KeyCode = Enum.KeyCode.Backspace,
    Position = { X = 0, Y = 0, Z = 0 },
})
assert(Nephren._deleteRepeat == nil)
runService.RenderStepped:Fire(1)
assert(textbox:GetValue() == valueAfterHeldDelete, "deletion should stop on key release")
textbox:SetValue("XYZ", true)
userInputService.InputBegan:Fire({
    UserInputType = Enum.UserInputType.Keyboard,
    KeyCode = Enum.KeyCode.Delete,
    Position = { X = 0, Y = 0, Z = 0 },
}, false)
assert(textbox:GetValue() == "XY", "delete should remove the trailing character")
userInputService.InputEnded:Fire({
    UserInputType = Enum.UserInputType.Keyboard,
    KeyCode = Enum.KeyCode.Delete,
    Position = { X = 0, Y = 0, Z = 0 },
})
assert(Nephren._deleteRepeat == nil)
userInputService.InputBegan:Fire({
    UserInputType = Enum.UserInputType.Keyboard,
    KeyCode = Enum.KeyCode.Return,
    Position = { X = 0, Y = 0, Z = 0 },
}, false)

dropdown:OpenPopup()
assert(dropdown.Open == true)
assert(dropdown._activeGradient.Parts[1].Object.Visible == true)
assert(dropdown._activeGradientCorners[1].Object.Visible == true)
assert(math.abs(dropdown._activeGradient.StartColor.R - window.Theme.Accent.R * 0.20) < 0.0001)
assert(math.abs(dropdown._activeGradient.EndColor.R - window.Theme.AccentEnd.R * 0.30) < 0.0001)
assert(dropdown._popupOuter.Size.Y == 110)
assert(dropdown._popupOuter.Position.Y == dropdown._y + 48)
assert(dropdown._popupStroke._kind == "RoundedRect")
dropdown:SetValue("Two")
assert(window.Flags.Dropdown == "Two")
picker:OpenPopup()
assert(picker.Open == true)
assert(dropdown.Open == false, "opening one popup should close the previous popup")
assert(dropdown._activeGradient.Parts[1].Object.Visible == false)
assert(dropdown._activeGradientCorners[1].Object.Visible == false)
assert(picker._popupOuter.Size.X == 180)
assert(picker._popupOuter.Size.Y == 224)
assert(picker._swatchInner._kind == "Gradient")
assert(picker._crosshairH.Object.Visible == true)
picker:SetRainbow(true)
picker:_rainbowStep(0.1)
picker:SetValue(Color3.fromRGB(0, 255, 0))
picker:_focusField("HEX")
picker._editText = "#112233"
picker:Blur(true)
assert(math.floor(picker.Value.R * 255 + 0.5) == 17)
assert(math.floor(picker.Value.G * 255 + 0.5) == 34)
assert(math.floor(picker.Value.B * 255 + 0.5) == 51)
window:SetPosition(Vector2.new(100, 120))
window:Toggle()
assert(section._outer.Parts[1].Object.Visible == false)
window:Toggle()
assert(section._outer.Parts[1].Object.Visible == true)

assert(created > 700, "expected the gradient picker to create its drawing tiles")
Nephren:Unload()
assert(removed == created, "all owned Drawing objects should be removed")

print(string.format("smoke test passed (%d drawings)", created))
