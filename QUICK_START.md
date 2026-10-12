# CompareIt Quick Start

This preset includes a reusable `CompareIt` Lua template for A/B compare on the Novation Peak.

## What it does

- **A** = the patch state captured when the patch is loaded.
- **B** = the live edited state captured when `COMPARE_IT` is turned on.
- **ON** = store live state as B, then show A.
- **OFF** = restore B.

## Files

- `compare-it.lua` — main template and host wiring.

## Requirements

- Firmware **5.0.0 or higher**.
- A virtual control named **COMPARE_IT** with a toggle value of **0/1**.
- Its Lua callback should be set to `compareIt`.

## Setup

1. Copy the `CompareIt` template into the preset you want to use.
2. Keep the engine section unchanged.
3. Fill in `COMPARE_PROFILE.params`, or keep `buildParams()` if you want to generate the parameter list from `PATCH_PARAM_MAP`.
4. After every patch load, call:

   ```lua
   CompareIt.reset()
   CompareIt.captureA()
   ```

5. In any `onChange` handler that should ignore engine writes, add:

   ```lua
   if compareApplying then return end
   ```

## Peak-specific notes

This example is wired for the Novation Peak and includes handling for:

- CC7 / CC14 / NRPN parameters
- SysEx patch parsing
- settings messages
- wavetable name messages
- mod amount and macro state
- the combined master clock byte (`16003`)

## How to use compare mode

- Turn **COMPARE_IT = 1** to capture the current live state as B and show A.
- Turn **COMPARE_IT = 0** to restore B.

## What to customize

### 1) Device profile

Update the mapping table in **Section 1** if you are adapting this template to another device.

### 2) Host wiring

Update **Section 3** so `COMPARE_IT` is wired into your preset correctly.

## Important behavior

- `CompareIt.captureA()` should run after the patch has been parsed.
- If compare mode is active while LFOs are running, the template pauses them and restores them afterward.
- Locked mod amounts are preserved when switching back from compare mode.

## Troubleshooting

- **“COMPARE_IT: no patch parsed yet”**
  - Call `CompareIt.captureA()` after patch parsing.
- **Compare values seem wrong**
  - Make sure the patch SysEx has been captured before `captureA()`.
- **Unexpected writes during compare**
  - Guard your handlers with `if compareApplying then return end`.

## Minimal integration example

```lua
function compareIt(valueObject, value)
  CompareIt.toggle(value)
end

-- after patch parse
CompareIt.reset()
CompareIt.captureA()
```

## Summary

Use this template when you want a reliable A/B compare mode for Peak presets without rewriting the compare logic each time.
