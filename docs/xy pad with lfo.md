# XY Pad Template for Electra One / Novation Peak

This template provides a reusable XY pad controller with:
- 2-axis pad input
- optional LFO modulation on X and Y
- per-axis flip and curve shaping
- LFO rate / waveform / depth / phase controls
- live scope display for both traces
- reset behavior and virtual parameter defaults

It was designed to be adapted to a custom preset by swapping in the target synth parameters and control IDs.

## 1. What it does

The pad works like a normalized 2D controller:

- X and Y are stored as values from 0.0 to 1.0
- the values are mapped to actual synth parameters
- optional LFO modulation offsets the position around a center point
- each axis supports:
  - flip
  - curve shaping
  - independent depth
  - optional hold-on-touch behavior
- a scope shows the live X/Y movement for debugging and visual feedback

This is useful for:
- assignable synth controls like cutoff + resonance
- filter mix / pan combinations
- morphing between modulation targets
- any 2D CV-like control surface

---

## 2. Required wiring

The template expects a few things to exist in the preset:

### Control IDs
These are configured in `CFG`:

```lua
local CFG = {
  deviceId = 1,

  xyPadCtrl = 19,
  phaseYCtrl = 10,
  corrCtrl = 4,
  scopeCtrl = 25,

  xSelectParam = 12000,
  ySelectParam = 12001,
  xFlipParam   = 12002,
  yFlipParam   = 12003,
  xCurveParam  = 12004,
  yCurveParam  = 12005,

  xyLfoModeParam   = 12010,
  xyLfoRateParam   = 12011,
  xyLfoWaveParam   = 12012,
  xyLfoDepthXParam = 12013,
  xyLfoDepthYParam = 12014,
  xyLfoPhaseYParam = 12015,
  xyLfoHoldParam   = 12016,
  xySetCenterParam = 12017,
  xyLfoCorrParam   = 12018,
  xyResetParam     = 12019,
}
