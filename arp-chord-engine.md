# arp-chord-engine.lua Reference (Hybrid)

> Repository: `kiwigrass-byte/Novation-Peak`  
> Script: `arp-chord-engine.lua`  
> Purpose: Arpeggiator + Harmony generator (Shape/SATB) + Chord Capture, with shared routing and performance controls.

---

## 1) What this script does (quick overview)

This preset script combines three note-generation systems:

1. **Arpeggiator**  
   Uses held notes as a pool and plays them step-by-step using selectable patterns, sync rates, gate, swing, chance, transpose, octaves, and latch modes.

2. **Harmony Mode** (`ref 37`, labeled “HARMONY MODE” on controller)  
   - **Off**: keys behave normally (one key = one note)  
   - **Shape**: each key generates a diatonic chord shape from Key/Scale/Mode  
   - **SATB**: each key generates a four-part harmonization with common-practice / tintinnabuli-style voicing options

3. **Chord Capture** (`ref 26`)  
   Independent tool for capturing a played chord shape (semitone offsets from lowest note) and replaying/transposing it from single keys.

These systems share source/destination routing and enforce mutual exclusions where needed (notably Shape/SATB vs Capture, and Arp vs Break Time behavior).

---

## 2) Control reference map (refs used by script)

## Timing / pattern / arp core
- **1** Tempo
- **2** Pattern
- **9** Latch (Off / Normal / Chord)
- **10** Octaves
- **11** Gate Length
- **12** Swing
- **13** Sync Rate
- **16** Chance
- **18** Transpose Octave
- **19** Transpose Semitone
- **29** Arp On/Off
- **32** Arp Reset

## Routing
- **3/4/5** Source Interface / Port / Channel
- **6/7/8** Destination Interface / Port / Channel
- **45/46/47** External switch Interface / Port / Channel

## Harmony / scale
- **27** Mode
- **33** Key
- **34** Scale
- **37** Harmony Mode (internally “Chord Mode” constants)
- **36** Shape
- **40** Inversion (Shape mode only)
- **50/51/52** SATB: Root Degree / Cantus Primus / Position
- **49** Note Priority (Last / Highest / Lowest)

## Chord Capture
- **26** Capture toggle
- **30** Clear chord
- **31** Chord Armed indicator (display only; script sets color)

## Broken chord
- **43** Break Time (ms)
- **44** Break Direction (Up / Down / Alternating)

---

## 3) High-level architecture

Core internal state buckets:

- **Arp pool/state**: `held`, `pressOrder`, `stepIndex`, `direction`, `currentNote`, `swingParity`
- **Generated-note ownership** (Shape/SATB): `noteRefCount`, `keyGeneratedNotes`, `keyVelocity`
- **Physical-key tracking**: `keysDown`
- **Shape/SATB priority subsystem**: `shapeHeld`, `shapePressOrder`, `shapeActiveKey`
- **Chord Capture subsystem**: `chordHeld`, `chordPressOrder`, `chordOffsets`, `chordArmed`, `chordCapturing`, `chordCaptureNotes`, etc.

Important design pattern:
- **Physical keys** are tracked separately from **generated notes**.
- Generated notes are reference-counted, so overlapping results from different keys are released correctly.

---

## 4) Arpeggiator behavior

## 4.1 Pattern list (14)
Internal constants map to control order:

0. Up  
1. Down  
2. Up/Down (no repeated ends)  
3. Up/Down repeat ends  
4. Up -8ve  
5. Down -8ve  
6. Up/Down -8ve  
7. Up/Down repeat ends -8ve  
8. Step Up  
9. Step Down  
10. Random  
11. Random2 (no immediate repeat when possible)  
12. Random3 (shuffled permutation per pass)  
13. As Played

## 4.2 Octave expansion
`orderedNotes(skipSeams)` expands held notes over `Octaves`.  
- `-8ve` variants skip seam duplicates between octave bands.

## 4.3 Timing and sync
- Base period = BPM + Sync Rate (`syncRates` table)
- Timer period is stable; swing does **not** alter period dynamically.

## 4.4 Swing
- Swing is bipolar.
- Positive swing delays off-beats.
- Negative swing delays the preceding on-beat (so the same gap is shortened without “negative delay”).

## 4.5 Gate and chance
- Chance: per-step probability; skipped steps still advance sequence.
- Gate < 100% schedules note-off before next nominal step window.

## 4.6 Quantization + transpose at output
Before send:
1. pattern/octave picks note
2. octave + semitone transpose applied
3. quantized via Key/Scale/Mode (`quantizeToScale`)
4. clamped 0–127 and sent

---

## 5) Key/Scale/Mode system

- Scales come from `SCALE_OFFSETS`.
- Mode rotates scale interval pattern (`computeRotatedOffsets`) to derive modal degrees while keeping key root reference.
- `nearestScaleMatch(note)` snaps to nearest degree (tie rounds upward).
- Quantizer is active for arp step output and used as degree basis for Shape/SATB generation logic.

`Mode` display:
- For Major scale, names Ionian..Locrian are shown where applicable.
- Otherwise numeric label shown.

---

## 6) Harmony Mode (`ref 37`)

Values:
- `0` Off
- `1` Shape
- `2` SATB

Visibility rules (`updateHarmonyParamVisibility`):
- Always visible: Key/Mode/Scale (`33/27/34`)
- Shape visible only in Shape mode: Shape/Inversion (`36/40`)
- SATB visible only in SATB mode: Root Degree/Cantus Primus/Position (`50/51/52`)

Mode switch resets/cleanup are centralized via `settleModeChange()` plus mode-specific handling.

---

## 7) Shape mode details

## 7.1 Concept
A struck key is snapped to nearest scale tone first, then chord is built by **scale degrees** from that location (not fixed semitone template transposition).

Result: chord quality follows scale degree (diatonic behavior).

## 7.2 Shapes
14 shapes (`SHAPES`) from single note up to Ninth variants, encoded as `{degree, extraOctaves}` pairs.

## 7.3 Inversion
`applyInversion` rotates lowest N shape tones up an octave, wrapping by note count.

## 7.4 Live regeneration
Changing Shape/Inversion (and SATB params when in SATB) updates currently sounding generated notes via `regenerateShapeNotes()` (diff-based, not full panic).

---

## 8) SATB mode details

SATB output is always four voices:
- Soprano, Alto, Tenor, Bass (clamped 0–127)

## 8.1 Root Degree (`ref 50`)
Defines the **role** of struck note in its own chord (I/III/V/etc.), not one fixed global chord.

## 8.2 Cantus Primus (`ref 51`)
Selects which voice the struck note belongs to (S/A/T/B).

## 8.3 Position (`ref 52`)
- Closed
- Open
- Tintinnabuli variants (`+1/+2/-1/-2` modeled as internal position constants)

Engines:
- `satbClosedOrOpen`
- `satbTintinnabuli`

Both are built so the struck note is placed exactly in the selected Cantus voice.

---

## 9) Note Priority (`ref 49`)

Shared policy for:
- Chord Capture playback (when Harmony Mode Off)
- Shape/SATB active physical-key selection

Modes:
- Last
- Highest
- Lowest

When multiple keys are held, only one “winner” key drives generated output in Shape/SATB priority path (`shapeActiveKey`), and winner can change live on key/policy changes.

---

## 10) Latch modes (`ref 9`)

- **Off**: release removes notes normally.
- **Normal**: notes can remain latched.
- **Chord**: a fresh gesture (first new physical key when none held) replaces previous latched collection.

Script handles physical key state and generated-note state separately to preserve expected latch semantics with generated chords.

---

## 11) Chord Capture subsystem (independent tool)

Only active when Harmony Mode is **Off**.

## 11.1 Capture flow
- Toggle Capture on (`ref 26`) opens recording window.
- Notes played during window are collected (`chordCaptureNotes`), even if released before close.
- Toggle off finalizes:
  - sort notes
  - root = lowest note
  - store semitone offsets from root (`chordOffsets`)
  - set `chordArmed = true`
  - update indicator (`ref 31` green)

Empty capture window leaves prior captured chord unchanged.

## 11.2 Playback
With captured chord armed:
- pressing a key transposes stored offsets to that key
- uses triggering key velocity for all generated notes
- optional broken playback if Break Time > 0

## 11.3 Clear
`ref 30` clears armed chord and active capture state, stops sounding captured notes, resets indicator.

---

## 12) Break Time / Direction (refs 43/44)

Break feature spreads chord notes over time:
- first note immediately
- last note exactly at Break Time ms
- order by Break Direction:
  - Up
  - Down
  - Alternating outside-in

Used by:
- Shape/SATB direct chord sounding (when arp off)
- Chord Capture trigger playback

Release behavior is simple/all-at-once note-off (not staggered off).

---

## 13) Arp vs Break exclusivity

Mutual handoff logic:
- If Break Time rises above 0 while arp is on → arp is turned off.
- If arp turns on while Break Time > 0 → Break Time is set to 0.

Implementation uses `setValue()` intentionally so normal side effects run as if user toggled directly.

---

## 14) Routing and I/O

## 14.1 Note source
`srcMatches()` compares incoming note route against refs `3/4/5`.

## 14.2 Destination
`destRoute()` reads refs `6/7/8`.

## 14.3 External switch CC input
From refs `45/46/47` route:
- CC **126** toggles Arp On/Off (`ref 29`)
- CC **127** toggles Capture (`ref 26`)
- value >= 64 treated as ON

---

## 15) Initialization / lifecycle

## `preset.onReady()`
- sends All Notes Off to destination
- clears runtime state
- restores timer enable according to arp toggle state
- resets chord-armed state/indicator in fresh Lua state
- refreshes Mode display override
- syncs `lastChordMode`
- applies parameter visibility for loaded mode

## `preset.onExit()`
- disables timer
- stops arp current note
- stops chord-capture sounding notes
- sends note-offs for direct Shape/SATB sounding notes when applicable

---

## 16) Key helper functions (developer index)

- **Config readers**
  - `cfgList(ref)`: list controls with signed uint16 unwrap
  - `cfgValue(ref)`: direct numeric controls (supports negative ranges reliably)
- **Scale/mode**
  - `computeRotatedOffsets`
  - `nearestScaleMatch`
  - `quantizeToScale`
  - `scaleStepOffset`
- **Shape**
  - `shapeNotesForKey`
  - `applyInversion`
  - `regenerateShapeNotes`
- **SATB**
  - `satbChordForNote`
  - `satbClosedOrOpen`
  - `satbTintinnabuli`
  - `satbNotesForKey`
- **Arp stepping**
  - `orderedNotes`
  - `buildUpDownRepeatSequence`
  - `advanceStep`
- **Timing**
  - `basePeriodMs`
  - `swingDelayMs`
  - `stepIsDelayedBySwing`
- **Chord Capture**
  - `triggerChord`
  - `finalizeCapture`
  - `clearChordCapture`
- **Mode / state transitions**
  - `settleModeChange`
  - `updateHarmonyParamVisibility`

---

## 17) Important interaction rules (summary)

1. Shape/SATB and Chord Capture are mutually exclusive chord-mapping systems.
2. Chord Capture only processes notes when Harmony Mode is Off.
3. Arp and Break Time are mutually exclusive “who owns keystroke timing” engines.
4. Key/Scale/Mode are global in practice (arp quantization + harmony degree logic), not Shape-only.
5. Generated-note reference counting prevents premature note-off with overlapping generated pitches.

---

## 18) Debug helpers included in script

Temporary debug functions at bottom:
- `debugNotesForKey`
- `debugQuantize`
- `debugSentNotesHook` + sent-note list accessors
- `debugKeyDown`, `debugKeyUp`, `debugTick`

These are useful for quick behavioral checks and should be reviewed before production release if you want a clean build.

---

## 19) Suggested future doc add-ons (optional)

- Truth table for mode/latch combinations
- Per-pattern worked examples for a sample held-note set
- SATB worked examples for each Cantus Primus + Position option
- MIDI routing troubleshooting section
- “Musician quick start” appendix with 5 common setups
