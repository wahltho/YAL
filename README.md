# Yet Another Linda (YAL)
**Version 4.6** (stable channel)

*(C) WAHLTHO 2023-2026*

Virtual copilot plugin for the Zibo Mod 737 in X-Plane.

## License and Official Distribution
YAL is source-available software and is not distributed as an open-source
project. Personal, non-commercial use of official YAL releases is permitted
under the terms in `LICENSE`.

Only releases published by the copyright holder through this repository or the
official YAL update channels are official and supported YAL releases.
Publishing or redistributing modified or unmodified YAL versions requires prior
written permission. Bundled third-party components remain subject to their own
licenses, including `SASL-LICENSE.txt`.

## Installation
1. Copy the main `YAL` folder into `X-Plane/Resources/plugins/`.
2. Start X-Plane.
3. Configure YAL via `Plugins -> Yet Another Linda -> Settings`.

## Optional: Skunkcrafts Beta Channel
1. Copy `skunkcrafts_updater_beta.cfg` into the aircraft directory that contains the Zibo aircraft.
2. Start X-Plane, open Skunkcrafts Updater and refresh.
3. In the YAL settings window enable `Show beta updates`.
4. Run the `YAL Beta` updater entry to install prerelease builds from the beta/RC feed.
5. To return to stable builds, disable `Show beta updates` and use the normal updater entry again.

## Requirements
- X-Plane 11 or 12
- Primary support target: Zibo B737-800
- Optional: X-Camera
- Optional: BetterPushback
- Optional: YANSH
- Optional: YAL Hoppie Helper

## What YAL Does
YAL automates or advises normal cockpit flows for the Zibo 737 and provides additional support features such as:
- Procedure automation from cold and dark through turnaround/shutdown
- Voice Advice Only mode for manual operation with spoken guidance
- FMC-related assistance for descent, approach and landing setup
- Taxi map, taxi routing, taxi guidance and experimental auto taxiing
- Weather, METAR and runway/RVR related assistance
- Optional update checks for YAL and Zibo

## Main Features in the 4.6 Release
- Extended taxi map and taxi routing:
  - ARR/DEP planning
  - scenery/global apt source switching
  - manual route locking
  - improved rerouting and source failover from the current aircraft position
  - runway entry, backtrack, align and threshold guidance
  - gate guidance, gate switching and routeable end-ramp validation
- Manual route drawing/editing now follows route order more naturally:
  - start first
  - then point-by-point along the route
  - optional gate/ramp selection as the final point
- Expanded taxi guidance and Auto Taxiing with voice and visual guidance support
- `SET ILS` / approach setup no longer depends on parsing the FMC `APPROACH REF` page
- More consistent approach handling for ILS / LOC / LDA / IGS / GLS / LPV / RNAV, including non-tunable RNAV cases
- New trim advice popup for manual takeoff-trim setting in Voice Advice Only mode
- Startup update check for both YAL and Zibo versions
- Voice advice repeat throttling and optional maximum repeat protection
- Periodic YAL autosave now accepts `0` or `9999` as `off`

## Procedure Overview
YAL supports both manually triggered and automatically triggered procedures.

Typical manually triggered procedures:
- Cold and Dark Startup
- Cockpit Initialization
- APU Startup
- Engine Startup
- Engine Shutdown / Shutdown
- Set ILS / GLS Freq/Course
- Set Landing Flaps / VREF
- Set Takeoff Flaps
- Tests

Typical automatic procedures:
- Before Taxi
- Before Takeoff
- After Takeoff
- During Climb
- Above 10,000 Feet
- During Descent
- Below 10,000 Feet
- Final approach gates
- After Landing
- At Parking Position

## Taxi Map, Taxi Guidance and Auto Taxiing
The taxi system is one of the major YAL feature areas.

Key capabilities:
- Automatic departure and arrival taxi routing
- Manual route drawing and route editing
- Locking a manual route against automatic recompute
- Spoken taxi guidance
- Independent visual taxi guidance popup
- Experimental Auto Taxiing following the active taxi route
- Source switching between scenery and global `apt.dat`, with `AUTO` fallback when one source is invalid

Useful commands:
- `YAL/toggleautotaxiing`
- `YAL/toggleautotaxipause`

## Approach Setup / SET ILS
`SET ILS` now resolves the selected approach internally.

This means:
- YAL no longer needs to parse the FMC `APPROACH REF` page to determine the selected approach
- YAL resolves the required tuning/channel/course targets internally
- Auto mode still sets frequencies/channels and courses
- Voice Advice Only mode still announces the same targets for manual entry
- For RNAV approaches without a tunable frequency/channel, YAL announces that explicitly and then provides the final approach course

Supported approach families include:
- ILS / LOC
- LDA / IGS
- GLS / LPV
- RNAV, including LP differentiation where supported by navdata

## Voice Advice Tools
If you prefer manual flying and cockpit operation, YAL can run in `Voice Advice Only` mode.

Useful related features:
- `YAL/step_once`: execute exactly the current requested step once
- `YAL/toggletrimpopup`: toggle the trim advice popup while a valid takeoff-trim target exists
- `Voice Advice Repeat Skip (cycles)` setting
- `Voice Advice Max Repeats (0/99=off)` setting

## Update Check and Save Notes
- YAL can check for both YAL and Zibo updates during X-Plane startup
- Stable builds use the stable YAL update feed by default
- `Show beta updates` switches the YAL update check to the prerelease beta/RC feed
- Periodic YAL flight save uses:
  - `Auto Flight Save Time`
  - `Auto Flight Save EFB Position(s)`
- To disable periodic YAL autosave, use `0` or `9999` for `Auto Flight Save Time`
- Autosave is skipped when X-Plane reports that the aircraft has crashed

## Useful Commands
Commonly used assignable commands include:
- `YAL/step_once`
- `YAL/toggleautofunctions`
- `YAL/toggleadviceonly`
- `YAL/toggleviewchanges`
- `YAL/toggleautotaxiing`
- `YAL/toggleautotaxipause`
- `YAL/toggletrimpopup`
- `YAL/setils`
- `YAL/setvref`
- `YAL/cycleprocedures`
- `YAL/skipprocedurestep`

All assignable commands are available in the X-Plane keyboard/joystick settings under the `YAL/...` group.

## Documentation
The full user manual is included as:
- `YAL Manual.pdf`

Use the PDF for the complete reference, including:
- all procedures
- all settings
- taxi map usage details
- taxi guidance and auto taxiing details
- SET ILS / approach handling details
- trim popup details

## Notes
- YAL remains largely idle when no supported aircraft is loaded.
- LevelUp 737 variants based on the Zibo systems should generally work in principle, but they are not part of the regular test scope.
- The plugin is designed to have very low FPS impact because the main logic runs on a timed loop rather than every frame.
