-- Minimal Roblox/Luau/Drawing compatibility layer for exercising Nephren in Lua 5.3.

math.clamp = math.clamp
	or function(value, minimum, maximum)
		assert(minimum <= maximum, "minimum must not exceed maximum")
		return math.max(minimum, math.min(maximum, value))
	end

math.round = math.round
	or function(value)
		if value >= 0 then
			return math.floor(value + 0.5)
		end
		return math.ceil(value - 0.5)
	end

table.clear = table.clear
	or function(source)
		for key in pairs(source) do
			source[key] = nil
		end
	end

table.clone = table.clone
	or function(source)
		local result = {}
		for key, value in pairs(source) do
			result[key] = value
		end
		return result
	end

table.create = table.create
	or function(count, value)
		local result = {}
		if value ~= nil then
			for index = 1, count do
				result[index] = value
			end
		end
		return result
	end

table.find = table.find
	or function(source, wanted, startIndex)
		for index = startIndex or 1, #source do
			if source[index] == wanted then
				return index
			end
		end
		return nil
	end

local vectorMeta = {}
vectorMeta.__index = vectorMeta
vectorMeta.__add = function(left, right)
	return Vector2.new(left.X + right.X, left.Y + right.Y)
end
vectorMeta.__sub = function(left, right)
	return Vector2.new(left.X - right.X, left.Y - right.Y)
end
vectorMeta.__mul = function(left, right)
	if type(left) == "number" then
		return Vector2.new(left * right.X, left * right.Y)
	end
	if type(right) == "number" then
		return Vector2.new(left.X * right, left.Y * right)
	end
	return Vector2.new(left.X * right.X, left.Y * right.Y)
end

Vector2 = {}
function Vector2.new(x, y)
	return setmetatable({ X = x, Y = y }, vectorMeta)
end

function vectorMeta:Floor()
	return Vector2.new(math.floor(self.X), math.floor(self.Y))
end

function vectorMeta:Max(...)
	local x, y = self.X, self.Y
	for _, vector in ipairs({ ... }) do
		x = math.max(x, vector.X)
		y = math.max(y, vector.Y)
	end
	return Vector2.new(x, y)
end

Rect = {}
function Rect.new(first, second, third, fourth)
	if first == nil then
		return {
			Min = Vector2.new(0, 0),
			Max = Vector2.new(0, 0),
			Width = 0,
			Height = 0,
		}
	end

	local minimum
	local maximum
	if type(first) == "table" then
		minimum = first
		maximum = second
	else
		minimum = Vector2.new(first, second)
		maximum = Vector2.new(third, fourth)
	end
	return {
		Min = minimum,
		Max = maximum,
		Width = maximum.X - minimum.X,
		Height = maximum.Y - minimum.Y,
	}
end

local colorMeta = {}
colorMeta.__index = colorMeta

Color3 = {}
function Color3.new(r, g, b)
	return setmetatable({ R = r or 0, G = g or 0, B = b or 0 }, colorMeta)
end

function Color3.fromRGB(r, g, b)
	return Color3.new(r / 255, g / 255, b / 255)
end

function Color3.fromHex(hexadecimal)
	local text = string.gsub(hexadecimal, "^#", "")
	if #text == 3 then
		text = string.sub(text, 1, 1)
			.. string.sub(text, 1, 1)
			.. string.sub(text, 2, 2)
			.. string.sub(text, 2, 2)
			.. string.sub(text, 3, 3)
			.. string.sub(text, 3, 3)
	end
	assert(#text == 6 and string.match(text, "^[%da-fA-F]+$"), "invalid hex color")
	return Color3.fromRGB(
		tonumber(string.sub(text, 1, 2), 16),
		tonumber(string.sub(text, 3, 4), 16),
		tonumber(string.sub(text, 5, 6), 16)
	)
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

function colorMeta:Lerp(other, alpha)
	return Color3.new(
		self.R + (other.R - self.R) * alpha,
		self.G + (other.G - self.G) * alpha,
		self.B + (other.B - self.B) * alpha
	)
end

function colorMeta:ToHex()
	return string.format(
		"%02x%02x%02x",
		math.round(self.R * 255),
		math.round(self.G * 255),
		math.round(self.B * 255)
	)
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
	KeyCodeStringFormat = enumGroup(),
	UserInputType = enumGroup(),
}

local function event()
	local value = { Listeners = {} }
	function value:Connect(callback)
		local connection = {
			Connected = true,
		}
		function connection:Disconnect()
			self.Connected = false
		end
		table.insert(self.Listeners, {
			Callback = callback,
			Connection = connection,
		})
		return connection
	end
	function value:Fire(...)
		for _, listener in ipairs(self.Listeners) do
			if listener.Connection.Connected then
				listener.Callback(...)
			end
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

local keyCodeStrings = {
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
	Space = "Space",
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

local abbreviatedKeyNames = {
	LeftControl = "LCtrl",
	RightControl = "RCtrl",
	LeftShift = "LShift",
	RightShift = "RShift",
	LeftAlt = "LAlt",
	RightAlt = "RAlt",
	Backspace = "Bksp",
	Escape = "Esc",
	CapsLock = "Caps",
	PageUp = "PgUp",
	PageDown = "PgDn",
}

function userInputService:GetStringForKeyCode(keyCode, format)
	local name = keyCode.Name
	if format == Enum.KeyCodeStringFormat.Abbreviated then
		return abbreviatedKeyNames[name] or keyCodeStrings[name] or name
	end
	return keyCodeStrings[name] or name
end

local runService = {
	RenderStepped = event(),
}

local workspaceService = {
	CurrentCamera = {
		ViewportSize = Vector2.new(1920, 1080),
	},
}

game = {}
function game:GetService(name)
	if name == "UserInputService" then
		return userInputService
	elseif name == "RunService" then
		return runService
	elseif name == "Workspace" then
		return workspaceService
	end
	error("unknown service: " .. tostring(name))
end

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
assert(window._titleDrawing._object.Font == Drawing.Fonts.Plex)
assert(window._titleDrawing._object.Size == 14)
assert(window._titleDrawing._object.Position.Y == window.Position.Y + 10)
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
assert(section._outer._kind == "RoundedRectangle")
assert(section._outer._reinforceCorners == true)
assert(#section._outer._parts == 10)
assert(section._outer._parts[3]._object.Position.X == section._outer._parts[7]._object.Position.X)
assert(section._outer._parts[3]._object.Position.Y == section._outer._parts[7]._object.Position.Y)
assert(section._outer._parts[3]._object.Radius == section._outer._parts[7]._object.Radius)
assert(section._outer._parts[3]._object.Filled == true)
assert(section._outer._parts[7]._object.Filled == false)
assert(#section._inner._parts == 6)
assert(section._accent._kind == "Gradient")
assert(section._accent._radius == 3)
assert(section._accent._radius == tab._accent._radius)
assert(section._accent._segments == tab._accent._segments)
assert(section._x == window.Position.X + 10)
assert(section._bodyY == window.Position.Y + window.Theme.HeaderHeight + 36)
assert(section._width == 276)
assert(section._outer._color == window.Theme.Border)
assert(section._outer._position.X == section._x - 1)
assert(section._outer._position.Y == section._bodyY - 1)
assert(section._outer._size.X == section._width + 2)
assert(section._outer._size.Y == section:_bodyHeight() + 2)
assert(section._accent._position.X == section._x)
assert(section._accent._position.Y == section._bodyY)
assert(section._accent._size.X == section._width)
assert(section._accent._size.Y == 4)
assert(section._title._object.Size == 14)
assert(section._title._object.Position.Y == section._bodyY - 18)
assert(section._accent._startCap._object.Radius == 2)
assert(section._accent._startCap._object.Position.Y == section._bodyY + 2)
assert(section._outline == nil)
assert(section._stroke._color == window.Theme.Stroke)
assert(section._stroke._position.X == section._x)
assert(section._stroke._position.Y == section._bodyY + 2)
assert(section._stroke._size.X == section._width)
assert(section._stroke._size.Y == section:_bodyHeight() - 2)
assert(section._inner._position.X == section._x + 1)
assert(section._inner._position.Y == section._bodyY + 3)
assert(tab._accent._radius == 3)
assert(tab._accent._position.Y == window.Position.Y + 3)
assert(tab._accent._size.X == tab.Width)
assert(tab._accent._size.Y == 6)
assert(tab._stroke._position.Y == window.Position.Y + 5)
assert(tab._inner._position.Y == window.Position.Y + 6)
assert(tab._bottomMask._object.Kind == "Square")
assert(tab._bottomMask._object.Visible == true)
assert(tab._bottomMask._object.Color == window.Theme.Background)
assert(tab._bottomMask._object.Position.X == window.Position.X + window.Theme.TitleWidth)
assert(tab._bottomMask._object.Position.Y == window.Position.Y + window.Theme.HeaderHeight - 1)
assert(tab._bottomMask._object.Size.X == tab.Width - 2)
assert(tab._accent == otherTab._accent)
assert(tab._stroke == otherTab._stroke)
assert(tab._inner == otherTab._inner)
assert(tab._bottomMask == otherTab._bottomMask)
otherTab:Select()
assert(tab._accent._parts[1]._object.Visible == true)
assert(tab._bottomMask._object.Visible == true)
assert(otherTab._accent._parts[1]._object.Visible == true)
assert(otherTab._bottomMask._object.Visible == true)
assert(otherTab._accent._position.X == otherTab._headerX)
assert(otherTab._bottomMask._object.Position.X == otherTab._headerX)
tab:Select()
assert(tab._accent._position.X == tab._headerX)
assert(tab._text._object.Size == 14)
assert(tab._text._object.Position.Y == window.Position.Y + 10)
assert(slider._fill._kind == "Gradient")
assert(slider._trackOuter._kind == "RoundedRectangle")
assert(slider._trackBackground._kind == "RoundedRectangle")
assert(textbox._inner._kind == "RoundedRectangle")
assert(listbox._outer._kind == "RoundedRectangle")
assert(textbox._inner._color == window.Theme.Input)
assert(spinner._valueInner._color == window.Theme.Input)
assert(listbox._inner._color == window.Theme.Input)
assert(button._outer._color == window.Theme.ControlBorder)
assert(button._highlight._color == window.Theme.ControlStroke)
assert(textbox._highlight._color == window.Theme.InputStroke)
assert(listbox._stroke._color == window.Theme.InputStroke)
assert(button._inner._radius == 1)
assert(dropdown._inner._radius == 1)
assert(textbox._inner._radius == 1)
assert(button._outer._size.X == 200)
assert(button._outer._size.Y == 27)
assert(dropdown._outer._size.X == 200)
assert(dropdown._activeGradient == nil)
assert(dropdown._popupCreated ~= true)
assert(dropdown._popupLayoutDirty == true)
assert(textbox._outer._size.X == 198)
assert(listbox._outer._size.X == 198)
assert(listbox._outer._size.Y == 127)
assert(multibox._glyph == nil)
assert(#multibox._glyphLines == 3)
assert(#multibox._glyphOutlineLines == 3)
assert(multibox._activeGradient == nil)
assert(multibox._popupCreated ~= true)
assert(multibox._popupLayoutDirty == true)
for index = 1, 3 do
	assert(multibox._glyphLines[index]._object.Kind == "Line")
	assert(multibox._glyphLines[index]._object.Thickness == 1)
	assert(multibox._glyphOutlineLines[index]._object.Thickness == 3)
	assert(
		multibox._glyphLines[index]._object.To.X - multibox._glyphLines[index]._object.From.X == 5
	)
	assert(multibox._glyphLines[index]._object.From.Y == multibox._y + 31 + (index - 1) * 2)
end
assert(picker._swatchOuter._object.Kind == "Square")
assert(picker._swatchInner._radius == 0)
assert(picker._swatchOuter._object.Size.X == 18)
assert(picker._swatchOuter._object.Size.Y == 8)
assert(checkbox._boxOuter._size.X == 14)
assert(checkbox._check._kind == "Gradient")
assert(checkbox._check._size.X == 8)
assert(checkbox._check._size.Y == 8)
assert(checkbox._check._startColor == window.Theme.Accent)
assert(checkbox._check._endColor == window.Theme.AccentEnd)
assert(#checkbox._checkCorners == 4)
assert(checkboxKeybind.Mode == "Toggle")
assert(spinner._valueOuter._size.X == 144)
assert(spinner._minusOuter._size.X == 27)
assert(spinner._plusOuter._size.X == 27)
assert(button._text._object.Size == 14)
assert(dropdown._label._object.Size == 14)
assert(dropdown._valueText._object.Size == 14)
assert(dropdown._glyph._object.Size == 14)
assert(slider._label._object.Size == 14)
assert(slider._valueText._object.Size == 14)
assert(multibox._label._object.Size == 14)
assert(multibox._valueText._object.Size == 14)
assert(spinner._label._object.Size == 14)
assert(spinner._valueText._object.Size == 14)
assert(spinner._minusText._object.Size == 14)
assert(spinner._plusText._object.Size == 14)
assert(checkbox._label._object.Size == 14)
assert(checkboxKeybind._text._object.Size == 12)
assert(textbox._label._object.Size == 14)
assert(textbox._valueText._object.Size == 14)
assert(listbox._label._object.Size == 14)
assert(listbox._rows[1]._text._object.Size == 14)
assert(dropdown._x == section._x + 9)
assert(dropdown._y == section._bodyY + 12)
assert(dropdown._label._object.Position.Y == dropdown._y + 4)
assert(dropdown._outer._position.Y == dropdown._y + 20)
assert(dropdown._valueText._object.Position.Y == dropdown._y + 28)
assert(dropdown._glyph._object.Position.Y == dropdown._y + 25)
assert(slider._x == section._x + 9)
assert(slider._y == section._bodyY + 72)
assert(slider._label._object.Position.Y == slider._y - 2)
assert(slider._trackOuter._position.Y == slider._y + 13)
assert(slider._trackBackground._position.Y == slider._y + 15)
assert(slider._valueText._object.Position.Y == slider._y + 20)
assert(button._outer._position.Y == section._bodyY + 105)
assert(button._text._object.Position.Y == button._outer._position.Y + 8)
assert(multibox._y == section._bodyY + 142)
assert(multibox._label._object.Position.Y == multibox._y + 4)
assert(multibox._valueText._object.Position.Y == multibox._y + 28)
assert(spinner._label._object.Position.Y == section._bodyY + 200)
assert(spinner._valueOuter._position.Y == section._bodyY + 215)
assert(spinner._valueText._object.Position.Y == section._bodyY + 222)
assert(spinner._minusText._object.Position.Y == section._bodyY + 222)
assert(spinner._plusText._object.Position.Y == section._bodyY + 222)
assert(checkbox._y == section._bodyY + 250)
assert(checkbox._rowWidth == 251)
assert(checkbox._boxOuter._position.Y == checkbox._y + 4)
assert(checkbox._label._object.Position.X == checkbox._x + 21)
assert(checkbox._label._object.Position.Y == checkbox._y + 5)
assert(checkboxKeybind._x == checkbox._x + 213)
assert(checkboxKeybind._text._object.Position.Y == checkbox._y + 5)
checkboxKeybind:SetValue(Enum.KeyCode.LeftControl, true)
assert(checkboxKeybind._text._object.Text == "[LCtrl]")
checkboxKeybind:SetValue(Enum.KeyCode.H, true)
assert(picker._x == checkbox._x + 233)
assert(picker._swatchOuter._object.Position.Y == checkbox._y + 7)
assert(picker._swatchInner._position.X == checkbox._x + 234)
assert(picker._swatchInner._position.Y == checkbox._y + 8)
assert(picker._popupX == checkbox._x + 76)
assert(picker._popupY == checkbox._y + 19)
assert(picker._popupCreated ~= true)
assert(picker._popupLayoutDirty == true)
assert(textbox._y == section._bodyY + 276)
assert(textbox._label._object.Position.Y == textbox._y + 1)
assert(textbox._outer._position.Y == textbox._y + 16)
assert(textbox._valueText._object.Position.X == textbox._x + 13)
assert(textbox._valueText._object.Position.Y == textbox._y + 23)
assert(listbox._y == section._bodyY + 327)
assert(listbox._label._object.Position.Y == listbox._y + 1)
assert(listbox._outer._position.Y == listbox._y + 16)
assert(listbox._rows[1]._text._object.Position.Y == listbox._y + 24)
assert(slider._height == 33)

local halfFill = math.floor((slider._width - 4) * 0.5 + 0.5)
assert(slider._fill._size.X == halfFill)
assert(slider._valueText._object.Position.X == slider._x + 2 + halfFill - 3)
slider:SetValue(0, true)
assert(slider._fill._parts[1]._object.Visible == false)
slider:SetValue(10, true)
assert(slider._fill._size.X == slider._width - 4)
slider:SetValue(5, true)

assert(created < 500, "closed popups should be allocated lazily")
assert(multibox._activeGradient == nil)
multibox:OpenPopup()
assert(multibox.Open == true)
assert(multibox._popupCreated == true)
assert(multibox._activeGradient._kind == "Gradient")
assert(multibox._activeGradient._radius == 0)
assert(#multibox._activeGradientCorners == 4)
assert(multibox._popupLayoutDirty == false)
assert(multibox._activeGradient._position.X == multibox._x + 2)
assert(multibox._activeGradient._position.Y == multibox._y + 22)
assert(multibox._activeGradient._size.X == multibox._width - 4)
assert(multibox._activeGradient._size.Y == 23)
assert(multibox._activeGradient._parts[1]._object.Visible == true)
assert(multibox._activeGradientCorners[1]._object.Visible == true)
assert(math.abs(multibox._activeGradient._startColor.R - window.Theme.Accent.R * 0.20) < 0.0001)
assert(math.abs(multibox._activeGradient._endColor.R - window.Theme.AccentEnd.R * 0.30) < 0.0001)
assert(multibox._valueText._object.Color == window.Theme.Text)
for index = 1, 3 do
	assert(multibox._glyphLines[index]._object.Color == window.Theme.MenuIcon)
end
multibox:Close()
assert(multibox._activeGradient._parts[1]._object.Visible == false)
assert(multibox._activeGradientCorners[1]._object.Visible == false)

local checkboxPoint = Vector2.new(
	checkbox._region._rectangle._minimum.X + 2,
	checkbox._region._rectangle._minimum.Y + 2
)
userInputService.MouseLocation = checkboxPoint
userInputService.InputBegan:Fire({
	UserInputType = Enum.UserInputType.MouseButton1,
	KeyCode = Enum.KeyCode.Unknown,
	Position = { X = checkboxPoint.X, Y = checkboxPoint.Y, Z = 0 },
}, false)
assert(window.Flags.Checkbox == true, "checkbox should respond through UserInputService")
assert(checkbox._check._parts[1]._object.Visible == true)
assert(checkbox._checkCorners[1]._object.Visible == true)

userInputService.InputBegan:Fire({
	UserInputType = Enum.UserInputType.Keyboard,
	KeyCode = Enum.KeyCode.H,
	Position = { X = 0, Y = 0, Z = 0 },
}, false)
assert(window.Flags.Checkbox == false, "checkbox keybind should update its parent state")
assert(checkbox._check._parts[1]._object.Visible == false)
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
assert(checkbox._check._parts[1]._object.Visible == true)
userInputService.InputEnded:Fire({
	UserInputType = Enum.UserInputType.Keyboard,
	KeyCode = Enum.KeyCode.H,
	Position = { X = 0, Y = 0, Z = 0 },
})

local textboxPoint = Vector2.new(
	textbox._region._rectangle._minimum.X + 2,
	textbox._region._rectangle._minimum.Y + 2
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
assert(textbox._caret._object.From.X == textbox._x + 13 + 5 * 5)
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
assert(textbox._caret._object.From.X == textbox._x + 13 + 8 * 5)
keyCodeStrings.Q = "A"
userInputService.InputBegan:Fire({
	UserInputType = Enum.UserInputType.Keyboard,
	KeyCode = Enum.KeyCode.Q,
	Position = { X = 0, Y = 0, Z = 0 },
}, false)
assert(
	textbox:GetValue() == "TextaBCda",
	"textbox input should use the keyboard-layout-aware Roblox key string"
)
userInputService.InputEnded:Fire({
	UserInputType = Enum.UserInputType.Keyboard,
	KeyCode = Enum.KeyCode.Q,
	Position = { X = 0, Y = 0, Z = 0 },
})
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
assert(Nephren._deleteRepeat._interval < 0.12)
runService.RenderStepped:Fire(0.30)
assert(#textbox:GetValue() < 8, "held deletion should accelerate")
local valueAfterHeldDelete = textbox:GetValue()
userInputService.InputEnded:Fire({
	UserInputType = Enum.UserInputType.Keyboard,
	KeyCode = Enum.KeyCode.Backspace,
	Position = { X = 0, Y = 0, Z = 0 },
})
assert(Nephren._deleteRepeat == nil)
assert(Nephren._renderConnection == nil)
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
assert(dropdown._popupCreated == true)
assert(dropdown._activeGradient._kind == "Gradient")
assert(dropdown._activeGradient._radius == 0)
assert(#dropdown._activeGradientCorners == 4)
assert(dropdown._popupLayoutDirty == false)
assert(dropdown._activeGradient._position.X == dropdown._x + 2)
assert(dropdown._activeGradient._position.Y == dropdown._y + 22)
assert(dropdown._activeGradient._size.X == dropdown._width - 4)
assert(dropdown._activeGradient._size.Y == 23)
assert(dropdown._activeGradient._parts[1]._object.Visible == true)
assert(dropdown._activeGradientCorners[1]._object.Visible == true)
assert(math.abs(dropdown._activeGradient._startColor.R - window.Theme.Accent.R * 0.20) < 0.0001)
assert(math.abs(dropdown._activeGradient._endColor.R - window.Theme.AccentEnd.R * 0.30) < 0.0001)
assert(dropdown._popupOuter._size.Y == 110)
assert(dropdown._popupOuter._position.Y == dropdown._y + 48)
assert(dropdown._popupStroke._kind == "RoundedRectangle")
dropdown:SetValue("Two")
assert(window.Flags.Dropdown == "Two")
picker:OpenPopup()
assert(picker.Open == true)
assert(picker._popupCreated == true)
assert(picker._popupLayoutDirty == false)
assert(picker._rainbowText._object.Size == 14)
assert(picker._redGreenBlueText._object.Size == 14)
assert(picker._hexadecimalText._object.Size == 14)
assert(picker._rainbowText._object.Position.Y == picker._popupY + 137)
assert(picker._redGreenBlueText._object.Position.Y == picker._popupY + 165)
assert(picker._hexadecimalText._object.Position.Y == picker._popupY + 197)
assert(dropdown.Open == false, "opening one popup should close the previous popup")
assert(dropdown._activeGradient._parts[1]._object.Visible == false)
assert(dropdown._activeGradientCorners[1]._object.Visible == false)
assert(picker._popupOuter._size.X == 180)
assert(picker._popupOuter._size.Y == 224)
assert(picker._swatchInner._kind == "Gradient")
assert(picker._crosshairHorizontal._object.Visible == true)
picker:SetRainbow(true)
picker:_rainbowStep(0.1)
picker:SetValue(Color3.fromRGB(0, 255, 0))
picker:_focusField("HEX")
picker._editText = "#112233"
picker:Blur(true)
assert(math.floor(picker.Value.R * 255 + 0.5) == 17)
assert(math.floor(picker.Value.G * 255 + 0.5) == 34)
assert(math.floor(picker.Value.B * 255 + 0.5) == 51)
assert(picker:_hexadecimalString() == "#112233")
dropdown:SetValues({ "Only" })
assert(dropdown:GetValue() == nil and window.Flags.Dropdown == nil)
table.insert(dropdown.Values, "Direct Dropdown")
dropdown:SetValue("Direct Dropdown")
assert(dropdown:GetValue() == "Direct Dropdown")
dropdown:SetValue("Only")
table.remove(dropdown.Values, 2)
dropdown:SetValue("Direct Dropdown")
assert(dropdown:GetValue() == "Only")
table.insert(multibox.Values, "Direct Multi")
multibox:SetValue({ "Direct Multi" })
assert(multibox:GetValue()[1] == "Direct Multi")
table.insert(listbox.Values, "Direct Listbox")
listbox:SetValue("Direct Listbox")
assert(listbox:GetValue() == "Direct Listbox")
local originalAccent = window.Theme.Accent
local originalAccentEnd = window.Theme.AccentEnd
local originalControlStroke = window.Theme.ControlStroke
local originalControlBorder = window.Theme.ControlBorder
local originalMenuIcon = window.Theme.MenuIcon
window.Theme.Accent = Color3.fromRGB(12, 34, 56)
window.Theme.AccentEnd = Color3.fromRGB(65, 43, 21)
window.Theme.ControlStroke = Color3.fromRGB(21, 22, 23)
window.Theme.ControlBorder = Color3.fromRGB(24, 25, 26)
window.Theme.MenuIcon = Color3.fromRGB(27, 28, 29)
checkbox:_updateStyle()
dropdown:_updateStyle()
multibox:_updateStyle()
assert(checkbox._check._startColor == window.Theme.Accent)
assert(dropdown._activeGradient._startColor.R == window.Theme.Accent.R * 0.20)
assert(dropdown._activeGradientCorners[1].Color == window.Theme.ControlStroke)
assert(multibox._glyphOutlineLines[1].Color == window.Theme.ControlBorder)
assert(multibox._glyphLines[1].Color == window.Theme.MenuIcon)
window.Theme.Accent = originalAccent
window.Theme.AccentEnd = originalAccentEnd
window.Theme.ControlStroke = originalControlStroke
window.Theme.ControlBorder = originalControlBorder
window.Theme.MenuIcon = originalMenuIcon
checkbox:_updateStyle()
dropdown:_updateStyle()
multibox:_updateStyle()
window:SetPosition(Vector2.new(100, 120))
window:Toggle()
assert(section._outer._parts[1]._object.Visible == false)
window:Toggle()
assert(section._outer._parts[1]._object.Visible == true)
window:SetSize(Vector2.new(100, 100))
assert(window.Size.X == 360 and window.Size.Y == 260)

local autoSection = otherTab:AddSection({ Title = "Auto", Side = "Left" })
local followingSection = otherTab:AddSection({ Title = "Following", Side = "Left" })
local firstAutoControl = autoSection:AddLabel({ Text = "First" })
assert(autoSection._x == nil, "inactive tabs should defer content layout")
spinner:Focus()
checkboxKeybind:_startBinding()
otherTab:Select()
assert(Nephren._focusedTextbox == nil and spinner._editing == false)
assert(Nephren._bindingKeybind == nil and checkboxKeybind._binding == false)
assert(autoSection._x ~= nil)
local followingY = followingSection._y
local addedAutoControl = autoSection:AddLabel({ Text = "Second" })
assert(followingSection._y == followingY + addedAutoControl._height)
assert(#autoSection.Controls == 2)
addedAutoControl:Destroy()
assert(followingSection._y == followingY)
assert(#autoSection.Controls == 1 and autoSection.Controls[1] == firstAutoControl)

tab:Select()
local visibilitySection = tab:AddSection({ Title = "Visibility Mutation", Side = "Right" })
local addedDuringHide
local destroyingSpinner = visibilitySection:AddSpinner({
	Text = "Destroy During Hide",
	Min = 0,
	Max = 10,
	Callback = function(_, control)
		addedDuringHide = section:AddCheckbox({ Text = "Added During Hide" })
		control:Destroy()
	end,
})
local visibilityFollower = visibilitySection:AddCheckbox({ Text = "Visibility Follower" })
destroyingSpinner:Focus()
destroyingSpinner._editText = "2"
otherTab:Select()
assert(destroyingSpinner._destroyed == true)
assert(addedDuringHide and addedDuringHide._parentVisible == false)
assert(addedDuringHide._label._object.Visible == false)
assert(addedDuringHide._region._activeIndex == nil)
assert(visibilityFollower._parentVisible == false)
assert(visibilityFollower._label._object.Visible == false)
assert(visibilityFollower._region._activeIndex == nil)

tab:Select()
local reentrantSpinner = visibilitySection:AddSpinner({
	Text = "Reentrant Selection",
	Min = 0,
	Max = 10,
	Callback = function()
		tab:Select()
	end,
})
reentrantSpinner:Focus()
reentrantSpinner._editText = "3"
otherTab:Select()
assert(window.SelectedTab == tab, "the latest reentrant tab selection should win")
assert(visibilityFollower._parentVisible == true)
assert(visibilityFollower._label._object.Visible == true)
assert(visibilityFollower._region._activeIndex ~= nil)
otherTab:Select()

local duplicateA = autoSection:AddCheckbox({
	Text = "Duplicate A",
	Default = false,
	Flag = "Duplicate",
})
local duplicateB = autoSection:AddCheckbox({
	Text = "Duplicate B",
	Default = true,
	Flag = "Duplicate",
})
assert(window.Flags.Duplicate == true and Nephren.Flags.Duplicate == true)
duplicateA:SetValue(false)
assert(window.Flags.Duplicate == false and Nephren.Flags.Duplicate == false)
duplicateA:Destroy()
assert(window.Flags.Duplicate == true and Nephren.Flags.Duplicate == true)
window:SetValue("Duplicate", false)
assert(duplicateB:GetValue() == false)
local duplicateC = autoSection:AddCheckbox({
	Text = "Duplicate C",
	Default = true,
	Flag = "Duplicate",
})
assert(window.Flags.Duplicate == true and Nephren.Flags.Duplicate == true)
duplicateC:Destroy()
assert(window.Flags.Duplicate == false and Nephren.Flags.Duplicate == false)

local holdEvents = {}
local holdKeybind = autoSection:AddKeybind({
	Text = "Hold",
	Default = Enum.KeyCode.J,
	Mode = "Hold",
	Callback = function(active)
		table.insert(holdEvents, active)
	end,
})
userInputService.InputBegan:Fire({
	UserInputType = Enum.UserInputType.Keyboard,
	KeyCode = Enum.KeyCode.J,
	Position = { X = 0, Y = 0, Z = 0 },
}, false)
assert(holdKeybind._addon.State == true and holdEvents[#holdEvents] == true)
local holdEventCount = #holdEvents
holdKeybind:SetValue(Enum.KeyCode.J)
assert(holdKeybind._addon.State == true and #holdEvents == holdEventCount)
holdKeybind:SetValue(Enum.KeyCode.K)
assert(holdKeybind._addon.State == false and holdEvents[#holdEvents] == false)

local destroyOnRebind
destroyOnRebind = autoSection:AddKeybind({
	Text = "Destroy On Rebind",
	Default = Enum.KeyCode.Q,
	Mode = "Hold",
	Flag = "DestroyOnRebind",
	Callback = function(active)
		if not active then
			destroyOnRebind:Destroy()
		end
	end,
})
userInputService.InputBegan:Fire({
	UserInputType = Enum.UserInputType.Keyboard,
	KeyCode = Enum.KeyCode.Q,
	Position = { X = 0, Y = 0, Z = 0 },
}, false)
assert(destroyOnRebind._addon.State == true)
destroyOnRebind:SetValue(Enum.KeyCode.R)
assert(destroyOnRebind._destroyed == true)
assert(window.Flags.DestroyOnRebind == nil and Nephren.Flags.DestroyOnRebind == nil)
userInputService.InputEnded:Fire({
	UserInputType = Enum.UserInputType.Keyboard,
	KeyCode = Enum.KeyCode.Q,
	Position = { X = 0, Y = 0, Z = 0 },
})

local reentrantHold
local reentrantHoldRebound = false
reentrantHold = autoSection:AddKeybind({
	Text = "Reentrant Rebind",
	Default = Enum.KeyCode.U,
	Mode = "Hold",
	Flag = "ReentrantRebind",
	Callback = function(active)
		if not active and not reentrantHoldRebound then
			reentrantHoldRebound = true
			reentrantHold:SetValue(Enum.KeyCode.X)
		end
	end,
})
userInputService.InputBegan:Fire({
	UserInputType = Enum.UserInputType.Keyboard,
	KeyCode = Enum.KeyCode.U,
	Position = { X = 0, Y = 0, Z = 0 },
}, false)
assert(reentrantHold._addon.State == true)
reentrantHold:SetValue(Enum.KeyCode.Y)
assert(reentrantHold:GetValue() == Enum.KeyCode.X)
assert(window.Flags.ReentrantRebind == Enum.KeyCode.X)
assert(Nephren.Flags.ReentrantRebind == Enum.KeyCode.X)
userInputService.InputEnded:Fire({
	UserInputType = Enum.UserInputType.Keyboard,
	KeyCode = Enum.KeyCode.U,
	Position = { X = 0, Y = 0, Z = 0 },
})
userInputService.InputBegan:Fire({
	UserInputType = Enum.UserInputType.Keyboard,
	KeyCode = Enum.KeyCode.Y,
	Position = { X = 0, Y = 0, Z = 0 },
}, false)
assert(reentrantHold._addon.State == false)
userInputService.InputEnded:Fire({
	UserInputType = Enum.UserInputType.Keyboard,
	KeyCode = Enum.KeyCode.Y,
	Position = { X = 0, Y = 0, Z = 0 },
})
userInputService.InputBegan:Fire({
	UserInputType = Enum.UserInputType.Keyboard,
	KeyCode = Enum.KeyCode.X,
	Position = { X = 0, Y = 0, Z = 0 },
}, false)
assert(reentrantHold._addon.State == true)
userInputService.InputEnded:Fire({
	UserInputType = Enum.UserInputType.Keyboard,
	KeyCode = Enum.KeyCode.X,
	Position = { X = 0, Y = 0, Z = 0 },
})

local recursiveCheckbox = autoSection:AddCheckbox({ Text = "Recursive Destroy" })
local recursivePicker = recursiveCheckbox:AddColorPicker({
	Default = Color3.fromRGB(255, 255, 255),
})
local recursiveHold = recursiveCheckbox:AddKeybind({
	Default = Enum.KeyCode.L,
	Mode = "Hold",
	Callback = function(active)
		if not active then
			recursiveCheckbox:Destroy()
		end
	end,
})
userInputService.InputBegan:Fire({
	UserInputType = Enum.UserInputType.Keyboard,
	KeyCode = Enum.KeyCode.L,
	Position = { X = 0, Y = 0, Z = 0 },
}, false)
assert(recursiveHold.State == true)
recursiveCheckbox:Destroy()
assert(recursiveCheckbox._destroyed == true and #recursiveCheckbox._addons == 0)
assert(recursiveHold._destroyed == true and recursivePicker._destroyed == true)
userInputService.InputEnded:Fire({
	UserInputType = Enum.UserInputType.Keyboard,
	KeyCode = Enum.KeyCode.L,
	Position = { X = 0, Y = 0, Z = 0 },
})

local deferredKeybind
local deferredKeybindCalls = 0
local mutatingKeybind
mutatingKeybind = autoSection:AddKeybind({
	Text = "Mutating Dispatch",
	Default = Enum.KeyCode.P,
	Callback = function()
		mutatingKeybind:Destroy()
		deferredKeybind = autoSection:AddKeybind({
			Text = "Deferred Dispatch",
			Default = Enum.KeyCode.P,
			Callback = function()
				deferredKeybindCalls = deferredKeybindCalls + 1
			end,
		})
	end,
})
userInputService.InputBegan:Fire({
	UserInputType = Enum.UserInputType.Keyboard,
	KeyCode = Enum.KeyCode.P,
	Position = { X = 0, Y = 0, Z = 0 },
}, false)
assert(mutatingKeybind._destroyed == true and deferredKeybind ~= nil)
assert(deferredKeybindCalls == 0, "new same-key bindings must wait for the next input")
userInputService.InputEnded:Fire({
	UserInputType = Enum.UserInputType.Keyboard,
	KeyCode = Enum.KeyCode.P,
	Position = { X = 0, Y = 0, Z = 0 },
})
userInputService.InputBegan:Fire({
	UserInputType = Enum.UserInputType.Keyboard,
	KeyCode = Enum.KeyCode.P,
	Position = { X = 0, Y = 0, Z = 0 },
}, false)
assert(deferredKeybindCalls == 1)
userInputService.InputEnded:Fire({
	UserInputType = Enum.UserInputType.Keyboard,
	KeyCode = Enum.KeyCode.P,
	Position = { X = 0, Y = 0, Z = 0 },
})

local rainbowPeer = duplicateB:AddColorPicker({
	Default = Color3.fromRGB(255, 255, 255),
	Rainbow = true,
})
picker.Callback = function(_, control)
	control:SetRainbow(false)
end
picker:SetRainbow(true)
local peerHue = rainbowPeer.Hue
runService.RenderStepped:Fire(0.1)
assert(picker.Rainbow == false)
assert(rainbowPeer.Hue ~= peerHue, "rainbow mutation must not skip or crash later pickers")
rainbowPeer:SetRainbow(false)
assert(#Nephren._rainbowPickers == 0 and Nephren._renderConnection == nil)

local mainTabChromeObject = tab._accent._parts[1]._object
local doomedWindow = Nephren:CreateWindow({
	Title = "Doomed",
	Position = Vector2.new(30, 40),
})
local doomedTab = doomedWindow:AddTab("Doomed Tab")
local doomedSection = doomedTab:AddSection("Doomed Section")
assert(doomedTab._accent ~= tab._accent)
local ghostKeybind
local ghostPicker
local ghostPresses = 0
local teardownHold = doomedSection:AddKeybind({
	Default = Enum.KeyCode.M,
	Mode = "Hold",
	Callback = function(active)
		if not active then
			ghostKeybind = doomedSection:AddKeybind({
				Default = Enum.KeyCode.N,
				Callback = function()
					ghostPresses = ghostPresses + 1
				end,
			})
			ghostPicker = doomedSection:AddColorPicker({ Rainbow = true })
		end
	end,
})
userInputService.InputBegan:Fire({
	UserInputType = Enum.UserInputType.Keyboard,
	KeyCode = Enum.KeyCode.M,
	Position = { X = 0, Y = 0, Z = 0 },
}, false)
assert(teardownHold._addon.State == true)
doomedWindow:Destroy()
assert(ghostKeybind == nil and ghostPicker == nil)
assert(#Nephren._rainbowPickers == 0 and Nephren._renderConnection == nil)
assert(mainTabChromeObject.__OBJECT_EXISTS == true)
userInputService.InputEnded:Fire({
	UserInputType = Enum.UserInputType.Keyboard,
	KeyCode = Enum.KeyCode.M,
	Position = { X = 0, Y = 0, Z = 0 },
})
userInputService.InputBegan:Fire({
	UserInputType = Enum.UserInputType.Keyboard,
	KeyCode = Enum.KeyCode.N,
	Position = { X = 0, Y = 0, Z = 0 },
}, false)
assert(ghostPresses == 0, "destroy callbacks must not leave ghost keybinds")
userInputService.InputEnded:Fire({
	UserInputType = Enum.UserInputType.Keyboard,
	KeyCode = Enum.KeyCode.N,
	Position = { X = 0, Y = 0, Z = 0 },
})

tab:Select()
picker:OpenPopup()
picker:_focusField("HEX")
picker._editText = "#445566"
picker.Callback = function(_, control)
	control:Close()
end
picker:Blur(true)
assert(picker.Open == false and picker._editing == nil)

picker:OpenPopup()
picker:_focusField("HEX")
picker._editText = "#556677"
picker.Callback = function()
	window:Show()
end
window:Hide()
assert(window.Visible == true)
assert(section._outer._parts[1]._object.Visible == true)

local teardownCallbacks = 0
picker:OpenPopup()
picker:_focusField("HEX")
picker.Callback = function()
	teardownCallbacks = teardownCallbacks + 1
end

assert(created > 700, "expected all popup renderers to be created after opening")
Nephren:Unload()
assert(teardownCallbacks == 0, "unload should cancel editor callbacks")
assert(removed == created, "all owned Drawing objects should be removed")

local reloadWindow = Nephren:CreateWindow({
	Title = "Reload",
	Position = Vector2.new(0, 0),
})
userInputService.InputBegan:Fire({
	UserInputType = Enum.UserInputType.Keyboard,
	KeyCode = Enum.KeyCode.RightShift,
	Position = { X = 0, Y = 0, Z = 0 },
}, false)
assert(reloadWindow.Visible == false, "reload should install exactly one input handler")
userInputService.InputEnded:Fire({
	UserInputType = Enum.UserInputType.Keyboard,
	KeyCode = Enum.KeyCode.RightShift,
	Position = { X = 0, Y = 0, Z = 0 },
})
Nephren:Unload()
assert(removed == created, "reload cleanup should remove every new drawing")

local nestedWindow = Nephren:CreateWindow({
	Title = "Nested Unload",
	Position = Vector2.new(0, 0),
})
local nestedSection = nestedWindow:AddTab("Nested Tab"):AddSection("Nested Section")
local nestedCheckbox = nestedSection:AddCheckbox({ Text = "Nested Checkbox" })
local nestedPicker = nestedCheckbox:AddColorPicker({ Rainbow = true })
local nestedHold = nestedCheckbox:AddKeybind({
	Default = Enum.KeyCode.O,
	Mode = "Hold",
	Callback = function(active)
		if not active then
			nestedWindow:Destroy()
		end
	end,
})
userInputService.InputBegan:Fire({
	UserInputType = Enum.UserInputType.Keyboard,
	KeyCode = Enum.KeyCode.O,
	Position = { X = 0, Y = 0, Z = 0 },
}, false)
assert(nestedHold.State == true and nestedPicker._rainbowIndex ~= nil)
nestedCheckbox:Destroy()
assert(nestedWindow._destroyed == true)
assert(nestedCheckbox._destroyed == true and nestedPicker._destroyed == true)
assert(nestedPicker._rainbowIndex == nil and #Nephren._rainbowPickers == 0)
assert(removed == created, "nested unload cleanup should remove every drawing")

print(string.format("smoke test passed (%d drawings)", created))
