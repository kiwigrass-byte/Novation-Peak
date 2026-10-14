-- Arpeggiator
-- Pattern (ref 2) is 14 modes: Up, Down, Up/Down, Up/Down Rpt Ends, Up -8ve,
-- Down -8ve, Up/Down -8ve, UpDwn Rpt -8ve, Step Up, Step Down, Random,
-- Random2, Random3, As Played - see PATTERN_* below (named Alt/Alt2
-- internally, for "alternating") and orderedNotes()/advanceStep() for what
-- each does.
-- References: 1 Tempo, 2 Pattern; 3/4/5 source iface/port/chan; 6/7/8 dest iface/port/chan;
--             9 Latch, 10 Octaves, 11 Gate Length, 12 Swing, 13 Sync Rate, 16 Chance,
--             18 Transpose Octave, 19 Transpose Semitone, 29 Arp On/Off, 32 Arp Reset,
--             33 Key, 34 Scale, 27 Mode, 36 Shape, 37 Chord Mode, 40 Inversion
--             (Shape mode only - see applyInversion() below), 53 HOLD (see onHoldChange
--             below - keeps a directly-sounding Shape/SATB or Chord Capture chord ringing
--             after the key is released; mutually exclusive with the arp).
--             60/61 Min/Max Note (Config page, keyboard split).
--
-- Harmony Mode (ref 37, labelled "HARMONY MODE" on the controller - still
-- "Chord Mode"/CHORD_MODE_* in this script, unrenamed internally) is Off,
-- Shape or SATB, and decides what a struck key turns into for the ARP
-- ITSELF - not a separate tool.
--
-- SATB (refs 50/51/52: ROOT DEGREE, CANTUS PRIMUS, POSITION) builds a
-- common-practice four-part harmonization. ROOT DEGREE does NOT pick one
-- fixed chord every note gets forced onto - it names the ROLE the struck
-- note plays in its OWN chord (I: the note is the root; III: the note is
-- the third, so the actual root is found two scale-steps below it; and so
-- on - see satbChordForNote()), so walking a scale produces a different,
-- diatonically correct chord quality for every note, the same way
-- Shape's Triad already varies by scale degree. The note is assigned
-- exactly to the voice CANTUS PRIMUS names, and the other three voices
-- are filled in by POSITION: Closed or Open (satbClosedOrOpen() - Soprano
-- is worked out from whichever voice Cantus Primus actually names, so the
-- struck note is transposed into place as that voice, then Alto/Tenor/Bass
-- stack below it as always), or one of four Tintinnabuli-style positions
-- after Arvo Part (satbTintinnabuli() - the same idea, generalized from
-- Alto instead of Soprano since that is Tintinnabuli's own reference
-- voice). Either way changing Cantus Primus genuinely changes the pitches
-- sent, not just which voice label is attached to them. SATB plugs
-- into the exact
-- same output machinery as Shape - joins the arp's pool when the arp is
-- on, sounds directly (through Break Time if set) when it is off, shares
-- Note Priority so one held key sounds at a time, and is mutually
-- exclusive with Chord Capture the same way Shape is.
--
-- Key/Scale Mode/Scale are not Shape-specific - the plain arp quantizes
-- every step through them too (see quantizeToScale() below) - so they
-- stay visible under every Harmony Mode, Off included. Only Shape's own
-- two (Shape, Inversion) and SATB's three (Root Degree/Cantus
-- Primus/Position) are shown/hidden by mode: Off hides both groups,
-- Shape shows its two and hides SATB's three, SATB shows its three and
-- hides Shape's two. See updateHarmonyParamVisibility() below.
--
-- Chord Capture (the CAPTURE pad, ref 26) and Shape/SATB are alternative
-- chord-to-key mappings and cannot both be live: selecting either clears
-- Chord Capture outright - exactly as pressing CLR CHORD would, including
-- a chord already armed (the indicator green from an earlier capture) and
-- a window left open, which is abandoned rather than finalized - and
-- turning Capture on while Shape or SATB is selected switches Harmony
-- Mode back to Off first, through Harmony Mode's own function. Each one
-- yields to the other exactly the way Break Time and the Arp do (see
-- onBreakTimeChange below).
--   Off   - the arp sees exactly the notes you hold, same as always. Play
--           a Cmaj7 yourself (C E G B) and the arp arpeggiates those four.
--   Shape - every key you strike is expanded, the moment it goes down,
--           into the selected Shape's full set of notes - NOT by
--           transposing the shape's semitone intervals onto the raw key,
--           but by snapping the key to the nearest tone of the current
--           Key/Scale/Mode and then stacking the shape's degrees (1st,
--           3rd, 5th, ...) from THAT scale position (see notesForKey(),
--           scaleStepOffset() and nearestScaleMatch() below). This means
--           the chord's quality follows the scale, not just its root: with
--           Key C / Scale Major / Shape "Seventh", striking C gives Cmaj7
--           (the I chord), but striking D gives Dm7, not Dmaj7 - D is the
--           2nd degree of C major, and the diatonic seventh chord on a
--           major scale's 2nd degree is minor, exactly as a chord built by
--           hand in that key would be. Changing Key or Scale only affects
--           the NEXT struck key, not one already sounding - unlike Shape or
--           Inversion changing (see regenerateShapeNotes()), nothing
--           re-reads Key/Scale for a note already in the pool. The arp
--           then arpeggiates the generated set, not the one key. See
--           addGeneratedNotes() and removeGeneratedNotes() below for how a
--           physical key's generated notes are tracked so releasing it
--           releases exactly what it added, even when two struck keys
--           generate an overlapping pitch between them.
--
-- Key/Scale is a quantizer shared by the arp and the degree numbers Shape
-- reads: every note the arp is about to send is snapped to the nearest
-- note of the chosen scale, rooted on Key, before it goes out - see
-- SCALE_OFFSETS and quantizeToScale() below. Scale "Chromatic" (the
-- default) allows every note, i.e. quantizes nothing.
--             (14, 15 and 17 are group labels added in the editor - not controls this script reads.)
--
-- Chord Capture - a separate, older tool, entirely independent of the arp
-- and of Shape: its own note tracking, its own output (not arpeggiated),
-- meant for trying a hand-played chord (an awkward Cmin7 voicing, say)
-- moved around the keyboard while editing a synth patch, not for feeding
-- the arp. It shares the arp's source/destination routing (3/4/5 and
-- 6/7/8) rather than carrying its own: 26 is its Capture toggle, 30 is its
-- Clear pad, 31 is the Chord Armed indicator (display only - the script
-- drives its colour; nothing reacts to it being pressed). It only ever
-- operates while Chord Mode is Off - see the guard at the top of
-- onChordKeyDown()/onChordKeyUp() below - since a struck key's own meaning
-- is already spoken for by Shape whenever Chord Mode is Shape.

local held = {}                      -- note -> velocity, the notes being arpeggiated
local pressOrder = {}                -- notes in the order pressed ("As Played")
local keysDown = {}                  -- note -> true, the keys physically held (for latch)
local noteRefCount = {}              -- generated note -> how many struck keys currently contribute it
local keyGeneratedNotes = {}         -- struck note -> { generated note numbers... } it added to `held`
local keyVelocity = {}               -- struck note -> the velocity it was struck with, for regenerating later
local stepIndex, direction = 0, 1
local currentNote = nil              -- the one note sounding on the destination
local gateHandle = nil               -- schedule.after handle for the gate-off
local swingParity = 0                -- 0 = on-beat step, 1 = off-beat step

-- Forward declared: isArpOn() is defined near the bottom (by the Arp
-- On/Off control's own section) but addGeneratedNotes()/removeGeneratedNotes()/
-- regenerateShapeNotes(), much higher up, need to call it to decide whether
-- a Shape-mode key should sound its generated chord directly (no arp
-- running to arpeggiate it) or just join the arp's held-notes pool (arp
-- running, current behaviour unchanged).
local isArpOn

-- Forward declared: finalizeCapture() is assigned down by onChordCapture
-- (which is where chordCaptureNotes is explained), but onChordModeChange,
-- above it in the file, needs to call it DIRECTLY rather than through
-- Capture's own control value - see the long comment at onChordModeChange
-- for why a nested setValue() will not do here.
local finalizeCapture

-- Forward declared the same way: clearChordCapture() is assigned down by
-- onChordClear (the CLR CHORD pad), and onChordModeChange calls it
-- directly for the same reason finalizeCapture is - selecting Shape wipes
-- the stored chord exactly as CLR CHORD would, rather than leaving a
-- chord captured under Off still armed (and the indicator still green)
-- once Shape has taken over what a struck key means.
local clearChordCapture

-- Chord Mode - its own note tracking, entirely separate from the arp's
-- pattern engine, but it shares the arp's own source/destination routing.
local chordHeld = {}                 -- note -> velocity, keys currently physically down
local chordPressOrder = {}           -- notes in the order pressed (for Last priority), most recent last
local chordActiveNote = nil          -- the physical key currently driving the sounding chord, or nil
local chordActiveSentNotes = {}      -- the generated note numbers currently sounding for chordActiveNote
local chordOffsets = nil             -- captured chord: array of semitone offsets from its root, or nil
local chordArmed = false             -- true once a chord has been captured
local chordCapturing = false         -- true while the Capture toggle is on
local chordCaptureNotes = {}         -- note -> velocity, every note played during this capture window

-- Note priority (ref 49): which physically-held key drives the sounding
-- chord when more than one is down at once. Last: whichever was struck
-- most recently (the usual mono-synth behaviour); Highest/Lowest: whichever
-- of the currently-held keys is pitched highest/lowest, regardless of
-- press order. Whichever key "wins" sounds the chord; the others are held
-- in reserve and take over, retriggering, if the winner is released while
-- they are still down - see activeChordNote() below.
local CHORD_PRIORITY_LAST, CHORD_PRIORITY_HIGHEST, CHORD_PRIORITY_LOWEST = 0, 1, 2

-- Pattern list, in the order the control shows them.
local PATTERN_UP        = 0
local PATTERN_DOWN      = 1
local PATTERN_ALT       = 2   -- bounces up/down, does not repeat the end notes
local PATTERN_ALT2      = 3   -- bounces up/down, repeats the end notes
local PATTERN_UP_8VE    = 4
local PATTERN_DOWN_8VE  = 5
local PATTERN_ALT_8VE   = 6
local PATTERN_ALT2_8VE  = 7
local PATTERN_STEP_UP   = 8
local PATTERN_STEP_DOWN = 9
local PATTERN_RANDOM    = 10
local PATTERN_RANDOM2   = 11  -- random, never the same note twice running
local PATTERN_RANDOM3   = 12  -- a shuffled permutation, reshuffled each pass
local PATTERN_ASPLAYED  = 13

-- Random3's state: a shuffled permutation of note indices, and where in it
-- the next step reads from. Rebuilt whenever it runs out or the note count
-- changes under it.
local shuffledOrder = nil
local shuffledPos = 1

local LATCH_OFF, LATCH_NORMAL, LATCH_CHORD = 0, 1, 2
local CHORD_MODE_OFF, CHORD_MODE_SHAPE, CHORD_MODE_SATB = 0, 1, 2

-- The controls that only make sense under one Harmony Mode or the other -
-- shown/hidden together by updateHarmonyParamVisibility() below, so the
-- grid only ever shows parameters the current mode actually reads.
-- Key/Scale Mode/Scale are NOT Shape-specific - they are the quantizer the
-- plain arp uses too (see the comment on quantizeToScale() above) AND the
-- degree numbers both Shape and SATB read, so they stay visible always,
-- regardless of Harmony Mode. Only Shape and Inversion are Shape-only.
local ALWAYS_VISIBLE_REFS = { 33, 27, 34 }       -- Key, Mode, Scale
local SHAPE_PARAM_REFS    = { 36, 40 }           -- Shape, Inversion
local SATB_PARAM_REFS     = { 50, 51, 52 }       -- Root Degree, Cantus Primus, Position

-- Beats (quarter notes) each step takes, indexed as the SYNC list's values.
-- Each is MIDI ticks / 24 (24 PPQN), from the published sync rate table -
-- slowest (8 beats) at index 0 down to fastest (32nd triplet) at index 18.
local syncRates = {
  [0]  = 192 / 24,  -- 8 beats     (1 cycle per 2 bars)
  [1]  = 144 / 24,  -- 6 beats     (1 cycle per 6 beats)
  [2]  = 128 / 24,  -- 5 + 1/3     (3 cycles per 4 bars)
  [3]  = 96 / 24,   -- 4 beats     (1 cycle per 1 bar)
  [4]  = 72 / 24,   -- 3 beats     (1 cycle per 3 beats)
  [5]  = 64 / 24,   -- 2 + 2/3     (3 cycles per 2 bars)
  [6]  = 48 / 24,   -- 2nd         (2 cycles per 1 bar)
  [7]  = 36 / 24,   -- 4th dotted  (2 cycles per 3 beats)
  [8]  = 32 / 24,   -- 1 + 1/3     (3 cycles per 1 bar)
  [9]  = 24 / 24,   -- 4th         (4 cycles per 1 bar)
  [10] = 18 / 24,   -- 8th dotted  (4 cycles per 3 beats)
  [11] = 16 / 24,   -- 4th triplet (6 cycles per 1 bar)
  [12] = 12 / 24,   -- 8th         (8 cycles per 1 bar)
  [13] = 9 / 24,    -- 16th dotted (8 cycles per 3 beats)
  [14] = 8 / 24,    -- 8th triplet (12 cycles per 1 bar)
  [15] = 6 / 24,    -- 16th        (16 cycles per 1 bar)
  [16] = 4 / 24,    -- 16th triplet (24 cycles per 1 bar)
  [17] = 3 / 24,    -- 32nd        (32 cycles per 1 bar)
  [18] = 2 / 24,    -- 32nd triplet (48 cycles per 1 bar)
}

-- The scales offered by Key/Scale, as semitone offsets from the root (Key).
-- Each set is exactly the degrees given in the published scale table.
-- Chromatic (index 0) is a full 12 - every note is already "in scale".
local SCALE_OFFSETS = {
  [0] = { 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11 },  -- Chromatic
  [1] = { 0, 2, 4, 5, 7, 9, 11 },                  -- Major
  [2] = { 0, 2, 3, 5, 7, 8, 10 },                  -- Natural Minor
  [3] = { 0, 2, 3, 5, 7, 8, 11 },                  -- Harmonic Minor
  [4] = { 0, 2, 4, 5, 7, 9, 10 },                  -- Dominant
  [5] = { 0, 2, 3, 5, 6, 8, 9, 11 },                -- Fully Diminished
  [6] = { 0, 1, 3, 4, 6, 7, 9, 10 },                -- Dominant Dim
  [7] = { 0, 3, 4, 7, 8, 11 },                      -- Augmented
  [8] = { 0, 2, 4, 6, 8, 10 },                      -- Whole Tone
}

-- The familiar mode names for the Major scale, indexed 0..6 to match the
-- Mode control's own raw value (a list: 0 Ionian .. 6 Locrian, shown to the
-- player as "1".."12"). Nothing is shown for another scale, or for a Mode
-- value beyond the scale's own note count - formatModeName() falls back to
-- the plain number (the label the control itself shows) in both cases.
local MAJOR_MODE_NAMES = {
  [0] = "Ionian",
  [1] = "Dorian",
  [2] = "Phrygian",
  [3] = "Lydian",
  [4] = "Mixolydian",
  [5] = "Aeolian",
  [6] = "Locrian",
}

-- Rotates a scale's interval pattern to start from its mode-th degree,
-- keeping the same root (Key) as offset 0 - this is what turns Major's
-- offsets into Dorian's, Phrygian's, etc, and does the equivalent rotation
-- for every other scale too. `mode` is the Mode control's own raw value,
-- 0-based, and wraps on the scale's own note count: mode 0 is always the
-- scale exactly as SCALE_OFFSETS declares it (Ionian, for Major).
--
-- Method: turn the offsets into their step sizes (the gaps between one
-- degree and the next, wrapping the last gap back to the octave), rotate
-- the step list to start at the chosen degree, then rebuild offsets from
-- that rotated step list, root back at 0.
local rotatedOffsetsCache = {}         -- "scale:mode" -> offsets, memoised

local function computeRotatedOffsets(scale, mode)
  local offsets = SCALE_OFFSETS[scale]
  if not offsets then return nil end

  local L = #offsets
  if L <= 1 then return offsets end

  local modeIndex = mode % L          -- 0-based degree this mode starts on
  if modeIndex == 0 then return offsets end  -- mode 0: unrotated, exactly as declared

  local key = scale .. ":" .. mode
  local cached = rotatedOffsetsCache[key]
  if cached then return cached end

  local steps = {}
  for i = 1, L - 1 do
    steps[i] = offsets[i + 1] - offsets[i]
  end
  steps[L] = 12 - offsets[L]           -- the gap back up to the root's octave

  local rotated = { 0 }
  local running = 0
  for i = 1, L - 1 do
    local step = steps[((modeIndex + i - 1) % L) + 1]
    running = running + step
    rotated[i + 1] = running
  end

  rotatedOffsetsCache[key] = rotated
  return rotated
end

-- The 14 chord shapes, in the order the Shape control lists them. Each
-- entry is a list of { degree, extraOctaves } pairs: `degree` is a 1-based
-- scale degree (1 is the root) read against whatever the current
-- Key/Scale/Mode's rotated offsets are, and `extraOctaves` is how many
-- further octaves to add on top of that degree's own octave - this is how
-- "1(8ve)" and "2(8ve)" in the shape table are expressed, rather than as a
-- literal semitone count, so every shape stays correct as Key/Scale/Mode
-- change under it.
local SHAPES = {
  [0]  = { { 1, 0 } },                                   -- None
  [1]  = { { 1, 0 }, { 1, 1 } },                          -- Octave
  [2]  = { { 1, 0 }, { 1, 1 }, { 1, 2 } },                 -- Two Octaves
  [3]  = { { 1, 0 }, { 5, 0 } },                          -- Root/Fifth
  [4]  = { { 1, 0 }, { 5, 0 }, { 1, 1 } },                 -- Root/Fifth + 8ve
  [5]  = { { 1, 0 }, { 3, 0 }, { 5, 0 } },                 -- Triad
  [6]  = { { 1, 0 }, { 3, 0 }, { 5, 0 }, { 1, 1 } },        -- Triad + 8ve
  [7]  = { { 1, 0 }, { 4, 0 }, { 5, 0 } },                 -- Sus4
  [8]  = { { 1, 0 }, { 4, 0 }, { 5, 0 }, { 1, 1 } },        -- Sus4 + 8ve
  [9]  = { { 1, 0 }, { 3, 0 }, { 5, 0 }, { 6, 0 } },        -- Sixth
  [10] = { { 1, 0 }, { 3, 0 }, { 5, 0 }, { 6, 0 }, { 1, 1 } }, -- Sixth + 8ve
  [11] = { { 1, 0 }, { 3, 0 }, { 5, 0 }, { 7, 0 } },        -- Seventh
  [12] = { { 1, 0 }, { 3, 0 }, { 5, 0 }, { 7, 0 }, { 1, 1 } }, -- Seventh + 8ve
  [13] = { { 1, 0 }, { 3, 0 }, { 5, 0 }, { 7, 0 }, { 2, 1 } }, -- Ninth
}

-- The semitone offset, counted from a root that is already sitting AT one
-- of this scale's own degrees, to the degree `steps` places above it (0 =
-- the root itself) - wrapping past the array's own length by adding whole
-- octaves, so a scale with 7 degrees (or 6, or 8 - SCALE_OFFSETS has scales
-- of several lengths) all stack correctly. `offsets` is a rotated-offsets
-- array (1-based, ascending, offsets[1] == 0); `startIndex0` is the
-- 0-based index of the root WITHIN that array - not a semitone count, a
-- degree count, which is what makes this diatonic: a Triad built on the
-- 2nd degree of a major scale comes out minor, not a transposed copy of
-- the Triad built on the 1st. See nearestScaleMatch() below for where
-- `startIndex0` comes from.
local function scaleStepOffset(offsets, startIndex0, steps)
  local L = #offsets
  local total = startIndex0 + steps
  local idx0 = total % L
  local octave = total // L
  return (offsets[idx0 + 1] + 12 * octave) - offsets[startIndex0 + 1]
end

-- A list control's display value is its 0-based index; toMidi() translates
-- that to the overlay item's actual labelled value (e.g. index 0 -> channel
-- 1). Use this only for list controls.
--
-- A NEGATIVE labelled value comes back wrapped as an unsigned 16-bit number
-- (seen on the Transpose Octave list: item value -2 reads back as 65534,
-- -1 as 65535) - the firmware stores an overlay item's value as uint16
-- regardless of what the project declares. Un-wrap it with the standard
-- two's-complement trick so a list is free to use negative item values.
local function cfgList(ref)
  local v = controls.get(ref):getValue()
  local raw = v:toMidi(v:getValue())
  if raw > 32767 then raw = raw - 65536 end
  return raw
end

-- A proportional control's display value already IS the number the script
-- wants (BPM, a percent, a semitone count, ...) - no translation needed.
-- Do NOT route this through toMidi(): the firmware clamps a message's min
-- to 0 even when the project declares a negative one (seen on Swing and
-- Transpose, both bipolar), so toMidi() on a fader with a negative range
-- silently returns the wrong, non-negative number. getValue() is unaffected
-- - it reads the control's own display range, which is stored correctly.
local function cfgValue(ref)
  return controls.get(ref):getValue():getValue()
end

-- Break Time/Direction (refs 43/44) - spreading a chord's notes out in time
-- instead of sounding them all at once. Read live, like every other config
-- value here - cfgValue(43)/cfgList(44) always reflect the current knob.
local BREAK_UP, BREAK_DOWN, BREAK_ALT = 0, 1, 2

-- The pitch order the break fires its notes in. Up: low to high. Down:
-- high to low. Alternating: outside-in, low/high/low/high.
local function orderForBreak(notes)
  local sorted = {}
  for i, n in ipairs(notes) do sorted[i] = n end
  table.sort(sorted)

  local dir = cfgList(44)
  if dir == BREAK_DOWN then
    local rev = {}
    for i = #sorted, 1, -1 do rev[#rev + 1] = sorted[i] end
    return rev
  elseif dir == BREAK_ALT then
    local alt = {}
    local lo, hi = 1, #sorted
    local takeLow = true
    while lo <= hi do
      if takeLow then
        alt[#alt + 1] = sorted[lo]
        lo = lo + 1
      else
        alt[#alt + 1] = sorted[hi]
        hi = hi - 1
      end
      takeLow = not takeLow
    end
    return alt
  end
  return sorted   -- BREAK_UP, the default
end

-- Sends `notes` spread across the current Break Time, ordered by Break
-- Direction - the first note at once, the last exactly Break Time ms
-- later - using midi.at() the same way a swung step is delayed
-- (swingDelayMs() above). `velocityFor(note)` gets each note's velocity.
-- Note-off is not broken: a release stops everything at once, since how a
-- chord already breaking should react to a mid-break release is still an
-- open design question (see the note by Break Time/Direction below).
local function sendBrokenNotes(notes, velocityFor, iface, port, chan)
  local breakMs = cfgValue(43)
  local ordered = orderForBreak(notes)
  local n = #ordered

  for i, note in ipairs(ordered) do
    local delay = (n > 1) and math.floor(breakMs * (i - 1) / (n - 1)) or 0
    if delay > 0 then
      midi.at(schedule.now() + delay)
      midi.sendNoteOn(iface, port, chan, note, velocityFor(note))
      midi.at()
    else
      midi.sendNoteOn(iface, port, chan, note, velocityFor(note))
    end
    if debugSentNotesHook then debugSentNotesHook(note) end
  end
end

-- Snaps `note` to the nearest note of the chosen scale, rooted on Key, and
-- says which of the scale's own degrees it landed on. If the note is
-- already in the scale, it is returned unchanged, at its own degree.
-- Otherwise the nearest scale degree is found by shortest distance around
-- the 12-note circle; a tie (exactly 6 semitones either way) rounds up.
-- For Chromatic, every semitone IS a degree (SCALE_OFFSETS[0] has all 12),
-- so this naturally snaps to nothing (shift 0) while still handing back a
-- degree index - notesForKey() below needs that index for every scale,
-- Chromatic included, to build a shape that stacks correctly from
-- wherever the struck key actually landed, not from Key's own position.
--
-- Returns: quantizedNote, degreeIndex0 (0-based, into `offsets`), offsets
-- (the rotated-offsets array itself, so a caller does not have to
-- recompute it).
local function nearestScaleMatch(note)
  local offsets = computeRotatedOffsets(cfgList(34), cfgList(27))
  if not offsets then return note, 0, { 0 } end  -- should not happen; every Scale value has an entry

  local key = cfgList(33)
  local rel = (note - key) % 12          -- note's position relative to Key, 0..11

  local bestShift, bestAbs, bestIdx0 = 0, 12, 0
  for i, degree in ipairs(offsets) do
    local up = (degree - rel) % 12       -- 0..11: semitones up to reach this degree
    local shift = up
    if shift > 6 then shift = shift - 12 end   -- range (-6,6]
    local a = math.abs(shift)
    if a < bestAbs or (a == bestAbs and shift > bestShift) then
      bestAbs = a
      bestShift = shift
      bestIdx0 = i - 1
    end
  end

  return note + bestShift, bestIdx0, offsets
end

local function quantizeToScale(note)
  return (nearestScaleMatch(note))
end

local function latchMode()
  return cfgList(9)
end

-- HOLD (ref 53, Chord Generator) - while on, a chord already sounding
-- directly (Shape/SATB with the arp off, or Chord Capture) keeps ringing
-- once the key that struck it is released, instead of stopping. It is
-- read live, like every other config value here. Hold and the arp cannot
-- run together - a struck key's release has nothing to do with the arp,
-- so the two compete for the same keystroke the same way Break Time and
-- the arp already do (see onBreakTimeChange/onArpToggle below).
local function holdActive()
  return controls.get(53):getValue():getValue() == 1
end

local function chordMode()
  return cfgList(37)
end

-- Shows only the parameter group the current Harmony Mode actually reads:
-- Off hides both the Shape params (Key/Mode/Scale/Shape/Inversion) and the
-- SATB params (Root Degree/Cantus Primus/Position); Shape shows its own
-- five and hides SATB's three; SATB shows its own three and hides Shape's
-- five. Called whenever Harmony Mode changes (onChordModeChange, and the
-- onChordCapture path that moves it to Off directly - see settleModeChange
-- and its callers) and once from preset.onReady() to match whatever
-- loaded.
local function updateHarmonyParamVisibility()
  local mode = chordMode()
  local showShape = (mode == CHORD_MODE_SHAPE)
  local showSatb = (mode == CHORD_MODE_SATB)

  for _, ref in ipairs(ALWAYS_VISIBLE_REFS) do
    controls.get(ref):setVisible(true)
  end
  for _, ref in ipairs(SHAPE_PARAM_REFS) do
    controls.get(ref):setVisible(showShape)
  end
  for _, ref in ipairs(SATB_PARAM_REFS) do
    controls.get(ref):setVisible(showSatb)
  end
end

-- What Chord Mode was a moment ago, so onChordModeChange() (whose own
-- control value has already changed by the time it runs, like every other
-- value function here) can tell whether the OLD mode left any notes
-- sounding directly that the new mode's cleanup needs to silence.
-- Synced from preset.onReady() and from the end of onChordModeChange()
-- itself.
local lastChordMode = CHORD_MODE_OFF

-- What a struck key turns into, as an array of note numbers. Off: just the
-- key itself. Shape: the selected shape's full chord, rooted on that key,
-- using the degrees of the current Key/Scale/Mode (the same machinery
-- quantizeToScale's rotation uses).
-- Inversion (Shape mode only, ref 40): rotates the shape's own notes rather
-- than transposing the chord. Inversion N takes the LOWEST N notes of the
-- shape, in pitch order, and moves each of them up an octave - so for a
-- Triad (root, 3rd, 5th: e.g. C E G), inversion 1 moves the root above the
-- 5th (E G C), inversion 2 moves the root and 3rd above it (G C E), and so
-- on. It wraps on the shape's own note count: a shape with only 3 notes
-- sees inversion 3 as a full cycle back to the root position (all three
-- notes raised an octave together is the same shape again), not a 4th kind
-- of voicing a triad does not have.
local function applyInversion(offsets, inversion)
  local sorted = {}
  for i, v in ipairs(offsets) do sorted[i] = v end
  table.sort(sorted)

  local n = #sorted
  if n == 0 then return sorted end

  local inv = inversion % n
  for i = 1, inv do
    sorted[i] = sorted[i] + 12
  end
  table.sort(sorted)
  return sorted
end

-- Snaps the struck key to the nearest scale tone FIRST, then builds the
-- shape by stacking scale degrees from there - not by adding flat semitone
-- intervals to the raw, possibly out-of-scale key. This is what keeps the
-- generated chord in key: striking C# with a Major-scale Triad plays the
-- same C-E-G (or D-F-A, if the tie rounds the other way) a diatonic player
-- would reach for, rather than a C#-F-G# shape carried over unchanged from
-- the key the Triad happens to look like in C major. See
-- scaleStepOffset()/nearestScaleMatch() above for the mechanics.
local function shapeNotesForKey(note)
  local rootNote, startIndex0, offsets = nearestScaleMatch(note)
  local shape = SHAPES[cfgList(36)] or SHAPES[0]

  local semitoneOffsets = {}
  for _, spec in ipairs(shape) do
    semitoneOffsets[#semitoneOffsets + 1] = scaleStepOffset(offsets, startIndex0, spec[1] - 1) + 12 * spec[2]
  end
  semitoneOffsets = applyInversion(semitoneOffsets, cfgList(40))

  local notes = {}
  for _, offset in ipairs(semitoneOffsets) do
    notes[#notes + 1] = math.floor(helpers.clamp(rootNote + offset, 0, 127))
  end
  return notes
end

-- SATB (common-practice four-part harmony). CANTUS_SOPRANO etc are
-- CANTUS PRIMUS's own raw values; POSITION_CLOSED/OPEN are POSITION's,
-- and POSITION_T1_1..T2_2 below (values 2..5) are the Tintinnabuli ones.
local CANTUS_SOPRANO, CANTUS_ALTO, CANTUS_TENOR, CANTUS_BASS = 0, 1, 2, 3
local POSITION_CLOSED, POSITION_OPEN = 0, 1
-- Tintinnabuli-style positions (after the technique developed by Arvo
-- Part): "+1"/"+2" is how many triad tones above the alto the soprano
-- sits (first or second position superior); "-1"/"-2" is how many below
-- it the tenor sits (first or second position inferior) - see
-- satbNotesForKey() below for how Soprano/Tenor are picked from these and
-- how the voices are permuted when Cantus Primus names a voice other
-- than Alto.
local POSITION_T1_1, POSITION_T2_1, POSITION_T1_2, POSITION_T2_2 = 2, 3, 4, 5

-- The chord whose ROOT DEGREE role is satisfied by the struck note. ROOT
-- DEGREE (I..VII, stored 0..6 like every other list in this script) does
-- NOT name one fixed chord every note gets forced onto - it names the
-- ROLE the struck note itself plays in whatever chord it is harmonizing:
-- I means the note is the chord's own root; III means it is the chord's
-- third (so the actual root sits two scale-steps below it); and so on.
-- This is what makes walking a scale produce a different chord quality
-- for every note, the same way Shape's Triad already does when the note
-- IS the root - striking D with ROOT DEGREE "I" gives D-F-A (ii, minor,
-- because D is the 2nd degree of C major), striking F gives F-A-C (IV,
-- major), and so on, each diatonically correct. ROOT DEGREE "III" shifts
-- every one of those down a third: striking C now harmonizes it as the
-- third of A-C-E (vi).
--
-- The struck note is snapped to its own nearest scale degree first -
-- nearestScaleMatch(), same as Shape - and `rootDegree0 = noteDegree0 -
-- roleSteps` finds which degree the ROOT sits on; from there the root's
-- own absolute pitch and the third/fifth above it follow exactly the way
-- notesForKey() builds Shape's Triad (rootNote + scaleStepOffset()).
--
-- Returns the exact pitch the cantus firmus voice should sing (the
-- snapped note, unchanged) and the chord's three pitch classes (0..11):
-- root, third, fifth.
local function satbChordForNote(note)
  local offsets = computeRotatedOffsets(cfgList(34), cfgList(27)) or { 0 }
  local scaleLen = #offsets

  local snappedNote, noteDegree0 = nearestScaleMatch(note)

  local roleSteps = cfgList(50)                       -- 0 for I, 2 for III, 4 for V, ...
  local rootDegree0 = (noteDegree0 - roleSteps) % scaleLen
  local rootNote = snappedNote - scaleStepOffset(offsets, rootDegree0, roleSteps)

  local root  = rootNote % 12
  local third = (rootNote + scaleStepOffset(offsets, rootDegree0, 2)) % 12
  local fifth = (rootNote + scaleStepOffset(offsets, rootDegree0, 4)) % 12

  return snappedNote, { root, third, fifth }
end

-- The nearest note of pitch class `pc` strictly below/above `note` - never
-- `note` itself, even when `note` already has that pitch class.
local function nearestChordToneBelow(note, pcs)
  local bestNote, bestDist = nil, 13
  for _, pc in ipairs(pcs) do
    local dist = (note - pc) % 12
    if dist == 0 then dist = 12 end
    if dist < bestDist then bestDist, bestNote = dist, note - dist end
  end
  return bestNote
end

local function nearestChordToneAbove(note, pcs)
  local bestNote, bestDist = nil, 13
  for _, pc in ipairs(pcs) do
    local dist = (pc - note) % 12
    if dist == 0 then dist = 12 end
    if dist < bestDist then bestDist, bestNote = dist, note + dist end
  end
  return bestNote
end

-- The chord tone `n` steps above/below `note` (n = 0, 1, 2, 3 ...), applying
-- nearestChordToneAbove()/Below() repeatedly. Because `note` is always
-- itself a chord tone here (every call site starts from a pitch class in
-- `pcs`), and the "nearest chord tone" relation between the (at most
-- three) pitch classes of a triad is simply each one's immediate neighbour
-- in cyclic pitch-class order, going up n steps and back down n steps (or
-- the reverse) always returns to the note you started from - which is
-- exactly the property satbClosedOrOpen() and satbTintinnabuli() below
-- rely on to place the struck note correctly however many steps away from
-- the chord's reference voice it is built.
local function nthChordToneAbove(note, pcs, n)
  local result = note
  for _ = 1, n do
    result = nearestChordToneAbove(result, pcs)
  end
  return result
end

local function nthChordToneBelow(note, pcs, n)
  local result = note
  for _ = 1, n do
    result = nearestChordToneBelow(result, pcs)
  end
  return result
end

-- Close position: Soprano sits on top, and each lower voice is the nearest
-- chord tone below the one above it - Alto 1 step below Soprano, Tenor 2
-- steps below, Bass 3 steps below (confirmed against the worked example:
-- Soprano C4(60) gives Alto G3(55), Tenor E3(52), Bass C3(48)).
--
-- Open position widens that same stack - Alto 2 steps below Soprano
-- (skipping a chord tone, so a 5th-or-wider gap opens up where Close had
-- roughly a 3rd), Tenor 4 steps below, Bass 6 steps below - rather than
-- Close's 1/2/3. This is a found equivalence, not a rephrasing: the
-- textbook Open recipe ("Alto takes Close's Tenor pitch; Tenor takes
-- Close's Alto pitch, dropped an octave; Bass drops an octave too if that
-- would put it above the new Tenor") and "double every step" produce
-- exactly the same four pitches for a Soprano-anchored chord - confirmed
-- against the same worked example Close uses: Soprano C4(60) gives Alto
-- G3(52), Tenor F2(43), Bass C2(36) either way - but only the doubled-step
-- version has an answer for every OTHER Cantus Primus too.
--
-- Generalized to every Cantus Primus the same way satbTintinnabuli() is:
-- the struck note (already exactly a chord tone, by construction of
-- satbChordForNote()) is the voice CANTUS PRIMUS names, so Soprano is
-- worked out as however many steps ABOVE the struck note the named voice
-- sits below Soprano in the stack (0 for Soprano itself, 1 for Alto, 2 for
-- Tenor, 3 for Bass, each then doubled for Open) - then Alto/Tenor/Bass
-- are built down from that Soprano exactly as always. Soprano Cantus
-- Primus needs no detour: the struck note already IS Soprano.
--
-- The textbook Open recipe is phrased in terms of fixed ROLES ("the
-- alto", "the tenor") and so, taken literally, always transforms whichever
-- pitch happens to be sitting in the Alto/Tenor/Bass slot - which is only
-- harmless when Cantus Primus is Soprano (untouched by the recipe) or,
-- by luck, Tenor (the recipe's new Alto is the old Tenor's pitch,
-- unchanged). For Alto or Bass it silently relocates the very note Cantus
-- Primus was supposed to anchor - found by a test case built to catch
-- exactly this ("the struck note is one of the four voices"). The
-- doubled-step construction avoids that: it is built from the struck note
-- outward in every case, the same principle satbTintinnabuli() already
-- uses, so the voice CANTUS PRIMUS names is always exactly the pitch that
-- was struck, never an octave or a step away from it.
local function satbClosedOrOpen(note, position)
  local pivotNote, pcs = satbChordForNote(note)

  local cantus = cfgList(51)
  local voiceIndexFromTop -- 0 Soprano, 1 Alto, 2 Tenor, 3 Bass
  if cantus == CANTUS_ALTO then
    voiceIndexFromTop = 1
  elseif cantus == CANTUS_TENOR then
    voiceIndexFromTop = 2
  elseif cantus == CANTUS_BASS then
    voiceIndexFromTop = 3
  else -- CANTUS_SOPRANO
    voiceIndexFromTop = 0
  end

  local step = (position == POSITION_OPEN) and 2 or 1

  local soprano = nthChordToneAbove(pivotNote, pcs, step * voiceIndexFromTop)
  local alto = nthChordToneBelow(soprano, pcs, step * 1)
  local tenor = nthChordToneBelow(soprano, pcs, step * 2)
  local bass = nthChordToneBelow(soprano, pcs, step * 3)

  return {
    math.floor(helpers.clamp(soprano, 0, 127)),
    math.floor(helpers.clamp(alto, 0, 127)),
    math.floor(helpers.clamp(tenor, 0, 127)),
    math.floor(helpers.clamp(bass, 0, 127)),
  }
end

-- Tintinnabuli positions (after the technique developed by Arvo Part),
-- POSITION values T-vce +1/-1 .. +2/-2: soprano is the first or second
-- triad tone above alto ("+1"/"+2"), tenor the first or second below
-- ("-1"/"-2"), and bass is always exactly an octave below alto.
--
-- The struck note (snapped to a chord tone by satbChordForNote(), so it
-- IS one of the triad's three pitch classes) is the voice CANTUS PRIMUS
-- names - not relabelled after the fact, but placed there by first working
-- out what ALTO must be for that to hold, then building the other three
-- voices from that alto exactly as when Cantus Primus is Alto itself.
-- Alto is Soprano's known distance below it, or Tenor's distance above it,
-- or (Bass) built the other way since bass is always alto - 12. Moving UP
-- by a position's step count and back DOWN the same count (or the
-- reverse) returns to the same note - see nthChordToneAbove/Below above -
-- which is what makes the struck note land exactly on the named voice
-- rather than merely close to it. Cantus Primus Alto needs no detour: the
-- struck note already IS alto.
local function satbTintinnabuli(note, position)
  local pivotNote, pcs = satbChordForNote(note)

  local sopranoSteps = (position == POSITION_T2_1 or position == POSITION_T2_2) and 2 or 1
  local tenorSteps   = (position == POSITION_T1_2 or position == POSITION_T2_2) and 2 or 1

  local cantus = cfgList(51)
  local altoNote
  if cantus == CANTUS_SOPRANO then
    altoNote = nthChordToneBelow(pivotNote, pcs, sopranoSteps)
  elseif cantus == CANTUS_TENOR then
    altoNote = nthChordToneAbove(pivotNote, pcs, tenorSteps)
  elseif cantus == CANTUS_BASS then
    altoNote = pivotNote + 12
  else -- CANTUS_ALTO
    altoNote = pivotNote
  end

  local bassNote = altoNote - 12
  local sopranoNote = nthChordToneAbove(altoNote, pcs, sopranoSteps)
  local tenorNote = nthChordToneBelow(altoNote, pcs, tenorSteps)

  return {
    math.floor(helpers.clamp(sopranoNote, 0, 127)),
    math.floor(helpers.clamp(altoNote, 0, 127)),
    math.floor(helpers.clamp(tenorNote, 0, 127)),
    math.floor(helpers.clamp(bassNote, 0, 127)),
  }
end

local function satbNotesForKey(note)
  local position = cfgList(52)
  if position == POSITION_CLOSED or position == POSITION_OPEN then
    return satbClosedOrOpen(note, position)
  end
  -- Any other POSITION value is one of the four Tintinnabuli settings -
  -- POSITION's declared range stops at 5, so there is nothing else.
  return satbTintinnabuli(note, position)
end

local function notesForKey(note)
  local mode = chordMode()
  if mode == CHORD_MODE_SATB then
    return satbNotesForKey(note)
  end
  if mode ~= CHORD_MODE_SHAPE then
    return { note }
  end
  return shapeNotesForKey(note)
end

local function srcMatches(midiInput, channel)
  return midiInput.interface == cfgList(3) and midiInput.port == cfgList(4) and channel == cfgList(5)
end

-- MIN NOTE / MAX NOTE (refs 60/61, Config page): restrict which incoming
-- notes the arp and Chord Capture ever see, for a keyboard split. Read
-- live, like every other config value here. If the player sets Min above
-- Max the two are swapped rather than treating it as an always-false
-- range.
local function noteInRange(note)
  local minNote = cfgList(60)
  local maxNote = cfgList(61)
  if minNote > maxNote then
    minNote, maxNote = maxNote, minNote
  end
  return note >= minNote and note <= maxNote
end

local function destRoute()
  return cfgList(6), cfgList(7), cfgList(8)
end

local function stopCurrent()
  if gateHandle then
    schedule.cancel(gateHandle)
    gateHandle = nil
  end
  if currentNote ~= nil then
    local iface, port, chan = destRoute()
    midi.sendNoteOff(iface, port, chan, currentNote, 0)
    currentNote = nil
  end
end

local function sortedNotes()
  local list = {}
  for note in pairs(held) do list[#list + 1] = note end
  table.sort(list)
  return list
end

local function pressNote(note, velocity)
  if held[note] == nil then pressOrder[#pressOrder + 1] = note end
  held[note] = velocity
end

local function releaseNote(note)
  if held[note] == nil then return end
  held[note] = nil
  for i = #pressOrder, 1, -1 do
    if pressOrder[i] == note then table.remove(pressOrder, i) end
  end
  if next(held) == nil then            -- last key up: silence, reset
    stopCurrent()
    stepIndex, direction = 0, 1
  end
end

-- Expands `note` per notesForKey() and adds every result to `held`,
-- crediting them to this physical key so releaseGeneratedNotes() can later
-- take back exactly what this key added - no more, no less, even when two
-- struck keys' shapes share a pitch between them (noteRefCount is how a
-- shared pitch outlives the first key that is released).
-- Whether a Shape- or SATB-mode key should sound its generated notes
-- ITSELF, right now, rather than only joining the arp's held-notes pool:
-- true whenever Harmony Mode is Shape or SATB and the arp is not running
-- to arpeggiate the pool for us. With the arp running this stays false and
-- behaviour is exactly as before - the generated notes just join `held`
-- and the arp steps them.
local function shouldSoundShapeDirectly()
  local mode = chordMode()
  return (mode == CHORD_MODE_SHAPE or mode == CHORD_MODE_SATB) and not isArpOn()
end

local function addGeneratedNotes(note, velocity)
  local notes = notesForKey(note)
  local direct = shouldSoundShapeDirectly()
  local iface, port, chan
  if direct then iface, port, chan = destRoute() end

  local newlySounding = {}
  for _, n in ipairs(notes) do
    local alreadySounding = noteRefCount[n] ~= nil
    noteRefCount[n] = (noteRefCount[n] or 0) + 1
    pressNote(n, velocity)
    if direct and not alreadySounding then
      newlySounding[#newlySounding + 1] = n
    end
  end

  if direct and #newlySounding > 0 then
    if cfgValue(43) > 0 then
      sendBrokenNotes(newlySounding, function() return velocity end, iface, port, chan)
    else
      for _, n in ipairs(newlySounding) do
        midi.sendNoteOn(iface, port, chan, n, velocity)
        if debugSentNotesHook then debugSentNotesHook(n) end
      end
    end
  end

  keyGeneratedNotes[note] = notes
  keyVelocity[note] = velocity
end

local function removeGeneratedNotes(note)
  local notes = keyGeneratedNotes[note]
  if not notes then return end
  keyGeneratedNotes[note] = nil
  keyVelocity[note] = nil

  local direct = shouldSoundShapeDirectly()
  local iface, port, chan
  if direct then iface, port, chan = destRoute() end

  for _, n in ipairs(notes) do
    local count = (noteRefCount[n] or 1) - 1
    if count <= 0 then
      noteRefCount[n] = nil
      releaseNote(n)
      if direct then
        midi.sendNoteOff(iface, port, chan, n, 0)
      end
    else
      noteRefCount[n] = count
    end
  end
end

-- Shape and Inversion are read once, at the moment a key goes down - unlike
-- Key/Scale/Mode, which quantizeToScale() reads fresh on every single step,
-- so a struck key's generated notes just sit in `held` as fixed pitches
-- until something re-reads them. Changing Shape or Inversion while notes
-- are already sounding calls this to catch every key currently contributing
-- generated notes (still physically down, or latched) up to the new
-- Shape/Inversion - recomputing each one's notes and diffing against what
-- it previously added, rather than silencing everything outright.
local function regenerateShapeNotes()
  local mode = chordMode()
  if mode ~= CHORD_MODE_SHAPE and mode ~= CHORD_MODE_SATB then return end

  local direct = shouldSoundShapeDirectly()
  local iface, port, chan
  if direct then iface, port, chan = destRoute() end

  for key, oldNotes in pairs(keyGeneratedNotes) do
    local newNotes = notesForKey(key)

    local oldSet, newSet = {}, {}
    for _, n in ipairs(oldNotes) do oldSet[n] = true end
    for _, n in ipairs(newNotes) do newSet[n] = true end

    for _, n in ipairs(oldNotes) do
      if not newSet[n] then
        local count = (noteRefCount[n] or 1) - 1
        if count <= 0 then
          noteRefCount[n] = nil
          releaseNote(n)
          if direct then
            midi.sendNoteOff(iface, port, chan, n, 0)
          end
        else
          noteRefCount[n] = count
        end
      end
    end

    local velocity = keyVelocity[key] or 100
    for _, n in ipairs(newNotes) do
      if not oldSet[n] then
        local alreadySounding = noteRefCount[n] ~= nil
        noteRefCount[n] = (noteRefCount[n] or 0) + 1
        pressNote(n, velocity)
        if direct and not alreadySounding then
          midi.sendNoteOn(iface, port, chan, n, velocity)
        end
      end
    end

    keyGeneratedNotes[key] = newNotes
  end
end

-- Shape and SATB both share Note Priority (ref 49) with Chord Capture: at
-- most ONE physically-held key contributes its generated chord to the
-- pool at a time - the "active" key, chosen the same way activeChordNote()
-- chooses for Chord Capture (Last/Highest/Lowest) - rather than every held
-- key's chord stacking together. Holding a second key while the first is
-- still down retriggers on it when it wins priority (Last always does;
-- Highest/Lowest only when it actually outranks what is already held);
-- releasing the active key falls back to whichever held key wins next,
-- adding ITS notes fresh (they were never added while it was losing the
-- competition). Off-mode (Harmony Mode Off) is untouched by any of this -
-- every held key still feeds the arp's pool simultaneously, which is the
-- ordinary arpeggiator behaviour and has nothing to do with priority.
local shapeHeld = {}                 -- note -> velocity, physically held keys while Harmony Mode is Shape or SATB
local shapePressOrder = {}           -- press order stack (for Last priority), most recent last
local shapeActiveKey = nil           -- the physical key currently contributing its generated notes, or nil

local function activeShapeNote()
  local priority = cfgList(49)

  if priority == CHORD_PRIORITY_HIGHEST or priority == CHORD_PRIORITY_LOWEST then
    local best = nil
    for n in pairs(shapeHeld) do
      if best == nil then
        best = n
      elseif priority == CHORD_PRIORITY_HIGHEST and n > best then
        best = n
      elseif priority == CHORD_PRIORITY_LOWEST and n < best then
        best = n
      end
    end
    return best
  end

  for i = #shapePressOrder, 1, -1 do
    if shapeHeld[shapePressOrder[i]] ~= nil then
      return shapePressOrder[i]
    end
  end
  return nil
end

local function onShapeKeyDown(note, velocity)
  shapeHeld[note] = velocity
  shapePressOrder[#shapePressOrder + 1] = note

  local winner = activeShapeNote()
  if winner ~= nil and winner ~= shapeActiveKey then
    if shapeActiveKey ~= nil then
      removeGeneratedNotes(shapeActiveKey)   -- retract the key that just lost priority
    end
    addGeneratedNotes(winner, shapeHeld[winner])
    shapeActiveKey = winner
  end
end

local function onShapeKeyUp(note)
  shapeHeld[note] = nil
  for i = #shapePressOrder, 1, -1 do
    if shapePressOrder[i] == note then table.remove(shapePressOrder, i) end
  end

  if note ~= shapeActiveKey then return end   -- some other held key already has priority; nothing changes

  -- HOLD on: leave the chord sounding and shapeActiveKey as it stands,
  -- exactly as if the key were still down - a key that then wins priority
  -- still takes over normally on its OWN press (onShapeKeyDown), and
  -- turning HOLD off with nothing held stops it (see onHoldChange).
  if holdActive() then return end

  -- Latch Off: a release really releases, same as ever.
  -- Latch Normal/Chord: its generated notes keep sounding, unchanged -
  -- only the "who is active" bookkeeping moves on, so a still-held key
  -- that was losing the competition can take over the slot and add ITS
  -- shape too (stacking with what is already latched).
  if latchMode() == LATCH_OFF then
    removeGeneratedNotes(note)
  end
  shapeActiveKey = nil

  local winner = activeShapeNote()
  if winner ~= nil then
    addGeneratedNotes(winner, shapeHeld[winner])
    shapeActiveKey = winner
  end
end

local function onKeyDown(note, velocity)
  local mode = latchMode()
  local wasAnyKeyDown = next(keysDown) ~= nil
  keysDown[note] = true

  -- Chord: a fresh gesture (nothing was physically down a moment ago)
  -- replaces whatever was latched. Several keys pressed together still
  -- build one chord, since wasAnyKeyDown is true for the 2nd key onward.
  -- Normal: never clears here - a new note always adds to what is playing.
  if mode == LATCH_CHORD and not wasAnyKeyDown then
    -- Whatever the previous chord was sounding directly (Shape, arp off)
    -- must stop here too - this wipes noteRefCount without going through
    -- removeGeneratedNotes, which is the only other place that sends the
    -- matching note-off.
    if shouldSoundShapeDirectly() then
      local iface, port, chan = destRoute()
      for n in pairs(noteRefCount) do
        midi.sendNoteOff(iface, port, chan, n, 0)
      end
    end
    held, pressOrder, noteRefCount, keyGeneratedNotes = {}, {}, {}, {}
    shapeHeld, shapePressOrder, shapeActiveKey = {}, {}, nil
  end

  local mode = chordMode()
  if mode == CHORD_MODE_SHAPE or mode == CHORD_MODE_SATB then
    onShapeKeyDown(note, velocity)
  else
    addGeneratedNotes(note, velocity)
  end
end

local function onKeyUp(note)
  keysDown[note] = nil
  local mode = chordMode()
  if mode == CHORD_MODE_SHAPE or mode == CHORD_MODE_SATB then
    onShapeKeyUp(note)
  elseif latchMode() == LATCH_OFF then
    -- Off: a release really releases. Normal and Chord both latch - the
    -- generated notes keep sounding until something explicitly clears them
    -- (a fresh Chord gesture, or Latch going back to Off).
    removeGeneratedNotes(note)
  end
end

-- Chord Mode. Turn Capture on, play the chord shape - on one hand, two
-- hands, one finger at a time, released and re-pressed, however it takes -
-- then turn Capture off: every distinct note struck while it was on becomes
-- the stored chord, the lowest of them its root, every note's offset from
-- that root kept. From then on, striking a key plays the whole stored
-- chord transposed so its root lands on that key - using that key's own
-- velocity for every generated note. It listens on the arp's own source
-- and plays through the arp's own destination (srcMatches()/destRoute()
-- above) rather than carrying a route of its own.
--
-- Nothing sounds while Capture is on - it is a recording gesture, not a
-- performance - and nothing sounds before a chord has ever been captured
-- either, since sharing the arp's input means every note the arp sees,
-- Chord Mode sees too, and passing it through again would double it on the
-- wire.
--
-- Only ONE chord sounds at a time - whichever physically-held key wins
-- Note Priority (ref 49, see above). Holding a second key while the first
-- is down retriggers on the new key when it takes priority (Last always
-- does; Highest/Lowest only when the new key actually out-ranks what is
-- already held); releasing the key that currently has priority falls back
-- to whichever held key wins next, retriggering that one, rather than
-- going silent while other keys are still down.
local function stopAllChordNotes()
  local iface, port, chan = destRoute()
  for _, n in ipairs(chordActiveSentNotes) do
    midi.sendNoteOff(iface, port, chan, n, 0)
  end
  chordActiveNote = nil
  chordActiveSentNotes = {}
end

-- Which physically-held key should be driving the chord right now, under
-- the current Note Priority. `nil` when nothing is held.
local function activeChordNote()
  local priority = cfgList(49)

  if priority == CHORD_PRIORITY_HIGHEST or priority == CHORD_PRIORITY_LOWEST then
    local best = nil
    for n in pairs(chordHeld) do
      if best == nil then
        best = n
      elseif priority == CHORD_PRIORITY_HIGHEST and n > best then
        best = n
      elseif priority == CHORD_PRIORITY_LOWEST and n < best then
        best = n
      end
    end
    return best
  end

  -- Last (the default): whichever is nearest the end of the press stack
  -- and still actually held - a key that was pressed after the winner but
  -- has since been released does not count.
  for i = #chordPressOrder, 1, -1 do
    if chordHeld[chordPressOrder[i]] ~= nil then
      return chordPressOrder[i]
    end
  end
  return nil
end

-- Sounds the stored chord rooted on `note`, replacing whatever was
-- sounding before. Does nothing (and does not touch what is already
-- sounding) when no chord has been captured yet.
--
-- Deliberately NOT run through quantizeToScale(): Chord Capture's whole
-- point (see the long comment above) is reproducing a hand-played chord
-- exactly - "an awkward Cmin7 voicing" is the example given there - and
-- snapping its intervals to Key/Scale on every replay would quietly turn
-- a minor third into a major one, or whatever else the scale disagreed
-- with, the moment the chord was struck on a different root. That is
-- Shape mode's job (it reads degrees FROM the scale on purpose); Chord
-- Capture only transposes the exact semitone offsets it captured.
local function triggerChord(note)
  if not (chordArmed and chordOffsets) then return end

  stopAllChordNotes()

  local velocity = chordHeld[note] or 100
  local iface, port, chan = destRoute()
  local sent = {}
  for _, offset in ipairs(chordOffsets) do
    local n = math.floor(helpers.clamp(note + offset, 0, 127))
    sent[#sent + 1] = n
  end

  if cfgValue(43) > 0 then
    sendBrokenNotes(sent, function() return velocity end, iface, port, chan)
  else
    for _, n in ipairs(sent) do
      midi.sendNoteOn(iface, port, chan, n, velocity)
      if debugSentNotesHook then debugSentNotesHook(n) end
    end
  end

  chordActiveNote = note
  chordActiveSentNotes = sent
end

-- The Chord Armed pad is purely a display: grey when no chord is stored,
-- green once one is. It does nothing when pressed - only chordArmed
-- changing moves it, from the places that change chordArmed.
local function updateChordArmedIndicator()
  controls.get(31):setColor(chordArmed and GREEN or 0x606060)
end

-- Chord Capture only operates while Chord Mode is Off - a struck key's
-- meaning is already spoken for by Shape otherwise, and there is nothing
-- useful left for Capture to record or trigger.
local function onChordKeyDown(note, velocity)
  if chordMode() ~= CHORD_MODE_OFF then return end

  chordHeld[note] = velocity
  chordPressOrder[#chordPressOrder + 1] = note

  if chordCapturing then
    chordCaptureNotes[note] = velocity   -- recorded even if released before Capture goes off
    return                               -- silent while actively capturing
  end

  local winner = activeChordNote()
  if winner ~= nil and winner ~= chordActiveNote then
    triggerChord(winner)
  end
end

local function onChordKeyUp(note)
  if chordMode() ~= CHORD_MODE_OFF then return end

  chordHeld[note] = nil
  for i = #chordPressOrder, 1, -1 do
    if chordPressOrder[i] == note then table.remove(chordPressOrder, i) end
  end
  -- Note: chordCaptureNotes is untouched here - a note released mid-capture
  -- still counts towards the chord once Capture goes off.

  if note ~= chordActiveNote then return end   -- some other held key still has priority; nothing changes

  -- HOLD on: leave the chord sounding and chordActiveNote as it stands,
  -- exactly as if the key were still down - a later key press still
  -- retriggers normally (its winner differs from chordActiveNote), and
  -- turning HOLD off with nothing held stops it (see onHoldChange).
  if holdActive() then return end

  stopAllChordNotes()
  local winner = activeChordNote()
  if winner ~= nil then
    triggerChord(winner)
  end
end

-- Note Priority changing with keys currently down re-evaluates who should
-- be sounding right now, same as onChordKeyDown/Up - without this, picking
-- Highest while a lower key happens to be the one sounding would leave it
-- sounding until the next physical key event. Shared between Chord Capture
-- (Chord Mode Off) and Shape (Chord Mode Shape) - only one of the two is
-- ever live at once, gated by chordMode(), same as everywhere else.
function onChordPriorityChange(valueObject, value)
  if chordMode() == CHORD_MODE_OFF then
    if next(chordHeld) == nil then return end
    local winner = activeChordNote()
    if winner ~= nil and winner ~= chordActiveNote then
      triggerChord(winner)
    end
  elseif chordMode() == CHORD_MODE_SHAPE or chordMode() == CHORD_MODE_SATB then
    if next(shapeHeld) == nil then return end
    local winner = activeShapeNote()
    if winner ~= nil and winner ~= shapeActiveKey then
      if shapeActiveKey ~= nil then
        removeGeneratedNotes(shapeActiveKey)
      end
      addGeneratedNotes(winner, shapeHeld[winner])
      shapeActiveKey = winner
    end
  end
end

-- Whether a pattern is one of the "-8ve" variants, which skip the duplicate
-- note at an octave-repeat seam rather than playing it twice running - see
-- orderedNotes() below.
local function patternSkipsOctaveSeams(pattern)
  return pattern == PATTERN_UP_8VE or pattern == PATTERN_DOWN_8VE
    or pattern == PATTERN_ALT_8VE or pattern == PATTERN_ALT2_8VE
end

-- The base note list, expanded across the chosen number of octaves.
-- Each entry is { note = <midi note>, velocity = <original velocity> } so an
-- octave-shifted step still plays with the velocity of the key that was held.
--
-- When the held notes themselves already span a full octave (the top note
-- is exactly the bottom note plus 12), repeating the whole group a further
-- octave up lands that same pitch twice in a row, at the seam between one
-- repetition and the next. The plain patterns play that duplicate - it is
-- just another step. The "-8ve" patterns skip it, via `skipSeams`.
local function orderedNotes(skipSeams)
  local pattern = cfgList(2)
  local base
  if pattern == PATTERN_ASPLAYED then
    base = pressOrder
  else
    base = sortedNotes()
  end

  local octaves = cfgList(10)
  local list = {}

  for oct = 0, octaves - 1 do
    for _, n in ipairs(base) do
      local note = n + oct * 12
      if skipSeams and #list > 0 and list[#list].note == note then
        -- the same pitch as the step just added: a seam duplicate, skipped
      else
        list[#list + 1] = { note = note, velocity = held[n] or 100 }
      end
    end
  end

  return list
end

-- An up/down path where the lowest and highest notes are each played twice
-- (once on the way past, once again before turning round), instead of the
-- plain Up/Down's single pass at each end.
local function buildUpDownRepeatSequence(notes)
  local n = #notes
  if n == 0 then return {} end
  if n == 1 then return { notes[1], notes[1] } end

  local seq = { notes[1], notes[1] }
  for i = 2, n - 1 do seq[#seq + 1] = notes[i] end
  seq[#seq + 1] = notes[n]
  seq[#seq + 1] = notes[n]
  for i = n - 1, 2, -1 do seq[#seq + 1] = notes[i] end
  return seq
end

-- The fixed step period (ms), from the current tempo and sync rate only.
-- Swing never touches this: the timer always ticks on an even grid, so
-- setPeriod() is called only when the tempo or sync rate actually change,
-- never once per step - its no-drift guarantee stays intact and a tick's own
-- run time is never added back into the schedule.
local function basePeriodMs()
  local bpm = cfgValue(1)
  local beatsPerStep = syncRates[cfgList(13)] or 0.25
  return (60000 / bpm) * beatsPerStep
end

-- Swing is bipolar, -80..+80%, centred on 0. It shifts the gap between an
-- even (off-beat) step and the odd (on-beat) step right before it:
--   negative -> that gap shortens (the even step effectively arrives sooner)
--   positive -> that gap lengthens (the even step arrives later)
--   zero     -> no effect
--
-- The timer's grid is never touched (see basePeriodMs() above). Instead,
-- exactly one of the two steps in a pair is delayed with midi.at(), and
-- which one depends on the sign:
--   positive swing delays the even step itself, pushing it later and so
--     widening the odd -> even gap, exactly as before;
--   negative swing delays the *preceding* odd step instead. Moving the odd
--     step later, towards the even step that follows it at its fixed time,
--     narrows the very same gap - without ever sending a message "in the
--     past", which a direct negative delay on the even step would require.
-- Both delays are measured from the step's own nominal tick, so neither
-- needs to look ahead to the next one.
local function swingDelayMs()
  local swing = math.abs(cfgValue(12)) / 100   -- 0..0.8
  return math.floor(basePeriodMs() * swing / 3)
end

local function stepIsDelayedBySwing(isOffBeat)
  local swing = cfgValue(12)
  if swing > 0 then return isOffBeat end
  if swing < 0 then return not isOffBeat end
  return false
end

local function advanceStep(isOffBeat)
  stopCurrent()                        -- one note at a time, right now
  local pattern = cfgList(2)
  local notes = orderedNotes(patternSkipsOctaveSeams(pattern))
  local n = #notes
  if n == 0 then return end

  local entry

  if pattern == PATTERN_UP or pattern == PATTERN_UP_8VE or pattern == PATTERN_ASPLAYED then
    stepIndex = (stepIndex % n) + 1
    entry = notes[stepIndex]

  elseif pattern == PATTERN_DOWN or pattern == PATTERN_DOWN_8VE then
    stepIndex = (stepIndex % n) + 1
    entry = notes[n - stepIndex + 1]

  elseif pattern == PATTERN_ALT or pattern == PATTERN_ALT_8VE then
    if n == 1 then
      stepIndex = 1
    else
      stepIndex = stepIndex + direction
      if stepIndex >= n then
        stepIndex = n
        direction = -1
      elseif stepIndex <= 1 then
        stepIndex = 1
        direction = 1
      end
    end
    entry = notes[stepIndex]

  elseif pattern == PATTERN_ALT2 or pattern == PATTERN_ALT2_8VE then
    local seq = buildUpDownRepeatSequence(notes)
    local sn = #seq
    if sn == 0 then
      entry = nil
    else
      stepIndex = (stepIndex % sn) + 1
      entry = seq[stepIndex]
    end

  elseif pattern == PATTERN_STEP_UP then
    -- The lowest note alternates with the rest, rising: C E C G C ...
    if n == 1 then
      entry = notes[1]
    else
      local cycle = 2 * (n - 1)
      stepIndex = (stepIndex % cycle) + 1
      if stepIndex % 2 == 1 then
        entry = notes[1]
      else
        entry = notes[1 + (stepIndex // 2)]
      end
    end

  elseif pattern == PATTERN_STEP_DOWN then
    -- The highest note alternates with the rest, falling: G E G C G ...
    if n == 1 then
      entry = notes[1]
    else
      local cycle = 2 * (n - 1)
      stepIndex = (stepIndex % cycle) + 1
      if stepIndex % 2 == 1 then
        entry = notes[n]
      else
        entry = notes[n - (stepIndex // 2)]
      end
    end

  elseif pattern == PATTERN_RANDOM then
    stepIndex = math.random(1, n)
    entry = notes[stepIndex]

  elseif pattern == PATTERN_RANDOM2 then
    -- Never the same note twice running - reroll on a repeat, unless there
    -- is only the one note and a repeat is all there is.
    if n == 1 then
      entry = notes[1]
    else
      local pick
      repeat
        pick = math.random(1, n)
      until pick ~= stepIndex
      stepIndex = pick
      entry = notes[stepIndex]
    end

  elseif pattern == PATTERN_RANDOM3 then
    -- A shuffled permutation of every note, then a fresh shuffle for the
    -- next pass - never two passes alike, but every note once per pass.
    if (not shuffledOrder) or (#shuffledOrder ~= n) or (shuffledPos > #shuffledOrder) then
      shuffledOrder = {}
      for i = 1, n do shuffledOrder[i] = i end
      for i = n, 2, -1 do
        local j = math.random(1, i)
        shuffledOrder[i], shuffledOrder[j] = shuffledOrder[j], shuffledOrder[i]
      end
      shuffledPos = 1
    end
    entry = notes[shuffledOrder[shuffledPos]]
    shuffledPos = shuffledPos + 1

  else
    stepIndex = (stepIndex % n) + 1
    entry = notes[stepIndex]
  end

  if entry then
    -- ArpChance: each step has this percent chance of actually sounding.
    -- The sequence still advances either way - a skipped step is a rest,
    -- not a repeat of the same step next time.
    local chancePercent = cfgValue(16)
    if chancePercent < 100 and math.random(1, 100) > chancePercent then
      return
    end

    -- Transpose: up to 2 octaves (a list - a dial has too few steps to land
    -- on accurately) and up to 12 semitones, both bipolar and applied
    -- together, on top of whatever the pattern/octave engine picked. Then
    -- Key/Scale snaps the result to the chosen scale before it is clamped
    -- and sent.
    local transposed = entry.note + (cfgList(18) * 12) + cfgValue(19)
    local note = math.floor(helpers.clamp(quantizeToScale(transposed), 0, 127))
    local iface, port, chan = destRoute()

    -- Swing delays exactly one step per pair, chosen by the sign - see
    -- stepIsDelayedBySwing() above. The timer's own period is never touched.
    local delay = stepIsDelayedBySwing(isOffBeat) and swingDelayMs() or 0
    if delay > 0 then
      midi.at(schedule.now() + delay)
    end
    midi.sendNoteOn(iface, port, chan, note, entry.velocity or 100)
    midi.at()                          -- back to sending at once
    currentNote = note
    if debugSentNotesHook then debugSentNotesHook(note) end

    local gatePercent = cfgValue(11)
    if gatePercent < 100 then
      -- Measured from now, so it still includes the swing delay above.
      local gateMs = delay + math.floor(basePeriodMs() * gatePercent / 100)
      local noteForGate = note
      gateHandle = schedule.after(gateMs, function()
        if currentNote == noteForGate then
          stopCurrent()
        end
      end)
    end
  end
end

-- An external momentary/latching MIDI switch can drive Arp On/Off, Chord
-- Capture and HOLD directly, on its own CC numbers and its own routing -
-- refs 45/46/47 (Switch Interface/Port/Channel, Config page) - separate
-- from the arp's own source routing (3/4/5), since a footswitch is
-- commonly on a different port (USB Host, say) from the keyboard/synth
-- sending notes, and the two should be free to differ. CC 126 toggles Arp
-- On/Off (ref 29); CC 127 toggles Chord Capture (ref 26); CC 125 toggles
-- HOLD (ref 53) - all standard on/off switch CCs, 0 = off, 127 = on
-- (>=64 counts as on, so a switch that is not perfectly 0/127 still
-- works). setValue() (not updateValue()) is used deliberately: it runs
-- the control's own function (onArpToggle/onChordCapture/onHoldChange)
-- exactly as pressing the pad by hand would, so every existing on/off
-- side effect (silencing notes, starting/stopping the timer, opening/
-- closing the capture window) happens the same way regardless of what
-- triggered it.
local EXTERNAL_ARP_CC = 126
local EXTERNAL_CAPTURE_CC = 127
local EXTERNAL_HOLD_CC = 125

local function switchRoute()
  return cfgList(45), cfgList(46), cfgList(47)
end

-- Nothing needs to react live to the Switch Interface/Port/Channel
-- controls changing - switchRoute() above reads them fresh on every
-- incoming CC, the same way srcMatches()/destRoute() already do for the
-- arp's own routing. The function exists only because every control here
-- is declared with one (recipe 33.14).
function onSwitchRouteChange(valueObject, value)
end

-- MIN NOTE / MAX NOTE: nothing needs to react live either - noteInRange()
-- above reads both fresh on every incoming note. The functions exist only
-- because every control here is declared with one.
function onMinNoteChange(valueObject, value)
end

function onMaxNoteChange(valueObject, value)
end

-- SATB (refs 50/51/52) - ROOT DEGREE, CANTUS PRIMUS, POSITION. Each
-- changes what satbNotesForKey() builds, so - exactly like Shape and
-- Inversion above - a chord already sounding is brought up to date rather
-- than left stale until the key is re-struck.
function onRootDegreeChange(valueObject, value)
  regenerateShapeNotes()
end

function onCantusPrimusChange(valueObject, value)
  regenerateShapeNotes()
end

function onPositionChange(valueObject, value)
  regenerateShapeNotes()
end

function midi.onControlChange(midiInput, channel, controllerNumber, value)
  local iface, port, chan = switchRoute()
  if midiInput.interface ~= iface or midiInput.port ~= port or channel ~= chan then return end

  if controllerNumber == EXTERNAL_ARP_CC then
    controls.get(29):getValue():setValue(value >= 64 and 1 or 0)
  elseif controllerNumber == EXTERNAL_CAPTURE_CC then
    controls.get(26):getValue():setValue(value >= 64 and 1 or 0)
  elseif controllerNumber == EXTERNAL_HOLD_CC then
    controls.get(53):getValue():setValue(value >= 64 and 1 or 0)
  end
end

function midi.onNoteOn(midiInput, channel, noteNumber, velocity)
  if not srcMatches(midiInput, channel) then return end
  if not noteInRange(noteNumber) then return end

  if velocity == 0 then
    onKeyUp(noteNumber)
    onChordKeyUp(noteNumber)
  else
    onKeyDown(noteNumber, velocity)
    onChordKeyDown(noteNumber, velocity)
  end
end

function midi.onNoteOff(midiInput, channel, noteNumber, velocity)
  if not srcMatches(midiInput, channel) then return end
  if not noteInRange(noteNumber) then return end
  onKeyUp(noteNumber)
  onChordKeyUp(noteNumber)
end

function timer.onTick(ticks)
  -- A tick can stand for several missed periods; walk the counter - and the
  -- swing parity - over them, but sound only the step that is due now. The
  -- timer's own period is never touched here.
  for _ = 2, ticks do
    local pattern = cfgList(2)
    local n = #orderedNotes(patternSkipsOctaveSeams(pattern))
    if n > 0 then stepIndex = (stepIndex % n) + 1 end
    swingParity = (swingParity + 1) % 2
  end

  advanceStep(swingParity == 1)
  swingParity = (swingParity + 1) % 2
end

function onTempoChange(valueObject, value)
  timer.setPeriod(basePeriodMs())
end

function formatBpm(valueObject, value)
  return value .. " BPM"
end

function formatPercent(valueObject, value)
  return value .. " %"
end

function formatSwing(valueObject, value)
  if value > 0 then return "+" .. value .. " %" end
  return value .. " %"
end

function formatBreakTime(valueObject, value)
  return value .. " ms"
end

-- Break Time/Direction (refs 43/44) are for the "broken chord" feature:
-- spreading a Shape-mode or Chord-Capture chord's notes out in time
-- instead of sounding them all at once, since either one is generated
-- instantly from a single keystroke. See sendBrokenNotes()/orderForBreak()
-- above for the engine: when Break Time is above 0, a chord's notes fire
-- one by one, ordered by Break Direction (Up/Down/Alternating), spread
-- evenly so the first sounds at once and the last exactly Break Time ms
-- later. Note-off is NOT broken - a release (or a fresh trigger replacing
-- the chord) stops every sounding note at once, which is the simplest
-- answer to "how does a chord already breaking react to a mid-break
-- release" and the one open question this round settles by not trying to
-- be clever about it. Latch interaction is otherwise unaffected: Break
-- plugs into the same two note-producing places (addGeneratedNotes() for
-- Shape mode sounding directly, triggerChord() for Chord Capture) and
-- changes nothing about when those places are called.
--
-- Break and the ARP still cannot run together, because they are two
-- different engines competing for the same single keystroke:
--
--   Break Time raised above 0 while the arp is on turns the arp off.
--   The arp turned on while Break Time is above 0 sets Break Time to 0.
--
-- Each direction sets the OTHER control via setValue() (not updateValue()),
-- so it runs through that control's own function and every normal
-- on/off side effect (silencing notes, stopping the timer) exactly as if
-- the player had reached for that control directly - and each guards on
-- the condition that would otherwise fire it again, so the two functions
-- do not recurse into each other.
function onBreakTimeChange(valueObject, value)
  if value > 0 and isArpOn() then
    controls.get(29):getValue():setValue(0)   -- Arp: off, Break Time has the keystroke now
  end
end

function onBreakDirectionChange(valueObject, value)
end

function formatTransposeSemi(valueObject, value)
  if value > 0 then return "+" .. value .. " st" end
  if value < 0 then return value .. " st" end
  return "0 st"
end

function onPatternChange(valueObject, value)
  stepIndex, direction = 0, 1
  shuffledOrder, shuffledPos = nil, 1
end

function onOctavesChange(valueObject, value)
  stepIndex, direction = 0, 1
  shuffledOrder, shuffledPos = nil, 1
end

function onGateChange(valueObject, value)
end

function onChanceChange(valueObject, value)
end

function onTransposeOctaveChange(valueObject, value)
end

-- The Mode control's own cached display text only recomputes when Mode's
-- OWN value changes (value:getText() is composed "the last time the value
-- changed" - see ControlValue in the reference - and Scale changing is a
-- different control, so it never retriggers Mode's formatter). Measured on
-- the instrument: selecting Major after Mode was already showing "4" left
-- it reading "4" forever, never "Lydian", until Mode itself was turned.
-- setOverride() sidesteps the stale cache outright - it is drawn as given,
-- not derived from anything cached - so every call here recomputes the
-- full text itself rather than leaning on formatModeName's own cache.
local function refreshModeDisplay()
  local scale = cfgList(34)
  local mode = cfgList(27)
  local text = (scale == 1) and MAJOR_MODE_NAMES[mode] or nil
  controls.get(27):setOverride(text or tostring(mode + 1))
end

function onScaleChange(valueObject, value)
  refreshModeDisplay()
end

function onModeChange(valueObject, value)
  refreshModeDisplay()
end

-- Shape changes the notes a struck key generates, so anything already
-- sounding from an earlier Shape is brought up to date rather than left
-- stale until the key is re-struck - see regenerateShapeNotes() above.
function onShapeChange(valueObject, value)
  regenerateShapeNotes()
end

-- Inversion, the same way: it rearranges the shape's own notes, so a chord
-- already sounding is updated live too.
function onInversionChange(valueObject, value)
  regenerateShapeNotes()
end

-- Shared between onChordModeChange (an ordinary switch) and onChordCapture
-- (Capture turning on while Shape is selected, which switches the mode
-- back to Off as a side effect): everything a mode change needs to settle
-- EXCEPT Chord Capture's own chordCapturing/chordCaptureNotes - those are
-- deliberately left to the caller. onChordModeChange always resets them
-- (an ordinary switch should drop a stray capture), but onChordCapture is
-- switching the mode in order to START a capture, and must not have that
-- capture wiped out a moment later by the same cleanup that switching the
-- mode would otherwise do unconditionally - see onChordCapture below for
-- how this bit the first version of this coupling.
local function settleModeChange()
  -- Anything the OLD mode was sounding directly (Shape, arp off) must be
  -- silenced before the tables that remember it are wiped below. chordMode()
  -- would read the NEW value already (this control's own value has already
  -- changed by the time its function runs, like every other value function
  -- here) so the OLD one is read from lastChordMode instead.
  if (lastChordMode == CHORD_MODE_SHAPE or lastChordMode == CHORD_MODE_SATB) and not isArpOn() then
    local iface, port, chan = destRoute()
    for n in pairs(noteRefCount) do
      midi.sendNoteOff(iface, port, chan, n, 0)
    end
  end

  stopCurrent()
  held, pressOrder, keysDown, noteRefCount, keyGeneratedNotes, keyVelocity = {}, {}, {}, {}, {}, {}
  shapeHeld, shapePressOrder, shapeActiveKey = {}, {}, nil
  stepIndex, direction = 0, 1

  stopAllChordNotes()
  chordHeld, chordPressOrder = {}, {}
end

-- Chord Mode decides what a struck key means, so switching it silences
-- everything outright rather than leaving the old meaning's notes stuck
-- sounding under the new one - both the arp's own held notes and whatever
-- Chord Capture had going (which also stops reacting entirely once this is
-- Shape; see the guard at the top of onChordKeyDown()/onChordKeyUp()).
function onChordModeChange(valueObject, value)
  -- Chord Capture and Shape/SATB are alternative chord-to-key mappings and
  -- cannot both be live: switching TO either clears Chord Capture outright,
  -- exactly as pressing CLR CHORD would - any chord already armed (the
  -- indicator showing green) is dropped, not left standing under a mode
  -- that no longer reads a struck key that way, and a capture window left
  -- open is abandoned rather than finalized. This calls clearChordCapture()
  -- DIRECTLY rather than going through CLR CHORD's own control value: a
  -- nested setValue() made from inside another value's own function is
  -- not run inline here - it is only applied once this whole function
  -- returns - so by the time it would run, the resets a few lines below
  -- would already have touched the same state. Calling the logic directly
  -- keeps the order right; updateValue() then moves the Capture pad to
  -- match without re-running its own function a second time.
  if value == CHORD_MODE_SHAPE or value == CHORD_MODE_SATB then
    clearChordCapture()
    if controls.get(26):getValue():getValue() == 1 then
      controls.get(26):getValue():updateValue(0)
    end
  end

  settleModeChange()
  chordCapturing = false
  chordCaptureNotes = {}

  lastChordMode = chordMode()
  updateHarmonyParamVisibility()
end

-- Named modes only make sense for the Major scale, and only up to its own
-- seven degrees; everything else - another scale, or a Mode value beyond
-- what the current scale has - shows the plain number instead (the control's
-- raw value is 0-based; the player sees it labelled 1..12, so the fallback
-- adds 1 back).
function formatModeName(valueObject, value)
  local scale = cfgList(34)
  if scale == 1 then
    local name = MAJOR_MODE_NAMES[value]
    if name then return name end
  end
  return tostring(value + 1)
end

function onTransposeSemitoneChange(valueObject, value)
end

function onSwingChange(valueObject, value)
  -- Swing never changes the timer's period; it only delays the off-beat
  -- note-on via midi.at() inside advanceStep.
end

function onSyncChange(valueObject, value)
  timer.setPeriod(basePeriodMs())
end

function onLatchChange(valueObject, value)
  -- value is the list's labelled value (0 Off, 1 Normal, 2 Chord), not an
  -- index - textValues were declared 0/1/2 so the two agree here.
  if value == LATCH_OFF then
    -- switching to Off: drop every struck key's generated notes unless
    -- that key is still physically down. Go by keyGeneratedNotes, not
    -- `held` directly - in Shape mode a held note can be a long way from
    -- the physical key number that produced it.
    for note in pairs(keyGeneratedNotes) do
      if not keysDown[note] then
        removeGeneratedNotes(note)
      end
    end
    if next(held) == nil then
      stopCurrent()
      stepIndex, direction = 0, 1
    end

    -- A latched (but no longer held) Shape/SATB key dropped above may have
    -- been the "active" one - if so a still-held key that was losing the
    -- priority competition should take over the slot now.
    if chordMode() == CHORD_MODE_SHAPE or chordMode() == CHORD_MODE_SATB then
      if shapeActiveKey ~= nil and keyGeneratedNotes[shapeActiveKey] == nil then
        shapeActiveKey = nil
      end
      if shapeActiveKey == nil then
        local winner = activeShapeNote()
        if winner ~= nil then
          addGeneratedNotes(winner, shapeHeld[winner])
          shapeActiveKey = winner
        end
      end
    end
  end
end

-- Destination moved: silence the old route before anything plays on the new
-- - for both the arp and Chord Mode, since they now share this destination.
-- Includes whatever Shape was sounding directly with the arp off.
function onDestChange(valueObject, value)
  if shouldSoundShapeDirectly() then
    local iface, port, chan = destRoute()
    for n in pairs(noteRefCount) do
      midi.sendNoteOff(iface, port, chan, n, 0)
    end
  end
  stopCurrent()
  stopAllChordNotes()
end

-- Source moved: the keys held on the old source will never send their
-- note-off, for either the arp or Chord Capture, since they now share it.
function onSourceChange(valueObject, value)
  if shouldSoundShapeDirectly() then
    local iface, port, chan = destRoute()
    for n in pairs(noteRefCount) do
      midi.sendNoteOff(iface, port, chan, n, 0)
    end
  end
  stopCurrent()
  held, pressOrder, keysDown, noteRefCount, keyGeneratedNotes, keyVelocity = {}, {}, {}, {}, {}, {}
  shapeHeld, shapePressOrder, shapeActiveKey = {}, {}, nil
  stepIndex, direction = 0, 1

  stopAllChordNotes()
  chordHeld, chordPressOrder = {}, {}
  -- A capture in progress was listening on the old source too; abandon it
  -- rather than finish it with notes from a route that no longer applies.
  chordCapturing = false
  chordCaptureNotes = {}
end

-- The Capture toggle. Turning it ON opens a recording window - seeded with
-- whatever is already held, so starting the gesture with keys already down
-- still counts - and every note struck while it is open is remembered,
-- whether or not it is still held when the window closes. Turning it OFF
-- closes the window and, if anything was played during it, replaces the
-- stored chord with it; an empty window (toggled on and off with nothing
-- played) leaves whatever was captured before untouched.
-- Finalizes whatever was played during a capture window: turns the notes
-- struck into offsets from their lowest, arms the chord, and updates the
-- indicator. Called from onChordCapture() when the player turns Capture
-- off by hand, and called DIRECTLY (not through Capture's control value)
-- from onChordModeChange() when switching to Shape turns Capture off for
-- the player - see the long comment there for why a nested setValue()
-- cannot be trusted to run before onChordModeChange's own state resets do.
finalizeCapture = function()
  chordCapturing = false

  local notes = {}
  for note in pairs(chordCaptureNotes) do notes[#notes + 1] = note end
  chordCaptureNotes = {}
  if #notes == 0 then return end       -- nothing played during the window: leave the old chord alone

  table.sort(notes)
  local root = notes[1]
  local offsets = {}
  for _, note in ipairs(notes) do
    offsets[#offsets + 1] = note - root
  end

  chordOffsets = offsets
  chordArmed = true
  updateChordArmedIndicator()
end

function onChordCapture(valueObject, value)
  if value == 1 then
    -- Chord Capture and Shape/SATB are alternative chord-to-key mappings
    -- and cannot both be live: turning Capture on while either is selected
    -- hands the keystroke back to Capture - every side effect of leaving
    -- it (silencing whatever it was sounding directly, etc) via
    -- settleModeChange(), the same helper onChordModeChange uses.
    --
    -- This does NOT go through Chord Mode's own setValue(): a nested
    -- setValue() made from inside another value's own function is not
    -- run inline - it is only applied once this whole function returns -
    -- and onChordModeChange's generic cleanup unconditionally resets
    -- chordCapturing/chordCaptureNotes. Were this call left as a nested
    -- setValue(), that deferred reset would land AFTER the capturing
    -- session started below and silently cancel it - found by testing
    -- exactly this sequence (Shape selected, Capture pressed, chord
    -- played) and getting the Shape default chord back instead of what
    -- was played. Calling settleModeChange() directly and moving the
    -- control with updateValue() keeps the order right and never
    -- re-enters onChordModeChange at all.
    if chordMode() == CHORD_MODE_SHAPE or chordMode() == CHORD_MODE_SATB then
      settleModeChange()
      lastChordMode = CHORD_MODE_OFF
      controls.get(37):getValue():updateValue(CHORD_MODE_OFF)
      updateHarmonyParamVisibility()
    end

    chordCapturing = true
    chordCaptureNotes = {}
    for note, vel in pairs(chordHeld) do
      chordCaptureNotes[note] = vel
    end
    return
  end

  finalizeCapture()
end

-- Clears the stored chord outright: anything still sounding from it stops,
-- any capture window left open is abandoned, and every key struck
-- afterwards is silent again until a new chord is captured - exactly like
-- the state before anything was ever captured. Fires on press only.
clearChordCapture = function()
  stopAllChordNotes()
  chordArmed = false
  chordOffsets = nil
  chordCapturing = false
  chordCaptureNotes = {}
  updateChordArmedIndicator()
end

function onChordClear(valueObject, value)
  if value == 0 then return end

  clearChordCapture()
end

-- The arp's own on/off switch. Chord Mode is unaffected either way - only
-- the timer that drives the pattern engine is gated here. Assigned (not
-- "local function") because this fills the forward declaration above.
isArpOn = function()
  return controls.get(29):getValue():getValue() == 1
end

-- Resets the pattern to its first step - the same starting point a pattern
-- or octave-range change already gives it - without changing anything else
-- (the held notes, the latch, the destination). Stops whatever is currently
-- sounding; the next tick plays step 1, fresh. Fires on press only.
function onArpReset(valueObject, value)
  if value == 0 then return end

  stopCurrent()
  stepIndex, direction = 0, 1
  swingParity = 0
  shuffledOrder, shuffledPos = nil, 1
end

-- HOLD (ref 53): keeps a directly-sounding chord (Shape/SATB or Chord
-- Capture) ringing after the key that struck it is released, until HOLD
-- itself is turned off. It cannot run together with the arp - a struck
-- key's release has nothing to do with the arp - so the two compete for
-- the same keystroke exactly the way Break Time and the arp already do
-- (onBreakTimeChange/onArpToggle): turning HOLD on hands the keystroke
-- back from the arp, turning the arp on takes it back from HOLD.
function onHoldChange(valueObject, value)
  if value == 1 then
    if isArpOn() then
      controls.get(29):getValue():setValue(0)   -- Arp: off, HOLD has the keystroke now
    end
    return
  end

  -- HOLD turned off: anything only still sounding because of it, with
  -- nothing physically holding it any more, should stop now.
  local mode = chordMode()
  if mode == CHORD_MODE_SHAPE or mode == CHORD_MODE_SATB then
    if shapeActiveKey ~= nil and shapeHeld[shapeActiveKey] == nil then
      removeGeneratedNotes(shapeActiveKey)
      shapeActiveKey = nil
    end
  elseif mode == CHORD_MODE_OFF then
    if chordActiveNote ~= nil and chordHeld[chordActiveNote] == nil then
      stopAllChordNotes()
    end
  end
end

function onArpToggle(valueObject, value)
  if value == 1 then
    -- The arp and Break Time compete for the same keystroke (see
    -- onBreakTimeChange above) - turning the arp on hands the keystroke
    -- back to it, so Break Time is reset to 0.
    if cfgValue(43) > 0 then
      controls.get(43):getValue():setValue(0)   -- Break Time: off, the arp has the keystroke now
    end
    -- HOLD competes for the same keystroke too (see onHoldChange above).
    if holdActive() then
      controls.get(53):getValue():setValue(0)   -- HOLD: off, the arp has the keystroke now
    end
    -- Handing the held pool over to the arp: anything Shape/SATB was
    -- sounding directly (arp was off a moment ago) must stop now, since the
    -- arp is about to start stepping through the very same pool one note
    -- at a time - both at once would double notes up.
    if chordMode() == CHORD_MODE_SHAPE or chordMode() == CHORD_MODE_SATB then
      local iface, port, chan = destRoute()
      for n in pairs(noteRefCount) do
        midi.sendNoteOff(iface, port, chan, n, 0)
      end
    end
    swingParity = 0
    timer.setPeriod(basePeriodMs())
    timer.enable()
  else
    timer.disable()
    stopCurrent()
    -- Taking the pool back from the arp: in Shape/SATB mode, whatever is
    -- still held should keep sounding, as the whole chord at once rather
    -- than one arpeggiated note - nothing else will play it now.
    if chordMode() == CHORD_MODE_SHAPE or chordMode() == CHORD_MODE_SATB then
      local iface, port, chan = destRoute()
      for n, vel in pairs(held) do
        midi.sendNoteOn(iface, port, chan, n, vel)
      end
    end
  end
end

function preset.onReady()
  local iface, port, chan = destRoute()
  -- All Notes Off: a reload forgets what it was sounding, for the arp and
  -- for Chord Capture, since both share this destination.
  midi.sendControlChange(iface, port, chan, 123, 0)
  held, pressOrder, keysDown, currentNote = {}, {}, {}, nil
  noteRefCount, keyGeneratedNotes, keyVelocity = {}, {}, {}
  shapeHeld, shapePressOrder, shapeActiveKey = {}, {}, nil
  stepIndex, direction = 0, 1
  shuffledOrder, shuffledPos = nil, 1
  swingParity = 0
  timer.setPeriod(basePeriodMs())
  -- Respect the Arp On/Off control's own loaded value (its function has
  -- already run by this point, same as every other control's) rather than
  -- forcing the timer on regardless - see recipe 33.13's trap 3.
  if isArpOn() then
    timer.enable()
  else
    timer.disable()
  end

  chordHeld, chordPressOrder, chordActiveNote, chordActiveSentNotes = {}, {}, nil, {}
  chordCapturing, chordCaptureNotes = false, {}
  -- A reload's fresh Lua state never remembers a captured chord (chordArmed
  -- starts false again), so the indicator must be reset to match, not left
  -- showing whatever colour the project file happens to declare.
  chordArmed = false
  updateChordArmedIndicator()

  -- The Mode control's displayed text is driven by setOverride() rather
  -- than solely by its formatter's cache (see refreshModeDisplay above),
  -- so it needs setting explicitly on load too.
  refreshModeDisplay()

  -- Sync onChordModeChange()'s memory of "the mode a moment ago" to what
  -- actually loaded, so the first change after a reload compares against
  -- the real starting mode rather than a stale default.
  lastChordMode = chordMode()
  updateHarmonyParamVisibility()
end

function preset.onExit()
  timer.disable()
  stopCurrent()
  stopAllChordNotes()
  if shouldSoundShapeDirectly() then
    local iface, port, chan = destRoute()
    for n in pairs(noteRefCount) do
      midi.sendNoteOff(iface, port, chan, n, 0)
    end
  end
end

-- TEMP DEBUG
function debugNotesForKey(n)
  return notesForKey(n)
end
function debugQuantize(n)
  return quantizeToScale(n)
end
debugSentNotesList = {}
function debugSentNotesHook(note)
  debugSentNotesList[#debugSentNotesList+1] = note
end
function debugGetSent()
  return debugSentNotesList
end
function debugClearSent()
  debugSentNotesList = {}
end
function debugKeyDown(n, v)
  onKeyDown(n, v or 100)
end
function debugKeyUp(n)
  onKeyUp(n)
end
function debugTick(n)
  for i=1,(n or 1) do timer.onTick(1) end
end
