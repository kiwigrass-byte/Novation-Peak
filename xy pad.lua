-- ========================= XY Pad + XY LFO ==========================================
-- Description: 2-axis touch pad with optional XY LFO modulation.

do
-- XY_PAD CTRL ID
local CTRL_XY_PAD = 381

-- State (normalized 0..1, origin bottom-left)
local X = 0.5
local Y = 0.5

local xYControl = controls.get(CTRL_XY_PAD)

local XY_WIDTH = 325 -- 650
local XY_HEIGHT = 325

-- Colors
local BG   = 0x000000
local GRID = 0x404040
local DOT  = 0xFFFFFF
local CTR  = 0x00D0FF   -- center marker color (cyan-ish)

-- option parameters
local PARAM_X_SELECT = 12000
local PARAM_Y_SELECT = 12001
local PARAM_X_FLIP   = 12002
local PARAM_Y_FLIP   = 12003
local PARAM_X_CURVE  = 12004
local PARAM_Y_CURVE  = 12005

-- Synth MIDI parameters the XY pad writes to. {param number, param type, MIDI max}
local PARAM_X = { [0] = {29, 2, 16383}, {79, 1, 127}, {43, 0, 127}, {44, 0, 127},  
                {23, 2, 16383}, {24, 2, 16383}, {25, 2, 16383}, {51, 0, 127}, {5, 1, 127}, {30, 2, 16383}, {31, 2, 16383},
                 }
local PARAM_Y = PARAM_X

-- ===== Curve / flip helpers =====
local CURVE_EXP, CURVE_LOG = 1, 2

local function clamp01(v)
  if v < 0 then return 0 end
  if v > 1 then return 1 end
  return v
end

-- n: 0..1 -> shaped 0..1
local function applyCurve(n, curve)
  if curve == CURVE_EXP then
    return n * n
  elseif curve == CURVE_LOG then
    return 1 - (1 - n) * (1 - n)
  end
  return n
end

-- shaped 0..1 -> n: 0..1
local function invertCurve(n, curve)
  if curve == CURVE_EXP then
    return math.sqrt(n)
  elseif curve == CURVE_LOG then
    return 1 - math.sqrt(1 - n)
  end
  return n
end

local function padToParam(n, flip, curve)
  if flip == 1 then n = 1 - n end
  return applyCurve(n, curve)
end

local function paramToPad(n, flip, curve)
  n = invertCurve(n, curve)
  if flip == 1 then n = 1 - n end
  return n
end

local function getAxisOptions()
  local xFlip  = parameterMap.get(deviceId, PT_VIRTUAL, PARAM_X_FLIP)  or 0
  local yFlip  = parameterMap.get(deviceId, PT_VIRTUAL, PARAM_Y_FLIP)  or 0
  local xCurve = parameterMap.get(deviceId, PT_VIRTUAL, PARAM_X_CURVE) or 0
  local yCurve = parameterMap.get(deviceId, PT_VIRTUAL, PARAM_Y_CURVE) or 0
  return xFlip, yFlip, xCurve, yCurve
end

local function emit()
  local xNum = parameterMap.get(deviceId, PT_VIRTUAL, PARAM_X_SELECT)
  local yNum = parameterMap.get(deviceId, PT_VIRTUAL, PARAM_Y_SELECT)
  local xd = PARAM_X[xNum]
  local yd = PARAM_Y[yNum]
  if not xd or not yd then return end

  local xFlip, yFlip, xCurve, yCurve = getAxisOptions()
  local xn = padToParam(X, xFlip, xCurve)
  local yn = padToParam(Y, yFlip, yCurve)

  parameterMap.set(deviceId, xd[2], xd[1], math.floor(xn * xd[3] + 0.5))
  parameterMap.set(deviceId, yd[2], yd[1], math.floor(yn * yd[3] + 0.5))
end

-- ========================= XY LFO ====================================================

local PARAM_XY_LFO_MODE      = 12010 -- 0 off, 1 uni, 2 bi
local PARAM_XY_LFO_RATE      = 12011 -- 0..255
local PARAM_XY_LFO_WAVE      = 12012 -- 0 sine, 1 S&H
local PARAM_XY_LFO_DEPTH_X   = 12013 -- 0..100
local PARAM_XY_LFO_DEPTH_Y   = 12014 -- 0..100
local PARAM_XY_LFO_PHASE_Y   = 12015 -- 0..360 degrees
local PARAM_XY_LFO_HOLD      = 12016 -- 0/1
local PARAM_XY_LFO_CORR      = 12018 -- 0..100 (0=independent, 100=linked)

local PHASE_MAX = 360

-- mode enum
local XY_LFO_OFF      = 0
local XY_LFO_UNI_POS  = 1  -- unipolar up/right
local XY_LFO_UNI_NEG  = 2  -- unipolar down/left
local XY_LFO_BIPOLAR  = 3

local XY_LFO_SINE, XY_LFO_SH = 0, 1

local XY_RATE_MIN_MS, XY_RATE_MAX_MS = 300, 20000
local XY_SH_RATE_MIN_PERIOD_MS, XY_SH_RATE_MAX_PERIOD_MS = 2000, 20000
local XY_SH_RATE_MAX_MULT, XY_SH_MAX_STEP, XY_SH_GLIDE_FRACTION = 4, 1.00, 1.00

local xyLfo = {
  isRunning=false, phase=0.0, shPhase=1.0, periodMs=3000, stepMs=33,
  mode=XY_LFO_OFF, waveform=XY_LFO_SINE, depthX=1.0, depthY=1.0, phaseY=0.25, holdOnTouch=1,

  -- independent smooth-random lanes
  heldRandomX=0.5, heldRandomY=0.5,
  shFromX=0.5, shFromY=0.5,
  shToX=0.5, shToY=0.5,
  shBoundaryX=nil, shBoundaryY=nil,

  centerX=0.5, centerY=0.5, userTouching=false,
  corr = 0,
}
local xyLfoHandle = nil

local function xyLfoClamp01(v) if v<0 then return 0 elseif v>1 then return 1 else return v end end
local function xyLfoSmoothBezier(t) return t*t*(3-2*t) end

local function xyLfoRateToPeriodMs(value)
  local t = (value or 0) / 255
  local logMin, logMax = math.log(XY_RATE_MIN_MS), math.log(XY_RATE_MAX_MS)
  local logPeriod = logMax + (logMin - logMax) * t
  return math.floor(math.exp(logPeriod) + 0.5)
end

local function xyShSampleMultiplier(periodMs)
  if periodMs <= XY_SH_RATE_MIN_PERIOD_MS then return 1.0 end
  if periodMs >= XY_SH_RATE_MAX_PERIOD_MS then return XY_SH_RATE_MAX_MULT end
  local t = (periodMs - XY_SH_RATE_MIN_PERIOD_MS) / (XY_SH_RATE_MAX_PERIOD_MS - XY_SH_RATE_MIN_PERIOD_MS)
  return 1.0 + t * (XY_SH_RATE_MAX_MULT - 1.0)
end

local function xyChooseNextTarget1D(fromValue)
  local signedRandom = math.random() + math.random() - 1
  local newTarget = fromValue + signedRandom * XY_SH_MAX_STEP

  if newTarget > 1 then
    local overshoot = newTarget - 1
    return 1 - overshoot, 1
  elseif newTarget < 0 then
    local overshoot = -newTarget
    return overshoot, 0
  else
    return newTarget, nil
  end
end

local function xyChooseNextSHTarget()
  xyLfo.shFromX = xyLfo.heldRandomX
  xyLfo.shFromY = xyLfo.heldRandomY
  xyLfo.shToX, xyLfo.shBoundaryX = xyChooseNextTarget1D(xyLfo.shFromX)
  xyLfo.shToY, xyLfo.shBoundaryY = xyChooseNextTarget1D(xyLfo.shFromY)
end

local function xyUpdateSHGlide1D(fromValue, toValue, boundary, phase01)
  local glideFraction = XY_SH_GLIDE_FRACTION
  if glideFraction <= 0 or phase01 >= glideFraction then
    return toValue
  end

  local glidePosition = xyLfoClamp01(phase01 / glideFraction)

  if boundary == nil then
    local eased = xyLfoSmoothBezier(glidePosition)
    return fromValue + (toValue - fromValue) * eased
  end

  local d1 = math.abs(boundary - fromValue)
  local d2 = math.abs(toValue - boundary)
  local total = d1 + d2
  local splitPoint = (total > 0) and (d1 / total) or 0.5

  if glidePosition < splitPoint then
    local localT = (splitPoint > 0) and (glidePosition / splitPoint) or 1
    local eased = xyLfoSmoothBezier(localT)
    return fromValue + (boundary - fromValue) * eased
  else
    local remaining = 1 - splitPoint
    local localT = (remaining > 0) and ((glidePosition - splitPoint) / remaining) or 1
    local eased = xyLfoSmoothBezier(localT)
    return boundary + (toValue - boundary) * eased
  end
end

local function xyUpdateSHGlide()
  xyLfo.heldRandomX = xyUpdateSHGlide1D(xyLfo.shFromX, xyLfo.shToX, xyLfo.shBoundaryX, xyLfo.shPhase)
  xyLfo.heldRandomY = xyUpdateSHGlide1D(xyLfo.shFromY, xyLfo.shToY, xyLfo.shBoundaryY, xyLfo.shPhase)
end

local function mix(a, b, t)
  return a + (b - a) * t
end

local function xyWaveAtPhase(phase01, axis)
  phase01 = phase01 - math.floor(phase01)
  if xyLfo.waveform == XY_LFO_SH then
    local rx = xyLfo.heldRandomX
    local ry = xyLfo.heldRandomY
    local linked = 0.5 * (rx + ry) -- shared component
    if axis == "y" then
      return mix(ry, linked, xyLfo.corr)
    else
      return mix(rx, linked, xyLfo.corr)
    end
  end
  return 0.5 + 0.5 * math.sin(phase01 * 2 * math.pi)
end

-- Convert waveform to axis position around center with edge-aware depth.
-- This avoids hard clipping plateaus at boundaries.
local function xyApplyDepth(center, wave01, depth, mode)
  center = xyLfoClamp01(center)
  depth = xyLfoClamp01(depth)

  local maxPlus  = 1 - center
  local maxMinus = center

  if mode == XY_LFO_UNI_POS then
    -- 0..1 maps center -> max edge
    local amp = maxPlus * depth
    return center + wave01 * amp

  elseif mode == XY_LFO_UNI_NEG then
    -- 0..1 maps center -> min edge
    local amp = maxMinus * depth
    return center - wave01 * amp

  else
    -- bipolar: symmetric waveform, edge-aware per side
    local bipolar = (wave01 * 2) - 1
    if bipolar >= 0 then
      return center + bipolar * (maxPlus * depth)
    else
      return center + bipolar * (maxMinus * depth)
    end
  end
end

local function xyEmitAndRepaint()
  emit()
  if xYControl then xYControl:repaint() end
end

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
end

local function xyLfoStopScheduler()
  if xyLfoHandle then schedule.cancel(xyLfoHandle); xyLfoHandle = nil end
end

local function xyLfoStartScheduler()
  xyLfoStopScheduler()
  xyLfoHandle = schedule.every(xyLfo.stepMs, xyLfoTick)
end

local function xyLfoApplyParams()
  xyLfo.mode = parameterMap.get(deviceId, PT_VIRTUAL, PARAM_XY_LFO_MODE) or XY_LFO_OFF
  if xyLfo.mode < XY_LFO_OFF or xyLfo.mode > XY_LFO_BIPOLAR then
    xyLfo.mode = XY_LFO_BIPOLAR
  end

  xyLfo.waveform  = parameterMap.get(deviceId, PT_VIRTUAL, PARAM_XY_LFO_WAVE) or XY_LFO_SINE
  xyLfo.periodMs  = xyLfoRateToPeriodMs(parameterMap.get(deviceId, PT_VIRTUAL, PARAM_XY_LFO_RATE) or 0)
  xyLfo.depthX    = (parameterMap.get(deviceId, PT_VIRTUAL, PARAM_XY_LFO_DEPTH_X) or 0) / 100
  xyLfo.depthY    = (parameterMap.get(deviceId, PT_VIRTUAL, PARAM_XY_LFO_DEPTH_Y) or 0) / 100
  xyLfo.holdOnTouch = parameterMap.get(deviceId, PT_VIRTUAL, PARAM_XY_LFO_HOLD) or 1

  -- put correlation here
  xyLfo.corr = (parameterMap.get(deviceId, PT_VIRTUAL, PARAM_XY_LFO_CORR) or 0) / 100
  if xyLfo.corr < 0 then xyLfo.corr = 0 elseif xyLfo.corr > 1 then xyLfo.corr = 1 end

  local p = parameterMap.get(deviceId, PT_VIRTUAL, PARAM_XY_LFO_PHASE_Y) or 90
  if p < 0 then p = 0 elseif p > PHASE_MAX then p = PHASE_MAX end
  xyLfo.phaseY = p / PHASE_MAX
end

local function xyLfoStart()
  xyLfoApplyParams()
  if xyLfo.mode == XY_LFO_OFF then xyLfo.isRunning=false; xyLfoStopScheduler(); return end
  xyLfo.isRunning = true
  xyLfoStartScheduler()
end

local function xyLfoStop()
  xyLfo.isRunning = false
  xyLfoStopScheduler()
end

function xyLfoParamChange(valueObject, value)
  xyLfoApplyParams()
  if xyLfo.mode == XY_LFO_OFF then
    xyLfoStop()
  elseif not xyLfo.isRunning then
    xyLfoStart()
  end
end

function xyLfoSetCenter(valueObject, value)
  if value == 0 then return end
  xyLfo.centerX, xyLfo.centerY = X, Y
end

local CTRL_XY_PHASE_Y = 387
local CTRL_XY_RANDOM_CORR = 391
local XY_SHARED_SLOT = 22
local XY_SHARED_PAGE = 7

local function updateXyWaveUi(wave)
  local phaseCtrl = controls.get(CTRL_XY_PHASE_Y)
  local corrCtrl  = controls.get(CTRL_XY_RANDOM_CORR)
  if not phaseCtrl or not corrCtrl then return end

  if wave == XY_LFO_SINE then
    phaseCtrl:setSlot(XY_SHARED_SLOT, XY_SHARED_PAGE)
    -- optional cleanliness:
    phaseCtrl:setVisible(true)
    corrCtrl:setVisible(false)
  else -- XY_LFO_SH
    corrCtrl:setSlot(XY_SHARED_SLOT, XY_SHARED_PAGE)
    corrCtrl:setVisible(true)
    phaseCtrl:setVisible(false)
  end
end

function initXYLfo()
  xyLfoApplyParams()
  updateXyWaveUi(xyLfo.waveform)
  if xyLfo.mode ~= XY_LFO_OFF then xyLfoStart() end
end

function initXYPad()
  local bounds = xYControl:getBounds()
  bounds[WIDTH]  = XY_WIDTH
  bounds[HEIGHT] = XY_HEIGHT
  xYControl:setBounds(bounds)
  xYControl:setPaintCallback(paintXY)
  xYControl:setTouchCallback(touchXY)
  syncXYFromParams()
  initXYLfo()
end

function resetXYVirtualDefaults()
  parameterMap.updateValue(deviceId, PT_VIRTUAL, PARAM_X_SELECT, 0)
  parameterMap.updateValue(deviceId, PT_VIRTUAL, PARAM_Y_SELECT, 1)
  parameterMap.updateValue(deviceId, PT_VIRTUAL, PARAM_X_FLIP, 0)
  parameterMap.updateValue(deviceId, PT_VIRTUAL, PARAM_Y_FLIP, 0)
  parameterMap.updateValue(deviceId, PT_VIRTUAL, PARAM_X_CURVE, 0)
  parameterMap.updateValue(deviceId, PT_VIRTUAL, PARAM_Y_CURVE, 0)
  parameterMap.updateValue(deviceId, PT_VIRTUAL, PARAM_XY_LFO_MODE, 0)
  parameterMap.updateValue(deviceId, PT_VIRTUAL, PARAM_XY_LFO_RATE, 64)
  parameterMap.updateValue(deviceId, PT_VIRTUAL, PARAM_XY_LFO_WAVE, 0)
  parameterMap.updateValue(deviceId, PT_VIRTUAL, PARAM_XY_LFO_PHASE_Y, 90)
  parameterMap.updateValue(deviceId, PT_VIRTUAL, PARAM_XY_LFO_HOLD, 1)
  parameterMap.updateValue(deviceId, PT_VIRTUAL, PARAM_XY_LFO_CORR, 0)
  parameterMap.updateValue(deviceId, PT_VIRTUAL, PARAM_XY_LFO_DEPTH_X, 35)
  parameterMap.updateValue(deviceId, PT_VIRTUAL, PARAM_XY_LFO_DEPTH_Y, 35)
end

-- ========================= XY draw/touch/sync callbacks ==============================

function paintXY(control, value)
  local b = control:getBounds()
  local w = b[WIDTH]
  local h = b[HEIGHT]

  g.setColor(BG); g.fillRect(0, 0, w, h)
  g.setColor(GRID); g.drawRoundRect(0, 0, w, h, 5)

  local mx = math.floor(w / 2)
  local my = math.floor(h / 2)
  g.drawLine(mx, 0, mx, h)
  g.drawLine(0, my, w, my)

  -- center marker (LFO orbit center)
  local ccx = math.floor(xyLfo.centerX * w + 0.5)
  local ccy = math.floor((1 - xyLfo.centerY) * h + 0.5)
  g.setColor(CTR)
  g.drawLine(ccx - 6, ccy, ccx + 6, ccy)
  g.drawLine(ccx, ccy - 6, ccx, ccy + 6)

  -- XY cursor
  g.setColor(DOT)
  local cx = math.floor(X * w)
  local cy = math.floor((1 - Y) * h)
  g.fillCircle(cx, cy, 10)
end

function touchXY(control, event)
  if event.type == DOWN then
    xyLfo.userTouching = true
  elseif event.type == UP then
    xyLfo.userTouching = false
    xyLfo.centerX, xyLfo.centerY = X, Y
  end

  if event.type == MOVE or event.type == DOWN then
    local b = control:getBounds()
    X = math.max(0, math.min(1, event.x / b[WIDTH]))
    Y = math.max(0, math.min(1, 1 - event.y / b[HEIGHT]))
    emit()
    control:repaint()
  end
end

function syncXYFromParams()
  local xNum = parameterMap.get(deviceId, PT_VIRTUAL, PARAM_X_SELECT) or 0
  local yNum = parameterMap.get(deviceId, PT_VIRTUAL, PARAM_Y_SELECT) or 1
  local xd = PARAM_X[xNum]
  local yd = PARAM_Y[yNum]
  if not xd or not yd then return end

  local xFlip, yFlip, xCurve, yCurve = getAxisOptions()
  local xv = parameterMap.get(deviceId, xd[2], xd[1])
  local yv = parameterMap.get(deviceId, yd[2], yd[1])

  if xv then X = clamp01(paramToPad(clamp01(xv / xd[3]), xFlip, xCurve)) end
  if yv then Y = clamp01(paramToPad(clamp01(yv / yd[3]), yFlip, yCurve)) end

  xyLfo.centerX, xyLfo.centerY = X, Y
  xYControl:repaint()
end

function xyOptionChange(valueObject, value)
  emit()
end

function xySelectChange(valueObject, value)
  syncXYFromParams()
end

function formatPhaseDegrees(valueObject, value)
  return string.format("%d deg", value or 0)
end

function formatPercentInt(valueObject, value)
  return string.format("%d %%", value or 0)
end

function formatXYLfoRate(valueObject, value)
  local periodMs = xyLfoRateToPeriodMs(value)
  local wave = parameterMap.get(deviceId, PT_VIRTUAL, PARAM_XY_LFO_WAVE) or XY_LFO_SINE
  if wave == XY_LFO_SH then
    local stepMs = periodMs / xyShSampleMultiplier(periodMs)
    if stepMs >= 1000 then
      return string.format("%.1f s/step", stepMs / 1000)
    end
    return string.format("%d ms/step", math.floor(stepMs + 0.5))
  end
  if periodMs >= 1000 then
    return string.format("%.1f s", periodMs / 1000)
  end
  return string.format("%d ms", periodMs)
end

local function xyRefreshRateDisplay()
  local cur = parameterMap.get(deviceId, PT_VIRTUAL, PARAM_XY_LFO_RATE) or 0
  local bump = (cur < 255) and (cur + 1) or (cur - 1)
  parameterMap.set(deviceId, PT_VIRTUAL, PARAM_XY_LFO_RATE, bump)
  parameterMap.set(deviceId, PT_VIRTUAL, PARAM_XY_LFO_RATE, cur)
end

function xyLfoWaveChange(valueObject, value)
  xyLfoParamChange(valueObject, value)
  updateXyWaveUi(value)
  schedule.after(1, xyRefreshRateDisplay)
end

end

-- helper to reset all XY pad params to default when a new patch is loaded 
local function resetVirtualParams()
  if resetXYVirtualDefaults then resetXYVirtualDefaults() end
end

-- assigns parsed synth params to preset params
function assignParam()   
  resetVirtualParams()
  syncXYFromParams()
end

-- initialize XY pad when preset loads
function preset.onLoad()
  -- events to track
  events.subscribe(PAGES | POTS)
  -- initialize XY Pad (now wrapped in its own scope)
  initXYPad()
end
