# Electra One Preset References (fw 5.x)

This file captures external documentation and project conventions we rely on when developing and maintaining Electra One presets.

## Official documentation

- Electra One developer docs (fw 5.0):https://docs.electra.one/5.0/developers/architecture.html
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
  - Ideal for high-frequency temporary value changes (e.g., an LFO timer modulating mod-amount depth) because it avoids the overhead of `set`/`updateValue` (no map write, no callback dispatch, no redraw churn).
  - Used in this preset for the macro-amount LFO instead of repeatedly calling `parameterMap.set`/`updateValue` on a timer tick.
  - Baseline handling: because `modulate` does not alter the stored Parameter Map value, keep a separate baseline cache and apply modulation relative to that.

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

### 7) Scheduled background work: prefer `schedule` over a shared timer
- The patch scanner was migrated from the shared `timer.onTick` callback to `schedule.every(SCAN_PERIOD_MS, scanNextPatch)`.
- The scanner stores the returned schedule handle and calls `schedule.cancel(scanHandle)` when scanning is stopped or complete.
- Primary reason: keep timer path available for macro LFO and avoid scheduling contention.
- Keep each scan step short and deferred.

### 8) Startup sequencing: event-driven wave-name handshake with timeout fallback
- On `preset.onReady()`, request all 10 user wavetable names first.
- Request settings after all expected wavetable replies arrive in `midi.onSysex`, not by default fixed delay.
- Keep a timeout fallback (`schedule.after(...)`) if replies are missing.
- Guard settings request with one-shot flag to avoid duplicates.

### 9) Unset MIDI value
- `MIDI_VALUE_DO_NOT_SEND` indicates “no value to send” and is intentionally outside valid MIDI ranges.
- Accepted by setters that build messages, refused by actual senders (`midi.send*` expects valid MIDI ranges).
- Useful when a control needs meaningful on-value and explicit no-send off-value semantics.

### 10) Macro LFO motion and waveform notes
- Smooth random (S&H) uses curved glide (`smoothBezier`) for musical motion.
- Boundary handling uses wave-fold style through boundary waypoint logic (`shBoundary`) to reduce edge stickiness and improve full-range visitation.
- Sine and smooth random preserve value continuity on waveform switches.

### 11) Macro S&H sampling-rate scaling for longer LFO periods (corrected)

- The macro LFO Sample-and-Hold waveform samples new random targets at a cadence derived from the LFO period.
- With `SH_RATE_MIN_PERIOD_MS = 2000`, `SH_RATE_MAX_PERIOD_MS = 20000`, and `SH_RATE_MAX_MULT = 4`:
  - At or below 2 s period: multiplier = 1.0 → one sampled target per cycle (about every 2 s at 2 s period).
  - At or above 20 s period: multiplier = 4.0 → four sampled targets per cycle (every 5 s at 20 s period).
  - Between 2 s and 20 s: linear interpolation of the multiplier.
- Effective S&H step interval is:
  - `shPeriodMs = periodMs / shSampleMultiplier(periodMs)`
- Therefore, with current code the slow-end step interval is **5 s** (not 4 s).
- If a 4 s slow-end step interval is desired at 20 s period, `SH_RATE_MAX_MULT` must be 5.

## XY Pad Mapping: Flip, Curve, and Sync Behavior

The XY pad writes two selected parameters using `PARAM_X_SELECT` and `PARAM_Y_SELECT`, with each destination defined in `PARAM_X` / `PARAM_Y` as:
- parameter number
- parameter type
- maximum value (`127` for 7-bit, `16383` for 14-bit)

### Mapping behavior

Each axis supports:
- `FLIP`
  - `0` = normal
  - `1` = reversed
- `CURVE`
  - `0` = linear
  - `1` = exponential-style
  - `2` = logarithmic-style

Value flow:
- **Pad movement → synth parameters** via `emit()`
- **Synth parameters → pad position** via `syncXYFromParams()`

### Interaction model
- `touchXY()` calls `emit()` so movement updates synth immediately.
- `xyOptionChange()` also calls `emit()` so changing flip/curve updates synth immediately from current dot position.
- `xySelectChange()` calls `syncXYFromParams()` so dot follows newly selected destination parameter.

### Notes
- The destination max field in `PARAM_X` / `PARAM_Y` handles 7-bit vs 14-bit scaling.
- Use nearest-integer rounding for writes.
- Use `clamp01()` when reading back to keep dot in range.
- `PARAM_Y = PARAM_X` is valid if both axes share destination list.

## XY LFO (XY pad modulation) behavior and conventions

The XY pad has an internal LFO that modulates pad coordinates (`X`, `Y`) before `emit()` writes selected destination parameters.

### Parameters

- `PARAM_XY_LFO_MODE` (`12010`)
  - `0` Off
  - `1` Uni+ (toward max edge)
  - `2` Uni- (toward min edge)
  - `3` Bipolar (around center)
- `PARAM_XY_LFO_RATE` (`12011`): `0..255` (log-mapped period)
- `PARAM_XY_LFO_WAVE` (`12012`): `0` Sine, `1` Smooth Random (S&H glide)
- `PARAM_XY_LFO_DEPTH_X` (`12013`): `0..100 %`
- `PARAM_XY_LFO_DEPTH_Y` (`12014`): `0..100 %`
- `PARAM_XY_LFO_PHASE_Y` (`12015`): `0..360` degrees (`360` is equivalent to `0`)
- `PARAM_XY_LFO_HOLD` (`12016`): `0/1` (pause LFO while touching XY pad when `1`)

### Phase

- `PARAM_XY_LFO_PHASE_Y` is interpreted as degrees:
  - `xyLfo.phaseY = phaseDegrees / 360`
- Useful landmarks:
  - `0°`: X and Y in phase
  - `90°`: quadrature (circle/ellipse-like)
  - `180°`: inverse
  - `270°`: opposite quadrature
  - `360°`: same as `0°`

### Depth and boundary behavior

XY LFO uses **edge-aware depth scaling** to avoid boundary dwell:
- `maxPlus = 1 - center`
- `maxMinus = center`
- Uni+/Uni-/Bipolar apply depth within those limits rather than hard clipping at edges.
- This keeps depth useful across full `0..100%` range.

### Hold and center semantics

- On touch down:
  - `xyLfo.userTouching = true`
  - if Hold = 1, LFO motion pauses while manual touch updates continue.
- On touch up:
  - `xyLfo.userTouching = false`
  - center updates to current dot (`centerX`, `centerY`) as new orbit center.
- Optional `Set Center` action explicitly latches current dot position as center.
- Center marker on the pad visualizes the current orbit center.

### Smooth Random cadence (XY)

With:
- `XY_SH_RATE_MIN_PERIOD_MS = 2000`
- `XY_SH_RATE_MAX_PERIOD_MS = 20000`
- `XY_SH_RATE_MAX_MULT = 4`

Then at long periods, S&H cadence scales up to 4x relative to cycle period (20 s period → 5 s per S&H step).

### Control wiring conventions (important)

- XY rate (`12011`) and XY wave (`12012`) must be different parameter numbers.
- Do not reuse macro LFO rate formatter if it reads macro wave parameter (`PARAM_LFO_WAVE`).
- Use an XY-specific formatter for XY rate that reads `PARAM_XY_LFO_WAVE`.
- If rate text depends on wave (`s` vs `s/step`), force rate-display refresh when XY wave changes (bump/revert technique).

## Preset UX conventions in this repo

- Patch scroll and patch select are separate controls.
- Explicit patch select (+ / -) sends:
  1. bank/program change
  2. explicit patch request SysEx
- This is intentional and preferred over automatic debounce behavior.

## Maintenance note

When updating this file, keep examples concrete and tied to observed behavior in MIDI monitor/output logs.
