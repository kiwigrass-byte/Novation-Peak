-- Preset compatibility: fw 5.0.0 or higher

-- Declare device and port 
local deviceId = 1 -- the device ID used in the E1 preset
local device = devices.get(deviceId)
local port = device:getPort()

-- ====================== PatchNames template ================================
-- Edit only:
--   1) DEVICE PROFILE
--   2) request/response parsing functions
--   3) host wiring (port, onLoad, onSysex, displayPatch)
--
-- Do not edit:
--   engine logic below

------------------------------------------------------------
-- SECTION 1: DEVICE PROFILE  (edit this for each synth)
------------------------------------------------------------

-- Helper for parseReply: read `len` ASCII chars from a SysEx block (1-based index)
local function readAscii(block, startIndex, len)
  local t = {}
  for i = 0, len - 1 do t[#t + 1] = string.char(block:peek(startIndex + i)) end
  return table.concat(t)
end

local PATCHNAMES_PROFILE = {
  ---- Memory layout ----
  banks          = 4,      -- number of banks              (e.g. 5)
  bankBase       = 1,      -- first bank number            (0 or 1)
  patchesPerBank = 128,    -- patches in each bank         (e.g. 100)
  patchBase      = 0,      -- first patch number           (0 or 1)

  ---- Behaviour ----
  scanPeriodMs       = 200,   -- tick rate; one request per tick at most
  scanReplyTimeoutMs = 750,   -- give up waiting for a reply after this
  saveEveryN         = 128,   -- checkpoint save every N names received
  persistTag         = "patchNamesV1", -- change per preset/layout version

  ---- Request: return a table of bytes (no F0/F7 for Electra sendSysex) ----
  buildRequest = function(bank, patch)
    -- Peak example:
    return { 0x00,0x20,0x29,0x01,0x10,0x00,0x7E,0x41,0x00,0x00,0x00, bank, patch }
  end,

  ---- Reply parser ----
  -- Return bank, patch, name   when block is a patch-name reply
  -- Return nil                 when block is anything else
  -- bank/patch may be nil if the reply doesn't contain them; the engine
  -- then uses the bank/patch it last requested.
  parseReply = function(block)
    -- Peak example:
    if block:getLength() <= 33 then return nil end
    if block:peek(1) ~= 0xF0 or block:peek(2) ~= 0x00 or block:peek(3) ~= 0x20
       or block:peek(4) ~= 0x29 or block:peek(5) ~= 0x01 or block:peek(6) ~= 0x10
       or block:peek(7) ~= 0x00 or block:peek(8) ~= 0x7E then return nil end
    if block:peek(9) ~= 0x01 then return nil end
    return block:peek(13), block:peek(14), readAscii(block, 17, 16)
  end,
}

--[[ Example profile for a different synth: 5 banks x 100 patches, names
     returned as 12 chars at offset 10, no bank/patch in the reply:

  banks = 5, bankBase = 0, patchesPerBank = 100, patchBase = 1,
  buildRequest = function(bank, patch) return { 0x00,0x21,0x22, 0x10, bank, patch } end,
  parseReply = function(block)
    if block:peek(2) ~= 0x00 or block:peek(3) ~= 0x21 or block:peek(4) ~= 0x22 then return nil end
    if block:peek(5) ~= 0x11 then return nil end
    return nil, nil, readAscii(block, 10, 12)
  end,
]]

------------------------------------------------------------
-- SECTION 2: ENGINE  (do not edit)
------------------------------------------------------------
local PatchNames = (function(CONFIG)
  local M = {}

  local lastBank  = CONFIG.bankBase + CONFIG.banks - 1
  local lastPatch = CONFIG.patchBase + CONFIG.patchesPerBank - 1

  local state = {
    getPort = nil,
    names = {},
    dirty = false,
    updateCount = 0,
    onScanComplete = nil,
    onNameUpdated = nil,
    scan = { running = false, finished = false, bank = 0, patch = 0, handle = nil,
             pending = false, startedAt = 0, reqBank = nil, reqPatch = nil },
  }

  local function clean(s)
    s = tostring(s or "")
    s = s:gsub("%z", "")
    s = s:gsub("[^\32-\126]", "")
    s = s:gsub("%s+$", "")
    return s
  end

  local function validBank(b)  return type(b) == "number" and b >= CONFIG.bankBase  and b <= lastBank  end
  local function validPatch(p) return type(p) == "number" and p >= CONFIG.patchBase and p <= lastPatch end
  local function key(b, p) return string.format("b%d_p%03d", b, p) end

  local function resetNames()
    state.names = {}
    for b = CONFIG.bankBase, lastBank do
      state.names[b] = {}
      for p = CONFIG.patchBase, lastPatch do state.names[b][p] = "" end
    end
  end

  local function save()
    local flat, count = {}, 0
    for b = CONFIG.bankBase, lastBank do
      for p = CONFIG.patchBase, lastPatch do
        local v = state.names[b][p]
        flat[key(b, p)] = v
        if v ~= "" then count = count + 1 end
      end
    end
    local payload = { _tag = CONFIG.persistTag, banks = CONFIG.banks,
                      patches = CONFIG.patchesPerBank, names = flat }
    local ok, err = pcall(persist, payload)
    print(ok and string.format("PatchNames saved (%d names, %d updates this session)", count, state.updateCount)
          or ("PatchNames save failed: " .. tostring(err)))
    state.dirty = false
  end

  local function markDirty()
    state.dirty = true
    state.updateCount = state.updateCount + 1
    if state.updateCount % CONFIG.saveEveryN == 0 then save() end
  end

  function M.init(opts)
    opts = opts or {}
    state.getPort = opts.getPort
    state.onScanComplete = opts.onScanComplete
    state.onNameUpdated = opts.onNameUpdated
    resetNames()
  end

  function M.load()
    local payload = {}
    local ok, err = pcall(recall, payload)
    if not ok then print("PatchNames recall failed: " .. tostring(err)) return end
    if payload._tag ~= CONFIG.persistTag or payload.banks ~= CONFIG.banks
       or payload.patches ~= CONFIG.patchesPerBank or type(payload.names) ~= "table" then
      print("PatchNames recall: no matching saved data")
      return
    end
    local count = 0
    for b = CONFIG.bankBase, lastBank do
      for p = CONFIG.patchBase, lastPatch do
        local v = payload.names[key(b, p)] or ""
        state.names[b][p] = v
        if v ~= "" then count = count + 1 end
      end
    end
    print(string.format("PatchNames restored (%d names)", count))
  end

  function M.get(bank, patch)
    if not validBank(bank) or not validPatch(patch) then return "" end
    return state.names[bank][patch] or ""
  end

  function M.handleSysex(block)
    local ok, bank, patch, raw = pcall(CONFIG.parseReply, block)
    if not ok then
      print("PatchNames parseReply error: " .. tostring(bank))
      return false
    end
    if raw == nil then return false end          -- not a patch-name reply

    -- fall back to the last requested bank/patch if the reply doesn't carry them
    if bank == nil  then bank  = state.scan.reqBank  end
    if patch == nil then patch = state.scan.reqPatch end
    if not validBank(bank) or not validPatch(patch) then return true end

    local name = clean(raw)
    state.names[bank][patch] = name
    markDirty()
    state.scan.pending = false
    if state.onNameUpdated then state.onNameUpdated(bank, patch, name) end
    return true
  end

  function M.stopScan()
    local s = state.scan
    s.running, s.pending = false, false
    if s.handle then schedule.cancel(s.handle) s.handle = nil end
    if state.dirty then save() end
  end

  local function finishScan()
    M.stopScan()
    if state.onScanComplete then state.onScanComplete() end
  end

  local function tick()
    local s = state.scan
    if not s.running then return end

    if s.pending then
      if controller.uptime() - s.startedAt < CONFIG.scanReplyTimeoutMs then return end
      s.pending = false                           -- timed out, move on
    end
    if s.finished then finishScan() return end    -- last reply (or timeout) done

    local port = state.getPort and state.getPort()
    if port == nil then
      print("PatchNames: no port, stopping scan")
      M.stopScan()
      return
    end

    s.reqBank, s.reqPatch = s.bank, s.patch
    midi.sendSysex(port, CONFIG.buildRequest(s.bank, s.patch))
    s.pending, s.startedAt = true, controller.uptime()

    s.patch = s.patch + 1
    if s.patch > lastPatch then
      s.patch = CONFIG.patchBase
      s.bank = s.bank + 1
      if s.bank > lastBank then s.finished = true end
    end
  end

  function M.startScan()
    local s = state.scan
    if s.running then return end
    s.running, s.finished, s.pending = true, false, false
    s.bank, s.patch = CONFIG.bankBase, CONFIG.patchBase
    s.handle = schedule.every(CONFIG.scanPeriodMs, tick)
  end

  function M.save() save() end

  return M
end)(PATCHNAMES_PROFILE)

------------------------------------------------------------
-- SECTION 3: HOST WIRING  (adapt per synth)
------------------------------------------------------------
-- Put this AFTER your port/device variables exist.
PatchNames.init{
  getPort = function() return port end,
  onScanComplete = function()
    -- e.g. reset the "scan" button parameter in your preset
    parameterMap.set(deviceId, PT_VIRTUAL, 10024, 0)
  end,
--  optional print:
--  onNameUpdated = function(bank, patch, name) 
--     print("name", bank, patch, name)
--  end,
}

-- 1. In your scan button's Lua callback:
--      function startPatchScanner(valueObject, value)
--        if value ~= 0 then PatchNames.startScan() end
--      end
-- 2. At the top of your existing midi.onSysex:
--      if PatchNames.handleSysex(sysexBlock) then return end
-- 3. In your existing preset.onLoad:
--      PatchNames.load()
-- 4. To show a name:   PatchNames.get(bank, patch)


-- The following example and Bank and Patch Number controls are for the Novation Peak only.

function startPatchScanner(valueObject, value)
  if value ~= 0 then PatchNames.startScan() end
end

function midi.onSysex(midiInput, sysexBlock)
  if PatchNames.handleSysex(sysexBlock) then return end
  -- other SysEx handling goes here
end

function preset.onLoad()
  -- load persisted name data if created
  PatchNames.load()
end

local CTRL_PATCH_NUMBER = 4 -- the Patch Number Control ID #

function displayPatch(valueObject, value)
  local bankTxt = {"A","B","C","D"}
  local bankNum = parameterMap.get(deviceId, PT_VIRTUAL, 10032)
  local patchName = PatchNames.get(bankNum, value)
  controls.get(CTRL_PATCH_NUMBER):setName(patchName)
  return bankTxt[bankNum] .. " " .. string.format("%03d", value)
end
