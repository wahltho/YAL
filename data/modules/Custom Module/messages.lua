local P = {}
messages = P -- package name


local lang = get(globalProperty("sim/operation/prefs/misc/language")) + 1

local english = {
    SETUP = 'Settings',
    GENERAL = 'General',
    VOICEREADBACK = 'Command Voice Readback',
    AUTOFUNCTIONS = 'Automatic Functions',
    VOICEADVICEONLY = 'Voice Advice Only',
    DEBUGMODE = 'Debug mode log',
    TODPAUSEQUITTIME = 'Sim exit after Pause at TOD (0-9999 sec)',
    SAVETIME = 'Auto Flight Save Time (0-9999 sec)',
    SAVENUMBER = 'Auto Flight Save EFB Position (1-8)',
    WAKEOVERRIDE = 'Disable XP Wake Effects',
    AUTOANTIICE = 'Automatic Anti Icing',
    AUTOWIPER = 'Automatic Wipers',
    AUTOBARO = 'Automatic Baro Settings',
    AUTOCENTERTANKHANDLING = 'Automatic Center Tank Handling',
    AUTOFLAPS = 'Automatic Flap Handlng',
    VIEWCHANGES = 'View Changes during Procedures',
    USEGROUNDPOWER = 'Use Ground Power when available instead APU',

    CUSTOMIZE = 'Customising',
    SPEEDRESTR250 = 'Set Speed Restriction 250',
    VREF30 = 'Calculate Approach Flaps, Vref, Autobrake',
    LOWERAIRSPACEALT = 'Lower Airspace Altitude (feet)',
    BANKANGLEMAX = 'Maximum Bank Angle (1-4)',
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
    GENBRIGHTAFDSFLOOD = 'AFDS Flodd',
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
