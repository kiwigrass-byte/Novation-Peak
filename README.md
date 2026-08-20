# Novation Peak with Patch Parsing
Based closely on # V4 of Summit preset by @NewIgnis, using the Peak sysEx header and including only Peak relevant parameters.
---

- Synth must be on firmware V2.1 (august 2022) or above

- Set the midi channel (the preset uses channel 3)

---
**What's in the preset**
- Automatic parsing of a patch when a new patch is selected.
- Parameters will update when changed on the Peak.
- The "Patch Select"  buttons send a program change message before loading the patch data. You can also select patches directly on the Peak and all the parameters should update. 
- "Bank Names" retrieves all the patch names of the currently selected bank. The button should toggle to an 'off' state after all 128 names are read. The patch number fader will then display the patch names when scrolling.
- A subset of the Peak's settings can be changed, including the master clock rate, clock source, transpose, and master fine tuning.
- The names of the 10 user wavetables are displayed when selected. 
- Various controls darken or are hidden when not in use.
----

No AI minions were harmed in the making of this preset.


[Firmware V2.0 + V2.1 manual](https://fael-downloads-prod.focusrite.com/customer/prod/downloads/summit_peak_2.1_firmware_update_addendum_v1_english_en.pdf)

---
