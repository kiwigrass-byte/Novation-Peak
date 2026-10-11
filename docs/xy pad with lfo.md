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
3. Target parameter map
Lua
local PARAM_X = {
  [0] = {29, 2, 16383},
  [1] = {79, 1, 127},
}

local PARAM_Y = PARAM_X
Each entry is:

Lua
{ parameterNumber, parameterType, maxMidiValue }
4. Write function
Lua
local function emit()
  local xNum = safeParamGet(PT_VIRTUAL, PARAM_X_SELECT, 0)
  local yNum = safeParamGet(PT_VIRTUAL, PARAM_Y_SELECT, 1)
  local xd = PARAM_X[xNum]
  local yd = PARAM_Y[yNum]
  if not xd or not yd then return end

  local xFlip, yFlip, xCurve, yCurve = getAxisOptions()
  local xn = padToParam(X, xFlip, xCurve)
  local yn = padToParam(Y, yFlip, yCurve)

  parameterMap.set(deviceId, xd[2], xd[1], math.floor(xn * xd[3] + 0.5))
  parameterMap.set(deviceId, yd[2], yd[1], math.floor(yn * yd[3] + 0.5))
end
5. LFO tick

Lua
local function xyLfoTick()
  if not xyLfo.isRunning or xyLfo.mode == XY_LFO_OFF then return end
  if xyLfo.holdOnTouch == 1 and xyLfo.userTouching then return end

  xyLfo.phase = xyLfo.phase + (xyLfo.stepMs / xyLfo.periodMs)
  while xyLfo.phase >= 1 do xyLfo.phase = xyLfo.phase - 1 end

  if xyLfo.waveform == XY_LFO_SH then
    local shPeriodMs = xyLfo.periodMs / xyShSampleMultiplier(xyLfo.periodMs)
    xyLfo.shPhase = xyLfo.shPhase + (xyLfo.stepMs / shPeriodMs)
    if xyLfo.shPhase >= 1 then
      xyLfo.shPhase = xyLfo.shPhase - 1
      xyChooseNextSHTarget()
    end
    xyUpdateSHGlide()
  end

  local wx = xyWaveAtPhase(xyLfo.phase, "x")
  local wy = xyWaveAtPhase(xyLfo.phase + xyLfo.phaseY, "y")
  X = xyApplyDepth(xyLfo.centerX, wx, xyLfo.depthX, xyLfo.mode)
  Y = xyApplyDepth(xyLfo.centerY, wy, xyLfo.depthY, xyLfo.mode)

  xyEmitAndRepaint()
  pushScopeSample()
end
6. Scope update
Lua
local function pushScopeSample()
  for i = 1, SCOPE_WIDTH - 1 do
    scope.x[i] = scope.x[i + 1]
    scope.y[i] = scope.y[i + 1]
  end
  scope.x[SCOPE_WIDTH] = unitToBipolar(X)
  scope.y[SCOPE_WIDTH] = unitToBipolar(Y)

  scopeRepaintCount = scopeRepaintCount + 1
  if scopeRepaintCount >= scopeRepaintDiv then
    scopeRepaintCount = 0
    if scopeControl then scopeControl:repaint() end
  end
end
7. Reset
Lua
function xyReset(valueObject, value)
  if value == 0 then return end

  xyLfoStop()
  xyLfo.phase = 0.0
  xyLfo.shPhase = 1.0
  xyLfo.heldRandomX, xyLfo.heldRandomY = 0.5, 0.5
  xyLfo.shFromX, xyLfo.shFromY = 0.5, 0.5
  xyLfo.shToX, xyLfo.shToY = 0.5, 0.5
  xyLfo.shBoundaryX, xyLfo.shBoundaryY = nil, nil
  xyLfo.userTouching = false

  resetXYVirtualDefaults()
  xyLfoApplyParams()
  updateXyWaveUi(xyLfo.waveform)
  emit()
  initializeScopeData()
end
8. Porting checklist
replace PARAM_X and PARAM_Y
update all control IDs in CFG
tune LFO depth / rate / phase
check whether your target params are CC7 or CC14
test reset and scope behavior
This is the easiest version to copy into a preset and adapt.
