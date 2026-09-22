# Macro-Knob LFO Design Note

## Status

Design note for a future enhancement to the Novation Peak v6.4 Electra One preset.

Date: September 22, 2026

## Goal

Add a slow-moving LFO that modulates the virtual macro knob parameter (`10038`). The macro LFO should reuse the existing macro processing so that all current behavior remains consistent:

- unlocked modulation amounts are scaled automatically;
- locked modulation slots remain unchanged;
- modulation amounts at the centered/base value (`64`) are skipped;
- unchanged values do not generate redundant NRPN messages;
- changed modulation amounts are sent to the Peak as NRPN values.

## Existing architecture

The macro knob is represented by virtual parameter `10038`. Its current processing calculates a bipolar macro factor and applies it to the 16 modulation amount parameters:

```lua
PARAM_MOD_AMOUNT = {
  130, 258, 386, 514,
  642, 770, 898, 1026,
  1154, 1282, 1410, 1538,
  1666, 1794, 1922, 2050
}
```

The macro should continue to call the existing lock-aware `applyMacroToAll()` function rather than duplicating scaling or MIDI-send logic.

## Timer constraint

The preset already uses the single Electra One `timer` object for scanning all 512 Peak patches and collecting patch names. The LFO cannot install an independent timer callback. The existing `timer.onTick()` should dispatch between:

1. patch scanning, when `patchScanState.isRunning` is true; and
2. macro-LFO updates, when `macroLfoState.isRunning` is true.

The patch scanner and macro LFO should normally be mutually exclusive because both need to control the timer period and callback.

## Proposed state

```lua
local macroLfoState = {
  isRunning = false,
  phase = 0.0,
  periodMs = 4000, -- one complete cycle
  stepMs = 50,     -- timer interval
  waveform = 1,    -- future waveform selector
  minValue = 0,
  maxValue = MACRO_MAX,
}
```

The first implementation can use a fixed triangle wave. Rate, waveform, and range can be exposed as virtual parameters later.

## Triangle-wave behavior

A unipolar triangle wave can be generated from phase `0..1`:

```lua
local function triangleValue(phase)
  local triangle = phase < 0.5
    and phase * 2
    or 2 - phase * 2

  return math.floor(
    macroLfoState.minValue
      + triangle * (macroLfoState.maxValue - macroLfoState.minValue)
      + 0.5
  )
end
```

A useful initial range is the full macro range, `0..16383`. A later version may default to a narrower range around `MACRO_CENTER` (`8192`) to make the effect less extreme.

## Proposed controls

Future controls should include:

- LFO enable/disable toggle;
- LFO rate or cycle-period control;
- waveform selector, initially triangle and optionally sine, ramp, and square;
- minimum macro value;
- maximum macro value;
- optional reset-phase control.

These should use virtual parameters that do not conflict with existing preset parameters. The current macro lock parameters occupy `10050..10065`, so a separate range should be selected after auditing the preset.

## Timer integration sketch

The existing timer callback can be extended along these lines:

```lua
function timer.onTick()
  if patchScanState.isRunning then
    -- Existing patch-scan request/advance logic.
    return
  end

  if macroLfoState.isRunning then
    macroLfoState.phase = macroLfoState.phase
      + macroLfoState.stepMs / macroLfoState.periodMs

    if macroLfoState.phase >= 1 then
      macroLfoState.phase = macroLfoState.phase - 1
    end

    local value = triangleValue(macroLfoState.phase)
    macroKnobValue = value
    parameterMap.set(deviceId, PT_VIRTUAL, PARAM_MACRO_KNOB, value)
    applyMacroToAll()
  end
end
```

The exact implementation should avoid applying the macro twice if `parameterMap.set()` invokes the macro parameter-change handler. This needs to be verified against the Electra One runtime behavior. If the parameter-change handler already calls `applyMacroToAll()`, the timer should update the virtual parameter and let that handler do the work, or use a guard around the explicit call.

## Start/stop behavior

Starting the LFO should:

- refuse to start while patch scanning is active, or stop the scanner explicitly;
- reset or preserve phase according to a deliberate UI choice;
- set the timer period to `stepMs`;
- enable the timer.

Stopping the LFO should:

- set `isRunning = false`;
- disable the timer only if patch scanning is not active;
- leave the macro at its current value unless a reset behavior is explicitly added.

## MIDI behavior

The LFO must not send NRPN for virtual parameter `10038` itself. Instead, every LFO step should result in the normal macro calculation, and `applyMacroToAll()` should:

1. skip locked slots;
2. skip slots whose base amount is `64`;
3. calculate the new amount;
4. compare it with the current parameter value;
5. update the UI with `parameterMap.set()`; and
6. explicitly send an NRPN for changed real Peak modulation amount parameters.

This preserves the optimized behavior already implemented for manual macro movement.

## Compare behavior

`COMPARE_IT` should continue to work with the LFO:

- compare ON should show the true parsed patch values;
- compare OFF should restore live values and respect locks;
- the LFO should not advance or overwrite compare snapshots unexpectedly.

A safe first implementation should either pause the LFO while comparing or define clearly that the LFO is disabled whenever `COMPARE_IT` is active.

## Testing checklist

Before committing an implementation, test:

- start and stop controls;
- timer coexistence with patch scanning;
- triangle phase progression and cycle period;
- full-range and narrow-range movement;
- locked slot remains fixed;
- base-64 slot sends no NRPN;
- unchanged values send no NRPN;
- changed values send the correct NRPN;
- COMPARE_IT on/off while the LFO is stopped;
- behavior when starting/stopping the LFO during compare mode;
- loading a new patch while the LFO is active;
- MIDI channel and port changes while the LFO is active.

## Recommended implementation order

1. Add the state table and a fixed-rate triangle-wave LFO.
2. Integrate it with the existing timer dispatcher.
3. Add start/stop controls.
4. Verify no duplicate `applyMacroToAll()` calls occur.
5. Add rate control.
6. Add range and waveform controls only after the basic version is stable.
