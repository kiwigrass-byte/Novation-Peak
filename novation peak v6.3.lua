-- Novation PEAK preset v6.3
-- 08/24/26
local authorDate = "New Ignis Kiwigrass"
info.setText(authorDate)

local deviceId = 1 -- the device ID used in the E1 preset
local device = devices.get(deviceId)
local port = device:getPort()
local channel = device:getChannel()

-- set timer interval for requesting each of 512 patch dumps for patch name extraction
timer.setPeriod(200) -- 200 ms

-- events to track
events.subscribe(PAGES | POTS)

-- Peak-reported channel (source of truth when available)
local midiChannel = nil

-- assign MIDI channel based on Peak
function assignChannel(valueObject, value)
  device:setChannel(midiChannel)
  channel = device:getChannel()
  deviceId = device:getId()
  port = device:getPort()
end

local sysExPatch = {}   -- sysExPatch[byte] – store patch data
local sysExSettings = {} -- sysExSettings[byte] – store settings data

-- NRPN reassembly registers
local msbNum = 0
local lsbNum = 0

local nameBank = {}    -- to store patch names of each bank
for y = 1,4 do        -- 1 = bank A, 2= bank B, 3 = bank C, 4 = bank D
    nameBank[y] = {}
    for z = 0,127 do  -- patch numbers 0..127
        nameBank[y][z] = ""
    end
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
local SAVE_EVERY_N_UPDATES = 32 -- tune to 16/32/64 if desired

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

-- request Peak wavetable names and global settings on preset load
function preset.onLoad()
  loadNameBank()       -- restore cached patch names first
  getAllWaveNames(nil, 1)
  getSettings(nil,1) 
  pages.display(12)
end

-- helper function to find target array from a table of arrays
local function findArrayByValue(tbl, targetValue1,targetValue2) 
    for i, arr in ipairs(tbl) do
        if arr[1] == targetValue1 and arr[2] == targetValue2 then
            return arr
        end
    end
    return nil -- not found
end

-- helper function to get a specific bit series from a value
local function getBits(value, start, length) 
    -- Calculate the mask by shifting (1 << length) - 1 to the correct position
    local mask = (1 << length) - 1
    -- Shift the mask to the starting position and apply it to the value
    return (value >> (9 - start - length)) & mask
end

-- helper function to concatenate two arrays. Used for SysEx message construction
local function concat(t1, t2)
  local t = {}
  for i=1,#t1 do t[#t+1] = t1[i] end
  for i=1,#t2 do t[#t+1] = t2[i] end
  return t
end

-- ── Helper: safe controls.get() (pcall-wrapped for deleted/invalid IDs) ────────
local function safeGet(id)
  local ok, c = pcall(controls.get, id)
  return ok and c or nil
end

-- I only want to send some MIDI messages after a control knob is released (for example, to avoid sending a stream of 527 byte sysEx messages when scrolling a settings fader)
-- curCtl holds which of the control knobs was touched (HT @oldgearguy)
curCtl   = -1

-- control Ids for the controls that I only want to send MIDI data after I have released the knob
local releaseCtls = {318,356,357,358} -- control # of master clock fader, transpose fader, master fine tune fader, velocity curve 

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
  local idx = get_key_for_value(releaseCtls,controlId)
  local sendHeader = {0x00, 0x20, 0x29, 0x01, 0x10, 0x00, 0x7E,0x00,0x00,0x00,0x00,0x00,0x00,0x00} -- first section of sysEx message for sending a patch to Peak's edit buffer 
  local settingsHeader = {0x00, 0x20, 0x29, 0x01, 0x10, 0x00, 0x7E,0x04,0x00,0x00,0x00,0x00,0x00,0x00} -- first section of sysEx message for sending system settings to Peak 
  if (idx == nil) then return end
  if (touched == true) and (curCtl ~= controlId) then curCtl = controlId end
  if (touched == false) and (curCtl == controlId) then
    local midiValue = controls.get(controlId):getValue("value"):getMessage():getValue()
    if curCtl == 318 then -- clock
      sysExPatch[237] = math.floor(midiValue/2)
      sysExPatch[238] = 64*(midiValue%2)
      midi.sendSysex (port, concat(sendHeader,sysExPatch)) -- sends the updated patch to the edit buffer of the Peak
    elseif curCtl == 356 then
      sysExSettings[16] = midiValue
      midi.sendSysex (port, concat(settingsHeader,sysExSettings))  -- sends the updated settings to the Peak
    elseif curCtl == 357 then
      sysExSettings[15] = midiValue
      midi.sendSysex (port, concat(settingsHeader,sysExSettings)) 
    elseif curCtl == 358 then
      sysExSettings[14] = midiValue
      midi.sendSysex (port, concat(settingsHeader,sysExSettings)) 
    end
  end
end

-- display formatter functions ---------------------------------------------------------------------
-- Wavetable name lookup 
local waveTableNames = {
  [4]="BS Sine",   [5]="Random",   [6]="Zing",      [7]="Tubey",    [8]="Octaves",
  [9]="Wobbler",   [10]="Chords",  [11]="Didgery",  [12]="Harsh",   [13]="Organ",
  [14]="E.Piano",  [15]="VoxOooEe",[16]="VoxYahEe", [17]="Winds",   [18]="SoftClav",
  [19]="String",   [20]="BassOrgn",[21]="Acid",     [22]="Buzzy",   [23]="Carousel",
  [24]="Choral",   [25]="Clmbing", [26]="CoinFlip", [27]="Deep",    [28]="Dub",
  [29]="Eee",      [30]="Eris",    [31]="Flame",    [32]="Further", [33]="GlassSaw",
  [34]="Glassy",   [35]="Granular",[36]="Grime",    [37]="Drow",    [38]="Heavy",
  [39]="Hedge",    [40]="Hungry",  [41]="Ladders",  [42]="Lead",    [43]="Modeling",
  [44]="Modem",    [45]="Monster", [46]="Screech",  [47]="SeaBase", [48]="Shmorgan",
  [49]="Sprials",  [50]="Steel",   [51]="Sunrise",  [52]="Swell",   [53]="Thicker",
  [54]="Thinner",  [55]="Tides",   [56]="Tokyo",    [57]="Tops",    [58]="VChord",
  [59]="Variance", [60]="Vocaloid",[61]="Vowelled", [62]="WeirdVox",[63]="Yeah",
  [64]="User 1",   [65]="User 2",  [66]="User 3",   [67]="User 4",  [68]="User 5",
  [69]="User 6",   [70]="User 7",  [71]="User 8",   [72]="User 9",  [73]="User 10"
}

local notes = {"C  %d","C# %d","D  %d","D# %d","E  %d","F  %d","F# %d","G  %d","G# %d","A  %d","A# %d","B  %d"}

function displayBpm(valueObject,value)
   return(math.floor(value) .. " bpm")
end

function displayNotes (valueObject, value)
  if value > 0 then return (string.format(notes[math.fmod(value-1, 12)+1], (value// 12)-2)) 
  else return("X")
  end
end

function displayPatch (valueObject, value)
  local bankTxt={"A","B","C","D"} -- abbreviations of the bank names
  local bankNum = parameterMap.get (deviceId, PT_VIRTUAL, 10032)
  local patchName = nameBank[bankNum][value]
  local c423 = safeGet(423); if c423 then c423:setName(patchName) end
  return (bankTxt[bankNum].." "..string.format("%03d",value))
end

function displayChar (valueObject, value) -- borrowed from pro 800 preset to display patch names
  -- The full name is assembled and pushed to the info bar inside assignParam().
  return string.char(value)
end

function displayWaveTable(valueObject, value)
  return waveTableNames[value] or string.format("Wave %d", value)
end

-- ── AHDSR value-in-name suffix ───────────────────────────────────────────────
-- Appends the live value of an AHDSR envelope's primary stage to its tile
-- title, e.g. "AMP ATTACK" -> "AMP ATTACK 101". The base (unsuffixed) name is
-- captured the first time each control is seen so repeat updates don't keep
-- stacking suffixes onto an already-modified name.

local ahdsrBaseNames = setmetatable({}, {__mode = "k"})

function ahdsrValueName(valueObject, value)
  local ctrl = valueObject:getControl()
  --if not ctrl then return end
  local id = ctrl:getId()
  if not ahdsrBaseNames[id] then ahdsrBaseNames[id] = ctrl:getName() end
  ctrl:setName(ahdsrBaseNames[id] .. " " .. string.format("%d", value))
  -- print ("ctl = "..id..", base Name = "..ahdsrBaseNames[id])
end

function semiTones(valueObject, value)
  if value > 0 then return string.format("%.1f st", value*12/127)
  else return string.format("%.1f st", value*12/128) end
end

function percent(valueObject,value) ---- 
  return string.format ("%d %%", value)
end

function cent(valueObject,value) ---- 
  return string.format ("%d cents", value)
end

function st(valueObject,value) ---- 
  return string.format ("%d semitones", value)
end

function convertToPhase(valueObject,value) ---- 
  return string.format ("%d deg", (value-1)*3)
end

-- Mod matrix depth formatters – colour-code src/dst controls and refresh the visualisation
function modWhite(valueObject, value)
  local id = valueObject:getControl():getId()
  local color = (value == 0) and 0x202020 or WHITE
  controls.get(id-6):setColor(color); controls.get(id-5):setColor(color)
  controls.get(id  ):setColor(color); controls.get(id+1):setColor(color)
  return string.format("%d", value)
end

function modOrange(valueObject, value)
  local id = valueObject:getControl():getId()
  local color = (value == 0) and 0x202020 or ORANGE
  controls.get(id-6):setColor(color); controls.get(id-5):setColor(color)
  controls.get(id  ):setColor(color); controls.get(id+1):setColor(color)
  return string.format("%d", value)
end

function modGreen(valueObject, value)
  local id = valueObject:getControl():getId()
  local color = (value == 0) and 0x202020 or GREEN
  controls.get(id-6):setColor(color); controls.get(id-5):setColor(color)
  controls.get(id  ):setColor(color); controls.get(id+1):setColor(color)
  return string.format("%d", value)
end

-- set color formatters for controls
local colorConfigs = {
  blue   = { off = 0x202067, on = BLUE },
  orange = { off = 0x572700, on = ORANGE },
  green = { off = 0x003930, on = GREEN },
  yellow = { off = 0x505000, on = 0xF1F50E },
  white = { off =  0x202020, on = 0xFFFFFF },
  grey = { off = 0x101010, on =  0x6F6F6F },
  red = { off = 0x401010, on = RED },
  purple = { off = 0x401040, on = PURPLE},
}

local function makeColorFormatter(colorConfig)
  return function(valueObject, value)
    valueObject:getControl():setColor(value == 0 and colorConfig.off or colorConfig.on)
    return string.format("%d", value)
  end
end

lightBlue = makeColorFormatter(colorConfigs.blue)
colOrange = makeColorFormatter(colorConfigs.orange)
colGreen = makeColorFormatter(colorConfigs.green)
colYellow = makeColorFormatter(colorConfigs.yellow)
colWhite = makeColorFormatter(colorConfigs.white)
colGrey = makeColorFormatter(colorConfigs.grey)
colRed = makeColorFormatter(colorConfigs.red)
colPurple = makeColorFormatter(colorConfigs.purple)

-- visibility options for wave shape options
function waveChange(valueObject, value)
  local parameter = valueObject:getMessage ():getParameterNumber ()
  sendSimpleNRPN(parameter, value)
  local oscNumber = 1
  if parameter == 23 then  oscNumber = 2 elseif parameter == 32 then oscNumber = 3
  end
  local controlTbl = {{9,38,39,5},{21,50,51,17},{33,62,63,29}} -- shape, wave density, wave spread, wave table
  local control = controls.get(controlTbl[oscNumber][1]) -- setting shape name
  local nameTbl = {"FOLD","FOLD","FOLD","PULSE WIDTH","SHAPE"}
  control:setName(nameTbl[value+1]) 
  local visiBool = (value == 2) -- showing wave density and wavespread if saw waveform
  for i = 2,3 do controls.get(controlTbl[oscNumber][i]):setVisible(visiBool) end
  controls.get(controlTbl[oscNumber][4]):setVisible(value == 4) -- shape, wave density, wave spread, wave table
end

-- visibility options for voice options
function voiceMode(valueObject, value)
  local visiBool = value <= 1 -- showing monotrig if in mono or monoLG mode
  for _,id in ipairs({118,130,142}) do controls.get(id):setVisible(visiBool) end -- envelope monotrig
  local visiBool = value <= 2 -- showing lfo monotrig if in monophonic mode
  for _,id in ipairs({149,161,155,167}) do controls.get(id):setVisible(visiBool) end -- lfo monotrig, fade sync
  controls.get(156):setSlot(11, 5)
  controls.get(168):setSlot(23, 5)
  for _,id in ipairs({156,168}) do controls.get(id):setVisible(not visiBool) end -- lfo common sync
end

function egLoop(valueObject, value)
  local parameter = valueObject:getMessage():getParameterNumber()
  local egNumber = parameter - 3226
  controls.get(({119,131,143})[egNumber]):setVisible(value == 1) -- repeats
end

function unison(valueObject, value)
  controls.get(48):setColor(value == 0 and 0x202020 or WHITE)
end

function glide(valueObject, value)
  local color = (value == 0) and 0x001013 or GREEN
  for i = 1,2 do controls.get(({418,419})[i]):setColor(color) end
end

-- set note/time sync ---- 
function setSync(valueObject, value)
  local parameter    = valueObject:getMessage ():getParameterNumber ()
  local messageValue = valueObject:getMessage ():getValue ()
  local messageType  = valueObject:getMessage ():getType ()
  if messageType == PT_VIRTUAL then sendSimpleNRPN(parameter, messageValue) end
  local paramTbl = {
    {68,0,146,11,2,147,5,2},{68,1,146,11,2,147,5,2},{68,2,147,11,1,146,5,2},
    {83,0,158,11,8,159,5,14},{83,1,158,11,8,159,5,14},{83,2,159,11,7,158,5,14},
    {3225,0,170,11,14,171,5,26},{3225,1,171,11,13,170,5,26},{3226,0,173,11,20,174,5,29},
    {3226,1,174,11,19,173,5,29},{93,0,195,11,26,194,6,13},{93,1,194,11,25,195,6,13}
  }  
    -- member array = {parameter, value, ctl to hide, page, slot, ctl to show, page, slot}
    -- 68 = range LFO1, CC31/CC84 = off/on LFO2, 3201-2 = off/on LFO3, 3204-5 = off/on LFO4, CC109/94 = off/on Delay
  local member = findArrayByValue(paramTbl, parameter,value) -- retrieve the desired array
  controls.get(member[3]):setSlot(member[5], member[4])
  controls.get(member[6]):setSlot(member[8], member[7])
end

---------------------------- MIDI send functions ---------------------------------------
function sendSimpleNRPN(nrpn, value)
  midi.sendControlChange (port , channel , 99, math.floor(nrpn/128))
  midi.sendControlChange (port , channel , 98, nrpn%128)
  midi.sendControlChange (port , channel , 6, value)
end

function sendPatch(valueObject, value) -- Send patch data
  if value == 0 then return end
  local sendHeader = {0x00, 0x20, 0x29, 0x01, 0x10, 0x00, 0x7E,0x00,0x00,0x00,0x00,0x00,0x00,0x00}
  midi.sendSysex (port, concat(sendHeader,sysExPatch)) -- sends the current state of the patch from E1 to the edit buffer of the Peak
end

function sendSettings(valueObject, value) -- Send settings data
  if value == 0 then return end
  local sendHeader = {0x00, 0x20, 0x29, 0x01, 0x10, 0x00, 0x7E,0x04,0x00,0x00,0x00,0x00,0x00,0x00}
  midi.sendSysex (port, concat(sendHeader,sysExSettings)) -- sends the settings back to the Peak
end

function selectIt(valueObject, value)
  if value==0 then return end
  local message = valueObject:getMessage ()
  local parameterNumber = message:getParameterNumber ()
  local messageValue = message:getValue ()
  local bankNum = parameterMap.get (deviceId, PT_VIRTUAL, parameterNumber-messageValue -1)
  local progNum = parameterMap.get (deviceId, PT_VIRTUAL, parameterNumber-messageValue ) + messageValue - 2
  if bankNum == 0 then bankNum =1 end
  if progNum == 128 then progNum= 0 end
  if progNum == -1   then progNum=127  end
  parameterMap.set (deviceId, PT_VIRTUAL, parameterNumber-messageValue,progNum+1)
  parameterMap.set (deviceId, PT_VIRTUAL, parameterNumber-messageValue,progNum)
  midi.sendControlChange(port , channel , 32, bankNum)
  midi.sendProgramChange(port , channel , progNum)
  -- request patch 
  getPatch(nil,1)
end

--------------------------------- MIDI request functions ----------------------------------------------------------
-- request current patch data from edit buffer without a program change message sent first (if patch selected on Peak rather than E1)
function getPatch(valueObject, value)
  if value == 0 then return end
  midi.sendSysex (port, {0x00, 0x20, 0x29, 0x01, 0x10, 0x00, 0x7E,0x40,0x00,0x00,0x00,0x00,0x00}) 
end

 -- request Peak settings data
function getSettings(valueObject,value)
  if value == 0 then return end
  midi.sendSysex (port, {0x00, 0x20, 0x29, 0x01, 0x10, 0x00, 0x7E,0x44,0x00,0x00,0x00,0x00,0x00})
end

-- Request user wavetable names for all 10 user slots (64-73). Each response triggers waveName update via midi.onSysex (cmd=0x07).
function getAllWaveNames(valueObject, value)
  if value == 0 then return end
  for i = 64, 73 do
    midi.sendSysex(port, {0x00, 0x20, 0x29, 0x01, 0x10, 0x00, 0x7E,0x47,0x00,0x00,i,0x00,0x00})
  end
end
--------------------------- Timer-based patch scanning all patches al all banks ----------------------------------------
-- State tracking for the patch scanner
local patchScanState = {
  bank = 1,           -- current bank (1-4)
  patch = 0,          -- current patch (0-127)
  isRunning = false   -- scanner active flag
}

-- Start the patch scanner (sends 5 requests per second)
function startPatchScanner(valueObject,value)
  if value == 0 then return end
  if patchScanState.isRunning then
    print("Patch scanner already running")
    return
  end
  patchScanState.isRunning = true
  patchScanState.bank = 1
  patchScanState.patch = 0
  print("Starting patch scanner: 4 banks × 128 patches")
  timer.enable()
end

-- function to stop the patch scanner
local function stopPatchScanner()
  timer.disable()
  patchScanState.isRunning = false
  flushNameBankIfDirty()   -- final save at end of scan
  print("Patch scanner stopped")
end

local SCAN_HEADER = {0x00, 0x20, 0x29, 0x01, 0x10, 0x00, 0x7E, 0x41, 0x00, 0x00, 0x00}

-- Timer callback (called by Electra One runtime)
function timer.onTick()
  if not patchScanState.isRunning then return end
  -- Send the sysex request for current bank/patch
  local msg = concat(SCAN_HEADER, {patchScanState.bank, patchScanState.patch})
  midi.sendSysex(port, msg)
  print(string.format("Requesting Bank %d, Patch %03d", patchScanState.bank, patchScanState.patch))
  -- Advance to next patch
  patchScanState.patch = patchScanState.patch + 1
  -- Check if we've reached the end of this bank
  if patchScanState.patch >= 128 then
    patchScanState.patch = 0
    patchScanState.bank = patchScanState.bank + 1
    -- Check if we've completed all 4 banks
    if patchScanState.bank > 4 then
      patchScanState.bank = 1
      print("Patch scanner cycle complete")
      stopPatchScanner()
      parameterMap.set(deviceId, PT_VIRTUAL, 10024, 0)
    end
  end
end

-- assigns sysEx MIDI values from received patch to corresponding preset parameter values: {byte #, parameter type, nrpn #}
function assignParam()   
  if not sysExPatch[2] then return end -- do not process if not parsed
  local sysEx2Param = {{2,0,10001},{3,0,10002},{4,0,10003},{5,0,10004},{6,0,10005},{7,0,10006},{8,0,10007},{9,0,10008},{10,0,10009},{11,0,10010},{12,0,10011},{13,0,10012},{14,0,10013},{15,0,10014},{16,0,10015},{17,0,10016},{34,0,2},{35,0,3},{36,0,4},
                     {37,0,5},{39,1,5},{40,0,7},{41,1,35},{43,0,9},{44,0,10},{45,0,11},{46,0,12},{47,0,13},{48,1,3},{49,12,14},{51,1,15},{53,1,9},{54,12,16},{56,0,14},{57,0,15},{59,1,12},{60,1,119},{61,1,33},{62,1,34},{63,0,17},{64,0,18},
                     {65,0,19},{66,0,20},{69,1,37},{70,12,17},{72,1,18},{74,1,38},{75,12,19},{77,0,23},{78,0,24},{80,1,39},{81,1,40},{82,1,41},{83,1,42},{84,0,26},{85,0,27},{86,0,28},{87,0,29},{90,1,65},{91,12,20},{93,1,21},{95,1,43},{96,12,22},
                     {98,0,32},{99,0,33},{101,1,71},{102,1,72},{103,1,73},{104,1,44},{105,0,35},{106,0,36},{107,0,37},{108,0,38},{111,12,23},{113,12,24},{115,12,25},{117,12,26},{119,12,27},{121,0,41},{122,0,42},{123,0,43},{124,0,44},{125,1,80},
                     {126,1,36},{127,0,45},{128,0,46},{129,1,75},{130,1,79},{131,12,29},{133,12,28},{135,1,76},{137,1,77},{138,1,78},{139,0,48},{142,0,51},{143,0,52},{146,1,86},{147,1,87},{148,1,88},{149,1,89},{150,0,55},{151,0,56},{152,0,57},
                     {153,0,58},{155,1,90},{156,1,91},{157,1,92},{158,1,93},{159,0,60},{160,0,61},{161,0,62},{162,0,63},{163,1,94},{164,1,95},{165,1,117},{166,1,103},{167,0,64},{168,0,65},{169,0,66},{170,0,67},{171,0,68},{172,12,30},{174,1,81},
                     {175,0,69},{176,0,70},{177,0,71},{178,1,82},{179,0,72},{180,0,73},{181,0,74},{182,0,75},{183,0,76},{185,1,83},{186,12,31},{188,1,84},{189,0,78},{190,0,79},{191,0,80},{192,1,85},{193,0,81},{194,0,82},{195,0,83},{196,0,84},
                     {197,0,85},{199,1,104},{201,0,88},{202,0,89},{204,1,108},{205,1,109},{206,0,91},{207,0,92},{208,0,93},{209,0,94},{210,1,110},{211,0,95},{212,0,96},{213,0,97},{214,0,98},{217,1,112},{218,0,101},{219,1,113},{220,0,102},{221,0,103},
                     {222,0,104},{223,0,105},{224,0,106},{225,0,107},{226,0,108},{227,0,109},{229,1,105},{230,0,111},{231,1,118},{232,0,112},{233,1,107},{234,0,113},{235,0,114},{236,0,115},{237,0,16003},{239,0,116},{240,0,117},{241,0,118},{242,0,119},
                     {243,1,116},{244,0,120},{245,0,121},{246,0,122},{247,0,123},{248,0,124},{252,0,128},{253,0,129},{254,0,130},{255,0,131},{256,0,256},{257,0,257},{258,0,258},{259,0,259},{260,0,384},{261,0,385},{262,0,386},{263,0,387},
                     {264,0,512},{265,0,513},{266,0,514},{267,0,515},{268,0,640},{269,0,641},{270,0,642},{271,0,643},{272,0,768},{273,0,769},{274,0,770},{275,0,771},{276,0,896},{277,0,897},{278,0,898},{279,0,899},{280,0,1024},{281,0,1025},
                     {282,0,1026},{283,0,1027},{284,0,1152},{285,0,1153},{286,0,1154},{287,0,1155},{288,0,1280},{289,0,1281},{290,0,1282},{291,0,1283},{292,0,1408},{293,0,1409},{294,0,1410},{295,0,1411},{296,0,1536},{297,0,1537},{298,0,1538},
                     {299,0,1539},{300,0,1664},{301,0,1665},{302,0,1666},{303,0,1667},{304,0,1792},{305,0,1793},{306,0,1794},{307,0,1795},{308,0,1920},{309,0,1921},{310,0,1922},{311,0,1923},{312,0,2048},{313,0,2049},{314,0,2050},{315,0,2051},
                     {316,0,2176},{317,0,2177},{318,0,2178},{319,0,2179},{320,0,2304},{321,0,2305},{322,0,2306},{323,0,2307},{324,0,2432},{325,0,2433},{326,0,2434},{327,0,2435},{328,0,2560},{329,0,2561},{330,0,2562},{331,0,2563},{348,0,3200},
                     {349,0,3201},{350,0,3202},{351,0,3203},{352,0,3204},{353,0,3205},{354,0,3206},{357,0,3209},{358,0,3210},{359,0,3211},{361,0,3213},{362,0,3214},{363,0,3215},{365,0,3217},{366,0,3218},{367,0,3219},{369,0,3221},{370,0,3222},{371,0,3223},
                     {373,0,3225},{374,0,3226},{375,0,3227},{376,0,3228},{377,0,3229},{378,0,3230},{379,0,3231},{380,0,3232},{381,0,3233},{382,0,3234},{383,0,3235},{384,0,3236},{385,0,3237},{386,0,3238},{387,0,3239},{388,0,3240},{389,0,3241},
                     {390,0,3242},{391,0,3243},{392,0,3244},{393,0,3245}}
  for i = 1, #sysEx2Param do
    local sysExByte = sysEx2Param[i][1] -- byte number of sysEx payload 
    local parType = sysEx2Param[i][2]%10 -- parameter type (0 = virtual, 1 = CC7, 2 = CC14 -- see below for value calculation, 3 = NRPN -- not used)
    local parNum = sysEx2Param[i][3]  -- parameter number
    local value = sysExPatch[sysExByte] -- parameter value
    if sysEx2Param[i][2] == 12 then -- 12 stands for a type CC14 of which byte 1 has bits 8-1 and byte 2 has bit 0 on place 6
      value = 64 * (sysExPatch[sysEx2Param[i][1]] * 2 + getBits(sysExPatch[sysEx2Param[i][1]+1], 2, 1) )
    elseif sysEx2Param[i][1] == 237 then  -- clock rate 
      value = (sysExPatch[sysEx2Param[i][1]] * 2 + getBits(sysExPatch[sysEx2Param[i][1]+1], 2, 1) )
      --print("i "..i..", byte "..sysEx2Param[i][1].. ": value = "..value.."  bit 0 = "..getBits(sysExPatch[partNum][sysEx2Param[i][1]+1],2,1) )
    end
    parameterMap.set (deviceId, parType, parNum, value)
  end
  -- Update info bar with patch name
  local patchName = ""
  for j = 0, 15 do
    local ch = parameterMap.get(deviceId, PT_VIRTUAL, 10001+j)
    if ch and ch ~= 0 then patchName = patchName .. string.char(ch) end
  end
  if #patchName > 0 then info.setText(string.sub(patchName, 1, 20)) end
end

 -- assigns sysEx MIDI values from received settings to corresponding preset parameter values
function assignSettings()  
  if not sysExSettings[2] then return end
  local param = {{2,8192},{8,8198},{14,8204},{15,8205},{16,8206},{17,8207},{19,8209},{31,8221},{32,8222}}
  for i = 1, #param do
    parameterMap.set (deviceId, PT_VIRTUAL, param[i][2], sysExSettings[param[i][1]])
  end
end

-- helper function to remove empty spaces from patch names before they are stored
local function cleanPatchName(s)
  -- remove NULs first, then trim trailing whitespace
  s = s:gsub("%z", "")
  s = s:gsub("%s+$", "")
  return s
end

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
--  print("Peak sysex message received on interface= " .. midiInput.interface..", cmd=0x"..string.format("%02X",cmd).." len="..len)

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

  -- patch from edit buffer received (no bank or patch number)
  elseif len == 527 and cmd == 0x00 then 
    print("patch from edit buffer received")
    for i = 1,512 do
      sysExPatch[i]=sysexBlock:peek(i+15)
    end
    assignParam()

  -- settings received
  elseif len == 527 and cmd == 0x04 then 
    print("settings received")
    for i = 1,511 do
      sysExSettings[i]=sysexBlock:peek(i+15)
    end
    assignSettings()
    midiChannel = parameterMap.get(deviceId, PT_VIRTUAL, 8207) + 1
    print("Peak's MIDI Channel: "..math.floor(midiChannel))
    assignChannel(nil,1)         -- should set device channel to same as Peak's when preset loaded

  -- user wavetable name received 
  elseif len == 23 and cmd == 0x07 then
  print("user wavetable name received") 
    local waveName = ""
    for i = 1, 7 do 
      waveName = waveName .. string.char(sysexBlock:peek(i+15))
    end
    waveTableNames[sysexBlock:peek(15)] = waveName
  end
end

function midi.onControlChange(midiInput, ch, controllerNumber, value)
  if controllerNumber == 32 then
    parameterMap.set(deviceId, PT_VIRTUAL, 10032, value)
  elseif controllerNumber == 99 then
    msbNum = value
  elseif controllerNumber == 98 then
    lsbNum = value
  elseif controllerNumber == 6 then
    local nrpn = 128*msbNum + lsbNum
    parameterMap.set(deviceId, PT_VIRTUAL, nrpn, value)
    -- assign new midi channel to device if channel changed on Peak
    if nrpn == 8207 then 
      midiChannel = value+1 
      assignChannel(nil,1) 
      print("New MIDI Channel assigned by Peak: "..math.floor(midiChannel))
    end
  end
end

function midi.onProgramChange(midiInput, channel, programNumber)
  parameterMap.set(deviceId, PT_VIRTUAL, 10033, programNumber) -- updates patch number parameter if change patch on the Peak
  getPatch(nil,1)
end

function parameterMap.onChange(valueObjects, origin, midiValue)
  if (origin ~= INTERNAL) then return end
  local msg = valueObjects[1]:getMessage()
  local pNum = msg:getParameterNumber()
  local ctlId = valueObjects[1]:getControl():getId()
  local settingsHeader = {0x00, 0x20, 0x29, 0x01, 0x10, 0x00, 0x7E,0x04,0x00,0x00,0x00,0x00,0x00,0x00} -- first section of sysEx message for sending system settings to Peak 
  -- Patch cue toggle
  if pNum == 8192 then 
    sysExSettings[2] = parameterMap.get(deviceId, PT_VIRTUAL, pNum)
    midi.sendSysex (port, concat(settingsHeader,sysExSettings)) -- sends the updated settings to the Peak
  -- clock source
  elseif pNum == 8198 then 
    sysExSettings[8] = parameterMap.get(deviceId, PT_VIRTUAL, pNum)
    midi.sendSysex (port, concat(settingsHeader,sysExSettings)) 
  -- ARP > MIDI toggle
  elseif pNum == 8209 then 
    sysExSettings[19] = parameterMap.get(deviceId, PT_VIRTUAL, pNum)
    midi.sendSysex (port, concat(settingsHeader,sysExSettings)) 
  -- master vol range
  elseif pNum == 8221 then 
    sysExSettings[31] = parameterMap.get(deviceId, PT_VIRTUAL, pNum)
    midi.sendSysex (port, concat(settingsHeader,sysExSettings)) 
-- tuning mode for tuning table
  elseif pNum == 8222 then  
    sysExSettings[32] = parameterMap.get(deviceId, PT_VIRTUAL, pNum)
    midi.sendSysex (port, concat(settingsHeader,sysExSettings))
-- midi channel
  elseif pNum == 8207 then  
    sysExSettings[17] = parameterMap.get(deviceId, PT_VIRTUAL, pNum)
    midi.sendSysex (port, concat(settingsHeader,sysExSettings))
    midiChannel = midiValue + 1
    print("New MIDI Channel assigned by preset: "..math.floor(midiChannel))
    assignChannel(nil,1)         -- should set device channel
-- send nrpn messages 
  elseif msg:getType() == PT_VIRTUAL and pNum < 8000 then
    sendSimpleNRPN(pNum, midiValue, channel)
  end
end
