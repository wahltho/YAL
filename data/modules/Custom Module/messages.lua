local P = {}
messages = P -- package name


local lang = get(globalProperty("sim/operation/prefs/misc/language")) + 1

local english = {
    UPDATEAVAILABLE = 'UPDATE AVAILABLE',
    SETUP = 'Settings',
    
    GENERAL = 'General',
    VOICEREADBACK = 'Command Voice Readback',
    AUTOFUNCTIONS = 'Automatic Functions',
    FMCAUTOMATION = 'FMC Automation',
    HEADINGSYNCINTERVAL = 'Heading Sync Interval (sec, 0=off)',
    VOICEADVICEONLY = 'Voice Advice Only',
    AUTOTAXIGUIDANCE = 'Auto Taxi Guidance (voice)',
    VISUALTAXIGUIDANCE = 'Auto Taxi Guidance (Visual)',
    AUTOTAXIING = 'Auto Taxiing (Experimental)',
    HOPPIEVOICE = 'ATIS/CPDLC to Voice',
    BPBINTEGRATION = 'BetterPushback Integration',
    YANSHINTEGRATION = 'YANSH Integration',
    AUTOFUELING = 'YANSH Automatic Fueling',
    HOPPIEID = 'Hoppie ID',
    DEBUGMODE = 'Debug mode log',
    SHOWBETAUPDATES = 'Show beta updates',
    AUTOUPDATECHECK = 'Check YAL/Zibo updates on startup',
    TODPAUSEQUITTIME = 'Sim exit after Pause at TOD (0-9999 sec)',
    SAVETIME = 'Auto Flight Save Time (0-9999 sec)',
    SAVENUMBER = 'Auto Flight Save EFB Position(s)',
    WAKEOVERRIDE = 'Disable XP Wake Effects',
    RUNWAYFRICTIONCLAMP = 'XP Runway Friction Clamp',
    AUTOANTIICE = 'Automatic Anti Icing',
    AUTOWIPER = 'Automatic Wipers',
    AUTOBARO = 'Automatic Baro Settings',
    AUTOCENTERTANKHANDLING = 'Automatic Center Tank Handling',
    AUTOCHOCKSPB = 'Automatic Chocks and Parking Brake',
    AUTOFLAPS = 'Automatic Flap Handling',
    VIEWCHANGES = 'View Changes during Procedures',
    USEGROUNDPOWER = 'Use Ground Power when available instead APU',

    CUSTOMIZE = 'Customising',
    SPEEDRESTR250 = 'Set Speed Restriction 250',
    VREF30 = 'Set Approach Flaps, Vref, Autobrake',
    CUSTOMAPPROACHCALC = 'Custom Calculation for Flaps, Vref, Autobrake',
    LOWERAIRSPACEALT = 'Lower Airspace Altitude (feet)',
    BANKANGLEMAX = 'Maximum Bank Angle (1-4)',
    PACKSRESTOREALT = 'Packs Restore Altitude (ft AGL)',
    LOWERDU = 'Set Lower Display Unit',
    TRANSPONDERCODE = 'Default Transponder Code',
    GEARDOWNFLAPS = 'Gear Down Flaps',

    VIEWS = 'Views',
    VIEWMAINPANEL = 'Main Panel View',
    VIEWPEDESTAL = 'Pedestal Panel View',
    VIEWOVERHEADPANEL = 'Overhead Panel View',
    VIEWFMS = 'FMS View',
    VIEWTHROTTLE = 'Throttle View',
    VIEWUPPEROVERHEADPANEL = 'Upper Overhead Panel View',

    BRIGHTNESS = 'Instrument Panel Brightness',
    BRIGHTMAINPANEL = 'Main Panel',
    BRIGHTOVERHEAD = 'Overhead Panel',
    BRIGHTPEDESTRAL = 'Pedestal Panel',
    GENBRIGHTBACKGROUND = 'Background',
    GENBRIGHTAFDSFLOOD = 'AFDS Flood',
    GENBRIGHTPEDESTRALFLOOD = 'Pedestal Flood',
    INSTRBRIGHTOUTBDDU = 'Outbound Display Unit',
    INSTRBRIGHTINBDDU = 'Inner Display Unit',
    INSTRBRIGHTUPPERDU = 'Upper Display Unit',
    INSTRBRIGHTLOWDU = 'Lower Display Unit',
    INSTRBRIGHTINBDDUS = 'Inner Display Unit2',
    IGNOREALLBRIGHTHNESSSETTINGS = 'Ignore All Brightness Settings',
    HIDEEFBS = 'Hide Captain/FO EFBs',
    MISC = "Misc"

}




local french = english
local german = english
local russian = english
local italian = english
local castilan = english
local portuges = english
local japanese = english
local chinese = english

-- order in IMPORTANT
local translations = {
    english,
    french,
    german,
    russian,
    italian,
    castilan,
    portuges,
    japanese,
    chinese
}

P.translation = translations[lang]

return messages
