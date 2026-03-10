# Yet Another Linda (YAL)
**Version 4.6b9** (beta channel)

*(C) WAHLTHO 2023-2026*

Virtual copilot plugin for the Zibo Mod 737 in X-Plane.

## Installation
1. Copy the main `YAL` folder into `X-Plane/Resources/plugins/`.
2. Start X-Plane and configure YAL via `Plugins -> Yet Another Linda -> Settings`.

### Optional: Skunkcrafts Beta Channel
1. Copy `skunkcrafts_updater_beta.cfg` into the aircraft directory that contains the Zibo aircraft.
2. Start X-Plane, open Skunkcrafts Updater and refresh.
3. In the YAL settings window enable `Show beta updates`.
4. Run the `YAL Beta` updater entry to install beta builds.

## Requirements
- X-Plane 11 or 12
- Supported Zibo aircraft
- Optional: X-Camera
- Optional: BetterPushback
- Optional: YANSH
- Optional: YAL Hoppie Helper

## Release Highlights (4.6b9 beta)
- Extended taxi map and taxi routing: ARR/DEP planning, scenery/global apt source switching, manual route lock, improved rerouting, runway entry/backtrack handling and gate guidance.
- Auto Taxiing and taxi guidance have been expanded and can now be used with voice and/or visual guidance.
- `SET ILS` / approach setup no longer depends on parsing the FMC `APPROACH REF` page; approach selection, tuning and course calculation are resolved internally with zibo-like logic.
- Approach handling now covers ILS/LOC/LDA/IGS/GLS/LPV/RNAV more consistently.
- New trim advice popup for manual takeoff-trim setting in Voice Advice Only mode.
- New startup update check for YAL and Zibo versions.
- Voice advice controls now include repeat throttling and optional maximum repeats.
- Periodic YAL autosave accepts `0` or `9999` as `off`.

## Useful Commands
- `YAL/step_once`: execute the current requested step once in Voice Advice Only mode.
- `YAL/toggleautotaxiing`: toggle Auto Taxiing.
- `YAL/toggleautotaxipause`: pause/resume Auto Taxiing.
- `YAL/toggletrimpopup`: show or hide the trim advice popup while a valid trim target exists.
- `YAL/setils`: run `SET ILS / GLS Freq/Course` manually.

## Documentation
The full user documentation is in:
- `Documentation/YAL Manual.md`

## Notes
- YAL remains largely idle when no supported aircraft is loaded.
- All assignable commands are available in the X-Plane keyboard/joystick settings under the `YAL/...` group.
- The plugin is designed to have very low FPS impact because the main logic runs on a timed loop rather than every frame.
