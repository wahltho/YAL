**Yet Another Linda (YAL) for Zibo Mod**

**VIRTUAL COPILOT PLUGIN FOR ZIBO MOD 738**

**(C) [@wahltho](https://forums.x-plane.org/profile/1083181-wahltho/) 2023/2024/2025**

**Installation:**

1\. Copy main YAL folder into Xplane plugins folder

2\. Check YAL settings in settings YAL settings window

**Requirements:**

• XPlane 11 or 12 (Windows, Mac/Intel/Arm, Linux)

• Aircraft B737-800 by Zibo

• Optional : X-Camera plugin

**Please Note:**

• This plugin basically has no FPS impact, because functions are only executed every second, not every frame.

• While flying other aircrafts than the Zibo B738, YAL will stay idle and all YAL’s menus and commands will be inactive

All custom commands created by this script can be found in YAL/…

Additionally most commands and all procedures are available via the **_Yet Another Linda_** sub-menu available in the **_Plugins_** Menu.

**1\. YAL Functions:**

**1.1 CUSTOM COMMANDS (CAN BE ASSIGNED TO BE JOYSTICK/KEYBOARD BUTTONS)**

0. Toggle Sim Freeze: Only freezes the physics, manipulation of controls, etc. still possible (in contrast to the pause function)

1\. Master Caution + FMS CLR: Mastercaution + FMS Clear + Altitude Horn Cutout

2\. Sync AP Heading with Ground Track: Syncs MCP Heading wih Groundtrack

3\. Both Wipers Up: Both Wipers Up 1 Step

4\. Both Wipers Down: Both Wipers Down 1 Step

5\. Toggle Taxi Lights : Toggles all Taxi Lights On/Off

6\. Toggle Collision Lights: Toggles Collision Lights On/Off

7\. Toggle Landing Lights: Toggles Landing Lights On/Off

8\. Toggle Logo Light: Toggles Logo Lights On/Off

9\. Toggle Runway Lights: Toggles Runway Lights

10\. Toggle Position Lights: Toggles Position Lights between Steady and Strobe

11\. Toggle Transponder: Toggles Transponder between Standby and TA/RA

12\. Toggle Both Flight Directors: Toggles Both Flightdirectors On/Off

13\. Toggle Both Weather Radars: Toggles Both Weather Radars On/Off

14\. Toggle Both Terrain Radars: Toggles Both Terrain Radars On/Off

15\. Toggle Window Heat: Toggles all for Window Heat Switches On/Off

16\. Toggle Probe Heat: Toggles Both Probe Heats On/Off

17\. Toggle Ice Protection: Toggles Ice Protection for Wing and Engines On/Off

18\. Copy Nav1/MMR1 to Nav2/MMR2: Copy Nav1/MMR1 course(, mode) and frequency to Nav2/MMR2

19\. Toggle All Automatic functions of YAL On/Off

20\. Toggle Voice Readback On/Off

**1.2 PROCEDURES (AVAILABLE VIA COMMANDS AND MENU ITEM):**

1\. Cockpit Initialisation (Performs several cockpit setup and initialisation tasks according to settings window entries and resets YAL (recommended between two flights without restart of XP).

2\. Cold and Dark Startup (to Turnaround State)

3\. APU Startup (automatically done during Cold and Dark Startup Procedure if not configured to use Ground Power/Ground Power not available)

4\. Engine Startup (requires APU running)

5\. Engine Shutdown

6\. Shutdown (to Cold and Dark)

7\. Tests

**PLEASE NOTE:**

For better immersion, during execution of procedures #2 - 7, view changes are performed to put view focus on the panel/switches currently used. Therefore certain quick looks or X-Camera views must be defined (see below). The viewnchanges can be generally switched of via settings menu. The script automatically recognises X-Camera installations and then uses the X-Camera views instead of quick looks.

**1.3 PROCEDURES (EXECUTED AUTOMATICALLY)**

1. **Before Taxi Procedure** (Triggered when Taxi Lights Set to On)

Seat Belt Sign On / Window Heat On / Probe Heat On / Both Starter CONT / Dome

Light Off / Both FDs On / Logo Light On

2. **Before Takeoff Procedure** (Triggered on departure runway and heading < 20 degree departure runway heading and ground speed 0)

Transponder TA/RA / Position Lights Strobe / Landing Lights On / Taxi Lights Off /

Runway Turnoff Lights On / Autobrake RTO

3. **After Takeoff Procedure**

Gear Up (200ft RA) / Gear Handle Off / Autobrake Off

4. **During Climb Procedure**

Baro Standard above Transition Altitude (automatic baro configurable via ini file) / Verify that Before Takeoff Procedure has been executed /

**5\. Flaps Up Handling according to FMC speeds**

6. **Above 10000 Feet Procedure** (altitude configurable via ini file)

Landing Lights Off / Logo Light Off / Seatbelt Sign Off / Both Starters Auto

7. **During Descent Procedure**

Set Speed Restriction 250 below 10000 feet (altitude configurable via ini file) / Set Baro to Local QNH (configurable via ini file) / Flaps Down Handling according to FMC speeds

**Below 10.000 feet Procedure** (Altitude configurable via ini file)

Seatbelt Sign On / Landings Lights On / Logo Light On / Autobrake 1 /

If ILS/GLS approach set Nav1/MMR1 to ILS/GLS course and frequency /

If ILS/DME approach set both Nav1/MMR1 and Nav1/MMR2 to ILS course and frequency / Set VRef30

**9\. Below 2.500 feet (RA) Procedure**

Both Starters Cont / Gear Down ( only if flaps >=15 already set)

**10\. Below 1.000 feet (RA) Procedure**

Taxilights On / Runway Turnoff Lights On / Set Missed Approach Altitude/ Speedbrake Auto / Set MCP Heading Destination Runway Heading / Gear Down / Configure flaps for landing (flaps 30 or 40, depending on APP settings)

**11\. After Landing Procedure** (Triggered after leaving destination runway and heading >

20 degree arrival runway heading or get(groundspeed) zero)

Transponder Standby / Position Lights Standby / Weather & Terrain Radar Off /

Landing Lights Off / Runway Turnoff Lights Off / Both Starter Auto / Both FDs Off /

Speedbrake Down / Flaps Up / Autobrake off Window and Probe Heat Off

**12\. At Parking Position Procedure** (triggered when Parking Brake is Set)

Taxi Lights Off / Logo Light Off / Dome Light Dim / Seatbelt Sign / Off

**1.4 AUTOMATIC FUNCTIONS (CONFIGURABLE VIA SETTINGS)**

1\. While On Ground and Taxilights Off: Set Trim according to calculated FMC Trim / Set Baro to Local QNH / Set MCP Speed to V2 / Set MCP Heading to Departure Runway Heading

2\. Automatic On/Off for Center Fuel Tank Pumps

3\. Set Cabin Cruise Altitude to FMC Cruise Altitude

4\. Set Cabin Landing Altitude to Destination Runway Altitude (rounded)

5\. Automatically set Pilot Barometer to standard above transition altitude and to local QNH below transition level

6\. Wing and Engine Anti Ice On/Off in case of ice detection below 30.000 feet and TAT < 10.

7\. Automatic Wiper Function depending on Rain Intensity below 250 knots

Voice Readback of basically all commands executed automatically or manually

(configurable via settings)

**1.5 VOICE CALLOUTS, E.G.**

1\. Passing 10.000 feet (depending on Lower Airspace Altitude set)

2\. Start of Descent

3\. Below 10.000 feet (depending on Lower Airspace Altitude set)

**2\. SETTINGS**

**If you change numerical values in settings, please confirm with Return-Key after entering the values, otherwise the new value will not be accepted.**

The Settings window can be opened via the menu **Plugins/_Yet Another Linda/Settings_**.

**General**

• **Use Ground Power when available instead of APU**

During Cold & Dark Startup and Engine Shutdown Procedure Ground Power will be used, if available. APU startup has to be done separately before Engine Startup.

• **Command Voice Readback**

Command Voice Readback for almost all actions performed (procedures, commands,

switches, actions)

• **Automatic Functions**

Turn Automatic Functions On/Off (see above for details)

• **Sim exit after Pause at TOD**

Time in seconds after which XPlane will exit automatically after pausing at TOD. This presumes, that you have automatic save activated. It makes no sense to have the sim potentially running for hours in case of unforeseen real world events.

• **Override Wake Effects** (only with Plane 12)

Suppresses the wake effects from other aircrafts

• **Automatic Anti Icing**

Automatic Wing / Engine Anti Ice in case of ice detection. Works only below 30.000 feet and TAT < 10.

• **Automatic Wiper**

Automatically Turns both wipers on/and off according to rain intensity (only available,

APU or ground power connected or Engines running). Only available below 250 knots.

• **Automatic Center Tank Handling**

Automatically Handles Center Tank Fuel Pump Switch. Switches will be automatically turned on, if center tank fuel quantity is above 1.000 lbs / 500 kg. Switches will be automatically turned off, if center tank fuel quantity is below 1.000 lbs / 500 kg. Turning off below 1.000 lbs / 500 kg can be manually overridden until fuel pressure becomes low.

• **Automatic Baro Settings**

Pilot Barometer is set automatically to standard above transition altitude and to local

QNH below transition level

• **View Changes during Procedures**

View changes to be executed during procedures for better immersion. This continuously sets focus to the panel currently being used in the resection procedure.

Requires that quick views for the respective procedures are defined.

**Customising**

• **Set Speed Restriction 250**

Sets the speed below Lower Airspace Altitude to 250 (instead of 240 which is Zibo Mod default).

• **Set Vref 30**

Automatically set Approach Reference to Vref 30

• **Lower Airspace Altitude (feet)**

Lower Airspace Altitude to be used e.g. 10000 or 18000 feet (if this entry is undefined,

then 10000 feet is taken as default)

• **Bank Angle Maximum**

Maximum Bank Angle set during Cockpit Initialisation Procedure (Min = 1, Max = 4)

• **Lower Display Unit**

Set Lower Display Unit during Cockpit Initialisation Procedure

• **Default Transponder Code**

Default Transponder Code to be set during Cockpit Initialisation Procedure.
In case that the value is set to Zero (you have to enter „0000“ and press return), the Transponder will not be set automatically to Standby or TA/RA in case that automatic functions are activated.

**Views**

• Quick views for the respective panels, which are used in procedures. Only relevant, if setting View Changes during Procedures is active.

• YALs use the Quick Look natively defined in XPlane or views configured by the plugin X-Camera (if installed).

PLEASE NOTE:  The numbers of the 3-D cockpit locations are relevant for the YAL view settings and not the keyboard numbers the 3-D cockpit locations are assigned to.

Here is an example:

Overhead panel view is assigned to "3-D cockpit location #4". This has been done using the keyboard command "Memorize 3-D cockpit location #4". Keyboard command "Go to save 3-D cockpit location #4" has been assigned to key "4".

In the YAL settings window "4" has to be entered for the Overhead Panel view, because this is assigned to "3-D cockpit location #4", and NOT because it is assigned to key "4". If "3-D cockpit location #4" would be assigned to key "5", still "4" would have to be entered in the YAL settings window.

**Instrument Panel Brightness**

• Individual settings for each of the individual instrument and cockpit lights. These individual settings are ignored, if **Ignore All Brightness Settings** is selected. In this case no changes will be done.
