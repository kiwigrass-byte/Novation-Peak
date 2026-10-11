-- Instruo Seashell controller v1.6
-- by kiwigrass
-- 10/09/26

-- Preset compatibility check
assert( controller.isRequired(MODEL_MK2, "5.0.0"),  "Version 5.0.0 or higher is required" )

-- a debug helper. 
local DEBUG = false

local function dprint(msg)
   if DEBUG then print(msg) end
end

local currentDevice  = devices.get(1)
local deviceId = currentDevice:getId()
local channel = currentDevice:getChannel ()
local port      = currentDevice:getPort ()

local authorDate = "kiwigrass 2026" -- populate the bottom RH screen information display on load
info.setText(authorDate)

--------- Global Constants---------------

-- number of MIDI parameters on Seashell
local PARAM_NUM = 96 

-- 7-bit profile
local MIDI_MAX = 127

-- Mod matrix first and last param numbers (0-based)
local MOD_MATRIX_FIRST_PARAM = 54
local MOD_MATRIX_LAST_PARAM = 93

-- maximum LFO frequency is C below middle C
local C3_HZ = 130.81280517578125

-- synth parameter numbers
local ENV_MODE = 21
local LFO_RATE_TYPE = 35
local RND_RATE_TYPE = 45
local SYNC_TO_LFO = 42
local LFO_RATE = 33
local RND_RATE = 43
local LFO_NOTE = 34
local RND_NOTE = 44

-- synth parameter numbers for the 4x4 mod matrix row sources and column destinations
local MOD_SOURCE_PARAM = {54, 55, 56, 57}       -- row source param numbers
local MOD_DEST_PARAM   = {58, 59, 60, 61}       -- column destination param numbers
-- synth parameter numbers for the mod matrix amount cells (row-major, 4x4)
local MOD_AMOUNT_PARAM = {62, 63, 64, 65, 66, 67, 68, 69, 70, 71, 72, 73, 74, 75, 76, 77}

-- virtual parameter numbers
local PARAM_COMPARE_IT = 10010 -- comparison of edited and patch parameter values
local SELECT_IT = 10011 -- patch selector param

-- control id numbers
local CTRL_SELECT_IT = {149,150,152} -- control patch selector 
local CTRL_COMPARE_IT = {81,83,84} -- edited/patch comparison control ids
local CTRL_LFO_RATE = 41
local CTRL_LFO_NOTE = 42
local CTRL_RND_RATE = 92
local CTRL_RND_NOTE = 93
local CTRL_DECAY_TIME = 4
local CTRL_SUSTAIN_LEVEL = 5
local CTRL_SYNC_TO_LFO = 99
local CTRL_RND_RATE_TYPE = 91

-- Generic helper for two controls where one is the inverse of the other.
local function setPairVisibility(firstControlId, secondControlId, showFirst)
  controls.get(firstControlId):setVisible(showFirst)
  controls.get(secondControlId):setVisible(not showFirst)
end

-- display/hide lfo rate and note sync
function updateLfoVisibility(valueObject, value)
  local mode = parameterMap.get(deviceId, PT_VIRTUAL, LFO_RATE_TYPE)
  local isSync = (mode == 127)
  setPairVisibility(CTRL_LFO_NOTE, CTRL_LFO_RATE, isSync)
end

-- display/hide decay time and sustain level
function showADSR(valueObject, value)
  local mode = parameterMap.get(deviceId, PT_VIRTUAL, ENV_MODE)
  local show = (mode == 64)
  controls.get(CTRL_DECAY_TIME):setVisible(show)
  controls.get(CTRL_SUSTAIN_LEVEL):setVisible(show)
end

-- display/hide random rate and random note sync
function updateRndVisibility(valueObject, value)
  local rndMode   = parameterMap.get(deviceId, PT_VIRTUAL, RND_RATE_TYPE) or 0
  local syncToLfo = (parameterMap.get(deviceId, PT_VIRTUAL, SYNC_TO_LFO) or 0) == 127
  if syncToLfo then
    -- LFO is master: hide all RND timing controls
    controls.get(CTRL_RND_RATE_TYPE):setVisible(false)
    controls.get(CTRL_RND_RATE):setVisible(false)
    controls.get(CTRL_RND_NOTE):setVisible(false)
    return
  end
  -- normal (independent) mode: show type selector and the active value control
  controls.get(CTRL_RND_RATE_TYPE):setVisible(true)
  setPairVisibility(CTRL_RND_NOTE, CTRL_RND_RATE, rndMode == 127)
end


-- value formatters --

-- MIDI values to 0 to 100%
function percent(valueObject,value) ---- 
  local displayed = 100 * value / MIDI_MAX
  return string.format ("%.0f", displayed)
end

-- MIDI values to -1 to + 1
function oscFreq(valueObject, value)
  local displayed = 2 * value / MIDI_MAX - 1
  if math.abs(displayed) < 0.01 then
    displayed = 0
  end
  return string.format("%.2f", displayed)
end

-- MIDI values to -100 to + 100
function attenuverter(valueObject,value)
  local displayed = 200 * value / MIDI_MAX - 100
  if math.abs(displayed) < 1 then
    displayed = 0
  end
  return string.format("%.0f", displayed)
end

-- MIDI values to -180 to + 180deg
function phase(valueObject,value)
  local displayed = 360 * value / MIDI_MAX - 180
  if math.abs(displayed) < 2 then
    displayed = 0
  end
  return string.format("%.1f deg", displayed)
end

-- MIDI values to lfo rate scale (0 to 130Hz)
function lfoScale(valueObject,value)
  -- scale t0 [0,1]
  local r = value/MIDI_MAX
  -- ensure median is a frequency of 5.0 
  local l = math.log(5.0 / C3_HZ) / math.log(0.5)
  -- frequency displayed
  local f = C3_HZ * r^l
  if r == 0 then
    return (string.format("%.21f Hz", 0))
  elseif r == 1 then  
    return (string.format("%.2f Hz", 131))
  else
    return (string.format("%.2f Hz", f))
  end
end

-- ── AHDSR value-in-name suffix ───────────────────────────────────────────────
-- Appends the live value of an AHDSR envelope's primary stage to its tile
-- title, e.g. "AMP ATTACK" -> "AMP ATTACK 101". 
local adsrBaseNames = {}
function adsrValueName(valueObject, value)
  local ctrl = valueObject:getControl()
  if not ctrl then return end
  local id = ctrl:getId()
  if not adsrBaseNames[id] then adsrBaseNames[id] = ctrl:getName() end
  if id ~= 5 then
    ctrl:setName(adsrBaseNames[id] .. " " .. string.format("%.1f s", (10*value/MIDI_MAX)))
  elseif id == 5 then
    ctrl:setName(adsrBaseNames[id] .. " " .. string.format("%d %%", math.floor(100*value/MIDI_MAX)))
  end
  -- print ("ctl = "..id..", base Name = "..ahdsrBaseNames[id])
end

local MOD_SOURCE = {
[0] = "None", "CV Input", "Offset", "Offset x2", "Env: Output", "Env: Gate", "Env: Active", "Env: EOC", "Gate/Trg Input", "Gat/Trg Button", "LFO: Sine", "LFO: Triangle", "LFO: Square", "LFO: Saw", "Random",
"Destination A", "Destination B", "Destination C", "Destination D", "MIDI: Pitch", "MIDI: Pitch Bd", "MIDI: Velocity", "MIDI: Pressure", "MIDI: Note On", "CC0", "CC1", "CC2", "CC3", "CC4", "CC5", "CC6",
"CC7", "CC8", "CC9", "CC10", "CC11", "CC12", "CC13", "CC14", "CC15", "CC16", "CC17", "CC18", "CC19", "CC20", "CC21", "CC22", "CC23", "CC24", "CC25", "CC26", "CC27", "CC28", "CC29", "CC30", "CC31", "CC32",
"CC33", "CC34", "CC35", "CC36", "CC37", "CC38", "CC39", "CC40", "CC41", "CC42", "CC43", "CC44", "CC45", "CC46", "CC47", "CC48", "CC49", "CC50", "CC51", "CC52", "CC53", "CC54", "CC55", "CC56", "CC57", "CC58", "CC59",
"CC60", "CC61", "CC62", "CC63", "CC64", "CC65", "CC66", "CC67", "CC68", "CC69", "CC70", "CC71", "CC72", "CC73", "CC74", "CC75", "CC76", "CC77", "CC78", "CC79", "CC80", "CC81", "CC82", "CC83", "CC84", "CC85", "CC86",
"CC87", "CC88", "CC89", "CC90", "CC91", "CC92", "CC93", "CC94", "CC95", "CC96", "CC97", "CC98", "CC99", "CC100", "CC101", "CC102", "CC103",
}

function modSource(valueObject, value)
  local idx = math.floor(tonumber(value) or -1)
  local p = MOD_SOURCE[idx]
  if p then
    return p
  end
  return "Source " .. tostring(value)
end

------------------------------------- preset parsing block ---------------------------
-- Seashell xml preset files:
local PRESETS = {
  [0] = { name = "Initial",   raw = [[
VC2!ø  <?xml version="1.0" encoding="UTF-8"?> <SeashellPreset><Version major="2" minor="0" patch="0" tweak="0"/><Parameters><PARAM id="osc1frequency" value="0.0"/><PARAM id="osc2frequency" value="0.0"/><PARAM id="lfonoff" value="0.0"/><PARAM id="octaverange" value="5.0"/><PARAM id="sync" value="0.0"/><PARAM id="1voctrouting" value="3.0"/><PARAM id="transpose" value="0.0"/><PARAM id="portamento" value="0.0"/><PARAM id="midipitchbend" value="2.0"/><PARAM id="wavefoldinput" value="0.0"/><PARAM id="folddepth" value="99.93285369873047"/><PARAM id="foldbias" value="0.0"/><PARAM id="foldbiasanimate" value="50.0"/><PARAM id="pulsewidth" value="50.0"/><PARAM id="pwmanimate" value="50.0"/><PARAM id="animateonoff" value="1.0"/><PARAM id="waveformselect" value="0.0"/><PARAM id="filtercutoff" value="99.94506072998047"/><PARAM id="filterkeytrack" value="0.0"/><PARAM id="outputlevel" value="100.0"/><PARAM id="diffuseamount" value="0.0"/><PARAM id="envmode" value="0.0"/><PARAM id="envattack" value="0.9920079708099365"/><PARAM id="envdecay" value="1.051816344261169"/><PARAM id="envsustain" value="50.0"/><PARAM id="envrelease" value="1.051816344261169"/><PARAM id="envshape" value="1.0"/><PARAM id="envgate" value="1.0"/><PARAM id="envretrigonoff" value="1.0"/><PARAM id="envtriggerbutton" value="1.0"/><PARAM id="envtriggerjack" value="1.0"/><PARAM id="envtriggernoteon" value="1.0"/><PARAM id="extend" value="0.0"/><PARAM id="lforate" value="0.4998534023761749"/><PARAM id="lforatesubdivision" value="9.0"/><PARAM id="lfotimemode" value="0.0"/><PARAM id="lfomode" value="0.0"/><PARAM id="lfopolarity" value="0.0"/><PARAM id="lfophase" value="0.0"/><PARAM id="lfotriggerbutton" value="0.0"/><PARAM id="lfotriggerjack" value="0.0"/><PARAM id="lfotriggernoteon" value="0.0"/><PARAM id="rndlforatesync" value="1.0"/><PARAM id="rndrate" value="5.000000476837158"/><PARAM id="rndratesubdivision" value="9.0"/><PARAM id="rndtimemode" value="0.0"/><PARAM id="rndpolarity" value="0.0"/><PARAM id="rnddensity" value="100.0"/><PARAM id="rndsmoothing" value="0.0"/><PARAM id="rndtriggerbutton" value="0.0"/><PARAM id="rndtriggerjack" value="0.0"/><PARAM id="rndtriggernoteon" value="0.0"/><PARAM id="taptempoenable" value="1.0"/><PARAM id="macro" value="14.78361797332764"/><PARAM id="mxsource1" value="2.0"/><PARAM id="mxsource2" value="0.0"/><PARAM id="mxsource3" value="0.0"/><PARAM id="mxsource4" value="0.0"/><PARAM id="mxdesta" value="6.0"/><PARAM id="mxdestb" value="0.0"/><PARAM id="mxdestc" value="0.0"/><PARAM id="mxdestd" value="0.0"/><PARAM id="mxnode1a" value="100.0"/><PARAM id="mxnode1b" value="0.0"/><PARAM id="mxnode1c" value="0.0"/><PARAM id="mxnode1d" value="0.0"/><PARAM id="mxnode2a" value="0.0"/><PARAM id="mxnode2b" value="0.0"/><PARAM id="mxnode2c" value="0.0"/><PARAM id="mxnode2d" value="0.0"/><PARAM id="mxnode3a" value="0.0"/><PARAM id="mxnode3b" value="0.0"/><PARAM id="mxnode3c" value="0.0"/><PARAM id="mxnode3d" value="0.0"/><PARAM id="mxnode4a" value="0.0"/><PARAM id="mxnode4b" value="0.0"/><PARAM id="mxnode4c" value="0.0"/><PARAM id="mxnode4d" value="0.0"/><PARAM id="mxnode1alock" value="0.0"/><PARAM id="mxnode1block" value="0.0"/><PARAM id="mxnode1clock" value="0.0"/><PARAM id="mxnode1dlock" value="0.0"/><PARAM id="mxnode2alock" value="0.0"/><PARAM id="mxnode2block" value="0.0"/><PARAM id="mxnode2clock" value="0.0"/><PARAM id="mxnode2dlock" value="0.0"/><PARAM id="mxnode3alock" value="0.0"/><PARAM id="mxnode3block" value="0.0"/><PARAM id="mxnode3clock" value="0.0"/><PARAM id="mxnode3dlock" value="0.0"/><PARAM id="mxnode4alock" value="0.0"/><PARAM id="mxnode4block" value="0.0"/><PARAM id="mxnode4clock" value="0.0"/><PARAM id="mxnode4dlock" value="0.0"/><PARAM id="monitormix" value="100.0"/><PARAM id="pickupbehaviour" value="0.0"/><Quantiser program="0"/></Parameters><Notes text=""/></SeashellPreset> 
]] },
  [1] = { name = "Deep Bass", raw = [[
VC2!  <?xml version="1.0" encoding="UTF-8"?> <SeashellPreset><Version major="2" minor="0" patch="0" tweak="0"/><Parameters><PARAM id="osc1frequency" value="-0.7049993276596069"/><PARAM id="osc2frequency" value="-0.4849995970726013"/><PARAM id="lfonoff" value="0.0"/><PARAM id="octaverange" value="5.0"/><PARAM id="sync" value="0.0"/><PARAM id="1voctrouting" value="3.0"/><PARAM id="transpose" value="3.0"/><PARAM id="portamento" value="0.0"/><PARAM id="midipitchbend" value="2.0"/><PARAM id="wavefoldinput" value="0.0"/><PARAM id="folddepth" value="0.0"/><PARAM id="foldbias" value="0.0"/><PARAM id="foldbiasanimate" value="50.0"/><PARAM id="pulsewidth" value="50.0"/><PARAM id="pwmanimate" value="50.0"/><PARAM id="animateonoff" value="0.0"/><PARAM id="waveformselect" value="0.0"/><PARAM id="filtercutoff" value="0.0"/><PARAM id="filterkeytrack" value="0.0"/><PARAM id="outputlevel" value="100.0"/><PARAM id="diffuseamount" value="0.0"/><PARAM id="envmode" value="1.0"/><PARAM id="envattack" value="0.002446333644911647"/><PARAM id="envdecay" value="0.5528836846351624"/><PARAM id="envsustain" value="37.75"/><PARAM id="envrelease" value="0.3658246397972107"/><PARAM id="envshape" value="1.0"/><PARAM id="envgate" value="1.0"/><PARAM id="envretrigonoff" value="1.0"/><PARAM id="envtriggerbutton" value="1.0"/><PARAM id="envtriggerjack" value="1.0"/><PARAM id="envtriggernoteon" value="1.0"/><PARAM id="extend" value="1.0"/><PARAM id="lforate" value="11.47613525390625"/><PARAM id="lforatesubdivision" value="9.0"/><PARAM id="lfotimemode" value="0.0"/><PARAM id="lfomode" value="2.0"/><PARAM id="lfopolarity" value="1.0"/><PARAM id="lfophase" value="0.0"/><PARAM id="lfotriggerbutton" value="0.0"/><PARAM id="lfotriggerjack" value="0.0"/><PARAM id="lfotriggernoteon" value="1.0"/><PARAM id="rndlforatesync" value="1.0"/><PARAM id="rndrate" value="5.000000476837158"/><PARAM id="rndratesubdivision" value="9.0"/><PARAM id="rndtimemode" value="0.0"/><PARAM id="rndpolarity" value="0.0"/><PARAM id="rnddensity" value="100.0"/><PARAM id="rndsmoothing" value="0.0"/><PARAM id="rndtriggerbutton" value="0.0"/><PARAM id="rndtriggerjack" value="0.0"/><PARAM id="rndtriggernoteon" value="0.0"/><PARAM id="taptempoenable" value="1.0"/><PARAM id="macro" value="99.993896484375"/><PARAM id="mxsource1" value="4.0"/><PARAM id="mxsource2" value="13.0"/><PARAM id="mxsource3" value="0.0"/><PARAM id="mxsource4" value="0.0"/><PARAM id="mxdesta" value="3.0"/><PARAM id="mxdestb" value="9.0"/><PARAM id="mxdestc" value="0.0"/><PARAM id="mxdestd" value="0.0"/><PARAM id="mxnode1a" value="25.5001220703125"/><PARAM id="mxnode1b" value="0.0"/><PARAM id="mxnode1c" value="0.0"/><PARAM id="mxnode1d" value="0.0"/><PARAM id="mxnode2a" value="0.0"/><PARAM id="mxnode2b" value="21.00003814697266"/><PARAM id="mxnode2c" value="0.0"/><PARAM id="mxnode2d" value="0.0"/><PARAM id="mxnode3a" value="0.0"/><PARAM id="mxnode3b" value="0.0"/><PARAM id="mxnode3c" value="0.0"/><PARAM id="mxnode3d" value="0.0"/><PARAM id="mxnode4a" value="0.0"/><PARAM id="mxnode4b" value="0.0"/><PARAM id="mxnode4c" value="0.0"/><PARAM id="mxnode4d" value="0.0"/><PARAM id="mxnode1alock" value="0.0"/><PARAM id="mxnode1block" value="0.0"/><PARAM id="mxnode1clock" value="0.0"/><PARAM id="mxnode1dlock" value="0.0"/><PARAM id="mxnode2alock" value="0.0"/><PARAM id="mxnode2block" value="0.0"/><PARAM id="mxnode2clock" value="0.0"/><PARAM id="mxnode2dlock" value="0.0"/><PARAM id="mxnode3alock" value="0.0"/><PARAM id="mxnode3block" value="0.0"/><PARAM id="mxnode3clock" value="0.0"/><PARAM id="mxnode3dlock" value="0.0"/><PARAM id="mxnode4alock" value="0.0"/><PARAM id="mxnode4block" value="0.0"/><PARAM id="mxnode4clock" value="0.0"/><PARAM id="mxnode4dlock" value="0.0"/><PARAM id="monitormix" value="100.0"/><PARAM id="pickupbehaviour" value="0.0"/><Quantiser program="0"/></Parameters><Notes text=""/></SeashellPreset> 
]] },
  [2] = { name = "Ow Bass",   raw = [[
VC2!  <?xml version="1.0" encoding="UTF-8"?> <SeashellPreset><Version major="2" minor="0" patch="0" tweak="0"/><Parameters><PARAM id="osc1frequency" value="0.0"/><PARAM id="osc2frequency" value="-0.5499997138977051"/><PARAM id="lfonoff" value="0.0"/><PARAM id="octaverange" value="5.0"/><PARAM id="sync" value="0.0"/><PARAM id="1voctrouting" value="3.0"/><PARAM id="transpose" value="2.0"/><PARAM id="portamento" value="0.0"/><PARAM id="midipitchbend" value="2.0"/><PARAM id="wavefoldinput" value="0.0"/><PARAM id="folddepth" value="0.2685710787773132"/><PARAM id="foldbias" value="0.0"/><PARAM id="foldbiasanimate" value="0.4211682677268982"/><PARAM id="pulsewidth" value="50.0"/><PARAM id="pwmanimate" value="0.4211682677268982"/><PARAM id="animateonoff" value="0.0"/><PARAM id="waveformselect" value="7.0"/><PARAM id="filtercutoff" value="12.42141246795654"/><PARAM id="filterkeytrack" value="0.0"/><PARAM id="outputlevel" value="100.0"/><PARAM id="diffuseamount" value="3.25"/><PARAM id="envmode" value="0.0"/><PARAM id="envattack" value="0.0"/><PARAM id="envdecay" value="0.0"/><PARAM id="envsustain" value="100.0"/><PARAM id="envrelease" value="0.470175176858902"/><PARAM id="envshape" value="1.0"/><PARAM id="envgate" value="1.0"/><PARAM id="envretrigonoff" value="1.0"/><PARAM id="envtriggerbutton" value="1.0"/><PARAM id="envtriggerjack" value="1.0"/><PARAM id="envtriggernoteon" value="1.0"/><PARAM id="extend" value="1.0"/><PARAM id="lforate" value="14.1532735824585"/><PARAM id="lforatesubdivision" value="9.0"/><PARAM id="lfotimemode" value="0.0"/><PARAM id="lfomode" value="0.0"/><PARAM id="lfopolarity" value="1.0"/><PARAM id="lfophase" value="0.0"/><PARAM id="lfotriggerbutton" value="0.0"/><PARAM id="lfotriggerjack" value="0.0"/><PARAM id="lfotriggernoteon" value="1.0"/><PARAM id="rndlforatesync" value="1.0"/><PARAM id="rndrate" value="5.000000476837158"/><PARAM id="rndratesubdivision" value="9.0"/><PARAM id="rndtimemode" value="0.0"/><PARAM id="rndpolarity" value="0.0"/><PARAM id="rnddensity" value="100.0"/><PARAM id="rndsmoothing" value="0.0"/><PARAM id="rndtriggerbutton" value="0.0"/><PARAM id="rndtriggerjack" value="0.0"/><PARAM id="rndtriggernoteon" value="0.0"/><PARAM id="taptempoenable" value="1.0"/><PARAM id="macro" value="99.96337890625"/><PARAM id="mxsource1" value="4.0"/><PARAM id="mxsource2" value="0.0"/><PARAM id="mxsource3" value="0.0"/><PARAM id="mxsource4" value="0.0"/><PARAM id="mxdesta" value="3.0"/><PARAM id="mxdestb" value="0.0"/><PARAM id="mxdestc" value="0.0"/><PARAM id="mxdestd" value="0.0"/><PARAM id="mxnode1a" value="33.50001525878906"/><PARAM id="mxnode1b" value="0.0"/><PARAM id="mxnode1c" value="0.0"/><PARAM id="mxnode1d" value="0.0"/><PARAM id="mxnode2a" value="0.0"/><PARAM id="mxnode2b" value="0.0"/><PARAM id="mxnode2c" value="0.0"/><PARAM id="mxnode2d" value="0.0"/><PARAM id="mxnode3a" value="0.0"/><PARAM id="mxnode3b" value="0.0"/><PARAM id="mxnode3c" value="0.0"/><PARAM id="mxnode3d" value="0.0"/><PARAM id="mxnode4a" value="0.0"/><PARAM id="mxnode4b" value="0.0"/><PARAM id="mxnode4c" value="0.0"/><PARAM id="mxnode4d" value="0.0"/><PARAM id="mxnode1alock" value="0.0"/><PARAM id="mxnode1block" value="0.0"/><PARAM id="mxnode1clock" value="0.0"/><PARAM id="mxnode1dlock" value="0.0"/><PARAM id="mxnode2alock" value="0.0"/><PARAM id="mxnode2block" value="0.0"/><PARAM id="mxnode2clock" value="0.0"/><PARAM id="mxnode2dlock" value="0.0"/><PARAM id="mxnode3alock" value="0.0"/><PARAM id="mxnode3block" value="0.0"/><PARAM id="mxnode3clock" value="0.0"/><PARAM id="mxnode3dlock" value="0.0"/><PARAM id="mxnode4alock" value="0.0"/><PARAM id="mxnode4block" value="0.0"/><PARAM id="mxnode4clock" value="0.0"/><PARAM id="mxnode4dlock" value="0.0"/><PARAM id="monitormix" value="100.0"/><PARAM id="pickupbehaviour" value="0.0"/><Quantiser program="0"/></Parameters><Notes text=""/></SeashellPreset> 
]] },
  [3] = { name = "Uber Drone",  raw = [[
VC2!\  <?xml version="1.0" encoding="UTF-8"?> <SeashellPreset><Version major="2" minor="0" patch="0" tweak="0"/><Parameters><PARAM id="osc1frequency" value="-0.2710000276565552"/><PARAM id="osc2frequency" value="-0.2249997854232788"/><PARAM id="lfonoff" value="0.0"/><PARAM id="octaverange" value="5.0"/><PARAM id="sync" value="0.0"/><PARAM id="1voctrouting" value="3.0"/><PARAM id="transpose" value="3.0"/><PARAM id="portamento" value="0.0"/><PARAM id="midipitchbend" value="2.0"/><PARAM id="wavefoldinput" value="0.0"/><PARAM id="folddepth" value="50.75382995605469"/><PARAM id="foldbias" value="50.0"/><PARAM id="foldbiasanimate" value="100.0"/><PARAM id="pulsewidth" value="50.0"/><PARAM id="pwmanimate" value="100.0"/><PARAM id="animateonoff" value="1.0"/><PARAM id="waveformselect" value="0.0"/><PARAM id="filtercutoff" value="50.06409454345703"/><PARAM id="filterkeytrack" value="0.0"/><PARAM id="outputlevel" value="100.0"/><PARAM id="diffuseamount" value="100.0"/><PARAM id="envmode" value="2.0"/><PARAM id="envattack" value="9.945338249206543"/><PARAM id="envdecay" value="9.945338249206543"/><PARAM id="envsustain" value="50.0"/><PARAM id="envrelease" value="9.945338249206543"/><PARAM id="envshape" value="0.0"/><PARAM id="envgate" value="1.0"/><PARAM id="envretrigonoff" value="1.0"/><PARAM id="envtriggerbutton" value="1.0"/><PARAM id="envtriggerjack" value="1.0"/><PARAM id="envtriggernoteon" value="1.0"/><PARAM id="extend" value="1.0"/><PARAM id="lforate" value="0.1001115441322327"/><PARAM id="lforatesubdivision" value="9.0"/><PARAM id="lfotimemode" value="0.0"/><PARAM id="lfomode" value="0.0"/><PARAM id="lfopolarity" value="0.0"/><PARAM id="lfophase" value="0.0"/><PARAM id="lfotriggerbutton" value="0.0"/><PARAM id="lfotriggerjack" value="0.0"/><PARAM id="lfotriggernoteon" value="0.0"/><PARAM id="rndlforatesync" value="1.0"/><PARAM id="rndrate" value="5.000000476837158"/><PARAM id="rndratesubdivision" value="9.0"/><PARAM id="rndtimemode" value="0.0"/><PARAM id="rndpolarity" value="0.0"/><PARAM id="rnddensity" value="100.0"/><PARAM id="rndsmoothing" value="0.0"/><PARAM id="rndtriggerbutton" value="0.0"/><PARAM id="rndtriggerjack" value="0.0"/><PARAM id="rndtriggernoteon" value="0.0"/><PARAM id="taptempoenable" value="1.0"/><PARAM id="macro" value="100.0"/><PARAM id="mxsource1" value="10.0"/><PARAM id="mxsource2" value="4.0"/><PARAM id="mxsource3" value="0.0"/><PARAM id="mxsource4" value="0.0"/><PARAM id="mxdesta" value="7.0"/><PARAM id="mxdestb" value="8.0"/><PARAM id="mxdestc" value="9.0"/><PARAM id="mxdestd" value="3.0"/><PARAM id="mxnode1a" value="14.99998474121094"/><PARAM id="mxnode1b" value="-36.0"/><PARAM id="mxnode1c" value="-17.0"/><PARAM id="mxnode1d" value="-12.0"/><PARAM id="mxnode2a" value="-13.70000457763672"/><PARAM id="mxnode2b" value="36.49996948242188"/><PARAM id="mxnode2c" value="18.99998474121094"/><PARAM id="mxnode2d" value="12.49998474121094"/><PARAM id="mxnode3a" value="0.0"/><PARAM id="mxnode3b" value="0.0"/><PARAM id="mxnode3c" value="0.0"/><PARAM id="mxnode3d" value="0.0"/><PARAM id="mxnode4a" value="0.0"/><PARAM id="mxnode4b" value="0.0"/><PARAM id="mxnode4c" value="0.0"/><PARAM id="mxnode4d" value="0.0"/><PARAM id="mxnode1alock" value="0.0"/><PARAM id="mxnode1block" value="0.0"/><PARAM id="mxnode1clock" value="0.0"/><PARAM id="mxnode1dlock" value="0.0"/><PARAM id="mxnode2alock" value="0.0"/><PARAM id="mxnode2block" value="0.0"/><PARAM id="mxnode2clock" value="0.0"/><PARAM id="mxnode2dlock" value="0.0"/><PARAM id="mxnode3alock" value="0.0"/><PARAM id="mxnode3block" value="0.0"/><PARAM id="mxnode3clock" value="0.0"/><PARAM id="mxnode3dlock" value="0.0"/><PARAM id="mxnode4alock" value="0.0"/><PARAM id="mxnode4block" value="0.0"/><PARAM id="mxnode4clock" value="0.0"/><PARAM id="mxnode4dlock" value="0.0"/><PARAM id="monitormix" value="100.0"/><PARAM id="pickupbehaviour" value="0.0"/><Quantiser program="0"/></Parameters><Notes text=""/></SeashellPreset> 
]] },
  [4] = { name = "Wub Wub",   raw = [[
VC2!H  <?xml version="1.0" encoding="UTF-8"?> <SeashellPreset><Version major="2" minor="0" patch="0" tweak="0"/><Parameters><PARAM id="osc1frequency" value="-0.184733510017395"/><PARAM id="osc2frequency" value="-0.3049997091293335"/><PARAM id="lfonoff" value="0.0"/><PARAM id="octaverange" value="5.0"/><PARAM id="sync" value="1.0"/><PARAM id="1voctrouting" value="3.0"/><PARAM id="transpose" value="3.0"/><PARAM id="portamento" value="0.0"/><PARAM id="midipitchbend" value="2.0"/><PARAM id="wavefoldinput" value="0.0"/><PARAM id="folddepth" value="0.1342855393886566"/><PARAM id="foldbias" value="0.0"/><PARAM id="foldbiasanimate" value="50.0"/><PARAM id="pulsewidth" value="50.0"/><PARAM id="pwmanimate" value="50.0"/><PARAM id="animateonoff" value="1.0"/><PARAM id="waveformselect" value="0.0"/><PARAM id="filtercutoff" value="6.757004737854004"/><PARAM id="filterkeytrack" value="0.0"/><PARAM id="outputlevel" value="100.0"/><PARAM id="diffuseamount" value="16.00000381469727"/><PARAM id="envmode" value="1.0"/><PARAM id="envattack" value="0.001425864058546722"/><PARAM id="envdecay" value="0.7438417077064514"/><PARAM id="envsustain" value="50.0"/><PARAM id="envrelease" value="0.7438417077064514"/><PARAM id="envshape" value="1.0"/><PARAM id="envgate" value="1.0"/><PARAM id="envretrigonoff" value="1.0"/><PARAM id="envtriggerbutton" value="1.0"/><PARAM id="envtriggerjack" value="1.0"/><PARAM id="envtriggernoteon" value="1.0"/><PARAM id="extend" value="1.0"/><PARAM id="lforate" value="3.916121006011963"/><PARAM id="lforatesubdivision" value="12.0"/><PARAM id="lfotimemode" value="0.0"/><PARAM id="lfomode" value="0.0"/><PARAM id="lfopolarity" value="1.0"/><PARAM id="lfophase" value="0.0"/><PARAM id="lfotriggerbutton" value="1.0"/><PARAM id="lfotriggerjack" value="1.0"/><PARAM id="lfotriggernoteon" value="1.0"/><PARAM id="rndlforatesync" value="1.0"/><PARAM id="rndrate" value="5.000000476837158"/><PARAM id="rndratesubdivision" value="9.0"/><PARAM id="rndtimemode" value="0.0"/><PARAM id="rndpolarity" value="0.0"/><PARAM id="rnddensity" value="100.0"/><PARAM id="rndsmoothing" value="0.0"/><PARAM id="rndtriggerbutton" value="0.0"/><PARAM id="rndtriggerjack" value="0.0"/><PARAM id="rndtriggernoteon" value="0.0"/><PARAM id="taptempoenable" value="1.0"/><PARAM id="macro" value="41.23176193237305"/><PARAM id="mxsource1" value="10.0"/><PARAM id="mxsource2" value="2.0"/><PARAM id="mxsource3" value="0.0"/><PARAM id="mxsource4" value="0.0"/><PARAM id="mxdesta" value="3.0"/><PARAM id="mxdestb" value="9.0"/><PARAM id="mxdestc" value="7.0"/><PARAM id="mxdestd" value="25.0"/><PARAM id="mxnode1a" value="66.5"/><PARAM id="mxnode1b" value="28.99996948242188"/><PARAM id="mxnode1c" value="75.5"/><PARAM id="mxnode1d" value="0.0"/><PARAM id="mxnode2a" value="0.0"/><PARAM id="mxnode2b" value="0.0"/><PARAM id="mxnode2c" value="0.0"/><PARAM id="mxnode2d" value="22.49997711181641"/><PARAM id="mxnode3a" value="0.0"/><PARAM id="mxnode3b" value="0.0"/><PARAM id="mxnode3c" value="0.0"/><PARAM id="mxnode3d" value="0.0"/><PARAM id="mxnode4a" value="0.0"/><PARAM id="mxnode4b" value="0.0"/><PARAM id="mxnode4c" value="0.0"/><PARAM id="mxnode4d" value="0.0"/><PARAM id="mxnode1alock" value="0.0"/><PARAM id="mxnode1block" value="0.0"/><PARAM id="mxnode1clock" value="0.0"/><PARAM id="mxnode1dlock" value="0.0"/><PARAM id="mxnode2alock" value="0.0"/><PARAM id="mxnode2block" value="0.0"/><PARAM id="mxnode2clock" value="0.0"/><PARAM id="mxnode2dlock" value="0.0"/><PARAM id="mxnode3alock" value="0.0"/><PARAM id="mxnode3block" value="0.0"/><PARAM id="mxnode3clock" value="0.0"/><PARAM id="mxnode3dlock" value="0.0"/><PARAM id="mxnode4alock" value="0.0"/><PARAM id="mxnode4block" value="0.0"/><PARAM id="mxnode4clock" value="0.0"/><PARAM id="mxnode4dlock" value="0.0"/><PARAM id="monitormix" value="100.0"/><PARAM id="pickupbehaviour" value="0.0"/><Quantiser program="0"/></Parameters><Notes text=""/></SeashellPreset> 
]] },
  [5] = { name = "Apocolypse Strings", raw = [[
VC2!  <?xml version="1.0" encoding="UTF-8"?> <SeashellPreset><Version major="2" minor="0" patch="0" tweak="0"/><Parameters><PARAM id="osc1frequency" value="0.4000005722045898"/><PARAM id="osc2frequency" value="0.0"/><PARAM id="lfonoff" value="0.0"/><PARAM id="octaverange" value="5.0"/><PARAM id="sync" value="0.0"/><PARAM id="1voctrouting" value="3.0"/><PARAM id="transpose" value="0.0"/><PARAM id="portamento" value="0.0"/><PARAM id="midipitchbend" value="2.0"/><PARAM id="wavefoldinput" value="0.0"/><PARAM id="folddepth" value="0.0"/><PARAM id="foldbias" value="0.0"/><PARAM id="foldbiasanimate" value="0.0"/><PARAM id="pulsewidth" value="50.0"/><PARAM id="pwmanimate" value="50.0"/><PARAM id="animateonoff" value="1.0"/><PARAM id="waveformselect" value="3.0"/><PARAM id="filtercutoff" value="75.55393218994141"/><PARAM id="filterkeytrack" value="65.50013732910156"/><PARAM id="outputlevel" value="100.0"/><PARAM id="diffuseamount" value="31.2499828338623"/><PARAM id="envmode" value="1.0"/><PARAM id="envattack" value="1.513456463813782"/><PARAM id="envdecay" value="0.0"/><PARAM id="envsustain" value="100.0"/><PARAM id="envrelease" value="1.366572618484497"/><PARAM id="envshape" value="1.0"/><PARAM id="envgate" value="1.0"/><PARAM id="envretrigonoff" value="1.0"/><PARAM id="envtriggerbutton" value="1.0"/><PARAM id="envtriggerjack" value="1.0"/><PARAM id="envtriggernoteon" value="1.0"/><PARAM id="extend" value="1.0"/><PARAM id="lforate" value="1.999995112419128"/><PARAM id="lforatesubdivision" value="9.0"/><PARAM id="lfotimemode" value="0.0"/><PARAM id="lfomode" value="0.0"/><PARAM id="lfopolarity" value="0.0"/><PARAM id="lfophase" value="0.0"/><PARAM id="lfotriggerbutton" value="1.0"/><PARAM id="lfotriggerjack" value="1.0"/><PARAM id="lfotriggernoteon" value="1.0"/><PARAM id="rndlforatesync" value="1.0"/><PARAM id="rndrate" value="5.000000476837158"/><PARAM id="rndratesubdivision" value="9.0"/><PARAM id="rndtimemode" value="0.0"/><PARAM id="rndpolarity" value="0.0"/><PARAM id="rnddensity" value="100.0"/><PARAM id="rndsmoothing" value="0.0"/><PARAM id="rndtriggerbutton" value="0.0"/><PARAM id="rndtriggerjack" value="0.0"/><PARAM id="rndtriggernoteon" value="0.0"/><PARAM id="taptempoenable" value="1.0"/><PARAM id="macro" value="100.0"/><PARAM id="mxsource1" value="4.0"/><PARAM id="mxsource2" value="10.0"/><PARAM id="mxsource3" value="0.0"/><PARAM id="mxsource4" value="0.0"/><PARAM id="mxdesta" value="3.0"/><PARAM id="mxdestb" value="9.0"/><PARAM id="mxdestc" value="10.0"/><PARAM id="mxdestd" value="6.0"/><PARAM id="mxnode1a" value="30.49996948242188"/><PARAM id="mxnode1b" value="0.0"/><PARAM id="mxnode1c" value="0.0"/><PARAM id="mxnode1d" value="80.5"/><PARAM id="mxnode2a" value="0.0"/><PARAM id="mxnode2b" value="5.999992370605469"/><PARAM id="mxnode2c" value="1.5"/><PARAM id="mxnode2d" value="0.0"/><PARAM id="mxnode3a" value="0.0"/><PARAM id="mxnode3b" value="0.0"/><PARAM id="mxnode3c" value="0.0"/><PARAM id="mxnode3d" value="0.0"/><PARAM id="mxnode4a" value="0.0"/><PARAM id="mxnode4b" value="0.0"/><PARAM id="mxnode4c" value="0.0"/><PARAM id="mxnode4d" value="0.0"/><PARAM id="mxnode1alock" value="0.0"/><PARAM id="mxnode1block" value="0.0"/><PARAM id="mxnode1clock" value="0.0"/><PARAM id="mxnode1dlock" value="0.0"/><PARAM id="mxnode2alock" value="0.0"/><PARAM id="mxnode2block" value="0.0"/><PARAM id="mxnode2clock" value="0.0"/><PARAM id="mxnode2dlock" value="0.0"/><PARAM id="mxnode3alock" value="0.0"/><PARAM id="mxnode3block" value="0.0"/><PARAM id="mxnode3clock" value="0.0"/><PARAM id="mxnode3dlock" value="0.0"/><PARAM id="mxnode4alock" value="0.0"/><PARAM id="mxnode4block" value="0.0"/><PARAM id="mxnode4clock" value="0.0"/><PARAM id="mxnode4dlock" value="0.0"/><PARAM id="monitormix" value="100.0"/><PARAM id="pickupbehaviour" value="0.0"/><Quantiser program="0"/></Parameters><Notes text=""/></SeashellPreset> 
]] },
  [6] = { name = "Boards of Fanada", raw = [[
VC2!J  <?xml version="1.0" encoding="UTF-8"?> <SeashellPreset><Version major="2" minor="0" patch="0" tweak="0"/><Parameters><PARAM id="osc1frequency" value="0.3426111936569214"/><PARAM id="osc2frequency" value="-0.1229933500289917"/><PARAM id="lfonoff" value="0.0"/><PARAM id="octaverange" value="5.0"/><PARAM id="sync" value="0.0"/><PARAM id="1voctrouting" value="3.0"/><PARAM id="transpose" value="3.0"/><PARAM id="portamento" value="0.0"/><PARAM id="midipitchbend" value="2.0"/><PARAM id="wavefoldinput" value="0.0"/><PARAM id="folddepth" value="0.25"/><PARAM id="foldbias" value="0.0"/><PARAM id="foldbiasanimate" value="0.0"/><PARAM id="pulsewidth" value="99.75"/><PARAM id="pwmanimate" value="100.0"/><PARAM id="animateonoff" value="1.0"/><PARAM id="waveformselect" value="3.0"/><PARAM id="filtercutoff" value="65.35433197021484"/><PARAM id="filterkeytrack" value="-71.5"/><PARAM id="outputlevel" value="100.0"/><PARAM id="diffuseamount" value="83.0"/><PARAM id="envmode" value="1.0"/><PARAM id="envattack" value="0.1889340728521347"/><PARAM id="envdecay" value="9.789768218994141"/><PARAM id="envsustain" value="50.0"/><PARAM id="envrelease" value="9.789768218994141"/><PARAM id="envshape" value="0.0"/><PARAM id="envgate" value="1.0"/><PARAM id="envretrigonoff" value="1.0"/><PARAM id="envtriggerbutton" value="1.0"/><PARAM id="envtriggerjack" value="1.0"/><PARAM id="envtriggernoteon" value="1.0"/><PARAM id="extend" value="1.0"/><PARAM id="lforate" value="0.5445027947425842"/><PARAM id="lforatesubdivision" value="9.0"/><PARAM id="lfotimemode" value="0.0"/><PARAM id="lfomode" value="1.0"/><PARAM id="lfopolarity" value="0.0"/><PARAM id="lfophase" value="0.0"/><PARAM id="lfotriggerbutton" value="0.0"/><PARAM id="lfotriggerjack" value="0.0"/><PARAM id="lfotriggernoteon" value="1.0"/><PARAM id="rndlforatesync" value="1.0"/><PARAM id="rndrate" value="5.000000476837158"/><PARAM id="rndratesubdivision" value="9.0"/><PARAM id="rndtimemode" value="0.0"/><PARAM id="rndpolarity" value="0.0"/><PARAM id="rnddensity" value="100.0"/><PARAM id="rndsmoothing" value="0.0"/><PARAM id="rndtriggerbutton" value="0.0"/><PARAM id="rndtriggerjack" value="0.0"/><PARAM id="rndtriggernoteon" value="0.0"/><PARAM id="taptempoenable" value="1.0"/><PARAM id="macro" value="99.81687927246094"/><PARAM id="mxsource1" value="10.0"/><PARAM id="mxsource2" value="19.0"/><PARAM id="mxsource3" value="0.0"/><PARAM id="mxsource4" value="0.0"/><PARAM id="mxdesta" value="13.0"/><PARAM id="mxdestb" value="16.0"/><PARAM id="mxdestc" value="2.0"/><PARAM id="mxdestd" value="3.0"/><PARAM id="mxnode1a" value="-2.000015258789062"/><PARAM id="mxnode1b" value="0.0"/><PARAM id="mxnode1c" value="10.50007629394531"/><PARAM id="mxnode1d" value="-9.999954223632812"/><PARAM id="mxnode2a" value="0.0"/><PARAM id="mxnode2b" value="3.000007629394531"/><PARAM id="mxnode2c" value="0.0"/><PARAM id="mxnode2d" value="0.0"/><PARAM id="mxnode3a" value="0.0"/><PARAM id="mxnode3b" value="0.0"/><PARAM id="mxnode3c" value="0.0"/><PARAM id="mxnode3d" value="0.0"/><PARAM id="mxnode4a" value="0.0"/><PARAM id="mxnode4b" value="0.0"/><PARAM id="mxnode4c" value="0.0"/><PARAM id="mxnode4d" value="0.0"/><PARAM id="mxnode1alock" value="0.0"/><PARAM id="mxnode1block" value="0.0"/><PARAM id="mxnode1clock" value="0.0"/><PARAM id="mxnode1dlock" value="0.0"/><PARAM id="mxnode2alock" value="0.0"/><PARAM id="mxnode2block" value="0.0"/><PARAM id="mxnode2clock" value="0.0"/><PARAM id="mxnode2dlock" value="0.0"/><PARAM id="mxnode3alock" value="0.0"/><PARAM id="mxnode3block" value="0.0"/><PARAM id="mxnode3clock" value="0.0"/><PARAM id="mxnode3dlock" value="0.0"/><PARAM id="mxnode4alock" value="0.0"/><PARAM id="mxnode4block" value="0.0"/><PARAM id="mxnode4clock" value="0.0"/><PARAM id="mxnode4dlock" value="0.0"/><PARAM id="monitormix" value="100.0"/><PARAM id="pickupbehaviour" value="0.0"/><Quantiser program="0"/></Parameters><Notes text=""/></SeashellPreset> 
]] },
  [7] = { name = "Buzz Saw", raw = [[
VC2!:  <?xml version="1.0" encoding="UTF-8"?> <SeashellPreset><Version major="2" minor="0" patch="0" tweak="0"/><Parameters><PARAM id="osc1frequency" value="-0.0549999475479126"/><PARAM id="osc2frequency" value="-0.04499995708465576"/><PARAM id="lfonoff" value="0.0"/><PARAM id="octaverange" value="5.0"/><PARAM id="sync" value="1.0"/><PARAM id="1voctrouting" value="3.0"/><PARAM id="transpose" value="3.0"/><PARAM id="portamento" value="0.0"/><PARAM id="midipitchbend" value="2.0"/><PARAM id="wavefoldinput" value="0.0"/><PARAM id="folddepth" value="0.2624672055244446"/><PARAM id="foldbias" value="0.0"/><PARAM id="foldbiasanimate" value="50.0"/><PARAM id="pulsewidth" value="50.0"/><PARAM id="pwmanimate" value="50.0"/><PARAM id="animateonoff" value="0.0"/><PARAM id="waveformselect" value="1.0"/><PARAM id="filtercutoff" value="7.275834560394287"/><PARAM id="filterkeytrack" value="0.0"/><PARAM id="outputlevel" value="100.0"/><PARAM id="diffuseamount" value="0.0"/><PARAM id="envmode" value="1.0"/><PARAM id="envattack" value="0.002854987047612667"/><PARAM id="envdecay" value="1.440206408500671"/><PARAM id="envsustain" value="50.0"/><PARAM id="envrelease" value="1.440206408500671"/><PARAM id="envshape" value="1.0"/><PARAM id="envgate" value="1.0"/><PARAM id="envretrigonoff" value="1.0"/><PARAM id="envtriggerbutton" value="1.0"/><PARAM id="envtriggerjack" value="1.0"/><PARAM id="envtriggernoteon" value="1.0"/><PARAM id="extend" value="1.0"/><PARAM id="lforate" value="3.580113172531128"/><PARAM id="lforatesubdivision" value="9.0"/><PARAM id="lfotimemode" value="0.0"/><PARAM id="lfomode" value="0.0"/><PARAM id="lfopolarity" value="0.0"/><PARAM id="lfophase" value="0.0"/><PARAM id="lfotriggerbutton" value="0.0"/><PARAM id="lfotriggerjack" value="0.0"/><PARAM id="lfotriggernoteon" value="0.0"/><PARAM id="rndlforatesync" value="1.0"/><PARAM id="rndrate" value="5.000000476837158"/><PARAM id="rndratesubdivision" value="9.0"/><PARAM id="rndtimemode" value="0.0"/><PARAM id="rndpolarity" value="0.0"/><PARAM id="rnddensity" value="100.0"/><PARAM id="rndsmoothing" value="0.0"/><PARAM id="rndtriggerbutton" value="0.0"/><PARAM id="rndtriggerjack" value="0.0"/><PARAM id="rndtriggernoteon" value="0.0"/><PARAM id="taptempoenable" value="1.0"/><PARAM id="macro" value="100.0"/><PARAM id="mxsource1" value="4.0"/><PARAM id="mxsource2" value="11.0"/><PARAM id="mxsource3" value="0.0"/><PARAM id="mxsource4" value="0.0"/><PARAM id="mxdesta" value="14.0"/><PARAM id="mxdestb" value="13.0"/><PARAM id="mxdestc" value="3.0"/><PARAM id="mxdestd" value="0.0"/><PARAM id="mxnode1a" value="25.99997711181641"/><PARAM id="mxnode1b" value="0.0"/><PARAM id="mxnode1c" value="34.49996948242188"/><PARAM id="mxnode1d" value="0.0"/><PARAM id="mxnode2a" value="0.0"/><PARAM id="mxnode2b" value="4.499992370605469"/><PARAM id="mxnode2c" value="0.0"/><PARAM id="mxnode2d" value="0.0"/><PARAM id="mxnode3a" value="0.0"/><PARAM id="mxnode3b" value="0.0"/><PARAM id="mxnode3c" value="0.0"/><PARAM id="mxnode3d" value="0.0"/><PARAM id="mxnode4a" value="0.0"/><PARAM id="mxnode4b" value="0.0"/><PARAM id="mxnode4c" value="0.0"/><PARAM id="mxnode4d" value="0.0"/><PARAM id="mxnode1alock" value="0.0"/><PARAM id="mxnode1block" value="0.0"/><PARAM id="mxnode1clock" value="0.0"/><PARAM id="mxnode1dlock" value="0.0"/><PARAM id="mxnode2alock" value="0.0"/><PARAM id="mxnode2block" value="0.0"/><PARAM id="mxnode2clock" value="0.0"/><PARAM id="mxnode2dlock" value="0.0"/><PARAM id="mxnode3alock" value="0.0"/><PARAM id="mxnode3block" value="0.0"/><PARAM id="mxnode3clock" value="0.0"/><PARAM id="mxnode3dlock" value="0.0"/><PARAM id="mxnode4alock" value="0.0"/><PARAM id="mxnode4block" value="0.0"/><PARAM id="mxnode4clock" value="0.0"/><PARAM id="mxnode4dlock" value="0.0"/><PARAM id="monitormix" value="100.0"/><PARAM id="pickupbehaviour" value="0.0"/><Quantiser program="0"/></Parameters><Notes text=""/></SeashellPreset> 
]] },
  [8] = { name = "Sad String", raw = [[
VC2!c  <?xml version="1.0" encoding="UTF-8"?> <SeashellPreset><Version major="2" minor="0" patch="0" tweak="0"/><Parameters><PARAM id="osc1frequency" value="0.2371358871459961"/><PARAM id="osc2frequency" value="0.0"/><PARAM id="lfonoff" value="0.0"/><PARAM id="octaverange" value="5.0"/><PARAM id="sync" value="0.0"/><PARAM id="1voctrouting" value="3.0"/><PARAM id="transpose" value="1.0"/><PARAM id="portamento" value="0.0"/><PARAM id="midipitchbend" value="2.0"/><PARAM id="wavefoldinput" value="0.0"/><PARAM id="folddepth" value="0.2502593994140625"/><PARAM id="foldbias" value="0.0"/><PARAM id="foldbiasanimate" value="0.4211682677268982"/><PARAM id="pulsewidth" value="50.0"/><PARAM id="pwmanimate" value="0.4211682677268982"/><PARAM id="animateonoff" value="0.0"/><PARAM id="waveformselect" value="1.0"/><PARAM id="filtercutoff" value="50.79474639892578"/><PARAM id="filterkeytrack" value="40.99996948242188"/><PARAM id="outputlevel" value="0.0"/><PARAM id="diffuseamount" value="100.0"/><PARAM id="envmode" value="1.0"/><PARAM id="envattack" value="3.047772169113159"/><PARAM id="envdecay" value="0.4765294790267944"/><PARAM id="envsustain" value="100.0"/><PARAM id="envrelease" value="0.3861320912837982"/><PARAM id="envshape" value="1.0"/><PARAM id="envgate" value="0.0"/><PARAM id="envretrigonoff" value="1.0"/><PARAM id="envtriggerbutton" value="1.0"/><PARAM id="envtriggerjack" value="1.0"/><PARAM id="envtriggernoteon" value="1.0"/><PARAM id="extend" value="1.0"/><PARAM id="lforate" value="1.352001547813416"/><PARAM id="lforatesubdivision" value="9.0"/><PARAM id="lfotimemode" value="0.0"/><PARAM id="lfomode" value="0.0"/><PARAM id="lfopolarity" value="0.0"/><PARAM id="lfophase" value="0.0"/><PARAM id="lfotriggerbutton" value="0.0"/><PARAM id="lfotriggerjack" value="0.0"/><PARAM id="lfotriggernoteon" value="0.0"/><PARAM id="rndlforatesync" value="1.0"/><PARAM id="rndrate" value="5.000000476837158"/><PARAM id="rndratesubdivision" value="9.0"/><PARAM id="rndtimemode" value="0.0"/><PARAM id="rndpolarity" value="0.0"/><PARAM id="rnddensity" value="100.0"/><PARAM id="rndsmoothing" value="0.0"/><PARAM id="rndtriggerbutton" value="0.0"/><PARAM id="rndtriggerjack" value="0.0"/><PARAM id="rndtriggernoteon" value="0.0"/><PARAM id="taptempoenable" value="1.0"/><PARAM id="macro" value="99.981689453125"/><PARAM id="mxsource1" value="4.0"/><PARAM id="mxsource2" value="10.0"/><PARAM id="mxsource3" value="21.0"/><PARAM id="mxsource4" value="22.0"/><PARAM id="mxdesta" value="4.0"/><PARAM id="mxdestb" value="13.0"/><PARAM id="mxdestc" value="16.0"/><PARAM id="mxdestd" value="6.0"/><PARAM id="mxnode1a" value="52.0"/><PARAM id="mxnode1b" value="0.0"/><PARAM id="mxnode1c" value="0.0"/><PARAM id="mxnode1d" value="0.0"/><PARAM id="mxnode2a" value="0.0"/><PARAM id="mxnode2b" value="1.250076293945312"/><PARAM id="mxnode2c" value="0.0"/><PARAM id="mxnode2d" value="0.0"/><PARAM id="mxnode3a" value="0.0"/><PARAM id="mxnode3b" value="0.0"/><PARAM id="mxnode3c" value="-0.4000091552734375"/><PARAM id="mxnode3d" value="-31.99999237060547"/><PARAM id="mxnode4a" value="42.5"/><PARAM id="mxnode4b" value="0.0"/><PARAM id="mxnode4c" value="0.0"/><PARAM id="mxnode4d" value="0.0"/><PARAM id="mxnode1alock" value="0.0"/><PARAM id="mxnode1block" value="0.0"/><PARAM id="mxnode1clock" value="0.0"/><PARAM id="mxnode1dlock" value="0.0"/><PARAM id="mxnode2alock" value="0.0"/><PARAM id="mxnode2block" value="0.0"/><PARAM id="mxnode2clock" value="0.0"/><PARAM id="mxnode2dlock" value="0.0"/><PARAM id="mxnode3alock" value="0.0"/><PARAM id="mxnode3block" value="0.0"/><PARAM id="mxnode3clock" value="0.0"/><PARAM id="mxnode3dlock" value="0.0"/><PARAM id="mxnode4alock" value="0.0"/><PARAM id="mxnode4block" value="0.0"/><PARAM id="mxnode4clock" value="0.0"/><PARAM id="mxnode4dlock" value="0.0"/><PARAM id="monitormix" value="100.0"/><PARAM id="pickupbehaviour" value="0.0"/><Quantiser program="0"/></Parameters><Notes text=""/></SeashellPreset> 
]] },
  [9] = { name = "Soup or Saw", raw = [[
VC2!>  <?xml version="1.0" encoding="UTF-8"?> <SeashellPreset><Version major="2" minor="0" patch="0" tweak="0"/><Parameters><PARAM id="osc1frequency" value="-0.2299991846084595"/><PARAM id="osc2frequency" value="-0.2645958662033081"/><PARAM id="lfonoff" value="0.0"/><PARAM id="octaverange" value="5.0"/><PARAM id="sync" value="0.0"/><PARAM id="1voctrouting" value="3.0"/><PARAM id="transpose" value="3.0"/><PARAM id="portamento" value="0.0"/><PARAM id="midipitchbend" value="2.0"/><PARAM id="wavefoldinput" value="0.0"/><PARAM id="folddepth" value="0.1342855393886566"/><PARAM id="foldbias" value="0.0"/><PARAM id="foldbiasanimate" value="50.0"/><PARAM id="pulsewidth" value="50.0"/><PARAM id="pwmanimate" value="50.0"/><PARAM id="animateonoff" value="0.0"/><PARAM id="waveformselect" value="1.0"/><PARAM id="filtercutoff" value="0.1342855393886566"/><PARAM id="filterkeytrack" value="0.0"/><PARAM id="outputlevel" value="0.0"/><PARAM id="diffuseamount" value="23.9999885559082"/><PARAM id="envmode" value="1.0"/><PARAM id="envattack" value="0.05125704780220985"/><PARAM id="envdecay" value="1.38995897769928"/><PARAM id="envsustain" value="43.25"/><PARAM id="envrelease" value="1.38995897769928"/><PARAM id="envshape" value="1.0"/><PARAM id="envgate" value="1.0"/><PARAM id="envretrigonoff" value="1.0"/><PARAM id="envtriggerbutton" value="1.0"/><PARAM id="envtriggerjack" value="1.0"/><PARAM id="envtriggernoteon" value="1.0"/><PARAM id="extend" value="1.0"/><PARAM id="lforate" value="3.882403373718262"/><PARAM id="lforatesubdivision" value="6.0"/><PARAM id="lfotimemode" value="0.0"/><PARAM id="lfomode" value="0.0"/><PARAM id="lfopolarity" value="0.0"/><PARAM id="lfophase" value="0.0"/><PARAM id="lfotriggerbutton" value="1.0"/><PARAM id="lfotriggerjack" value="0.0"/><PARAM id="lfotriggernoteon" value="1.0"/><PARAM id="rndlforatesync" value="1.0"/><PARAM id="rndrate" value="5.000000476837158"/><PARAM id="rndratesubdivision" value="9.0"/><PARAM id="rndtimemode" value="0.0"/><PARAM id="rndpolarity" value="0.0"/><PARAM id="rnddensity" value="100.0"/><PARAM id="rndsmoothing" value="0.0"/><PARAM id="rndtriggerbutton" value="0.0"/><PARAM id="rndtriggerjack" value="0.0"/><PARAM id="rndtriggernoteon" value="0.0"/><PARAM id="taptempoenable" value="1.0"/><PARAM id="macro" value="99.98779296875"/><PARAM id="mxsource1" value="4.0"/><PARAM id="mxsource2" value="23.0"/><PARAM id="mxsource3" value="2.0"/><PARAM id="mxsource4" value="21.0"/><PARAM id="mxdesta" value="3.0"/><PARAM id="mxdestb" value="16.0"/><PARAM id="mxdestc" value="6.0"/><PARAM id="mxdestd" value="4.0"/><PARAM id="mxnode1a" value="75.0"/><PARAM id="mxnode1b" value="0.0"/><PARAM id="mxnode1c" value="0.0"/><PARAM id="mxnode1d" value="0.0"/><PARAM id="mxnode2a" value="0.0"/><PARAM id="mxnode2b" value="0.0"/><PARAM id="mxnode2c" value="0.0"/><PARAM id="mxnode2d" value="100.0"/><PARAM id="mxnode3a" value="0.0"/><PARAM id="mxnode3b" value="1.39990234375"/><PARAM id="mxnode3c" value="0.0"/><PARAM id="mxnode3d" value="0.0"/><PARAM id="mxnode4a" value="25.0"/><PARAM id="mxnode4b" value="0.0"/><PARAM id="mxnode4c" value="14.49998474121094"/><PARAM id="mxnode4d" value="0.0"/><PARAM id="mxnode1alock" value="0.0"/><PARAM id="mxnode1block" value="0.0"/><PARAM id="mxnode1clock" value="0.0"/><PARAM id="mxnode1dlock" value="0.0"/><PARAM id="mxnode2alock" value="0.0"/><PARAM id="mxnode2block" value="0.0"/><PARAM id="mxnode2clock" value="0.0"/><PARAM id="mxnode2dlock" value="0.0"/><PARAM id="mxnode3alock" value="0.0"/><PARAM id="mxnode3block" value="0.0"/><PARAM id="mxnode3clock" value="0.0"/><PARAM id="mxnode3dlock" value="0.0"/><PARAM id="mxnode4alock" value="0.0"/><PARAM id="mxnode4block" value="0.0"/><PARAM id="mxnode4clock" value="0.0"/><PARAM id="mxnode4dlock" value="0.0"/><PARAM id="monitormix" value="100.0"/><PARAM id="pickupbehaviour" value="0.0"/><Quantiser program="0"/></Parameters><Notes text=""/></SeashellPreset> 
]] },
  [10] = { name = "Sync Bender", raw = [[
VC2!ó  <?xml version="1.0" encoding="UTF-8"?> <SeashellPreset><Version major="2" minor="0" patch="0" tweak="0"/><Parameters><PARAM id="osc1frequency" value="0.4249995946884155"/><PARAM id="osc2frequency" value="0.0"/><PARAM id="lfonoff" value="0.0"/><PARAM id="octaverange" value="5.0"/><PARAM id="sync" value="1.0"/><PARAM id="1voctrouting" value="3.0"/><PARAM id="transpose" value="0.0"/><PARAM id="portamento" value="0.0"/><PARAM id="midipitchbend" value="2.0"/><PARAM id="wavefoldinput" value="0.0"/><PARAM id="folddepth" value="32.10645294189453"/><PARAM id="foldbias" value="0.0"/><PARAM id="foldbiasanimate" value="100.0"/><PARAM id="pulsewidth" value="50.0"/><PARAM id="pwmanimate" value="100.0"/><PARAM id="animateonoff" value="1.0"/><PARAM id="waveformselect" value="0.0"/><PARAM id="filtercutoff" value="0.0"/><PARAM id="filterkeytrack" value="0.0"/><PARAM id="outputlevel" value="100.0"/><PARAM id="diffuseamount" value="100.0"/><PARAM id="envmode" value="0.0"/><PARAM id="envattack" value="1.612692832946777"/><PARAM id="envdecay" value="1.373126626014709"/><PARAM id="envsustain" value="50.0"/><PARAM id="envrelease" value="1.373126626014709"/><PARAM id="envshape" value="0.0"/><PARAM id="envgate" value="1.0"/><PARAM id="envretrigonoff" value="1.0"/><PARAM id="envtriggerbutton" value="1.0"/><PARAM id="envtriggerjack" value="1.0"/><PARAM id="envtriggernoteon" value="1.0"/><PARAM id="extend" value="1.0"/><PARAM id="lforate" value="1.999999761581421"/><PARAM id="lforatesubdivision" value="9.0"/><PARAM id="lfotimemode" value="0.0"/><PARAM id="lfomode" value="0.0"/><PARAM id="lfopolarity" value="0.0"/><PARAM id="lfophase" value="0.0"/><PARAM id="lfotriggerbutton" value="0.0"/><PARAM id="lfotriggerjack" value="0.0"/><PARAM id="lfotriggernoteon" value="0.0"/><PARAM id="rndlforatesync" value="1.0"/><PARAM id="rndrate" value="5.000000476837158"/><PARAM id="rndratesubdivision" value="9.0"/><PARAM id="rndtimemode" value="0.0"/><PARAM id="rndpolarity" value="0.0"/><PARAM id="rnddensity" value="100.0"/><PARAM id="rndsmoothing" value="0.0"/><PARAM id="rndtriggerbutton" value="0.0"/><PARAM id="rndtriggerjack" value="0.0"/><PARAM id="rndtriggernoteon" value="0.0"/><PARAM id="taptempoenable" value="1.0"/><PARAM id="macro" value="100.0"/><PARAM id="mxsource1" value="4.0"/><PARAM id="mxsource2" value="0.0"/><PARAM id="mxsource3" value="0.0"/><PARAM id="mxsource4" value="0.0"/><PARAM id="mxdesta" value="3.0"/><PARAM id="mxdestb" value="13.0"/><PARAM id="mxdestc" value="16.0"/><PARAM id="mxdestd" value="0.0"/><PARAM id="mxnode1a" value="91.5"/><PARAM id="mxnode1b" value="100.0"/><PARAM id="mxnode1c" value="-9.0"/><PARAM id="mxnode1d" value="0.0"/><PARAM id="mxnode2a" value="0.0"/><PARAM id="mxnode2b" value="0.0"/><PARAM id="mxnode2c" value="0.0"/><PARAM id="mxnode2d" value="0.0"/><PARAM id="mxnode3a" value="0.0"/><PARAM id="mxnode3b" value="0.0"/><PARAM id="mxnode3c" value="0.0"/><PARAM id="mxnode3d" value="0.0"/><PARAM id="mxnode4a" value="0.0"/><PARAM id="mxnode4b" value="0.0"/><PARAM id="mxnode4c" value="0.0"/><PARAM id="mxnode4d" value="0.0"/><PARAM id="mxnode1alock" value="0.0"/><PARAM id="mxnode1block" value="0.0"/><PARAM id="mxnode1clock" value="0.0"/><PARAM id="mxnode1dlock" value="0.0"/><PARAM id="mxnode2alock" value="0.0"/><PARAM id="mxnode2block" value="0.0"/><PARAM id="mxnode2clock" value="0.0"/><PARAM id="mxnode2dlock" value="0.0"/><PARAM id="mxnode3alock" value="0.0"/><PARAM id="mxnode3block" value="0.0"/><PARAM id="mxnode3clock" value="0.0"/><PARAM id="mxnode3dlock" value="0.0"/><PARAM id="mxnode4alock" value="0.0"/><PARAM id="mxnode4block" value="0.0"/><PARAM id="mxnode4clock" value="0.0"/><PARAM id="mxnode4dlock" value="0.0"/><PARAM id="monitormix" value="100.0"/><PARAM id="pickupbehaviour" value="0.0"/><Quantiser program="0"/></Parameters><Notes text=""/></SeashellPreset> 
]] },
  [11] = { name = "Tone Bender", raw = [[
VC2!ã  <?xml version="1.0" encoding="UTF-8"?> <SeashellPreset><Version major="2" minor="0" patch="0" tweak="0"/><Parameters><PARAM id="osc1frequency" value="0.0"/><PARAM id="osc2frequency" value="0.0"/><PARAM id="lfonoff" value="0.0"/><PARAM id="octaverange" value="5.0"/><PARAM id="sync" value="0.0"/><PARAM id="1voctrouting" value="3.0"/><PARAM id="transpose" value="0.0"/><PARAM id="portamento" value="0.0"/><PARAM id="midipitchbend" value="2.0"/><PARAM id="wavefoldinput" value="0.0"/><PARAM id="folddepth" value="32.10645294189453"/><PARAM id="foldbias" value="0.0"/><PARAM id="foldbiasanimate" value="100.0"/><PARAM id="pulsewidth" value="50.0"/><PARAM id="pwmanimate" value="100.0"/><PARAM id="animateonoff" value="1.0"/><PARAM id="waveformselect" value="0.0"/><PARAM id="filtercutoff" value="0.0"/><PARAM id="filterkeytrack" value="0.0"/><PARAM id="outputlevel" value="100.0"/><PARAM id="diffuseamount" value="100.0"/><PARAM id="envmode" value="0.0"/><PARAM id="envattack" value="1.612692832946777"/><PARAM id="envdecay" value="1.373126626014709"/><PARAM id="envsustain" value="50.0"/><PARAM id="envrelease" value="1.373126626014709"/><PARAM id="envshape" value="0.0"/><PARAM id="envgate" value="1.0"/><PARAM id="envretrigonoff" value="1.0"/><PARAM id="envtriggerbutton" value="1.0"/><PARAM id="envtriggerjack" value="1.0"/><PARAM id="envtriggernoteon" value="1.0"/><PARAM id="extend" value="1.0"/><PARAM id="lforate" value="1.999999761581421"/><PARAM id="lforatesubdivision" value="9.0"/><PARAM id="lfotimemode" value="0.0"/><PARAM id="lfomode" value="0.0"/><PARAM id="lfopolarity" value="0.0"/><PARAM id="lfophase" value="0.0"/><PARAM id="lfotriggerbutton" value="0.0"/><PARAM id="lfotriggerjack" value="0.0"/><PARAM id="lfotriggernoteon" value="0.0"/><PARAM id="rndlforatesync" value="1.0"/><PARAM id="rndrate" value="5.000000476837158"/><PARAM id="rndratesubdivision" value="9.0"/><PARAM id="rndtimemode" value="0.0"/><PARAM id="rndpolarity" value="0.0"/><PARAM id="rnddensity" value="100.0"/><PARAM id="rndsmoothing" value="0.0"/><PARAM id="rndtriggerbutton" value="0.0"/><PARAM id="rndtriggerjack" value="0.0"/><PARAM id="rndtriggernoteon" value="0.0"/><PARAM id="taptempoenable" value="1.0"/><PARAM id="macro" value="100.0"/><PARAM id="mxsource1" value="4.0"/><PARAM id="mxsource2" value="0.0"/><PARAM id="mxsource3" value="0.0"/><PARAM id="mxsource4" value="0.0"/><PARAM id="mxdesta" value="3.0"/><PARAM id="mxdestb" value="13.0"/><PARAM id="mxdestc" value="16.0"/><PARAM id="mxdestd" value="0.0"/><PARAM id="mxnode1a" value="91.5"/><PARAM id="mxnode1b" value="-7.0"/><PARAM id="mxnode1c" value="-8.5"/><PARAM id="mxnode1d" value="0.0"/><PARAM id="mxnode2a" value="0.0"/><PARAM id="mxnode2b" value="0.0"/><PARAM id="mxnode2c" value="0.0"/><PARAM id="mxnode2d" value="0.0"/><PARAM id="mxnode3a" value="0.0"/><PARAM id="mxnode3b" value="0.0"/><PARAM id="mxnode3c" value="0.0"/><PARAM id="mxnode3d" value="0.0"/><PARAM id="mxnode4a" value="0.0"/><PARAM id="mxnode4b" value="0.0"/><PARAM id="mxnode4c" value="0.0"/><PARAM id="mxnode4d" value="0.0"/><PARAM id="mxnode1alock" value="0.0"/><PARAM id="mxnode1block" value="0.0"/><PARAM id="mxnode1clock" value="0.0"/><PARAM id="mxnode1dlock" value="0.0"/><PARAM id="mxnode2alock" value="0.0"/><PARAM id="mxnode2block" value="0.0"/><PARAM id="mxnode2clock" value="0.0"/><PARAM id="mxnode2dlock" value="0.0"/><PARAM id="mxnode3alock" value="0.0"/><PARAM id="mxnode3block" value="0.0"/><PARAM id="mxnode3clock" value="0.0"/><PARAM id="mxnode3dlock" value="0.0"/><PARAM id="mxnode4alock" value="0.0"/><PARAM id="mxnode4block" value="0.0"/><PARAM id="mxnode4clock" value="0.0"/><PARAM id="mxnode4dlock" value="0.0"/><PARAM id="monitormix" value="100.0"/><PARAM id="pickupbehaviour" value="0.0"/><Quantiser program="0"/></Parameters><Notes text=""/></SeashellPreset> 
]] },
  [12] = { name = "Doppler", raw = [[
VC2!  <?xml version="1.0" encoding="UTF-8"?> <SeashellPreset><Version major="2" minor="0" patch="0" tweak="0"/><Parameters><PARAM id="osc1frequency" value="0.0"/><PARAM id="osc2frequency" value="0.0"/><PARAM id="lfonoff" value="0.0"/><PARAM id="octaverange" value="5.0"/><PARAM id="sync" value="0.0"/><PARAM id="1voctrouting" value="3.0"/><PARAM id="transpose" value="0.0"/><PARAM id="portamento" value="0.0"/><PARAM id="midipitchbend" value="2.0"/><PARAM id="wavefoldinput" value="0.0"/><PARAM id="folddepth" value="0.0"/><PARAM id="foldbias" value="0.0"/><PARAM id="foldbiasanimate" value="0.0"/><PARAM id="pulsewidth" value="50.0"/><PARAM id="pwmanimate" value="50.0"/><PARAM id="animateonoff" value="1.0"/><PARAM id="waveformselect" value="3.0"/><PARAM id="filtercutoff" value="33.25001525878906"/><PARAM id="filterkeytrack" value="21.49997711181641"/><PARAM id="outputlevel" value="100.0"/><PARAM id="diffuseamount" value="26.74999618530273"/><PARAM id="envmode" value="1.0"/><PARAM id="envattack" value="0.0"/><PARAM id="envdecay" value="0.2633198797702789"/><PARAM id="envsustain" value="66.74998474121094"/><PARAM id="envrelease" value="0.2633198797702789"/><PARAM id="envshape" value="1.0"/><PARAM id="envgate" value="1.0"/><PARAM id="envretrigonoff" value="1.0"/><PARAM id="envtriggerbutton" value="1.0"/><PARAM id="envtriggerjack" value="1.0"/><PARAM id="envtriggernoteon" value="1.0"/><PARAM id="extend" value="1.0"/><PARAM id="lforate" value="1.0010826587677"/><PARAM id="lforatesubdivision" value="9.0"/><PARAM id="lfotimemode" value="0.0"/><PARAM id="lfomode" value="0.0"/><PARAM id="lfopolarity" value="0.0"/><PARAM id="lfophase" value="0.0"/><PARAM id="lfotriggerbutton" value="1.0"/><PARAM id="lfotriggerjack" value="1.0"/><PARAM id="lfotriggernoteon" value="1.0"/><PARAM id="rndlforatesync" value="1.0"/><PARAM id="rndrate" value="5.000000476837158"/><PARAM id="rndratesubdivision" value="9.0"/><PARAM id="rndtimemode" value="0.0"/><PARAM id="rndpolarity" value="0.0"/><PARAM id="rnddensity" value="100.0"/><PARAM id="rndsmoothing" value="0.0"/><PARAM id="rndtriggerbutton" value="0.0"/><PARAM id="rndtriggerjack" value="0.0"/><PARAM id="rndtriggernoteon" value="0.0"/><PARAM id="taptempoenable" value="1.0"/><PARAM id="macro" value="100.0"/><PARAM id="mxsource1" value="10.0"/><PARAM id="mxsource2" value="4.0"/><PARAM id="mxsource3" value="0.0"/><PARAM id="mxsource4" value="0.0"/><PARAM id="mxdesta" value="9.0"/><PARAM id="mxdestb" value="3.0"/><PARAM id="mxdestc" value="0.0"/><PARAM id="mxdestd" value="0.0"/><PARAM id="mxnode1a" value="30.99996948242188"/><PARAM id="mxnode1b" value="0.0"/><PARAM id="mxnode1c" value="0.0"/><PARAM id="mxnode1d" value="0.0"/><PARAM id="mxnode2a" value="0.0"/><PARAM id="mxnode2b" value="50.49996948242188"/><PARAM id="mxnode2c" value="0.0"/><PARAM id="mxnode2d" value="0.0"/><PARAM id="mxnode3a" value="0.0"/><PARAM id="mxnode3b" value="0.0"/><PARAM id="mxnode3c" value="0.0"/><PARAM id="mxnode3d" value="0.0"/><PARAM id="mxnode4a" value="0.0"/><PARAM id="mxnode4b" value="0.0"/><PARAM id="mxnode4c" value="0.0"/><PARAM id="mxnode4d" value="0.0"/><PARAM id="mxnode1alock" value="0.0"/><PARAM id="mxnode1block" value="0.0"/><PARAM id="mxnode1clock" value="0.0"/><PARAM id="mxnode1dlock" value="0.0"/><PARAM id="mxnode2alock" value="0.0"/><PARAM id="mxnode2block" value="0.0"/><PARAM id="mxnode2clock" value="0.0"/><PARAM id="mxnode2dlock" value="0.0"/><PARAM id="mxnode3alock" value="0.0"/><PARAM id="mxnode3block" value="0.0"/><PARAM id="mxnode3clock" value="0.0"/><PARAM id="mxnode3dlock" value="0.0"/><PARAM id="mxnode4alock" value="0.0"/><PARAM id="mxnode4block" value="0.0"/><PARAM id="mxnode4clock" value="0.0"/><PARAM id="mxnode4dlock" value="0.0"/><PARAM id="monitormix" value="100.0"/><PARAM id="pickupbehaviour" value="0.0"/><Quantiser program="0"/></Parameters><Notes text=""/></SeashellPreset> 
]] },
  [13] = { name = "Kitchen Sync", raw = [[
VC2!*  <?xml version="1.0" encoding="UTF-8"?> <SeashellPreset><Version major="2" minor="0" patch="0" tweak="0"/><Parameters><PARAM id="osc1frequency" value="0.2050007581710815"/><PARAM id="osc2frequency" value="0.0"/><PARAM id="lfonoff" value="0.0"/><PARAM id="octaverange" value="5.0"/><PARAM id="sync" value="1.0"/><PARAM id="1voctrouting" value="3.0"/><PARAM id="transpose" value="0.0"/><PARAM id="portamento" value="0.0"/><PARAM id="midipitchbend" value="2.0"/><PARAM id="wavefoldinput" value="0.0"/><PARAM id="folddepth" value="0.0"/><PARAM id="foldbias" value="0.0"/><PARAM id="foldbiasanimate" value="0.0"/><PARAM id="pulsewidth" value="50.0"/><PARAM id="pwmanimate" value="50.0"/><PARAM id="animateonoff" value="1.0"/><PARAM id="waveformselect" value="3.0"/><PARAM id="filtercutoff" value="10.42544078826904"/><PARAM id="filterkeytrack" value="47.0"/><PARAM id="outputlevel" value="0.0"/><PARAM id="diffuseamount" value="24.0"/><PARAM id="envmode" value="1.0"/><PARAM id="envattack" value="0.09587927162647247"/><PARAM id="envdecay" value="0.7977157235145569"/><PARAM id="envsustain" value="66.49998474121094"/><PARAM id="envrelease" value="0.7977157235145569"/><PARAM id="envshape" value="1.0"/><PARAM id="envgate" value="1.0"/><PARAM id="envretrigonoff" value="1.0"/><PARAM id="envtriggerbutton" value="1.0"/><PARAM id="envtriggerjack" value="1.0"/><PARAM id="envtriggernoteon" value="1.0"/><PARAM id="extend" value="1.0"/><PARAM id="lforate" value="1.003321766853333"/><PARAM id="lforatesubdivision" value="9.0"/><PARAM id="lfotimemode" value="0.0"/><PARAM id="lfomode" value="0.0"/><PARAM id="lfopolarity" value="0.0"/><PARAM id="lfophase" value="0.0"/><PARAM id="lfotriggerbutton" value="1.0"/><PARAM id="lfotriggerjack" value="1.0"/><PARAM id="lfotriggernoteon" value="1.0"/><PARAM id="rndlforatesync" value="1.0"/><PARAM id="rndrate" value="5.000000476837158"/><PARAM id="rndratesubdivision" value="9.0"/><PARAM id="rndtimemode" value="0.0"/><PARAM id="rndpolarity" value="0.0"/><PARAM id="rnddensity" value="100.0"/><PARAM id="rndsmoothing" value="0.0"/><PARAM id="rndtriggerbutton" value="0.0"/><PARAM id="rndtriggerjack" value="0.0"/><PARAM id="rndtriggernoteon" value="0.0"/><PARAM id="taptempoenable" value="1.0"/><PARAM id="macro" value="100.0"/><PARAM id="mxsource1" value="10.0"/><PARAM id="mxsource2" value="4.0"/><PARAM id="mxsource3" value="21.0"/><PARAM id="mxsource4" value="0.0"/><PARAM id="mxdesta" value="14.0"/><PARAM id="mxdestb" value="9.0"/><PARAM id="mxdestc" value="3.0"/><PARAM id="mxdestd" value="4.0"/><PARAM id="mxnode1a" value="4.499992370605469"/><PARAM id="mxnode1b" value="-15.99998474121094"/><PARAM id="mxnode1c" value="0.0"/><PARAM id="mxnode1d" value="0.0"/><PARAM id="mxnode2a" value="30.64996337890625"/><PARAM id="mxnode2b" value="0.0"/><PARAM id="mxnode2c" value="82.5"/><PARAM id="mxnode2d" value="0.0"/><PARAM id="mxnode3a" value="0.0"/><PARAM id="mxnode3b" value="0.0"/><PARAM id="mxnode3c" value="0.0"/><PARAM id="mxnode3d" value="100.0"/><PARAM id="mxnode4a" value="0.0"/><PARAM id="mxnode4b" value="0.0"/><PARAM id="mxnode4c" value="0.0"/><PARAM id="mxnode4d" value="0.0"/><PARAM id="mxnode1alock" value="0.0"/><PARAM id="mxnode1block" value="0.0"/><PARAM id="mxnode1clock" value="0.0"/><PARAM id="mxnode1dlock" value="0.0"/><PARAM id="mxnode2alock" value="0.0"/><PARAM id="mxnode2block" value="0.0"/><PARAM id="mxnode2clock" value="0.0"/><PARAM id="mxnode2dlock" value="0.0"/><PARAM id="mxnode3alock" value="0.0"/><PARAM id="mxnode3block" value="0.0"/><PARAM id="mxnode3clock" value="0.0"/><PARAM id="mxnode3dlock" value="0.0"/><PARAM id="mxnode4alock" value="0.0"/><PARAM id="mxnode4block" value="0.0"/><PARAM id="mxnode4clock" value="0.0"/><PARAM id="mxnode4dlock" value="0.0"/><PARAM id="monitormix" value="100.0"/><PARAM id="pickupbehaviour" value="0.0"/><Quantiser program="0"/></Parameters><Notes text=""/></SeashellPreset> 
]] },
  [14] = { name = "Pulse with Mod", raw = [[
VC2!  <?xml version="1.0" encoding="UTF-8"?> <SeashellPreset><Version major="2" minor="0" patch="0" tweak="0"/><Parameters><PARAM id="osc1frequency" value="0.0"/><PARAM id="osc2frequency" value="0.0"/><PARAM id="lfonoff" value="0.0"/><PARAM id="octaverange" value="5.0"/><PARAM id="sync" value="0.0"/><PARAM id="1voctrouting" value="3.0"/><PARAM id="transpose" value="0.0"/><PARAM id="portamento" value="0.0"/><PARAM id="midipitchbend" value="2.0"/><PARAM id="wavefoldinput" value="0.0"/><PARAM id="folddepth" value="0.0"/><PARAM id="foldbias" value="0.0"/><PARAM id="foldbiasanimate" value="50.0"/><PARAM id="pulsewidth" value="50.0"/><PARAM id="pwmanimate" value="50.0"/><PARAM id="animateonoff" value="0.0"/><PARAM id="waveformselect" value="6.0"/><PARAM id="filtercutoff" value="91.75001525878906"/><PARAM id="filterkeytrack" value="0.0"/><PARAM id="outputlevel" value="100.0"/><PARAM id="diffuseamount" value="26.74999618530273"/><PARAM id="envmode" value="1.0"/><PARAM id="envattack" value="0.0"/><PARAM id="envdecay" value="0.2633198797702789"/><PARAM id="envsustain" value="66.74998474121094"/><PARAM id="envrelease" value="0.2633198797702789"/><PARAM id="envshape" value="1.0"/><PARAM id="envgate" value="1.0"/><PARAM id="envretrigonoff" value="1.0"/><PARAM id="envtriggerbutton" value="1.0"/><PARAM id="envtriggerjack" value="1.0"/><PARAM id="envtriggernoteon" value="1.0"/><PARAM id="extend" value="1.0"/><PARAM id="lforate" value="1.0010826587677"/><PARAM id="lforatesubdivision" value="9.0"/><PARAM id="lfotimemode" value="0.0"/><PARAM id="lfomode" value="0.0"/><PARAM id="lfopolarity" value="0.0"/><PARAM id="lfophase" value="0.0"/><PARAM id="lfotriggerbutton" value="1.0"/><PARAM id="lfotriggerjack" value="1.0"/><PARAM id="lfotriggernoteon" value="1.0"/><PARAM id="rndlforatesync" value="1.0"/><PARAM id="rndrate" value="5.000000476837158"/><PARAM id="rndratesubdivision" value="9.0"/><PARAM id="rndtimemode" value="0.0"/><PARAM id="rndpolarity" value="0.0"/><PARAM id="rnddensity" value="100.0"/><PARAM id="rndsmoothing" value="0.0"/><PARAM id="rndtriggerbutton" value="0.0"/><PARAM id="rndtriggerjack" value="0.0"/><PARAM id="rndtriggernoteon" value="0.0"/><PARAM id="taptempoenable" value="1.0"/><PARAM id="macro" value="0.0"/><PARAM id="mxsource1" value="10.0"/><PARAM id="mxsource2" value="4.0"/><PARAM id="mxsource3" value="2.0"/><PARAM id="mxsource4" value="0.0"/><PARAM id="mxdesta" value="9.0"/><PARAM id="mxdestb" value="3.0"/><PARAM id="mxdestc" value="0.0"/><PARAM id="mxdestd" value="0.0"/><PARAM id="mxnode1a" value="30.99996948242188"/><PARAM id="mxnode1b" value="0.0"/><PARAM id="mxnode1c" value="0.0"/><PARAM id="mxnode1d" value="0.0"/><PARAM id="mxnode2a" value="0.0"/><PARAM id="mxnode2b" value="0.0"/><PARAM id="mxnode2c" value="0.0"/><PARAM id="mxnode2d" value="0.0"/><PARAM id="mxnode3a" value="0.0"/><PARAM id="mxnode3b" value="15.99998474121094"/><PARAM id="mxnode3c" value="0.0"/><PARAM id="mxnode3d" value="0.0"/><PARAM id="mxnode4a" value="0.0"/><PARAM id="mxnode4b" value="0.0"/><PARAM id="mxnode4c" value="0.0"/><PARAM id="mxnode4d" value="0.0"/><PARAM id="mxnode1alock" value="0.0"/><PARAM id="mxnode1block" value="0.0"/><PARAM id="mxnode1clock" value="0.0"/><PARAM id="mxnode1dlock" value="0.0"/><PARAM id="mxnode2alock" value="0.0"/><PARAM id="mxnode2block" value="0.0"/><PARAM id="mxnode2clock" value="0.0"/><PARAM id="mxnode2dlock" value="0.0"/><PARAM id="mxnode3alock" value="0.0"/><PARAM id="mxnode3block" value="0.0"/><PARAM id="mxnode3clock" value="0.0"/><PARAM id="mxnode3dlock" value="0.0"/><PARAM id="mxnode4alock" value="0.0"/><PARAM id="mxnode4block" value="0.0"/><PARAM id="mxnode4clock" value="0.0"/><PARAM id="mxnode4dlock" value="0.0"/><PARAM id="monitormix" value="100.0"/><PARAM id="pickupbehaviour" value="0.0"/><Quantiser program="0"/></Parameters><Notes text=""/></SeashellPreset> 
]] },
  [15] = { name = "Saw 5ths", raw = [[
VC2!  <?xml version="1.0" encoding="UTF-8"?> <SeashellPreset><Version major="2" minor="0" patch="0" tweak="0"/><Parameters><PARAM id="osc1frequency" value="-0.1399998664855957"/><PARAM id="osc2frequency" value="-0.03499996662139893"/><PARAM id="lfonoff" value="0.0"/><PARAM id="octaverange" value="5.0"/><PARAM id="sync" value="0.0"/><PARAM id="1voctrouting" value="3.0"/><PARAM id="transpose" value="3.0"/><PARAM id="portamento" value="0.0"/><PARAM id="midipitchbend" value="2.0"/><PARAM id="wavefoldinput" value="0.0"/><PARAM id="folddepth" value="3.467008590698242"/><PARAM id="foldbias" value="0.0"/><PARAM id="foldbiasanimate" value="50.0"/><PARAM id="pulsewidth" value="31.5"/><PARAM id="pwmanimate" value="50.0"/><PARAM id="animateonoff" value="0.0"/><PARAM id="waveformselect" value="1.0"/><PARAM id="filtercutoff" value="7.275834560394287"/><PARAM id="filterkeytrack" value="0.0"/><PARAM id="outputlevel" value="100.0"/><PARAM id="diffuseamount" value="0.0"/><PARAM id="envmode" value="1.0"/><PARAM id="envattack" value="0.0"/><PARAM id="envdecay" value="1.634606838226318"/><PARAM id="envsustain" value="47.00000762939453"/><PARAM id="envrelease" value="0.5755913257598877"/><PARAM id="envshape" value="1.0"/><PARAM id="envgate" value="1.0"/><PARAM id="envretrigonoff" value="1.0"/><PARAM id="envtriggerbutton" value="1.0"/><PARAM id="envtriggerjack" value="1.0"/><PARAM id="envtriggernoteon" value="1.0"/><PARAM id="extend" value="1.0"/><PARAM id="lforate" value="7.260122299194336"/><PARAM id="lforatesubdivision" value="9.0"/><PARAM id="lfotimemode" value="0.0"/><PARAM id="lfomode" value="0.0"/><PARAM id="lfopolarity" value="0.0"/><PARAM id="lfophase" value="0.0"/><PARAM id="lfotriggerbutton" value="0.0"/><PARAM id="lfotriggerjack" value="0.0"/><PARAM id="lfotriggernoteon" value="0.0"/><PARAM id="rndlforatesync" value="1.0"/><PARAM id="rndrate" value="5.000000476837158"/><PARAM id="rndratesubdivision" value="9.0"/><PARAM id="rndtimemode" value="0.0"/><PARAM id="rndpolarity" value="0.0"/><PARAM id="rnddensity" value="100.0"/><PARAM id="rndsmoothing" value="0.0"/><PARAM id="rndtriggerbutton" value="0.0"/><PARAM id="rndtriggerjack" value="0.0"/><PARAM id="rndtriggernoteon" value="0.0"/><PARAM id="taptempoenable" value="1.0"/><PARAM id="macro" value="100.0"/><PARAM id="mxsource1" value="4.0"/><PARAM id="mxsource2" value="10.0"/><PARAM id="mxsource3" value="0.0"/><PARAM id="mxsource4" value="0.0"/><PARAM id="mxdesta" value="3.0"/><PARAM id="mxdestb" value="25.0"/><PARAM id="mxdestc" value="10.0"/><PARAM id="mxdestd" value="0.0"/><PARAM id="mxnode1a" value="37.0"/><PARAM id="mxnode1b" value="-24.5"/><PARAM id="mxnode1c" value="0.0"/><PARAM id="mxnode1d" value="0.0"/><PARAM id="mxnode2a" value="0.0"/><PARAM id="mxnode2b" value="0.0"/><PARAM id="mxnode2c" value="-0.5"/><PARAM id="mxnode2d" value="0.0"/><PARAM id="mxnode3a" value="0.0"/><PARAM id="mxnode3b" value="0.0"/><PARAM id="mxnode3c" value="0.0"/><PARAM id="mxnode3d" value="0.0"/><PARAM id="mxnode4a" value="0.0"/><PARAM id="mxnode4b" value="0.0"/><PARAM id="mxnode4c" value="0.0"/><PARAM id="mxnode4d" value="0.0"/><PARAM id="mxnode1alock" value="0.0"/><PARAM id="mxnode1block" value="0.0"/><PARAM id="mxnode1clock" value="0.0"/><PARAM id="mxnode1dlock" value="0.0"/><PARAM id="mxnode2alock" value="0.0"/><PARAM id="mxnode2block" value="0.0"/><PARAM id="mxnode2clock" value="0.0"/><PARAM id="mxnode2dlock" value="0.0"/><PARAM id="mxnode3alock" value="0.0"/><PARAM id="mxnode3block" value="0.0"/><PARAM id="mxnode3clock" value="0.0"/><PARAM id="mxnode3dlock" value="0.0"/><PARAM id="mxnode4alock" value="0.0"/><PARAM id="mxnode4block" value="0.0"/><PARAM id="mxnode4clock" value="0.0"/><PARAM id="mxnode4dlock" value="0.0"/><PARAM id="monitormix" value="100.0"/><PARAM id="pickupbehaviour" value="0.0"/><Quantiser program="0"/></Parameters><Notes text=""/></SeashellPreset> 
]] },
  [16] = { name = "Sync Sweep", raw = [[
VC2!:  <?xml version="1.0" encoding="UTF-8"?> <SeashellPreset><Version major="2" minor="0" patch="0" tweak="0"/><Parameters><PARAM id="osc1frequency" value="-0.1400003433227539"/><PARAM id="osc2frequency" value="0.0"/><PARAM id="lfonoff" value="0.0"/><PARAM id="octaverange" value="5.0"/><PARAM id="sync" value="2.0"/><PARAM id="1voctrouting" value="3.0"/><PARAM id="transpose" value="0.0"/><PARAM id="portamento" value="0.0"/><PARAM id="midipitchbend" value="2.0"/><PARAM id="wavefoldinput" value="0.0"/><PARAM id="folddepth" value="0.2502593994140625"/><PARAM id="foldbias" value="0.0"/><PARAM id="foldbiasanimate" value="50.0"/><PARAM id="pulsewidth" value="23.25000762939453"/><PARAM id="pwmanimate" value="50.0"/><PARAM id="animateonoff" value="0.0"/><PARAM id="waveformselect" value="3.0"/><PARAM id="filtercutoff" value="0.0"/><PARAM id="filterkeytrack" value="0.0"/><PARAM id="outputlevel" value="100.0"/><PARAM id="diffuseamount" value="15.75001525878906"/><PARAM id="envmode" value="1.0"/><PARAM id="envattack" value="0.002378250472247601"/><PARAM id="envdecay" value="6.785644054412842"/><PARAM id="envsustain" value="0.0"/><PARAM id="envrelease" value="0.6216555833816528"/><PARAM id="envshape" value="1.0"/><PARAM id="envgate" value="1.0"/><PARAM id="envretrigonoff" value="1.0"/><PARAM id="envtriggerbutton" value="1.0"/><PARAM id="envtriggerjack" value="1.0"/><PARAM id="envtriggernoteon" value="1.0"/><PARAM id="extend" value="1.0"/><PARAM id="lforate" value="6.341420650482178"/><PARAM id="lforatesubdivision" value="9.0"/><PARAM id="lfotimemode" value="0.0"/><PARAM id="lfomode" value="2.0"/><PARAM id="lfopolarity" value="1.0"/><PARAM id="lfophase" value="0.0"/><PARAM id="lfotriggerbutton" value="0.0"/><PARAM id="lfotriggerjack" value="0.0"/><PARAM id="lfotriggernoteon" value="1.0"/><PARAM id="rndlforatesync" value="1.0"/><PARAM id="rndrate" value="5.000000476837158"/><PARAM id="rndratesubdivision" value="9.0"/><PARAM id="rndtimemode" value="0.0"/><PARAM id="rndpolarity" value="0.0"/><PARAM id="rnddensity" value="100.0"/><PARAM id="rndsmoothing" value="0.0"/><PARAM id="rndtriggerbutton" value="0.0"/><PARAM id="rndtriggerjack" value="0.0"/><PARAM id="rndtriggernoteon" value="0.0"/><PARAM id="taptempoenable" value="1.0"/><PARAM id="macro" value="100.0"/><PARAM id="mxsource1" value="4.0"/><PARAM id="mxsource2" value="23.0"/><PARAM id="mxsource3" value="14.0"/><PARAM id="mxsource4" value="0.0"/><PARAM id="mxdesta" value="14.0"/><PARAM id="mxdestb" value="3.0"/><PARAM id="mxdestc" value="9.0"/><PARAM id="mxdestd" value="6.0"/><PARAM id="mxnode1a" value="45.0"/><PARAM id="mxnode1b" value="28.49996948242188"/><PARAM id="mxnode1c" value="0.0"/><PARAM id="mxnode1d" value="-49.49993896484375"/><PARAM id="mxnode2a" value="0.0"/><PARAM id="mxnode2b" value="17.49998474121094"/><PARAM id="mxnode2c" value="0.0"/><PARAM id="mxnode2d" value="0.0"/><PARAM id="mxnode3a" value="0.0"/><PARAM id="mxnode3b" value="0.0"/><PARAM id="mxnode3c" value="100.0"/><PARAM id="mxnode3d" value="0.0"/><PARAM id="mxnode4a" value="0.0"/><PARAM id="mxnode4b" value="0.0"/><PARAM id="mxnode4c" value="0.0"/><PARAM id="mxnode4d" value="0.0"/><PARAM id="mxnode1alock" value="1.0"/><PARAM id="mxnode1block" value="0.0"/><PARAM id="mxnode1clock" value="0.0"/><PARAM id="mxnode1dlock" value="0.0"/><PARAM id="mxnode2alock" value="0.0"/><PARAM id="mxnode2block" value="0.0"/><PARAM id="mxnode2clock" value="0.0"/><PARAM id="mxnode2dlock" value="0.0"/><PARAM id="mxnode3alock" value="0.0"/><PARAM id="mxnode3block" value="0.0"/><PARAM id="mxnode3clock" value="0.0"/><PARAM id="mxnode3dlock" value="0.0"/><PARAM id="mxnode4alock" value="0.0"/><PARAM id="mxnode4block" value="0.0"/><PARAM id="mxnode4clock" value="0.0"/><PARAM id="mxnode4dlock" value="0.0"/><PARAM id="monitormix" value="100.0"/><PARAM id="pickupbehaviour" value="0.0"/><Quantiser program="0"/></Parameters><Notes text=""/></SeashellPreset> 
]] },
  [17] = { name = "Unraveled", raw = [[
VC2!  <?xml version="1.0" encoding="UTF-8"?> <SeashellPreset><Version major="2" minor="0" patch="0" tweak="0"/><Parameters><PARAM id="osc1frequency" value="0.0"/><PARAM id="osc2frequency" value="0.00149989128112793"/><PARAM id="lfonoff" value="0.0"/><PARAM id="octaverange" value="5.0"/><PARAM id="sync" value="0.0"/><PARAM id="1voctrouting" value="3.0"/><PARAM id="transpose" value="0.0"/><PARAM id="portamento" value="0.0"/><PARAM id="midipitchbend" value="2.0"/><PARAM id="wavefoldinput" value="0.0"/><PARAM id="folddepth" value="0.1342855393886566"/><PARAM id="foldbias" value="100.0"/><PARAM id="foldbiasanimate" value="50.0"/><PARAM id="pulsewidth" value="50.0"/><PARAM id="pwmanimate" value="50.0"/><PARAM id="animateonoff" value="0.0"/><PARAM id="waveformselect" value="0.0"/><PARAM id="filtercutoff" value="24.2629566192627"/><PARAM id="filterkeytrack" value="29.49996948242188"/><PARAM id="outputlevel" value="0.0"/><PARAM id="diffuseamount" value="100.0"/><PARAM id="envmode" value="1.0"/><PARAM id="envattack" value="1.017829179763794"/><PARAM id="envdecay" value="1.546327590942383"/><PARAM id="envsustain" value="50.0"/><PARAM id="envrelease" value="1.546327590942383"/><PARAM id="envshape" value="0.0"/><PARAM id="envgate" value="0.0"/><PARAM id="envretrigonoff" value="1.0"/><PARAM id="envtriggerbutton" value="1.0"/><PARAM id="envtriggerjack" value="1.0"/><PARAM id="envtriggernoteon" value="1.0"/><PARAM id="extend" value="1.0"/><PARAM id="lforate" value="0.4998534023761749"/><PARAM id="lforatesubdivision" value="9.0"/><PARAM id="lfotimemode" value="0.0"/><PARAM id="lfomode" value="0.0"/><PARAM id="lfopolarity" value="0.0"/><PARAM id="lfophase" value="0.0"/><PARAM id="lfotriggerbutton" value="0.0"/><PARAM id="lfotriggerjack" value="0.0"/><PARAM id="lfotriggernoteon" value="0.0"/><PARAM id="rndlforatesync" value="1.0"/><PARAM id="rndrate" value="5.000000476837158"/><PARAM id="rndratesubdivision" value="9.0"/><PARAM id="rndtimemode" value="0.0"/><PARAM id="rndpolarity" value="0.0"/><PARAM id="rnddensity" value="100.0"/><PARAM id="rndsmoothing" value="0.0"/><PARAM id="rndtriggerbutton" value="0.0"/><PARAM id="rndtriggerjack" value="0.0"/><PARAM id="rndtriggernoteon" value="0.0"/><PARAM id="taptempoenable" value="1.0"/><PARAM id="macro" value="100.0"/><PARAM id="mxsource1" value="4.0"/><PARAM id="mxsource2" value="0.0"/><PARAM id="mxsource3" value="0.0"/><PARAM id="mxsource4" value="0.0"/><PARAM id="mxdesta" value="3.0"/><PARAM id="mxdestb" value="4.0"/><PARAM id="mxdestc" value="0.0"/><PARAM id="mxdestd" value="0.0"/><PARAM id="mxnode1a" value="12.49998474121094"/><PARAM id="mxnode1b" value="100.0"/><PARAM id="mxnode1c" value="0.0"/><PARAM id="mxnode1d" value="0.0"/><PARAM id="mxnode2a" value="0.0"/><PARAM id="mxnode2b" value="0.0"/><PARAM id="mxnode2c" value="0.0"/><PARAM id="mxnode2d" value="0.0"/><PARAM id="mxnode3a" value="0.0"/><PARAM id="mxnode3b" value="0.0"/><PARAM id="mxnode3c" value="0.0"/><PARAM id="mxnode3d" value="0.0"/><PARAM id="mxnode4a" value="0.0"/><PARAM id="mxnode4b" value="0.0"/><PARAM id="mxnode4c" value="0.0"/><PARAM id="mxnode4d" value="0.0"/><PARAM id="mxnode1alock" value="0.0"/><PARAM id="mxnode1block" value="0.0"/><PARAM id="mxnode1clock" value="0.0"/><PARAM id="mxnode1dlock" value="0.0"/><PARAM id="mxnode2alock" value="0.0"/><PARAM id="mxnode2block" value="0.0"/><PARAM id="mxnode2clock" value="0.0"/><PARAM id="mxnode2dlock" value="0.0"/><PARAM id="mxnode3alock" value="0.0"/><PARAM id="mxnode3block" value="0.0"/><PARAM id="mxnode3clock" value="0.0"/><PARAM id="mxnode3dlock" value="0.0"/><PARAM id="mxnode4alock" value="0.0"/><PARAM id="mxnode4block" value="0.0"/><PARAM id="mxnode4clock" value="0.0"/><PARAM id="mxnode4dlock" value="0.0"/><PARAM id="monitormix" value="100.0"/><PARAM id="pickupbehaviour" value="0.0"/><Quantiser program="0"/></Parameters><Notes text=""/></SeashellPreset> 
]] },
  [18] = { name = "Dmaj Gen Duophonic", raw = [[
VC2!f  <?xml version="1.0" encoding="UTF-8"?> <SeashellPreset><Version major="2" minor="0" patch="0" tweak="0"/><Parameters><PARAM id="osc1frequency" value="0.1393517255783081"/><PARAM id="osc2frequency" value="-0.2527620196342468"/><PARAM id="lfonoff" value="0.0"/><PARAM id="octaverange" value="5.0"/><PARAM id="sync" value="0.0"/><PARAM id="1voctrouting" value="0.0"/><PARAM id="transpose" value="3.0"/><PARAM id="portamento" value="0.0"/><PARAM id="midipitchbend" value="2.0"/><PARAM id="wavefoldinput" value="0.0"/><PARAM id="folddepth" value="59.50070190429688"/><PARAM id="foldbias" value="0.0"/><PARAM id="foldbiasanimate" value="50.0"/><PARAM id="pulsewidth" value="0.0"/><PARAM id="pwmanimate" value="100.0"/><PARAM id="animateonoff" value="1.0"/><PARAM id="waveformselect" value="0.0"/><PARAM id="filtercutoff" value="50.71720504760742"/><PARAM id="filterkeytrack" value="0.0"/><PARAM id="outputlevel" value="100.0"/><PARAM id="diffuseamount" value="100.0"/><PARAM id="envmode" value="2.0"/><PARAM id="envattack" value="0.2105538249015808"/><PARAM id="envdecay" value="1.534162282943726"/><PARAM id="envsustain" value="50.0"/><PARAM id="envrelease" value="1.534162282943726"/><PARAM id="envshape" value="1.0"/><PARAM id="envgate" value="1.0"/><PARAM id="envretrigonoff" value="1.0"/><PARAM id="envtriggerbutton" value="1.0"/><PARAM id="envtriggerjack" value="1.0"/><PARAM id="envtriggernoteon" value="1.0"/><PARAM id="extend" value="1.0"/><PARAM id="lforate" value="0.5820217132568359"/><PARAM id="lforatesubdivision" value="9.0"/><PARAM id="lfotimemode" value="0.0"/><PARAM id="lfomode" value="0.0"/><PARAM id="lfopolarity" value="0.0"/><PARAM id="lfophase" value="0.0"/><PARAM id="lfotriggerbutton" value="0.0"/><PARAM id="lfotriggerjack" value="0.0"/><PARAM id="lfotriggernoteon" value="0.0"/><PARAM id="rndlforatesync" value="1.0"/><PARAM id="rndrate" value="5.000000476837158"/><PARAM id="rndratesubdivision" value="9.0"/><PARAM id="rndtimemode" value="0.0"/><PARAM id="rndpolarity" value="0.0"/><PARAM id="rnddensity" value="100.0"/><PARAM id="rndsmoothing" value="0.0"/><PARAM id="rndtriggerbutton" value="0.0"/><PARAM id="rndtriggerjack" value="0.0"/><PARAM id="rndtriggernoteon" value="0.0"/><PARAM id="taptempoenable" value="1.0"/><PARAM id="macro" value="99.81687927246094"/><PARAM id="mxsource1" value="0.0"/><PARAM id="mxsource2" value="14.0"/><PARAM id="mxsource3" value="0.0"/><PARAM id="mxsource4" value="4.0"/><PARAM id="mxdesta" value="15.0"/><PARAM id="mxdestb" value="18.0"/><PARAM id="mxdestc" value="21.0"/><PARAM id="mxdestd" value="25.0"/><PARAM id="mxnode1a" value="0.0"/><PARAM id="mxnode1b" value="0.0"/><PARAM id="mxnode1c" value="0.0"/><PARAM id="mxnode1d" value="0.0"/><PARAM id="mxnode2a" value="23.99997711181641"/><PARAM id="mxnode2b" value="-14.00001525878906"/><PARAM id="mxnode2c" value="64.99996948242188"/><PARAM id="mxnode2d" value="0.0"/><PARAM id="mxnode3a" value="0.0"/><PARAM id="mxnode3b" value="0.0"/><PARAM id="mxnode3c" value="0.0"/><PARAM id="mxnode3d" value="0.0"/><PARAM id="mxnode4a" value="0.0"/><PARAM id="mxnode4b" value="29.49996948242188"/><PARAM id="mxnode4c" value="26.49997711181641"/><PARAM id="mxnode4d" value="-100.0"/><PARAM id="mxnode1alock" value="0.0"/><PARAM id="mxnode1block" value="0.0"/><PARAM id="mxnode1clock" value="0.0"/><PARAM id="mxnode1dlock" value="0.0"/><PARAM id="mxnode2alock" value="0.0"/><PARAM id="mxnode2block" value="0.0"/><PARAM id="mxnode2clock" value="0.0"/><PARAM id="mxnode2dlock" value="0.0"/><PARAM id="mxnode3alock" value="0.0"/><PARAM id="mxnode3block" value="0.0"/><PARAM id="mxnode3clock" value="0.0"/><PARAM id="mxnode3dlock" value="0.0"/><PARAM id="mxnode4alock" value="0.0"/><PARAM id="mxnode4block" value="0.0"/><PARAM id="mxnode4clock" value="0.0"/><PARAM id="mxnode4dlock" value="0.0"/><PARAM id="monitormix" value="100.0"/><PARAM id="pickupbehaviour" value="0.0"/><Quantiser program="0"/></Parameters><Notes text=""/></SeashellPreset> 
]] },
  [19] = { name = "Frodo", raw = [[
VC2!\  <?xml version="1.0" encoding="UTF-8"?> <SeashellPreset><Version major="2" minor="0" patch="0" tweak="0"/><Parameters><PARAM id="osc1frequency" value="0.0"/><PARAM id="osc2frequency" value="0.0"/><PARAM id="lfonoff" value="0.0"/><PARAM id="octaverange" value="5.0"/><PARAM id="sync" value="0.0"/><PARAM id="1voctrouting" value="1.0"/><PARAM id="transpose" value="0.0"/><PARAM id="portamento" value="0.0"/><PARAM id="midipitchbend" value="2.0"/><PARAM id="wavefoldinput" value="0.0"/><PARAM id="folddepth" value="72.59353637695312"/><PARAM id="foldbias" value="36.5"/><PARAM id="foldbiasanimate" value="69.25000762939453"/><PARAM id="pulsewidth" value="50.0"/><PARAM id="pwmanimate" value="100.0"/><PARAM id="animateonoff" value="1.0"/><PARAM id="waveformselect" value="0.0"/><PARAM id="filtercutoff" value="27.43372917175293"/><PARAM id="filterkeytrack" value="0.0"/><PARAM id="outputlevel" value="100.0"/><PARAM id="diffuseamount" value="35.75002288818359"/><PARAM id="envmode" value="1.0"/><PARAM id="envattack" value="0.3455523252487183"/><PARAM id="envdecay" value="0.6284205913543701"/><PARAM id="envsustain" value="0.0"/><PARAM id="envrelease" value="0.6036593317985535"/><PARAM id="envshape" value="1.0"/><PARAM id="envgate" value="1.0"/><PARAM id="envretrigonoff" value="1.0"/><PARAM id="envtriggerbutton" value="1.0"/><PARAM id="envtriggerjack" value="1.0"/><PARAM id="envtriggernoteon" value="1.0"/><PARAM id="extend" value="1.0"/><PARAM id="lforate" value="4.6080002784729"/><PARAM id="lforatesubdivision" value="9.0"/><PARAM id="lfotimemode" value="0.0"/><PARAM id="lfomode" value="0.0"/><PARAM id="lfopolarity" value="0.0"/><PARAM id="lfophase" value="0.0"/><PARAM id="lfotriggerbutton" value="0.0"/><PARAM id="lfotriggerjack" value="0.0"/><PARAM id="lfotriggernoteon" value="1.0"/><PARAM id="rndlforatesync" value="1.0"/><PARAM id="rndrate" value="5.000000476837158"/><PARAM id="rndratesubdivision" value="9.0"/><PARAM id="rndtimemode" value="0.0"/><PARAM id="rndpolarity" value="0.0"/><PARAM id="rnddensity" value="100.0"/><PARAM id="rndsmoothing" value="0.0"/><PARAM id="rndtriggerbutton" value="0.0"/><PARAM id="rndtriggerjack" value="0.0"/><PARAM id="rndtriggernoteon" value="0.0"/><PARAM id="taptempoenable" value="1.0"/><PARAM id="macro" value="100.0"/><PARAM id="mxsource1" value="4.0"/><PARAM id="mxsource2" value="14.0"/><PARAM id="mxsource3" value="0.0"/><PARAM id="mxsource4" value="0.0"/><PARAM id="mxdesta" value="3.0"/><PARAM id="mxdestb" value="18.0"/><PARAM id="mxdestc" value="7.0"/><PARAM id="mxdestd" value="6.0"/><PARAM id="mxnode1a" value="16.49998474121094"/><PARAM id="mxnode1b" value="10.99999237060547"/><PARAM id="mxnode1c" value="-47.49997329711914"/><PARAM id="mxnode1d" value="55.99995422363281"/><PARAM id="mxnode2a" value="0.0"/><PARAM id="mxnode2b" value="36.49996948242188"/><PARAM id="mxnode2c" value="0.0"/><PARAM id="mxnode2d" value="28.49996948242188"/><PARAM id="mxnode3a" value="0.0"/><PARAM id="mxnode3b" value="0.0"/><PARAM id="mxnode3c" value="0.0"/><PARAM id="mxnode3d" value="0.0"/><PARAM id="mxnode4a" value="0.0"/><PARAM id="mxnode4b" value="0.0"/><PARAM id="mxnode4c" value="0.0"/><PARAM id="mxnode4d" value="0.0"/><PARAM id="mxnode1alock" value="1.0"/><PARAM id="mxnode1block" value="0.0"/><PARAM id="mxnode1clock" value="0.0"/><PARAM id="mxnode1dlock" value="0.0"/><PARAM id="mxnode2alock" value="0.0"/><PARAM id="mxnode2block" value="0.0"/><PARAM id="mxnode2clock" value="0.0"/><PARAM id="mxnode2dlock" value="0.0"/><PARAM id="mxnode3alock" value="0.0"/><PARAM id="mxnode3block" value="0.0"/><PARAM id="mxnode3clock" value="0.0"/><PARAM id="mxnode3dlock" value="0.0"/><PARAM id="mxnode4alock" value="0.0"/><PARAM id="mxnode4block" value="0.0"/><PARAM id="mxnode4clock" value="0.0"/><PARAM id="mxnode4dlock" value="0.0"/><PARAM id="monitormix" value="100.0"/><PARAM id="pickupbehaviour" value="0.0"/><Quantiser program="0"/></Parameters><Notes text=""/></SeashellPreset> 
]] },
  [20] = { name = "Montage", raw = [[
VC2!6  <?xml version="1.0" encoding="UTF-8"?> <SeashellPreset><Version major="2" minor="0" patch="0" tweak="0"/><Parameters><PARAM id="osc1frequency" value="0.0"/><PARAM id="osc2frequency" value="0.1167805194854736"/><PARAM id="lfonoff" value="0.0"/><PARAM id="octaverange" value="5.0"/><PARAM id="sync" value="0.0"/><PARAM id="1voctrouting" value="3.0"/><PARAM id="transpose" value="0.0"/><PARAM id="portamento" value="0.0"/><PARAM id="midipitchbend" value="2.0"/><PARAM id="wavefoldinput" value="0.0"/><PARAM id="folddepth" value="49.1342658996582"/><PARAM id="foldbias" value="12.24999809265137"/><PARAM id="foldbiasanimate" value="50.0"/><PARAM id="pulsewidth" value="50.0"/><PARAM id="pwmanimate" value="50.0"/><PARAM id="animateonoff" value="0.0"/><PARAM id="waveformselect" value="0.0"/><PARAM id="filtercutoff" value="0.0"/><PARAM id="filterkeytrack" value="0.0"/><PARAM id="outputlevel" value="33.25006103515625"/><PARAM id="diffuseamount" value="18.75"/><PARAM id="envmode" value="1.0"/><PARAM id="envattack" value="0.001425864058546722"/><PARAM id="envdecay" value="0.6368820071220398"/><PARAM id="envsustain" value="50.0"/><PARAM id="envrelease" value="0.6368820071220398"/><PARAM id="envshape" value="0.0"/><PARAM id="envgate" value="1.0"/><PARAM id="envretrigonoff" value="1.0"/><PARAM id="envtriggerbutton" value="1.0"/><PARAM id="envtriggerjack" value="1.0"/><PARAM id="envtriggernoteon" value="1.0"/><PARAM id="extend" value="1.0"/><PARAM id="lforate" value="6.555122375488281"/><PARAM id="lforatesubdivision" value="9.0"/><PARAM id="lfotimemode" value="0.0"/><PARAM id="lfomode" value="0.0"/><PARAM id="lfopolarity" value="1.0"/><PARAM id="lfophase" value="0.0"/><PARAM id="lfotriggerbutton" value="1.0"/><PARAM id="lfotriggerjack" value="1.0"/><PARAM id="lfotriggernoteon" value="1.0"/><PARAM id="rndlforatesync" value="1.0"/><PARAM id="rndrate" value="5.000000476837158"/><PARAM id="rndratesubdivision" value="9.0"/><PARAM id="rndtimemode" value="0.0"/><PARAM id="rndpolarity" value="0.0"/><PARAM id="rnddensity" value="100.0"/><PARAM id="rndsmoothing" value="0.0"/><PARAM id="rndtriggerbutton" value="0.0"/><PARAM id="rndtriggerjack" value="0.0"/><PARAM id="rndtriggernoteon" value="0.0"/><PARAM id="taptempoenable" value="1.0"/><PARAM id="macro" value="100.0"/><PARAM id="mxsource1" value="14.0"/><PARAM id="mxsource2" value="0.0"/><PARAM id="mxsource3" value="0.0"/><PARAM id="mxsource4" value="0.0"/><PARAM id="mxdesta" value="3.0"/><PARAM id="mxdestb" value="7.0"/><PARAM id="mxdestc" value="8.0"/><PARAM id="mxdestd" value="4.0"/><PARAM id="mxnode1a" value="50.0"/><PARAM id="mxnode1b" value="4.499992370605469"/><PARAM id="mxnode1c" value="-5.499984741210938"/><PARAM id="mxnode1d" value="60.99996948242188"/><PARAM id="mxnode2a" value="0.0"/><PARAM id="mxnode2b" value="0.0"/><PARAM id="mxnode2c" value="0.0"/><PARAM id="mxnode2d" value="0.0"/><PARAM id="mxnode3a" value="0.0"/><PARAM id="mxnode3b" value="0.0"/><PARAM id="mxnode3c" value="0.0"/><PARAM id="mxnode3d" value="0.0"/><PARAM id="mxnode4a" value="0.0"/><PARAM id="mxnode4b" value="0.0"/><PARAM id="mxnode4c" value="0.0"/><PARAM id="mxnode4d" value="0.0"/><PARAM id="mxnode1alock" value="0.0"/><PARAM id="mxnode1block" value="0.0"/><PARAM id="mxnode1clock" value="0.0"/><PARAM id="mxnode1dlock" value="0.0"/><PARAM id="mxnode2alock" value="0.0"/><PARAM id="mxnode2block" value="0.0"/><PARAM id="mxnode2clock" value="0.0"/><PARAM id="mxnode2dlock" value="0.0"/><PARAM id="mxnode3alock" value="0.0"/><PARAM id="mxnode3block" value="0.0"/><PARAM id="mxnode3clock" value="0.0"/><PARAM id="mxnode3dlock" value="0.0"/><PARAM id="mxnode4alock" value="0.0"/><PARAM id="mxnode4block" value="0.0"/><PARAM id="mxnode4clock" value="0.0"/><PARAM id="mxnode4dlock" value="0.0"/><PARAM id="monitormix" value="100.0"/><PARAM id="pickupbehaviour" value="0.0"/><Quantiser program="0"/></Parameters><Notes text=""/></SeashellPreset> 
]] },
  [21] = { name = "Rando Calrissian", raw = [[
VC2!  <?xml version="1.0" encoding="UTF-8"?> <SeashellPreset><Version major="2" minor="0" patch="0" tweak="0"/><Parameters><PARAM id="osc1frequency" value="-0.0100712776184082"/><PARAM id="osc2frequency" value="0.0"/><PARAM id="lfonoff" value="0.0"/><PARAM id="octaverange" value="5.0"/><PARAM id="sync" value="1.0"/><PARAM id="1voctrouting" value="3.0"/><PARAM id="transpose" value="0.0"/><PARAM id="portamento" value="0.0"/><PARAM id="midipitchbend" value="2.0"/><PARAM id="wavefoldinput" value="1.0"/><PARAM id="folddepth" value="0.1342855393886566"/><PARAM id="foldbias" value="0.0"/><PARAM id="foldbiasanimate" value="100.0"/><PARAM id="pulsewidth" value="50.0"/><PARAM id="pwmanimate" value="100.0"/><PARAM id="animateonoff" value="0.0"/><PARAM id="waveformselect" value="3.0"/><PARAM id="filtercutoff" value="41.57968902587891"/><PARAM id="filterkeytrack" value="0.0"/><PARAM id="outputlevel" value="100.0"/><PARAM id="diffuseamount" value="37.5"/><PARAM id="envmode" value="1.0"/><PARAM id="envattack" value="0.001425863825716078"/><PARAM id="envdecay" value="0.2141739130020142"/><PARAM id="envsustain" value="51.7500114440918"/><PARAM id="envrelease" value="0.2141739130020142"/><PARAM id="envshape" value="1.0"/><PARAM id="envgate" value="1.0"/><PARAM id="envretrigonoff" value="1.0"/><PARAM id="envtriggerbutton" value="1.0"/><PARAM id="envtriggerjack" value="1.0"/><PARAM id="envtriggernoteon" value="1.0"/><PARAM id="extend" value="1.0"/><PARAM id="lforate" value="8.0"/><PARAM id="lforatesubdivision" value="15.0"/><PARAM id="lfotimemode" value="0.0"/><PARAM id="lfomode" value="0.0"/><PARAM id="lfopolarity" value="0.0"/><PARAM id="lfophase" value="0.0"/><PARAM id="lfotriggerbutton" value="1.0"/><PARAM id="lfotriggerjack" value="1.0"/><PARAM id="lfotriggernoteon" value="1.0"/><PARAM id="rndlforatesync" value="1.0"/><PARAM id="rndrate" value="5.000000476837158"/><PARAM id="rndratesubdivision" value="9.0"/><PARAM id="rndtimemode" value="0.0"/><PARAM id="rndpolarity" value="0.0"/><PARAM id="rnddensity" value="100.0"/><PARAM id="rndsmoothing" value="0.0"/><PARAM id="rndtriggerbutton" value="0.0"/><PARAM id="rndtriggerjack" value="0.0"/><PARAM id="rndtriggernoteon" value="0.0"/><PARAM id="taptempoenable" value="1.0"/><PARAM id="macro" value="100.0"/><PARAM id="mxsource1" value="14.0"/><PARAM id="mxsource2" value="4.0"/><PARAM id="mxsource3" value="0.0"/><PARAM id="mxsource4" value="0.0"/><PARAM id="mxdesta" value="3.0"/><PARAM id="mxdestb" value="14.0"/><PARAM id="mxdestc" value="0.0"/><PARAM id="mxdestd" value="0.0"/><PARAM id="mxnode1a" value="58.0"/><PARAM id="mxnode1b" value="60.5"/><PARAM id="mxnode1c" value="0.0"/><PARAM id="mxnode1d" value="0.0"/><PARAM id="mxnode2a" value="25.49997711181641"/><PARAM id="mxnode2b" value="0.0"/><PARAM id="mxnode2c" value="0.0"/><PARAM id="mxnode2d" value="0.0"/><PARAM id="mxnode3a" value="0.0"/><PARAM id="mxnode3b" value="0.0"/><PARAM id="mxnode3c" value="0.0"/><PARAM id="mxnode3d" value="0.0"/><PARAM id="mxnode4a" value="0.0"/><PARAM id="mxnode4b" value="0.0"/><PARAM id="mxnode4c" value="0.0"/><PARAM id="mxnode4d" value="0.0"/><PARAM id="mxnode1alock" value="0.0"/><PARAM id="mxnode1block" value="0.0"/><PARAM id="mxnode1clock" value="0.0"/><PARAM id="mxnode1dlock" value="0.0"/><PARAM id="mxnode2alock" value="0.0"/><PARAM id="mxnode2block" value="0.0"/><PARAM id="mxnode2clock" value="0.0"/><PARAM id="mxnode2dlock" value="0.0"/><PARAM id="mxnode3alock" value="0.0"/><PARAM id="mxnode3block" value="0.0"/><PARAM id="mxnode3clock" value="0.0"/><PARAM id="mxnode3dlock" value="0.0"/><PARAM id="mxnode4alock" value="0.0"/><PARAM id="mxnode4block" value="0.0"/><PARAM id="mxnode4clock" value="0.0"/><PARAM id="mxnode4dlock" value="0.0"/><PARAM id="monitormix" value="100.0"/><PARAM id="pickupbehaviour" value="0.0"/><Quantiser program="0"/></Parameters><Notes text=""/></SeashellPreset> 
]] },
  [22] = { name = "Rhythmic FC", raw = [[
VC2!i  <?xml version="1.0" encoding="UTF-8"?> <SeashellPreset><Version major="2" minor="0" patch="0" tweak="0"/><Parameters><PARAM id="osc1frequency" value="-0.2250012159347534"/><PARAM id="osc2frequency" value="-0.3349959850311279"/><PARAM id="lfonoff" value="0.0"/><PARAM id="octaverange" value="5.0"/><PARAM id="sync" value="0.0"/><PARAM id="1voctrouting" value="3.0"/><PARAM id="transpose" value="3.0"/><PARAM id="portamento" value="0.0"/><PARAM id="midipitchbend" value="2.0"/><PARAM id="wavefoldinput" value="0.0"/><PARAM id="folddepth" value="22.91399765014648"/><PARAM id="foldbias" value="0.0"/><PARAM id="foldbiasanimate" value="0.0"/><PARAM id="pulsewidth" value="24.0"/><PARAM id="pwmanimate" value="50.0"/><PARAM id="animateonoff" value="1.0"/><PARAM id="waveformselect" value="0.0"/><PARAM id="filtercutoff" value="3.418177366256714"/><PARAM id="filterkeytrack" value="0.0"/><PARAM id="outputlevel" value="100.0"/><PARAM id="diffuseamount" value="15.75000762939453"/><PARAM id="envmode" value="1.0"/><PARAM id="envattack" value="0.0"/><PARAM id="envdecay" value="0.6312680244445801"/><PARAM id="envsustain" value="0.500028133392334"/><PARAM id="envrelease" value="0.4722370207309723"/><PARAM id="envshape" value="1.0"/><PARAM id="envgate" value="1.0"/><PARAM id="envretrigonoff" value="1.0"/><PARAM id="envtriggerbutton" value="1.0"/><PARAM id="envtriggerjack" value="1.0"/><PARAM id="envtriggernoteon" value="1.0"/><PARAM id="extend" value="1.0"/><PARAM id="lforate" value="6.83451509475708"/><PARAM id="lforatesubdivision" value="15.0"/><PARAM id="lfotimemode" value="0.0"/><PARAM id="lfomode" value="0.0"/><PARAM id="lfopolarity" value="1.0"/><PARAM id="lfophase" value="0.0"/><PARAM id="lfotriggerbutton" value="0.0"/><PARAM id="lfotriggerjack" value="0.0"/><PARAM id="lfotriggernoteon" value="1.0"/><PARAM id="rndlforatesync" value="1.0"/><PARAM id="rndrate" value="5.000000476837158"/><PARAM id="rndratesubdivision" value="9.0"/><PARAM id="rndtimemode" value="0.0"/><PARAM id="rndpolarity" value="0.0"/><PARAM id="rnddensity" value="100.0"/><PARAM id="rndsmoothing" value="0.0"/><PARAM id="rndtriggerbutton" value="0.0"/><PARAM id="rndtriggerjack" value="0.0"/><PARAM id="rndtriggernoteon" value="0.0"/><PARAM id="taptempoenable" value="1.0"/><PARAM id="macro" value="99.981689453125"/><PARAM id="mxsource1" value="4.0"/><PARAM id="mxsource2" value="14.0"/><PARAM id="mxsource3" value="2.0"/><PARAM id="mxsource4" value="0.0"/><PARAM id="mxdesta" value="3.0"/><PARAM id="mxdestb" value="7.0"/><PARAM id="mxdestc" value="6.0"/><PARAM id="mxdestd" value="25.0"/><PARAM id="mxnode1a" value="28.99996948242188"/><PARAM id="mxnode1b" value="6.999946594238281"/><PARAM id="mxnode1c" value="0.0"/><PARAM id="mxnode1d" value="0.0"/><PARAM id="mxnode2a" value="26.99997711181641"/><PARAM id="mxnode2b" value="-19.49998474121094"/><PARAM id="mxnode2c" value="33.50004577636719"/><PARAM id="mxnode2d" value="0.0"/><PARAM id="mxnode3a" value="0.0"/><PARAM id="mxnode3b" value="0.0"/><PARAM id="mxnode3c" value="0.0"/><PARAM id="mxnode3d" value="0.0"/><PARAM id="mxnode4a" value="0.0"/><PARAM id="mxnode4b" value="0.0"/><PARAM id="mxnode4c" value="0.0"/><PARAM id="mxnode4d" value="0.0"/><PARAM id="mxnode1alock" value="1.0"/><PARAM id="mxnode1block" value="1.0"/><PARAM id="mxnode1clock" value="0.0"/><PARAM id="mxnode1dlock" value="0.0"/><PARAM id="mxnode2alock" value="0.0"/><PARAM id="mxnode2block" value="0.0"/><PARAM id="mxnode2clock" value="0.0"/><PARAM id="mxnode2dlock" value="0.0"/><PARAM id="mxnode3alock" value="0.0"/><PARAM id="mxnode3block" value="0.0"/><PARAM id="mxnode3clock" value="0.0"/><PARAM id="mxnode3dlock" value="0.0"/><PARAM id="mxnode4alock" value="0.0"/><PARAM id="mxnode4block" value="0.0"/><PARAM id="mxnode4clock" value="0.0"/><PARAM id="mxnode4dlock" value="0.0"/><PARAM id="monitormix" value="100.0"/><PARAM id="pickupbehaviour" value="0.0"/><Quantiser program="0"/></Parameters><Notes text=""/></SeashellPreset> 
]] },
  [23] = { name = "Kick", raw = [[
VC2!  <?xml version="1.0" encoding="UTF-8"?> <SeashellPreset><Version major="2" minor="0" patch="0" tweak="0"/><Parameters><PARAM id="osc1frequency" value="-1.0"/><PARAM id="osc2frequency" value="-1.0"/><PARAM id="lfonoff" value="0.0"/><PARAM id="octaverange" value="5.0"/><PARAM id="sync" value="0.0"/><PARAM id="1voctrouting" value="0.0"/><PARAM id="transpose" value="0.0"/><PARAM id="portamento" value="0.0"/><PARAM id="midipitchbend" value="2.0"/><PARAM id="wavefoldinput" value="0.0"/><PARAM id="folddepth" value="41.96422958374023"/><PARAM id="foldbias" value="0.25"/><PARAM id="foldbiasanimate" value="50.0"/><PARAM id="pulsewidth" value="23.25000762939453"/><PARAM id="pwmanimate" value="50.0"/><PARAM id="animateonoff" value="0.0"/><PARAM id="waveformselect" value="4.0"/><PARAM id="filtercutoff" value="28.74998092651367"/><PARAM id="filterkeytrack" value="0.0"/><PARAM id="outputlevel" value="0.0"/><PARAM id="diffuseamount" value="0.0"/><PARAM id="envmode" value="1.0"/><PARAM id="envattack" value="0.002378250472247601"/><PARAM id="envdecay" value="0.3995509147644043"/><PARAM id="envsustain" value="0.0"/><PARAM id="envrelease" value="1.664509892463684"/><PARAM id="envshape" value="1.0"/><PARAM id="envgate" value="0.0"/><PARAM id="envretrigonoff" value="1.0"/><PARAM id="envtriggerbutton" value="1.0"/><PARAM id="envtriggerjack" value="1.0"/><PARAM id="envtriggernoteon" value="1.0"/><PARAM id="extend" value="1.0"/><PARAM id="lforate" value="8.860222816467285"/><PARAM id="lforatesubdivision" value="9.0"/><PARAM id="lfotimemode" value="0.0"/><PARAM id="lfomode" value="2.0"/><PARAM id="lfopolarity" value="1.0"/><PARAM id="lfophase" value="0.0"/><PARAM id="lfotriggerbutton" value="0.0"/><PARAM id="lfotriggerjack" value="0.0"/><PARAM id="lfotriggernoteon" value="1.0"/><PARAM id="rndlforatesync" value="1.0"/><PARAM id="rndrate" value="5.000000476837158"/><PARAM id="rndratesubdivision" value="9.0"/><PARAM id="rndtimemode" value="0.0"/><PARAM id="rndpolarity" value="0.0"/><PARAM id="rnddensity" value="100.0"/><PARAM id="rndsmoothing" value="0.0"/><PARAM id="rndtriggerbutton" value="0.0"/><PARAM id="rndtriggerjack" value="0.0"/><PARAM id="rndtriggernoteon" value="0.0"/><PARAM id="taptempoenable" value="1.0"/><PARAM id="macro" value="100.0"/><PARAM id="mxsource1" value="4.0"/><PARAM id="mxsource2" value="13.0"/><PARAM id="mxsource3" value="0.0"/><PARAM id="mxsource4" value="0.0"/><PARAM id="mxdesta" value="14.0"/><PARAM id="mxdestb" value="4.0"/><PARAM id="mxdestc" value="7.0"/><PARAM id="mxdestd" value="0.0"/><PARAM id="mxnode1a" value="51.49996948242188"/><PARAM id="mxnode1b" value="100.0"/><PARAM id="mxnode1c" value="0.0"/><PARAM id="mxnode1d" value="0.0"/><PARAM id="mxnode2a" value="0.0"/><PARAM id="mxnode2b" value="0.0"/><PARAM id="mxnode2c" value="-75.49997711181641"/><PARAM id="mxnode2d" value="0.0"/><PARAM id="mxnode3a" value="0.0"/><PARAM id="mxnode3b" value="0.0"/><PARAM id="mxnode3c" value="0.0"/><PARAM id="mxnode3d" value="0.0"/><PARAM id="mxnode4a" value="0.0"/><PARAM id="mxnode4b" value="0.0"/><PARAM id="mxnode4c" value="0.0"/><PARAM id="mxnode4d" value="0.0"/><PARAM id="mxnode1alock" value="0.0"/><PARAM id="mxnode1block" value="0.0"/><PARAM id="mxnode1clock" value="0.0"/><PARAM id="mxnode1dlock" value="0.0"/><PARAM id="mxnode2alock" value="0.0"/><PARAM id="mxnode2block" value="0.0"/><PARAM id="mxnode2clock" value="0.0"/><PARAM id="mxnode2dlock" value="0.0"/><PARAM id="mxnode3alock" value="0.0"/><PARAM id="mxnode3block" value="0.0"/><PARAM id="mxnode3clock" value="0.0"/><PARAM id="mxnode3dlock" value="0.0"/><PARAM id="mxnode4alock" value="0.0"/><PARAM id="mxnode4block" value="0.0"/><PARAM id="mxnode4clock" value="0.0"/><PARAM id="mxnode4dlock" value="0.0"/><PARAM id="monitormix" value="100.0"/><PARAM id="pickupbehaviour" value="0.0"/><Quantiser program="0"/></Parameters><Notes text=""/></SeashellPreset> 
]] },
  [24] = { name = "Snare", raw = [[
VC2!0  <?xml version="1.0" encoding="UTF-8"?> <SeashellPreset><Version major="2" minor="0" patch="0" tweak="0"/><Parameters><PARAM id="osc1frequency" value="0.5800004005432129"/><PARAM id="osc2frequency" value="0.1092681884765625"/><PARAM id="lfonoff" value="0.0"/><PARAM id="octaverange" value="5.0"/><PARAM id="sync" value="0.0"/><PARAM id="1voctrouting" value="0.0"/><PARAM id="transpose" value="0.0"/><PARAM id="portamento" value="0.0"/><PARAM id="midipitchbend" value="2.0"/><PARAM id="wavefoldinput" value="1.0"/><PARAM id="folddepth" value="95.34766387939453"/><PARAM id="foldbias" value="100.0"/><PARAM id="foldbiasanimate" value="100.0"/><PARAM id="pulsewidth" value="0.0"/><PARAM id="pwmanimate" value="50.0"/><PARAM id="animateonoff" value="1.0"/><PARAM id="waveformselect" value="4.0"/><PARAM id="filtercutoff" value="51.29707336425781"/><PARAM id="filterkeytrack" value="0.0"/><PARAM id="outputlevel" value="0.0"/><PARAM id="diffuseamount" value="0.25"/><PARAM id="envmode" value="0.0"/><PARAM id="envattack" value="0.00108607835136354"/><PARAM id="envdecay" value="0.1974319219589233"/><PARAM id="envsustain" value="100.0"/><PARAM id="envrelease" value="0.09692041575908661"/><PARAM id="envshape" value="1.0"/><PARAM id="envgate" value="1.0"/><PARAM id="envretrigonoff" value="1.0"/><PARAM id="envtriggerbutton" value="1.0"/><PARAM id="envtriggerjack" value="1.0"/><PARAM id="envtriggernoteon" value="1.0"/><PARAM id="extend" value="1.0"/><PARAM id="lforate" value="0.4998534023761749"/><PARAM id="lforatesubdivision" value="9.0"/><PARAM id="lfotimemode" value="0.0"/><PARAM id="lfomode" value="0.0"/><PARAM id="lfopolarity" value="0.0"/><PARAM id="lfophase" value="0.0"/><PARAM id="lfotriggerbutton" value="0.0"/><PARAM id="lfotriggerjack" value="0.0"/><PARAM id="lfotriggernoteon" value="0.0"/><PARAM id="rndlforatesync" value="1.0"/><PARAM id="rndrate" value="5.000000476837158"/><PARAM id="rndratesubdivision" value="9.0"/><PARAM id="rndtimemode" value="0.0"/><PARAM id="rndpolarity" value="0.0"/><PARAM id="rnddensity" value="100.0"/><PARAM id="rndsmoothing" value="0.0"/><PARAM id="rndtriggerbutton" value="0.0"/><PARAM id="rndtriggerjack" value="0.0"/><PARAM id="rndtriggernoteon" value="0.0"/><PARAM id="taptempoenable" value="1.0"/><PARAM id="macro" value="99.81687927246094"/><PARAM id="mxsource1" value="4.0"/><PARAM id="mxsource2" value="2.0"/><PARAM id="mxsource3" value="0.0"/><PARAM id="mxsource4" value="0.0"/><PARAM id="mxdesta" value="3.0"/><PARAM id="mxdestb" value="14.0"/><PARAM id="mxdestc" value="2.0"/><PARAM id="mxdestd" value="4.0"/><PARAM id="mxnode1a" value="100.0"/><PARAM id="mxnode1b" value="-18.49994659423828"/><PARAM id="mxnode1c" value="100.0"/><PARAM id="mxnode1d" value="100.0"/><PARAM id="mxnode2a" value="0.0"/><PARAM id="mxnode2b" value="0.0"/><PARAM id="mxnode2c" value="0.0"/><PARAM id="mxnode2d" value="0.0"/><PARAM id="mxnode3a" value="0.0"/><PARAM id="mxnode3b" value="0.0"/><PARAM id="mxnode3c" value="0.0"/><PARAM id="mxnode3d" value="0.0"/><PARAM id="mxnode4a" value="0.0"/><PARAM id="mxnode4b" value="0.0"/><PARAM id="mxnode4c" value="0.0"/><PARAM id="mxnode4d" value="0.0"/><PARAM id="mxnode1alock" value="0.0"/><PARAM id="mxnode1block" value="0.0"/><PARAM id="mxnode1clock" value="0.0"/><PARAM id="mxnode1dlock" value="0.0"/><PARAM id="mxnode2alock" value="0.0"/><PARAM id="mxnode2block" value="0.0"/><PARAM id="mxnode2clock" value="0.0"/><PARAM id="mxnode2dlock" value="0.0"/><PARAM id="mxnode3alock" value="0.0"/><PARAM id="mxnode3block" value="0.0"/><PARAM id="mxnode3clock" value="0.0"/><PARAM id="mxnode3dlock" value="0.0"/><PARAM id="mxnode4alock" value="0.0"/><PARAM id="mxnode4block" value="0.0"/><PARAM id="mxnode4clock" value="0.0"/><PARAM id="mxnode4dlock" value="0.0"/><PARAM id="monitormix" value="100.0"/><PARAM id="pickupbehaviour" value="0.0"/><Quantiser program="0"/></Parameters><Notes text=""/></SeashellPreset> 
]] },
  [25] = { name = "Sourdrum Starter", raw = [[
VC2!  <?xml version="1.0" encoding="UTF-8"?> <SeashellPreset><Version major="2" minor="0" patch="0" tweak="0"/><Parameters><PARAM id="osc1frequency" value="0.0"/><PARAM id="osc2frequency" value="0.0"/><PARAM id="lfonoff" value="0.0"/><PARAM id="octaverange" value="5.0"/><PARAM id="sync" value="0.0"/><PARAM id="1voctrouting" value="3.0"/><PARAM id="transpose" value="0.0"/><PARAM id="portamento" value="0.0"/><PARAM id="midipitchbend" value="2.0"/><PARAM id="wavefoldinput" value="0.0"/><PARAM id="folddepth" value="0.0"/><PARAM id="foldbias" value="0.0"/><PARAM id="foldbiasanimate" value="50.0"/><PARAM id="pulsewidth" value="50.0"/><PARAM id="pwmanimate" value="50.0"/><PARAM id="animateonoff" value="0.0"/><PARAM id="waveformselect" value="0.0"/><PARAM id="filtercutoff" value="25.82555198669434"/><PARAM id="filterkeytrack" value="0.0"/><PARAM id="outputlevel" value="0.0"/><PARAM id="diffuseamount" value="20.00002288818359"/><PARAM id="envmode" value="1.0"/><PARAM id="envattack" value="0.0"/><PARAM id="envdecay" value="0.285179615020752"/><PARAM id="envsustain" value="3.749993324279785"/><PARAM id="envrelease" value="1.688738226890564"/><PARAM id="envshape" value="1.0"/><PARAM id="envgate" value="0.0"/><PARAM id="envretrigonoff" value="1.0"/><PARAM id="envtriggerbutton" value="1.0"/><PARAM id="envtriggerjack" value="1.0"/><PARAM id="envtriggernoteon" value="1.0"/><PARAM id="extend" value="1.0"/><PARAM id="lforate" value="2.003450155258179"/><PARAM id="lforatesubdivision" value="9.0"/><PARAM id="lfotimemode" value="0.0"/><PARAM id="lfomode" value="2.0"/><PARAM id="lfopolarity" value="0.0"/><PARAM id="lfophase" value="0.0"/><PARAM id="lfotriggerbutton" value="1.0"/><PARAM id="lfotriggerjack" value="1.0"/><PARAM id="lfotriggernoteon" value="1.0"/><PARAM id="rndlforatesync" value="1.0"/><PARAM id="rndrate" value="5.000000476837158"/><PARAM id="rndratesubdivision" value="9.0"/><PARAM id="rndtimemode" value="0.0"/><PARAM id="rndpolarity" value="0.0"/><PARAM id="rnddensity" value="100.0"/><PARAM id="rndsmoothing" value="0.0"/><PARAM id="rndtriggerbutton" value="0.0"/><PARAM id="rndtriggerjack" value="0.0"/><PARAM id="rndtriggernoteon" value="0.0"/><PARAM id="taptempoenable" value="1.0"/><PARAM id="macro" value="100.0"/><PARAM id="mxsource1" value="4.0"/><PARAM id="mxsource2" value="13.0"/><PARAM id="mxsource3" value="0.0"/><PARAM id="mxsource4" value="0.0"/><PARAM id="mxdesta" value="11.0"/><PARAM id="mxdestb" value="3.0"/><PARAM id="mxdestc" value="7.0"/><PARAM id="mxdestd" value="4.0"/><PARAM id="mxnode1a" value="35.49996948242188"/><PARAM id="mxnode1b" value="15.99998474121094"/><PARAM id="mxnode1c" value="25.0"/><PARAM id="mxnode1d" value="0.0"/><PARAM id="mxnode2a" value="0.0"/><PARAM id="mxnode2b" value="0.0"/><PARAM id="mxnode2c" value="0.0"/><PARAM id="mxnode2d" value="100.0"/><PARAM id="mxnode3a" value="0.0"/><PARAM id="mxnode3b" value="0.0"/><PARAM id="mxnode3c" value="0.0"/><PARAM id="mxnode3d" value="0.0"/><PARAM id="mxnode4a" value="0.0"/><PARAM id="mxnode4b" value="0.0"/><PARAM id="mxnode4c" value="0.0"/><PARAM id="mxnode4d" value="0.0"/><PARAM id="mxnode1alock" value="0.0"/><PARAM id="mxnode1block" value="0.0"/><PARAM id="mxnode1clock" value="0.0"/><PARAM id="mxnode1dlock" value="0.0"/><PARAM id="mxnode2alock" value="0.0"/><PARAM id="mxnode2block" value="0.0"/><PARAM id="mxnode2clock" value="0.0"/><PARAM id="mxnode2dlock" value="0.0"/><PARAM id="mxnode3alock" value="0.0"/><PARAM id="mxnode3block" value="0.0"/><PARAM id="mxnode3clock" value="0.0"/><PARAM id="mxnode3dlock" value="0.0"/><PARAM id="mxnode4alock" value="0.0"/><PARAM id="mxnode4block" value="0.0"/><PARAM id="mxnode4clock" value="0.0"/><PARAM id="mxnode4dlock" value="0.0"/><PARAM id="monitormix" value="100.0"/><PARAM id="pickupbehaviour" value="0.0"/><Quantiser program="0"/></Parameters><Notes text=""/></SeashellPreset> 
]] },
  [26] = { name = "Stone Table", raw = [[
VC2!ú  <?xml version="1.0" encoding="UTF-8"?> <SeashellPreset><Version major="2" minor="0" patch="0" tweak="0"/><Parameters><PARAM id="osc1frequency" value="0.0"/><PARAM id="osc2frequency" value="0.0"/><PARAM id="lfonoff" value="0.0"/><PARAM id="octaverange" value="5.0"/><PARAM id="sync" value="0.0"/><PARAM id="1voctrouting" value="3.0"/><PARAM id="transpose" value="0.0"/><PARAM id="portamento" value="0.0"/><PARAM id="midipitchbend" value="2.0"/><PARAM id="wavefoldinput" value="0.0"/><PARAM id="folddepth" value="0.0"/><PARAM id="foldbias" value="0.0"/><PARAM id="foldbiasanimate" value="50.0"/><PARAM id="pulsewidth" value="50.0"/><PARAM id="pwmanimate" value="50.0"/><PARAM id="animateonoff" value="0.0"/><PARAM id="waveformselect" value="0.0"/><PARAM id="filtercutoff" value="25.82555198669434"/><PARAM id="filterkeytrack" value="0.0"/><PARAM id="outputlevel" value="0.0"/><PARAM id="diffuseamount" value="100.0"/><PARAM id="envmode" value="1.0"/><PARAM id="envattack" value="0.0"/><PARAM id="envdecay" value="0.285179615020752"/><PARAM id="envsustain" value="3.749993324279785"/><PARAM id="envrelease" value="1.688738226890564"/><PARAM id="envshape" value="1.0"/><PARAM id="envgate" value="0.0"/><PARAM id="envretrigonoff" value="1.0"/><PARAM id="envtriggerbutton" value="1.0"/><PARAM id="envtriggerjack" value="1.0"/><PARAM id="envtriggernoteon" value="1.0"/><PARAM id="extend" value="1.0"/><PARAM id="lforate" value="2.003450155258179"/><PARAM id="lforatesubdivision" value="9.0"/><PARAM id="lfotimemode" value="0.0"/><PARAM id="lfomode" value="2.0"/><PARAM id="lfopolarity" value="0.0"/><PARAM id="lfophase" value="0.0"/><PARAM id="lfotriggerbutton" value="1.0"/><PARAM id="lfotriggerjack" value="1.0"/><PARAM id="lfotriggernoteon" value="1.0"/><PARAM id="rndlforatesync" value="1.0"/><PARAM id="rndrate" value="5.000000476837158"/><PARAM id="rndratesubdivision" value="9.0"/><PARAM id="rndtimemode" value="0.0"/><PARAM id="rndpolarity" value="0.0"/><PARAM id="rnddensity" value="100.0"/><PARAM id="rndsmoothing" value="0.0"/><PARAM id="rndtriggerbutton" value="0.0"/><PARAM id="rndtriggerjack" value="0.0"/><PARAM id="rndtriggernoteon" value="0.0"/><PARAM id="taptempoenable" value="1.0"/><PARAM id="macro" value="100.0"/><PARAM id="mxsource1" value="4.0"/><PARAM id="mxsource2" value="13.0"/><PARAM id="mxsource3" value="0.0"/><PARAM id="mxsource4" value="0.0"/><PARAM id="mxdesta" value="11.0"/><PARAM id="mxdestb" value="3.0"/><PARAM id="mxdestc" value="7.0"/><PARAM id="mxdestd" value="4.0"/><PARAM id="mxnode1a" value="35.49996948242188"/><PARAM id="mxnode1b" value="15.99998474121094"/><PARAM id="mxnode1c" value="25.0"/><PARAM id="mxnode1d" value="0.0"/><PARAM id="mxnode2a" value="0.0"/><PARAM id="mxnode2b" value="0.0"/><PARAM id="mxnode2c" value="0.0"/><PARAM id="mxnode2d" value="100.0"/><PARAM id="mxnode3a" value="0.0"/><PARAM id="mxnode3b" value="0.0"/><PARAM id="mxnode3c" value="0.0"/><PARAM id="mxnode3d" value="0.0"/><PARAM id="mxnode4a" value="0.0"/><PARAM id="mxnode4b" value="0.0"/><PARAM id="mxnode4c" value="0.0"/><PARAM id="mxnode4d" value="0.0"/><PARAM id="mxnode1alock" value="0.0"/><PARAM id="mxnode1block" value="0.0"/><PARAM id="mxnode1clock" value="0.0"/><PARAM id="mxnode1dlock" value="0.0"/><PARAM id="mxnode2alock" value="0.0"/><PARAM id="mxnode2block" value="0.0"/><PARAM id="mxnode2clock" value="0.0"/><PARAM id="mxnode2dlock" value="0.0"/><PARAM id="mxnode3alock" value="0.0"/><PARAM id="mxnode3block" value="0.0"/><PARAM id="mxnode3clock" value="0.0"/><PARAM id="mxnode3dlock" value="0.0"/><PARAM id="mxnode4alock" value="0.0"/><PARAM id="mxnode4block" value="0.0"/><PARAM id="mxnode4clock" value="0.0"/><PARAM id="mxnode4dlock" value="0.0"/><PARAM id="monitormix" value="100.0"/><PARAM id="pickupbehaviour" value="0.0"/><Quantiser program="0"/></Parameters><Notes text=""/></SeashellPreset> 
]] },
  [27] = { name = "Brassy", raw = [[
VC2!@  <?xml version="1.0" encoding="UTF-8"?> <SeashellPreset><Version major="2" minor="0" patch="0" tweak="0"/><Parameters><PARAM id="osc1frequency" value="0.0"/><PARAM id="osc2frequency" value="0.0"/><PARAM id="lfonoff" value="0.0"/><PARAM id="octaverange" value="5.0"/><PARAM id="sync" value="0.0"/><PARAM id="1voctrouting" value="3.0"/><PARAM id="transpose" value="0.0"/><PARAM id="portamento" value="0.0"/><PARAM id="midipitchbend" value="2.0"/><PARAM id="wavefoldinput" value="0.0"/><PARAM id="folddepth" value="0.2502593994140625"/><PARAM id="foldbias" value="0.0"/><PARAM id="foldbiasanimate" value="99.57273101806641"/><PARAM id="pulsewidth" value="50.0"/><PARAM id="pwmanimate" value="99.57273101806641"/><PARAM id="animateonoff" value="1.0"/><PARAM id="waveformselect" value="1.0"/><PARAM id="filtercutoff" value="18.69010543823242"/><PARAM id="filterkeytrack" value="22.49997711181641"/><PARAM id="outputlevel" value="100.0"/><PARAM id="diffuseamount" value="0.0"/><PARAM id="envmode" value="1.0"/><PARAM id="envattack" value="0.1465429216623306"/><PARAM id="envdecay" value="0.2672066986560822"/><PARAM id="envsustain" value="50.0"/><PARAM id="envrelease" value="0.2672066986560822"/><PARAM id="envshape" value="1.0"/><PARAM id="envgate" value="1.0"/><PARAM id="envretrigonoff" value="1.0"/><PARAM id="envtriggerbutton" value="1.0"/><PARAM id="envtriggerjack" value="1.0"/><PARAM id="envtriggernoteon" value="1.0"/><PARAM id="extend" value="1.0"/><PARAM id="lforate" value="5.112433910369873"/><PARAM id="lforatesubdivision" value="9.0"/><PARAM id="lfotimemode" value="0.0"/><PARAM id="lfomode" value="2.0"/><PARAM id="lfopolarity" value="1.0"/><PARAM id="lfophase" value="0.0"/><PARAM id="lfotriggerbutton" value="0.0"/><PARAM id="lfotriggerjack" value="0.0"/><PARAM id="lfotriggernoteon" value="1.0"/><PARAM id="rndlforatesync" value="1.0"/><PARAM id="rndrate" value="5.000000476837158"/><PARAM id="rndratesubdivision" value="9.0"/><PARAM id="rndtimemode" value="0.0"/><PARAM id="rndpolarity" value="0.0"/><PARAM id="rnddensity" value="100.0"/><PARAM id="rndsmoothing" value="0.0"/><PARAM id="rndtriggerbutton" value="0.0"/><PARAM id="rndtriggerjack" value="0.0"/><PARAM id="rndtriggernoteon" value="0.0"/><PARAM id="taptempoenable" value="1.0"/><PARAM id="macro" value="100.0"/><PARAM id="mxsource1" value="4.0"/><PARAM id="mxsource2" value="13.0"/><PARAM id="mxsource3" value="0.0"/><PARAM id="mxsource4" value="0.0"/><PARAM id="mxdesta" value="3.0"/><PARAM id="mxdestb" value="16.0"/><PARAM id="mxdestc" value="6.0"/><PARAM id="mxdestd" value="0.0"/><PARAM id="mxnode1a" value="18.50011444091797"/><PARAM id="mxnode1b" value="0.0"/><PARAM id="mxnode1c" value="59.49996948242188"/><PARAM id="mxnode1d" value="0.0"/><PARAM id="mxnode2a" value="0.0"/><PARAM id="mxnode2b" value="6.499992370605469"/><PARAM id="mxnode2c" value="0.0"/><PARAM id="mxnode2d" value="0.0"/><PARAM id="mxnode3a" value="0.0"/><PARAM id="mxnode3b" value="0.0"/><PARAM id="mxnode3c" value="0.0"/><PARAM id="mxnode3d" value="0.0"/><PARAM id="mxnode4a" value="0.0"/><PARAM id="mxnode4b" value="0.0"/><PARAM id="mxnode4c" value="0.0"/><PARAM id="mxnode4d" value="0.0"/><PARAM id="mxnode1alock" value="0.0"/><PARAM id="mxnode1block" value="0.0"/><PARAM id="mxnode1clock" value="0.0"/><PARAM id="mxnode1dlock" value="0.0"/><PARAM id="mxnode2alock" value="0.0"/><PARAM id="mxnode2block" value="0.0"/><PARAM id="mxnode2clock" value="0.0"/><PARAM id="mxnode2dlock" value="0.0"/><PARAM id="mxnode3alock" value="0.0"/><PARAM id="mxnode3block" value="0.0"/><PARAM id="mxnode3clock" value="0.0"/><PARAM id="mxnode3dlock" value="0.0"/><PARAM id="mxnode4alock" value="0.0"/><PARAM id="mxnode4block" value="0.0"/><PARAM id="mxnode4clock" value="0.0"/><PARAM id="mxnode4dlock" value="0.0"/><PARAM id="monitormix" value="100.0"/><PARAM id="pickupbehaviour" value="0.0"/><Quantiser program="0"/></Parameters><Notes text=""/></SeashellPreset> 
]] },
  [28] = { name = "Chip Tune", raw = [[
VC2!  <?xml version="1.0" encoding="UTF-8"?> <SeashellPreset><Version major="2" minor="0" patch="0" tweak="0"/><Parameters><PARAM id="osc1frequency" value="0.0"/><PARAM id="osc2frequency" value="0.1099998950958252"/><PARAM id="lfonoff" value="0.0"/><PARAM id="octaverange" value="5.0"/><PARAM id="sync" value="2.0"/><PARAM id="1voctrouting" value="2.0"/><PARAM id="transpose" value="2.0"/><PARAM id="portamento" value="0.0"/><PARAM id="midipitchbend" value="2.0"/><PARAM id="wavefoldinput" value="1.0"/><PARAM id="folddepth" value="0.0"/><PARAM id="foldbias" value="0.0"/><PARAM id="foldbiasanimate" value="0.4211682677268982"/><PARAM id="pulsewidth" value="50.0"/><PARAM id="pwmanimate" value="0.0"/><PARAM id="animateonoff" value="0.0"/><PARAM id="waveformselect" value="0.0"/><PARAM id="filtercutoff" value="68.31472015380859"/><PARAM id="filterkeytrack" value="0.0"/><PARAM id="outputlevel" value="0.0"/><PARAM id="diffuseamount" value="0.75"/><PARAM id="envmode" value="1.0"/><PARAM id="envattack" value="3.144519090652466"/><PARAM id="envdecay" value="0.0"/><PARAM id="envsustain" value="100.0"/><PARAM id="envrelease" value="0.02262442372739315"/><PARAM id="envshape" value="1.0"/><PARAM id="envgate" value="1.0"/><PARAM id="envretrigonoff" value="1.0"/><PARAM id="envtriggerbutton" value="1.0"/><PARAM id="envtriggerjack" value="1.0"/><PARAM id="envtriggernoteon" value="1.0"/><PARAM id="extend" value="1.0"/><PARAM id="lforate" value="12.52081775665283"/><PARAM id="lforatesubdivision" value="9.0"/><PARAM id="lfotimemode" value="0.0"/><PARAM id="lfomode" value="0.0"/><PARAM id="lfopolarity" value="1.0"/><PARAM id="lfophase" value="0.0"/><PARAM id="lfotriggerbutton" value="0.0"/><PARAM id="lfotriggerjack" value="0.0"/><PARAM id="lfotriggernoteon" value="1.0"/><PARAM id="rndlforatesync" value="1.0"/><PARAM id="rndrate" value="5.000000476837158"/><PARAM id="rndratesubdivision" value="9.0"/><PARAM id="rndtimemode" value="0.0"/><PARAM id="rndpolarity" value="0.0"/><PARAM id="rnddensity" value="100.0"/><PARAM id="rndsmoothing" value="0.0"/><PARAM id="rndtriggerbutton" value="0.0"/><PARAM id="rndtriggerjack" value="0.0"/><PARAM id="rndtriggernoteon" value="0.0"/><PARAM id="taptempoenable" value="1.0"/><PARAM id="macro" value="99.96337890625"/><PARAM id="mxsource1" value="23.0"/><PARAM id="mxsource2" value="12.0"/><PARAM id="mxsource3" value="4.0"/><PARAM id="mxsource4" value="0.0"/><PARAM id="mxdesta" value="4.0"/><PARAM id="mxdestb" value="16.0"/><PARAM id="mxdestc" value="6.0"/><PARAM id="mxdestd" value="14.0"/><PARAM id="mxnode1a" value="100.0"/><PARAM id="mxnode1b" value="0.0"/><PARAM id="mxnode1c" value="33.0"/><PARAM id="mxnode1d" value="0.0"/><PARAM id="mxnode2a" value="0.0"/><PARAM id="mxnode2b" value="100.0"/><PARAM id="mxnode2c" value="0.0"/><PARAM id="mxnode2d" value="0.0"/><PARAM id="mxnode3a" value="0.0"/><PARAM id="mxnode3b" value="0.0"/><PARAM id="mxnode3c" value="0.0"/><PARAM id="mxnode3d" value="31.99996948242188"/><PARAM id="mxnode4a" value="0.0"/><PARAM id="mxnode4b" value="0.0"/><PARAM id="mxnode4c" value="0.0"/><PARAM id="mxnode4d" value="0.0"/><PARAM id="mxnode1alock" value="0.0"/><PARAM id="mxnode1block" value="0.0"/><PARAM id="mxnode1clock" value="0.0"/><PARAM id="mxnode1dlock" value="0.0"/><PARAM id="mxnode2alock" value="0.0"/><PARAM id="mxnode2block" value="0.0"/><PARAM id="mxnode2clock" value="0.0"/><PARAM id="mxnode2dlock" value="0.0"/><PARAM id="mxnode3alock" value="0.0"/><PARAM id="mxnode3block" value="0.0"/><PARAM id="mxnode3clock" value="0.0"/><PARAM id="mxnode3dlock" value="0.0"/><PARAM id="mxnode4alock" value="0.0"/><PARAM id="mxnode4block" value="0.0"/><PARAM id="mxnode4clock" value="0.0"/><PARAM id="mxnode4dlock" value="0.0"/><PARAM id="monitormix" value="100.0"/><PARAM id="pickupbehaviour" value="0.0"/><Quantiser program="0"/></Parameters><Notes text=""/></SeashellPreset> 
]] },
  [29] = { name = "Octave Pluck", raw = [[
VC2!4  <?xml version="1.0" encoding="UTF-8"?> <SeashellPreset><Version major="2" minor="0" patch="0" tweak="0"/><Parameters><PARAM id="osc1frequency" value="0.0"/><PARAM id="osc2frequency" value="0.0"/><PARAM id="lfonoff" value="0.0"/><PARAM id="octaverange" value="5.0"/><PARAM id="sync" value="0.0"/><PARAM id="1voctrouting" value="3.0"/><PARAM id="transpose" value="3.0"/><PARAM id="portamento" value="0.0"/><PARAM id="midipitchbend" value="2.0"/><PARAM id="wavefoldinput" value="0.0"/><PARAM id="folddepth" value="0.01831166446208954"/><PARAM id="foldbias" value="50.0"/><PARAM id="foldbiasanimate" value="0.0"/><PARAM id="pulsewidth" value="50.0"/><PARAM id="pwmanimate" value="50.0"/><PARAM id="animateonoff" value="1.0"/><PARAM id="waveformselect" value="0.0"/><PARAM id="filtercutoff" value="47.90941619873047"/><PARAM id="filterkeytrack" value="0.0"/><PARAM id="outputlevel" value="100.0"/><PARAM id="diffuseamount" value="66.24999237060547"/><PARAM id="envmode" value="0.0"/><PARAM id="envattack" value="0.0"/><PARAM id="envdecay" value="1.052506685256958"/><PARAM id="envsustain" value="50.0"/><PARAM id="envrelease" value="1.052506685256958"/><PARAM id="envshape" value="1.0"/><PARAM id="envgate" value="1.0"/><PARAM id="envretrigonoff" value="1.0"/><PARAM id="envtriggerbutton" value="1.0"/><PARAM id="envtriggerjack" value="1.0"/><PARAM id="envtriggernoteon" value="1.0"/><PARAM id="extend" value="1.0"/><PARAM id="lforate" value="5.149998188018799"/><PARAM id="lforatesubdivision" value="9.0"/><PARAM id="lfotimemode" value="0.0"/><PARAM id="lfomode" value="2.0"/><PARAM id="lfopolarity" value="0.0"/><PARAM id="lfophase" value="0.0"/><PARAM id="lfotriggerbutton" value="0.0"/><PARAM id="lfotriggerjack" value="0.0"/><PARAM id="lfotriggernoteon" value="1.0"/><PARAM id="rndlforatesync" value="1.0"/><PARAM id="rndrate" value="5.000000476837158"/><PARAM id="rndratesubdivision" value="9.0"/><PARAM id="rndtimemode" value="0.0"/><PARAM id="rndpolarity" value="0.0"/><PARAM id="rnddensity" value="100.0"/><PARAM id="rndsmoothing" value="0.0"/><PARAM id="rndtriggerbutton" value="0.0"/><PARAM id="rndtriggerjack" value="0.0"/><PARAM id="rndtriggernoteon" value="0.0"/><PARAM id="taptempoenable" value="1.0"/><PARAM id="macro" value="99.83518981933594"/><PARAM id="mxsource1" value="14.0"/><PARAM id="mxsource2" value="2.0"/><PARAM id="mxsource3" value="0.0"/><PARAM id="mxsource4" value="0.0"/><PARAM id="mxdesta" value="18.0"/><PARAM id="mxdestb" value="15.0"/><PARAM id="mxdestc" value="8.0"/><PARAM id="mxdestd" value="24.0"/><PARAM id="mxnode1a" value="29.0"/><PARAM id="mxnode1b" value="-21.50003051757812"/><PARAM id="mxnode1c" value="51.49993896484375"/><PARAM id="mxnode1d" value="8.999992370605469"/><PARAM id="mxnode2a" value="9.499992370605469"/><PARAM id="mxnode2b" value="0.0"/><PARAM id="mxnode2c" value="0.0"/><PARAM id="mxnode2d" value="0.0"/><PARAM id="mxnode3a" value="0.0"/><PARAM id="mxnode3b" value="0.0"/><PARAM id="mxnode3c" value="0.0"/><PARAM id="mxnode3d" value="0.0"/><PARAM id="mxnode4a" value="0.0"/><PARAM id="mxnode4b" value="0.0"/><PARAM id="mxnode4c" value="0.0"/><PARAM id="mxnode4d" value="0.0"/><PARAM id="mxnode1alock" value="0.0"/><PARAM id="mxnode1block" value="0.0"/><PARAM id="mxnode1clock" value="0.0"/><PARAM id="mxnode1dlock" value="0.0"/><PARAM id="mxnode2alock" value="0.0"/><PARAM id="mxnode2block" value="0.0"/><PARAM id="mxnode2clock" value="0.0"/><PARAM id="mxnode2dlock" value="0.0"/><PARAM id="mxnode3alock" value="0.0"/><PARAM id="mxnode3block" value="0.0"/><PARAM id="mxnode3clock" value="0.0"/><PARAM id="mxnode3dlock" value="0.0"/><PARAM id="mxnode4alock" value="0.0"/><PARAM id="mxnode4block" value="0.0"/><PARAM id="mxnode4clock" value="0.0"/><PARAM id="mxnode4dlock" value="0.0"/><PARAM id="monitormix" value="100.0"/><PARAM id="pickupbehaviour" value="0.0"/><Quantiser program="0"/></Parameters><Notes text=""/></SeashellPreset> 
]] },
  [30] = { name = "One Octave Trill", raw = [[
VC2!À  <?xml version="1.0" encoding="UTF-8"?> <SeashellPreset><Version major="2" minor="0" patch="0" tweak="0"/><Parameters><PARAM id="osc1frequency" value="0.0"/><PARAM id="osc2frequency" value="0.0"/><PARAM id="lfonoff" value="0.0"/><PARAM id="octaverange" value="5.0"/><PARAM id="sync" value="0.0"/><PARAM id="1voctrouting" value="3.0"/><PARAM id="transpose" value="0.0"/><PARAM id="portamento" value="0.0"/><PARAM id="midipitchbend" value="2.0"/><PARAM id="wavefoldinput" value="0.0"/><PARAM id="folddepth" value="0.0"/><PARAM id="foldbias" value="0.0"/><PARAM id="foldbiasanimate" value="50.0"/><PARAM id="pulsewidth" value="50.0"/><PARAM id="pwmanimate" value="50.0"/><PARAM id="animateonoff" value="0.0"/><PARAM id="waveformselect" value="3.0"/><PARAM id="filtercutoff" value="92.08325958251953"/><PARAM id="filterkeytrack" value="0.0"/><PARAM id="outputlevel" value="100.0"/><PARAM id="diffuseamount" value="0.0"/><PARAM id="envmode" value="1.0"/><PARAM id="envattack" value="1.0"/><PARAM id="envdecay" value="1.0"/><PARAM id="envsustain" value="50.0"/><PARAM id="envrelease" value="1.0"/><PARAM id="envshape" value="1.0"/><PARAM id="envgate" value="1.0"/><PARAM id="envretrigonoff" value="1.0"/><PARAM id="envtriggerbutton" value="1.0"/><PARAM id="envtriggerjack" value="1.0"/><PARAM id="envtriggernoteon" value="1.0"/><PARAM id="extend" value="1.0"/><PARAM id="lforate" value="8.000556945800781"/><PARAM id="lforatesubdivision" value="9.0"/><PARAM id="lfotimemode" value="0.0"/><PARAM id="lfomode" value="0.0"/><PARAM id="lfopolarity" value="1.0"/><PARAM id="lfophase" value="0.0"/><PARAM id="lfotriggerbutton" value="1.0"/><PARAM id="lfotriggerjack" value="1.0"/><PARAM id="lfotriggernoteon" value="1.0"/><PARAM id="rndlforatesync" value="1.0"/><PARAM id="rndrate" value="5.000000476837158"/><PARAM id="rndratesubdivision" value="9.0"/><PARAM id="rndtimemode" value="0.0"/><PARAM id="rndpolarity" value="0.0"/><PARAM id="rnddensity" value="100.0"/><PARAM id="rndsmoothing" value="0.0"/><PARAM id="rndtriggerbutton" value="0.0"/><PARAM id="rndtriggerjack" value="0.0"/><PARAM id="rndtriggernoteon" value="0.0"/><PARAM id="taptempoenable" value="1.0"/><PARAM id="macro" value="100.0"/><PARAM id="mxsource1" value="12.0"/><PARAM id="mxsource2" value="0.0"/><PARAM id="mxsource3" value="0.0"/><PARAM id="mxsource4" value="0.0"/><PARAM id="mxdesta" value="11.0"/><PARAM id="mxdestb" value="0.0"/><PARAM id="mxdestc" value="0.0"/><PARAM id="mxdestd" value="0.0"/><PARAM id="mxnode1a" value="16.49998474121094"/><PARAM id="mxnode1b" value="0.0"/><PARAM id="mxnode1c" value="0.0"/><PARAM id="mxnode1d" value="0.0"/><PARAM id="mxnode2a" value="0.0"/><PARAM id="mxnode2b" value="0.0"/><PARAM id="mxnode2c" value="0.0"/><PARAM id="mxnode2d" value="0.0"/><PARAM id="mxnode3a" value="0.0"/><PARAM id="mxnode3b" value="0.0"/><PARAM id="mxnode3c" value="0.0"/><PARAM id="mxnode3d" value="0.0"/><PARAM id="mxnode4a" value="0.0"/><PARAM id="mxnode4b" value="0.0"/><PARAM id="mxnode4c" value="0.0"/><PARAM id="mxnode4d" value="0.0"/><PARAM id="mxnode1alock" value="0.0"/><PARAM id="mxnode1block" value="0.0"/><PARAM id="mxnode1clock" value="0.0"/><PARAM id="mxnode1dlock" value="0.0"/><PARAM id="mxnode2alock" value="0.0"/><PARAM id="mxnode2block" value="0.0"/><PARAM id="mxnode2clock" value="0.0"/><PARAM id="mxnode2dlock" value="0.0"/><PARAM id="mxnode3alock" value="0.0"/><PARAM id="mxnode3block" value="0.0"/><PARAM id="mxnode3clock" value="0.0"/><PARAM id="mxnode3dlock" value="0.0"/><PARAM id="mxnode4alock" value="0.0"/><PARAM id="mxnode4block" value="0.0"/><PARAM id="mxnode4clock" value="0.0"/><PARAM id="mxnode4dlock" value="0.0"/><PARAM id="monitormix" value="100.0"/><PARAM id="pickupbehaviour" value="0.0"/><Quantiser program="0"/></Parameters><Notes text=""/></SeashellPreset> 
]] },
  [31] = { name = "Pink Echoes", raw = [[
VC2!  <?xml version="1.0" encoding="UTF-8"?> <SeashellPreset><Version major="2" minor="0" patch="0" tweak="0"/><Parameters><PARAM id="osc1frequency" value="0.0"/><PARAM id="osc2frequency" value="0.002782821655273438"/><PARAM id="lfonoff" value="0.0"/><PARAM id="octaverange" value="5.0"/><PARAM id="sync" value="0.0"/><PARAM id="1voctrouting" value="3.0"/><PARAM id="transpose" value="0.0"/><PARAM id="portamento" value="0.0"/><PARAM id="midipitchbend" value="2.0"/><PARAM id="wavefoldinput" value="0.0"/><PARAM id="folddepth" value="0.0"/><PARAM id="foldbias" value="0.0"/><PARAM id="foldbiasanimate" value="100.0"/><PARAM id="pulsewidth" value="50.0"/><PARAM id="pwmanimate" value="50.0"/><PARAM id="animateonoff" value="1.0"/><PARAM id="waveformselect" value="0.0"/><PARAM id="filtercutoff" value="65.50005340576172"/><PARAM id="filterkeytrack" value="0.0"/><PARAM id="outputlevel" value="100.0"/><PARAM id="diffuseamount" value="100.0"/><PARAM id="envmode" value="0.0"/><PARAM id="envattack" value="0.001425864291377366"/><PARAM id="envdecay" value="1.36419665813446"/><PARAM id="envsustain" value="0.0"/><PARAM id="envrelease" value="1.36419665813446"/><PARAM id="envshape" value="1.0"/><PARAM id="envgate" value="1.0"/><PARAM id="envretrigonoff" value="1.0"/><PARAM id="envtriggerbutton" value="1.0"/><PARAM id="envtriggerjack" value="1.0"/><PARAM id="envtriggernoteon" value="1.0"/><PARAM id="extend" value="1.0"/><PARAM id="lforate" value="16.20001029968262"/><PARAM id="lforatesubdivision" value="9.0"/><PARAM id="lfotimemode" value="0.0"/><PARAM id="lfomode" value="0.0"/><PARAM id="lfopolarity" value="0.0"/><PARAM id="lfophase" value="0.0"/><PARAM id="lfotriggerbutton" value="1.0"/><PARAM id="lfotriggerjack" value="1.0"/><PARAM id="lfotriggernoteon" value="1.0"/><PARAM id="rndlforatesync" value="1.0"/><PARAM id="rndrate" value="5.000000476837158"/><PARAM id="rndratesubdivision" value="9.0"/><PARAM id="rndtimemode" value="0.0"/><PARAM id="rndpolarity" value="0.0"/><PARAM id="rnddensity" value="100.0"/><PARAM id="rndsmoothing" value="0.0"/><PARAM id="rndtriggerbutton" value="0.0"/><PARAM id="rndtriggerjack" value="0.0"/><PARAM id="rndtriggernoteon" value="0.0"/><PARAM id="taptempoenable" value="1.0"/><PARAM id="macro" value="100.0"/><PARAM id="mxsource1" value="4.0"/><PARAM id="mxsource2" value="10.0"/><PARAM id="mxsource3" value="0.0"/><PARAM id="mxsource4" value="0.0"/><PARAM id="mxdesta" value="3.0"/><PARAM id="mxdestb" value="7.0"/><PARAM id="mxdestc" value="0.0"/><PARAM id="mxdestd" value="0.0"/><PARAM id="mxnode1a" value="20.99997711181641"/><PARAM id="mxnode1b" value="40.5"/><PARAM id="mxnode1c" value="0.0"/><PARAM id="mxnode1d" value="0.0"/><PARAM id="mxnode2a" value="-3.499977111816406"/><PARAM id="mxnode2b" value="30.5"/><PARAM id="mxnode2c" value="0.0"/><PARAM id="mxnode2d" value="0.0"/><PARAM id="mxnode3a" value="0.0"/><PARAM id="mxnode3b" value="0.0"/><PARAM id="mxnode3c" value="0.0"/><PARAM id="mxnode3d" value="0.0"/><PARAM id="mxnode4a" value="0.0"/><PARAM id="mxnode4b" value="0.0"/><PARAM id="mxnode4c" value="0.0"/><PARAM id="mxnode4d" value="0.0"/><PARAM id="mxnode1alock" value="0.0"/><PARAM id="mxnode1block" value="0.0"/><PARAM id="mxnode1clock" value="0.0"/><PARAM id="mxnode1dlock" value="0.0"/><PARAM id="mxnode2alock" value="0.0"/><PARAM id="mxnode2block" value="0.0"/><PARAM id="mxnode2clock" value="0.0"/><PARAM id="mxnode2dlock" value="0.0"/><PARAM id="mxnode3alock" value="0.0"/><PARAM id="mxnode3block" value="0.0"/><PARAM id="mxnode3clock" value="0.0"/><PARAM id="mxnode3dlock" value="0.0"/><PARAM id="mxnode4alock" value="0.0"/><PARAM id="mxnode4block" value="0.0"/><PARAM id="mxnode4clock" value="0.0"/><PARAM id="mxnode4dlock" value="0.0"/><PARAM id="monitormix" value="100.0"/><PARAM id="pickupbehaviour" value="0.0"/><Quantiser program="0"/></Parameters><Notes text=""/></SeashellPreset> 
]] },
  [32] = { name = "Pluck Short", raw = [[
VC2!J  <?xml version="1.0" encoding="UTF-8"?> <SeashellPreset><Version major="2" minor="0" patch="0" tweak="0"/><Parameters><PARAM id="osc1frequency" value="0.3179515600204468"/><PARAM id="osc2frequency" value="0.2526398897171021"/><PARAM id="lfonoff" value="0.0"/><PARAM id="octaverange" value="5.0"/><PARAM id="sync" value="2.0"/><PARAM id="1voctrouting" value="2.0"/><PARAM id="transpose" value="2.0"/><PARAM id="portamento" value="0.0"/><PARAM id="midipitchbend" value="2.0"/><PARAM id="wavefoldinput" value="1.0"/><PARAM id="folddepth" value="49.04473876953125"/><PARAM id="foldbias" value="0.0"/><PARAM id="foldbiasanimate" value="50.0"/><PARAM id="pulsewidth" value="50.0"/><PARAM id="pwmanimate" value="50.0"/><PARAM id="animateonoff" value="0.0"/><PARAM id="waveformselect" value="4.0"/><PARAM id="filtercutoff" value="86.68742370605469"/><PARAM id="filterkeytrack" value="0.0"/><PARAM id="outputlevel" value="100.0"/><PARAM id="diffuseamount" value="0.25"/><PARAM id="envmode" value="0.0"/><PARAM id="envattack" value="0.00108607835136354"/><PARAM id="envdecay" value="0.1881256848573685"/><PARAM id="envsustain" value="50.0"/><PARAM id="envrelease" value="0.1881256848573685"/><PARAM id="envshape" value="1.0"/><PARAM id="envgate" value="1.0"/><PARAM id="envretrigonoff" value="1.0"/><PARAM id="envtriggerbutton" value="1.0"/><PARAM id="envtriggerjack" value="1.0"/><PARAM id="envtriggernoteon" value="1.0"/><PARAM id="extend" value="1.0"/><PARAM id="lforate" value="1.431133508682251"/><PARAM id="lforatesubdivision" value="9.0"/><PARAM id="lfotimemode" value="0.0"/><PARAM id="lfomode" value="0.0"/><PARAM id="lfopolarity" value="1.0"/><PARAM id="lfophase" value="0.0"/><PARAM id="lfotriggerbutton" value="0.0"/><PARAM id="lfotriggerjack" value="0.0"/><PARAM id="lfotriggernoteon" value="0.0"/><PARAM id="rndlforatesync" value="1.0"/><PARAM id="rndrate" value="5.000000476837158"/><PARAM id="rndratesubdivision" value="9.0"/><PARAM id="rndtimemode" value="0.0"/><PARAM id="rndpolarity" value="0.0"/><PARAM id="rnddensity" value="100.0"/><PARAM id="rndsmoothing" value="0.0"/><PARAM id="rndtriggerbutton" value="0.0"/><PARAM id="rndtriggerjack" value="0.0"/><PARAM id="rndtriggernoteon" value="0.0"/><PARAM id="taptempoenable" value="1.0"/><PARAM id="macro" value="100.0"/><PARAM id="mxsource1" value="2.0"/><PARAM id="mxsource2" value="0.0"/><PARAM id="mxsource3" value="4.0"/><PARAM id="mxsource4" value="10.0"/><PARAM id="mxdesta" value="3.0"/><PARAM id="mxdestb" value="14.0"/><PARAM id="mxdestc" value="6.0"/><PARAM id="mxdestd" value="16.0"/><PARAM id="mxnode1a" value="0.0"/><PARAM id="mxnode1b" value="0.0"/><PARAM id="mxnode1c" value="100.0"/><PARAM id="mxnode1d" value="0.0"/><PARAM id="mxnode2a" value="0.0"/><PARAM id="mxnode2b" value="0.0"/><PARAM id="mxnode2c" value="0.0"/><PARAM id="mxnode2d" value="0.0"/><PARAM id="mxnode3a" value="0.0"/><PARAM id="mxnode3b" value="-2.499954223632812"/><PARAM id="mxnode3c" value="-55.99996566772461"/><PARAM id="mxnode3d" value="0.0"/><PARAM id="mxnode4a" value="21.49999237060547"/><PARAM id="mxnode4b" value="0.0"/><PARAM id="mxnode4c" value="0.0"/><PARAM id="mxnode4d" value="2.000030517578125"/><PARAM id="mxnode1alock" value="0.0"/><PARAM id="mxnode1block" value="0.0"/><PARAM id="mxnode1clock" value="0.0"/><PARAM id="mxnode1dlock" value="0.0"/><PARAM id="mxnode2alock" value="0.0"/><PARAM id="mxnode2block" value="0.0"/><PARAM id="mxnode2clock" value="0.0"/><PARAM id="mxnode2dlock" value="0.0"/><PARAM id="mxnode3alock" value="0.0"/><PARAM id="mxnode3block" value="1.0"/><PARAM id="mxnode3clock" value="0.0"/><PARAM id="mxnode3dlock" value="0.0"/><PARAM id="mxnode4alock" value="0.0"/><PARAM id="mxnode4block" value="0.0"/><PARAM id="mxnode4clock" value="0.0"/><PARAM id="mxnode4dlock" value="1.0"/><PARAM id="monitormix" value="100.0"/><PARAM id="pickupbehaviour" value="0.0"/><Quantiser program="0"/></Parameters><Notes text=""/></SeashellPreset> 
]] },
  [33] = { name = "Popcorn", raw = [[
VC2!ô  <?xml version="1.0" encoding="UTF-8"?> <SeashellPreset><Version major="2" minor="0" patch="0" tweak="0"/><Parameters><PARAM id="osc1frequency" value="0.00299990177154541"/><PARAM id="osc2frequency" value="0.0"/><PARAM id="lfonoff" value="0.0"/><PARAM id="octaverange" value="5.0"/><PARAM id="sync" value="0.0"/><PARAM id="1voctrouting" value="3.0"/><PARAM id="transpose" value="0.0"/><PARAM id="portamento" value="0.0"/><PARAM id="midipitchbend" value="2.0"/><PARAM id="wavefoldinput" value="0.0"/><PARAM id="folddepth" value="0.0"/><PARAM id="foldbias" value="0.0"/><PARAM id="foldbiasanimate" value="50.0"/><PARAM id="pulsewidth" value="50.0"/><PARAM id="pwmanimate" value="50.0"/><PARAM id="animateonoff" value="0.0"/><PARAM id="waveformselect" value="1.0"/><PARAM id="filtercutoff" value="49.49032592773438"/><PARAM id="filterkeytrack" value="31.5"/><PARAM id="outputlevel" value="100.0"/><PARAM id="diffuseamount" value="0.0"/><PARAM id="envmode" value="0.0"/><PARAM id="envattack" value="0.001425864058546722"/><PARAM id="envdecay" value="0.05708933621644974"/><PARAM id="envsustain" value="50.0"/><PARAM id="envrelease" value="0.05708933621644974"/><PARAM id="envshape" value="1.0"/><PARAM id="envgate" value="1.0"/><PARAM id="envretrigonoff" value="1.0"/><PARAM id="envtriggerbutton" value="1.0"/><PARAM id="envtriggerjack" value="1.0"/><PARAM id="envtriggernoteon" value="1.0"/><PARAM id="extend" value="1.0"/><PARAM id="lforate" value="5.000000476837158"/><PARAM id="lforatesubdivision" value="9.0"/><PARAM id="lfotimemode" value="0.0"/><PARAM id="lfomode" value="0.0"/><PARAM id="lfopolarity" value="0.0"/><PARAM id="lfophase" value="0.0"/><PARAM id="lfotriggerbutton" value="0.0"/><PARAM id="lfotriggerjack" value="0.0"/><PARAM id="lfotriggernoteon" value="0.0"/><PARAM id="rndlforatesync" value="1.0"/><PARAM id="rndrate" value="5.000000476837158"/><PARAM id="rndratesubdivision" value="9.0"/><PARAM id="rndtimemode" value="0.0"/><PARAM id="rndpolarity" value="0.0"/><PARAM id="rnddensity" value="100.0"/><PARAM id="rndsmoothing" value="0.0"/><PARAM id="rndtriggerbutton" value="0.0"/><PARAM id="rndtriggerjack" value="0.0"/><PARAM id="rndtriggernoteon" value="0.0"/><PARAM id="taptempoenable" value="1.0"/><PARAM id="macro" value="100.0"/><PARAM id="mxsource1" value="4.0"/><PARAM id="mxsource2" value="0.0"/><PARAM id="mxsource3" value="0.0"/><PARAM id="mxsource4" value="0.0"/><PARAM id="mxdesta" value="3.0"/><PARAM id="mxdestb" value="0.0"/><PARAM id="mxdestc" value="0.0"/><PARAM id="mxdestd" value="0.0"/><PARAM id="mxnode1a" value="100.0"/><PARAM id="mxnode1b" value="0.0"/><PARAM id="mxnode1c" value="0.0"/><PARAM id="mxnode1d" value="0.0"/><PARAM id="mxnode2a" value="0.0"/><PARAM id="mxnode2b" value="0.0"/><PARAM id="mxnode2c" value="0.0"/><PARAM id="mxnode2d" value="0.0"/><PARAM id="mxnode3a" value="0.0"/><PARAM id="mxnode3b" value="0.0"/><PARAM id="mxnode3c" value="0.0"/><PARAM id="mxnode3d" value="0.0"/><PARAM id="mxnode4a" value="0.0"/><PARAM id="mxnode4b" value="0.0"/><PARAM id="mxnode4c" value="0.0"/><PARAM id="mxnode4d" value="0.0"/><PARAM id="mxnode1alock" value="0.0"/><PARAM id="mxnode1block" value="0.0"/><PARAM id="mxnode1clock" value="0.0"/><PARAM id="mxnode1dlock" value="0.0"/><PARAM id="mxnode2alock" value="0.0"/><PARAM id="mxnode2block" value="0.0"/><PARAM id="mxnode2clock" value="0.0"/><PARAM id="mxnode2dlock" value="0.0"/><PARAM id="mxnode3alock" value="0.0"/><PARAM id="mxnode3block" value="0.0"/><PARAM id="mxnode3clock" value="0.0"/><PARAM id="mxnode3dlock" value="0.0"/><PARAM id="mxnode4alock" value="0.0"/><PARAM id="mxnode4block" value="0.0"/><PARAM id="mxnode4clock" value="0.0"/><PARAM id="mxnode4dlock" value="0.0"/><PARAM id="monitormix" value="100.0"/><PARAM id="pickupbehaviour" value="0.0"/><Quantiser program="0"/></Parameters><Notes text=""/></SeashellPreset> 
]] },
  [34] = { name = "Saw Slapback", raw = [[
VC2!8  <?xml version="1.0" encoding="UTF-8"?> <SeashellPreset><Version major="2" minor="0" patch="0" tweak="0"/><Parameters><PARAM id="osc1frequency" value="-0.1549990177154541"/><PARAM id="osc2frequency" value="-0.2650003433227539"/><PARAM id="lfonoff" value="0.0"/><PARAM id="octaverange" value="5.0"/><PARAM id="sync" value="0.0"/><PARAM id="1voctrouting" value="3.0"/><PARAM id="transpose" value="3.0"/><PARAM id="portamento" value="0.0"/><PARAM id="midipitchbend" value="2.0"/><PARAM id="wavefoldinput" value="0.0"/><PARAM id="folddepth" value="0.01831166446208954"/><PARAM id="foldbias" value="0.0"/><PARAM id="foldbiasanimate" value="0.0"/><PARAM id="pulsewidth" value="50.0"/><PARAM id="pwmanimate" value="50.0"/><PARAM id="animateonoff" value="1.0"/><PARAM id="waveformselect" value="1.0"/><PARAM id="filtercutoff" value="0.01831166446208954"/><PARAM id="filterkeytrack" value="0.0"/><PARAM id="outputlevel" value="100.0"/><PARAM id="diffuseamount" value="24.49998092651367"/><PARAM id="envmode" value="1.0"/><PARAM id="envattack" value="0.3804342150688171"/><PARAM id="envdecay" value="3.00173020362854"/><PARAM id="envsustain" value="37.75"/><PARAM id="envrelease" value="0.6356917023658752"/><PARAM id="envshape" value="1.0"/><PARAM id="envgate" value="1.0"/><PARAM id="envretrigonoff" value="1.0"/><PARAM id="envtriggerbutton" value="1.0"/><PARAM id="envtriggerjack" value="1.0"/><PARAM id="envtriggernoteon" value="1.0"/><PARAM id="extend" value="1.0"/><PARAM id="lforate" value="5.149998188018799"/><PARAM id="lforatesubdivision" value="9.0"/><PARAM id="lfotimemode" value="0.0"/><PARAM id="lfomode" value="1.0"/><PARAM id="lfopolarity" value="0.0"/><PARAM id="lfophase" value="0.0"/><PARAM id="lfotriggerbutton" value="0.0"/><PARAM id="lfotriggerjack" value="0.0"/><PARAM id="lfotriggernoteon" value="1.0"/><PARAM id="rndlforatesync" value="1.0"/><PARAM id="rndrate" value="5.000000476837158"/><PARAM id="rndratesubdivision" value="9.0"/><PARAM id="rndtimemode" value="0.0"/><PARAM id="rndpolarity" value="0.0"/><PARAM id="rnddensity" value="100.0"/><PARAM id="rndsmoothing" value="0.0"/><PARAM id="rndtriggerbutton" value="0.0"/><PARAM id="rndtriggerjack" value="0.0"/><PARAM id="rndtriggernoteon" value="0.0"/><PARAM id="taptempoenable" value="1.0"/><PARAM id="macro" value="99.79246520996094"/><PARAM id="mxsource1" value="4.0"/><PARAM id="mxsource2" value="23.0"/><PARAM id="mxsource3" value="0.0"/><PARAM id="mxsource4" value="0.0"/><PARAM id="mxdesta" value="3.0"/><PARAM id="mxdestb" value="6.0"/><PARAM id="mxdestc" value="0.0"/><PARAM id="mxdestd" value="0.0"/><PARAM id="mxnode1a" value="58.49996948242188"/><PARAM id="mxnode1b" value="0.0"/><PARAM id="mxnode1c" value="0.0"/><PARAM id="mxnode1d" value="0.0"/><PARAM id="mxnode2a" value="0.0"/><PARAM id="mxnode2b" value="100.0"/><PARAM id="mxnode2c" value="0.0"/><PARAM id="mxnode2d" value="0.0"/><PARAM id="mxnode3a" value="0.0"/><PARAM id="mxnode3b" value="0.0"/><PARAM id="mxnode3c" value="0.0"/><PARAM id="mxnode3d" value="0.0"/><PARAM id="mxnode4a" value="0.0"/><PARAM id="mxnode4b" value="0.0"/><PARAM id="mxnode4c" value="0.0"/><PARAM id="mxnode4d" value="0.0"/><PARAM id="mxnode1alock" value="0.0"/><PARAM id="mxnode1block" value="0.0"/><PARAM id="mxnode1clock" value="0.0"/><PARAM id="mxnode1dlock" value="0.0"/><PARAM id="mxnode2alock" value="0.0"/><PARAM id="mxnode2block" value="0.0"/><PARAM id="mxnode2clock" value="0.0"/><PARAM id="mxnode2dlock" value="0.0"/><PARAM id="mxnode3alock" value="0.0"/><PARAM id="mxnode3block" value="0.0"/><PARAM id="mxnode3clock" value="0.0"/><PARAM id="mxnode3dlock" value="0.0"/><PARAM id="mxnode4alock" value="0.0"/><PARAM id="mxnode4block" value="0.0"/><PARAM id="mxnode4clock" value="0.0"/><PARAM id="mxnode4dlock" value="0.0"/><PARAM id="monitormix" value="100.0"/><PARAM id="pickupbehaviour" value="0.0"/><Quantiser program="0"/></Parameters><Notes text=""/></SeashellPreset> 
]] },
  [35] = { name = "Shine On", raw = [[
VC2!  <?xml version="1.0" encoding="UTF-8"?> <SeashellPreset><Version major="2" minor="0" patch="0" tweak="0"/><Parameters><PARAM id="osc1frequency" value="0.0"/><PARAM id="osc2frequency" value="0.001281857490539551"/><PARAM id="lfonoff" value="0.0"/><PARAM id="octaverange" value="5.0"/><PARAM id="sync" value="0.0"/><PARAM id="1voctrouting" value="3.0"/><PARAM id="transpose" value="0.0"/><PARAM id="portamento" value="0.0"/><PARAM id="midipitchbend" value="2.0"/><PARAM id="wavefoldinput" value="0.0"/><PARAM id="folddepth" value="0.1342855393886566"/><PARAM id="foldbias" value="0.0"/><PARAM id="foldbiasanimate" value="50.0"/><PARAM id="pulsewidth" value="50.0"/><PARAM id="pwmanimate" value="50.0"/><PARAM id="animateonoff" value="0.0"/><PARAM id="waveformselect" value="4.0"/><PARAM id="filtercutoff" value="17.5"/><PARAM id="filterkeytrack" value="64.0"/><PARAM id="outputlevel" value="0.0"/><PARAM id="diffuseamount" value="99.5"/><PARAM id="envmode" value="1.0"/><PARAM id="envattack" value="0.2432128190994263"/><PARAM id="envdecay" value="0.8905612826347351"/><PARAM id="envsustain" value="50.0"/><PARAM id="envrelease" value="0.8905612826347351"/><PARAM id="envshape" value="1.0"/><PARAM id="envgate" value="0.0"/><PARAM id="envretrigonoff" value="1.0"/><PARAM id="envtriggerbutton" value="1.0"/><PARAM id="envtriggerjack" value="1.0"/><PARAM id="envtriggernoteon" value="1.0"/><PARAM id="extend" value="1.0"/><PARAM id="lforate" value="5.001803398132324"/><PARAM id="lforatesubdivision" value="9.0"/><PARAM id="lfotimemode" value="0.0"/><PARAM id="lfomode" value="0.0"/><PARAM id="lfopolarity" value="0.0"/><PARAM id="lfophase" value="0.0"/><PARAM id="lfotriggerbutton" value="0.0"/><PARAM id="lfotriggerjack" value="0.0"/><PARAM id="lfotriggernoteon" value="0.0"/><PARAM id="rndlforatesync" value="1.0"/><PARAM id="rndrate" value="5.000000476837158"/><PARAM id="rndratesubdivision" value="9.0"/><PARAM id="rndtimemode" value="0.0"/><PARAM id="rndpolarity" value="0.0"/><PARAM id="rnddensity" value="100.0"/><PARAM id="rndsmoothing" value="0.0"/><PARAM id="rndtriggerbutton" value="0.0"/><PARAM id="rndtriggerjack" value="0.0"/><PARAM id="rndtriggernoteon" value="0.0"/><PARAM id="taptempoenable" value="1.0"/><PARAM id="macro" value="100.0"/><PARAM id="mxsource1" value="4.0"/><PARAM id="mxsource2" value="11.0"/><PARAM id="mxsource3" value="0.0"/><PARAM id="mxsource4" value="0.0"/><PARAM id="mxdesta" value="13.0"/><PARAM id="mxdestb" value="3.0"/><PARAM id="mxdestc" value="4.0"/><PARAM id="mxdestd" value="0.0"/><PARAM id="mxnode1a" value="0.0"/><PARAM id="mxnode1b" value="50.99996948242188"/><PARAM id="mxnode1c" value="100.0"/><PARAM id="mxnode1d" value="0.0"/><PARAM id="mxnode2a" value="-0.5"/><PARAM id="mxnode2b" value="0.0"/><PARAM id="mxnode2c" value="0.0"/><PARAM id="mxnode2d" value="0.0"/><PARAM id="mxnode3a" value="0.0"/><PARAM id="mxnode3b" value="0.0"/><PARAM id="mxnode3c" value="0.0"/><PARAM id="mxnode3d" value="0.0"/><PARAM id="mxnode4a" value="0.0"/><PARAM id="mxnode4b" value="0.0"/><PARAM id="mxnode4c" value="0.0"/><PARAM id="mxnode4d" value="0.0"/><PARAM id="mxnode1alock" value="0.0"/><PARAM id="mxnode1block" value="0.0"/><PARAM id="mxnode1clock" value="0.0"/><PARAM id="mxnode1dlock" value="0.0"/><PARAM id="mxnode2alock" value="0.0"/><PARAM id="mxnode2block" value="0.0"/><PARAM id="mxnode2clock" value="0.0"/><PARAM id="mxnode2dlock" value="0.0"/><PARAM id="mxnode3alock" value="0.0"/><PARAM id="mxnode3block" value="0.0"/><PARAM id="mxnode3clock" value="0.0"/><PARAM id="mxnode3dlock" value="0.0"/><PARAM id="mxnode4alock" value="0.0"/><PARAM id="mxnode4block" value="0.0"/><PARAM id="mxnode4clock" value="0.0"/><PARAM id="mxnode4dlock" value="0.0"/><PARAM id="monitormix" value="100.0"/><PARAM id="pickupbehaviour" value="0.0"/><Quantiser program="0"/></Parameters><Notes text=""/></SeashellPreset> 
]] },
  [36] = { name = "Tremelo", raw = [[
VC2!&  <?xml version="1.0" encoding="UTF-8"?> <SeashellPreset><Version major="2" minor="0" patch="0" tweak="0"/><Parameters><PARAM id="osc1frequency" value="0.0"/><PARAM id="osc2frequency" value="0.0"/><PARAM id="lfonoff" value="0.0"/><PARAM id="octaverange" value="5.0"/><PARAM id="sync" value="0.0"/><PARAM id="1voctrouting" value="3.0"/><PARAM id="transpose" value="0.0"/><PARAM id="portamento" value="0.0"/><PARAM id="midipitchbend" value="2.0"/><PARAM id="wavefoldinput" value="0.0"/><PARAM id="folddepth" value="61.71641540527344"/><PARAM id="foldbias" value="50.0"/><PARAM id="foldbiasanimate" value="50.0"/><PARAM id="pulsewidth" value="50.0"/><PARAM id="pwmanimate" value="50.0"/><PARAM id="animateonoff" value="0.0"/><PARAM id="waveformselect" value="1.0"/><PARAM id="filtercutoff" value="17.71953582763672"/><PARAM id="filterkeytrack" value="0.0"/><PARAM id="outputlevel" value="0.0"/><PARAM id="diffuseamount" value="12.49998664855957"/><PARAM id="envmode" value="1.0"/><PARAM id="envattack" value="0.8372930884361267"/><PARAM id="envdecay" value="0.3210050761699677"/><PARAM id="envsustain" value="50.0"/><PARAM id="envrelease" value="0.3210050761699677"/><PARAM id="envshape" value="1.0"/><PARAM id="envgate" value="1.0"/><PARAM id="envretrigonoff" value="1.0"/><PARAM id="envtriggerbutton" value="1.0"/><PARAM id="envtriggerjack" value="1.0"/><PARAM id="envtriggernoteon" value="1.0"/><PARAM id="extend" value="1.0"/><PARAM id="lforate" value="2.995039224624634"/><PARAM id="lforatesubdivision" value="9.0"/><PARAM id="lfotimemode" value="0.0"/><PARAM id="lfomode" value="0.0"/><PARAM id="lfopolarity" value="1.0"/><PARAM id="lfophase" value="0.0"/><PARAM id="lfotriggerbutton" value="1.0"/><PARAM id="lfotriggerjack" value="1.0"/><PARAM id="lfotriggernoteon" value="1.0"/><PARAM id="rndlforatesync" value="1.0"/><PARAM id="rndrate" value="5.000000476837158"/><PARAM id="rndratesubdivision" value="9.0"/><PARAM id="rndtimemode" value="0.0"/><PARAM id="rndpolarity" value="0.0"/><PARAM id="rnddensity" value="100.0"/><PARAM id="rndsmoothing" value="0.0"/><PARAM id="rndtriggerbutton" value="0.0"/><PARAM id="rndtriggerjack" value="0.0"/><PARAM id="rndtriggernoteon" value="0.0"/><PARAM id="taptempoenable" value="1.0"/><PARAM id="macro" value="100.0"/><PARAM id="mxsource1" value="10.0"/><PARAM id="mxsource2" value="4.0"/><PARAM id="mxsource3" value="2.0"/><PARAM id="mxsource4" value="0.0"/><PARAM id="mxdesta" value="4.0"/><PARAM id="mxdestb" value="3.0"/><PARAM id="mxdestc" value="25.0"/><PARAM id="mxdestd" value="6.0"/><PARAM id="mxnode1a" value="100.0"/><PARAM id="mxnode1b" value="0.0"/><PARAM id="mxnode1c" value="0.0"/><PARAM id="mxnode1d" value="0.0"/><PARAM id="mxnode2a" value="0.0"/><PARAM id="mxnode2b" value="29.49996948242188"/><PARAM id="mxnode2c" value="0.0"/><PARAM id="mxnode2d" value="0.0"/><PARAM id="mxnode3a" value="0.0"/><PARAM id="mxnode3b" value="0.0"/><PARAM id="mxnode3c" value="29.99996948242188"/><PARAM id="mxnode3d" value="35.49996948242188"/><PARAM id="mxnode4a" value="0.0"/><PARAM id="mxnode4b" value="0.0"/><PARAM id="mxnode4c" value="0.0"/><PARAM id="mxnode4d" value="0.0"/><PARAM id="mxnode1alock" value="0.0"/><PARAM id="mxnode1block" value="0.0"/><PARAM id="mxnode1clock" value="0.0"/><PARAM id="mxnode1dlock" value="0.0"/><PARAM id="mxnode2alock" value="0.0"/><PARAM id="mxnode2block" value="0.0"/><PARAM id="mxnode2clock" value="0.0"/><PARAM id="mxnode2dlock" value="0.0"/><PARAM id="mxnode3alock" value="0.0"/><PARAM id="mxnode3block" value="0.0"/><PARAM id="mxnode3clock" value="0.0"/><PARAM id="mxnode3dlock" value="0.0"/><PARAM id="mxnode4alock" value="0.0"/><PARAM id="mxnode4block" value="0.0"/><PARAM id="mxnode4clock" value="0.0"/><PARAM id="mxnode4dlock" value="0.0"/><PARAM id="monitormix" value="100.0"/><PARAM id="pickupbehaviour" value="0.0"/><Quantiser program="0"/></Parameters><Notes text=""/></SeashellPreset> 
]] },
  [37] = { name = "ACME Ray Gun", raw = [[
VC2!$  <?xml version="1.0" encoding="UTF-8"?> <SeashellPreset><Version major="2" minor="0" patch="0" tweak="0"/><Parameters><PARAM id="osc1frequency" value="-0.4200000762939453"/><PARAM id="osc2frequency" value="-0.2224998474121094"/><PARAM id="lfonoff" value="0.0"/><PARAM id="octaverange" value="5.0"/><PARAM id="sync" value="0.0"/><PARAM id="1voctrouting" value="3.0"/><PARAM id="transpose" value="0.0"/><PARAM id="portamento" value="0.0"/><PARAM id="midipitchbend" value="2.0"/><PARAM id="wavefoldinput" value="0.0"/><PARAM id="folddepth" value="0.1342855393886566"/><PARAM id="foldbias" value="0.0"/><PARAM id="foldbiasanimate" value="50.0"/><PARAM id="pulsewidth" value="50.0"/><PARAM id="pwmanimate" value="50.0"/><PARAM id="animateonoff" value="1.0"/><PARAM id="waveformselect" value="0.0"/><PARAM id="filtercutoff" value="4.458433151245117"/><PARAM id="filterkeytrack" value="0.0"/><PARAM id="outputlevel" value="100.0"/><PARAM id="diffuseamount" value="26.25000381469727"/><PARAM id="envmode" value="0.0"/><PARAM id="envattack" value="0.001425863360054791"/><PARAM id="envdecay" value="0.9199976921081543"/><PARAM id="envsustain" value="50.0"/><PARAM id="envrelease" value="0.9199976921081543"/><PARAM id="envshape" value="1.0"/><PARAM id="envgate" value="1.0"/><PARAM id="envretrigonoff" value="1.0"/><PARAM id="envtriggerbutton" value="1.0"/><PARAM id="envtriggerjack" value="1.0"/><PARAM id="envtriggernoteon" value="1.0"/><PARAM id="extend" value="1.0"/><PARAM id="lforate" value="20.0"/><PARAM id="lforatesubdivision" value="9.0"/><PARAM id="lfotimemode" value="0.0"/><PARAM id="lfomode" value="0.0"/><PARAM id="lfopolarity" value="1.0"/><PARAM id="lfophase" value="0.0"/><PARAM id="lfotriggerbutton" value="1.0"/><PARAM id="lfotriggerjack" value="1.0"/><PARAM id="lfotriggernoteon" value="1.0"/><PARAM id="rndlforatesync" value="1.0"/><PARAM id="rndrate" value="5.000000476837158"/><PARAM id="rndratesubdivision" value="9.0"/><PARAM id="rndtimemode" value="0.0"/><PARAM id="rndpolarity" value="0.0"/><PARAM id="rnddensity" value="100.0"/><PARAM id="rndsmoothing" value="0.0"/><PARAM id="rndtriggerbutton" value="0.0"/><PARAM id="rndtriggerjack" value="0.0"/><PARAM id="rndtriggernoteon" value="0.0"/><PARAM id="taptempoenable" value="1.0"/><PARAM id="macro" value="100.0"/><PARAM id="mxsource1" value="4.0"/><PARAM id="mxsource2" value="12.0"/><PARAM id="mxsource3" value="0.0"/><PARAM id="mxsource4" value="0.0"/><PARAM id="mxdesta" value="11.0"/><PARAM id="mxdestb" value="7.0"/><PARAM id="mxdestc" value="3.0"/><PARAM id="mxdestd" value="0.0"/><PARAM id="mxnode1a" value="100.0"/><PARAM id="mxnode1b" value="45.5"/><PARAM id="mxnode1c" value="49.5"/><PARAM id="mxnode1d" value="0.0"/><PARAM id="mxnode2a" value="12.50001525878906"/><PARAM id="mxnode2b" value="25.5"/><PARAM id="mxnode2c" value="0.0"/><PARAM id="mxnode2d" value="0.0"/><PARAM id="mxnode3a" value="0.0"/><PARAM id="mxnode3b" value="0.0"/><PARAM id="mxnode3c" value="0.0"/><PARAM id="mxnode3d" value="0.0"/><PARAM id="mxnode4a" value="0.0"/><PARAM id="mxnode4b" value="0.0"/><PARAM id="mxnode4c" value="0.0"/><PARAM id="mxnode4d" value="0.0"/><PARAM id="mxnode1alock" value="0.0"/><PARAM id="mxnode1block" value="0.0"/><PARAM id="mxnode1clock" value="0.0"/><PARAM id="mxnode1dlock" value="0.0"/><PARAM id="mxnode2alock" value="0.0"/><PARAM id="mxnode2block" value="0.0"/><PARAM id="mxnode2clock" value="0.0"/><PARAM id="mxnode2dlock" value="0.0"/><PARAM id="mxnode3alock" value="0.0"/><PARAM id="mxnode3block" value="0.0"/><PARAM id="mxnode3clock" value="0.0"/><PARAM id="mxnode3dlock" value="0.0"/><PARAM id="mxnode4alock" value="0.0"/><PARAM id="mxnode4block" value="0.0"/><PARAM id="mxnode4clock" value="0.0"/><PARAM id="mxnode4dlock" value="0.0"/><PARAM id="monitormix" value="100.0"/><PARAM id="pickupbehaviour" value="0.0"/><Quantiser program="0"/></Parameters><Notes text=""/></SeashellPreset> 
]] },
  [38] = { name = "Kurtz", raw = [[
VC2!l  <?xml version="1.0" encoding="UTF-8"?> <SeashellPreset><Version major="2" minor="0" patch="0" tweak="0"/><Parameters><PARAM id="osc1frequency" value="0.0"/><PARAM id="osc2frequency" value="-0.06061160564422607"/><PARAM id="lfonoff" value="0.0"/><PARAM id="octaverange" value="5.0"/><PARAM id="sync" value="0.0"/><PARAM id="1voctrouting" value="3.0"/><PARAM id="transpose" value="2.0"/><PARAM id="portamento" value="0.0"/><PARAM id="midipitchbend" value="2.0"/><PARAM id="wavefoldinput" value="0.0"/><PARAM id="folddepth" value="0.1342855393886566"/><PARAM id="foldbias" value="0.0"/><PARAM id="foldbiasanimate" value="59.99999237060547"/><PARAM id="pulsewidth" value="50.0"/><PARAM id="pwmanimate" value="74.75"/><PARAM id="animateonoff" value="1.0"/><PARAM id="waveformselect" value="0.0"/><PARAM id="filtercutoff" value="23.90867614746094"/><PARAM id="filterkeytrack" value="0.0"/><PARAM id="outputlevel" value="100.0"/><PARAM id="diffuseamount" value="28.24999046325684"/><PARAM id="envmode" value="2.0"/><PARAM id="envattack" value="2.253501892089844"/><PARAM id="envdecay" value="2.233372211456299"/><PARAM id="envsustain" value="50.0"/><PARAM id="envrelease" value="2.233372211456299"/><PARAM id="envshape" value="1.0"/><PARAM id="envgate" value="0.0"/><PARAM id="envretrigonoff" value="1.0"/><PARAM id="envtriggerbutton" value="1.0"/><PARAM id="envtriggerjack" value="1.0"/><PARAM id="envtriggernoteon" value="1.0"/><PARAM id="extend" value="1.0"/><PARAM id="lforate" value="10.95200252532959"/><PARAM id="lforatesubdivision" value="9.0"/><PARAM id="lfotimemode" value="0.0"/><PARAM id="lfomode" value="0.0"/><PARAM id="lfopolarity" value="0.0"/><PARAM id="lfophase" value="0.0"/><PARAM id="lfotriggerbutton" value="1.0"/><PARAM id="lfotriggerjack" value="1.0"/><PARAM id="lfotriggernoteon" value="1.0"/><PARAM id="rndlforatesync" value="1.0"/><PARAM id="rndrate" value="5.000000476837158"/><PARAM id="rndratesubdivision" value="9.0"/><PARAM id="rndtimemode" value="0.0"/><PARAM id="rndpolarity" value="0.0"/><PARAM id="rnddensity" value="100.0"/><PARAM id="rndsmoothing" value="0.0"/><PARAM id="rndtriggerbutton" value="0.0"/><PARAM id="rndtriggerjack" value="0.0"/><PARAM id="rndtriggernoteon" value="0.0"/><PARAM id="taptempoenable" value="1.0"/><PARAM id="macro" value="100.0"/><PARAM id="mxsource1" value="10.0"/><PARAM id="mxsource2" value="4.0"/><PARAM id="mxsource3" value="2.0"/><PARAM id="mxsource4" value="0.0"/><PARAM id="mxdesta" value="3.0"/><PARAM id="mxdestb" value="7.0"/><PARAM id="mxdestc" value="9.0"/><PARAM id="mxdestd" value="6.0"/><PARAM id="mxnode1a" value="10.99999237060547"/><PARAM id="mxnode1b" value="60.49996948242188"/><PARAM id="mxnode1c" value="-5.0"/><PARAM id="mxnode1d" value="0.0"/><PARAM id="mxnode2a" value="13.99998474121094"/><PARAM id="mxnode2b" value="12.49998474121094"/><PARAM id="mxnode2c" value="0.0"/><PARAM id="mxnode2d" value="47.49996948242188"/><PARAM id="mxnode3a" value="0.0"/><PARAM id="mxnode3b" value="12.49998474121094"/><PARAM id="mxnode3c" value="0.0"/><PARAM id="mxnode3d" value="0.0"/><PARAM id="mxnode4a" value="0.0"/><PARAM id="mxnode4b" value="0.0"/><PARAM id="mxnode4c" value="0.0"/><PARAM id="mxnode4d" value="0.0"/><PARAM id="mxnode1alock" value="0.0"/><PARAM id="mxnode1block" value="0.0"/><PARAM id="mxnode1clock" value="0.0"/><PARAM id="mxnode1dlock" value="0.0"/><PARAM id="mxnode2alock" value="0.0"/><PARAM id="mxnode2block" value="0.0"/><PARAM id="mxnode2clock" value="0.0"/><PARAM id="mxnode2dlock" value="0.0"/><PARAM id="mxnode3alock" value="0.0"/><PARAM id="mxnode3block" value="0.0"/><PARAM id="mxnode3clock" value="0.0"/><PARAM id="mxnode3dlock" value="0.0"/><PARAM id="mxnode4alock" value="0.0"/><PARAM id="mxnode4block" value="0.0"/><PARAM id="mxnode4clock" value="0.0"/><PARAM id="mxnode4dlock" value="0.0"/><PARAM id="monitormix" value="100.0"/><PARAM id="pickupbehaviour" value="0.0"/><Quantiser program="0"/></Parameters><Notes text=""/></SeashellPreset> 
]] },
  [39] = { name = "Red Alert", raw = [[
VC2!û  <?xml version="1.0" encoding="UTF-8"?> <SeashellPreset><Version major="2" minor="0" patch="0" tweak="0"/><Parameters><PARAM id="osc1frequency" value="0.0"/><PARAM id="osc2frequency" value="0.009338974952697754"/><PARAM id="lfonoff" value="0.0"/><PARAM id="octaverange" value="5.0"/><PARAM id="sync" value="0.0"/><PARAM id="1voctrouting" value="3.0"/><PARAM id="transpose" value="0.0"/><PARAM id="portamento" value="0.0"/><PARAM id="midipitchbend" value="2.0"/><PARAM id="wavefoldinput" value="0.0"/><PARAM id="folddepth" value="0.0"/><PARAM id="foldbias" value="0.0"/><PARAM id="foldbiasanimate" value="50.0"/><PARAM id="pulsewidth" value="50.0"/><PARAM id="pwmanimate" value="50.0"/><PARAM id="animateonoff" value="0.0"/><PARAM id="waveformselect" value="1.0"/><PARAM id="filtercutoff" value="86.26625061035156"/><PARAM id="filterkeytrack" value="44.49996948242188"/><PARAM id="outputlevel" value="100.0"/><PARAM id="diffuseamount" value="27.00000762939453"/><PARAM id="envmode" value="0.0"/><PARAM id="envattack" value="0.0"/><PARAM id="envdecay" value="1.08731210231781"/><PARAM id="envsustain" value="50.0"/><PARAM id="envrelease" value="1.0"/><PARAM id="envshape" value="1.0"/><PARAM id="envgate" value="0.0"/><PARAM id="envretrigonoff" value="1.0"/><PARAM id="envtriggerbutton" value="1.0"/><PARAM id="envtriggerjack" value="1.0"/><PARAM id="envtriggernoteon" value="1.0"/><PARAM id="extend" value="1.0"/><PARAM id="lforate" value="1.0010826587677"/><PARAM id="lforatesubdivision" value="9.0"/><PARAM id="lfotimemode" value="0.0"/><PARAM id="lfomode" value="2.0"/><PARAM id="lfopolarity" value="0.0"/><PARAM id="lfophase" value="0.0"/><PARAM id="lfotriggerbutton" value="1.0"/><PARAM id="lfotriggerjack" value="1.0"/><PARAM id="lfotriggernoteon" value="1.0"/><PARAM id="rndlforatesync" value="1.0"/><PARAM id="rndrate" value="5.000000476837158"/><PARAM id="rndratesubdivision" value="9.0"/><PARAM id="rndtimemode" value="0.0"/><PARAM id="rndpolarity" value="0.0"/><PARAM id="rnddensity" value="100.0"/><PARAM id="rndsmoothing" value="0.0"/><PARAM id="rndtriggerbutton" value="0.0"/><PARAM id="rndtriggerjack" value="0.0"/><PARAM id="rndtriggernoteon" value="0.0"/><PARAM id="taptempoenable" value="1.0"/><PARAM id="macro" value="100.0"/><PARAM id="mxsource1" value="13.0"/><PARAM id="mxsource2" value="0.0"/><PARAM id="mxsource3" value="0.0"/><PARAM id="mxsource4" value="0.0"/><PARAM id="mxdesta" value="11.0"/><PARAM id="mxdestb" value="4.0"/><PARAM id="mxdestc" value="0.0"/><PARAM id="mxdestd" value="0.0"/><PARAM id="mxnode1a" value="-11.50004577636719"/><PARAM id="mxnode1b" value="100.0"/><PARAM id="mxnode1c" value="0.0"/><PARAM id="mxnode1d" value="0.0"/><PARAM id="mxnode2a" value="0.0"/><PARAM id="mxnode2b" value="0.0"/><PARAM id="mxnode2c" value="0.0"/><PARAM id="mxnode2d" value="0.0"/><PARAM id="mxnode3a" value="0.0"/><PARAM id="mxnode3b" value="0.0"/><PARAM id="mxnode3c" value="0.0"/><PARAM id="mxnode3d" value="0.0"/><PARAM id="mxnode4a" value="0.0"/><PARAM id="mxnode4b" value="0.0"/><PARAM id="mxnode4c" value="0.0"/><PARAM id="mxnode4d" value="0.0"/><PARAM id="mxnode1alock" value="0.0"/><PARAM id="mxnode1block" value="0.0"/><PARAM id="mxnode1clock" value="0.0"/><PARAM id="mxnode1dlock" value="0.0"/><PARAM id="mxnode2alock" value="0.0"/><PARAM id="mxnode2block" value="0.0"/><PARAM id="mxnode2clock" value="0.0"/><PARAM id="mxnode2dlock" value="0.0"/><PARAM id="mxnode3alock" value="0.0"/><PARAM id="mxnode3block" value="0.0"/><PARAM id="mxnode3clock" value="0.0"/><PARAM id="mxnode3dlock" value="0.0"/><PARAM id="mxnode4alock" value="0.0"/><PARAM id="mxnode4block" value="0.0"/><PARAM id="mxnode4clock" value="0.0"/><PARAM id="mxnode4dlock" value="0.0"/><PARAM id="monitormix" value="100.0"/><PARAM id="pickupbehaviour" value="0.0"/><Quantiser program="0"/></Parameters><Notes text=""/></SeashellPreset>   
]] },
  [40] = { name = "Ring Ring", raw = [[
VC2!1  <?xml version="1.0" encoding="UTF-8"?> <SeashellPreset><Version major="2" minor="0" patch="0" tweak="0"/><Parameters><PARAM id="osc1frequency" value="0.0"/><PARAM id="osc2frequency" value="0.1799997091293335"/><PARAM id="lfonoff" value="0.0"/><PARAM id="octaverange" value="5.0"/><PARAM id="sync" value="0.0"/><PARAM id="1voctrouting" value="0.0"/><PARAM id="transpose" value="0.0"/><PARAM id="portamento" value="0.0"/><PARAM id="midipitchbend" value="2.0"/><PARAM id="wavefoldinput" value="0.0"/><PARAM id="folddepth" value="0.2502593994140625"/><PARAM id="foldbias" value="0.0"/><PARAM id="foldbiasanimate" value="0.4211682677268982"/><PARAM id="pulsewidth" value="50.0"/><PARAM id="pwmanimate" value="0.4211682677268982"/><PARAM id="animateonoff" value="0.0"/><PARAM id="waveformselect" value="6.0"/><PARAM id="filtercutoff" value="59.73265075683594"/><PARAM id="filterkeytrack" value="0.0"/><PARAM id="outputlevel" value="0.0"/><PARAM id="diffuseamount" value="0.0"/><PARAM id="envmode" value="1.0"/><PARAM id="envattack" value="1.331680417060852"/><PARAM id="envdecay" value="0.4765294790267944"/><PARAM id="envsustain" value="100.0"/><PARAM id="envrelease" value="0.3861320912837982"/><PARAM id="envshape" value="1.0"/><PARAM id="envgate" value="1.0"/><PARAM id="envretrigonoff" value="1.0"/><PARAM id="envtriggerbutton" value="1.0"/><PARAM id="envtriggerjack" value="1.0"/><PARAM id="envtriggernoteon" value="1.0"/><PARAM id="extend" value="1.0"/><PARAM id="lforate" value="10.47563076019287"/><PARAM id="lforatesubdivision" value="9.0"/><PARAM id="lfotimemode" value="0.0"/><PARAM id="lfomode" value="0.0"/><PARAM id="lfopolarity" value="1.0"/><PARAM id="lfophase" value="0.0"/><PARAM id="lfotriggerbutton" value="0.0"/><PARAM id="lfotriggerjack" value="0.0"/><PARAM id="lfotriggernoteon" value="0.0"/><PARAM id="rndlforatesync" value="1.0"/><PARAM id="rndrate" value="5.000000476837158"/><PARAM id="rndratesubdivision" value="9.0"/><PARAM id="rndtimemode" value="0.0"/><PARAM id="rndpolarity" value="0.0"/><PARAM id="rnddensity" value="100.0"/><PARAM id="rndsmoothing" value="0.0"/><PARAM id="rndtriggerbutton" value="0.0"/><PARAM id="rndtriggerjack" value="0.0"/><PARAM id="rndtriggernoteon" value="0.0"/><PARAM id="taptempoenable" value="1.0"/><PARAM id="macro" value="99.96337890625"/><PARAM id="mxsource1" value="23.0"/><PARAM id="mxsource2" value="12.0"/><PARAM id="mxsource3" value="0.0"/><PARAM id="mxsource4" value="0.0"/><PARAM id="mxdesta" value="4.0"/><PARAM id="mxdestb" value="18.0"/><PARAM id="mxdestc" value="0.0"/><PARAM id="mxdestd" value="0.0"/><PARAM id="mxnode1a" value="100.0"/><PARAM id="mxnode1b" value="0.0"/><PARAM id="mxnode1c" value="0.0"/><PARAM id="mxnode1d" value="0.0"/><PARAM id="mxnode2a" value="0.0"/><PARAM id="mxnode2b" value="11.49999237060547"/><PARAM id="mxnode2c" value="0.0"/><PARAM id="mxnode2d" value="0.0"/><PARAM id="mxnode3a" value="0.0"/><PARAM id="mxnode3b" value="0.0"/><PARAM id="mxnode3c" value="0.0"/><PARAM id="mxnode3d" value="0.0"/><PARAM id="mxnode4a" value="0.0"/><PARAM id="mxnode4b" value="0.0"/><PARAM id="mxnode4c" value="0.0"/><PARAM id="mxnode4d" value="0.0"/><PARAM id="mxnode1alock" value="0.0"/><PARAM id="mxnode1block" value="0.0"/><PARAM id="mxnode1clock" value="0.0"/><PARAM id="mxnode1dlock" value="0.0"/><PARAM id="mxnode2alock" value="0.0"/><PARAM id="mxnode2block" value="0.0"/><PARAM id="mxnode2clock" value="0.0"/><PARAM id="mxnode2dlock" value="0.0"/><PARAM id="mxnode3alock" value="0.0"/><PARAM id="mxnode3block" value="0.0"/><PARAM id="mxnode3clock" value="0.0"/><PARAM id="mxnode3dlock" value="0.0"/><PARAM id="mxnode4alock" value="0.0"/><PARAM id="mxnode4block" value="0.0"/><PARAM id="mxnode4clock" value="0.0"/><PARAM id="mxnode4dlock" value="0.0"/><PARAM id="monitormix" value="100.0"/><PARAM id="pickupbehaviour" value="0.0"/><Quantiser program="0"/></Parameters><Notes text=""/></SeashellPreset> 
]] },
  [41] = { name = "Sound of the Future", raw = [[
VC2!  <?xml version="1.0" encoding="UTF-8"?> <SeashellPreset><Version major="2" minor="0" patch="0" tweak="0"/><Parameters><PARAM id="osc1frequency" value="0.007019519805908203"/><PARAM id="osc2frequency" value="0.0"/><PARAM id="lfonoff" value="0.0"/><PARAM id="octaverange" value="5.0"/><PARAM id="sync" value="0.0"/><PARAM id="1voctrouting" value="3.0"/><PARAM id="transpose" value="0.0"/><PARAM id="portamento" value="0.0"/><PARAM id="midipitchbend" value="2.0"/><PARAM id="wavefoldinput" value="0.0"/><PARAM id="folddepth" value="0.0"/><PARAM id="foldbias" value="0.0"/><PARAM id="foldbiasanimate" value="50.0"/><PARAM id="pulsewidth" value="50.0"/><PARAM id="pwmanimate" value="50.0"/><PARAM id="animateonoff" value="0.0"/><PARAM id="waveformselect" value="4.0"/><PARAM id="filtercutoff" value="99.969482421875"/><PARAM id="filterkeytrack" value="0.0"/><PARAM id="outputlevel" value="100.0"/><PARAM id="diffuseamount" value="36.25003051757812"/><PARAM id="envmode" value="1.0"/><PARAM id="envattack" value="0.001425863010808825"/><PARAM id="envdecay" value="0.0"/><PARAM id="envsustain" value="50.0"/><PARAM id="envrelease" value="0.4151345193386078"/><PARAM id="envshape" value="1.0"/><PARAM id="envgate" value="1.0"/><PARAM id="envretrigonoff" value="1.0"/><PARAM id="envtriggerbutton" value="1.0"/><PARAM id="envtriggerjack" value="1.0"/><PARAM id="envtriggernoteon" value="1.0"/><PARAM id="extend" value="1.0"/><PARAM id="lforate" value="6.903134822845459"/><PARAM id="lforatesubdivision" value="9.0"/><PARAM id="lfotimemode" value="0.0"/><PARAM id="lfomode" value="0.0"/><PARAM id="lfopolarity" value="0.0"/><PARAM id="lfophase" value="0.0"/><PARAM id="lfotriggerbutton" value="1.0"/><PARAM id="lfotriggerjack" value="1.0"/><PARAM id="lfotriggernoteon" value="1.0"/><PARAM id="rndlforatesync" value="1.0"/><PARAM id="rndrate" value="5.000000476837158"/><PARAM id="rndratesubdivision" value="9.0"/><PARAM id="rndtimemode" value="0.0"/><PARAM id="rndpolarity" value="0.0"/><PARAM id="rnddensity" value="100.0"/><PARAM id="rndsmoothing" value="0.0"/><PARAM id="rndtriggerbutton" value="0.0"/><PARAM id="rndtriggerjack" value="0.0"/><PARAM id="rndtriggernoteon" value="0.0"/><PARAM id="taptempoenable" value="1.0"/><PARAM id="macro" value="57.27278137207031"/><PARAM id="mxsource1" value="14.0"/><PARAM id="mxsource2" value="2.0"/><PARAM id="mxsource3" value="0.0"/><PARAM id="mxsource4" value="0.0"/><PARAM id="mxdesta" value="14.0"/><PARAM id="mxdestb" value="25.0"/><PARAM id="mxdestc" value="0.0"/><PARAM id="mxdestd" value="0.0"/><PARAM id="mxnode1a" value="80.5"/><PARAM id="mxnode1b" value="0.0"/><PARAM id="mxnode1c" value="0.0"/><PARAM id="mxnode1d" value="0.0"/><PARAM id="mxnode2a" value="0.0"/><PARAM id="mxnode2b" value="42.99996948242188"/><PARAM id="mxnode2c" value="0.0"/><PARAM id="mxnode2d" value="0.0"/><PARAM id="mxnode3a" value="0.0"/><PARAM id="mxnode3b" value="0.0"/><PARAM id="mxnode3c" value="0.0"/><PARAM id="mxnode3d" value="0.0"/><PARAM id="mxnode4a" value="0.0"/><PARAM id="mxnode4b" value="0.0"/><PARAM id="mxnode4c" value="0.0"/><PARAM id="mxnode4d" value="0.0"/><PARAM id="mxnode1alock" value="0.0"/><PARAM id="mxnode1block" value="0.0"/><PARAM id="mxnode1clock" value="0.0"/><PARAM id="mxnode1dlock" value="0.0"/><PARAM id="mxnode2alock" value="0.0"/><PARAM id="mxnode2block" value="0.0"/><PARAM id="mxnode2clock" value="0.0"/><PARAM id="mxnode2dlock" value="0.0"/><PARAM id="mxnode3alock" value="0.0"/><PARAM id="mxnode3block" value="0.0"/><PARAM id="mxnode3clock" value="0.0"/><PARAM id="mxnode3dlock" value="0.0"/><PARAM id="mxnode4alock" value="0.0"/><PARAM id="mxnode4block" value="0.0"/><PARAM id="mxnode4clock" value="0.0"/><PARAM id="mxnode4dlock" value="0.0"/><PARAM id="monitormix" value="100.0"/><PARAM id="pickupbehaviour" value="0.0"/><Quantiser program="0"/></Parameters><Notes text=""/></SeashellPreset> 
]] },
}

-- Value formatter for the preset selector control label
function formatPresetName(valueObject, value)
  local idx = math.floor(tonumber(value) or -1)
  local p = PRESETS[idx]
  if p then
    return p.name
  end
  return "Preset " .. tostring(value)
end

-- helper function to round positive number to nearest integer
local function round(x)
    return math.floor(x + 0.5)
end

-- helper for converting scaled lfo rates to 0-127 values
local function lfoScaleReverse(freq)
  -- ensure median is a frequency of 5.0 
  local l = math.log(5.0 / C3_HZ) / math.log(0.5)
  -- implied 14-bit MIDI value 
  local x = MIDI_MAX*( (freq / C3_HZ)^(1.0 / l) )
  return round(x) -- Round to nearest integer
end


-- scale display parameter value to 0..MIDI_MAX 
local function scaleSymmetric(x, min, max) return round(((x - min) * MIDI_MAX) / (max - min)) end

 -- map 0,1,..N values to corresponding 0..127 values
 local function map0N(x, max)
  x = tonumber(x) or 0
  if x <= 0 then return 0 end
  if x >= max then return 127 end
  return round((x * MIDI_MAX) / max)
end

-- map 1..N values to 0..127
local function map1N(x, max)
  x = tonumber(x) or 1
  if x <= 1 then return 0 end
  if x >= max then return 127 end
  return round(((x - 1) * 127) / (max - 1))
end

-- helper to convert seashell preset file into table of 94 scaled parameters 
local function parsePresetParameters(pm_raw)
  local pm = {}
  for value in pm_raw:gmatch('value%s*=%s*"([^"]+)"') do
    local n = tonumber(value)
    if n ~= nil then
      pm[#pm + 1] = n
    end
  end

  -- convert preset parameter values to 7-bit MIDI values
  pm[1]  = scaleSymmetric(pm[1], -1, 1) -- -1..1
  pm[2]  = scaleSymmetric(pm[2], -1, 1)
  pm[3]  = map0N(pm[3],1)
  pm[4]  = map1N(pm[4],6)
  pm[5]  = map0N(pm[5],3)
  pm[6]  = map0N(pm[6],3)
  pm[7]  = map0N(pm[7],3)
  pm[8]  = map0N(pm[8], 100) -- 0..100
  pm[9]  = map1N(pm[9],12)
  pm[10] = map0N(pm[10],1)
  pm[11] = map0N(pm[11], 100)
  pm[12] = map0N(pm[12], 100)
  pm[13] = map0N(pm[13], 100)
  pm[14] = map0N(pm[14], 100)
  pm[15] = map0N(pm[15], 100)
  pm[16] = map0N(pm[16],1)
  pm[17] = map0N(pm[17],7)
  pm[18] = map0N(pm[18], 100) 
  pm[19] = scaleSymmetric(pm[19], -100, 100) -- -100..100
  pm[20] = map0N(pm[20], 100) 
  pm[21] = map0N(pm[21], 100)
  pm[22] = map0N(pm[22],2)
  pm[23] = map0N(pm[23], 10) -- 0..10
  pm[24] = map0N(pm[24], 10)
  pm[25] = map0N(pm[25], 100)
  pm[26] = map0N(pm[26], 10)
  pm[27] = map0N(pm[27],1)
  pm[28] = map0N(pm[28],1)
  pm[29] = map0N(pm[29],1)
  pm[30] = map0N(pm[30],1)
  pm[31] = map0N(pm[31],1)
  pm[32] = map0N(pm[32],1)
  pm[33] = map0N(pm[33],1)
  pm[34] = round(lfoScaleReverse(pm[34]))  -- lfo rate
  pm[35] = map0N(pm[35],18)
  pm[36] = map0N(pm[36],1)
  pm[37] = map0N(pm[37],2)
  pm[38] = map0N(pm[38],1)
  pm[39] = round(((180+pm[39])*MIDI_MAX)/360) -- -180..180
  pm[40] = map0N(pm[40],1)
  pm[41] = map0N(pm[41],1)
  pm[42] = map0N(pm[42],1)
  pm[43] = map0N(pm[43],1)
  pm[44] = round(lfoScaleReverse(pm[44]))  -- random rate
  pm[45] = map0N(pm[45],18)
  pm[46] = map0N(pm[46],1)
  pm[47] = map0N(pm[47],1)
  pm[48] = map0N(pm[48], 100)
  pm[49] = map0N(pm[49], 100)
  pm[50] = map0N(pm[50],1)
  pm[51] = map0N(pm[51],1)
  pm[52] = map0N(pm[52],1)
  pm[53] = map0N(pm[53],1)
  pm[54] = map0N(pm[54], 100)

  for i = 63,78 do
    pm[i] = scaleSymmetric(pm[i], -100, 100) -- -100..100
  end
  for i = 79,94 do
    pm[i] = map0N(pm[i],1)
  end
  return pm
end

-- Set parameters from parsed preset
local function applyPresetParameters(pm)
  for i = 1, #pm-2 do -- there is no MIDI CC for the last 2 preset params (monitor mix, control behavior)
    local pNum = i - 1
    -- lock params (78..93) are not in the parameter map; lock state is handled by applyLockStates()
    if pNum < 78 or pNum > 93 then
      local v = pm[i] or 0
      if v > 16383 then print("pNum = "..pNum) end
      parameterMap.updateValue(deviceId, PT_VIRTUAL, pNum, v)
    end
  end
end

--------- block to handle sync of random rate/notes to lfo rate/notes ---------------------

-- guard to avoid re-entrant loops when we set RND_RATE from inside onChange
local syncingRndToLfo = false

-- if sync is enabled, force RND mode/value to follow LFO mode/value
local function applyRndLfoSync()
  if syncingRndToLfo then return end
  local sync = parameterMap.get(deviceId, PT_VIRTUAL, SYNC_TO_LFO) or 0
  if sync ~= 127 then return end
  syncingRndToLfo = true

  local lfoMode = parameterMap.get(deviceId, PT_VIRTUAL, LFO_RATE_TYPE) or 0
  local rndMode = parameterMap.get(deviceId, PT_VIRTUAL, RND_RATE_TYPE) or 0

  -- 1) align RND mode to LFO mode
  if rndMode ~= lfoMode then
    parameterMap.set(deviceId, PT_VIRTUAL, RND_RATE_TYPE, lfoMode)
    midi.sendControlChange(port, channel, RND_RATE_TYPE, lfoMode)
  end

  -- 2) align value in the active mode, and send mirrored param too
  if lfoMode == 127 then
    -- note-sync mode: copy LFO_NOTE -> RND_NOTE
    local lfoNote = parameterMap.get(deviceId, PT_VIRTUAL, LFO_NOTE) or 0
    local rndNote = parameterMap.get(deviceId, PT_VIRTUAL, RND_NOTE) or -1
    if rndNote ~= lfoNote then
      parameterMap.set(deviceId, PT_VIRTUAL, RND_NOTE, lfoNote)
      midi.sendControlChange(port, channel, RND_NOTE, lfoNote)
    end
  else
    -- free-rate mode: copy LFO_RATE -> RND_RATE
    local lfoRate = parameterMap.get(deviceId, PT_VIRTUAL, LFO_RATE) or 0
    local rndRate = parameterMap.get(deviceId, PT_VIRTUAL, RND_RATE) or -1
    if rndRate ~= lfoRate then
      parameterMap.set(deviceId, PT_VIRTUAL, RND_RATE, lfoRate)
      midi.sendControlChange(port, channel, RND_RATE, lfoRate)
    end
  end
  syncingRndToLfo = false
end

-- ---------------- Mod amount macro bipolar scaling ----------------
local PARAM_MACRO_KNOB = 10038
local MACRO_MAX = 200
local MACRO_CENTER = 100

local macroKnobValue = 200   -- default = full effect (factor 1)
local macroApplying = false    -- guard so applyMacroToAll doesn't re-derive base

local function macroFactor()
  if macroKnobValue == MACRO_CENTER then
    return 0
  elseif macroKnobValue < MACRO_CENTER then
    return (macroKnobValue - MACRO_CENTER) / MACRO_CENTER
  else
    return (macroKnobValue - MACRO_CENTER) / (MACRO_MAX - MACRO_CENTER)
  end
end

-- reuse the mod-amount param numbers already defined for the matrix
local PARAM_MOD_AMOUNT = MOD_AMOUNT_PARAM   -- {62..77}
local PARAM_MOD_AMOUNT_INDEX = {}
for i, p in ipairs(PARAM_MOD_AMOUNT) do PARAM_MOD_AMOUNT_INDEX[p] = i end

local modAmountBase = {}
for i = 1, 16 do modAmountBase[i] = 64 end

function displayMacroPercent(valueObject, value)
  local factor
  if value == MACRO_CENTER then
    factor = 0
  elseif value < MACRO_CENTER then
    factor = (value - MACRO_CENTER) / MACRO_CENTER
  else
    factor = (value - MACRO_CENTER) / (MACRO_MAX - MACRO_CENTER)
  end
  return string.format("%+d %%", math.floor(factor * 100 + 0.5))
end

-- ============================================================
-- Seashell mod matrix dimming + lock state (single source of truth)
-- ============================================================

local orange = { off = 0x572700, on = ORANGE }

-- lock params 78..93, row-major (flat index 1..16, same ordering as MOD_AMOUNT_PARAM)
local PARAM_MOD_LOCK = {78,79,80,81,82,83,84,85,86,87,88,89,90,91,92,93}

local PARAM_MOD_LOCK_INDEX = {}
for i, p in ipairs(PARAM_MOD_LOCK) do PARAM_MOD_LOCK_INDEX[p] = i end

-- mod amount control ids (there are no separate lock controls; lock state is shown by recoloring the amount control)
-- CTRL_MATRIX_CELL[row][col] = amount control
local CTRL_MATRIX_CELL = {
  { 46, 47, 48, 49 },
  { 50, 51, 52, 53 },
  { 54, 55, 56, 57 },
  { 58, 59, 60, 61 },
}

-- reverse lookup: amount control id -> flat index 1..16 (row-major)
local CTRL_MOD_AMOUNT_INDEX = {}
for row = 1, 4 do
  for col = 1, 4 do
    CTRL_MOD_AMOUNT_INDEX[CTRL_MATRIX_CELL[row][col]] = (row - 1) * 4 + col
  end
end

-- tap gesture state (short tap on a mod amount control toggles its lock)
local TAP_MAX_MS = 250
local tapDownControlId = nil
local tapDownTime = 0
local tapDownValue = nil

-- cached state
local rowIsZero = { false, false, false, false }
local colIsZero = { false, false, false, false }
local cellIsZero = {
  { false, false, false, false },
  { false, false, false, false },
  { false, false, false, false },
  { false, false, false, false },
}

-- single flat lock-state array (used by applyMacroToAll/resetVirtualParams/compareIt too)
local modAmountLocked = {}
for i = 1, 16 do modAmountLocked[i] = false end

local function updateModCell(row, col)
  local dim = rowIsZero[row] or colIsZero[col] or cellIsZero[row][col]
  local idx = (row - 1) * 4 + col
  local color = dim and orange.off or orange.on
  if not dim and modAmountLocked[idx] == true then color = RED end
  local id = CTRL_MATRIX_CELL[row][col]
  local c = controls.get(id)
  if c then c:setColor(color) end
end

local function updateMatrixCell(row, col)
  updateModCell(row, col)
end

local function repaintMatrix()
  for row = 1, 4 do
    for col = 1, 4 do
      updateMatrixCell(row, col)
    end
  end
end

local function clearMatrixState()
  for row = 1, 4 do
    rowIsZero[row] = false
    for col = 1, 4 do
      colIsZero[col] = false
      cellIsZero[row][col] = false
    end
  end
  for i = 1, 16 do modAmountLocked[i] = false end
end

local function seedMatrixDimState()
  for row = 1, 4 do
    rowIsZero[row] = (parameterMap.get(deviceId, PT_VIRTUAL, MOD_SOURCE_PARAM[row]) or 0) == 0
  end
  for col = 1, 4 do
    colIsZero[col] = (parameterMap.get(deviceId, PT_VIRTUAL, MOD_DEST_PARAM[col]) or 0) == 0
  end
  for row = 1, 4 do
    for col = 1, 4 do
      local idx = (row - 1) * 4 + col
      cellIsZero[row][col] = (parameterMap.get(deviceId, PT_VIRTUAL, MOD_AMOUNT_PARAM[idx]) or 64) == 64
      -- Don't read lock state from the parameter map; keep it in modAmountLocked (Lua state).
    end
  end
end

local function setModAmountLock(idx, locked)
  locked = locked and true or false
  modAmountLocked[idx] = locked

  -- Send CC directly to synth; no need to use parameterMap.set (no message bound)
  midi.sendControlChange(port, channel, PARAM_MOD_LOCK[idx], locked and 127 or 0)

  if not macroApplying then
    local row = math.floor((idx - 1) / 4) + 1
    local col = ((idx - 1) % 4) + 1
    updateMatrixCell(row, col)
  end
end

local function setRowZero(row, value)
  rowIsZero[row] = (value == 0)
  if not macroApplying then
    for col = 1, 4 do
      updateMatrixCell(row, col)
    end
  end
end

local function setColZero(col, value)
  colIsZero[col] = (value == 0)
  if not macroApplying then
    for row = 1, 4 do
      updateMatrixCell(row, col)
    end
  end
end

local function setCellZero(row, col, value)
  cellIsZero[row][col] = (value == 64)
  if not macroApplying then
    updateModCell(row, col)
  end
end

function dimRow1(valueObject, value) setRowZero(1, value) end
function dimRow2(valueObject, value) setRowZero(2, value) end
function dimRow3(valueObject, value) setRowZero(3, value) end
function dimRow4(valueObject, value) setRowZero(4, value) end

function dimCol1(valueObject, value) setColZero(1, value) end
function dimCol2(valueObject, value) setColZero(2, value) end
function dimCol3(valueObject, value) setColZero(3, value) end
function dimCol4(valueObject, value) setColZero(4, value) end

function dimAmt11(valueObject, value) setCellZero(1, 1, value) end
function dimAmt12(valueObject, value) setCellZero(1, 2, value) end
function dimAmt13(valueObject, value) setCellZero(1, 3, value) end
function dimAmt14(valueObject, value) setCellZero(1, 4, value) end
function dimAmt21(valueObject, value) setCellZero(2, 1, value) end
function dimAmt22(valueObject, value) setCellZero(2, 2, value) end
function dimAmt23(valueObject, value) setCellZero(2, 3, value) end
function dimAmt24(valueObject, value) setCellZero(2, 4, value) end
function dimAmt31(valueObject, value) setCellZero(3, 1, value) end
function dimAmt32(valueObject, value) setCellZero(3, 2, value) end
function dimAmt33(valueObject, value) setCellZero(3, 3, value) end
function dimAmt34(valueObject, value) setCellZero(3, 4, value) end
function dimAmt41(valueObject, value) setCellZero(4, 1, value) end
function dimAmt42(valueObject, value) setCellZero(4, 2, value) end
function dimAmt43(valueObject, value) setCellZero(4, 3, value) end
function dimAmt44(valueObject, value) setCellZero(4, 4, value) end

local function toggleModAmountLock(idx)
  setModAmountLock(idx, not modAmountLocked[idx])
end

local function scaledAmount(base, factor)
  local v = 64 + (base - 64) * factor
  v = math.floor(v + 0.5)
  if v < 0 then v = 0 elseif v > 127 then v = 127 end
  return v
end

local function applyMacroToAll(factorOverride, ignoreLocks)
  local alreadyApplying = macroApplying
  macroApplying = true  
  local factor = factorOverride or macroFactor()
  for i = 1, 16 do
    if modAmountBase[i] ~= 64 then
      local isLocked = modAmountLocked[i]
      if ignoreLocks or not isLocked then
        local newValue = scaledAmount(modAmountBase[i], factor)
        local current = parameterMap.get(deviceId, PT_VIRTUAL, PARAM_MOD_AMOUNT[i])
        if current ~= newValue then
          parameterMap.set(deviceId, PT_VIRTUAL, PARAM_MOD_AMOUNT[i], newValue)
          midi.sendControlChange(port, channel, PARAM_MOD_AMOUNT[i], newValue)
        end
      end
    end
  end
  if not alreadyApplying then
    macroApplying = false
  end
end

-- ---------------- macro base snapshots for A/B compare ----------------
local macroBaseSnapshotA = nil
local macroBaseSnapshotB = nil
local compareApplying = false
local comparingActive = false

local function copyModAmountBase(src)
  local t = {}
  for i = 1, 16 do t[i] = (src and src[i]) or 64 end
  return t
end

-- call this once, right after a preset is parsed/applied (SELECT_IT and
-- resetIt already do applyPresetParameters(pm))
local function captureMacroBaseA()
  for i = 1, 16 do
    modAmountBase[i] = parameterMap.get(deviceId, PT_VIRTUAL, PARAM_MOD_AMOUNT[i]) or 64
  end
  macroBaseSnapshotA = copyModAmountBase(modAmountBase)
  macroBaseSnapshotB = nil
  comparingActive = false
end

------------------ COMPARE_IT toggle block -----------------------------------
-- value 1: cache edited state (B), recall unedited baseline (A)
-- value 0: recall cached edited state (B)
-- comparison state (A/B)
-- A = unedited loaded patch snapshot
-- B = cached edited snapshot
local compareEditedPM   = nil
local compareUneditedPM = nil

-- Capture current 96 PT_VIRTUAL params from Electra
local function snapshotCurrentPM()
  local pm = {}
  for i = 1, PARAM_NUM do
    pm[i] = parameterMap.get(deviceId, PT_VIRTUAL, i - 1) or 0
  end
  -- lock params aren't in the map (they read back as 16537); use the Lua lock state instead
  for idx = 1, 16 do
    pm[PARAM_MOD_LOCK[idx] + 1] = modAmountLocked[idx] and 127 or 0
  end
  return pm
end

local function clonePM(src)
  if not src then return nil end
  local dst = {}
  for i = 1, #src do dst[i] = src[i] end
  return dst
end

-- lock-state snapshots for A/B compare (lock state lives in Lua, not the parameter map)
local compareEditedLocks = nil

local function copyLocks(src)
  local t = {}
  for i = 1, 16 do t[i] = (src and src[i]) == true end
  return t
end

-- patch lock states from a pm table (pm is 1-based, so param N is pm[N + 1]).
-- Only 1..127 counts as locked; 0 or an unset value (16537) counts as unlocked.
local function locksFromPM(pm)
  local t = {}
  for i = 1, 16 do
    local v = pm and pm[PARAM_MOD_LOCK[i] + 1]
    t[i] = (type(v) == "number" and v > 0 and v <= 127)
  end
  return t
end

-- set lock states, send CCs only for the ones that changed, then repaint
local function applyLockStates(states)
  for i = 1, 16 do
    local want = (states[i] == true)
    if modAmountLocked[i] ~= want then
      modAmountLocked[i] = want
      midi.sendControlChange(port, channel, PARAM_MOD_LOCK[i], want and 127 or 0)
    end
  end
  repaintMatrix()
end

local compareLatched = false

local lfo
local lfoWasRunningBeforeCompare = false
local stopLfo, resumeLfo, captureLfoMapBaseline

function compareIt(valueObject, value)
  local v = math.floor(tonumber(value) or 0)
  compareApplying = true

  if v == 1 then
    -- Pause Macro LFO while showing A, and remember whether to resume later.
    lfoWasRunningBeforeCompare = lfo and lfo.isRunning or false
    if lfoWasRunningBeforeCompare then
      stopLfo()
    end

    -- Latch edited snapshot (B) once per compare-on cycle.
    if not compareLatched then
      if not compareUneditedPM then
        compareUneditedPM = snapshotCurrentPM()
      end
      compareEditedPM = snapshotCurrentPM()
      compareEditedLocks = copyLocks(modAmountLocked)   
      macroBaseSnapshotB = copyModAmountBase(modAmountBase)
      compareLatched = true
    end

    -- Show unedited baseline (A)
    comparingActive = true
    applyPresetParameters(compareUneditedPM)
    applyLockStates(locksFromPM(compareUneditedPM))     -- Show the patch's locks

    -- Restore macro base to A and bypass macro scaling/locks while comparing.
    if macroBaseSnapshotA then
      modAmountBase = copyModAmountBase(macroBaseSnapshotA)
    end
    applyMacroToAll(1, true)

    applyRndLfoSync()
    updateRndVisibility(nil, nil)
    dprint("COMPARE_IT=1 -> showing unedited patch (macro bypassed)")

  elseif v == 0 then
    -- Restore edited snapshot (B)
    if compareLatched and compareEditedPM then
      applyPresetParameters(compareEditedPM)
      applyLockStates(compareEditedLocks or copyLocks(modAmountLocked))   -- NEW: restore edited locks

      if macroBaseSnapshotB then
        modAmountBase = copyModAmountBase(macroBaseSnapshotB)
      end

      -- Restore locked mod amounts to their exact edited values.
      for i = 1, 16 do
        if modAmountLocked[i] then
          local pnum = MOD_AMOUNT_PARAM[i]           -- 62..77
          local liveVal = compareEditedPM[pnum + 1]  -- snapshot is 1-based
          if liveVal ~= nil then
            parameterMap.set(deviceId, PT_VIRTUAL, pnum, liveVal)
          end
        end
      end

      -- Reapply current macro to unlocked slots.
      applyMacroToAll()

      applyRndLfoSync()
      updateRndVisibility(nil, nil)
      dprint("COMPARE_IT=0 -> restored edited patch (macro reapplied)")
    else
      dprint("COMPARE_IT=0 -> no cached edited patch to restore")
    end

    compareLatched = false
    comparingActive = false

    -- Resume Macro LFO if compare-on paused it.
    if lfoWasRunningBeforeCompare then
      captureLfoMapBaseline()
      resumeLfo()
      lfoWasRunningBeforeCompare = false
    end
  end

  compareApplying = false
end

-- ============================================================
-- Macro amount LFO (Peak behavior, adapted for Seashell 7-bit)
-- ============================================================

local PARAM_MACRO_LFO      = 10070
local PARAM_MACRO_LFO_RATE       = 10071
local PARAM_MACRO_LFO_WAVE = 10072

local MACRO_LFO_OFF      = 0
local MACRO_LFO_UNIPOLAR = 1
local MACRO_LFO_BIPOLAR  = 2

local MACRO_LFO_SINE = 0
local MACRO_LFO_SH   = 1

local MACRO_LFO_SH_MAX_STEP = 1.00
local MACRO_LFO_SH_GLIDE_FRACTION = 1.00

local SH_RATE_MIN_PERIOD_MS = 2000
local SH_RATE_MAX_PERIOD_MS = 20000
local SH_RATE_MAX_MULT = 4

lfo = {
  isRunning = false,
  phase = 0.5,
  shPhase = 0.5,

  periodMs = 20000,
  stepMs = 50,

  mode = MACRO_LFO_UNIPOLAR,
  waveform = MACRO_LFO_SINE,

  heldRandom = 1.0,
  shFromValue = 1.0,
  shToValue = 1.0,
  shBoundary = nil,

  minValue = MACRO_CENTER,
  maxValue = MACRO_MAX,
  amplitude = 1.0
}


-- modulation baseline cache (same concept as Peak)
local lfoMapBaseline = {}
local lfoBaselineValid = false
for i = 1, 16 do lfoMapBaseline[i] = 64 end

local function clamp01(v)
  if v < 0 then return 0 end
  if v > 1 then return 1 end
  return v
end

local function shSampleMultiplier(periodMs)
  if periodMs <= SH_RATE_MIN_PERIOD_MS then
    return 1.0
  elseif periodMs >= SH_RATE_MAX_PERIOD_MS then
    return SH_RATE_MAX_MULT
  end
  local t = (periodMs - SH_RATE_MIN_PERIOD_MS) / (SH_RATE_MAX_PERIOD_MS - SH_RATE_MIN_PERIOD_MS)
  return 1.0 + t * (SH_RATE_MAX_MULT - 1.0)
end

local function smoothBezier(t)
  return t * t * (3 - 2 * t)
end

local function sineMacroValue()
  local sineBipolar = -math.cos(lfo.phase * 2 * math.pi)
  local center = (lfo.minValue + lfo.maxValue) / 2
  local halfRange = (lfo.maxValue - lfo.minValue) / 2
  local value = center + sineBipolar * halfRange * lfo.amplitude
  return math.floor(value + 0.5)
end

local function sampleAndHoldMacroValue()
  local heldBipolar = (lfo.heldRandom * 2) - 1
  local center = (lfo.minValue + lfo.maxValue) / 2
  local halfRange = (lfo.maxValue - lfo.minValue) / 2
  local value = center + heldBipolar * halfRange * lfo.amplitude
  return math.floor(value + 0.5)
end

local function currentLfoValue()
  if lfo.waveform == MACRO_LFO_SH then
    return sampleAndHoldMacroValue()
  end
  return sineMacroValue()
end

local function chooseNextSampleAndHoldTarget()
  lfo.shFromValue = lfo.heldRandom
  local signedRandom = math.random() + math.random() - 1
  local newTarget = lfo.shFromValue + signedRandom * MACRO_LFO_SH_MAX_STEP

  if newTarget > 1 then
    local overshoot = newTarget - 1
    lfo.shBoundary = 1
    lfo.shToValue = 1 - overshoot
  elseif newTarget < 0 then
    local overshoot = -newTarget
    lfo.shBoundary = 0
    lfo.shToValue = overshoot
  else
    lfo.shBoundary = nil
    lfo.shToValue = newTarget
  end
end

local function updateSampleAndHoldGlide()
  local glideFraction = MACRO_LFO_SH_GLIDE_FRACTION
  if glideFraction <= 0 then
    lfo.heldRandom = lfo.shToValue
    return
  end

  if lfo.shPhase >= glideFraction then
    lfo.heldRandom = lfo.shToValue
    return
  end

  local glidePosition = clamp01(lfo.shPhase / glideFraction)

  if lfo.shBoundary == nil then
    local eased = smoothBezier(glidePosition)
    lfo.heldRandom = lfo.shFromValue + (lfo.shToValue - lfo.shFromValue) * eased
  else
    local d1 = math.abs(lfo.shBoundary - lfo.shFromValue)
    local d2 = math.abs(lfo.shToValue - lfo.shBoundary)
    local total = d1 + d2
    local splitPoint = (total > 0) and (d1 / total) or 0.5

    if glidePosition < splitPoint then
      local localT = (splitPoint > 0) and (glidePosition / splitPoint) or 1
      local eased = smoothBezier(localT)
      lfo.heldRandom = lfo.shFromValue + (lfo.shBoundary - lfo.shFromValue) * eased
    else
      local remaining = 1 - splitPoint
      local localT = (remaining > 0) and ((glidePosition - splitPoint) / remaining) or 1
      local eased = smoothBezier(localT)
      lfo.heldRandom = lfo.shBoundary + (lfo.shToValue - lfo.shBoundary) * eased
    end
  end
end

function captureLfoMapBaseline()
  for i = 1, 16 do
    lfoMapBaseline[i] = parameterMap.get(deviceId, PT_VIRTUAL, PARAM_MOD_AMOUNT[i]) or 64
  end
  lfoBaselineValid = true
end

local function clearLfoMapBaseline()
  lfoBaselineValid = false
  for i = 1, 16 do lfoMapBaseline[i] = 64 end
end

local function applyCurrentLfoValue()
  if comparingActive then return end
  local value = currentLfoValue()
  macroKnobValue = value

  macroApplying = true   -- set BEFORE the parameterMap.set that can re-enter onChange
  if lastLfoValue ~= value then
    parameterMap.set(deviceId, PT_VIRTUAL, PARAM_MACRO_KNOB, value)
    lastLfoValue = value
  end
  applyMacroToAll()
  macroApplying = false
end

-- ---------------- Macro LFO scope state ----------------

local SCOPE_WIDTH = 140 -- 314 for 2 slots wide
local SCOPE_HEIGHT = 140
local CTRL_LFO_SCOPE = 178

local g = graphics
local scopeControl = controls.get(CTRL_LFO_SCOPE)

local scope = {
  y = {}
}

local scopeRepaintDiv = 2
local scopeRepaintCount = 0

-- ---------------- Macro LFO scope helpers ----------------

local function macroValueToNorm(value)
  local range =
    lfo.maxValue - lfo.minValue
  if range <= 0 then
    return 0
  end
  local normalized = (value - lfo.minValue) / range
  normalized = clamp01(normalized)
  return (normalized * 2) - 1
end

function initializeScopeData()
  for i = 1, SCOPE_WIDTH do
    scope.y[i] = 0
  end
end

-- ---------------- Macro LFO scheduler ----------------

local lfoHandle = nil

local function stopLfoScheduler()
  if lfoHandle ~= nil then
    schedule.cancel(lfoHandle)
    lfoHandle = nil
  end
end

local function lfoStep()
  if not lfo.isRunning or comparingActive then
    return
  end

  lfo.phase =
    lfo.phase + lfo.stepMs / lfo.periodMs

  while lfo.phase >= 1 do
    lfo.phase = lfo.phase - 1
  end

  if lfo.waveform == MACRO_LFO_SH then
    local shPeriodMs =
      lfo.periodMs / shSampleMultiplier(lfo.periodMs)

    lfo.shPhase =
      lfo.shPhase + lfo.stepMs / shPeriodMs

    while lfo.shPhase >= 1 do
      lfo.shPhase = lfo.shPhase - 1
      chooseNextSampleAndHoldTarget()
    end

    updateSampleAndHoldGlide()
  end

  -- Calculate one value and use it for both the knob and scope.
  local value = currentLfoValue()

  applyCurrentLfoValue(value)

  -- Scope history update.
  for i = 1, SCOPE_WIDTH - 1 do
    scope.y[i] = scope.y[i + 1]
  end

  scope.y[SCOPE_WIDTH] = macroValueToNorm(value)

  -- At a 10 ms control rate, repaint approximately every 20 ms.
  scopeRepaintCount = scopeRepaintCount + 1
  if scopeRepaintCount >= scopeRepaintDiv then
    scopeRepaintCount = 0
    scopeControl:repaint()
  end
end


local function startLfoScheduler()
  stopLfoScheduler()
  lfoHandle = schedule.every(lfo.stepMs, lfoStep)
end

function stopLfo()
  lfo.isRunning = false

  if lfoBaselineValid then
    for i = 1, 16 do
      if modAmountBase[i] ~= 64 then
        parameterMap.modulate(deviceId, PT_VIRTUAL, PARAM_MOD_AMOUNT[i], 0, 0)
      end
    end
  end

  clearLfoMapBaseline()
  stopLfoScheduler()
  dprint("Macro LFO stopped")
end

function resumeLfo()
  if lfo.isRunning then return end
  if not lfoBaselineValid then captureLfoMapBaseline() end
  lfo.isRunning = true
  startLfoScheduler()
  applyCurrentLfoValue()
  dprint("Macro LFO resumed")
end

local function setLfoRange(mode)
  if mode ~= MACRO_LFO_UNIPOLAR and mode ~= MACRO_LFO_BIPOLAR then
    mode = MACRO_LFO_UNIPOLAR
  end
  lfo.mode = mode
  lfo.maxValue = MACRO_MAX
  lfo.minValue = (mode == MACRO_LFO_UNIPOLAR) and MACRO_CENTER or 0
end

function startLfo(mode)
  setLfoRange(mode)

  if lfo.isRunning then
    applyCurrentLfoValue()
    return
  end

  lastLfoValue = nil
  scopeRepaintCount = 0

  captureLfoMapBaseline()
  lfo.isRunning = true
  lfo.phase = 0.5
  lfo.heldRandom = 1.0
  lfo.shFromValue = 1.0
  lfo.shToValue = 1.0

  startLfoScheduler()
  applyCurrentLfoValue()
  dprint("Macro LFO started")
end

-- ---------------- Macro LFO UI callbacks ----------------

local LFO_RATE_MIN_MS = 300
local LFO_RATE_MAX_MS = 20000

local function lfoRateToPeriodMs(value)
  local t = value / 255
  local logMin = math.log(LFO_RATE_MIN_MS)
  local logMax = math.log(LFO_RATE_MAX_MS)
  local logPeriod = logMax + (logMin - logMax) * t
  return math.floor(math.exp(logPeriod) + 0.5)
end

function lfoRateChange(valueObject, value)
  lfo.periodMs = lfoRateToPeriodMs(value)
end

function displayLfoRate(valueObject, value)
  local periodMs = lfoRateToPeriodMs(value)
  local waveformParam = parameterMap.get(deviceId, PT_VIRTUAL, PARAM_MACRO_LFO_WAVE) or MACRO_LFO_SINE

  if waveformParam == MACRO_LFO_SH then
    local shPeriodMs = periodMs / shSampleMultiplier(periodMs)
    if shPeriodMs >= 1000 then
      return string.format("%.1f s/step", shPeriodMs / 1000)
    else
      return string.format("%d ms/step", math.floor(shPeriodMs + 0.5))
    end
  end

  if periodMs >= 1000 then
    return string.format("%.1f s", periodMs / 1000)
  end
  return string.format("%d ms", periodMs)
end

function lfoWaveChange(valueObject, value)
  if value ~= MACRO_LFO_SINE and value ~= MACRO_LFO_SH then
    value = MACRO_LFO_SINE
  end

  if value == MACRO_LFO_SH and lfo.waveform ~= MACRO_LFO_SH then
    local currentValue = sineMacroValue()
    local range = lfo.maxValue - lfo.minValue
    local normalized = 1.0
    if range > 0 then normalized = (currentValue - lfo.minValue) / range end
    normalized = clamp01(normalized)

    lfo.heldRandom = normalized
    lfo.shFromValue = normalized
    lfo.shToValue = normalized
    lfo.shPhase = 1.0
  end

  if value == MACRO_LFO_SINE and lfo.waveform ~= MACRO_LFO_SINE then
    local currentValue = sampleAndHoldMacroValue()
    local range = lfo.maxValue - lfo.minValue
    local normalized = 1.0
    if range > 0 then normalized = (currentValue - lfo.minValue) / range end
    normalized = clamp01(normalized)

    lfo.phase = math.acos(1 - 2 * normalized) / (2 * math.pi)
  end

  lfo.waveform = value
  applyCurrentLfoValue()

  local currentRateValue = parameterMap.get(deviceId, PT_VIRTUAL, PARAM_MACRO_LFO_RATE) or 0
  local bump = math.min(255, currentRateValue + 1)
  if bump ~= currentRateValue then
    parameterMap.set(deviceId, PT_VIRTUAL, PARAM_MACRO_LFO_RATE, bump)
  end
  parameterMap.set(deviceId, PT_VIRTUAL, PARAM_MACRO_LFO_RATE, currentRateValue)
  lfo.periodMs = lfoRateToPeriodMs(currentRateValue)
end

-- Map normalized [-1,1] to pixel Y inside the scope rect
local function normToPixel(n, top, bottom)
    local center = (top + bottom) * 0.5
    local amp    = (bottom - top) * 0.5
    return math.floor(center - n * amp + 0.5)
end

-- A callback to draw the XY pad graphics
function paintScope(control, value)
    local bounds = control:getBounds()
    local left   = 0
    local right  = bounds[WIDTH] - 1
    local top    = 0
    local bottom = bounds[HEIGHT] - 1
    -- Clear the Control's bounding box
    g.setColor(0x000000)
    g.fillRect(0, 0, bounds[WIDTH], bounds[HEIGHT])
    g.setColor(0x808080) -- mid gray
    g.drawRoundRect(0, 0, bounds[WIDTH], bounds[HEIGHT], 5)
    -- midline
    g.setColor(0x808080)
    local mid = normToPixel(0, top + 4, bottom - 4)
    g.drawLine(left + 4, mid, right - 4, mid)
    -- signal trace
    g.setColor(ORANGE)
    local lastx = left + 4
    local lasty = normToPixel(scope.y[1], top + 4, bottom - 4)
    for x = 2, math.min(SCOPE_WIDTH - 4, right - 4) do
        local y = normToPixel(scope.y[x], top + 4, bottom - 4)
        g.drawLine(lastx, lasty, x, y)
        lastx, lasty = x, y
    end
end

-- set parameters and send CCs to reset mod matrix to match init patch
function resetIt(valueObject,value)
  if value == 0 then return end
  local preset = PRESETS[0]
  if not preset then
    dprint("RESET_IT: unknown preset index " .. tostring(value))
    return
  end
  local pm = parsePresetParameters(preset.raw)
  for i = MOD_MATRIX_FIRST_PARAM, MOD_MATRIX_LAST_PARAM do
    local v = pm[i+1] or 0
    parameterMap.set(deviceId, PT_VIRTUAL, i, v)
    midi.sendControlChange(port, channel, i, v)
  end  
  dprint("Reset Mod Matrix")
  captureMacroBaseA()
  repaintMatrix()
end

-- helper to reset all virtual (E1 only) macro knob and compare params to default when a new patch is loaded
local function resetVirtualParams()
  parameterMap.updateValue(deviceId, PT_VIRTUAL, PARAM_MACRO_KNOB, MACRO_MAX)
  parameterMap.updateValue(deviceId, PT_VIRTUAL, PARAM_MACRO_LFO, 0)
  parameterMap.updateValue(deviceId, PT_VIRTUAL, PARAM_MACRO_LFO_RATE, 0)
  parameterMap.updateValue(deviceId, PT_VIRTUAL, PARAM_MACRO_LFO_WAVE, 0)
  parameterMap.updateValue(deviceId, PT_VIRTUAL, PARAM_COMPARE_IT, 0)

  if lfo.isRunning then
    stopLfo()
  end

  -- explicitly reset runtime LFO state (not driven by parameterMap.updateValue)
  lfo.mode        = MACRO_LFO_OFF
  lfo.waveform    = MACRO_LFO_SINE
  lfo.phase       = 0.5
  lfo.shPhase     = 0.5
  lfo.periodMs    = 20000      
  lfo.stepMs      = 50
  lfo.amplitude   = 1.0
  lfo.minValue    = MACRO_CENTER
  lfo.maxValue    = MACRO_MAX
  lfo.heldRandom  = 1.0
  lfo.shFromValue = 1.0
  lfo.shToValue   = 1.0
  lfo.shBoundary  = nil

  -- clear macro/compare caches too
  macroKnobValue          = MACRO_MAX
  macroBaseSnapshotA      = nil
  macroBaseSnapshotB      = nil
  compareApplying         = false
  lfoWasRunningBeforeCompare = false
  lfoBaselineValid        = false
  for i = 1, 16 do
    lfoMapBaseline[i] = 64
    modAmountBase[i]  = 64
  end

  initializeScopeData()
  scopeControl:setPaintCallback(paintScope)
  scopeControl:repaint()
end

-------------------- Patch selector on knob release ----------------------------------

-- activeTouchedControlId holds which of the control knobs was touched (HT @oldgearguy)
local activeTouchedControlId   = -1

-- helper function to find match between touched control and target list of controls
local function get_key_for_value(t, value) 
   if (t ~= nil) then
      for k,v in pairs(t) do
         if v==value then return k end
      end
   end
   return nil
end

function events.onPotTouchChange(potId, controlId, touched)
  local amtIdx = CTRL_MOD_AMOUNT_INDEX[controlId]
  if amtIdx then
    local currentValue = parameterMap.get(deviceId, PT_VIRTUAL, MOD_AMOUNT_PARAM[amtIdx])
    if touched == true then
      tapDownControlId = controlId
      tapDownTime = controller.uptime()
      tapDownValue = currentValue
    elseif tapDownControlId == controlId then
      if currentValue ~= nil
        and currentValue == tapDownValue
        and (controller.uptime() - tapDownTime) <= TAP_MAX_MS then
        toggleModAmountLock(amtIdx)
      end
      tapDownControlId = nil
    end
    return
  end
 
  --  if not touched then return end
  local idx = get_key_for_value(CTRL_SELECT_IT,controlId)
  if (idx == nil) then return end
  if (touched == true) and (activeTouchedControlId ~= controlId) then activeTouchedControlId = controlId end
  if (touched == false) and (activeTouchedControlId == controlId) then
    local value = controls.get(controlId):getValue("value"):getMessage():getValue()
    local index = math.floor(tonumber(value) or -1)
    local preset = PRESETS[index]
    if not preset then
      dprint("SELECT_IT: unknown preset index " .. tostring(value))
      return
    end
    local pm = parsePresetParameters(preset.raw)
    if #pm ~= PARAM_NUM then
      dprint(("SELECT_IT: '%s' has %d params (expected 96)"):format(preset.name, #pm))
      return
    end
    -- send patch parameter values to Seashell
    applyPresetParameters(pm)

    clearMatrixState()
    seedMatrixDimState()
    applyLockStates(locksFromPM(pm))  
    repaintMatrix()
    resetVirtualParams()
    captureMacroBaseA()

    -- send a program change to the Seashell as well (so Seashell app also stays in sync)
    midi.sendProgramChange(port, channel, index)

    -- enforce LFO->RND lock if SYNC_TO_LFO is enabled in the loaded preset
    applyRndLfoSync()

    -- always refresh RND visibility after patch load
    updateRndVisibility(nil, nil)

    -- refresh compare baseline to newly loaded preset (unedited A state)
    compareUneditedPM = clonePM(pm)
    compareEditedPM   = nil
    parameterMap.set(deviceId, PT_VIRTUAL, PARAM_COMPARE_IT, 0)

    dprint(("Loaded preset %d => %s"):format(index, preset.name))  end
end

-- parameterMap on change callback
function parameterMap.onChange(valueObjects, origin, midiValue)
  if (origin ~= INTERNAL) then return end
  local msg = valueObjects[1]:getMessage()
  if msg:getType() ~= PT_VIRTUAL then return end
  local pNum = msg:getParameterNumber()

  -- Macro LFO enable toggle (0 = off, 1 = unipolar, 2 = bipolar)
  if pNum == PARAM_MACRO_LFO then
    if midiValue == MACRO_LFO_OFF then
      stopLfo()
    else
      startLfo(midiValue)
    end
    return
  end

  -- Macro knob moved: rescale all 16 amounts, don't re-send the macro itself
  if pNum == PARAM_MACRO_KNOB then
    if macroApplying then return end   -- ignore our own write-back
    macroKnobValue = math.max(0, math.min(MACRO_MAX, midiValue))
    applyMacroToAll()
    return
  end

  -- keep macro base in sync when user (or macro) touches a mod-amount control
  local amtIdx = PARAM_MOD_AMOUNT_INDEX[pNum]
  if amtIdx and not macroApplying and not compareApplying then
    local factor = macroFactor()
    if math.abs(factor) > 0.02 then
      local base = 64 + (midiValue - 64) / factor
      if base < 0 then base = 0 elseif base > 127 then base = 127 end
      modAmountBase[amtIdx] = base
    else
      modAmountBase[amtIdx] = midiValue
    end
  end

  -- existing Seashell behaviors
  if pNum == SYNC_TO_LFO or pNum == LFO_RATE_TYPE
  or pNum == LFO_RATE or pNum == LFO_NOTE
  then
    applyRndLfoSync()
  end

  if pNum == SYNC_TO_LFO or pNum == RND_RATE_TYPE then
    updateRndVisibility(nil, nil)
  end

  if pNum < 128 then
    if macroApplying then return end   -- applyMacroToAll already sent this CC explicitly
      midi.sendControlChange(port, channel, pNum, midiValue)
  end
end

function preset.onLoad()
  events.subscribe(POTS|PAGES) 

  pages.display(1)

  local bounds = scopeControl:getBounds()
  bounds[WIDTH] = SCOPE_WIDTH
  bounds[HEIGHT] = SCOPE_HEIGHT
  scopeControl:setBounds(bounds)
  -- Initialize and assign Custom Control callbacks
  initializeScopeData();
  scopeControl:setPaintCallback(paintScope)
  scopeControl:repaint()

  clearMatrixState()
  seedMatrixDimState()
  applyLockStates(locksFromPM(pm))
  repaintMatrix()
end

