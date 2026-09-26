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
  - Ideal for high-frequency temporary value changes (e.g., an LFO timer modulating mod-amount depth) because it avoids the overhead of `set`/`updateValue` (no map write, no callback dispatch, no formatter re-evaluation).
  - Used in this preset for the macro-amount LFO (`applyCurrentMacroLfoValue` → `modulateAmountFromBaseline`) instead of repeatedly calling `parameterMap.set`/`updateValue` on a timer tick, which preserves UI responsiveness under load.
  - Baseline handling: because `modulate` does not alter the stored Parameter Map value, the script keeps its own baseline cache (`lfoMapBaseline`) captured when the LFO starts, so the modulation depth remains accurate around the real stored value.

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
- The patch scanner was migrated from the shared `timer.onTick` callback to
  `schedule.every(SCAN_PERIOD_MS, scanNextPatch)`.
- The scanner stores the returned schedule handle and calls
  `schedule.cancel(scanHandle)` when scanning is stopped or the complete
  four-bank scan has finished.
- The primary reason was to leave the timer path available for the macro-knob
  LFO. Patch scanning and LFO processing are now independent scheduled tasks
  rather than separate responsibilities competing inside one timer callback.
- This also gives the scanner an explicit lifecycle: start, repeat, cancel, and
  completion cleanup can be handled locally in `startPatchScanner()`,
  `scanNextPatch()`, and `stopPatchScanner()`.
- Scheduling keeps each scan step short and deferred. The script sends one
  patch request and returns, instead of performing a long scan or blocking while
  waiting for responses. This helps preserve controller responsiveness during
  large SysEx operations.
- The explicit handle makes cancellation deterministic and prevents a scanner
  from continuing after it has completed, been stopped, or otherwise needs to
  yield to other preset activity.
  
### 8) Startup sequencing: event-driven wave-name handshake with timeout fallback
- On `preset.onReady()`, request all 10 user wavetable names first (slots 64–73).
- Do **not** request settings on a fixed long delay by default.
- Instead, track incoming wavetable-name replies in `midi.onSysex` (cmd `0x07`) and request settings immediately once all expected replies are received.
- Keep a timeout fallback (`schedule.after(...)`) so startup can still continue if one or more replies are missing.
- Guard the settings request with a one-shot flag to prevent duplicate sends when “all replies received” and timeout occur close together.
- In this preset, this reduces unnecessary startup latency versus a fixed 1 s delay while preserving robustness on slower or lossy MIDI paths.
- Replaced fixed startup delay (`schedule.after(..., getSettings, ...)`) with an event-driven handshake.
- On `preset.onReady()`, request user wavetable names (slots 64–73) first.
- Track incoming wavetable-name replies in `midi.onSysex` (`cmd == 0x07`), then request settings immediately after all expected replies arrive.
- Keep a timeout fallback (`schedule.after`) so settings are still requested if one or more wavetable replies are missing.
- Use a one-shot guard so settings request is sent only once even if completion and timeout race.
- Reduced startup log noise by printing a single completion message once all 10 wavetable names are received.
- 
### Applied in this preset
- Patch scanning uses `schedule.every()` with a 200 ms interval.
- `scanHandle` is retained so the repeating task can be cancelled.
- `stopPatchScanner()` flushes pending patch-name persistence after cancelling
  the scheduled task.
- The macro-knob LFO remains responsible for the timer-driven high-frequency
  modulation path, while patch scanning uses the independent scheduling path.

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
