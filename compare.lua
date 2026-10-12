-- Preset compatibility: fw 5.0.0 or higher
-- ====================== CompareIt template ================================
-- Edit only:
--   1) DEVICE PROFILE (SECTION 1)
--   2) host wiring (SECTION 3)
-- Do not edit: the engine in SECTION 2.
--
-- A = state when the patch was loaded (captured by CompareIt.captureA())
-- B = live/edited state (captured when COMPARE_IT is switched on)
-- ON : cache live state as B, then push A into the parameterMap
-- OFF: push cached B back into the parameterMap
--
-- To use in another preset:
--   1) Create a virtual control for COMPARE_IT (toggle, 0/1) and set its Lua callback to compareIt.
--   2) Fill in COMPARE_PROFILE.params (or buildParams) with {parameterType, parameterNumber} pairs.
--   3) Call CompareIt.reset() then CompareIt.captureA() after every patch load.
--      With no SysEx dump, leave readA = nil: A is the parameterMap state at captureA() time.
--   4) In onChange handlers that must ignore engine writes: if compareApplying then return end

local deviceId = 1 -- the device ID used in the E1 preset
local PARAM_COMPARE_IT = 10037
compareApplying = false -- true while the engine writes to the parameterMap

------------------------------------------------------------
-- SECTION 1: DEVICE PROFILE (Peak example)
------------------------------------------------------------
-- The Peak has a mixture of CC7, CC14 and NRPN parameters and parameter numbers **DO NOT** uniquely identify all parameters 
-- PATCH_PARAM_MAP maps a patch byte to a preset parameter type and value: {byte #, parameter type, parameter #}.  Used by assignParam() and the A/B comapre logic
local PATCH_PARAM_MAP = {
  {2,0,10001},{3,0,10002},{4,0,10003},{5,0,10004},{6,0,10005},{7,0,10006},{8,0,10007},{9,0,10008},{10,0,10009},{11,0,10010},{12,0,10011},{13,0,10012},{14,0,10013},{15,0,10014},{16,0,10015},{17,0,10016},{34,0,2},{35,0,3},{36,0,4},
  {37,0,5},{39,1,5},{40,0,7},{41,1,35},{43,0,9},{44,0,10},{45,0,11},{46,0,12},{47,0,13},{48,1,3},{49,12,14},{51,12,15},{53,1,9},{54,12,16},{56,0,14},{57,0,15},{59,1,12},{60,1,119},{61,1,33},{62,1,34},{63,0,17},{64,0,18},
  {65,0,19},{66,0,20},{69,1,37},{70,12,17},{72,12,18},{74,1,38},{75,12,19},{77,0,23},{78,0,24},{80,1,39},{81,1,40},{82,1,41},{83,1,42},{84,0,26},{85,0,27},{86,0,28},{87,0,29},{90,1,65},{91,12,20},{93,12,21},{95,1,43},{96,12,22},
  {98,0,32},{99,0,33},{101,1,71},{102,1,72},{103,1,73},{104,1,44},{105,0,35},{106,0,36},{107,0,37},{108,0,38},{111,12,23},{113,12,24},{115,12,25},{117,12,26},{119,12,27},{121,0,41},{122,0,42},{123,0,43},{124,0,44},{125,1,80},
  {126,1,36},{127,0,45},{128,0,46},{129,1,75},{130,1,79},{131,12,29},{133,12,28},{135,1,76},{137,1,77},{138,1,78},{139,0,48},{142,0,51},{143,0,52},{146,1,86},{147,1,87},{148,1,88},{149,1,89},{150,0,55},{151,0,56},{152,0,57},
  {153,0,58},{155,1,90},{156,1,91},{157,1,92},{158,1,93},{159,0,60},{160,0,61},{161,0,62},{162,0,63},{163,1,94},{164,1,95},{165,1,117},{166,1,103},{167,0,64},{168,0,65},{169,0,66},{170,0,67},{171,0,68},{172,12,30},{174,1,81},
  {175,0,69},{176,0,70},{177,0,71},{178,1,82},{179,0,72},{180,0,73},{181,0,74},{182,0,75},{183,0,76},{185,1,83},{186,12,31},{188,1,84},{189,0,78},{190,0,79},{191,0,80},{192,1,85},{193,0,81},{194,0,82},{195,0,83},{196,0,84},
  {197,0,85},{199,1,104},{201,0,88},{202,0,89},{204,1,108},{205,1,109},{206,0,91},{207,0,92},{208,0,93},{209,0,94},{210,1,110},{211,0,95},{212,0,96},{213,0,97},{214,0,98},{217,1,112},{219,1,113},{220,0,102},{221,0,103},
  {222,0,104},{223,0,105},{224,0,106},{225,0,107},{226,0,108},{227,0,109},{229,1,105},{230,0,111},{231,1,118},{232,0,112},{233,1,107},{234,0,113},{235,0,114},{236,0,115},{237,0,16003},{239,0,116},{240,0,117},{241,0,118},{242,0,119},
  {243,1,116},{244,0,120},{245,0,121},{246,0,122},{247,0,123},{248,0,124},{252,0,128},{253,0,129},{254,0,130},{255,0,131},{256,0,256},{257,0,257},{258,0,258},{259,0,259},{260,0,384},{261,0,385},{262,0,386},{263,0,387},
  {264,0,512},{265,0,513},{266,0,514},{267,0,515},{268,0,640},{269,0,641},{270,0,642},{271,0,643},{272,0,768},{273,0,769},{274,0,770},{275,0,771},{276,0,896},{277,0,897},{278,0,898},{279,0,899},{280,0,1024},{281,0,1025},
  {282,0,1026},{283,0,1027},{284,0,1152},{285,0,1153},{286,0,1154},{287,0,1155},{288,0,1280},{289,0,1281},{290,0,1282},{291,0,1283},{292,0,1408},{293,0,1409},{294,0,1410},{295,0,1411},{296,0,1536},{297,0,1537},{298,0,1538},
  {299,0,1539},{300,0,1664},{301,0,1665},{302,0,1666},{303,0,1667},{304,0,1792},{305,0,1793},{306,0,1794},{307,0,1795},{308,0,1920},{309,0,1921},{310,0,1922},{311,0,1923},{312,0,2048},{313,0,2049},{314,0,2050},{315,0,2051},
  {316,0,2176},{317,0,2177},{318,0,2178},{319,0,2179},{320,0,2304},{321,0,2305},{322,0,2306},{323,0,2307},{324,0,2432},{325,0,2433},{326,0,2434},{327,0,2435},{328,0,2560},{329,0,2561},{330,0,2562},{331,0,2563},{348,0,3200},
  {349,0,3201},{350,0,3202},{351,0,3203},{352,0,3204},{353,0,3205},{354,0,3206},{361,0,3213},{362,0,3214},{363,0,3215},{365,0,3217},{366,0,3218},{367,0,3219},{369,0,3221},{370,0,3222},{371,0,3223},
  {373,0,3225},{374,0,3226},{375,0,3227},{376,0,3228},{377,0,3229},{378,0,3230},{379,0,3231},{380,0,3232},{381,0,3233},{382,0,3234},{383,0,3235},{384,0,3236},{385,0,3237},{386,0,3238},{387,0,3239},{388,0,3240},{389,0,3241},
  {390,0,3242},{391,0,3243},{392,0,3244},{393,0,3245}
}

-- Parameters not captured/restored by the generic snapshot machinery.
-- 16003 = combined master clock byte (sysEx byte 237 + bit from 238), handled independently via events.onPotTouchChange() /
-- sysExPatch writes, and its valid range does not match the raw computed value in all cases.
-- Mod amounts (PARAM_MOD_AMOUNT_INDEX) belong to the macro system and are handled in the hooks below.
local PATCH_PARAM_SKIP_SNAPSHOT = {[16003] = true, }

local function captureLiveModAmounts()
  local amounts = {}
  for i = 1, 16 do
    amounts[i] = parameterMap.get(deviceId, PT_VIRTUAL, PARAM_MOD_AMOUNT[i]) or 64
  end
  return amounts
end

local snapshotBModAmounts = nil

local COMPARE_PROFILE = {
  -- Virtual parameter number of the COMPARE_IT toggle (cleared by CompareIt.reset())
  compareParam = PARAM_COMPARE_IT,

  -- Parameter list: { parameterType, parameterNumber [, extra fields] }. Use `params = {...}` for a plain list.
  params = nil,

  -- OPTIONAL: build the list programmatically. Overrides `params` when present.
  buildParams = function()
    local list = {}
    for i = 1, #PATCH_PARAM_MAP do
      local e = PATCH_PARAM_MAP[i]
      list[#list + 1] = { e[2] % 10, e[3], byte = e[1], kind = e[2] }
    end
    return list
  end,

  -- OPTIONAL: return true to leave a parameter out of capture/restore
  skip = function(entry)
    return PARAM_MOD_AMOUNT_INDEX[entry[2]] or PATCH_PARAM_SKIP_SNAPSHOT[entry[2]] or false
  end,

  -- OPTIONAL: decoder for A. nil = A is the live parameterMap at captureA() time.
  readA = function(entry)
    local b = entry.byte
    if entry.kind == 12 then -- CC14 composed from 2 adjacent bytes
      return 64 * (sysExPatch[b] * 2 + getBits(sysExPatch[b + 1], 2, 1))
    elseif b == 237 then -- clock message is also a 14bit value
      return sysExPatch[b] * 2 + getBits(sysExPatch[b + 1], 2, 1)
    end
    return sysExPatch[b]
  end,

  -- OPTIONAL hooks (any may be nil)
  onCaptureA = function() -- after a new A baseline is taken
    snapshotBModAmounts = nil
    for i = 1, 16 do
      modAmountBase[i] = parameterMap.get(deviceId, PT_VIRTUAL, PARAM_MOD_AMOUNT[i]) or 64
    end
    macroBaseSnapshotA = copyModAmountBase(modAmountBase)
    macroBaseSnapshotB = nil
  end,
  onCompareOn = function() -- before B is captured
    lfoWasRunningBeforeCompare = lfo.isRunning
    if lfo.isRunning then stopLfo() end
  end,
  onCaptureB = function() -- after live state is captured as B
    snapshotBModAmounts = captureLiveModAmounts()
    macroBaseSnapshotB = copyModAmountBase(modAmountBase)
  end,
  afterShowA = function() -- after A has been pushed
    modAmountBase = copyModAmountBase(macroBaseSnapshotA)
    -- Show the true parsed patch values, ignoring locks.
    applyMacroToAll(1, true)
  end,
  afterRestoreB = function() -- after B has been pushed back
    modAmountBase = copyModAmountBase(macroBaseSnapshotB)
    -- Restore live values for locked mod amounts.
    if snapshotBModAmounts then
      for i = 1, 16 do
        local lockValue = parameterMap.get(deviceId, PT_VIRTUAL, PARAM_MOD_LOCK[i]) or 0
        if lockValue ~= 0 then
          parameterMap.set(deviceId, PT_VIRTUAL, PARAM_MOD_AMOUNT[i], snapshotBModAmounts[i])
        end
      end
    end
    -- The Parameter Map was restored to B: discard any baseline captured for the old state.
    clearLfoMapBaseline()
    -- Apply the current macro to unlocked slots only.
    applyMacroToAll()
  end,
  onCompareOff = function() -- always called when compare is switched off
    -- Resume LFO only if compare ON paused it.
    if lfoWasRunningBeforeCompare then
      captureLfoMapBaseline()
      resumeLfo()
      lfoWasRunningBeforeCompare = false
    end
  end,
}

------------------------------------------------------------
-- SECTION 2: ENGINE (do not edit)
------------------------------------------------------------
local CompareIt = (function(CONFIG)
  local M = {}
  local entries = nil
  local snapA, snapB = nil, nil
  local comparing = false

  local function resolveEntries()
    if entries then return entries end
    local src = CONFIG.buildParams and CONFIG.buildParams() or CONFIG.params or {}
    entries = {}
    for i = 1, #src do
      if not (CONFIG.skip and CONFIG.skip(src[i], i)) then
        entries[#entries + 1] = src[i]
      end
    end
    return entries
  end

  local function apply(snap)
    if not snap then return end
    local list = resolveEntries()
    for i = 1, #list do
      if snap[i] ~= nil then
        local ok, err = pcall(parameterMap.set, deviceId, list[i][1], list[i][2], snap[i])
        if not ok then
          print(string.format("CompareIt: type=%d num=%d value=%s rejected (%s)",
            list[i][1], list[i][2], tostring(snap[i]), tostring(err)))
        end
      end
    end
  end

  local function captureLive()
    local list, snap = resolveEntries(), {}
    for i = 1, #list do
      local v = parameterMap.get(deviceId, list[i][1], list[i][2])
      if v ~= nil and v ~= MIDI_VALUE_DO_NOT_SEND then snap[i] = v end
    end
    return snap
  end

  -- Call once a patch has been loaded (and parsed, if readA decodes from SysEx).
  function M.captureA()
    local list, snap = resolveEntries(), {}
    for i = 1, #list do
      if CONFIG.readA then
        snap[i] = CONFIG.readA(list[i], i)
      else
        local v = parameterMap.get(deviceId, list[i][1], list[i][2])
        if v ~= nil and v ~= MIDI_VALUE_DO_NOT_SEND then snap[i] = v end
      end
    end
    snapA, snapB, comparing = snap, nil, false
    if CONFIG.onCaptureA then CONFIG.onCaptureA() end
  end

  local function setOn()
    if CONFIG.onCompareOn then CONFIG.onCompareOn() end
    snapB = captureLive()
    if CONFIG.onCaptureB then CONFIG.onCaptureB() end
    comparing = true
    apply(snapA)
    if CONFIG.afterShowA then CONFIG.afterShowA() end
    print("COMPARE_IT: showing A (true patch values)")
  end

  local function setOff()
    if snapB then
      apply(snapB)
      if CONFIG.afterRestoreB then CONFIG.afterRestoreB() end
      print("COMPARE_IT: restored B (live values)")
    end
    comparing = false
    if CONFIG.onCompareOff then CONFIG.onCompareOff() end
  end

  function M.toggle(value)
    if not snapA then
      print("COMPARE_IT: no patch parsed yet")
      return
    end
    compareApplying = true
    local ok, err = pcall(function()
      if value == 1 then setOn() else setOff() end
    end)
    compareApplying = false -- always cleared, even on error
    if not ok then print("COMPARE_IT error: " .. tostring(err)) end
  end

  function M.isComparing() return comparing end

  -- Leave compare mode (call when a new patch is loaded, before captureA()).
  function M.reset()
    comparing = false
    if CONFIG.compareParam then
      parameterMap.updateValue(deviceId, PT_VIRTUAL, CONFIG.compareParam, 0)
    end
  end

  return M
end)(COMPARE_PROFILE)

------------------------------------------------------------
-- SECTION 3: HOST WIRING
------------------------------------------------------------
-- COMPARE_IT virtual control callback
function compareIt(valueObject, value)
  CompareIt.toggle(value)
end

-- After a patch is parsed (Peak: at the end of assignParam(), replacing captureSnapshotA()):
--   CompareIt.captureA()
-- (resetVirtualParams() already clears the compare toggle on the Peak; otherwise call CompareIt.reset() first.)
----------------------------- midi receive processing functions ----------------------------------------
function midi.onSysex(midiInput, sysexBlock)
  local function isPeak()
    return sysexBlock:peek(1) == 0xF0 and sysexBlock:peek(2) == 0x00
       and sysexBlock:peek(3) == 0x20 and sysexBlock:peek(4) == 0x29
       and sysexBlock:peek(5) == 0x01 and sysexBlock:peek(6) == 0x10
       and sysexBlock:peek(7) == 0x00 and sysexBlock:peek(8) == 0x7E
  end
  if not isPeak() then return end
  local cmd = sysexBlock:peek(9)
  local len = sysexBlock:getLength()

  -- a stored patch received and the patch name retrieved and stored in data.json
  if PatchNames.handleSysex(sysexBlock) then return end

  -- patch from edit buffer received (no bank or patch number)
  if len == 527 and cmd == 0x00 then 
    print("patch from edit buffer received")
    for i = 1,512 do
      sysExPatch[i]=sysexBlock:peek(i+15)
    end
    assignParam()
  end

  -- settings received
  if len == 527 and cmd == 0x04 then 
    print("settings received")
    for i = 1,511 do
      sysExSettings[i]=sysexBlock:peek(i+15)
    end
    assignSettings()
    midiChannel = parameterMap.get(deviceId, PT_VIRTUAL, 8207) + 1
    print("Peak's MIDI Channel: "..math.floor(midiChannel))
    assignChannel(nil,1)         -- should set device channel to same as Peak's when preset loaded
  end
  -- user wavetable name received 
  if len == 23 and cmd == 0x07 then
    local slot = sysexBlock:peek(15)
    local waveName = ""
    for i = 1, 7 do 
      waveName = waveName .. string.char(sysexBlock:peek(i+15))
    end
    waveTableNames[slot] = waveName
  end
end
