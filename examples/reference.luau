-- Adapt this line to however your development tool loads local Luau modules.
local Nephren = loadstring(readfile("src/Nephren.lua"))()

local window = Nephren:CreateWindow({
    Title = "Title",
    Size = Vector2.new(587, 563),
    ToggleKey = Enum.KeyCode.RightShift,
})

local main = window:AddTab("Tab")
window:AddTab("Tab")

local left = main:AddSection({
    Title = "Container",
    Side = "Left",
    Height = 490,
})

local right = main:AddSection({
    Title = "Container",
    Side = "Right",
    Height = 248,
})

left:AddCombobox({
    Text = "Combobox",
    Values = { "Combobox", "Option 2", "Option 3" },
    Default = "Combobox",
    Flag = "Combobox",
})

left:AddSlider({
    Text = "Slider",
    Min = 0,
    Max = 100,
    Step = 1,
    Default = 0,
    Flag = "Slider",
})

left:AddButton({
    Text = "Button",
    Callback = function()
        print("Button pressed")
    end,
})

left:AddMultibox({
    Text = "Multibox",
    Values = { "Option", "Second option", "Third option" },
    Placeholder = "Multibox",
    Flag = "Multibox",
})

left:AddSpinner({
    Text = "Spinner",
    Min = -10,
    Max = 10,
    Step = 1,
    Default = 0,
    Flag = "Spinner",
})

local checkbox = left:AddCheckbox({
    Text = "Checkbox",
    Flag = "Checkbox",
})

checkbox:AddKeybind({
    Default = Enum.KeyCode.H,
    Mode = "Toggle",
    Callback = function(enabled)
        print("Keybind toggled:", enabled)
    end,
})

checkbox:AddColorPicker({
    Default = Color3.fromRGB(210, 166, 169),
    Flag = "AccentColor",
    Callback = function(color)
        print("Color:", color)
    end,
})

left:AddTextbox({
    Text = "Textbox",
    Default = "Lorem ipsum",
    Flag = "Textbox",
})

left:AddListbox({
    Text = "Listbox",
    Values = { "Option" },
    Height = 127,
    Flag = "Listbox",
})

right:AddMultibox({
    Text = "Multibox",
    Values = { "Option" },
    Placeholder = "Multibox",
    Flag = "RightMultibox",
})

right:AddListbox({
    Text = "Listbox",
    Values = { "Option" },
    Height = 127,
    Flag = "RightListbox",
})

-- Later:
-- window:Destroy()
-- Nephren:Unload()
