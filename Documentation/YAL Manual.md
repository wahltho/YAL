# Yet Another Linda (YAL) for Zibo Mod - User Manual
Version 4.6b4 (based on features as of February 2026)
(C) WAHLTHO 2023-2026
VIRTUAL COPILOT PLUGIN FOR ZIBO MOD 738

## 1. Installation & Requirements
**Installation**
1. Copy the main YAL folder into your X-Plane 11/12 `Resources/plugins` folder.
2. Launch X-Plane and configure YAL via the settings window at `Plugins -> Yet Another Linda -> Settings`.

**Requirements**
- X-Plane 11 or 12 (Windows, Mac/Intel/Arm, Linux)
- Aircraft: B737-800 by Zibo
- Optional: X-Camera plugin (will be detected automatically)

**Please Note**
- YAL has virtually no FPS impact as its main functions run once per second, not every frame.
- When flying aircraft other than the Zibo B738, YAL remains idle and all its menus are inactive.
- All custom commands for key/joystick assignment can be found in the X-Plane keyboard/joystick settings under the `YAL/...` group.

## 2. Custom Commands
These commands can be assigned to keyboard keys or joystick buttons in the X-Plane settings menu.

### Core Functions
- Reset: Resynchronizes YAL's internal state with the current aircraft state. Use this if a procedure seems stuck or the plugin appears out of sync.
- Reset for New Flight: Completely resets all procedure progress for a new flight. This should be used at the gate after landing to ensure a clean start for the next leg.
- Cycle Through Procedures: Manually triggers the next logical, uncompleted procedure (e.g., from "Engine Start" to "Before Taxi").
- Skip Procedure Step: Skips the current active step in a running procedure.
- Abort Procedure: Immediately stops the currently active procedure.

### General Aircraft Control
- Toggle Sim Freeze: Freezes the aircraft's motion but allows you to interact with cockpit controls.
- Master Caution + FMS CLR: Acknowledges Master Caution, clears FMC messages, and silences the altitude alert horn.
- Sync AP Heading with Ground Track: Sets the MCP heading dial to the aircraft's current ground track.
- Copy NAV1/MMR1 to NAV2/MMR2: Copies the active frequency and course from the captain's side to the first officer's side.

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

### Plugin Control
- Toggle Auto Functions: A master switch to enable or disable all automatic functions of YAL.
- Toggle Voice Readback: Enables or disables voice confirmations for actions.
- Toggle Voice Advice Only: Switches YAL between executing actions automatically and only giving verbal advice.
- Toggle View Changes: Enables/disables automatic cockpit view changes during procedures.

## 3. Procedures
### Manually Triggered Procedures
These checklists can be started at any time via the `Plugins -> Yet Another Linda` menu or by assigning their corresponding `YAL/...` command to a key.

- Cold and Dark Startup: A full procedure from a completely powered-down state to a "Turnaround State" (APU running, systems ready for engine start).
- Cockpit Initialization: Prepares the cockpit for a new flight by setting lights, displays, and systems according to your preferences. It also resets the FMC and can trigger a flight plan import if YANSH is installed.
- APU Startup: Starts the APU and configures the electrical and bleed air systems.
- Engine Startup: Performs the full two-engine start sequence. Requires the APU to be running and providing bleed air.
- Engine Shutdown: A flexible procedure that can be used for a quick turnaround (leaving the APU running) or as part of a final shutdown.
- Shutdown: Powers down all aircraft systems and returns the aircraft to a "Cold & Dark" state.
- Tests: Executes a sequence of system tests (Fire, Stall Warning, etc.).

### Automatically Triggered Procedures
These procedures are triggered automatically based on specific pilot actions or flight parameters.

#### Before Taxi Procedure
Trigger: Taxi lights are switched ON and both engines are running.
Actions: Sets probe/window heat, starters to CONT, FDs on, etc.

#### Before Takeoff Procedure
Trigger: Aircraft is on the runway and aligned; speed is zero (TA/RA is no longer required).
Actions: Sets position lights to STROBE, landing lights ON, autobrake to RTO.

#### After Takeoff Procedure
Trigger: Automatically after liftoff.
Actions: Retracts gear above 200 ft RA and disarms the autobrake.

#### During Climb Procedure
Trigger: During the climb phase.
Actions: Sets Baro to Standard above transition altitude, handles flap retraction according to FMC speeds.

#### Above 10,000 Feet Procedure
Trigger: Climbing through the "Lower Airspace Altitude" (default 10,000 ft).
Actions: Retracts landing lights, turns off seatbelt sign, sets engine starters to AUTO.

#### During Descent Procedure
Trigger: During the descent phase.
Actions: Sets speed restrictions in the FMC, sets local QNH below transition level, handles flap extension.

#### Below 10,000 Feet Procedure
Trigger: Descending through the "Lower Airspace Altitude".
Actions: Turns on landing lights and seatbelt sign, sets the autobrake, and tunes ILS/GLS frequencies/courses.

#### Below 2,500 Feet (RA) Procedure
Trigger: Descending through 2,500 ft radio altitude.
Actions: Sets starters to CONT, extends landing gear (if flaps are set accordingly).

#### Below 1,000 Feet (RA) Procedure
Trigger: Descending through 1,000 ft radio altitude.
Actions: Sets final landing configuration (lights, speedbrake armed, landing flaps).

#### After Landing Procedure
Trigger: After vacating the runway.
Actions: Configures the aircraft for taxiing to the gate (lights, transponder, flaps up, etc.).

#### At Parking Position Procedure
Trigger: Parking brake is set at the gate.
Actions: Turns off taxi lights, seatbelt signs, and prepares for engine shutdown.

#### EEC/FADEC Check (Cockpit Init + Engine Start)
If EEC/FADEC is OFF while engines are running, YAL prompts a check (voice‑only unless Auto Functions are enabled). In Auto mode YAL sets both EECs ON. If EECs are already ON, the step is skipped (no delay).

## 4. Settings
The settings window allows detailed customization of all automatic features.

### General
- Use Ground Power...: If available, the plugin will use ground power instead of starting the APU during the Cold & Dark startup.
- Command Voice Readback: Provides voice announcements for most actions performed by the plugin.
- Automatic Functions: A master switch for all automatic procedures and background tasks.
- FMC Automation: Allows YAL to automate FMC page changes and FMC data entries.
- Heading Sync Interval: Repeats MCP heading sync at the given interval (seconds). Set 0 to disable.
- Hoppie ID: Sets the Hoppie logon used by the in‑sim Hoppie integration.
- Sim exit after Pause at TOD: If the sim is paused at the Top of Descent, it will automatically save and quit after the specified number of seconds (9999 to disable).
- Override Wake Effects: Suppresses wake turbulence effects from other aircraft.
- Automatic Anti Icing: Automatically enables wing and engine anti-ice when icing is detected.
- Automatic Wipers: Automatically controls wiper speed based on rain intensity.
- Automatic Center Tank Handling: Manages the center tank fuel pumps automatically.
- Automatic Baro Settings: Sets the altimeter to Standard or local QNH when passing transition altitude/level.
- Automatic Fueling (requires YANSH): When Automatic Functions are enabled, this automatically refuels the aircraft to match the Simbrief flight plan's ramp fuel during the Cockpit Initialization Procedure.
- View Changes during Procedures: Allows YAL to automatically switch to relevant cockpit views during procedures.
- Auto Taxi Guidance (Voice): Enables spoken taxi callouts.
- Auto Taxi Guidance (Visual): Enables the taxi guidance popup (independent of the taxi map window).

### Customising
- Set Speed Restriction 250: Automatically sets the FMC speed restriction below 10,000 ft to 250 knots.
- Set Vref 30: Automatically configures the FMC for a Flaps 30 landing.
- Lower Airspace Altitude (feet): Sets the altitude for the "Above/Below 10000" procedures.
- Maximum Bank Angle (1-4): Sets the bank angle selector during cockpit initialization.
- Set Lower Display Unit: Configures the lower DU to your preferred setting on startup.
- Default Transponder Code: Sets a default squawk code during initialization.

### Views
- Assigns the corresponding X-Plane Quick Look or X-Camera view numbers for automatic view changes.
- Apply QV0 to Default View: Updates the aircraft default view to match Quick View 0.

### Instrument Panel Brightness
- Allows you to pre-configure all panel and display brightness levels, which will be applied during the Cockpit Initialization procedure.
- Ignore All Brightness Settings: Prevents YAL from making any changes to panel lighting.

### Misc
- Debug mode log: Enables verbose logging to the Log.txt file for troubleshooting.

## 5. Taxi Map & Routing
### Overview
The Taxi Map provides airport layout, aircraft position, and routing guidance for departure and arrival. It supports automatic routing as well as manual routing with edit and draw modes. Taxi guidance can be spoken and/or shown in the visual popup.

### Opening the Taxi Map
Use `Plugins -> Yet Another Linda -> Taxi Map` (or the assigned command) to open the map. The map can be used in-flight to pre-plan arrival taxi routes.

### Toolbar and Controls
- ARR / DEP: Toggle arrival or departure mode.
- NORTH UP / HDG UP: Toggle map orientation.
- ZOOM - / ZOOM +: Zoom out or in.
- FIT: Fit the map to the current airport bounds.
- CENTER: Center on the aircraft (or bounds if the aircraft is not valid).
- AUTO: Return to automatic routing. Clears manual edits, draw route, undo history, and resets the route.
- EDIT / EDIT ON: Toggle edit mode for the current route.
- DRAW NEW / DRAWING: Start a new manual route (freehand draw).
- UNDO: Undo the last edit or draw action.
- A- / A+: Decrease or increase taxiway label font size.

### Automatic Routing (AUTO)
AUTO computes a route using the airport taxiway network. For departure, the route leads to the selected runway entry/hold-short. For arrival, the route leads to the selected or nearest suitable gate. The route updates automatically if the destination or runway changes.

### Edit Mode (EDIT)
Edit mode lets you adjust an existing route using handles. You can drag start/end handles and intermediate points to refine the route. Right-click deletes a point. Disable EDIT to resume normal guidance.

### Draw Mode (DRAW NEW)
Draw creates a freehand route that follows your clicked points.

- Click to place the start point, then click successive points to extend the route.
- A continuous line is drawn once there are at least two points.
- Shift-click inserts a point between the two nearest existing points (if close to the line).
- Drag points to move them.
- Right-click a point to delete it.
- Use AUTO to revert to automatic routing.

### Taxi Guidance (Voice + Visual)
Taxi guidance can be delivered via audio callouts and/or the visual popup. The popup is independent of the map window and can be shown even when the taxi map is closed.

Typical callouts include:
- Turn left/right on Taxiway ...
- Continue straight on Taxiway ...
- Leave RWY ... to left/right on Taxiway ...
- Runway crossing warnings
- Turn left/right on RWY ...
- Taxi complete
- Gate proximity callouts (e.g., "Gate in 30 meters", "Gate in 10 meters", "Stop")

### Tips and Notes
- While EDIT or DRAW is active, guidance may be suppressed to avoid conflicting callouts. Disable EDIT/DRAW to resume guidance.
- If the map is blank after reloads, ensure a valid DEP/DES ICAO is set or use the nearest airport on the ground.
- For arrival planning in-flight, use DRAW or EDIT to build a custom route before landing.
- When Tobii eye tracking is active, view changes are suppressed to avoid view‑control conflicts.

## 6. Navigation & Weather Enhancements (since 4.3)
- Approach course handling: consistent true vs mag logic, with RNAV/LPV/GLS prioritizing FMS final‑leg course; LDA/LOC/IGS approaches supported.
- METAR parsing upgrades: SLP and T‑group temps, KM and mixed SM visibility, structured RVR; speech uses active‑runway RVR and respects QNH units.

## 7. Taxi Guidance Enhancements (since 4.3)
- Runway‑exit callouts include left/right ("Leave RWY ... to left/right") and runway‑crossing warnings.
- Departure runway entry callouts ("Turn left/right on departure RWY ...") with queueing so they are not overwritten by "Taxi complete".
- Freehand routes can infer taxiway labels from nearby navdata edges for guidance.
