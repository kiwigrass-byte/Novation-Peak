# Arp Chord Engine Quickstart

Fast setup guide for the `arp-chord-engine.lua` Electra One preset.

---

## 1) Basic routing first (always do this)

Set these before testing anything:

- **Source**: refs **3/4/5** (Interface / Port / Channel)
- **Destination**: refs **6/7/8** (Interface / Port / Channel)

If notes don’t react, source is usually wrong.  
If notes react but no sound, destination is usually wrong.

---

## 2) Choose your play mode (Harmony Mode, ref 37)

- **Off**: normal arp input (keys go straight into arp pool)
- **Shape**: each key expands to a diatonic chord shape
- **SATB**: each key expands to four-part harmony

> Tip: Key/Mode/Scale (refs 33/27/34) matter in all modes because quantization/degree logic uses them globally.

---

## 3) Turn arp on/off (ref 29)

- **On**: timer-driven arpeggiation runs
- **Off**: no stepper; Shape/SATB can sound full generated chords directly

Reset pattern position anytime with **Arp Reset** (ref 32).

---

## 4) Core arp controls

- **Tempo** (1)
- **Sync Rate** (13)
- **Pattern** (2)
- **Octaves** (10)
- **Gate** (11)
- **Swing** (12)
- **Chance** (16)
- **Transpose Oct/Semi** (18/19)
- **Latch** (9)

Start here for a safe baseline:
- Pattern: Up
- Octaves: 1
- Gate: ~70–90%
- Swing: 0
- Chance: 100%

---

## 5) Shape mode quick use (ref 37 = Shape)

1. Set **Shape** (36), e.g. Triad or Seventh  
2. Optionally set **Inversion** (40)  
3. Play single notes; each key generates a full diatonic chord set.

Key point:
- Chords are degree-based in current Key/Scale/Mode, not fixed semitone templates.

---

## 6) SATB mode quick use (ref 37 = SATB)

1. Set **Root Degree** (50)
2. Set **Cantus Primus** (51)
3. Set **Position** (52): Closed / Open / Tintinnabuli variants
4. Play single notes for 4-voice output.

Use this when you want structured four-part movement from single-note input.

---

## 7) Chord Capture quick use (independent tool)

Works only when Harmony Mode is **Off**.

- **Capture** toggle: ref **26**
- **Clear chord**: ref **30**
- **Armed indicator**: ref **31** (green = captured chord stored)

Flow:
1. Set Harmony Mode to Off
2. Turn Capture ON
3. Play chord notes (any order/timing)
4. Turn Capture OFF
5. Now single keys replay that captured shape transposed

---

## 8) Break Time / Direction (broken chord spread)

- **Break Time** (43): spread chord notes over time (ms)
- **Break Direction** (44): Up / Down / Alternating

Important:
- Break and Arp are mutually exclusive by design.
  - If Break Time > 0 while arp is on, arp turns off.
  - If arp turns on, Break Time is reset to 0.

---

## 9) Note Priority (ref 49)

Used where one held key must “win”:

- **Last**
- **Highest**
- **Lowest**

Affects:
- Chord Capture playback key selection
- Shape/SATB active-key selection when multiple keys are held

---

## 10) External switch control (optional)

Set switch input route on refs **45/46/47**.

On that route:
- **CC126** toggles Arp On/Off (ref 29)
- **CC127** toggles Capture (ref 26)
- Value >= 64 = ON

---

## 11) Five ready-to-play recipes

## A) Classic arp
- Harmony Mode: Off
- Arp: On
- Pattern: Up/Down
- Octaves: 2
- Gate: 65%
- Swing: +15%

## B) Diatonic chord arp
- Harmony Mode: Shape
- Shape: Seventh
- Arp: On
- Play single notes; arp steps through generated chord tones.

## C) Big sustained harmonic pad
- Harmony Mode: SATB
- Position: Open
- Arp: Off
- Latch: Normal or Chord
- Play one key at a time for 4-note stacks.

## D) Captured voicing transposer
- Harmony Mode: Off
- Capture ON → play custom voicing → Capture OFF
- Arp: Off
- Play melody keys; each triggers captured voicing.

## E) Broken chord performer
- Harmony Mode: Shape or SATB (or captured chord)
- Arp: Off
- Break Time: 120–300 ms
- Break Direction: Alternating

---

## 12) Quick troubleshooting

- **No response to keys**: check source refs 3/4/5
- **Response but no sound**: check destination refs 6/7/8
- **Capture seems inactive**: ensure Harmony Mode is Off
- **Break not working**: make sure Arp is Off
- **Arp not running**: check ref 29 On and tempo/sync values
- **Stuck behavior after route changes**: retrigger notes; script clears states on route/mode changes by design

---

For full behavior details and internals, see:
**`arp-chord-engine-reference.md`**
