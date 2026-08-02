--[[
	Provides a Drawing-backed UI library for environments where Roblox GUI
	instances are unavailable.

	The host must provide Drawing, Vector2, Color3, Enum, and Roblox services.
]]

local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local CACHED_DRAWING_PROPERTIES = {
	Color = true,
	From = true,
	Position = true,
	Radius = true,
	Size = true,
	Text = true,
	To = true,
}

local RENDER_GROUP_FIELDS = {
	Color = "_color",
	EndColor = "_endColor",
	Position = "_position",
	Radius = "_radius",
	Size = "_size",
	StartColor = "_startColor",
}

local COLOR_FIELD_COLUMNS = 32
local COLOR_FIELD_ROWS = 20
local COLOR_PICKER_POPUP_HEIGHT = 224
local COLOR_PICKER_POPUP_WIDTH = 180
local COLOR_VALUE_SEGMENTS = 32
local COLOR_WHITE = Color3.new(1, 1, 1)

local DEFAULT_THEME = {
	Background = Color3.fromRGB(17, 17, 17),
	Topbar = Color3.fromRGB(0, 0, 0),
	Panel = Color3.fromRGB(20, 20, 20),
	Input = Color3.fromRGB(19, 19, 19),
	Control = Color3.fromRGB(37, 37, 37),
	ControlHover = Color3.fromRGB(44, 44, 44),
	ControlActive = Color3.fromRGB(48, 41, 45),
	SliderTrack = Color3.fromRGB(11, 11, 11),
	Border = Color3.fromRGB(0, 0, 0),
	Stroke = Color3.fromRGB(26, 26, 26),
	TabStroke = Color3.fromRGB(28, 28, 28),
	ControlBorder = Color3.fromRGB(11, 11, 11),
	ControlStroke = Color3.fromRGB(49, 49, 49),
	InputStroke = Color3.fromRGB(31, 31, 31),
	InnerBorder = Color3.fromRGB(49, 49, 49),
	Accent = Color3.fromRGB(219, 173, 177),
	AccentEnd = Color3.fromRGB(184, 169, 191),
	AccentDark = Color3.fromRGB(116, 92, 94),
	Text = Color3.fromRGB(255, 255, 255),
	MutedText = Color3.fromRGB(103, 103, 103),
	MenuIcon = Color3.fromRGB(109, 109, 109),
	DisabledText = Color3.fromRGB(73, 73, 73),
	Selection = Color3.fromRGB(52, 43, 46),
	Font = nil,
	TextSize = 14,
	HeaderHeight = 29,
	TitleWidth = 108,
	TabWidth = 57,
	SectionGap = 15,
	SectionPadding = 9,
	ControlWidth = 198,
}

local DELETE_REPEAT_ACCELERATION = 0.86
local DELETE_REPEAT_DELAY = 0.42
local DELETE_REPEAT_INTERVAL = 0.12
local DELETE_REPEAT_MIN_INTERVAL = 0.03
local FALLBACK_VIEWPORT_SIZE = Vector2.new(1920, 1080)
local MINIMUM_WINDOW_SIZE = Vector2.new(360, 260)

local SHIFT_KEYS = {
	["0"] = ")",
	["1"] = "!",
	["2"] = "@",
	["3"] = "#",
	["4"] = "$",
	["5"] = "%",
	["6"] = "^",
	["7"] = "&",
	["8"] = "*",
	["9"] = "(",
	["-"] = "_",
	["="] = "+",
	["["] = "{",
	["]"] = "}",
	["\\"] = "|",
	[";"] = ":",
	["'"] = '"',
	[","] = "<",
	["."] = ">",
	["/"] = "?",
	["`"] = "~",
}

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

local decimalPlaceCache = {}
local numberFormatCache = {}
local colorFieldHues = table.create(COLOR_FIELD_COLUMNS)
local colorValueColors = table.create(COLOR_VALUE_SEGMENTS)

for index = 1, COLOR_FIELD_COLUMNS do
	colorFieldHues[index] = Color3.fromHSV((index - 1) / (COLOR_FIELD_COLUMNS - 1), 1, 1)
end

for index = 1, COLOR_VALUE_SEGMENTS do
	local value = 1 - (index - 1) / (COLOR_VALUE_SEGMENTS - 1)
	colorValueColors[index] = Color3.new(value, value, value)
end

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

local function merge(base, overrides)
	local result = table.clone(base)
	for key, value in pairs(overrides or {}) do
		result[key] = value
	end
	return result
end

local function setCopy(source)
	source = source or {}
	local result = {}
	local keyCount = 0
	local isList = true
	for key in pairs(source) do
		keyCount = keyCount + 1
		if type(key) ~= "number" then
			isList = false
		end
	end
	if isList then
		for index = 1, keyCount do
			if source[index] == nil then
				isList = false
				break
			end
		end
	end

	if isList then
		for _, value in ipairs(source) do
			result[value] = true
		end
		return result
	end

	for key, value in pairs(source) do
		if type(key) == "number" then
			result[value] = true
		elseif value then
			result[key] = true
		end
	end
	return result
end

local function arraysEqual(first, second)
	if #first ~= #second then
		return false
	end
	for index, value in ipairs(first) do
		if value ~= second[index] then
			return false
		end
	end
	return true
end

local function snap(value, minimum, step)
	if not step or step <= 0 then
		return value
	end
	return minimum + math.round((value - minimum) / step) * step
end

local function pointInRegion(point, region)
	local x, y = point.X, point.Y
	return x >= region._minimumX
		and y >= region._minimumY
		and x <= region._maximumX
		and y <= region._maximumY
end

local function setRegionRectangle(region, x, y, width, height)
	local maximumX, maximumY = x + width, y + height
	if
		region._minimumX == x
		and region._minimumY == y
		and region._maximumX == maximumX
		and region._maximumY == maximumY
	then
		return false
	end
	region._minimumX = x
	region._minimumY = y
	region._maximumX = maximumX
	region._maximumY = maximumY
	local rectangle = region._rectangle
	rectangle._minimum.X, rectangle._minimum.Y = x, y
	rectangle._maximum.X, rectangle._maximum.Y = maximumX, maximumY
	return true
end

local function safeCall(callback, ...)
	if type(callback) ~= "function" then
		return
	end

	-- Consumer callbacks must not interrupt input or teardown state.
	local success, message = pcall(callback, ...)
	if not success then
		warn("[Nephren] callback error: " .. tostring(message))
	end
end

local function noOperation()
	return
end

local function optionText(configuration, fallback)
	return tostring(
		configuration.Text
			or configuration.Title
			or configuration.Name
			or configuration.Label
			or fallback
			or ""
	)
end

local function getFont(theme)
	if theme.Font ~= nil then
		return theme.Font
	end
	if Nephren._defaultFont ~= nil then
		return Nephren._defaultFont
	end
	if Drawing.Fonts then
		return Drawing.Fonts.Plex or Drawing.Fonts.UI or 2
	end
	return 2
end

local function centeredTextY(top, height, textSize)
	return math.round(top + (height - textSize) * 0.5)
end

local function truncate(text, width, textSize)
	text = tostring(text or "")
	local approximateCharacterWidth = math.max(5, (textSize or 13) * 0.52)
	local limit = math.max(1, math.floor(width / approximateCharacterWidth))
	if #text <= limit then
		return text
	end
	local length = utf8.len(text)
	if not length or length <= limit then
		return text
	end

	if limit <= 3 then
		local nextByte = utf8.offset(text, limit + 1)
		if nextByte then
			return string.sub(text, 1, nextByte - 1)
		end
		return text
	end
	local nextByte = utf8.offset(text, limit - 2)
	local prefix = text
	if nextByte then
		prefix = string.sub(text, 1, nextByte - 1)
	end
	return prefix .. "..."
end

local function getTextBounds(object)
	return object.TextBounds
end

local function measuredTextWidth(record, text, textSize)
	local object = record and record._object
	if object then
		-- Some Drawing hosts throw when TextBounds is unavailable.
		local success, bounds = pcall(getTextBounds, object)
		if success and bounds then
			local width = tonumber(bounds.X)
			if width and (width > 0 or text == "") then
				return width
			end
		end
	end
	return (utf8.len(text) or #text) * ((textSize or 13) * 0.52)
end

local function textLength(text)
	return utf8.len(text) or #text
end

local function removeLastCharacter(text)
	local length = #text
	if length == 0 then
		return ""
	end
	if string.byte(text, length) < 128 then
		return string.sub(text, 1, length - 1)
	end
	local byteOffset = utf8.offset(text, -1)
	if not byteOffset then
		return ""
	end
	return string.sub(text, 1, byteOffset - 1)
end

local function limitText(text, maximumLength)
	if #text <= maximumLength then
		return text
	end
	local nextByte = utf8.offset(text, maximumLength + 1)
	if not nextByte then
		return text
	end
	return string.sub(text, 1, nextByte - 1)
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
	step = step or 1
	local places = decimalPlaceCache[step]
	if places == nil then
		places = decimalPlaces(step)
		decimalPlaceCache[step] = places
	end
	if places == 0 then
		return tostring(math.round(value))
	end
	local format = numberFormatCache[places]
	if not format then
		format = "%." .. tostring(places) .. "f"
		numberFormatCache[places] = format
	end
	return string.format(format, value)
end

local function removeValue(array, wanted)
	local index = table.find(array, wanted)
	if index then
		table.remove(array, index)
	end
end

local function compactDead(array)
	local writeIndex = 1
	for readIndex = 1, #array do
		local value = array[readIndex]
		if not value._dead then
			array[writeIndex] = value
			writeIndex = writeIndex + 1
		end
	end
	for index = #array, writeIndex, -1 do
		array[index] = nil
	end
end

local function keyName(library, token)
	if token == nil then
		return "None"
	end

	if token == Enum.UserInputType.MouseButton1 then
		return "MB1"
	elseif token == Enum.UserInputType.MouseButton2 then
		return "MB2"
	elseif token == Enum.UserInputType.MouseButton3 then
		return "MB3"
	end

	return library._userInputService:GetStringForKeyCode(
		token,
		Enum.KeyCodeStringFormat.Abbreviated
	)
end

local function isDeleteKey(keyCode)
	return keyCode == Enum.KeyCode.Backspace or keyCode == Enum.KeyCode.Delete
end

local function keyIsDown(library, keyCode)
	if library._keysDown[keyCode] then
		return true
	end
	return library._userInputService:IsKeyDown(keyCode)
end

local function inputCharacter(library, keyCode)
	local character = library._userInputService:GetStringForKeyCode(keyCode)
	local shifted = keyIsDown(library, Enum.KeyCode.LeftShift)
		or keyIsDown(library, Enum.KeyCode.RightShift)

	if character == "Space" then
		return " "
	end
	if utf8.len(character) ~= 1 then
		return nil
	end

	if string.match(character, "^%a$") then
		if shifted ~= library._capsLock then
			return string.upper(character)
		end
		return string.lower(character)
	end

	if shifted and SHIFT_KEYS[character] then
		return SHIFT_KEYS[character]
	end
	return character
end

local function defaultPosition(workspaceService, size)
	local viewport = FALLBACK_VIEWPORT_SIZE
	local camera = workspaceService.CurrentCamera
	if camera then
		viewport = camera.ViewportSize
	end
	return ((viewport - size) * 0.5):Floor()
end

local function normalizeConfiguration(configuration, callback)
	if type(configuration) == "string" then
		return {
			Text = configuration,
			Callback = callback,
		}
	end
	return table.clone(configuration or {})
end

local function multiplyColor(color, amount)
	amount = math.clamp(amount, 0, 1)
	return Color3.new(color.R * amount, color.G * amount, color.B * amount)
end

local function activeAccentGradient(theme)
	return multiplyColor(theme.Accent, 0.20), multiplyColor(theme.AccentEnd, 0.30)
end

local function valuesEqual(first, second)
	if first == second then
		return true
	end
	if type(first) ~= "table" or type(second) ~= "table" then
		return false
	end

	local x = first.X
	if x ~= nil then
		return x == second.X and first.Y == second.Y
	end
	local red = first.R
	if red ~= nil then
		return red == second.R and first.G == second.G and first.B == second.B
	end
	return false
end

local function setPrimitive(record, property, value)
	if record._dead or valuesEqual(record[property], value) then
		return false
	end
	record[property] = value
	record._object[property] = value
	return true
end

local function setPrimitivePair(record, firstProperty, firstValue, secondProperty, secondValue)
	local changed = setPrimitive(record, firstProperty, firstValue)
	return setPrimitive(record, secondProperty, secondValue) or changed
end

local function removeDrawingObject(object)
	object:Remove()
end

local function disconnectConnection(connection)
	connection:Disconnect()
end

local function newRoundedRectangle(window, bucket, color, localZIndex, radius, reinforceCorners)
	local rounding = radius or 3
	local flat = rounding <= 0 and reinforceCorners ~= true
	local partCount = 6
	if flat then
		partCount = 1
	elseif reinforceCorners then
		partCount = 10
	end
	local zIndex = window:_getZIndex(localZIndex)
	local group = {
		_kind = "RoundedRectangle",
		_parts = table.create(partCount),
		_position = window.Position,
		_size = Vector2.new(1, 1),
		_radius = rounding,
		_reinforceCorners = reinforceCorners == true,
		_flat = flat,
		_color = color,
	}

	if flat then
		group._parts[1] = window:_newDrawing("Square", {
			Filled = true,
			Color = color,
			Position = window.Position,
			Size = Vector2.new(1, 1),
			ZIndex = zIndex,
			Transparency = 1,
			Visible = false,
		}, bucket)
		return group
	end

	for _ = 1, 2 do
		local index = #group._parts + 1
		group._parts[index] = window:_newDrawing("Square", {
			Filled = true,
			Color = color,
			Position = window.Position,
			Size = Vector2.new(1, 1),
			ZIndex = zIndex,
			Transparency = 1,
			Visible = false,
		}, bucket)
	end
	for _ = 1, 4 do
		local index = #group._parts + 1
		group._parts[index] = window:_newDrawing("Circle", {
			Filled = true,
			Color = color,
			Position = window.Position,
			Radius = 1,
			NumSides = 16,
			Thickness = 1,
			ZIndex = zIndex,
			Transparency = 1,
			Visible = false,
		}, bucket)
	end
	if group._reinforceCorners then
		for _ = 1, 4 do
			local index = #group._parts + 1
			group._parts[index] = window:_newDrawing("Circle", {
				Filled = false,
				Color = color,
				Position = window.Position,
				Radius = 1,
				NumSides = 16,
				Thickness = 1,
				ZIndex = zIndex,
				Transparency = 1,
				Visible = false,
			}, bucket)
		end
	end
	return group
end

local function layoutRoundedRectangle(window, group)
	local position = group._position
	local size = group._size
	if group._flat then
		setPrimitivePair(group._parts[1], "Position", position, "Size", size)
		return
	end

	local radius = math.max(
		0,
		math.min(group._radius or 0, math.floor(size.X * 0.5), math.floor(size.Y * 0.5))
	)
	local x, y = position.X, position.Y
	local width, height = size.X, size.Y

	setPrimitivePair(
		group._parts[1],
		"Position",
		Vector2.new(x + radius, y),
		"Size",
		Vector2.new(math.max(0, width - radius * 2), height)
	)
	setPrimitivePair(
		group._parts[2],
		"Position",
		Vector2.new(x, y + radius),
		"Size",
		Vector2.new(width, math.max(0, height - radius * 2))
	)

	local left, right = x + radius, x + width - radius
	local top, bottom = y + radius, y + height - radius
	for index = 1, 4 do
		local center
		if index == 1 then
			center = Vector2.new(left, top)
		elseif index == 2 then
			center = Vector2.new(right, top)
		elseif index == 3 then
			center = Vector2.new(left, bottom)
		else
			center = Vector2.new(right, bottom)
		end
		setPrimitivePair(group._parts[index + 2], "Position", center, "Radius", radius)
		if group._reinforceCorners then
			setPrimitivePair(group._parts[index + 6], "Position", center, "Radius", radius)
		end
	end
end

local function layoutRoundedRectanglePosition(group)
	local position = group._position
	if group._flat then
		setPrimitive(group._parts[1], "Position", position)
		return
	end
	local size = group._size
	local radius = math.max(
		0,
		math.min(group._radius or 0, math.floor(size.X * 0.5), math.floor(size.Y * 0.5))
	)
	local x, y = position.X, position.Y
	local left, right = x + radius, x + size.X - radius
	local top, bottom = y + radius, y + size.Y - radius
	setPrimitive(group._parts[1], "Position", Vector2.new(left, y))
	setPrimitive(group._parts[2], "Position", Vector2.new(x, top))
	for index = 1, 4 do
		local center
		if index == 1 then
			center = Vector2.new(left, top)
		elseif index == 2 then
			center = Vector2.new(right, top)
		elseif index == 3 then
			center = Vector2.new(left, bottom)
		else
			center = Vector2.new(right, bottom)
		end
		setPrimitive(group._parts[index + 2], "Position", center)
		if group._reinforceCorners then
			setPrimitive(group._parts[index + 6], "Position", center)
		end
	end
end

local function setRoundedColor(window, group, color)
	group._color = color
	for _, part in ipairs(group._parts) do
		setPrimitive(part, "Color", color)
	end
end

local function newGradient(
	window,
	bucket,
	localZIndex,
	startColor,
	endColor,
	segments,
	direction,
	radius
)
	local segmentCount = math.max(2, segments or 24)
	local hasCaps = (direction or "Horizontal") == "Horizontal" and (radius or 0) > 0
	local capCount = 0
	if hasCaps then
		capCount = 2
	end
	local zIndex = window:_getZIndex(localZIndex)
	local group = {
		_kind = "Gradient",
		_parts = table.create(segmentCount + capCount),
		_position = window.Position,
		_size = Vector2.new(1, 1),
		_startColor = startColor,
		_endColor = endColor,
		_segments = segmentCount,
		_direction = direction or "Horizontal",
		_radius = radius or 0,
	}
	for index = 1, group._segments do
		local alpha = (index - 1) / (group._segments - 1)
		group._parts[index] = window:_newDrawing("Square", {
			Filled = true,
			Color = startColor:Lerp(endColor, alpha),
			Position = window.Position,
			Size = Vector2.new(1, 1),
			ZIndex = zIndex,
			Transparency = 1,
			Visible = false,
		}, bucket)
	end
	if group._direction == "Horizontal" and group._radius > 0 then
		group._startCap = window:_newDrawing("Circle", {
			Filled = true,
			Color = startColor,
			Position = window.Position,
			Radius = group._radius,
			NumSides = 16,
			Thickness = 1,
			ZIndex = zIndex,
			Transparency = 1,
			Visible = false,
		}, bucket)
		group._endCap = window:_newDrawing("Circle", {
			Filled = true,
			Color = endColor,
			Position = window.Position,
			Radius = group._radius,
			NumSides = 16,
			Thickness = 1,
			ZIndex = zIndex,
			Transparency = 1,
			Visible = false,
		}, bucket)
		group._parts[group._segments + 1] = group._startCap
		group._parts[group._segments + 2] = group._endCap
	end
	return group
end

local function layoutGradient(window, group)
	local position = group._position
	local size = group._size
	local radius = math.max(
		0,
		math.min(group._radius or 0, math.floor(size.X * 0.5), math.floor(size.Y * 0.5))
	)

	if group._direction == "Vertical" then
		local sliceHeight = size.Y / group._segments
		local sliceSizeY = math.ceil(sliceHeight)
		for index = 1, group._segments do
			local inset = 0
			if radius > 0 then
				local edgeDistance = math.min(index - 1, group._segments - index)
				inset = math.max(0, radius - edgeDistance)
			end
			setPrimitivePair(
				group._parts[index],
				"Position",
				Vector2.new(position.X + inset, position.Y + (index - 1) * sliceHeight),
				"Size",
				Vector2.new(math.max(0, size.X - inset * 2), sliceSizeY)
			)
		end
		return
	end

	local contentX = position.X + radius
	local contentWidth = math.max(0, size.X - radius * 2)
	local sliceWidth = contentWidth / group._segments
	local sliceSizeX = math.ceil(sliceWidth)
	for index = 1, group._segments do
		setPrimitivePair(
			group._parts[index],
			"Position",
			Vector2.new(contentX + (index - 1) * sliceWidth, position.Y),
			"Size",
			Vector2.new(sliceSizeX, size.Y)
		)
	end
	if group._startCap then
		local capY = position.Y + size.Y * 0.5
		setPrimitivePair(
			group._startCap,
			"Position",
			Vector2.new(position.X + radius, capY),
			"Radius",
			radius
		)
		setPrimitivePair(
			group._endCap,
			"Position",
			Vector2.new(position.X + size.X - radius, capY),
			"Radius",
			radius
		)
	end
end

local function layoutGradientPosition(group)
	local position = group._position
	local size = group._size
	local radius = math.max(
		0,
		math.min(group._radius or 0, math.floor(size.X * 0.5), math.floor(size.Y * 0.5))
	)
	if group._direction == "Vertical" then
		local sliceHeight = size.Y / group._segments
		for index = 1, group._segments do
			local inset = 0
			if radius > 0 then
				local edgeDistance = math.min(index - 1, group._segments - index)
				inset = math.max(0, radius - edgeDistance)
			end
			setPrimitive(
				group._parts[index],
				"Position",
				Vector2.new(position.X + inset, position.Y + (index - 1) * sliceHeight)
			)
		end
		return
	end

	local contentX = position.X + radius
	local sliceWidth = math.max(0, size.X - radius * 2) / group._segments
	for index = 1, group._segments do
		setPrimitive(
			group._parts[index],
			"Position",
			Vector2.new(contentX + (index - 1) * sliceWidth, position.Y)
		)
	end
	if group._startCap then
		local capY = position.Y + size.Y * 0.5
		setPrimitive(group._startCap, "Position", Vector2.new(position.X + radius, capY))
		setPrimitive(group._endCap, "Position", Vector2.new(position.X + size.X - radius, capY))
	end
end

local function setGradientColors(window, group, startColor, endColor)
	group._startColor = startColor
	group._endColor = endColor
	for index = 1, group._segments do
		local alpha = (index - 1) / (group._segments - 1)
		setPrimitive(group._parts[index], "Color", startColor:Lerp(endColor, alpha))
	end
	if group._startCap then
		setPrimitive(group._startCap, "Color", startColor)
		setPrimitive(group._endCap, "Color", endColor)
	end
end

Nephren.Theme = DEFAULT_THEME
Nephren._windows = {}
Nephren._connections = {}
Nephren._keybinds = {}
Nephren._keybindBuckets = {}
Nephren._keybindGeneration = 0
Nephren._rainbowPickers = {}
Nephren._flagOwners = {}
Nephren._flagStacks = {}
Nephren._started = false
Nephren._unloading = false
Nephren._focusedTextbox = nil
Nephren._bindingKeybind = nil
Nephren._capture = nil
Nephren._hoveredRegion = nil
Nephren._keysDown = {}
Nephren._capsLock = false
Nephren._deleteRepeat = nil
Nephren._nextBaseZIndex = 0
Nephren._pendingDragWindows = {}
Nephren._pendingDragCount = 0

function Nephren:_queueWindowDrag(window, position)
	if not window._pendingDragPosition then
		self._pendingDragCount = self._pendingDragCount + 1
		self._pendingDragWindows[window] = true
	end
	window._pendingDragPosition = position
	self:_refreshRenderConnection()
end

function Nephren:_finishWindowDrag(window, apply)
	local position = window._pendingDragPosition
	if not position then
		return
	end
	window._pendingDragPosition = nil
	self._pendingDragWindows[window] = nil
	self._pendingDragCount = self._pendingDragCount - 1
	if apply and not window._destroyed then
		window:SetPosition(position)
	end
end

function Nephren:_flushWindowDrags()
	if self._pendingDragCount == 0 then
		return
	end
	for window in pairs(self._pendingDragWindows) do
		self:_finishWindowDrag(window, true)
	end
end

function Nephren:_refreshRenderConnection()
	if not self._started then
		return
	end
	local needed = self._deleteRepeat ~= nil
		or #self._rainbowPickers > 0
		or self._pendingDragCount > 0
	if needed and not self._renderConnection then
		self._renderConnection = self._runService.RenderStepped:Connect(function(deltaTime)
			local pickers = self._rainbowPickers
			self._steppingRainbows = true
			local count = #pickers
			for index = 1, count do
				local picker = pickers[index]
				if not picker then
					break
				end
				picker:_rainbowStep(deltaTime)
			end
			self._steppingRainbows = false

			local pending = self._pendingRainbowState
			if pending then
				self._pendingRainbowState = nil
				for picker, active in pairs(pending) do
					self:_setRainbowActive(picker, active)
				end
			end
			self:_flushWindowDrags()
			self:_stepDeleteRepeat(deltaTime)
			self:_refreshRenderConnection()
		end)
	elseif not needed and self._renderConnection then
		local connection = self._renderConnection
		self._renderConnection = nil
		connection:Disconnect()
	end
end

function Nephren:_registerKeybind(keybind)
	local keybinds = self._keybinds
	keybinds[#keybinds + 1] = keybind
	local token = keybind.Value
	if token == nil then
		return
	end
	local bucket = self._keybindBuckets[token]
	if not bucket then
		bucket = {}
		self._keybindBuckets[token] = bucket
	end
	self._keybindGeneration = self._keybindGeneration + 1
	keybind._bucketGeneration = self._keybindGeneration
	bucket[#bucket + 1] = keybind
end

function Nephren:_unindexKeybind(keybind, token)
	if token == nil then
		return
	end
	local bucket = self._keybindBuckets[token]
	if not bucket then
		return
	end
	removeValue(bucket, keybind)
	if #bucket == 0 then
		self._keybindBuckets[token] = nil
	end
end

function Nephren:_setKeybindToken(keybind, token)
	local previous = keybind.Value
	if previous == token then
		return false
	end
	if keybind.Mode == "Hold" and keybind.State then
		keybind:_inputEnded()
		if keybind._destroyed then
			return false
		end
		if keybind.Value ~= previous then
			return false
		end
	end
	self:_unindexKeybind(keybind, previous)
	keybind.Value = token
	if token ~= nil then
		local bucket = self._keybindBuckets[token]
		if not bucket then
			bucket = {}
			self._keybindBuckets[token] = bucket
		end
		self._keybindGeneration = self._keybindGeneration + 1
		keybind._bucketGeneration = self._keybindGeneration
		bucket[#bucket + 1] = keybind
	end
	return true
end

function Nephren:_unregisterKeybind(keybind)
	self:_unindexKeybind(keybind, keybind.Value)
	removeValue(self._keybinds, keybind)
end

function Nephren:_setRainbowActive(picker, active)
	active = not not active
	if self._steppingRainbows then
		local pending = self._pendingRainbowState
		if not pending then
			pending = {}
			self._pendingRainbowState = pending
		end
		pending[picker] = active
		return
	end
	local pickers = self._rainbowPickers
	local index = picker._rainbowIndex
	if index and pickers[index] ~= picker then
		index = table.find(pickers, picker)
		picker._rainbowIndex = index
	end
	if active == (index ~= nil) then
		return
	end
	if active then
		index = #pickers + 1
		pickers[index] = picker
		picker._rainbowIndex = index
		self:_refreshRenderConnection()
		return
	end

	local lastIndex = #pickers
	local last = pickers[lastIndex]
	pickers[index] = last
	pickers[lastIndex] = nil
	picker._rainbowIndex = nil
	if last ~= picker then
		last._rainbowIndex = index
	end
	self:_refreshRenderConnection()
end

function Nephren:_mousePosition()
	return self._userInputService:GetMouseLocation()
end

function Nephren:_setFocusedTextbox(textbox)
	if self._focusedTextbox and self._focusedTextbox ~= textbox then
		self:_stopDeleteRepeat(self._focusedTextbox)
		self._focusedTextbox:Blur(true)
	end
	self._focusedTextbox = textbox
end

function Nephren:_startDeleteRepeat(target, keyCode)
	if
		target ~= self._focusedTextbox
		or type(target._editText) ~= "string"
		or target._editText == ""
	then
		self._deleteRepeat = nil
		self:_refreshRenderConnection()
		return
	end

	self._deleteRepeat = {
		_target = target,
		_keyCode = keyCode,
		_timeUntilNext = DELETE_REPEAT_DELAY,
		_interval = DELETE_REPEAT_INTERVAL,
	}
	self:_refreshRenderConnection()
end

function Nephren:_stopDeleteRepeat(target)
	local repeatState = self._deleteRepeat
	if repeatState and (not target or repeatState._target == target) then
		self._deleteRepeat = nil
		self:_refreshRenderConnection()
	end
end

function Nephren:_stepDeleteRepeat(deltaTime)
	local repeatState = self._deleteRepeat
	if not repeatState then
		return
	end

	local target = repeatState._target
	if
		target ~= self._focusedTextbox
		or target._destroyed
		or not self._keysDown[repeatState._keyCode]
		or type(target._editText) ~= "string"
		or target._editText == ""
	then
		self._deleteRepeat = nil
		return
	end

	repeatState._timeUntilNext = repeatState._timeUntilNext - math.max(0, tonumber(deltaTime) or 0)
	local repeatCount = 0
	while repeatState._timeUntilNext <= 0 and repeatCount < 32 do
		target:_onKey(repeatState._keyCode)
		repeatCount = repeatCount + 1

		if
			self._deleteRepeat ~= repeatState
			or target ~= self._focusedTextbox
			or type(target._editText) ~= "string"
			or target._editText == ""
		then
			self._deleteRepeat = nil
			return
		end

		repeatState._interval = math.max(
			DELETE_REPEAT_MIN_INTERVAL,
			repeatState._interval * DELETE_REPEAT_ACCELERATION
		)
		repeatState._timeUntilNext = repeatState._timeUntilNext + repeatState._interval
	end

	if repeatCount == 32 and repeatState._timeUntilNext <= 0 then
		repeatState._timeUntilNext = repeatState._interval
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
	local bestZIndex = -math.huge
	local bestPriority = -math.huge
	local bestOrder = -1

	local windows = self._windows
	for windowIndex = 1, #windows do
		local window = windows[windowIndex]
		if not window._destroyed and window.Visible then
			local regions = window._activeRegions
			for index = 1, #regions do
				local region = regions[index]
				local enabled = not region._dead and pointInRegion(point, region)
				if enabled and region._enabled then
					enabled = region._enabled()
				end
				if enabled then
					local priority = region._priority
					local order = region._order
					local zIndex = window.BaseZIndex + priority
					if
						zIndex > bestZIndex
						or (zIndex == bestZIndex and windowIndex > bestWindowIndex)
						or (
							zIndex == bestZIndex
							and windowIndex == bestWindowIndex
							and (
								priority > bestPriority
								or (priority == bestPriority and order > bestOrder)
							)
						)
					then
						bestRegion = region
						bestWindowIndex = windowIndex
						bestZIndex = zIndex
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

	if self._hoveredRegion and self._hoveredRegion._onHover then
		self._hoveredRegion._onHover(false)
	end
	self._hoveredRegion = region
	if region and region._onHover then
		region._onHover(true)
	end
end

function Nephren:_closeForeignPopups(region)
	for _, window in ipairs(self._windows) do
		local popup = window._openPopup
		if popup and (not region or region._popupOwner ~= popup) then
			popup:Close()
		end
	end
end

function Nephren:_handleInputBegan(input, gameProcessed)
	local inputType = input.UserInputType
	local keyCode = input.KeyCode
	local token = inputType
	if inputType == Enum.UserInputType.Keyboard then
		token = keyCode
	end
	local keyAlreadyDown = false

	if inputType == Enum.UserInputType.Keyboard then
		keyAlreadyDown = self._keysDown[token] == true
		self._keysDown[token] = true
		if token == Enum.KeyCode.CapsLock and not keyAlreadyDown then
			self._capsLock = not self._capsLock
		end
	end

	if self._bindingKeybind then
		if
			inputType == Enum.UserInputType.Keyboard
			or inputType == Enum.UserInputType.MouseButton1
			or inputType == Enum.UserInputType.MouseButton2
			or inputType == Enum.UserInputType.MouseButton3
		then
			local binding = self._bindingKeybind
			self._bindingKeybind = nil
			binding:_finishBinding(token)
			return
		end
	end

	if inputType == Enum.UserInputType.Keyboard then
		for _, window in ipairs(self._windows) do
			if not window._destroyed and window.ToggleKey == token then
				window:SetVisible(not window.Visible)
				return
			end
		end
	end

	if self._focusedTextbox and inputType == Enum.UserInputType.Keyboard then
		if isDeleteKey(keyCode) and keyAlreadyDown then
			return
		end
		local focusedTextbox = self._focusedTextbox
		focusedTextbox:_onKey(keyCode)
		if isDeleteKey(keyCode) then
			self:_startDeleteRepeat(focusedTextbox, keyCode)
		end
		return
	end

	if not gameProcessed then
		local bucket = self._keybindBuckets[token]
		local generation = self._keybindGeneration
		local index = 1
		while bucket and index <= #bucket do
			local keybind = bucket[index]
			if keybind._bucketGeneration > generation then
				break
			end
			if not keybind._destroyed and not keybind._binding then
				keybind:_inputBegan()
			end
			if bucket[index] == keybind then
				index = index + 1
			end
		end
	end

	local isPrimary = inputType == Enum.UserInputType.MouseButton1
	if not isPrimary then
		return
	end

	local point = self:_mousePosition()
	local region = self:_topRegion(point)

	if self._focusedTextbox and (not region or region._owner ~= self._focusedTextbox) then
		self._focusedTextbox:Blur(true)
	end
	self:_closeForeignPopups(region)

	if region and region._onPress then
		local capture = region._onPress(point, input)
		if capture then
			self._capture = region
		end
	end
	self:_updateHover(point)
end

function Nephren:_handleInputChanged(input)
	local inputType = input.UserInputType
	if inputType == Enum.UserInputType.MouseMovement then
		local point = self:_mousePosition()
		local capture = self._capture
		if capture and not capture._dead and capture._onMove then
			capture._onMove(point, input)
		end
		self:_updateHover(point)
	elseif inputType == Enum.UserInputType.MouseWheel then
		local point = self:_mousePosition()
		local region = self:_topRegion(point)
		if region and region._onWheel then
			region._onWheel(input.Position.Z, point)
		end
	end
end

function Nephren:_handleInputEnded(input)
	local inputType = input.UserInputType
	local token = inputType
	if inputType == Enum.UserInputType.Keyboard then
		token = input.KeyCode
	end
	if inputType == Enum.UserInputType.Keyboard then
		self._keysDown[token] = nil
		local repeatState = self._deleteRepeat
		if repeatState and repeatState._keyCode == token then
			self:_stopDeleteRepeat(repeatState._target)
		end
	end

	if inputType == Enum.UserInputType.MouseButton1 and self._capture then
		local capture = self._capture
		self._capture = nil
		if not capture._dead and capture._onRelease then
			capture._onRelease(self:_mousePosition(), input)
		end
	end

	local bucket = self._keybindBuckets[token]
	local generation = self._keybindGeneration
	local index = 1
	while bucket and index <= #bucket do
		local keybind = bucket[index]
		if keybind._bucketGeneration > generation then
			break
		end
		if not keybind._destroyed then
			keybind:_inputEnded()
		end
		if bucket[index] == keybind then
			index = index + 1
		end
	end
end

function Nephren:_start()
	if self._started then
		return
	end

	assert(Drawing and Drawing.new, "Nephren requires Drawing.new")

	self._userInputService = UserInputService
	self._runService = RunService
	self._workspace = Workspace
	self._drawingNew = Drawing.new
	self._defaultFont = 2
	if Drawing.Fonts then
		self._defaultFont = Drawing.Fonts.Plex or Drawing.Fonts.UI or 2
	end
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
end

function Window.new(library, configuration)
	local size = configuration.Size
		or Vector2.new(tonumber(configuration.Width) or 587, tonumber(configuration.Height) or 563)
	size = size:Max(MINIMUM_WINDOW_SIZE)

	local position = configuration.Position
	if not position then
		if configuration.Center == false then
			position = Vector2.new(40, 40)
		else
			position = defaultPosition(library._workspace, size)
		end
	end

	local toggleKey = configuration.ToggleKey
	if toggleKey == nil then
		toggleKey = Enum.KeyCode.RightShift
	elseif toggleKey == false then
		toggleKey = nil
	end

	local baseZIndex = configuration.ZIndex
	if baseZIndex == nil then
		baseZIndex = library._nextBaseZIndex
		library._nextBaseZIndex = baseZIndex + 1000
	end

	local self = setmetatable({
		Title = tostring(configuration.Title or configuration.Name or "Nephren"),
		Position = position,
		Size = size,
		Visible = configuration.Visible ~= false,
		Draggable = configuration.Draggable ~= false,
		ToggleKey = toggleKey,
		BaseZIndex = baseZIndex,
		Theme = merge(DEFAULT_THEME, configuration.Theme),
		Tabs = {},
		SelectedTab = nil,
		Flags = {},
		_flagControls = {},
		_drawings = {},
		_shownDrawings = {},
		_baseDrawings = {},
		_regions = {},
		_activeRegions = {},
		_deadDrawingCount = 0,
		_deadRegionCount = 0,
		_nextRegionOrder = 0,
		_tabWidthTotal = 0,
		_geometryRevision = 1,
		_destroyed = false,
		_openPopup = nil,
	}, Window)

	self:_createBase()
	return self
end

function Window:_getZIndex(localZIndex)
	return self.BaseZIndex + localZIndex
end

function Window:_newDrawing(kind, properties, bucket)
	local object = Nephren._drawingNew(kind)
	local wantedVisible = properties.Visible ~= false
	local actualVisible = self.Visible and wantedVisible
	local record = {
		_object = object,
		_wantedVisible = wantedVisible,
		_actualVisible = actualVisible,
		_dead = false,
	}

	for property, value in pairs(properties) do
		if property ~= "Visible" then
			object[property] = value
			if CACHED_DRAWING_PROPERTIES[property] then
				record[property] = value
			end
		end
	end
	object.Visible = actualVisible

	table.insert(self._drawings, record)
	if wantedVisible then
		local shown = self._shownDrawings
		local index = #shown + 1
		shown[index] = record
		record._shownIndex = index
	end
	if bucket then
		table.insert(bucket, record)
	end
	return record
end

function Window:_set(record, properties)
	if not record or record._dead then
		return
	end
	if record._kind == "RoundedRectangle" then
		local needsLayout = false
		local positionOnly = true
		for property, value in pairs(properties) do
			if property == "Position" or property == "Size" or property == "Radius" then
				local field = RENDER_GROUP_FIELDS[property]
				if not valuesEqual(record[field], value) then
					record[field] = value
					needsLayout = true
					if property ~= "Position" then
						positionOnly = false
					end
				end
			elseif property == "Color" then
				local field = RENDER_GROUP_FIELDS[property]
				if not valuesEqual(record[field], value) then
					setRoundedColor(self, record, value)
				end
			elseif property == "Visible" then
				self:_show(record, value)
			else
				for _, part in ipairs(record._parts) do
					setPrimitive(part, property, value)
				end
			end
		end
		if needsLayout then
			if positionOnly then
				layoutRoundedRectanglePosition(record)
			else
				layoutRoundedRectangle(self, record)
			end
		end
		return
	elseif record._kind == "Gradient" then
		local needsLayout = false
		local positionOnly = true
		local recolor = false
		for property, value in pairs(properties) do
			if property == "Position" or property == "Size" or property == "Radius" then
				local field = RENDER_GROUP_FIELDS[property]
				if not valuesEqual(record[field], value) then
					record[field] = value
					needsLayout = true
					if property ~= "Position" then
						positionOnly = false
					end
				end
			elseif property == "StartColor" or property == "EndColor" then
				local field = RENDER_GROUP_FIELDS[property]
				if not valuesEqual(record[field], value) then
					record[field] = value
					recolor = true
				end
			elseif property == "Visible" then
				self:_show(record, value)
			else
				for _, part in ipairs(record._parts) do
					setPrimitive(part, property, value)
				end
			end
		end
		if recolor then
			setGradientColors(self, record, record._startColor, record._endColor)
		end
		if needsLayout then
			if positionOnly then
				layoutGradientPosition(record)
			else
				layoutGradient(self, record)
			end
		end
		return
	end
	for property, value in pairs(properties) do
		if property == "Visible" then
			self:_show(record, value)
		else
			setPrimitive(record, property, value)
		end
	end
end

function Window:_setPositionSize(record, position, size)
	if not record or record._dead then
		return
	end
	local kind = record._kind
	if kind == "RoundedRectangle" or kind == "Gradient" then
		local positionChanged = not valuesEqual(record._position, position)
		local sizeChanged = not valuesEqual(record._size, size)
		if positionChanged then
			record._position = position
		end
		if sizeChanged then
			record._size = size
		end
		if positionChanged or sizeChanged then
			if kind == "RoundedRectangle" then
				if positionChanged and not sizeChanged then
					layoutRoundedRectanglePosition(record)
				else
					layoutRoundedRectangle(self, record)
				end
			else
				if positionChanged and not sizeChanged then
					layoutGradientPosition(record)
				else
					layoutGradient(self, record)
				end
			end
		end
		return
	end
	setPrimitivePair(record, "Position", position, "Size", size)
end

function Window:_setPosition(record, position)
	if not record or record._dead then
		return
	end
	local kind = record._kind
	if kind == "RoundedRectangle" or kind == "Gradient" then
		if valuesEqual(record._position, position) then
			return
		end
		record._position = position
		if kind == "RoundedRectangle" then
			layoutRoundedRectanglePosition(record)
		else
			layoutGradientPosition(record)
		end
		return
	end
	setPrimitive(record, "Position", position)
end

function Window:_setColor(record, color)
	if not record or record._dead then
		return
	end
	if record._kind == "RoundedRectangle" then
		if not valuesEqual(record._color, color) then
			setRoundedColor(self, record, color)
		end
		return
	end
	if record._kind == "Gradient" then
		for _, part in ipairs(record._parts) do
			setPrimitive(part, "Color", color)
		end
		return
	end
	setPrimitive(record, "Color", color)
end

function Window:_setGradient(record, startColor, endColor)
	if not record or record._dead then
		return
	end
	if valuesEqual(record._startColor, startColor) and valuesEqual(record._endColor, endColor) then
		return
	end
	setGradientColors(self, record, startColor, endColor)
end

function Window:_setText(record, text)
	if record and not record._dead then
		setPrimitive(record, "Text", text)
	end
end

function Window:_setTextPosition(record, text, position)
	if record and not record._dead then
		setPrimitivePair(record, "Text", text, "Position", position)
	end
end

function Window:_setTextColor(record, text, color)
	if record and not record._dead then
		setPrimitivePair(record, "Text", text, "Color", color)
	end
end

function Window:_setLine(record, from, to)
	if record and not record._dead then
		setPrimitivePair(record, "From", from, "To", to)
	end
end

function Window:_show(record, visible)
	if not record or record._dead then
		return
	end
	if record._kind == "RoundedRectangle" or record._kind == "Gradient" then
		local wantedVisible = not not visible
		record._wantedVisible = wantedVisible
		for _, part in ipairs(record._parts) do
			self:_show(part, wantedVisible)
		end
		return
	end
	local wantedVisible = not not visible
	if record._wantedVisible ~= wantedVisible then
		record._wantedVisible = wantedVisible
		local shown = self._shownDrawings
		local shownIndex = record._shownIndex
		if wantedVisible then
			local index = #shown + 1
			shown[index] = record
			record._shownIndex = index
		elseif shownIndex then
			local lastIndex = #shown
			local last = shown[lastIndex]
			shown[shownIndex] = last
			shown[lastIndex] = nil
			record._shownIndex = nil
			if last ~= record then
				last._shownIndex = shownIndex
			end
		end
	end

	local actualVisible = self.Visible and wantedVisible
	if record._actualVisible ~= actualVisible then
		record._actualVisible = actualVisible
		record._object.Visible = actualVisible
	end
end

function Window:_removeDrawing(record)
	if not record or record._dead then
		return
	end
	record._dead = true
	local shownIndex = record._shownIndex
	if shownIndex then
		local shown = self._shownDrawings
		local lastIndex = #shown
		local last = shown[lastIndex]
		shown[shownIndex] = last
		shown[lastIndex] = nil
		record._shownIndex = nil
		if last ~= record then
			last._shownIndex = shownIndex
		end
	end
	local object = record._object
	if object then
		-- Drawing hosts can throw after an object was removed externally.
		pcall(removeDrawingObject, object)
		record._object = nil
	end
	self._deadDrawingCount = self._deadDrawingCount + 1
end

function Window:_newRegion(owner, priority)
	self._nextRegionOrder = self._nextRegionOrder + 1
	local region = {
		_owner = owner,
		_minimumX = 0,
		_minimumY = 0,
		_maximumX = 0,
		_maximumY = 0,
		_rectangle = {
			_minimum = { X = 0, Y = 0 },
			_maximum = { X = 0, Y = 0 },
		},
		_priority = priority or 0,
		_order = self._nextRegionOrder,
		_dead = false,
	}
	table.insert(self._regions, region)
	return region
end

function Window:_setRegionActive(region, active)
	if not region or region._dead then
		return
	end

	active = not not active
	local index = region._activeIndex
	if active == (index ~= nil) then
		return
	end

	local regions = self._activeRegions
	if active then
		index = #regions + 1
		regions[index] = region
		region._activeIndex = index
		return
	end

	local lastIndex = #regions
	local last = regions[lastIndex]
	regions[index] = last
	regions[lastIndex] = nil
	region._activeIndex = nil
	if last ~= region then
		last._activeIndex = index
	end

	if Nephren._hoveredRegion == region then
		if region._onHover then
			region._onHover(false)
		end
		Nephren._hoveredRegion = nil
	end
	if Nephren._capture == region then
		if region._onCancel then
			region._onCancel()
		end
		Nephren._capture = nil
	end
end

function Window:_removeRegion(region)
	if not region or region._dead then
		return
	end
	self:_setRegionActive(region, false)
	region._dead = true
	region._owner = nil
	region._popupOwner = nil
	region._enabled = nil
	region._onPress = nil
	region._onMove = nil
	region._onRelease = nil
	region._onCancel = nil
	region._onWheel = nil
	region._onHover = nil
	self._deadRegionCount = self._deadRegionCount + 1
end

function Window:_compactStorage(force)
	local drawingCount = #self._drawings
	if
		self._deadDrawingCount > 0
		and (force or self._deadDrawingCount >= 64 or self._deadDrawingCount * 3 >= drawingCount)
	then
		compactDead(self._drawings)
		self._deadDrawingCount = 0
	end

	local regionCount = #self._regions
	if
		self._deadRegionCount > 0
		and (force or self._deadRegionCount >= 32 or self._deadRegionCount * 3 >= regionCount)
	then
		compactDead(self._regions)
		self._deadRegionCount = 0
	end
end

function Window:_baseDrawing(kind, properties)
	return self:_newDrawing(kind, properties, self._baseDrawings)
end

function Window:_ensureTabChrome()
	if self._tabAccent then
		return
	end

	local theme = self.Theme
	self._tabAccent = newGradient(
		self,
		self._baseDrawings,
		5,
		theme.Accent,
		theme.AccentEnd,
		24,
		"Horizontal",
		3
	)
	self._tabStroke = newRoundedRectangle(self, self._baseDrawings, theme.TabStroke, 6, 3, true)
	self._tabInner = newRoundedRectangle(self, self._baseDrawings, theme.Background, 7, 2)
	self._tabBottomMask = self:_baseDrawing("Square", {
		Filled = true,
		Position = self.Position,
		Size = Vector2.new(1, 1),
		Color = theme.Background,
		ZIndex = self:_getZIndex(8),
		Transparency = 1,
		Visible = false,
	})
	self:_show(self._tabAccent, false)
	self:_show(self._tabStroke, false)
	self:_show(self._tabInner, false)
end

function Window:_registerFlag(control, flag)
	if not flag then
		return
	end
	local stack = Nephren._flagStacks[flag]
	if not stack then
		stack = {}
		Nephren._flagStacks[flag] = stack
	end
	stack[#stack + 1] = control
	self._flagControls[flag] = control
	Nephren._flagOwners[flag] = control
	local value = control:GetValue()
	self.Flags[flag] = value
	Nephren.Flags[flag] = value
end

function Window:_setFlag(flag, value, owner)
	if not flag then
		return
	end
	self.Flags[flag] = value
	Nephren.Flags[flag] = value
	owner = owner or self._flagControls[flag]
	if owner and owner._window == self then
		self._flagControls[flag] = owner
	end
	Nephren._flagOwners[flag] = owner
end

function Window:_unregisterFlag(owner, flag)
	if not flag then
		return
	end
	local stack = Nephren._flagStacks[flag]
	if stack then
		removeValue(stack, owner)
		if #stack == 0 then
			Nephren._flagStacks[flag] = nil
			stack = nil
		end
	end

	local windowReplacement
	local globalReplacement
	if stack then
		for index = #stack, 1, -1 do
			local candidate = stack[index]
			if not candidate._destroyed then
				globalReplacement = globalReplacement or candidate
				if candidate._window == self then
					windowReplacement = candidate
					break
				end
			end
		end
	end

	if self._flagControls[flag] == owner then
		self._flagControls[flag] = windowReplacement
		self.Flags[flag] = windowReplacement and windowReplacement:GetValue()
	end
	if Nephren._flagOwners[flag] == owner then
		Nephren._flagOwners[flag] = globalReplacement
		Nephren.Flags[flag] = globalReplacement and globalReplacement:GetValue()
	end
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

	self._outer = newRoundedRectangle(self, self._baseDrawings, theme.Border, 1, 4, true)
	self._windowStroke = newRoundedRectangle(self, self._baseDrawings, theme.Stroke, 2, 3, true)
	self._body = newRoundedRectangle(self, self._baseDrawings, theme.Background, 3, 2)
	self._topbar = newRoundedRectangle(self, self._baseDrawings, theme.Topbar, 4, 2)
	self:_show(self._outer, true)
	self:_show(self._windowStroke, true)
	self:_show(self._body, true)
	self:_show(self._topbar, true)
	self._headerLine = self:_baseDrawing("Line", {
		From = self.Position + Vector2.new(1, theme.HeaderHeight - 1),
		To = self.Position + Vector2.new(self.Size.X - 1, theme.HeaderHeight - 1),
		Color = theme.Border,
		Thickness = 1,
		ZIndex = self:_getZIndex(5),
		Transparency = 1,
		Visible = true,
	})
	self._titleDrawing = self:_baseDrawing("Text", {
		Text = self.Title,
		Font = font,
		Size = theme.TextSize,
		Position = self.Position + Vector2.new(7, centeredTextY(4, 25, theme.TextSize)),
		Color = theme.Text,
		Outline = true,
		OutlineColor = theme.Border,
		OutlineOpacity = 1,
		ZIndex = self:_getZIndex(6),
		Transparency = 1,
		Visible = true,
	})
	self._dragRegion = self:_newRegion(self, 1)
	function self._dragRegion._enabled()
		return self.Visible and self.Draggable and not self._destroyed
	end
	function self._dragRegion._onPress(point)
		self._dragOffset = point - self.Position
		return true
	end
	function self._dragRegion._onMove(point)
		local position = point - self._dragOffset
		Nephren:_queueWindowDrag(self, position:Floor())
	end
	function self._dragRegion._onRelease()
		Nephren:_finishWindowDrag(self, true)
		self._dragOffset = nil
	end
	function self._dragRegion._onCancel()
		Nephren:_finishWindowDrag(self, false)
		self._dragOffset = nil
	end
	self:_setRegionActive(self._dragRegion, true)
end

function Window:_layoutBase()
	local theme = self.Theme
	local position = self.Position
	local size = self.Size

	self:_setPositionSize(self._outer, position, size)
	self:_setPositionSize(
		self._windowStroke,
		position + Vector2.new(1, 1),
		size - Vector2.new(2, 2)
	)
	self:_setPositionSize(self._body, position + Vector2.new(2, 2), size - Vector2.new(4, 4))
	self:_setPositionSize(
		self._topbar,
		position + Vector2.new(2, 2),
		Vector2.new(size.X - 4, theme.HeaderHeight - 2)
	)
	self:_setLine(
		self._headerLine,
		position + Vector2.new(1, theme.HeaderHeight - 1),
		position + Vector2.new(size.X - 1, theme.HeaderHeight - 1)
	)
	self:_setTextPosition(
		self._titleDrawing,
		self.Title,
		position + Vector2.new(7, centeredTextY(4, 25, theme.TextSize))
	)
	setRegionRectangle(
		self._dragRegion,
		position.X + 1,
		position.Y + 1,
		size.X - 2,
		theme.HeaderHeight - 2
	)
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
	end
	if self.SelectedTab then
		self.SelectedTab:_layoutContent()
	end
end

function Window:SetPosition(position)
	if valuesEqual(self.Position, position) then
		return self
	end
	self.Position = position
	self._geometryRevision = self._geometryRevision + 1
	self:_layout()
	return self
end

function Window:SetSize(size)
	size = size:Max(MINIMUM_WINDOW_SIZE)
	if valuesEqual(self.Size, size) then
		return self
	end
	self.Size = size
	self._geometryRevision = self._geometryRevision + 1
	self:_layout()
	return self
end

function Window:SetTitle(title)
	title = tostring(title)
	if self.Title == title then
		return self
	end
	self.Title = title
	self:_setText(self._titleDrawing, self.Title)
	return self
end

function Window:SetVisible(visible)
	visible = not not visible
	if self.Visible == visible then
		return self
	end
	self.Visible = visible
	if not self.Visible then
		local capture = Nephren._capture
		local captureOwner = capture and capture._owner
		if captureOwner == self or (captureOwner and captureOwner._window == self) then
			if capture._onCancel then
				capture._onCancel()
			end
			Nephren._capture = nil
		end
		local hovered = Nephren._hoveredRegion
		local hoveredOwner = hovered and hovered._owner
		if hoveredOwner == self or (hoveredOwner and hoveredOwner._window == self) then
			if hovered._onHover then
				hovered._onHover(false)
			end
			Nephren._hoveredRegion = nil
		end
		if self._openPopup then
			self._openPopup:Close()
		end
		if Nephren._focusedTextbox and Nephren._focusedTextbox._window == self then
			Nephren._focusedTextbox:Blur(true)
		end
		if Nephren._bindingKeybind and Nephren._bindingKeybind._window == self then
			Nephren._bindingKeybind:_cancelBinding()
		end
	else
		self:_layout()
	end
	if self.Visible ~= visible then
		return self
	end

	local shown = self._shownDrawings
	for index = 1, #shown do
		local record = shown[index]
		if not record._dead and record._actualVisible ~= visible then
			record._actualVisible = visible
			record._object.Visible = visible
		end
	end
	return self
end

function Window:Show()
	return self:SetVisible(true)
end

function Window:Hide()
	return self:SetVisible(false)
end

function Window:Toggle()
	return self:SetVisible(not self.Visible)
end

function Window:SelectTab(tabOrName)
	if self._destroyed then
		return false
	end

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

	if not selected or selected._window ~= self or selected._destroyed then
		return false
	end

	if self._selectingTab then
		self._pendingTabSelection = selected
		return true
	end

	self._selectingTab = true
	local target = selected
	while target and not self._destroyed do
		self._pendingTabSelection = nil
		if self._openPopup then
			self._openPopup:Close()
		end

		if
			not self._destroyed
			and not self._pendingTabSelection
			and self.SelectedTab ~= target
		then
			local previous = self.SelectedTab
			self.SelectedTab = target
			if previous then
				previous:_updateHeader()
			end
			target:_updateHeader()
			if previous then
				previous:_syncVisibility(false)
			end
			if not self._destroyed then
				if target._layoutRevision ~= self._geometryRevision then
					target:_layoutContent()
				end
				target:_syncVisibility(true)
			end
		end
		target = self._pendingTabSelection
	end
	self._pendingTabSelection = nil
	self._selectingTab = nil
	return not self._destroyed
end

function Window:AddTab(configuration)
	if self._destroyed then
		return nil
	end

	if type(configuration) == "string" then
		configuration = { Name = configuration }
	else
		configuration = table.clone(configuration or {})
	end

	local tab = Tab.new(self, configuration)
	local tabX = self.Position.X + self.Theme.TitleWidth + self._tabWidthTotal
	table.insert(self.Tabs, tab)
	self._tabWidthTotal = self._tabWidthTotal + tab.Width
	if not self.SelectedTab then
		self.SelectedTab = tab
	end
	tab:_layoutHeader(tabX, self.Position.Y)
	tab:_syncVisibility(self.SelectedTab == tab)
	return tab
end

Window.Tab = Window.AddTab
Window.CreateTab = Window.AddTab

function Window:Destroy()
	if self._destroyed then
		return
	end
	self._destroyed = true
	self._pendingTabSelection = nil
	self._bulkDestroying = true
	Nephren:_finishWindowDrag(self, false)

	if self._openPopup then
		self._openPopup:Close(false)
	end
	if Nephren._focusedTextbox and Nephren._focusedTextbox._window == self then
		Nephren._focusedTextbox:Blur(false)
	end
	if Nephren._bindingKeybind and Nephren._bindingKeybind._window == self then
		Nephren._bindingKeybind = nil
	end
	if
		Nephren._capture
		and Nephren._capture._owner
		and Nephren._capture._owner._window == self
	then
		Nephren._capture = nil
	end
	if
		Nephren._hoveredRegion
		and Nephren._hoveredRegion._owner
		and Nephren._hoveredRegion._owner._window == self
	then
		Nephren._hoveredRegion = nil
	end

	for _, tab in ipairs(self.Tabs) do
		tab._destroyed = true
		for _, section in ipairs(tab.Sections) do
			section._destroyed = true
			for index = #section.Controls, 1, -1 do
				local control = section.Controls[index]
				if not control._destroyed then
					control:Destroy()
				end
			end
			table.clear(section.Controls)
			table.clear(section._drawings)
		end
		table.clear(tab.Sections)
		table.clear(tab._drawings)
	end

	for _, region in ipairs(self._regions) do
		self:_removeRegion(region)
	end
	for _, record in ipairs(self._drawings) do
		self:_removeDrawing(record)
	end
	for flag in pairs(self.Flags) do
		local owner = Nephren._flagOwners[flag]
		if owner and owner._window == self then
			Nephren._flagOwners[flag] = nil
			Nephren.Flags[flag] = nil
		end
	end
	table.clear(self.Flags)
	table.clear(self._flagControls)
	table.clear(self._shownDrawings)
	table.clear(self._activeRegions)
	table.clear(self._drawings)
	table.clear(self._regions)
	table.clear(self._baseDrawings)
	table.clear(self.Tabs)
	self._bulkDestroying = nil
	removeValue(Nephren._windows, self)
	if #Nephren._windows == 0 and not Nephren._unloading then
		Nephren:Unload()
	end
end

Window.Remove = Window.Destroy

function Tab.new(window, configuration)
	local self = setmetatable({
		_window = window,
		Name = optionText(configuration, "Tab"),
		Width = configuration.Width or window.Theme.TabWidth,
		Sections = {},
		_drawings = {},
		_destroyed = false,
	}, Tab)

	self:_createHeader()
	return self
end

function Tab:_createHeader()
	local window = self._window
	local theme = window.Theme
	local font = getFont(theme)

	window:_ensureTabChrome()
	self._accent = window._tabAccent
	self._stroke = window._tabStroke
	self._inner = window._tabInner
	self._bottomMask = window._tabBottomMask
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
		ZIndex = window:_getZIndex(9),
		Transparency = 1,
		Visible = true,
	}, self._drawings)

	self._region = window:_newRegion(self, 10)
	function self._region._enabled()
		return window.Visible and not self._destroyed
	end
	function self._region._onPress()
		window:SelectTab(self)
		return false
	end
	function self._region._onHover(hovered)
		self._hovered = hovered
		self:_updateHeader()
	end
	window:_setRegionActive(self._region, true)
end

function Tab:_updateHeader()
	local window = self._window
	local theme = window.Theme
	local selected = window.SelectedTab == self

	if selected then
		window:_setColor(self._inner, theme.Background)
		window:_setColor(self._stroke, theme.TabStroke)
		window:_setGradient(self._accent, theme.Accent, theme.AccentEnd)
		window:_setColor(self._bottomMask, theme.Background)
		window:_show(self._accent, true)
		window:_show(self._stroke, true)
		window:_show(self._inner, true)
		window:_show(self._bottomMask, true)
		if self._headerX then
			self:_layoutChrome()
		end
	end
	local textColor = theme.MutedText
	if selected or self._hovered then
		textColor = theme.Text
	end
	window:_setColor(self._text, textColor)
end

function Tab:_layoutChrome()
	local window = self._window
	local x, y = self._headerX, self._headerY
	local headerHeight = window.Theme.HeaderHeight
	window:_setPositionSize(self._accent, Vector2.new(x, y + 3), Vector2.new(self.Width, 6))
	window:_setPositionSize(
		self._stroke,
		Vector2.new(x, y + 5),
		Vector2.new(self.Width, headerHeight - 4)
	)
	window:_setPositionSize(
		self._inner,
		Vector2.new(x + 1, y + 6),
		Vector2.new(self.Width - 2, headerHeight - 5)
	)
	window:_setPositionSize(
		self._bottomMask,
		Vector2.new(x, y + headerHeight - 1),
		Vector2.new(self.Width - 2, 1)
	)
end

function Tab:_layoutHeader(x, y)
	local window = self._window
	local headerHeight = window.Theme.HeaderHeight
	self._headerX, self._headerY = x, y
	window:_setPosition(
		self._text,
		Vector2.new(x + self.Width * 0.5, y + centeredTextY(4, 25, window.Theme.TextSize))
	)
	setRegionRectangle(self._region, x, y + 1, self.Width, headerHeight - 1)
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
	local leftCursor, rightCursor = top, top

	for _, section in ipairs(self.Sections) do
		local side = section.Side
		local width = leftWidth
		local x = leftX
		if side == "Right" then
			width = rightWidth
			x = rightX
		end
		if side == "Right" then
			rightCursor = rightCursor + section:_layout(x, rightCursor, width) + 10
		else
			leftCursor = leftCursor + section:_layout(x, leftCursor, width) + 10
		end
	end
	self._layoutRevision = window._geometryRevision
end

function Tab:_shiftSectionsAfter(section, delta)
	if delta == 0 then
		return
	end

	local found = false
	for _, candidate in ipairs(self.Sections) do
		if candidate == section then
			found = true
		elseif
			found
			and candidate.Side == section.Side
			and candidate._x
			and not candidate._destroyed
		then
			candidate:_layout(candidate._x, candidate._y + delta, candidate._width)
		end
	end
end

function Tab:_syncVisibility(active)
	if active == nil then
		active = self._window.SelectedTab == self
	end
	local sections = table.clone(self.Sections)
	for _, section in ipairs(sections) do
		if not section._destroyed then
			section:_syncVisibility(active)
		end
	end
end

function Tab:AddSection(configuration)
	if self._destroyed or self._window._destroyed then
		return nil
	end

	if type(configuration) == "string" then
		configuration = { Name = configuration }
	else
		configuration = table.clone(configuration or {})
	end

	local side = configuration.Side or configuration.Column or "Left"
	if side == 2 or string.lower(tostring(side)) == "right" then
		side = "Right"
	else
		side = "Left"
	end

	local section = Section.new(self, configuration, side)
	table.insert(self.Sections, section)
	local active = self._window.SelectedTab == self
	if active then
		local previous
		for index = #self.Sections - 1, 1, -1 do
			local candidate = self.Sections[index]
			if candidate.Side == side then
				previous = candidate
				break
			end
		end
		if previous and previous._x then
			section:_layout(
				previous._x,
				previous._y + previous:_totalHeight() + 10,
				previous._width
			)
		else
			local window = self._window
			local theme = window.Theme
			local contentX = window.Position.X + 1
			local available = window.Size.X - 2 - theme.SectionPadding * 2 - theme.SectionGap
			local leftWidth = math.floor(available * 0.5)
			local rightWidth = available - leftWidth
			local leftX = contentX + theme.SectionPadding
			local x = leftX
			local width = leftWidth
			if side == "Right" then
				x = leftX + leftWidth + theme.SectionGap
				width = rightWidth
			end
			local y = window.Position.Y + 1 + theme.HeaderHeight + 15
			section:_layout(x, y, width)
		end
		self._layoutRevision = self._window._geometryRevision
	else
		self._layoutRevision = nil
	end
	section:_syncVisibility(active)
	return section
end

Tab.Section = Tab.AddSection
Tab.CreateSection = Tab.AddSection

function Tab:Select()
	self._window:SelectTab(self)
	return self
end

function Section.new(tab, configuration, side)
	local self = setmetatable({
		_tab = tab,
		_window = tab._window,
		Name = optionText(configuration, "Container"),
		Side = side,
		Height = configuration.Height,
		ControlWidth = configuration.ControlWidth,
		Controls = {},
		_contentHeightValue = 17,
		_drawings = {},
		_destroyed = false,
		_parentVisible = false,
	}, Section)

	self:_createFrame()
	return self
end

function Section:_createFrame()
	local window = self._window
	local theme = window.Theme
	local font = getFont(theme)

	self._outer = newRoundedRectangle(window, self._drawings, theme.Border, 4, 2, true)
	self._stroke = newRoundedRectangle(window, self._drawings, theme.Stroke, 6, 3, true)
	self._inner = newRoundedRectangle(window, self._drawings, theme.Panel, 7, 2)
	self._accent =
		newGradient(window, self._drawings, 5, theme.Accent, theme.AccentEnd, 24, "Horizontal", 3)
	self._title = window:_newDrawing("Text", {
		Text = self.Name,
		Font = font,
		Size = theme.TextSize,
		Position = window.Position,
		Color = theme.Text,
		Outline = true,
		OutlineColor = theme.Border,
		OutlineOpacity = 1,
		ZIndex = window:_getZIndex(9),
		Transparency = 1,
		Visible = false,
	}, self._drawings)
end

function Section:_contentHeight()
	return self._contentHeightValue
end

function Section:_bodyHeight()
	return self.Height or math.max(38, self:_contentHeight())
end

function Section:_totalHeight()
	return 20 + self:_bodyHeight()
end

function Section:_layoutFrame(x, y, width)
	local window = self._window
	local bodyY = y + 20
	local bodyHeight = self:_bodyHeight()
	self._x = x
	self._y = y
	self._width = width
	self._bodyY = bodyY

	window:_setPositionSize(
		self._outer,
		Vector2.new(x - 1, bodyY - 1),
		Vector2.new(width + 2, bodyHeight + 2)
	)
	window:_setPositionSize(
		self._stroke,
		Vector2.new(x, bodyY + 2),
		Vector2.new(width, bodyHeight - 2)
	)
	window:_setPositionSize(
		self._inner,
		Vector2.new(x + 1, bodyY + 3),
		Vector2.new(width - 2, bodyHeight - 4)
	)
	window:_setPositionSize(self._accent, Vector2.new(x, bodyY), Vector2.new(width, 4))
	window:_setTextPosition(
		self._title,
		self.Name,
		Vector2.new(x + 12, centeredTextY(y - 2, 22, window.Theme.TextSize))
	)

	local controlWidth = self.ControlWidth
		or math.min(window.Theme.ControlWidth, math.max(80, width - 20))
	self._controlWidth = controlWidth
	self._controlRowWidth = math.max(controlWidth, width - 25)
	return bodyHeight
end

function Section:_layoutControls(firstIndex)
	local controls = self.Controls
	local cursor = self._bodyY + 12
	firstIndex = firstIndex or 1
	for index = 1, firstIndex - 1 do
		cursor = cursor + controls[index]._height
	end
	for index = firstIndex, #controls do
		local control = controls[index]
		control._rowWidth = self._controlRowWidth
		control:_layout(self._x + 9, cursor, self._controlWidth)
		cursor = cursor + control._height
	end
end

function Section:_layout(x, y, width)
	local bodyHeight = self:_layoutFrame(x, y, width)
	self:_layoutControls(1)
	return 20 + bodyHeight
end

function Section:_removeControl(control)
	if self._window._bulkDestroying then
		return
	end
	local index = table.find(self.Controls, control)
	if not index then
		return
	end

	local oldBodyHeight = self:_bodyHeight()
	table.remove(self.Controls, index)
	self._contentHeightValue = self._contentHeightValue - control._height

	if self._destroyed or self._window.SelectedTab ~= self._tab or not self._x then
		self._tab._layoutRevision = nil
		return
	end

	local bodyHeight = self:_layoutFrame(self._x, self._y, self._width)
	self:_layoutControls(index)
	self._tab:_shiftSectionsAfter(self, bodyHeight - oldBodyHeight)
end

function Section:_syncVisibility(parentVisible)
	self._parentVisible = parentVisible and not self._destroyed
	for _, drawing in ipairs(self._drawings) do
		self._window:_show(drawing, self._parentVisible)
	end
	local controls = table.clone(self.Controls)
	for _, control in ipairs(controls) do
		if not control._destroyed then
			control:_syncVisibility(self._parentVisible)
		end
	end
end

function Section:_add(control)
	if self._destroyed or self._tab._destroyed or self._window._destroyed then
		control:Destroy()
		return nil
	end

	local oldBodyHeight = self:_bodyHeight()
	local oldContentHeight = self._contentHeightValue
	table.insert(self.Controls, control)
	self._contentHeightValue = self._contentHeightValue + control._height
	self._window:_registerFlag(control, control.Flag)
	local active = self._window.SelectedTab == self._tab
	if active and self._x then
		local bodyHeight = self:_layoutFrame(self._x, self._y, self._width)
		control._rowWidth = self._controlRowWidth
		control:_layout(self._x + 9, self._bodyY + oldContentHeight - 5, self._controlWidth)
		self._tab:_shiftSectionsAfter(self, bodyHeight - oldBodyHeight)
	elseif active then
		self._tab:_layoutContent()
	else
		self._tab._layoutRevision = nil
	end
	control:_syncVisibility(active)
	return control
end

function Section:SetTitle(title)
	title = tostring(title)
	if self.Name == title then
		return self
	end
	self.Name = title
	self._window:_setText(self._title, self.Name)
	return self
end

function Section:SetHeight(height)
	if self.Height == height then
		return self
	end
	local oldBodyHeight = self:_bodyHeight()
	self.Height = height
	if self._window.SelectedTab == self._tab and self._x then
		local bodyHeight = self:_layoutFrame(self._x, self._y, self._width)
		self._tab:_shiftSectionsAfter(self, bodyHeight - oldBodyHeight)
	else
		self._tab._layoutRevision = nil
	end
	return self
end

function Control:_initialize(section, configuration, height)
	self._section = section
	self._tab = section._tab
	self._window = section._window
	self._library = Nephren
	self.Format = configuration.Format
	self.AllowUnknown = configuration.AllowUnknown == true
	self.ControlTextSize = configuration.Size
	self._drawings = {}
	self._regions = {}
	self._height = height
	self._destroyed = false
	self._parentVisible = false
	self._hovered = false
	self.Text = optionText(configuration)
	self.Flag = configuration.Flag
	self.Callback = configuration.Callback
end

function Control:_draw(kind, properties, bucket)
	return self._window:_newDrawing(kind, properties, bucket or self._drawings)
end

function Control:_region(priority)
	local region = self._window:_newRegion(self, priority or 20)
	function region._enabled()
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
	for _, region in ipairs(self._regions) do
		self._window:_setRegionActive(region, self._parentVisible)
	end
end

function Control:_changed(value, silent)
	self._window:_setFlag(self.Flag, value, self)
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
	text = tostring(text)
	if self.Text == text then
		return self
	end
	self.Text = text
	if self._label then
		self._window:_setText(self._label, self.Text)
	elseif self._text then
		self._window:_setText(self._text, self.Text)
	end
	return self
end

function Control:Destroy()
	if self._destroyed then
		return
	end
	self._destroyed = true
	for _, region in ipairs(self._regions) do
		self._window:_removeRegion(region)
	end
	for _, drawing in ipairs(self._drawings) do
		self._window:_removeDrawing(drawing)
	end
	self._window:_unregisterFlag(self, self.Flag)
	self._section:_removeControl(self)
	if not self._window._bulkDestroying then
		self._window:_compactStorage(false)
	end
	table.clear(self._drawings)
	table.clear(self._regions)
end

Control.Remove = Control.Destroy

local function createBox(control, localZIndex, fillColor, radius, innerRadius, strokeColor)
	local theme = control._window.Theme
	local window = control._window
	local rounding = radius or 4
	local innerRounding = innerRadius
	if innerRounding == nil then
		innerRounding = 1
	end
	local outer = newRoundedRectangle(
		window,
		control._drawings,
		theme.ControlBorder,
		localZIndex or 10,
		rounding
	)
	local stroke = newRoundedRectangle(
		window,
		control._drawings,
		strokeColor or theme.ControlStroke,
		(localZIndex or 10) + 1,
		math.max(0, innerRounding + 1)
	)
	local inner = newRoundedRectangle(
		window,
		control._drawings,
		fillColor or theme.Control,
		(localZIndex or 10) + 2,
		innerRounding
	)
	return outer, inner, stroke
end

local function layoutBox(window, outer, inner, stroke, x, y, width, height)
	window:_setPositionSize(outer, Vector2.new(x, y), Vector2.new(width, height))
	window:_setPositionSize(stroke, Vector2.new(x + 1, y + 1), Vector2.new(width - 2, height - 2))
	window:_setPositionSize(inner, Vector2.new(x + 2, y + 2), Vector2.new(width - 4, height - 4))
end

local function createLabelDrawing(control, text, localZIndex)
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
		ZIndex = control._window:_getZIndex(localZIndex or 14),
		Transparency = 1,
		Visible = false,
	})
end

function Button.new(section, configuration, callback)
	configuration = normalizeConfiguration(configuration, callback)
	local self = setmetatable({}, Button)
	Control._initialize(self, section, configuration, configuration.Height or 37)

	self._outer, self._inner, self._highlight = createBox(self, 10)
	self._text = createLabelDrawing(self, self.Text, 14)
	self._window:_set(self._text, { Center = true })
	self._region = self:_region(20)
	function self._region._onPress()
		self._pressed = true
		self:_updateStyle()
		return true
	end
	function self._region._onRelease(point)
		local wasPressed = self._pressed
		self._pressed = false
		self:_updateStyle()
		if wasPressed and pointInRegion(point, self._region) then
			safeCall(self.Callback, self)
		end
	end
	function self._region._onCancel()
		self._pressed = false
		self:_updateStyle()
	end
	function self._region._onHover(hovered)
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
	self._window:_setColor(self._inner, color)
end

function Button:_layout(x, y, width)
	local actualWidth = width + 2
	layoutBox(self._window, self._outer, self._inner, self._highlight, x, y, actualWidth, 27)
	self._window:_setTextPosition(
		self._text,
		self.Text,
		Vector2.new(x + actualWidth * 0.5, centeredTextY(y + 2, 25, self._window.Theme.TextSize))
	)
	setRegionRectangle(self._region, x, y, actualWidth, 27)
end

function Button:Press()
	safeCall(self.Callback, self)
	return self
end

function Button:GetValue()
	return nil
end

function Checkbox.new(section, configuration)
	configuration = normalizeConfiguration(configuration)
	local self = setmetatable({}, Checkbox)
	Control._initialize(self, section, configuration, configuration.Height or 26)
	self.Value = configuration.Default == true or configuration.Value == true
	self._addons = {}

	local theme = self._window.Theme
	self._boxOuter = newRoundedRectangle(self._window, self._drawings, theme.ControlBorder, 10, 3)
	self._boxStroke = newRoundedRectangle(self._window, self._drawings, theme.ControlStroke, 11, 1)
	self._boxInner = newRoundedRectangle(self._window, self._drawings, theme.Input, 12, 0)
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
		table.insert(
			self._checkCorners,
			self:_draw("Square", {
				Filled = true,
				Color = theme.Control,
				Position = self._window.Position,
				Size = Vector2.new(1, 1),
				ZIndex = self._window:_getZIndex(14),
				Transparency = 1,
				Visible = false,
			})
		)
	end
	self._label = createLabelDrawing(self, self.Text, 14)

	self._region = self:_region(20)
	function self._region._onPress()
		self:SetValue(not self.Value)
		return false
	end
	function self._region._onHover(hovered)
		self._hovered = hovered
		self:_updateStyle()
	end
	self:_updateStyle()

	return section:_add(self)
end

function Checkbox:_updateStyle()
	local theme = self._window.Theme
	local innerColor = theme.Control
	if self._hovered then
		innerColor = theme.ControlHover
	end
	local checkedVisible = self._parentVisible and self.Value
	self._window:_setColor(self._boxInner, innerColor)
	self._window:_setGradient(self._check, theme.Accent, theme.AccentEnd)
	self._window:_show(self._check, checkedVisible)
	for _, corner in ipairs(self._checkCorners) do
		self._window:_setColor(corner, innerColor)
		self._window:_show(corner, checkedVisible)
	end
end

function Checkbox:_layout(x, y, width)
	self._x = x
	self._y = y
	self._width = width
	self._window:_setPositionSize(self._boxOuter, Vector2.new(x, y + 4), Vector2.new(14, 14))
	self._window:_setPositionSize(self._boxStroke, Vector2.new(x + 1, y + 5), Vector2.new(12, 12))
	self._window:_setPositionSize(self._boxInner, Vector2.new(x + 2, y + 6), Vector2.new(10, 10))
	self._window:_setPositionSize(self._check, Vector2.new(x + 3, y + 7), Vector2.new(8, 8))
	local checkRight = x + 10
	local checkBottom = y + 14
	local cornerPositions = {
		Vector2.new(x + 3, y + 7),
		Vector2.new(checkRight, y + 7),
		Vector2.new(x + 3, checkBottom),
		Vector2.new(checkRight, checkBottom),
	}
	for index, position in ipairs(cornerPositions) do
		self._window:_setPosition(self._checkCorners[index], position)
	end
	self._window:_setTextPosition(
		self._label,
		self.Text,
		Vector2.new(x + 21, centeredTextY(y + 5, 14, self._window.Theme.TextSize))
	)
	setRegionRectangle(self._region, x, y + 3, math.min(width, 21 + textLength(self.Text) * 7), 16)

	local addonX = x + (self._rowWidth or width)
	for index = #self._addons, 1, -1 do
		local addon = self._addons[index]
		local addonWidth = addon:_preferredWidth()
		addonX = addonX - addonWidth
		addon:_layout(addonX, y, addonWidth)
		addonX = addonX - 6
	end
end

function Checkbox:_syncVisibility(parentVisible)
	Control._syncVisibility(self, parentVisible)
	self:_updateStyle()
	local addons = table.clone(self._addons)
	for _, addon in ipairs(addons) do
		if not addon._destroyed then
			addon:_syncVisibility(self._parentVisible)
		end
	end
end

function Checkbox:SetValue(value, silent)
	value = not not value
	local changed = self.Value ~= value
	self.Value = value
	for _, addon in ipairs(self._addons) do
		if addon._checkbox == self and addon.Mode == "Toggle" then
			addon.State = self.Value
		end
	end
	if changed then
		self:_updateStyle()
	end
	self:_changed(self.Value, silent)
	return self
end

Checkbox.Set = Checkbox.SetValue

function Checkbox:Destroy()
	if self._destroyed or self._destroying then
		return
	end
	self._destroying = true
	while #self._addons > 0 do
		local addon = self._addons[#self._addons]
		addon:Destroy()
		if self._addons[#self._addons] == addon then
			self._addons[#self._addons] = nil
		end
	end
	self._destroying = nil
	Control.Destroy(self)
end

local function initializeKeybind(target, parent, configuration, normalized)
	if not normalized then
		configuration = normalizeConfiguration(configuration)
	end
	target._parent = parent
	target._window = parent._window
	target._library = Nephren
	target._drawings = {}
	target._regions = {}
	target._destroyed = false
	target._parentVisible = false
	target._binding = false
	target.Value = configuration.Default or configuration.Value or configuration.Key
	target.Mode = configuration.Mode or "Press"
	target.Callback = configuration.Callback
	target.Changed = configuration.Changed
	target.Flag = configuration.Flag
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
		ZIndex = target._window:_getZIndex(16),
		Transparency = 1,
		Visible = false,
	}, target._drawings)

	target._region = target._window:_newRegion(target, 30)
	function target._region._enabled()
		return target._parentVisible and not target._destroyed
	end
	function target._region._onPress()
		target:_startBinding()
		return false
	end
	function target._region._onHover(hovered)
		target._hovered = hovered
		target:_updateText()
	end

	Nephren:_registerKeybind(target)
	target:_updateText()
end

function KeybindAddon.new(parent, configuration, normalized)
	local self = setmetatable({}, KeybindAddon)
	initializeKeybind(self, parent, configuration, normalized)
	return self
end

function KeybindAddon:_preferredWidth()
	local display
	if self._binding then
		display = "..."
	elseif self.Value == nil then
		display = "None"
	elseif self._cachedKeyToken == self.Value then
		display = self._cachedKeyName
	else
		display = keyName(self._library, self.Value)
		self._cachedKeyToken = self.Value
		self._cachedKeyName = display
	end
	return math.clamp(textLength(display) * 6 + 6, 14, 52)
end

function KeybindAddon:_updateText()
	local theme = self._window.Theme
	local display
	if self._binding then
		display = "..."
	elseif self.Value then
		local name
		if self._cachedKeyToken == self.Value then
			name = self._cachedKeyName
		else
			name = keyName(self._library, self.Value)
			self._cachedKeyToken = self.Value
			self._cachedKeyName = name
		end
		display = "[" .. name .. "]"
	else
		display = "[-]"
	end
	local color = theme.MutedText
	if self._binding then
		color = theme.Accent
	elseif self._hovered then
		color = theme.Text
	end
	self._window:_setTextColor(self._text, display, color)
end

function KeybindAddon:_layout(x, y, width)
	self._x = x
	self._y = y
	self._width = width
	self._window:_setPosition(self._text, Vector2.new(x, y + 5))
	setRegionRectangle(self._region, x - 2, y + 3, width + 4, 15)
end

function KeybindAddon:_syncVisibility(parentVisible)
	self._parentVisible = parentVisible and not self._destroyed
	for _, drawing in ipairs(self._drawings) do
		self._window:_show(drawing, self._parentVisible)
	end
	self._window:_setRegionActive(self._region, self._parentVisible)
	if not self._parentVisible and self._binding then
		self:_cancelBinding()
	end
end

function KeybindAddon:_startBinding()
	self._binding = true
	self._library:_setBindingKeybind(self)
	self:_updateText()
end

function KeybindAddon:_cancelBinding()
	self._binding = false
	if self._library._bindingKeybind == self then
		self._library._bindingKeybind = nil
	end
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
	self._library:_setKeybindToken(self, token)
	if self._destroyed then
		return
	end
	self:_updateText()
	if self.Flag then
		self._window:_setFlag(self.Flag, self.Value, self)
	end
	safeCall(self.Changed, self.Value, self)
	local parent = self._parent
	if parent and parent._x then
		parent:_layout(parent._x, parent._y, parent._width)
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
	local changed = self._library:_setKeybindToken(self, value)
	if self._destroyed then
		return self
	end
	local currentValue = self.Value
	self:_updateText()
	if self.Flag then
		self._window:_setFlag(self.Flag, currentValue, self)
	end
	if not silent then
		safeCall(self.Changed, currentValue, self)
	end
	local parent = self._parent
	if changed and parent and parent._x then
		parent:_layout(parent._x, parent._y, parent._width)
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
	if self.Mode == "Hold" and self.State then
		self:_inputEnded()
		if self._destroyed then
			return
		end
	end
	self._destroyed = true
	if Nephren._bindingKeybind == self then
		Nephren._bindingKeybind = nil
	end
	self._window:_removeRegion(self._region)
	for _, drawing in ipairs(self._drawings) do
		self._window:_removeDrawing(drawing)
	end
	self._window:_unregisterFlag(self, self.Flag)
	Nephren:_unregisterKeybind(self)
	local parent = self._parent
	local addons = parent and parent._addons
	if addons then
		removeValue(addons, self)
		if not parent._destroying and parent._x then
			parent:_layout(parent._x, parent._y, parent._width)
		end
	end
	if not self._window._bulkDestroying then
		self._window:_compactStorage(false)
	end
	table.clear(self._drawings)
	table.clear(self._regions)
end

KeybindAddon.Remove = KeybindAddon.Destroy

function Checkbox:AddKeybind(configuration)
	if self._destroyed or self._destroying or self._window._destroyed then
		return nil
	end

	configuration = normalizeConfiguration(configuration)
	if configuration.Mode == nil then
		configuration.Mode = "Toggle"
	end
	local addon = KeybindAddon.new(self, configuration, true)
	addon._checkbox = self
	addon.State = self.Value
	table.insert(self._addons, addon)
	if addon.Flag then
		self._window:_registerFlag(addon, addon.Flag)
	end
	if self._x then
		self:_layout(self._x, self._y, self._width)
	end
	addon:_syncVisibility(self._parentVisible)
	return addon
end

local function initializeColorPicker(target, parent, configuration, normalized)
	if not normalized then
		configuration = normalizeConfiguration(configuration)
	end
	target._parent = parent
	target._window = parent._window
	target._library = Nephren
	target._drawings = {}
	target._popupDrawings = {}
	target._regions = {}
	target._destroyed = false
	target._parentVisible = false
	target.Open = false
	target.Value = configuration.Default or configuration.Value or target._window.Theme.Accent
	target.Callback = configuration.Callback
	target.Flag = configuration.Flag
	target.Rainbow = configuration.Rainbow == true
	target.RainbowSpeed = tonumber(configuration.RainbowSpeed) or 0.12
	target.Hue, target.Saturation, target.Brightness = target.Value:ToHSV()

	local window = target._window
	local theme = window.Theme
	target._swatchOuter = window:_newDrawing("Square", {
		Filled = true,
		Color = theme.Border,
		Position = window.Position,
		Size = Vector2.new(1, 1),
		ZIndex = window:_getZIndex(15),
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

	target._swatchRegion = window:_newRegion(target, 30)
	target._swatchRegion._popupOwner = target
	function target._swatchRegion._enabled()
		return target._parentVisible and not target._destroyed
	end
	function target._swatchRegion._onPress()
		if target.Open then
			target:Close()
		else
			target:OpenPopup()
		end
		return false
	end
	target._regions[1] = target._swatchRegion

	function target:_ensurePopup()
		if target._popupCreated then
			return
		end
		target._popupCreated = true

		local function popupDraw(kind, properties)
			return window:_newDrawing(kind, properties, target._popupDrawings)
		end

		target._popupOuter =
			newRoundedRectangle(window, target._popupDrawings, theme.ControlBorder, 200, 4)
		target._popupStroke =
			newRoundedRectangle(window, target._popupDrawings, theme.InputStroke, 201, 2)
		target._popupInner =
			newRoundedRectangle(window, target._popupDrawings, theme.Input, 202, 1)
		target._fieldBorder = popupDraw("Square", {
			Filled = true,
			Color = theme.ControlBorder,
			Position = window.Position,
			Size = Vector2.new(1, 1),
			ZIndex = window:_getZIndex(203),
			Transparency = 1,
			Visible = false,
		})
		target._hueColumns = table.create(COLOR_FIELD_COLUMNS)
		for column = 1, COLOR_FIELD_COLUMNS do
			target._hueColumns[column] = popupDraw("Square", {
				Filled = true,
				Color = colorFieldHues[column],
				Position = window.Position,
				Size = Vector2.new(1, 1),
				ZIndex = window:_getZIndex(205),
				Transparency = 1,
				Visible = false,
			})
		end
		target._saturationRows = table.create(COLOR_FIELD_ROWS)
		for row = 1, COLOR_FIELD_ROWS do
			target._saturationRows[row] = popupDraw("Square", {
				Filled = true,
				Color = COLOR_WHITE,
				Position = window.Position,
				Size = Vector2.new(1, 1),
				ZIndex = window:_getZIndex(206),
				Transparency = (row - 1) / (COLOR_FIELD_ROWS - 1),
				Visible = false,
			})
		end

		target._crosshairOuterHorizontal = popupDraw("Line", {
			From = window.Position,
			To = window.Position,
			Color = theme.Border,
			Thickness = 3,
			ZIndex = window:_getZIndex(208),
			Transparency = 1,
			Visible = false,
		})
		target._crosshairOuterVertical = popupDraw("Line", {
			From = window.Position,
			To = window.Position,
			Color = theme.Border,
			Thickness = 3,
			ZIndex = window:_getZIndex(208),
			Transparency = 1,
			Visible = false,
		})
		target._crosshairHorizontal = popupDraw("Line", {
			From = window.Position,
			To = window.Position,
			Color = theme.Text,
			Thickness = 1,
			ZIndex = window:_getZIndex(209),
			Transparency = 1,
			Visible = false,
		})
		target._crosshairVertical = popupDraw("Line", {
			From = window.Position,
			To = window.Position,
			Color = theme.Text,
			Thickness = 1,
			ZIndex = window:_getZIndex(209),
			Transparency = 1,
			Visible = false,
		})

		target._valueBorder = popupDraw("Square", {
			Filled = true,
			Color = theme.ControlBorder,
			Position = window.Position,
			Size = Vector2.new(1, 1),
			ZIndex = window:_getZIndex(203),
			Transparency = 1,
			Visible = false,
		})
		target._valueSegments = table.create(COLOR_VALUE_SEGMENTS)
		for segment = 1, COLOR_VALUE_SEGMENTS do
			target._valueSegments[segment] = popupDraw("Square", {
				Filled = true,
				Color = colorValueColors[segment],
				Position = window.Position,
				Size = Vector2.new(1, 10),
				ZIndex = window:_getZIndex(205),
				Transparency = 1,
				Visible = false,
			})
		end
		target._valueMarkerOuter = popupDraw("Line", {
			From = window.Position,
			To = window.Position,
			Color = theme.Border,
			Thickness = 3,
			ZIndex = window:_getZIndex(208),
			Transparency = 1,
			Visible = false,
		})
		target._valueMarker = popupDraw("Line", {
			From = window.Position,
			To = window.Position,
			Color = theme.Text,
			Thickness = 1,
			ZIndex = window:_getZIndex(209),
			Transparency = 1,
			Visible = false,
		})

		target._rainbowOuter =
			newRoundedRectangle(window, target._popupDrawings, theme.ControlBorder, 204, 3)
		target._rainbowStroke =
			newRoundedRectangle(window, target._popupDrawings, theme.ControlStroke, 205, 1)
		target._rainbowInner =
			newRoundedRectangle(window, target._popupDrawings, theme.Control, 206, 1)
		target._rainbowCheck =
			newRoundedRectangle(window, target._popupDrawings, theme.Accent, 207, 1)
		target._rainbowText = popupDraw("Text", {
			Text = "Rainbow",
			Font = getFont(theme),
			Size = theme.TextSize,
			Position = window.Position,
			Color = theme.Text,
			Outline = true,
			OutlineColor = theme.Border,
			OutlineOpacity = 1,
			ZIndex = window:_getZIndex(207),
			Transparency = 1,
			Visible = false,
		})

		target._redGreenBlueOuter =
			newRoundedRectangle(window, target._popupDrawings, theme.ControlBorder, 204, 4)
		target._redGreenBlueStroke =
			newRoundedRectangle(window, target._popupDrawings, theme.InputStroke, 205, 2)
		target._redGreenBlueInner =
			newRoundedRectangle(window, target._popupDrawings, theme.Input, 206, 1)
		target._redGreenBlueText = popupDraw("Text", {
			Text = "RGB Value",
			Font = getFont(theme),
			Size = theme.TextSize,
			Position = window.Position,
			Color = theme.Text,
			Outline = true,
			OutlineColor = theme.Border,
			OutlineOpacity = 1,
			ZIndex = window:_getZIndex(207),
			Transparency = 1,
			Visible = false,
		})
		target._hexadecimalOuter =
			newRoundedRectangle(window, target._popupDrawings, theme.ControlBorder, 204, 4)
		target._hexadecimalStroke =
			newRoundedRectangle(window, target._popupDrawings, theme.InputStroke, 205, 2)
		target._hexadecimalInner =
			newRoundedRectangle(window, target._popupDrawings, theme.Input, 206, 1)
		target._hexadecimalText = popupDraw("Text", {
			Text = "HEX Value",
			Font = getFont(theme),
			Size = theme.TextSize,
			Position = window.Position,
			Color = theme.Text,
			Outline = true,
			OutlineColor = theme.Border,
			OutlineOpacity = 1,
			ZIndex = window:_getZIndex(207),
			Transparency = 1,
			Visible = false,
		})

		target._popupRegion = window:_newRegion(target, 210)
		target._popupRegion._popupOwner = target
		function target._popupRegion._enabled()
			return target._parentVisible and target.Open and not target._destroyed
		end

		target._fieldRegion = window:_newRegion(target, 230)
		target._fieldRegion._popupOwner = target
		target._fieldRegion._enabled = target._popupRegion._enabled
		function target._fieldRegion._onPress(point)
			if target._editing then
				target:Blur(true)
			end
			target:_setFieldFromPoint(point)
			target._draggingField = true
			return true
		end
		function target._fieldRegion._onMove(point)
			if target._draggingField then
				target:_setFieldFromPoint(point)
			end
		end
		function target._fieldRegion._onRelease()
			target._draggingField = false
		end
		target._fieldRegion._onCancel = target._fieldRegion._onRelease

		target._valueRegion = window:_newRegion(target, 230)
		target._valueRegion._popupOwner = target
		target._valueRegion._enabled = target._popupRegion._enabled
		function target._valueRegion._onPress(point)
			if target._editing then
				target:Blur(true)
			end
			target:_setBrightnessFromPoint(point)
			target._draggingValue = true
			return true
		end
		function target._valueRegion._onMove(point)
			if target._draggingValue then
				target:_setBrightnessFromPoint(point)
			end
		end
		function target._valueRegion._onRelease()
			target._draggingValue = false
		end
		target._valueRegion._onCancel = target._valueRegion._onRelease

		target._rainbowRegion = window:_newRegion(target, 230)
		target._rainbowRegion._popupOwner = target
		target._rainbowRegion._enabled = target._popupRegion._enabled
		function target._rainbowRegion._onPress()
			if target._editing then
				target:Blur(true)
			end
			target:SetRainbow(not target.Rainbow)
			return false
		end

		target._redGreenBlueRegion = window:_newRegion(target, 230)
		target._redGreenBlueRegion._popupOwner = target
		target._redGreenBlueRegion._enabled = target._popupRegion._enabled
		function target._redGreenBlueRegion._onPress()
			target:_focusField("RGB")
			return false
		end
		target._hexadecimalRegion = window:_newRegion(target, 230)
		target._hexadecimalRegion._popupOwner = target
		target._hexadecimalRegion._enabled = target._popupRegion._enabled
		function target._hexadecimalRegion._onPress()
			target:_focusField("HEX")
			return false
		end

		for _, region in ipairs({
			target._popupRegion,
			target._fieldRegion,
			target._valueRegion,
			target._rainbowRegion,
			target._redGreenBlueRegion,
			target._hexadecimalRegion,
		}) do
			table.insert(target._regions, region)
		end
		target._ensurePopup = noOperation
	end
	Nephren:_setRainbowActive(target, target.Rainbow)
	target._visualDirty = false
end

function ColorPickerAddon.new(parent, configuration, normalized)
	local self = setmetatable({}, ColorPickerAddon)
	initializeColorPicker(self, parent, configuration, normalized)
	return self
end

function ColorPickerAddon:_preferredWidth()
	return 18
end

function ColorPickerAddon:_redGreenBlueString()
	return string.format(
		"%d, %d, %d",
		math.round(self.Value.R * 255),
		math.round(self.Value.G * 255),
		math.round(self.Value.B * 255)
	)
end

function ColorPickerAddon:_hexadecimalString()
	return "#" .. string.upper(self.Value:ToHex())
end

function ColorPickerAddon:_updateReadouts()
	if not self._popupCreated then
		return
	end
	local theme = self._window.Theme
	local redGreenBlueText = "RGB Value"
	local redGreenBlueTextColor = theme.Text
	local redGreenBlueInputColor = theme.Input
	if self._editing == "RGB" then
		redGreenBlueText = self._editText
		redGreenBlueTextColor = theme.Accent
		redGreenBlueInputColor = theme.ControlActive
	end

	local hexadecimalText = "HEX Value"
	local hexadecimalTextColor = theme.Text
	local hexadecimalInputColor = theme.Input
	if self._editing == "HEX" then
		hexadecimalText = self._editText
		hexadecimalTextColor = theme.Accent
		hexadecimalInputColor = theme.ControlActive
	end

	self._window:_setTextColor(self._redGreenBlueText, redGreenBlueText, redGreenBlueTextColor)
	self._window:_setTextColor(self._hexadecimalText, hexadecimalText, hexadecimalTextColor)
	self._window:_setColor(self._redGreenBlueInner, redGreenBlueInputColor)
	self._window:_setColor(self._hexadecimalInner, hexadecimalInputColor)
end

function ColorPickerAddon:_updateSwatch()
	self._window:_setGradient(self._swatchInner, self.Value, multiplyColor(self.Value, 0.554))
end

function ColorPickerAddon:_updateFieldMarker()
	if not self._popupCreated or not self._fieldX then
		return
	end
	local window = self._window
	local crossX = self._fieldX + self.Hue * self._fieldWidth
	local crossY = self._fieldY + (1 - self.Saturation) * self._fieldHeight
	local horizontalFrom = Vector2.new(crossX - 5, crossY)
	local horizontalTo = Vector2.new(crossX + 5, crossY)
	local verticalFrom = Vector2.new(crossX, crossY - 5)
	local verticalTo = Vector2.new(crossX, crossY + 5)
	window:_setLine(self._crosshairOuterHorizontal, horizontalFrom, horizontalTo)
	window:_setLine(self._crosshairHorizontal, horizontalFrom, horizontalTo)
	window:_setLine(self._crosshairOuterVertical, verticalFrom, verticalTo)
	window:_setLine(self._crosshairVertical, verticalFrom, verticalTo)
end

function ColorPickerAddon:_updateValueMarker()
	if not self._popupCreated or not self._valueX then
		return
	end
	local markerX = self._valueX + (1 - self.Brightness) * self._valueWidth
	local from = Vector2.new(markerX, self._valueY - 2)
	local to = Vector2.new(markerX, self._valueY + 11)
	self._window:_setLine(self._valueMarkerOuter, from, to)
	self._window:_setLine(self._valueMarker, from, to)
end

function ColorPickerAddon:_updateRainbowVisual()
	if not self._popupCreated then
		return
	end
	local window = self._window
	local theme = window.Theme
	local color = theme.Control
	if self.Rainbow then
		color = theme.AccentDark
	end
	window:_setColor(self._rainbowInner, color)
	window:_show(self._rainbowCheck, self._parentVisible and self.Open and self.Rainbow)
end

function ColorPickerAddon:_updateVisual()
	self:_updateSwatch()
	self:_updateRainbowVisual()
	self:_updateFieldMarker()
	self:_updateValueMarker()
	self:_updateReadouts()
	self._visualDirty = false
end

function ColorPickerAddon:_commitColor(silent, updateFieldMarker, updateValueMarker)
	self.Value = Color3.fromHSV(self.Hue, self.Saturation, self.Brightness)
	if self._parentVisible and self._window.Visible then
		self:_updateSwatch()
		if self.Open then
			if updateFieldMarker then
				self:_updateFieldMarker()
			end
			if updateValueMarker then
				self:_updateValueMarker()
			end
		end
		self._visualDirty = false
	else
		self._visualDirty = true
	end
	if self.Flag then
		self._window:_setFlag(self.Flag, self.Value, self)
	end
	if not silent then
		safeCall(self.Callback, self.Value, self)
	end
end

function ColorPickerAddon:_setFieldFromPoint(point)
	self.Hue = math.clamp((point.X - self._fieldX) / self._fieldWidth, 0, 1)
	self.Saturation = 1 - math.clamp((point.Y - self._fieldY) / self._fieldHeight, 0, 1)
	self:_commitColor(false, true, false)
end

function ColorPickerAddon:_setBrightnessFromPoint(point)
	self.Brightness = 1 - math.clamp((point.X - self._valueX) / self._valueWidth, 0, 1)
	self:_commitColor(false, false, true)
end

function ColorPickerAddon:_layout(x, y)
	local window = self._window
	local theme = window.Theme
	self._x = x
	self._y = y
	window:_setPositionSize(self._swatchOuter, Vector2.new(x, y + 7), Vector2.new(18, 8))
	window:_setPositionSize(self._swatchInner, Vector2.new(x + 1, y + 8), Vector2.new(16, 6))
	setRegionRectangle(self._swatchRegion, x - 2, y + 3, 22, 15)

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

	self._popupLayoutDirty = true
	if self.Open then
		self:_layoutPopup()
	elseif self._visualDirty then
		self:_updateVisual()
	end
end

function ColorPickerAddon:_layoutPopup()
	if not self._popupCreated then
		return
	end
	local window = self._window
	local theme = window.Theme
	local popupX, popupY = self._popupX, self._popupY

	window:_setPositionSize(
		self._popupOuter,
		Vector2.new(popupX, popupY),
		Vector2.new(COLOR_PICKER_POPUP_WIDTH, COLOR_PICKER_POPUP_HEIGHT)
	)
	window:_setPositionSize(
		self._popupStroke,
		Vector2.new(popupX + 1, popupY + 1),
		Vector2.new(178, 222)
	)
	window:_setPositionSize(
		self._popupInner,
		Vector2.new(popupX + 2, popupY + 2),
		Vector2.new(176, 220)
	)
	window:_setPositionSize(
		self._fieldBorder,
		Vector2.new(self._fieldX - 1, self._fieldY - 1),
		Vector2.new(162, 102)
	)

	local tileWidth = self._fieldWidth / COLOR_FIELD_COLUMNS
	local tileHeight = self._fieldHeight / COLOR_FIELD_ROWS
	local columnSize = Vector2.new(math.ceil(tileWidth), self._fieldHeight)
	for column = 1, COLOR_FIELD_COLUMNS do
		window:_setPositionSize(
			self._hueColumns[column],
			Vector2.new(self._fieldX + (column - 1) * tileWidth, self._fieldY),
			columnSize
		)
	end
	local rowSize = Vector2.new(self._fieldWidth, math.ceil(tileHeight))
	for row = 1, COLOR_FIELD_ROWS do
		window:_setPositionSize(
			self._saturationRows[row],
			Vector2.new(self._fieldX, self._fieldY + (row - 1) * tileHeight),
			rowSize
		)
	end

	window:_setPositionSize(
		self._valueBorder,
		Vector2.new(self._valueX - 1, self._valueY - 1),
		Vector2.new(162, 11)
	)
	local valueWidth = self._valueWidth / COLOR_VALUE_SEGMENTS
	local valueSize = Vector2.new(math.ceil(valueWidth), 9)
	for segment = 1, COLOR_VALUE_SEGMENTS do
		window:_setPositionSize(
			self._valueSegments[segment],
			Vector2.new(self._valueX + (segment - 1) * valueWidth, self._valueY),
			valueSize
		)
	end

	window:_setPositionSize(
		self._rainbowOuter,
		Vector2.new(popupX + 10, popupY + 136),
		Vector2.new(14, 14)
	)
	window:_setPositionSize(
		self._rainbowStroke,
		Vector2.new(popupX + 11, popupY + 137),
		Vector2.new(12, 12)
	)
	window:_setPositionSize(
		self._rainbowInner,
		Vector2.new(popupX + 12, popupY + 138),
		Vector2.new(10, 10)
	)
	window:_setPositionSize(
		self._rainbowCheck,
		Vector2.new(popupX + 13, popupY + 139),
		Vector2.new(8, 8)
	)
	window:_setPosition(
		self._rainbowText,
		Vector2.new(popupX + 31, centeredTextY(popupY + 137, 14, theme.TextSize))
	)
	window:_setPositionSize(
		self._redGreenBlueOuter,
		Vector2.new(popupX + 10, popupY + 158),
		Vector2.new(162, 27)
	)
	window:_setPositionSize(
		self._redGreenBlueStroke,
		Vector2.new(popupX + 11, popupY + 159),
		Vector2.new(160, 25)
	)
	window:_setPositionSize(
		self._redGreenBlueInner,
		Vector2.new(popupX + 12, popupY + 160),
		Vector2.new(158, 23)
	)
	window:_setPosition(
		self._redGreenBlueText,
		Vector2.new(popupX + 21, centeredTextY(popupY + 160, 23, theme.TextSize))
	)
	window:_setPositionSize(
		self._hexadecimalOuter,
		Vector2.new(popupX + 10, popupY + 190),
		Vector2.new(162, 27)
	)
	window:_setPositionSize(
		self._hexadecimalStroke,
		Vector2.new(popupX + 11, popupY + 191),
		Vector2.new(160, 25)
	)
	window:_setPositionSize(
		self._hexadecimalInner,
		Vector2.new(popupX + 12, popupY + 192),
		Vector2.new(158, 23)
	)
	window:_setPosition(
		self._hexadecimalText,
		Vector2.new(popupX + 21, centeredTextY(popupY + 192, 23, theme.TextSize))
	)

	setRegionRectangle(
		self._popupRegion,
		popupX,
		popupY,
		COLOR_PICKER_POPUP_WIDTH,
		COLOR_PICKER_POPUP_HEIGHT
	)
	setRegionRectangle(self._fieldRegion, self._fieldX, self._fieldY, 160, 100)
	setRegionRectangle(self._valueRegion, self._valueX, self._valueY - 1, 160, 11)
	setRegionRectangle(self._rainbowRegion, popupX + 2, popupY + 131, 168, 21)
	setRegionRectangle(self._redGreenBlueRegion, popupX + 10, popupY + 158, 162, 27)
	setRegionRectangle(self._hexadecimalRegion, popupX + 10, popupY + 190, 162, 27)
	self._popupLayoutDirty = false
	self:_updateVisual()
end

function ColorPickerAddon:_syncVisibility(parentVisible)
	self._parentVisible = parentVisible and not self._destroyed
	for _, drawing in ipairs(self._drawings) do
		self._window:_show(drawing, self._parentVisible)
	end
	local popupVisible = self._parentVisible and self.Open
	if self.Open then
		for _, drawing in ipairs(self._popupDrawings) do
			self._window:_show(drawing, popupVisible)
		end
	end
	self._window:_show(self._rainbowCheck, self._parentVisible and self.Open and self.Rainbow)
	self._window:_setRegionActive(self._swatchRegion, self._parentVisible)
	for _, region in ipairs(self._regions) do
		if region ~= self._swatchRegion then
			self._window:_setRegionActive(region, popupVisible)
		end
	end
	if not self._parentVisible and self.Open then
		self:Close()
	elseif self._parentVisible and self._visualDirty then
		self:_updateVisual()
	end
end

function ColorPickerAddon:OpenPopup()
	if self._destroyed or not self._parentVisible or not self._window.Visible then
		return self
	end
	if self.Open then
		return self
	end
	if self._window._openPopup and self._window._openPopup ~= self then
		self._window._openPopup:Close()
	end
	self:_ensurePopup()
	self.Open = true
	self._window._openPopup = self
	if self._popupLayoutDirty then
		self:_layoutPopup()
	end
	self:_syncVisibility(true)
	self:_updateVisual()
	return self
end

function ColorPickerAddon:Close(commit)
	if not self.Open and not self._editing then
		return self
	end
	self.Open = false
	if self._window._openPopup == self then
		self._window._openPopup = nil
	end
	for _, drawing in ipairs(self._popupDrawings) do
		self._window:_show(drawing, false)
	end
	for _, region in ipairs(self._regions) do
		if region ~= self._swatchRegion then
			self._window:_setRegionActive(region, false)
		end
	end
	if self._editing then
		self:Blur(commit ~= false)
	end
	return self
end

function ColorPickerAddon:SetRainbow(enabled)
	enabled = not not enabled
	if self.Rainbow == enabled then
		return self
	end
	self.Rainbow = enabled
	self._library:_setRainbowActive(self, enabled)
	self:_updateRainbowVisual()
	return self
end

function ColorPickerAddon:_rainbowStep(deltaTime)
	if not self.Rainbow or self._destroyed then
		return
	end
	self.Hue = (self.Hue + deltaTime * self.RainbowSpeed) % 1
	self:_commitColor(false, true, false)
end

function ColorPickerAddon:_focusField(kind)
	if self._editing == kind then
		return
	end
	if self._editing and self._editing ~= kind then
		self:Blur(true)
	end
	self._editing = kind
	if kind == "RGB" then
		self._editText = self:_redGreenBlueString()
	else
		self._editText = self:_hexadecimalString()
	end
	self._library:_setFocusedTextbox(self)
	self:_updateReadouts()
end

function ColorPickerAddon:_parseEdit()
	if self._editing == "RGB" then
		local values = table.create(3)
		for number in string.gmatch(self._editText, "%d+") do
			table.insert(values, tonumber(number))
		end
		if #values == 3 then
			return Color3.fromRGB(
				math.clamp(values[1], 0, 255),
				math.clamp(values[2], 0, 255),
				math.clamp(values[3], 0, 255)
			)
		end
	elseif self._editing == "HEX" then
		local text = string.gsub(self._editText, "^#", "")
		if (#text == 3 or #text == 6) and string.match(text, "^[%da-fA-F]+$") then
			return Color3.fromHex(text)
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
		self._editText = removeLastCharacter(self._editText)
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
	if allowed and textLength(self._editText) < 18 then
		self._editText = self._editText .. character
		self:_updateReadouts()
	end
end

function ColorPickerAddon:Blur(commit)
	if not self._editing then
		return self
	end
	self._library:_stopDeleteRepeat(self)
	local color
	if commit then
		color = self:_parseEdit()
	end
	self._editing = nil
	self._editText = nil
	if self._library._focusedTextbox == self then
		self._library._focusedTextbox = nil
	end
	self:_updateReadouts()
	if color then
		self:SetValue(color)
	end
	return self
end

function ColorPickerAddon:SetValue(value, silent)
	self.Value = value
	self.Hue, self.Saturation, self.Brightness = value:ToHSV()
	if self._parentVisible and self._window.Visible then
		self:_updateVisual()
	else
		self._visualDirty = true
	end
	if self.Flag then
		self._window:_setFlag(self.Flag, value, self)
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
	self:Close(false)
	self._destroyed = true
	for _, region in ipairs(self._regions) do
		self._window:_removeRegion(region)
	end
	for _, drawing in ipairs(self._drawings) do
		self._window:_removeDrawing(drawing)
	end
	for _, drawing in ipairs(self._popupDrawings) do
		self._window:_removeDrawing(drawing)
	end
	self._window:_unregisterFlag(self, self.Flag)
	self._library:_setRainbowActive(self, false)
	local parent = self._parent
	local addons = parent and parent._addons
	if addons then
		removeValue(addons, self)
		if not parent._destroying and parent._x then
			parent:_layout(parent._x, parent._y, parent._width)
		end
	end
	if not self._window._bulkDestroying then
		self._window:_compactStorage(false)
	end
	table.clear(self._drawings)
	table.clear(self._popupDrawings)
	table.clear(self._regions)
end

ColorPickerAddon.Remove = ColorPickerAddon.Destroy

function Checkbox:AddColorPicker(configuration)
	if self._destroyed or self._destroying or self._window._destroyed then
		return nil
	end

	local addon = ColorPickerAddon.new(self, configuration)
	table.insert(self._addons, addon)
	if addon.Flag then
		self._window:_registerFlag(addon, addon.Flag)
	end
	if self._x then
		self:_layout(self._x, self._y, self._width)
	end
	addon:_syncVisibility(self._parentVisible)
	return addon
end

function Slider.new(section, configuration)
	configuration = normalizeConfiguration(configuration)
	local self = setmetatable({}, Slider)
	Control._initialize(self, section, configuration, configuration.Height or 33)

	self.Minimum = tonumber(configuration.Min or configuration.Minimum) or 0
	self.Maximum = tonumber(configuration.Max or configuration.Maximum) or 100
	if self.Maximum < self.Minimum then
		self.Minimum, self.Maximum = self.Maximum, self.Minimum
	end
	self.Step = tonumber(configuration.Step or configuration.Increment) or 1
	self.Prefix = tostring(configuration.Prefix or "")
	self.Suffix = tostring(configuration.Suffix or "")
	self.Value = math.clamp(
		snap(
			tonumber(configuration.Default or configuration.Value) or self.Minimum,
			self.Minimum,
			self.Step
		),
		self.Minimum,
		self.Maximum
	)

	local theme = self._window.Theme
	self._label = createLabelDrawing(self, self.Text, 14)
	self._trackOuter =
		newRoundedRectangle(self._window, self._drawings, theme.ControlBorder, 10, 6)
	self._trackInner =
		newRoundedRectangle(self._window, self._drawings, theme.ControlStroke, 11, 3)
	self._trackBackground =
		newRoundedRectangle(self._window, self._drawings, theme.SliderTrack, 12, 2)
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
	function self._region._onPress(point)
		self._sliding = true
		self:_setFromPoint(point)
		return true
	end
	function self._region._onMove(point)
		if self._sliding then
			self:_setFromPoint(point)
		end
	end
	function self._region._onRelease()
		self._sliding = false
	end
	self._region._onCancel = self._region._onRelease
	self:_updateVisual()

	return section:_add(self)
end

function Slider:_ratio()
	local range = self.Maximum - self.Minimum
	if range <= 0 then
		return 0
	end
	return math.clamp((self.Value - self.Minimum) / range, 0, 1)
end

function Slider:_displayValue()
	if type(self.Format) == "function" then
		-- User formatters are isolated so controls can still render raw values.
		local success, formatted = pcall(self.Format, self.Value)
		if success and formatted ~= nil then
			return tostring(formatted)
		end
	end
	return self.Prefix .. formatNumber(self.Value, self.Step) .. self.Suffix
end

function Slider:_updateVisual()
	if not self._x then
		return
	end
	local ratio = self:_ratio()
	local innerWidth = math.max(0, self._width - 4)
	local fillWidth = math.round(innerWidth * ratio)
	local fillX = self._x + 2
	local display = self:_displayValue()
	local textWidth = math.max(6, textLength(display) * (14 * 0.52))
	local halfTextWidth = math.min(textWidth * 0.5, self._width * 0.5)
	local valueX = math.clamp(
		fillX + fillWidth - 3,
		self._x + halfTextWidth,
		self._x + self._width - halfTextWidth
	)

	self._window:_setPositionSize(
		self._fill,
		Vector2.new(fillX, self._y + 15),
		Vector2.new(fillWidth, 4)
	)
	self._window:_show(self._fill, self._parentVisible and fillWidth > 0)
	self._window:_setTextPosition(
		self._valueText,
		display,
		Vector2.new(valueX, centeredTextY(self._y + 21, 12, 14))
	)
end

function Slider:_setFromPoint(point)
	local innerWidth = math.max(1, self._width - 4)
	local ratio = math.clamp((point.X - (self._x + 2)) / innerWidth, 0, 1)
	self:SetValue(self.Minimum + (self.Maximum - self.Minimum) * ratio)
end

function Slider:_layout(x, y, width)
	self._x = x
	self._y = y
	self._width = width
	self._window:_setTextPosition(
		self._label,
		self.Text,
		Vector2.new(x, centeredTextY(y, 10, self._window.Theme.TextSize))
	)
	self._window:_setPositionSize(self._trackOuter, Vector2.new(x, y + 13), Vector2.new(width, 8))
	self._window:_setPositionSize(
		self._trackInner,
		Vector2.new(x + 1, y + 14),
		Vector2.new(width - 2, 6)
	)
	self._window:_setPositionSize(
		self._trackBackground,
		Vector2.new(x + 2, y + 15),
		Vector2.new(width - 4, 4)
	)
	setRegionRectangle(self._region, x, y + 12, width, 14)
	self:_updateVisual()
end

function Slider:_syncVisibility(parentVisible)
	Control._syncVisibility(self, parentVisible)
	self:_updateVisual()
end

function Slider:SetValue(value, silent)
	value = tonumber(value) or self.Minimum
	value = math.clamp(snap(value, self.Minimum, self.Step), self.Minimum, self.Maximum)
	if self.Value ~= value then
		self.Value = value
		self:_updateVisual()
	end
	self:_changed(self.Value, silent)
	return self
end

Slider.Set = Slider.SetValue

local function initializeDropdown(self, section, configuration, isMultiple)
	local defaultHeight = 60
	local glyphLineCount = 0
	if isMultiple then
		defaultHeight = 57
		glyphLineCount = 3
	end
	Control._initialize(self, section, configuration, configuration.Height or defaultHeight)
	self.Values = table.clone(configuration.Values or configuration.Options or {})
	self.Placeholder = tostring(configuration.Placeholder or self.Text)
	self.PopupHeight =
		math.max(42, math.floor(configuration.PopupHeight or configuration.DropdownHeight or 110))
	self.MaxVisible =
		math.max(1, math.floor(configuration.MaxVisible or ((self.PopupHeight - 2) / 20)))
	self.Open = false
	self.ScrollOffset = 1
	self._isMultiple = isMultiple
	self._popupDrawings = {}
	self._optionRows = table.create(self.MaxVisible)

	if isMultiple then
		self.Selected = setCopy(configuration.Default or configuration.Value or {})
		self.Value = nil
	else
		local default = configuration.Default
		if default == nil then
			default = configuration.Value
		end
		self.Value = default
	end

	local window = self._window
	local theme = window.Theme
	self._label = createLabelDrawing(self, self.Text, 14)
	self._outer, self._inner, self._highlight = createBox(self, 10)
	self._activeGradient = nil
	self._activeGradientCorners = {}
	self._glyph = nil
	self._glyphLines = table.create(glyphLineCount)
	self._glyphOutlineLines = table.create(glyphLineCount)

	if isMultiple then
		for _ = 1, 3 do
			table.insert(
				self._glyphOutlineLines,
				self:_draw("Line", {
					From = window.Position,
					To = window.Position,
					Color = theme.ControlBorder,
					Thickness = 3,
					ZIndex = window:_getZIndex(14),
					Transparency = 1,
					Visible = false,
				})
			)
			table.insert(
				self._glyphLines,
				self:_draw("Line", {
					From = window.Position,
					To = window.Position,
					Color = theme.MenuIcon,
					Thickness = 1,
					ZIndex = window:_getZIndex(15),
					Transparency = 1,
					Visible = false,
				})
			)
		end
	else
		self._glyph = createLabelDrawing(self, "v", 14)
		window:_set(self._glyph, {
			Size = theme.TextSize,
			Color = theme.MutedText,
		})
	end

	self._valueText = createLabelDrawing(self, "", 14)

	self._region = self:_region(20)
	self._region._popupOwner = self
	function self._region._onPress()
		if self.Open then
			self:Close()
		else
			self:OpenPopup()
		end
		return false
	end
	function self._region._onHover(hovered)
		self._hovered = hovered
		self:_updateStyle()
	end

	function self:_ensurePopup()
		if self._popupCreated then
			return
		end
		self._popupCreated = true

		local activeGradientDark, activeGradientLight = activeAccentGradient(theme)
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
		self._activeGradientCorners = table.create(4)
		for index = 1, 4 do
			self._activeGradientCorners[index] = self:_draw("Square", {
				Filled = true,
				Color = theme.ControlStroke,
				Position = window.Position,
				Size = Vector2.new(1, 1),
				ZIndex = window:_getZIndex(14),
				Transparency = 1,
				Visible = false,
			})
		end

		local function popupDraw(kind, properties)
			return window:_newDrawing(kind, properties, self._popupDrawings)
		end

		self._popupOuter = newRoundedRectangle(window, self._popupDrawings, theme.Border, 200, 4)
		self._popupStroke =
			newRoundedRectangle(window, self._popupDrawings, theme.ControlStroke, 201, 2)
		self._popupInner = newRoundedRectangle(window, self._popupDrawings, theme.Control, 202, 1)

		self._popupRegion = window:_newRegion(self, 210)
		self._popupRegion._popupOwner = self
		function self._popupRegion._enabled()
			return self._parentVisible and self.Open and not self._destroyed
		end
		function self._popupRegion._onWheel(delta)
			self:_scroll(delta)
		end
		table.insert(self._regions, self._popupRegion)

		for rowIndex = 1, self.MaxVisible do
			local row = {}
			row._background = popupDraw("Square", {
				Filled = true,
				Color = theme.Control,
				Position = window.Position,
				Size = Vector2.new(1, 1),
				ZIndex = window:_getZIndex(204),
				Transparency = 1,
				Visible = false,
			})
			row._text = popupDraw("Text", {
				Text = "",
				Font = getFont(theme),
				Size = theme.TextSize,
				Position = window.Position,
				Color = theme.Text,
				Outline = true,
				OutlineColor = theme.Border,
				OutlineOpacity = 1,
				ZIndex = window:_getZIndex(206),
				Transparency = 1,
				Visible = false,
			})
			if isMultiple then
				row._mark = popupDraw("Text", {
					Text = "",
					Font = getFont(theme),
					Size = theme.TextSize - 2,
					Position = window.Position,
					Color = theme.Accent,
					Outline = true,
					OutlineColor = theme.Border,
					OutlineOpacity = 1,
					ZIndex = window:_getZIndex(207),
					Transparency = 1,
					Visible = false,
				})
			end
			row._region = window:_newRegion(self, 220)
			row._region._popupOwner = self
			function row._region._enabled()
				return self._parentVisible
					and self.Open
					and not self._destroyed
					and row._value ~= nil
			end
			function row._region._onPress()
				if row._value ~= nil then
					self:_selectOption(row._value)
				end
				return false
			end
			function row._region._onHover(hovered)
				row._hovered = hovered
				self:_updatePopupRow(row)
			end
			function row._region._onWheel(delta)
				self:_scroll(delta)
			end
			table.insert(self._regions, row._region)
			table.insert(self._optionRows, row)
		end
		self._ensurePopup = noOperation
	end

	self:_updateDisplay()
end

function Dropdown.new(section, configuration)
	configuration = normalizeConfiguration(configuration)
	local self = setmetatable({}, Dropdown)
	initializeDropdown(self, section, configuration, false)
	return section:_add(self)
end

function MultiDropdown.new(section, configuration)
	configuration = normalizeConfiguration(configuration)
	local self = setmetatable({}, MultiDropdown)
	initializeDropdown(self, section, configuration, true)
	return section:_add(self)
end

function Dropdown:_selected(value)
	if self._isMultiple then
		return self.Selected[value] == true
	end
	return self.Value == value
end

function Dropdown:_displayText()
	if not self._isMultiple then
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
	self._window:_setText(
		self._valueText,
		truncate(self:_displayText(), width - 29, self._window.Theme.TextSize)
	)
end

function Dropdown:_updateStyle()
	local theme = self._window.Theme
	local color = theme.Control
	if self.Open and not self._isMultiple then
		color = theme.ControlActive
	elseif self._hovered then
		color = theme.ControlHover
	end
	self._window:_setColor(self._inner, color)

	if self._activeGradient then
		local activeGradientDark, activeGradientLight = activeAccentGradient(theme)
		local activeGradientVisible = self._parentVisible and self.Open
		self._window:_setGradient(self._activeGradient, activeGradientDark, activeGradientLight)
		self._window:_show(self._activeGradient, activeGradientVisible)
		for _, corner in ipairs(self._activeGradientCorners) do
			self._window:_setColor(corner, theme.ControlStroke)
			self._window:_show(corner, activeGradientVisible)
		end
	end

	if self._glyph then
		local glyphColor = theme.MutedText
		if self.Open then
			glyphColor = theme.Accent
		end
		self._window:_setColor(self._glyph, glyphColor)
	else
		for _, line in ipairs(self._glyphOutlineLines) do
			self._window:_setColor(line, theme.ControlBorder)
		end
		for _, line in ipairs(self._glyphLines) do
			self._window:_setColor(line, theme.MenuIcon)
		end
	end

	self._window:_setColor(self._valueText, theme.Text)
end

function Dropdown:_visibleRowCount()
	return math.min(#self.Values, self.MaxVisible)
end

function Dropdown:_maximumOffset()
	return math.max(1, #self.Values - self:_visibleRowCount() + 1)
end

function Dropdown:_scroll(delta)
	if #self.Values <= self.MaxVisible then
		return
	end
	local offset = self.ScrollOffset
	if delta > 0 then
		offset = offset - 1
	elseif delta < 0 then
		offset = offset + 1
	end
	offset = math.clamp(offset, 1, self:_maximumOffset())
	if self.ScrollOffset == offset then
		return
	end
	self.ScrollOffset = offset
	self:_updatePopupRows()
end

function Dropdown:_updatePopupRow(row)
	local value = row._value
	local visible = self._parentVisible and self.Open and value ~= nil
	local window = self._window
	window:_show(row._background, visible)
	window:_show(row._text, visible)
	window:_show(row._mark, visible and self._isMultiple)
	if value == nil then
		return
	end

	local theme = window.Theme
	local selected = self:_selected(value)
	local backgroundColor = theme.Control
	if selected then
		backgroundColor = theme.Selection
	elseif row._hovered then
		backgroundColor = theme.ControlHover
	end
	local textColor = theme.Text
	local mark = ""
	if selected then
		textColor = theme.Accent
		mark = "x"
	end
	window:_setColor(row._background, backgroundColor)
	window:_setTextColor(
		row._text,
		truncate(tostring(value), (self._width or 100) - 26, theme.TextSize),
		textColor
	)
	window:_setText(row._mark, mark)
end

function Dropdown:_updatePopupRows()
	if not self.Open then
		return
	end
	local visibleRows = self:_visibleRowCount()

	for rowIndex, row in ipairs(self._optionRows) do
		local valueIndex = self.ScrollOffset + rowIndex - 1
		local value
		if rowIndex <= visibleRows then
			value = self.Values[valueIndex]
		end
		row._value = value
		self:_updatePopupRow(row)
	end
end

function Dropdown:_layoutPopup()
	if not self._x or not self.Open then
		self._popupLayoutDirty = true
		return
	end
	self:_ensurePopup()
	local window = self._window
	local height = self.PopupHeight
	local x = self._x
	local y = self._y + 48
	local width = self._width

	window:_setPositionSize(self._popupOuter, Vector2.new(x, y), Vector2.new(width, height))
	window:_setPositionSize(
		self._popupStroke,
		Vector2.new(x + 1, y + 1),
		Vector2.new(width - 2, height - 2)
	)
	window:_setPositionSize(
		self._popupInner,
		Vector2.new(x + 2, y + 2),
		Vector2.new(width - 4, height - 4)
	)
	window:_setPositionSize(
		self._activeGradient,
		Vector2.new(x + 2, self._y + 22),
		Vector2.new(width - 4, 23)
	)
	local gradientRight = x + width - 3
	local gradientBottom = self._y + 44
	window:_setPosition(self._activeGradientCorners[1], Vector2.new(x + 2, self._y + 22))
	window:_setPosition(self._activeGradientCorners[2], Vector2.new(gradientRight, self._y + 22))
	window:_setPosition(self._activeGradientCorners[3], Vector2.new(x + 2, gradientBottom))
	window:_setPosition(self._activeGradientCorners[4], Vector2.new(gradientRight, gradientBottom))
	setRegionRectangle(self._popupRegion, x, y, width, height)

	for rowIndex, row in ipairs(self._optionRows) do
		local rowY = y + 2 + (rowIndex - 1) * 20
		window:_setPositionSize(
			row._background,
			Vector2.new(x + 2, rowY),
			Vector2.new(width - 4, 20)
		)
		window:_setPosition(
			row._text,
			Vector2.new(x + 8, centeredTextY(rowY, 25, window.Theme.TextSize))
		)
		window:_setPosition(
			row._mark,
			Vector2.new(x + width - 14, centeredTextY(rowY, 25, window.Theme.TextSize - 2))
		)
		setRegionRectangle(row._region, x + 2, rowY, width - 4, 20)
	end
	self._popupLayoutDirty = false
end

function Dropdown:_layout(x, y, width)
	local actualWidth = width + 2
	self._x = x
	self._y = y
	self._width = actualWidth
	self._window:_setTextPosition(
		self._label,
		self.Text,
		Vector2.new(x, centeredTextY(y + 6, 10, self._window.Theme.TextSize))
	)
	layoutBox(self._window, self._outer, self._inner, self._highlight, x, y + 20, actualWidth, 27)
	self._window:_setPosition(
		self._valueText,
		Vector2.new(x + 10, centeredTextY(y + 30, 10, self._window.Theme.TextSize))
	)
	if self._glyph then
		self._window:_setPosition(
			self._glyph,
			Vector2.new(
				x + actualWidth - 13,
				centeredTextY(y + 27, 10, self._window.Theme.TextSize)
			)
		)
	else
		local lineX = x + actualWidth - 16
		for index = 1, 3 do
			local lineY = y + 31 + (index - 1) * 2
			local from = Vector2.new(lineX, lineY)
			local to = Vector2.new(lineX + 5, lineY)
			self._window:_setLine(self._glyphOutlineLines[index], from, to)
			self._window:_setLine(self._glyphLines[index], from, to)
		end
	end
	setRegionRectangle(self._region, x, y + 20, actualWidth, 27)
	self:_updateDisplay()
	self._popupLayoutDirty = true
	if self.Open then
		self:_layoutPopup()
	end
	self:_updateStyle()
end

function Dropdown:_syncVisibility(parentVisible)
	Control._syncVisibility(self, parentVisible)
	local popupVisible = self._parentVisible and self.Open
	if self.Open then
		for _, drawing in ipairs(self._popupDrawings) do
			self._window:_show(drawing, popupVisible)
		end
	end
	for _, region in ipairs(self._regions) do
		if region ~= self._region then
			self._window:_setRegionActive(region, popupVisible)
		end
	end
	if not self._parentVisible and self.Open then
		self:Close()
	end
	self:_updatePopupRows()
	self:_updateStyle()
end

function Dropdown:OpenPopup()
	if self._destroyed or not self._parentVisible or not self._window.Visible then
		return self
	end
	if self.Open then
		return self
	end
	if self._window._openPopup and self._window._openPopup ~= self then
		self._window._openPopup:Close()
	end
	self:_ensurePopup()
	self.Open = true
	self._window._openPopup = self
	self:_layoutPopup()
	self:_syncVisibility(true)
	return self
end

function Dropdown:Close()
	if not self.Open then
		return self
	end
	self.Open = false
	if self._window._openPopup == self then
		self._window._openPopup = nil
	end
	for _, drawing in ipairs(self._popupDrawings) do
		self._window:_show(drawing, false)
	end
	for _, region in ipairs(self._regions) do
		if region ~= self._region then
			self._window:_setRegionActive(region, false)
		end
	end
	self:_updateStyle()
	return self
end

function Dropdown:_selectOption(value)
	self:SetValue(value)
	self:Close()
end

function Dropdown:SetValue(value, silent)
	if value ~= nil and not table.find(self.Values, value) and not self.AllowUnknown then
		return self
	end
	if self.Value ~= value then
		self.Value = value
		self:_updateDisplay()
		self:_updatePopupRows()
	end
	self:_changed(self.Value, silent)
	return self
end

Dropdown.Set = Dropdown.SetValue

function Dropdown:SetValues(values, preserveValue)
	local previousValue = self.Value
	self.Values = table.clone(values or {})
	self.ScrollOffset = 1
	if not preserveValue and self.Value ~= nil and not table.find(self.Values, self.Value) then
		self.Value = nil
	end
	self:_updateDisplay()
	self:_updatePopupRows()
	if previousValue ~= self.Value then
		self:_changed(self.Value, true)
	end
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
	table.clear(self._popupDrawings)
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
	if not self.AllowUnknown then
		for value in pairs(self.Selected) do
			if not table.find(self.Values, value) then
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
	local previousValues = self:_selectedValues()
	local previous = self.Selected
	self.Values = table.clone(values or {})
	self.ScrollOffset = 1
	if preserveValue then
		self.Selected = previous
	else
		for value in pairs(self.Selected) do
			if not table.find(self.Values, value) then
				self.Selected[value] = nil
			end
		end
	end
	self:_updateDisplay()
	self:_updatePopupRows()
	local selectedValues = self:_selectedValues()
	if not arraysEqual(previousValues, selectedValues) then
		self:_changed(selectedValues, true)
	end
	return self
end

MultiDropdown.SetOptions = MultiDropdown.SetValues

function Spinner.new(section, configuration)
	configuration = normalizeConfiguration(configuration)
	local self = setmetatable({}, Spinner)
	Control._initialize(self, section, configuration, configuration.Height or 51)

	self.Minimum = tonumber(configuration.Min or configuration.Minimum) or -math.huge
	self.Maximum = tonumber(configuration.Max or configuration.Maximum) or math.huge
	if self.Maximum < self.Minimum then
		self.Minimum, self.Maximum = self.Maximum, self.Minimum
	end
	self.Step = tonumber(configuration.Step or configuration.Increment) or 1
	self.SnapBase = self.Minimum
	if self.Minimum == -math.huge then
		self.SnapBase = 0
	end
	local initialValue = tonumber(configuration.Default or configuration.Value) or 0
	self.Value =
		math.clamp(snap(initialValue, self.SnapBase, self.Step), self.Minimum, self.Maximum)

	local theme = self._window.Theme
	self._label = createLabelDrawing(self, self.Text, 14)
	self._valueOuter, self._valueInner, self._valueHighlight =
		createBox(self, 10, theme.Input, 4, 1, theme.InputStroke)
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
	function self._valueRegion._onPress()
		self:Focus()
		return false
	end
	function self._valueRegion._onWheel(delta)
		local amount = -self.Step
		if delta > 0 then
			amount = self.Step
		end
		self:SetValue(self.Value + amount)
	end
	function self._minusRegion._onPress()
		if self._editing then
			self:Blur(true)
		end
		self:SetValue(self.Value - self.Step)
		return false
	end
	function self._plusRegion._onPress()
		if self._editing then
			self:Blur(true)
		end
		self:SetValue(self.Value + self.Step)
		return false
	end
	function self._minusRegion._onHover(hovered)
		self._minusHovered = hovered
		self:_updateStyle()
	end
	function self._plusRegion._onHover(hovered)
		self._plusHovered = hovered
		self:_updateStyle()
	end
	function self._valueRegion._onHover(hovered)
		self._hovered = hovered
		self:_updateStyle()
	end
	self:_updateStyle()

	return section:_add(self)
end

function Spinner:_updateStyle()
	local theme = self._window.Theme
	local valueColor = theme.Input
	local text = formatNumber(self.Value, self.Step)
	local textColor = theme.Text
	if self._editing then
		valueColor = theme.ControlActive
		text = self._editText
		textColor = theme.Accent
	elseif self._hovered then
		valueColor = theme.ControlHover
	end

	local minusColor = theme.Control
	if self._minusHovered then
		minusColor = theme.ControlHover
	end
	local plusColor = theme.Control
	if self._plusHovered then
		plusColor = theme.ControlHover
	end

	self._window:_setColor(self._valueInner, valueColor)
	self._window:_setColor(self._minusInner, minusColor)
	self._window:_setColor(self._plusInner, plusColor)
	self._window:_setTextColor(self._valueText, text, textColor)
end

function Spinner:_layout(x, y, width)
	local actualWidth = width + 2
	local buttonWidth = 27
	local gap = 1
	local valueWidth = actualWidth - buttonWidth * 2 - gap * 2
	local fieldY = y + 16
	self._x, self._y, self._width = x, y, width
	self._window:_setTextPosition(
		self._label,
		self.Text,
		Vector2.new(x, centeredTextY(y + 3, 10, self._window.Theme.TextSize))
	)
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
	self._window:_setPosition(
		self._valueText,
		Vector2.new(x + 10, centeredTextY(y + 19, 22, self._window.Theme.TextSize))
	)
	self._window:_setPosition(
		self._minusText,
		Vector2.new(
			x + valueWidth + gap + buttonWidth * 0.5,
			centeredTextY(fieldY + 2, 23, self._window.Theme.TextSize)
		)
	)
	self._window:_setPosition(
		self._plusText,
		Vector2.new(
			x + valueWidth + gap + buttonWidth + gap + buttonWidth * 0.5,
			centeredTextY(fieldY + 2, 23, self._window.Theme.TextSize)
		)
	)
	setRegionRectangle(self._valueRegion, x, fieldY, valueWidth, 27)
	setRegionRectangle(self._minusRegion, x + valueWidth + gap, fieldY, buttonWidth, 27)
	setRegionRectangle(
		self._plusRegion,
		x + valueWidth + gap + buttonWidth + gap,
		fieldY,
		buttonWidth,
		27
	)
end

function Spinner:_syncVisibility(parentVisible)
	Control._syncVisibility(self, parentVisible)
	if not self._parentVisible and self._editing then
		self:Blur(true)
	end
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
	local value
	if commit then
		value = tonumber(self._editText)
	end
	self._editing = false
	self._editText = nil
	if self._library._focusedTextbox == self then
		self._library._focusedTextbox = nil
	end
	if value then
		value = math.clamp(snap(value, self.SnapBase, self.Step), self.Minimum, self.Maximum)
		self.Value = value
	end
	self:_updateStyle()
	if value then
		self:_changed(value, false)
	end
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
		self._editText = removeLastCharacter(self._editText)
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
	if character and string.match(character, "[%d%.%-]") and textLength(self._editText) < 16 then
		self._editText = self._editText .. character
		self:_updateStyle()
	end
end

function Spinner:SetValue(value, silent)
	value = tonumber(value) or self.Value
	value = math.clamp(snap(value, self.SnapBase, self.Step), self.Minimum, self.Maximum)
	if self.Value ~= value then
		self.Value = value
		self:_updateStyle()
	end
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

function Textbox.new(section, configuration)
	configuration = normalizeConfiguration(configuration)
	local self = setmetatable({}, Textbox)
	Control._initialize(self, section, configuration, configuration.Height or 51)

	self.Value = tostring(configuration.Default or configuration.Value or "")
	self.Placeholder = tostring(configuration.Placeholder or "")
	self.MaxLength = math.max(1, math.floor(configuration.MaxLength or 256))
	self.Numeric = configuration.Numeric == true
	self.ClearOnFocus = configuration.ClearOnFocus == true
	self.Live = configuration.Live ~= false
	self.Finished = configuration.Finished

	local theme = self._window.Theme
	self._label = createLabelDrawing(self, self.Text, 14)
	self._outer, self._inner, self._highlight =
		createBox(self, 10, theme.Input, 4, 1, theme.InputStroke)
	self._valueText = createLabelDrawing(self, "", 14)
	self._caret = self:_draw("Line", {
		From = self._window.Position,
		To = self._window.Position,
		Color = theme.Accent,
		Thickness = 1,
		ZIndex = self._window:_getZIndex(16),
		Transparency = 1,
		Visible = false,
	})

	self._region = self:_region(20)
	function self._region._onPress()
		self:Focus()
		return false
	end
	function self._region._onHover(hovered)
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
	local inputColor = theme.Input
	if self._editing then
		inputColor = theme.ControlActive
	elseif self._hovered then
		inputColor = theme.ControlHover
	end
	local textColor = theme.Text
	if not self._editing and self.Value == "" then
		textColor = theme.MutedText
	end
	self._window:_setColor(self._inner, inputColor)
	self._window:_setTextColor(self._valueText, displayValue, textColor)
	self._window:_show(self._caret, self._parentVisible and self._editing)

	if self._x and self._editing then
		local textWidth = self._measuredTextWidth
		if self._measuredText ~= displayValue or self._measuredTextSize ~= theme.TextSize then
			textWidth = measuredTextWidth(self._valueText, displayValue, theme.TextSize)
			self._measuredText = displayValue
			self._measuredTextSize = theme.TextSize
			self._measuredTextWidth = textWidth
		end
		local caretX = math.min(self._x + width - 6, self._x + 13 + textWidth)
		self._window:_setLine(
			self._caret,
			Vector2.new(caretX, self._y + 21),
			Vector2.new(caretX, self._y + 37)
		)
	end
end

function Textbox:_layout(x, y, width)
	self._x = x
	self._y = y
	self._width = width
	self._window:_setTextPosition(
		self._label,
		self.Text,
		Vector2.new(x, centeredTextY(y + 3, 10, self._window.Theme.TextSize))
	)
	layoutBox(self._window, self._outer, self._inner, self._highlight, x, y + 16, width, 27)
	self._window:_setPosition(
		self._valueText,
		Vector2.new(x + 13, centeredTextY(y + 18, 23, self._window.Theme.TextSize))
	)
	setRegionRectangle(self._region, x, y + 16, width, 27)
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
	self._editText = self.Value
	if self.ClearOnFocus then
		self._editText = ""
	end
	self._editLength = textLength(self._editText)
	self._library:_setFocusedTextbox(self)
	self:_updateVisual()
	return self
end

function Textbox:Blur(commit)
	if not self._editing then
		return self
	end
	self._library:_stopDeleteRepeat(self)
	local value
	if commit then
		value = limitText(self._editText, self.MaxLength)
	end
	self._editing = false
	self._editText = nil
	self._editLength = nil
	if self._library._focusedTextbox == self then
		self._library._focusedTextbox = nil
	end
	if value ~= nil then
		self.Value = value
	end
	self:_updateVisual()
	if value ~= nil then
		self:_changed(value, self.Live)
	end
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
		if self._editLength > 0 then
			self._editText = removeLastCharacter(self._editText)
			self._editLength = self._editLength - 1
		end
		if self.Live then
			self.Value = self._editText
			self:_changed(self.Value, false)
		end
		self:_updateVisual()
		return
	end

	local character = inputCharacter(self._library, keyCode)
	if not character or self._editLength >= self.MaxLength then
		return
	end
	if self.Numeric and not string.match(character, "[%d%.%-]") then
		return
	end
	self._editText = self._editText .. character
	self._editLength = self._editLength + 1
	if self.Live then
		self.Value = self._editText
		self:_changed(self.Value, false)
	end
	self:_updateVisual()
end

function Textbox:SetValue(value, silent)
	value = limitText(tostring(value or ""), self.MaxLength)
	local changed = self.Value ~= value or (self._editing and self._editText ~= value)
	self.Value = value
	if self._editing then
		self._editText = self.Value
		self._editLength = textLength(self.Value)
	end
	if changed then
		self:_updateVisual()
	end
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

function Listbox.new(section, configuration)
	configuration = normalizeConfiguration(configuration)
	local self = setmetatable({}, Listbox)
	self.BoxHeight =
		math.max(42, math.floor(configuration.Height or configuration.ListHeight or 127))
	Control._initialize(
		self,
		section,
		configuration,
		configuration.TotalHeight or (self.BoxHeight + 21)
	)

	self.Values = table.clone(configuration.Values or configuration.Options or {})
	self.Value = configuration.Default
	if self.Value == nil then
		self.Value = configuration.Value
	end
	self.ScrollOffset = 1
	self.RowHeight = math.max(16, math.floor(configuration.RowHeight or 20))
	self.VisibleRows = math.max(1, math.floor((self.BoxHeight - 2) / self.RowHeight))
	self._rows = table.create(self.VisibleRows)

	local theme = self._window.Theme
	self._label = createLabelDrawing(self, self.Text, 14)
	self._outer = newRoundedRectangle(self._window, self._drawings, theme.ControlBorder, 10, 4)
	self._stroke = newRoundedRectangle(self._window, self._drawings, theme.InputStroke, 11, 2)
	self._inner = newRoundedRectangle(self._window, self._drawings, theme.Input, 12, 1)

	for rowIndex = 1, self.VisibleRows do
		local row = {}
		row._background = self:_draw("Square", {
			Filled = true,
			Color = theme.Input,
			Position = self._window.Position,
			Size = Vector2.new(1, 1),
			ZIndex = self._window:_getZIndex(13),
			Transparency = 1,
			Visible = false,
		})
		row._text = createLabelDrawing(self, "", 14)
		row._region = self:_region(21)
		function row._region._enabled()
			return self._parentVisible and not self._destroyed and row._value ~= nil
		end
		function row._region._onPress()
			if row._value ~= nil then
				self:SetValue(row._value)
			end
			return false
		end
		function row._region._onHover(hovered)
			row._hovered = hovered
			self:_updateRow(row)
		end
		function row._region._onWheel(delta)
			self:_scroll(delta)
		end
		table.insert(self._rows, row)
	end

	self._scrollRegion = self:_region(20)
	function self._scrollRegion._onWheel(delta)
		self:_scroll(delta)
	end
	self:_updateRows()

	return section:_add(self)
end

function Listbox:_maximumOffset()
	return math.max(1, #self.Values - self.VisibleRows + 1)
end

function Listbox:_scroll(delta)
	local offset = self.ScrollOffset
	if delta > 0 then
		offset = offset - 1
	elseif delta < 0 then
		offset = offset + 1
	end
	offset = math.clamp(offset, 1, self:_maximumOffset())
	if self.ScrollOffset == offset then
		return
	end
	self.ScrollOffset = offset
	self:_updateRows()
end

function Listbox:_updateRow(row)
	local value = row._value
	local visible = self._parentVisible and value ~= nil
	self._window:_show(row._background, visible)
	self._window:_show(row._text, visible)
	if value == nil then
		return
	end
	local theme = self._window.Theme
	local selected = self.Value == value
	local backgroundColor = theme.Input
	if selected then
		backgroundColor = theme.Selection
	elseif row._hovered then
		backgroundColor = theme.ControlHover
	end
	local textColor = theme.Text
	if selected then
		textColor = theme.Accent
	end
	self._window:_setColor(row._background, backgroundColor)
	self._window:_setTextColor(row._text, tostring(value), textColor)
end

function Listbox:_updateRows()
	for rowIndex, row in ipairs(self._rows) do
		local value = self.Values[self.ScrollOffset + rowIndex - 1]
		row._value = value
		self:_updateRow(row)
	end
end

function Listbox:_layout(x, y, width)
	self._x = x
	self._y = y
	self._width = width
	local boxY = y + 16
	self._window:_setTextPosition(
		self._label,
		self.Text,
		Vector2.new(x, centeredTextY(y + 3, 10, self._window.Theme.TextSize))
	)
	self._window:_setPositionSize(
		self._outer,
		Vector2.new(x, boxY),
		Vector2.new(width, self.BoxHeight)
	)
	self._window:_setPositionSize(
		self._stroke,
		Vector2.new(x + 1, boxY + 1),
		Vector2.new(width - 2, self.BoxHeight - 2)
	)
	self._window:_setPositionSize(
		self._inner,
		Vector2.new(x + 2, boxY + 2),
		Vector2.new(width - 4, self.BoxHeight - 4)
	)
	setRegionRectangle(self._scrollRegion, x, boxY, width, self.BoxHeight)

	for rowIndex, row in ipairs(self._rows) do
		local rowY = boxY + 2 + (rowIndex - 1) * self.RowHeight
		self._window:_setPositionSize(
			row._background,
			Vector2.new(x + 2, rowY),
			Vector2.new(width - 4, self.RowHeight)
		)
		self._window:_setPosition(
			row._text,
			Vector2.new(x + 14, centeredTextY(rowY, 25, self._window.Theme.TextSize))
		)
		setRegionRectangle(row._region, x + 2, rowY, width - 4, self.RowHeight)
	end
	self:_updateRows()
end

function Listbox:_syncVisibility(parentVisible)
	Control._syncVisibility(self, parentVisible)
	self:_updateRows()
end

function Listbox:SetValue(value, silent)
	if value ~= nil and not table.find(self.Values, value) and not self.AllowUnknown then
		return self
	end
	if self.Value ~= value then
		self.Value = value
		self:_updateRows()
	end
	self:_changed(self.Value, silent)
	return self
end

Listbox.Set = Listbox.SetValue

function Listbox:SetValues(values, preserveValue)
	local previousValue = self.Value
	self.Values = table.clone(values or {})
	self.ScrollOffset = 1
	if not preserveValue and self.Value ~= nil and not table.find(self.Values, self.Value) then
		self.Value = nil
	end
	self:_updateRows()
	if previousValue ~= self.Value then
		self:_changed(self.Value, true)
	end
	return self
end

Listbox.SetOptions = Listbox.SetValues

function Label.new(section, configuration)
	configuration = normalizeConfiguration(configuration)
	local self = setmetatable({}, Label)
	Control._initialize(self, section, configuration, configuration.Height or 23)
	self.Value = self.Text
	self._text = createLabelDrawing(self, self.Text, 14)
	self._window:_set(self._text, {
		Color = configuration.Color or self._window.Theme.Text,
		Size = configuration.Size or self._window.Theme.TextSize,
	})
	return section:_add(self)
end

function Label:_layout(x, y)
	self._window:_setTextPosition(
		self._text,
		self.Text,
		Vector2.new(
			x,
			centeredTextY(y, self._height, self.ControlTextSize or self._window.Theme.TextSize)
		)
	)
end

function Label:SetValue(value)
	value = tostring(value)
	if self.Value == value then
		return self
	end
	self.Value = value
	self.Text = self.Value
	self._window:_setText(self._text, self.Value)
	return self
end

Label.Set = Label.SetValue

function Separator.new(section, configuration)
	configuration = normalizeConfiguration(configuration)
	local self = setmetatable({}, Separator)
	Control._initialize(self, section, configuration, configuration.Height or 16)
	self._line = self:_draw("Line", {
		From = self._window.Position,
		To = self._window.Position,
		Color = configuration.Color or self._window.Theme.InnerBorder,
		Thickness = 1,
		ZIndex = self._window:_getZIndex(12),
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
	self._window:_setLine(self._line, Vector2.new(x, y + 7), Vector2.new(x + width, y + 7))
	if self._text then
		self._window:_setPosition(self._text, Vector2.new(x + width * 0.5, y))
	end
end

function StandaloneKeybind.new(section, configuration)
	configuration = normalizeConfiguration(configuration)
	local self = setmetatable({}, StandaloneKeybind)
	Control._initialize(self, section, configuration, configuration.Height or 23)
	self._label = createLabelDrawing(self, self.Text, 14)
	self._addon = KeybindAddon.new(self, configuration, true)
	return section:_add(self)
end

function StandaloneKeybind:_layout(x, y, width)
	self._x, self._y, self._width = x, y, width
	self._window:_setTextPosition(
		self._label,
		self.Text,
		Vector2.new(x, centeredTextY(y, self._height, self._window.Theme.TextSize))
	)
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
	if self._destroyed or self._addon._destroyed then
		return self
	end
	self._window:_setFlag(self.Flag, self._addon:GetValue(), self)
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

function StandaloneColorPicker.new(section, configuration)
	configuration = normalizeConfiguration(configuration)
	local self = setmetatable({}, StandaloneColorPicker)
	Control._initialize(self, section, configuration, configuration.Height or 23)
	self._label = createLabelDrawing(self, self.Text, 14)
	self._addon = ColorPickerAddon.new(self, configuration, true)
	return section:_add(self)
end

function StandaloneColorPicker:_layout(x, y, width)
	self._x, self._y, self._width = x, y, width
	self._window:_setTextPosition(
		self._label,
		self.Text,
		Vector2.new(x, centeredTextY(y, self._height, self._window.Theme.TextSize))
	)
	self._addon:_layout(x + (self._rowWidth or width) - self._addon:_preferredWidth(), y)
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

function Section:AddButton(configuration, callback)
	return Button.new(self, configuration, callback)
end

Section.Button = Section.AddButton

function Section:AddCheckbox(configuration)
	return Checkbox.new(self, configuration)
end

Section.Checkbox = Section.AddCheckbox
Section.AddToggle = Section.AddCheckbox
Section.Toggle = Section.AddCheckbox

function Section:AddSlider(configuration)
	return Slider.new(self, configuration)
end

Section.Slider = Section.AddSlider

function Section:AddDropdown(configuration)
	return Dropdown.new(self, configuration)
end

Section.Dropdown = Section.AddDropdown
Section.AddCombobox = Section.AddDropdown
Section.Combobox = Section.AddDropdown
Section.AddComboBox = Section.AddDropdown
Section.ComboBox = Section.AddDropdown

function Section:AddMultiDropdown(configuration)
	return MultiDropdown.new(self, configuration)
end

Section.MultiDropdown = Section.AddMultiDropdown
Section.AddMultibox = Section.AddMultiDropdown
Section.Multibox = Section.AddMultiDropdown
Section.AddMultiBox = Section.AddMultiDropdown
Section.MultiBox = Section.AddMultiDropdown

function Section:AddSpinner(configuration)
	return Spinner.new(self, configuration)
end

Section.Spinner = Section.AddSpinner

function Section:AddTextbox(configuration)
	return Textbox.new(self, configuration)
end

Section.Textbox = Section.AddTextbox
Section.AddInput = Section.AddTextbox
Section.Input = Section.AddTextbox
Section.AddTextBox = Section.AddTextbox
Section.TextBox = Section.AddTextbox

function Section:AddListbox(configuration)
	return Listbox.new(self, configuration)
end

Section.Listbox = Section.AddListbox
Section.AddListBox = Section.AddListbox
Section.ListBox = Section.AddListbox

function Section:AddLabel(configuration)
	return Label.new(self, configuration)
end

Section.Label = Section.AddLabel

function Section:AddSeparator(configuration)
	return Separator.new(self, configuration)
end

Section.Separator = Section.AddSeparator
Section.AddDivider = Section.AddSeparator

function Section:AddKeybind(configuration)
	return StandaloneKeybind.new(self, configuration)
end

Section.Keybind = Section.AddKeybind

function Section:AddColorPicker(configuration)
	return StandaloneColorPicker.new(self, configuration)
end

Section.ColorPicker = Section.AddColorPicker

function Nephren:CreateWindow(configuration)
	assert(not self._unloading, "Nephren cannot create a window while unloading")
	configuration = table.clone(configuration or {})
	self:_start()

	local window = Window.new(self, configuration)
	table.insert(self._windows, window)
	window:_layout()
	return window
end

Nephren.Window = Nephren.CreateWindow

function Nephren:GetWindow(index)
	return self._windows[index or 1]
end

function Nephren:Unload()
	if self._unloading then
		return
	end
	self._unloading = true
	self._started = false

	-- Executor connections can throw after external disconnection.
	if self._renderConnection then
		pcall(disconnectConnection, self._renderConnection)
		self._renderConnection = nil
	end
	for _, connection in ipairs(self._connections) do
		pcall(disconnectConnection, connection)
	end

	while #self._windows > 0 do
		self._windows[#self._windows]:Destroy()
	end

	table.clear(self._connections)
	table.clear(self._windows)
	table.clear(self._keybinds)
	table.clear(self._keybindBuckets)
	self._keybindGeneration = 0
	for _, picker in ipairs(self._rainbowPickers) do
		picker._rainbowIndex = nil
	end
	table.clear(self._rainbowPickers)
	self._focusedTextbox = nil
	self._bindingKeybind = nil
	self._capture = nil
	self._hoveredRegion = nil
	table.clear(self._keysDown)
	self._capsLock = false
	self._deleteRepeat = nil
	self._steppingRainbows = nil
	self._pendingRainbowState = nil
	table.clear(self._pendingDragWindows)
	self._pendingDragCount = 0
	self._userInputService = nil
	self._runService = nil
	self._workspace = nil
	self._drawingNew = nil
	self._defaultFont = nil
	self._nextBaseZIndex = 0
	table.clear(self.Flags)
	table.clear(self._flagOwners)
	table.clear(self._flagStacks)
	self._unloading = false
end

Nephren.Destroy = Nephren.Unload

return Nephren
