# Novation Peak with Patch Parsing v6.7
---
- Based closely on V6 of Novation Summit preset by @NewIgnis, using the Peak sysEx header and including only Peak relevant parameters.
- Synth must be on at least firmware V2.1 (august 2022)
- E1 must be on at least firmware 5.0.0

---
**What's in the preset**
- Automatic parsing of a patch when a new patch is selected.
- Automatic detection of Peak's MIDI channel.
- Preset parameters will update when changed on the Peak.
- The **Patch Select**  buttons send a program change message before loading the patch data.  
- Turning the **Bank Names** switch 'on' retrieves all the patch names from all banks. The button should toggle to an 'off' state after all 512 names are read. The patch number fader will then display the patch names when scrolling. This process takes about 2 minutes to complete. The patch names are stored on the E1 and are loaded when the preset loads. If you change patches on the Peak or move the preset to a different slot then repeat the process.
- **Modulation Matrix Scaling** is a macro attenuverter for all 16 modulation-matrix depth amounts. At +100%, the individual modulation amounts are unchanged. At 0%, all modulation depths are reduced to zero—the depth controls are centered. At −100%, the individual modulation amounts are fully inverted. This is an add-on feature and not part of the Peak.
- The **Modulation Scaling LFO** is a rate-selectable uni- or bi-polar LFO (triangle or smoothed S&H) that can be used to modulate the macro attenuverter.
- There are also 16 **Modulation Matrix Scaling Locks**. When a lock is ON it prevents the scaling from applying to the corresponding matrix slot.
- The **Compare** switch provides a real-time comparison between the live patch and the parsed patch. When **Compare** is ON, the full parsed patch is restored, including modulation matrix depths, with no modulation matrix scaling applied. Turning **Compare** OFF restores the current live edited patch and reapplies the **Modulation Matrix Scaling** control.
- A subset of the Peak's global settings (dark blue) can be changed from the preset. 
- The names of the 10 user wavetables are displayed when selected. 
- Various controls dim or are hidden when not in use.
----


[Firmware V2.0 + V2.1 manual](https://fael-downloads-prod.focusrite.com/customer/prod/downloads/summit_peak_2.1_firmware_update_addendum_v1_english_en.pdf)

---


[Firmware V2.0 + V2.1 manual](https://fael-downloads-prod.focusrite.com/customer/prod/downloads/summit_peak_2.1_firmware_update_addendum_v1_english_en.pdf)

---
