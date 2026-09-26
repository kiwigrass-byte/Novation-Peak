# Electra One Preset References (fw 5.x)

This file captures external documentation and project conventions we rely on when developing and maintaining Electra One presets.

## Official documentation

- Electra One developer docs (fw 5.0): https://docs.electra.one/5.0/developers/
- Architecture / value-change flow: https://docs.electra.one/5.0/developers/architecture.html#what-happens-when-a-value-changes

## Key API feature

- `parameterMap.transaction(fn)`
  - Use for bulk patch-parse apply paths (e.g., `assignParam()`).
  - While transaction is open: map updates are held, callbacks are deferred, UI redraw is coalesced.
  - On close: screen/map updates once per changed parameter.

## Project lessons learned (Novation Peak preset)

### 1) Origin checks: explicit intent
- Prefer explicit origin handling by what we **allow**, not “not X”.
- If logic is intended for direct UI edits only, gate to `INTERNAL`.
- Do not assume `onChange` filtering alone covers all send paths.

### 2) Bound value functions can transmit too
- Functions bound to controls (e.g., `waveChange`, `setSync`) can run during value propagation.
- Therefore, sending MIDI inside those functions must also be origin-gated.
- Pattern used:

```lua
local function isInternalOrigin(valueObject)
  local msg = valueObject and valueObject:getMessage()
  if not msg or not msg.getOrigin then return false end
  return msg:getOrigin() == INTERNAL
end
```

Use `if isInternalOrigin(valueObject) then sendSimpleNRPN(...) end`.

### 3) Avoid pointless MIDI echo on patch load
- During incoming patch/settings parsing from synth → E1:
  - update Parameter Map
  - update UI state
  - **do not send same values back to synth** unless explicitly intended
- This prevents monitor noise and unnecessary traffic.

### 4) Where transaction is worth it
- High value:
  - `assignParam()` / full patch dump parse (hundreds of values)
- Low value:
  - tiny settings updates (single-digit params), unless there is visible churn.

### 5) Post-transaction follow-up
After bulk patch apply settles, then run derived-state/UI sync:
- macro baseline setup
- mod matrix dim/update refresh
- snapshot capture
- patch name/info text refresh

## Preset UX conventions in this repo

- Patch scroll and patch select are separate controls.
- Explicit patch select (+ / -) sends:
  1. bank/program change
  2. explicit patch request SysEx
- This is intentional and preferred over automatic debounce behavior.

## Maintenance note

When updating this file, keep examples concrete and tied to observed behavior in MIDI monitor/output logs.
