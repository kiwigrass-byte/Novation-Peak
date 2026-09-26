# Electra One Preset References (fw 5.x)

This file captures external documentation and project conventions we rely on when developing and maintaining Electra One presets.

## Official documentation

- Electra One developer docs (fw 5.0): https://docs.electra.one/5.0/developers/
- Architecture / value-change flow: https://docs.electra.one/5.0/developers/architecture.html#what-happens-when-a-value-changes

## Key API features

- `parameterMap.transaction(fn)`
  - Use for bulk patch-parse apply paths (e.g., `assignParam()`).
  - While transaction is open: map updates are held, callbacks are deferred, UI redraw is coalesced.
  - On close: screen/map updates once per changed parameter.

- `parameterMap.modulate(deviceId, type, parameterNumber, modulationValue, depth)`
  - Temporarily changes (modulates) the MIDI value of a Parameter Map entry.
  - The modulated value **is sent**, but it is **not saved** in the Parameter Map and is **not processed** by Lua callbacks or value formatters.
  - `parameterMap.onChange()` is **not called** for it either.
  - The modulation is spread over the range of the entry's first message and held inside it. For a message with no sign, that range is its MIDI min .. max.
  - Ideal for high-frequency temporary value changes (e.g., an LFO timer modulating mod-amount depth) because it avoids the overhead of `set`/`updateValue` (no map write, no callback dispatch, no formatter re-run) while still transmitting the live value.
  - Used in this preset for the macro-amount LFO (`applyCurrentMacroLfoValue` → `modulateAmountFromBaseline`) instead of repeatedly calling `parameterMap.set`/`updateValue` on a timer tick, which previously caused unnecessary map writes, callback churn, and UI repaint pressure at LFO tick rate.
  - Baseline handling: because `modulate` does not alter the stored Parameter Map value, the script keeps its own baseline cache (`lfoMapBaseline`) captured when the LFO starts, so the modulation depth/direction can be computed relative to the *stored* value rather than the transient modulated one.

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

### 6) High-frequency updates: prefer modulate over set/updateValue
- For timer-driven or rapidly repeating value changes (e.g., an LFO), use `parameterMap.modulate` instead of `parameterMap.set`/`updateValue`.
- This avoids repeated map writes, callback dispatch, and formatter re-evaluation on every tick, while still transmitting the live value to the synth.
- Keep a separate baseline cache for the "real" stored value, since `modulate` does not update the Parameter Map.

## Runtime responsiveness / lock behavior (important)

Electra One script execution and paint callbacks contend for a shared lock.  
If script work holds the lock too long, paint can miss frames (around 20 ms timeout) and controls appear unresponsive.

### Practical rules
- Do small chunks of work frequently instead of long blocks.
- Avoid `helpers.delay()` for waits (it blocks while holding the lock).
- Prefer `schedule.after()` / `schedule.every()` / `midi.at()` so work is deferred and script can return.
- Keep paint callbacks draw-only; precompute elsewhere and render cached values.
- High-frequency modulation should avoid expensive map/callback churn.

### Applied in this preset
- For timer-driven LFO updates, prefer `parameterMap.modulate(...)` over `set`/`updateValue`.
- `modulate` sends live MIDI without writing map state or triggering callbacks/formatters, reducing lock-hold pressure and improving UI responsiveness.
- For large patch parsing, use `parameterMap.transaction(...)` to coalesce map activity and avoid per-parameter callback storms during ingest.
  
## Preset UX conventions in this repo

- Patch scroll and patch select are separate controls.
- Explicit patch select (+ / -) sends:
  1. bank/program change
  2. explicit patch request SysEx
- This is intentional and preferred over automatic debounce behavior.

## Maintenance note

When updating this file, keep examples concrete and tied to observed behavior in MIDI monitor/output logs.
