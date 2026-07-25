# Nephren

Nephren is a compact Luau UI library rendered entirely through the custom
`Drawing` API. It uses Roblox-style `UserInputService` events for mouse,
keyboard, wheel, dragging, text entry, and keybinds; it does not create Roblox
GUI instances.

The default 587×563 theme and the example in
[`examples/reference.lua`](examples/reference.lua) reproduce the supplied dark,
two-column reference, including rounded controls, dual 1px borders, and the
pink-to-lavender accent gradients used by tabs, containers, sliders, and color
swatches.

The default palette mirrors the Studio mock-up's layer roles: section frames use
RGB `(0, 0, 0)` and `(26, 26, 26)`, standard controls use `(11, 11, 11)` and
`(49, 49, 49)`, and input/list surfaces use an inner `(31, 31, 31)` stroke.

## Loading

Use whichever loader your development tool exposes:

```lua
local Nephren = loadstring(readfile("src/Nephren.lua"))()
```

The host must provide `Drawing`, `Vector2`, `Color3`, `Enum`, `game:GetService`,
`UserInputService`, and `RunService`.

## Basic structure

```lua
local window = Nephren:CreateWindow({
    Title = "Title",
    Size = Vector2.new(587, 563),
    ToggleKey = Enum.KeyCode.RightShift,
})

local tab = window:AddTab("Tab")
local section = tab:AddSection({
    Title = "Container",
    Side = "Left", -- "Left" or "Right"
    Height = 300,
})

section:AddSlider({
    Text = "Amount",
    Min = 0,
    Max = 100,
    Default = 25,
    Flag = "Amount",
    Callback = function(value)
        print(value)
    end,
})
```

Controls are laid out automatically. A control with a `Flag` writes its current
value to both `window.Flags[flag]` and `Nephren.Flags[flag]`.

```lua
print(window.Flags.Amount)
window:SetValue("Amount", 50)
```

## Controls

All constructors take one configuration table.

| Constructor | Important fields |
| --- | --- |
| `AddButton` | `Text`, `Callback` |
| `AddCheckbox` / `AddToggle` | `Text`, `Default`, `Flag`, `Callback` |
| `AddSlider` | `Text`, `Min`, `Max`, `Step`, `Default`, `Prefix`, `Suffix` |
| `AddDropdown` / `AddCombobox` | `Text`, `Values`, `Default`, `PopupHeight` |
| `AddMultiDropdown` / `AddMultibox` | `Text`, `Values`, `Default`, `PopupHeight` |
| `AddSpinner` | `Text`, `Min`, `Max`, `Step`, `Default` |
| `AddTextbox` / `AddInput` | `Text`, `Default`, `Placeholder`, `MaxLength`, `Numeric` |
| `AddListbox` | `Text`, `Values`, `Default`, `Height` |
| `AddKeybind` | `Text`, `Default`, `Mode` (`Press`, `Toggle`, or `Hold`) |
| `AddColorPicker` | `Text`, `Default`, `Rainbow`, `RainbowSpeed` |
| `AddLabel` | `Text`, `Color`, `Size` |
| `AddSeparator` | `Text`, `Color` |

Value controls expose `GetValue()` and `SetValue(value, silent)`. Dropdowns and
listboxes also expose `SetValues(values, preserveValue)`.

### Checkbox add-ons

Keybinds and color pickers can sit on the right side of a checkbox, matching the
reference:

```lua
local enabled = section:AddCheckbox({
    Text = "Checkbox",
    Flag = "Enabled",
})

enabled:AddKeybind({
    Default = Enum.KeyCode.H,
    Mode = "Toggle",
    Callback = function(active)
        print(active)
    end,
})

enabled:AddColorPicker({
    Default = Color3.fromRGB(211, 181, 191),
    Flag = "Color",
})
```

Checkbox keybinds default to `Toggle` when `Mode` is omitted. Their toggle or
hold state is applied to the parent checkbox, including its flag, callback, and
checked visual.

The color popup contains a hue/saturation canvas with a crosshair, a brightness
strip, Rainbow mode, and editable RGB and HEX fields. Click either value field,
type a replacement, then press Enter.

## Window methods

```lua
window:SetVisible(false)
window:Toggle()
window:SetPosition(Vector2.new(100, 100))
window:SetSize(Vector2.new(587, 563))
window:SelectTab("Tab")
window:Destroy()
```

`Nephren:Unload()` disconnects input/render connections and removes only the
drawing objects owned by this library. It deliberately does not call
`cleardrawcache`, so unrelated overlays remain untouched.
