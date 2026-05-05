# Yet Another Linda (YAL) for Zibo Mod - User Manual
Version 4.6
(C) WAHLTHO 2023-2026
VIRTUAL COPILOT PLUGIN FOR ZIBO MOD 738

## 1. Installation & Requirements
**Installation**
1. Copy the main YAL folder into your X-Plane 11/12 `Resources/plugins` folder.
2. Launch X-Plane and configure YAL via the settings window at `Plugins -> Yet Another Linda -> Settings`.

**Requirements**
- X-Plane 11 or 12 (Windows, Mac/Intel/Arm, Linux)
- Primary support target: B737-800 by Zibo
- Optional: X-Camera plugin (will be detected automatically)

**Optional Integrations**
- YANSH (SimBrief import and auto-fueling).
- BetterPushback (pushback planning and plan hints). Full plan detection requires a BPB build exposing `bp/plan_complete`.
- X-Camera (view switching).
- Tobii eye tracker (supported; view changes are suppressed while active to avoid conflicts).
- YAL Hoppie Helper (optional CPDLC/Hoppie bridge).

**Please Note**
- YAL has virtually no FPS impact as its main functions run once per second, not every frame.
- When flying aircraft other than the supported Zibo aircraft, YAL remains idle and all its menus are inactive.
- LevelUp 737 variants based on the Zibo systems should generally work in principle, but they are not part of the regular test scope.
- All custom commands for key/joystick assignment can be found in the X-Plane keyboard/joystick settings under the `YAL/...` group.

## 2. Custom Commands
These commands can be assigned to keyboard keys or joystick buttons in the X-Plane settings menu.

### Core Functions
- Reset: Resynchronizes YAL's internal state with the current aircraft state.
- Reset for New Flight: Completely resets procedure progress for the next leg.
- Cycle Through Procedures: Manually triggers the next logical uncompleted procedure.
- Step Once (Advice Only): In Voice Advice Only mode, executes the current step exactly once, then returns to advice-only behavior.
- Skip Procedure Step: Skips the current active step in a running procedure.
- Skip Procedure: Marks the whole current procedure as complete.
- Abort Procedure: Immediately stops the currently active procedure.

### General Aircraft Control
- Toggle Sim Freeze: Freezes aircraft motion while allowing cockpit interaction.
- Master Caution + FMS CLR: Acknowledges Master Caution, clears FMC messages, and silences the altitude alert horn.
- Sync AP Heading with Ground Track: Sets the MCP heading dial to the aircraft's current ground track.
- Copy NAV1/MMR1 to NAV2/MMR2: Copies active frequency/channel and course from the captain's side to the FO side.

### Lights & Wipers
- Both Wipers Up / Down: Moves both wipers one step up or down.
- Toggle Taxi Lights: Toggles the taxi lights on/off.
- Toggle Collision Lights: Toggles the beacon lights on/off.
- Toggle Landing Lights: Toggles all landing lights on/off.
- Toggle Logo Light: Toggles the logo light on/off.
- Toggle Runway Lights: Toggles the runway turnoff lights on/off.
- Toggle Position Lights: Cycles the position lights between STEADY and STROBE & STEADY.

### Systems
- Toggle Transponder: Toggles the transponder between STANDBY and TA/RA.
- Toggle Both Flight Directors: Toggles both FDs on/off.
- Toggle Both Weather Radars: Toggles both WXR displays on/off.
- Toggle Both Terrain Radars: Toggles both TERR displays on/off.
- Toggle Window Heat: Toggles all four window heat switches on/off.
- Toggle Probe Heat: Toggles both probe heat switches on/off.
- Toggle Ice Protection: Toggles wing and engine anti-ice systems on/off.

### Plugin / Taxi Control
- Toggle Auto Functions: Master switch for automatic YAL procedures and background tasks.
- Toggle Voice Readback: Enables or disables voice confirmations for actions.
- Toggle Voice Advice Only: Switches YAL between automatic execution and spoken guidance only.
- Toggle View Changes: Enables/disables automatic cockpit view changes during procedures.
- Toggle Auto Taxiing: Enables/disables auto taxiing.
- Toggle Auto Taxi Pause: Temporarily pauses/resumes auto taxiing.
- Toggle Trim Advice Window: Shows or hides the trim popup while a valid takeoff-trim target exists.
- Speak Departure METAR / Speak Destination METAR: Reads the currently loaded METAR aloud.

## 3. Procedures
### Manually Triggered Procedures
These checklists can be started at any time via the `Plugins -> Yet Another Linda` menu or by assigning their corresponding `YAL/...` command to a key.

- Cold and Dark Startup: Full procedure from a powered-down aircraft to a turnaround-ready state.
- Cockpit Initialization: Prepares the cockpit for a new flight, resets the FMC, applies selected preferences, and can trigger a flight-plan import if YANSH is installed.
- APU Startup: Starts the APU and configures electrical and bleed air systems.
- Engine Startup: Performs the full two-engine start sequence.
- Engine Shutdown: Flexible procedure for turnaround or final shutdown.
- Shutdown: Returns the aircraft to a cold-and-dark state.
- Tests: Executes a sequence of system tests.
- Set ILS/GLS Freq/Course: Can be run manually and is also called automatically during approach setup.
- Set Landing Flaps/VREF: Sets or verifies landing flap, VREF and autobrake targets.
- Set Takeoff Flaps: Sets or verifies takeoff flap setting.

### Automatically Triggered Procedures
#### Before Taxi Procedure
Trigger: Taxi lights ON and both engines running.
Actions: Probe/window heat, starter mode, flight directors, and other standard taxi configuration.

#### Before Takeoff Procedure
Trigger: Aircraft is on the departure runway, aligned, and stopped.
Actions: Position lights to STROBE, landing lights ON, taxi lights OFF, autobrake to RTO, final takeoff-trim check, MCP speed/heading checks, LNAV/VNAV/A/T checks, and wind report.

#### After Takeoff Procedure
Trigger: Automatically after liftoff.
Actions: Retracts gear above 200 ft RA and disarms autobrake.

#### During Climb Procedure
Trigger: During climb.
Actions: Standard climb housekeeping, baro to standard above transition altitude, flap handling according to FMC speeds.

#### Above 10,000 Feet Procedure
Trigger: Climbing through the configured lower-airspace altitude.
Actions: Retracts landing lights, turns off seatbelt sign, sets starters to AUTO.

#### During Descent Procedure
Trigger: During descent.
Actions: Descent housekeeping, speed restrictions/FMC support, local QNH below transition level, flap handling.

#### Below 10,000 Feet Procedure
Trigger: Descending through the configured lower-airspace altitude.
Actions: Landing lights, seatbelt sign, autobrake, and approach setup including `SET ILS` / `SET VREF` / wind-correction logic as configured.

#### Below 2,500 Feet / 1,000 Feet Procedures
Trigger: Final approach gates using a mix of radio altitude and airfield-relative logic.
Actions: Landing gear, starter CONT, final landing configuration, lights and speedbrake checks.

#### After Landing Procedure
Trigger: After runway vacate.
Actions: Taxi configuration, arrival taxi guidance/routing preparation, and post-landing cleanup.

#### At Parking Position Procedure
Trigger: Parking brake set near the gate/parking position.
Actions: Turns off taxi lights and seatbelt signs and prepares for engine shutdown.

#### EEC/FADEC Check (Cockpit Init + Engine Start)
If EEC/FADEC is OFF while engines are running, YAL prompts a check (voice-only unless Auto Functions are enabled). In Auto mode YAL sets both EECs ON. If EECs are already ON, the step is skipped.

## 4. Settings
The settings window allows detailed customization of all automatic features.

### General
- Use Ground Power when available instead APU: Prefer GPU over APU when available.
- Command Voice Readback: Voice confirmations for actions performed by YAL.
- Automatic Functions: Master switch for automatic procedures and background tasks.
- FMC Automation: Allows YAL to automate FMC page changes and FMC data entries when a procedure supports it.
- Voice Advice Only: YAL gives spoken guidance but does not perform cockpit actions automatically.
- Voice Advice Repeat Skip (cycles): Only repeats the same advice every Nth cycle.
- Voice Advice Max Repeats (0/99=off): Limits identical repeated advice for one step. When the limit is reached, the step is skipped automatically.
- Voice Advice Trim Popup: Enables the trim popup during the takeoff trim advice step.
- Auto Taxi Guidance (voice): Enables spoken taxi guidance.
- Auto Taxi Guidance (Visual): Enables the independent taxi popup.
- Auto Taxiing (Experimental): Enables YAL auto taxiing on supported routes.
- ATIS/CPDLC to Voice: Speaks supported Hoppie/ATIS content if the helper plugin is installed.
- BetterPushback Integration: Enables BPB plan detection and pushback-aware taxi routing logic.
- YANSH Integration / YANSH Automatic Fueling: Enables YANSH integration and optional auto-fueling.
- Hoppie ID: Callsign/login for Hoppie integration.
- Show beta updates: Uses the prerelease update feed for beta/RC builds. Keep it off for the stable channel.
- Check YAL/Zibo updates on startup: Checks for new YAL and Zibo versions during X-Plane startup and shows a popup if an update is available.
- Sim exit after Pause at TOD (0-9999 sec): Delay before auto-save/quit after TOD pause.
- Auto Flight Save Time (0 or 9999 = off): Periodic YAL flight save interval. Autosave is skipped after an aircraft crash state is reported by X-Plane.
- Auto Flight Save EFB Position(s) (ignored if save is off): Save slot/EFB target used by periodic YAL flight saves.
- Disable XP Wake Effects: Suppresses X-Plane wake effects from other aircraft.
- XP Runway Friction Clamp: Enables runway-friction clamp logic.
- Automatic Anti Icing: Enables wing/engine anti-ice automatically when icing is detected.
- Automatic Wipers: Controls wiper speed based on rain intensity.
- Automatic Baro Settings: Sets local QNH or standard baro where appropriate.
- Automatic Center Tank Handling: Manages center tank pumps automatically.
- Automatic Chocks and Parking Brake: Applies automatic chocks/parking brake handling where supported.
- Automatic Flap Handling: Enables automatic flap handling features.
- View Changes during Procedures: Allows automatic cockpit view switching.

### Customising
- Set Speed Restriction 250: Applies the standard restriction below 10,000 ft.
- Set Approach Flaps, Vref, Autobrake: Enables automatic landing flap/VREF/autobrake handling.
- Custom Calculation for Flaps, Vref, Autobrake: Uses YAL's custom approach calculation logic instead of the basic preset path.
- Lower Airspace Altitude (feet): Threshold used for above/below 10,000 procedures.
- Maximum Bank Angle (1-4): Desired bank angle selector setting.
- Packs Restore Altitude (ft AGL): Altitude gate for restoring packs after takeoff.
- Set Lower Display Unit: Lower DU selection used during cockpit initialization.
- Default Transponder Code: Default squawk used during initialization.
- Gear Down Flaps: Flap setting that allows YAL to extend the landing gear automatically in final approach logic.
- Hide Captain/FO EFBs: Hides the EFBs during cockpit initialization.

### Views
- Main Panel / Pedestal / Overhead / FMS / Throttle / Upper Overhead View: Quick Look or X-Camera view numbers used by procedure view changes.
- Apply QV0 to Default View and CG-related quick-view tools remain available where supported.
- When Tobii eye tracking is active, automatic view changes are suppressed.

### Instrument Panel Brightness
- Allows you to pre-configure panel/display brightness values used during cockpit initialization.
- Ignore All Brightness Settings: Prevents YAL from changing panel lighting.

### Misc
- Debug mode log: Enables verbose logging for troubleshooting.

## 5. Taxi Map, Routing and Guidance
### Overview
The Taxi Map shows the airport layout, the aircraft position and the active taxi route. It can be used both on the ground and in flight to prepare a departure or arrival taxi plan.

### Opening the Taxi Map
Open the map via `Plugins -> Yet Another Linda -> Taxi Map` or an assigned command. The map can remain closed while taxi guidance continues through the popup and voice callouts.

### Toolbar and Controls
- ARR / DEP: Switch between arrival and departure mode.
- SRC AUTO / SRC SCN / SRC GLB: Choose which taxi data source should be used.
  - `AUTO`: lets YAL decide between scenery and global data.
  - `SCN`: use scenery/add-on airport data.
  - `GLB`: use global airport data.
- NORTH UP / HDG UP: Change map orientation.
- ZOOM - / ZOOM +: Change zoom level.
- FIT: Fit the route or airport into the window.
- CENTER / FOLLOW: Center once on the aircraft or follow it on the ground.
- AUTO: Return to automatic routing and clear manual route edits.
- MANUAL: Keep the current route and prevent automatic replacement.
- EDIT / EDIT ON: Edit the current route.
- DRAW NEW / DRAWING: Draw a new custom route.
- UNDO: Undo the last edit or draw action.
- A- / A+: Change taxiway label size.

### Automatic Routing
For departure, YAL routes from the current stand or pushback end position to the selected runway entry or hold-short point. For arrival, YAL routes from the runway exit area to the selected gate or another suitable nearby gate.

If the aircraft deviates far enough from the planned route, YAL can recalculate from the current position. With BetterPushback installed, YAL can also use the pushback plan to improve the initial departure route. In `AUTO` source mode, YAL may also fall back between scenery/add-on and global airport data if one source produces an invalid route.

### Manual Routing
#### EDIT
Use EDIT to adjust an automatically generated or already existing route.
- Drag handles to reshape the route.
- Drag the start or end handle to change the route start or destination.
- Right-click a point to delete it.
- Turn EDIT off to resume normal guidance.

#### DRAW NEW
Use DRAW NEW to create a custom freehand route.
- Click to add points in the order of the route.
- The first point becomes the route start, each further click extends the route, and the last point is the current route end.
- If the last click hits a ramp/gate marker, YAL treats it as the route end ramp/gate.
- Drag a waypoint to move it.
- Right-click a waypoint to delete it.
- Use MANUAL if you want to keep the custom route.
- Use AUTO to return to automatic routing.

### Taxi Guidance
Taxi guidance can be spoken, shown in the taxi popup, or both. Typical guidance includes:
- Turn left/right on Taxiway ...
- Continue straight on Taxiway ...
- Taxi via Taxiway ...
- Leave RWY ... to left/right on Taxiway ...
- Runway crossing warnings
- Enter departure runway ...
- Turn to backtrack on Runway ...
- Backtrack on Runway ...
- Align with departure Runway ...
- Threshold ahead in ... meters
- Taxi to Gate ...
- Gate in ... meters / Stop
- Taxi complete

Taxiway letters are spoken using NATO spelling where appropriate. The taxi popup can be moved and its position is saved.

### Auto Taxiing (Experimental)
Auto Taxiing uses the active taxi route to steer and control taxi speed.
- Enable it with the setting `Auto Taxiing (Experimental)` or the `Toggle Auto Taxiing` command.
- Use `Toggle Auto Taxi Pause` to pause or resume it.
- Voice and visual taxi guidance can be used together with Auto Taxiing.
- Auto Taxiing should always be monitored by the pilot.

### Arrival Gate Guidance
When taxiing to the gate, YAL can provide an initial `Taxi to Gate ...` call, later turn/distance callouts and stop guidance. Taxiing is considered complete when the aircraft reaches the parking position and/or the parking brake is set near the destination ramp. If the planned stand is clearly wrong and another nearby stand is obviously the one being used, YAL may retarget to the nearer stand.

## 6. Navigation, Weather and Approach Handling
### SET ILS / Approach Setup
YAL supports ILS, LOC, LDA, IGS, GLS, LPV and RNAV approach setup.

In Auto mode, YAL can set the relevant frequencies, channels and courses automatically. In Voice Advice Only mode, YAL announces the targets for manual entry. A one-time FMC page reminder may still be given where useful, but the procedure no longer depends on the FMC page staying open.

Not every approach has a tunable frequency or channel. For RNAV approaches, YAL may explicitly report that no tunable approach frequency/channel exists and then announce the final approach course instead.

### Approach Course Handling
YAL announces and sets approach courses according to the selected approach and runway. It correctly distinguishes between magnetic and true-course cases where required and supports non-ILS approach families such as LOC, LDA, IGS, GLS, LPV and RNAV.

### Weather / METAR Handling
YAL uses METAR data for weather-related advice such as QNH, visibility and runway-related RVR where available. Departure and nearest-airport METAR refreshes are limited to preflight. Destination METAR remains available for descent and arrival logic.

### Update Check
If enabled, YAL checks at startup whether newer YAL or Zibo versions are available and shows an update popup if appropriate. Stable builds use the stable YAL feed by default; the `Show beta updates` setting switches YAL to the prerelease feed used for beta/RC builds.

## 7. Trim Advice Popup and Voice Advice Controls
### Trim Advice Popup
The trim popup is intended to make manual takeoff-trim setting easier in Voice Advice Only mode.
- It shows the current trim, the target trim and an up/down direction arrow.
- It opens automatically with the Before Takeoff takeoff-trim advice in Voice Advice Only mode.
- It closes about 5 seconds after the target is reached or after the last trim input.
- Its position is saved.
- The `Toggle Trim Advice Window` command can open it manually while a valid takeoff-trim target exists. In that case it remains open until toggled off or until the trim context ends.

### Voice Advice Repeat Controls
- `Voice Advice Repeat Skip (cycles)` reduces how often the same advice is repeated.
- `Voice Advice Max Repeats` can stop endless repetition by automatically skipping a step after the configured number of identical repeats. Use `0` or `99` to disable this limit.
- `Step Once (Advice Only)` executes exactly the current requested step once and is intended for use in Voice Advice Only mode.
