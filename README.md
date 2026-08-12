# Nephren

Nephren is a lightweight UI library for Roblox scripts written in Luau. It
uses a script executor's Drawing API to create interactive windows and controls
without Roblox GUI instances.

## Features

- Customizable windows, tabs, and sections
- Buttons, checkboxes, toggles, labels, and separators
- Sliders, dropdowns, multi-dropdowns, spinners, and listboxes
- Textboxes, keybinds, and color pickers
- Flags for reading and updating control values
- Named JSON configs for flagged controls
- Window dragging, resizing, visibility toggling, and cleanup

## Config persistence

Controls with a string `Flag` can be saved to and restored from named JSON files. By default,
Nephren stores them in `Nephren/configs`; the folder can be changed before saving:

```luau
local configured, folderOrError = Nephren:SetConfigFolder("MyScript/configs")
assert(configured, folderOrError)

local saved, countOrError = window:SaveConfig("default")
assert(saved, countOrError)

local loaded, appliedOrError, skipped = window:LoadConfig("default")
assert(loaded, appliedOrError)
print("Loaded flags:", appliedOrError, "skipped:", skipped)

local configs, listError = window:ListConfigs()
assert(configs, listError)

local deleted, nameOrError = window:DeleteConfig("default")
assert(deleted, nameOrError)
```

`window:SaveConfig` and `window:LoadConfig` operate on one window. The matching
`Nephren:SaveConfig` and `Nephren:LoadConfig` methods operate on the active flag owner
across every live window. Both scopes share the same config folder and filenames.
Passing `true` as the second argument to `LoadConfig` applies values without firing
control callbacks:

```luau
window:LoadConfig("default", true)
```

Configs preserve booleans, finite numbers, strings, `Color3`, `EnumItem`, `nil`, and
table values such as multi-dropdown selections. Unflagged controls are ignored, and
flags not present in the current UI are safely skipped during loading. Set
`Persist = false` on a flagged control to exclude it from configs.

File persistence uses the executor's `writefile`, `readfile`, `listfiles`, `delfile`,
`isfile`, `isfolder`, and `makefolder` APIs when applicable. A missing required API or
an invalid config returns an error value instead of throwing.
