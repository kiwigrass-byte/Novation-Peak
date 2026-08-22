# Novation Peak with Patch Parsing

---
- Based closely on V6 of Novation Summit preset by @NewIgnis, using the Peak sysEx header and including only Peak relevant parameters.

- Synth must be on at least firmware V2.1 (august 2022)

- Set the midi channel (the preset uses channel 3)

---
**What's in the preset**
- Automatic parsing of a patch when a new patch is selected.
- Preset parameters will update when changed on the Peak.
- The "Patch Select"  buttons send a program change message before loading the patch data.  
- "Bank Names" retrieves all the patch names from all banks. The button should toggle to an 'off' state after all 512 names are read. The patch number fader will then display the patch names when scrolling. This process takes about 2 minutes to complete.
- A subset of the Peak's global settings can be changed from the preset. This feature sends the sysEx message only when the pot is released.
- The names of the 10 user wavetables are displayed when selected. 
- Various controls darken or are hidden when not in use.
----


[Firmware V2.0 + V2.1 manual](https://fael-downloads-prod.focusrite.com/customer/prod/downloads/summit_peak_2.1_firmware_update_addendum_v1_english_en.pdf)

---
