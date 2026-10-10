--------- Patch name processing for Peak 
local nameBank = {}    -- to store patch names of each bank
for y = 1,4 do        -- 1 = bank A, 2= bank B, 3 = bank C, 4 = bank D
    nameBank[y] = {}
    for z = 0,127 do  -- patch numbers 0..127
        nameBank[y][z] = ""
    end
end

-- helper function to remove empty spaces from patch names before they are stored
local function cleanPatchName(s)
  -- remove NULs first, then trim trailing whitespace
  s = s:gsub("%z", "")
  s = s:gsub("%s+$", "")
  return s
end

-- ---------- Persistence helpers for patch-name cache ----------
-- Electra One runtime in this preset:
--   persist(table)
--   recall(table)
-- We persist a tagged flat map and rebuild nameBank on load.
-- a tag to keep track of versions of patch-banks on the Peak 
local PERSIST_TAG = "peakPatchNamesV1"

local function makePatchKey(bank, patch)
  return string.format("b%d_p%03d", bank, patch) -- bank 1..4, patch 0..127
end

local function flattenNameBank(src)
  local flat = {}
  local count = 0
  for b = 1, 4 do
    for p = 0, 127 do
      local v = src[b] and src[b][p] or ""
      v = tostring(v or "")
      flat[makePatchKey(b, p)] = v
      if v ~= "" then count = count + 1 end
    end
  end
  return flat, count
end

local function inflateNameBank(flat)
  local dst = {}
  local count = 0
  for b = 1, 4 do
    dst[b] = {}
    for p = 0, 127 do
      local v = (flat and flat[makePatchKey(b, p)]) or ""
      dst[b][p] = v
      if v ~= "" then count = count + 1 end
    end
  end
  return dst, count
end

local function saveNameBank()
  local flat, count = flattenNameBank(nameBank)
  local payload = {
    _tag = PERSIST_TAG,
    names = flat
  }
  local ok, err = pcall(persist, payload)
  if ok then
    print(string.format("nameBank persisted (%d non-empty names)", count))
  else
    print("nameBank persist failed: " .. tostring(err))
  end
end

local function loadNameBank()
  local payload = {}
  local ok, err = pcall(recall, payload) -- recall(destinationTable)
  if not ok then
    print("nameBank recall failed: " .. tostring(err))
    return
  end
  if payload._tag ~= PERSIST_TAG then
    print("nameBank recall: no matching persisted payload tag")
    return
  end
  if type(payload.names) ~= "table" then
    print("nameBank recall: payload.names missing/invalid")
    return
  end
  local rebuilt, count = inflateNameBank(payload.names)
  nameBank = rebuilt
  print(string.format("nameBank restored (%d non-empty names)", count))
end

-- Debounced/controlled persistence during large scans
local nameBankDirty = false
local nameBankUpdates = 0
local SAVE_EVERY_N_UPDATES = 128 

local function markNameBankDirty()
  nameBankDirty = true
  nameBankUpdates = nameBankUpdates + 1
  -- periodic checkpoint save during long scans
  if (nameBankUpdates % SAVE_EVERY_N_UPDATES) == 0 then
    saveNameBank()
    nameBankDirty = false
  end
end

local function flushNameBankIfDirty()
  if nameBankDirty then
    saveNameBank()
    nameBankDirty = false
  end
end

------------------ Schedule patch scanning to extract patch name ------------------------
--
local patchScanState = {
  bank = 1,           -- current bank (1-4)
  patch = 0,          -- current patch (0-127)
  isRunning = false   -- scanner active flag
}
local SCAN_HEADER = { 0x00, 0x20, 0x29, 0x01, 0x10, 0x00, 0x7E, 0x41, 0x00, 0x00, 0x00 }
local SCAN_PERIOD_MS = 200
local scanHandle = nil

local function stopPatchScanner()
  patchScanState.isRunning = false
  if scanHandle ~= nil then
    schedule.cancel(scanHandle)
    scanHandle = nil
  end
  flushNameBankIfDirty()
  print("Patch scanner stopped")
end

local function scanNextPatch()
  if not patchScanState.isRunning then
    return
  end
  local bank = patchScanState.bank
  local patch = patchScanState.patch
  local msg = concat(SCAN_HEADER, {bank, patch})
  midi.sendSysex(port, msg)
  print(string.format(
    "Requesting Bank %d, Patch %03d",
    bank,
    patch
  ))
  patchScanState.patch = patch + 1
  if patchScanState.patch >= 128 then
    patchScanState.patch = 0
    patchScanState.bank = patchScanState.bank + 1
    if patchScanState.bank > 4 then
      patchScanState.bank = 1
      print("Patch scanner cycle complete")
      stopPatchScanner()
      parameterMap.set(deviceId, PT_VIRTUAL, 10024, 0)
    end
  end
end

function startPatchScanner(valueObject, value)
  if value == 0 then
    return
  end
  if patchScanState.isRunning then
    print("Patch scanner already running")
    return
  end
  patchScanState.isRunning = true
  patchScanState.bank = 1
  patchScanState.patch = 0
  print("Starting patch scanner: 4 banks × 128 patches")
  scanHandle = schedule.every( SCAN_PERIOD_MS, scanNextPatch  )
end

----------------------------- midi receive function to read Peak patch name ----------------------------------------
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
  -- a stored patch received and the patch name placed in nameBank[bankNum][patchNum]
  if len > 33 and cmd == 0x01 then 
    local bankNum = sysexBlock:peek(13)
    local patchNum = sysexBlock:peek(14)
    print("bank ".. math.floor(bankNum).."  patch " ..math.floor(patchNum).." received")
    local rawName = ""
    for i = 0,15 do
      rawName = rawName .. string.char(sysexBlock:peek(17+i))
    end
    nameBank[bankNum][patchNum] = cleanPatchName(rawName)
    markNameBankDirty()
  end
end

function preset.onLoad()
  -- load persisted name data if created
  loadNameBank()
end
