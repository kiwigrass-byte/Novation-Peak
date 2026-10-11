-- ====================== Template for an XY Pad with LFO Modulation ================
-- Preset compatibility check
assert(controller.isRequired(MODEL_MK2, "5.0.0"), "MK2 fw 5.0.0 or higher required")

local CFG = {
  deviceId = 1,

  xyPadCtrl = 19,
  phaseYCtrl = 10,
  corrCtrl = 4,

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
  xyResetParam    = 12019,
}

local deviceId = CFG.deviceId

local function safeControl(id)
  local c = controls.get(id)
  if not c then
    print("Missing control id: " .. tostring(id))
  end
  return c
end

local function safeParamGet(pType, pNum, default)
  local v = parameterMap.get(deviceId, pType, pNum)
  if v == nil then
    return default
  end
  return v
end

-- Synth MIDI parameters the XY pad controls
local PARAM_X = {
  [0] = {29, 2, 16383}, {79, 1, 127}, {43, 0, 127}, {44, 0, 127},
  {23, 2, 16383}, {24, 2, 16383}, {25, 2, 16383}, {51, 0, 127},
  {5, 1, 127}, {30, 2, 16383}, {31, 2, 16383},
}
local PARAM_Y = PARAM_X

do
  local CTRL_XY_PAD = CFG.xyPadCtrl
  local xYControl = safeControl(CTRL_XY_PAD)

  local X = 0.5
  local Y = 0.5

  local XY_WIDTH = 480
  local XY_HEIGHT = 480

  local BG   = 0x000000
  local GRID = 0x404040
  local DOT  = 0xFFFFFF
  local CTR  = 0x00D0FF

  local PARAM_X_SELECT = CFG.xSelectParam
  local PARAM_Y_SELECT = CFG.ySelectParam
  local PARAM_X_FLIP   = CFG.xFlipParam
  local PARAM_Y_FLIP   = CFG.yFlipParam
  local PARAM_X_CURVE  = CFG.xCurveParam
  local PARAM_Y_CURVE  = CFG.yCurveParam

  local CURVE_EXP, CURVE_LOG = 1, 2

  local function clamp01(v)
    if v < 0 then return 0 end
    if v > 1 then return 1 end
    return v
  end

  local function applyCurve(n, curve)
    if curve == CURVE_EXP then
      return n * n
    elseif curve == CURVE_LOG then
      return 1 - (1 - n) * (1 - n)
    end
    return n
  end

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
    local xFlip  = safeParamGet(PT_VIRTUAL, PARAM_X_FLIP, 0)
    local yFlip  = safeParamGet(PT_VIRTUAL, PARAM_Y_FLIP, 0)
    local xCurve = safeParamGet(PT_VIRTUAL, PARAM_X_CURVE, 0)
    local yCurve = safeParamGet(PT_VIRTUAL, PARAM_Y_CURVE, 0)
    return xFlip, yFlip, xCurve, yCurve
  end

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

  -- ========================= XY LFO ====================================================
  local PARAM_XY_LFO_MODE      = CFG.xyLfoModeParam
  local PARAM_XY_LFO_RATE      = CFG.xyLfoRateParam
  local PARAM_XY_LFO_WAVE      = CFG.xyLfoWaveParam
  local PARAM_XY_LFO_DEPTH_X   = CFG.xyLfoDepthXParam
  local PARAM_XY_LFO_DEPTH_Y   = CFG.xyLfoDepthYParam
  local PARAM_XY_LFO_PHASE_Y   = CFG.xyLfoPhaseYParam
  local PARAM_XY_LFO_HOLD      = CFG.xyLfoHoldParam
  local PARAM_XY_LFO_CORR      = CFG.xyLfoCorrParam

  local PHASE_MAX = 360
  local XY_LFO_OFF      = 0
  local XY_LFO_UNI_POS  = 1
  local XY_LFO_UNI_NEG  = 2
  local XY_LFO_BIPOLAR  = 3
  local XY_LFO_SINE, XY_LFO_SH = 0, 1

  local XY_RATE_MIN_MS, XY_RATE_MAX_MS = 300, 20000
  local XY_SH_RATE_MIN_PERIOD_MS, XY_SH_RATE_MAX_PERIOD_MS = 2000, 20000
  local XY_SH_RATE_MAX_MULT, XY_SH_MAX_STEP, XY_SH_GLIDE_FRACTION = 4, 1.00, 1.00

  local xyLfo = {
    isRunning = false,
    phase = 0.0,
    shPhase = 1.0,
    periodMs = 3000,
    stepMs = 33,
    mode = XY_LFO_OFF,
    waveform = XY_LFO_SINE,
    depthX = 1.0,
    depthY = 1.0,
    phaseY = 0.25,
    holdOnTouch = 1,
    heldRandomX = 0.5,
    heldRandomY = 0.5,
    shFromX = 0.5,
    shFromY = 0.5,
    shToX = 0.5,
    shToY = 0.5,
    shBoundaryX = nil,
    shBoundaryY = nil,
    centerX = 0.5,
    centerY = 0.5,
    userTouching = false,
    corr = 0,
  }

  local xyLfoHandle = nil

  local function xyLfoClamp01(v)
    if v < 0 then return 0 elseif v > 1 then return 1 else return v end
  end

  local function xyLfoSmoothBezier(t)
    return t * t * (3 - 2 * t)
  end

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
      local linked = 0.5 * (rx + ry)
      if axis == "y" then
        return mix(ry, linked, xyLfo.corr)
      else
        return mix(rx, linked, xyLfo.corr)
      end
    end
    return 0.5 + 0.5 * math.sin(phase01 * 2 * math.pi)
  end

  local function xyApplyDepth(center, wave01, depth, mode)
    center = xyLfoClamp01(center)
    depth = xyLfoClamp01(depth)

    local maxPlus  = 1 - center
    local maxMinus = center

    if mode == XY_LFO_UNI_POS then
      local amp = maxPlus * depth
      return center + wave01 * amp
    elseif mode == XY_LFO_UNI_NEG then
      local amp = maxMinus * depth
      return center - wave01 * amp
    else
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
    xyLfo.mode = safeParamGet(PT_VIRTUAL, PARAM_XY_LFO_MODE, XY_LFO_OFF)
    if xyLfo.mode < XY_LFO_OFF or xyLfo.mode > XY_LFO_BIPOLAR then
      xyLfo.mode = XY_LFO_BIPOLAR
    end

    xyLfo.waveform = safeParamGet(PT_VIRTUAL, PARAM_XY_LFO_WAVE, XY_LFO_SINE)
    xyLfo.periodMs = xyLfoRateToPeriodMs(safeParamGet(PT_VIRTUAL, PARAM_XY_LFO_RATE, 0))
    xyLfo.depthX = (safeParamGet(PT_VIRTUAL, PARAM_XY_LFO_DEPTH_X, 0) / 100)
    xyLfo.depthY = (safeParamGet(PT_VIRTUAL, PARAM_XY_LFO_DEPTH_Y, 0) / 100)
    xyLfo.holdOnTouch = safeParamGet(PT_VIRTUAL, PARAM_XY_LFO_HOLD, 1)

    xyLfo.corr = (safeParamGet(PT_VIRTUAL, PARAM_XY_LFO_CORR, 0) / 100)
    if xyLfo.corr < 0 then xyLfo.corr = 0 elseif xyLfo.corr > 1 then xyLfo.corr = 1 end

    local p = safeParamGet(PT_VIRTUAL, PARAM_XY_LFO_PHASE_Y, 90)
    if p < 0 then p = 0 elseif p > PHASE_MAX then p = PHASE_MAX end
    xyLfo.phaseY = p / PHASE_MAX
  end

  local function xyLfoStart()
    xyLfoApplyParams()
    if xyLfo.mode == XY_LFO_OFF then
      xyLfo.isRunning = false
      xyLfoStopScheduler()
      return
    end
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

  local CTRL_XY_PHASE_Y = CFG.phaseYCtrl
  local CTRL_XY_RANDOM_CORR = CFG.corrCtrl
  local XY_SHARED_SLOT = 34
  local XY_SHARED_PAGE = 1

  local function updateXyWaveUi(wave)
    local phaseCtrl = safeControl(CTRL_XY_PHASE_Y)
    local corrCtrl = safeControl(CTRL_XY_RANDOM_CORR)
    if not phaseCtrl or not corrCtrl then return end

    if wave == XY_LFO_SINE then
      phaseCtrl:setSlot(XY_SHARED_SLOT, XY_SHARED_PAGE)
      phaseCtrl:setVisible(true)
      corrCtrl:setVisible(false)
    else
      corrCtrl:setSlot(XY_SHARED_SLOT, XY_SHARED_PAGE)
      corrCtrl:setVisible(true)
      phaseCtrl:setVisible(false)
    end
  end

  function initXYLfo()
    xyLfoApplyParams()
    updateXyWaveUi(xyLfo.waveform)
    if xyLfo.mode ~= XY_LFO_OFF then
      xyLfoStart()
    end
  end

  function centerXYPad()
    X = 0.5
    Y = 0.5
    xyLfo.centerX = X
    xyLfo.centerY = Y
    if xYControl then
      xYControl:repaint()
    end
  end

  function initXYPad()
    if not xYControl then
      xYControl = safeControl(CTRL_XY_PAD)
    end
    if not xYControl then
      print("XY pad control not found; init aborted")
      return
    end

    local bounds = xYControl:getBounds()
    bounds[WIDTH] = XY_WIDTH
    bounds[HEIGHT] = XY_HEIGHT
    xYControl:setBounds(bounds)
    xYControl:setPaintCallback(paintXY)
    xYControl:setTouchCallback(touchXY)

    centerXYPad()
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

  local g = graphics

  function paintXY(control, value)
    if not control then return end
    local b = control:getBounds()
    local w = b[WIDTH]
    local h = b[HEIGHT]

    g.setColor(BG); g.fillRect(0, 0, w, h)
    g.setColor(GRID); g.drawRoundRect(0, 0, w, h, 5)

    local mx = math.floor(w / 2)
    local my = math.floor(h / 2)
    g.drawLine(mx, 0, mx, h)
    g.drawLine(0, my, w, my)

    local ccx = math.floor(xyLfo.centerX * w + 0.5)
    local ccy = math.floor((1 - xyLfo.centerY) * h + 0.5)
    g.setColor(CTR)
    g.drawLine(ccx - 6, ccy, ccx + 6, ccy)
    g.drawLine(ccx, ccy - 6, ccx, ccy + 6)

    g.setColor(DOT)
    local cx = math.floor(X * w)
    local cy = math.floor((1 - Y) * h)
    g.fillCircle(cx, cy, 10)
  end

  function touchXY(control, event)
    if not control then return end

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
    if not xYControl then
      xYControl = safeControl(CTRL_XY_PAD)
    end
    if not xYControl then return end

    local xNum = safeParamGet(PT_VIRTUAL, PARAM_X_SELECT, 0)
    local yNum = safeParamGet(PT_VIRTUAL, PARAM_Y_SELECT, 1)
    local xd = PARAM_X[xNum]
    local yd = PARAM_Y[yNum]
    if not xd or not yd then return end

    local xFlip, yFlip, xCurve, yCurve = getAxisOptions()
    local xv = parameterMap.get(deviceId, xd[2], xd[1])
    local yv = parameterMap.get(deviceId, yd[2], yd[1])

    if xv ~= nil then
      X = clamp01(paramToPad(clamp01(xv / xd[3]), xFlip, xCurve))
    end
    if yv ~= nil then
      Y = clamp01(paramToPad(clamp01(yv / yd[3]), yFlip, yCurve))
    end

    xyLfo.centerX = X
    xyLfo.centerY = Y
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
    local wave = safeParamGet(PT_VIRTUAL, PARAM_XY_LFO_WAVE, XY_LFO_SINE)
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
    local cur = safeParamGet(PT_VIRTUAL, PARAM_XY_LFO_RATE, 0)
    local bump = (cur < 255) and (cur + 1) or (cur - 1)
    parameterMap.set(deviceId, PT_VIRTUAL, PARAM_XY_LFO_RATE, bump)
    parameterMap.set(deviceId, PT_VIRTUAL, PARAM_XY_LFO_RATE, cur)
  end

  function xyLfoWaveChange(valueObject, value)
    xyLfoParamChange(valueObject, value)
    updateXyWaveUi(value)
    schedule.after(1, xyRefreshRateDisplay)
  end

  -- Momentary reset: fires on press, ignores release
  function xyReset(valueObject, value)
    if value == 0 then return end

    -- stop the LFO and clear its runtime state
    xyLfoStop()
    xyLfo.phase = 0.0
    xyLfo.shPhase = 1.0
    xyLfo.heldRandomX, xyLfo.heldRandomY = 0.5, 0.5
    xyLfo.shFromX, xyLfo.shFromY = 0.5, 0.5
    xyLfo.shToX, xyLfo.shToY = 0.5, 0.5
    xyLfo.shBoundaryX, xyLfo.shBoundaryY = nil, nil
    xyLfo.userTouching = false

    -- reset all XY parameters to their defaults
    resetXYVirtualDefaults()
    xyLfoApplyParams()
    updateXyWaveUi(xyLfo.waveform)

    -- center the dot and send the centered values to the synth
    centerXYPad()
    emit()

    -- refresh the rate display, since its text depends on the waveform
    schedule.after(1, xyRefreshRateDisplay)
  end
end

-- outside the block, only expose the startup hooks
local function resetVirtualParams()
  if resetXYVirtualDefaults then
    resetXYVirtualDefaults()
  end
end

function preset.onLoad()
  resetVirtualParams()
  if initXYPad then
    initXYPad()
  end
end

function preset.onReady()
  if centerXYPad then
    centerXYPad()
  end
end
