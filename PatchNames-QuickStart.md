# PatchNames Quick Start

This template adds patch-name scanning, caching, persistence, and recall for Electra One presets.

It is designed to be **portable**:
- the **engine** stays the same
- only the **device profile** and **host wiring** need to change for a new synth

---

## What it does

PatchNames:
- requests patch names from the synth
- stores names in a bank/patch cache
- persists the cache across preset reloads
- restores the cache on load
- exposes a simple lookup API for UI display

---

## Template structure

The Lua template is split into three parts:

### 1. Device profile
This is the only part you normally edit for a new synth.

It defines:
- bank count
- patch count per bank
- numbering base
- persistence tag
- scan timing
- SysEx request bytes
- SysEx reply parsing

### 2. Generic engine
This part should not usually be edited.

It handles:
- cache storage
- save/load
- scan scheduling
- dirty tracking
- callbacks
- validation

### 3. Host wiring
This is how you connect the template into a preset.

It usually includes:
- `PatchNames.init(...)`
- `PatchNames.load()`
- `PatchNames.handleSysex(...)`
- `PatchNames.startScan()`
- `PatchNames.get(bank, patch)`

---

## For the Peak example

The Peak profile uses:

- `banks = 4`
- `bankBase = 1`
- `patchesPerBank = 128`
- `patchBase = 0`

That means:
- banks are `1..4`
- patches are `0..127`

If you use another synth, these values may be different.

---

## What to change for another synth

For a new device, update these items:

### Memory layout
- `banks`
- `bankBase`
- `patchesPerBank`
- `patchBase`

### Storage/versioning
- `persistTag`

### Scan timing
- `scanPeriodMs`
- `scanReplyTimeoutMs`

### SysEx request
- `buildRequest(bank, patch)`

### SysEx reply parsing
- `parseReply(block)`

---

## How `parseReply(block)` should work

It should:

1. decide whether the SysEx message is a patch-name reply
2. extract the bank and patch if they are present
3. extract the patch name string
4. return:

```lua
bank, patch, name
```

If the reply does not contain bank/patch numbers, you can return:

```lua
nil, nil, name
```

The engine will then use the last requested bank/patch.

If the message is not a patch-name reply, return:

```lua
nil
```

---

## How `buildRequest(bank, patch)` should work

It should return the SysEx byte table used to request a patch name.

Example:

```lua
buildRequest = function(bank, patch)
  return { 0x00, 0x20, 0x29, 0x01, 0x10, 0x00, 0x7E, 0x41, 0x00, 0x00, 0x00, bank, patch }
end
```

Some synths may need a different request format.

---

## Host wiring

In the preset, connect the template like this:

```lua
PatchNames.init{
  getPort = function() return port end,
  onScanComplete = function()
    -- optional: reset scan button / update UI
  end,
  onNameUpdated = function(bank, patch, name)
    -- optional: debug output or UI refresh
  end,
}
```

Then:

### In `preset.onLoad`
```lua
PatchNames.load()
```

### In `midi.onSysex`
```lua
if PatchNames.handleSysex(sysexBlock) then
  return
end
```

### In the scan control callback
```lua
function startPatchScanner(valueObject, value)
  if value ~= 0 then
    PatchNames.startScan()
  end
end
```

### In patch display code
```lua
local patchName = PatchNames.get(bankNum, patchNum)
```

---

## Important: port handling

Use:

```lua
getPort = function() return port end
```

instead of storing the port directly.

That is safer because:
- `port` may be assigned later
- some presets reassign `port`
- the lookup happens at send time

---

## Testing checklist

### 1. Load test
Reload the preset and confirm there are no Lua errors.

### 2. Restore test
Look for:
- `PatchNames restored (...)`

### 3. Scan test
Start a scan and confirm:
- names are being updated
- periodic saves occur
- scan completes

### 4. Display test
Confirm `PatchNames.get(bank, patch)` returns names in the UI.

---

## Troubleshooting

### “no port set, stopping scan”
The module did not receive a valid `getPort` function or the port is not available yet.

Fix:
- call `PatchNames.init(...)` after `port` is defined
- use `getPort = function() return port end`

### “no matching saved data”
No saved cache exists yet, or the layout tag changed.

Usually this is fine on first load.

### Names do not appear
Check:
- `midi.onSysex` calls `PatchNames.handleSysex(...)` first
- `displayPatch` uses `PatchNames.get(...)`
- the scan is actually started

---

## Peak example summary

For Peak, the important values are:

- 4 banks
- 128 patches per bank
- bank numbers 1..4
- patch numbers 0..127
- Peak SysEx request/reply format

---

## Other synth example

For another synth, you might change to:

- 5 banks
- 100 patches per bank
- bank numbers 0..4
- patch numbers 1..100
- different SysEx request/reply bytes
- different name length or offsets

Only the device profile should change.

---

## Minimal integration summary

You usually only need to do these four things:

1. call `PatchNames.init(...)`
2. call `PatchNames.load()`
3. forward SysEx to `PatchNames.handleSysex(...)`
4. use `PatchNames.get(bank, patch)` in the patch display

---

## Notes

- The template is safe to use with checkpoints during long scans.
- Saved names are restored on preset load.
- The engine can be reused across presets as long as the device profile and host wiring are updated.
