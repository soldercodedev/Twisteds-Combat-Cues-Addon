-- Twisteds Combat Cues - Sounds.lua
-- Sound catalog and playback. Supports both Blizzard SOUNDKIT sounds (PlaySound)
-- and bundled files in the Sounds/ folder (PlaySoundFile), with safe fallbacks.
local addonName, TCC = ...

local FALLBACK_SOUND = 8959 -- numeric id for SOUNDKIT.RAID_WARNING (hard fallback)

-- Path (relative to the WoW data root) to this addon's bundled sound files.
local SOUND_PATH = "Interface\\AddOns\\TwistedsCombatCues\\Sounds\\"

-- An entry uses EITHER `kit` (a SOUNDKIT constant NAME) OR `file` (a bundled
-- file name). Both are validated at play time so a bad entry never errors.
TCC.SOUNDS = {
    -- Built-in Blizzard sounds.
    { key = "RAID_WARNING", label = "Raid Warning",        kit = "RAID_WARNING" },
    { key = "READY_CHECK",  label = "Ready Check",          kit = "READY_CHECK" },
    { key = "ALARM_CLOCK",  label = "Alarm Clock",          kit = "ALARM_CLOCK_WARNING_3" },
    { key = "MAP_PING",     label = "Map Ping",             kit = "MAP_PING" },
    { key = "SUBTLE",       label = "Subtle Notification",  kit = "IG_MAINMENU_OPTION_CHECKBOX_ON" },
    { key = "PVP_WARNING",  label = "PvP Warning",          kit = "PVPTHROUGHQUEUE" },

    -- Bundled custom sound files (Sounds/ folder).
    { key = "AcousticGuitar", label = "Acoustic Guitar", file = "AcousticGuitar.ogg" },
    { key = "Adds", label = "Adds", file = "Adds.ogg" },
    { key = "AirHorn", label = "Air Horn", file = "AirHorn.ogg" },
    { key = "Applause", label = "Applause", file = "Applause.ogg" },
    { key = "BananaPeelSlip", label = "Banana Peel Slip", file = "BananaPeelSlip.ogg" },
    { key = "BatmanPunch", label = "Batman Punch", file = "BatmanPunch.ogg" },
    { key = "BikeHorn", label = "Bike Horn", file = "BikeHorn.ogg" },
    { key = "Blast", label = "Blast", file = "Blast.ogg" },
    { key = "Bleat", label = "Bleat", file = "Bleat.ogg" },
    { key = "Boss", label = "Boss", file = "Boss.ogg" },
    { key = "BoxingArenaSound", label = "Boxing Arena Sound", file = "BoxingArenaSound.ogg" },
    { key = "Brass", label = "Brass", file = "Brass.mp3" },
    { key = "CartoonVoiceBaritone", label = "Cartoon Voice Baritone", file = "CartoonVoiceBaritone.ogg" },
    { key = "CartoonWalking", label = "Cartoon Walking", file = "CartoonWalking.ogg" },
    { key = "CatMeow2", label = "Cat Meow 2", file = "CatMeow2.ogg" },
    { key = "ChickenAlarm", label = "Chicken Alarm", file = "ChickenAlarm.ogg" },
    { key = "Circle", label = "Circle", file = "Circle.ogg" },
    { key = "CowMooing", label = "Cow Mooing", file = "CowMooing.ogg" },
    { key = "Cross", label = "Cross", file = "Cross.ogg" },
    { key = "Diamond", label = "Diamond", file = "Diamond.ogg" },
    { key = "DontRelease", label = "Dont Release", file = "DontRelease.ogg" },
    { key = "DoubleWhoosh", label = "Double Whoosh", file = "DoubleWhoosh.ogg" },
    { key = "Drums", label = "Drums", file = "Drums.ogg" },
    { key = "Empowered", label = "Empowered", file = "Empowered.ogg" },
    { key = "ErrorBeep", label = "Error Beep", file = "ErrorBeep.ogg" },
    { key = "Focus", label = "Focus", file = "Focus.ogg" },
    { key = "Glass", label = "Glass", file = "Glass.mp3" },
    { key = "GoatBleating", label = "Goat Bleating", file = "GoatBleating.ogg" },
    { key = "HeartbeatSingle", label = "Heartbeat Single", file = "HeartbeatSingle.ogg" },
    { key = "Idiot", label = "Idiot", file = "Idiot.ogg" },
    { key = "KittenMeow", label = "Kitten Meow", file = "KittenMeow.ogg" },
    { key = "Left", label = "Left", file = "Left.ogg" },
    { key = "Moon", label = "Moon", file = "Moon.ogg" },
    { key = "Next", label = "Next", file = "Next.ogg" },
    { key = "OhNo", label = "Oh No", file = "OhNo.ogg" },
    { key = "Portal", label = "Portal", file = "Portal.ogg" },
    { key = "Protected", label = "Protected", file = "Protected.ogg" },
    { key = "Release", label = "Release", file = "Release.ogg" },
    { key = "Right", label = "Right", file = "Right.ogg" },
    { key = "RingingPhone", label = "Ringing Phone", file = "RingingPhone.ogg" },
    { key = "RoaringLion", label = "Roaring Lion", file = "RoaringLion.ogg" },
    { key = "RobotBlip", label = "Robot Blip", file = "RobotBlip.ogg" },
    { key = "RoosterChickenCalls", label = "Rooster Chicken Calls", file = "RoosterChickenCalls.ogg" },
    { key = "RunAway", label = "Run Away", file = "RunAway.ogg" },
    { key = "SharpPunch", label = "Sharp Punch", file = "SharpPunch.ogg" },
    { key = "SheepBleat", label = "Sheep Bleat", file = "SheepBleat.ogg" },
    { key = "Shotgun", label = "Shotgun", file = "Shotgun.ogg" },
    { key = "Skull", label = "Skull", file = "Skull.ogg" },
    { key = "Spread", label = "Spread", file = "Spread.ogg" },
    { key = "Square", label = "Square", file = "Square.ogg" },
    { key = "SqueakyToyShort", label = "Squeaky Toy Short", file = "SqueakyToyShort.ogg" },
    { key = "SquishFart", label = "Squish Fart", file = "SquishFart.ogg" },
    { key = "Stack", label = "Stack", file = "Stack.ogg" },
    { key = "Star", label = "Star", file = "Star.ogg" },
    { key = "Switch", label = "Switch", file = "Switch.ogg" },
    { key = "SynthChord", label = "Synth Chord", file = "SynthChord.ogg" },
    { key = "TadaFanfare", label = "Tada Fanfare", file = "TadaFanfare.ogg" },
    { key = "Taunt", label = "Taunt", file = "Taunt.ogg" },
    { key = "TempleBellHuge", label = "Temple Bell Huge", file = "TempleBellHuge.ogg" },
    { key = "Torch", label = "Torch", file = "Torch.ogg" },
    { key = "Triangle", label = "Triangle", file = "Triangle.ogg" },
    { key = "WarningSiren", label = "Warning Siren", file = "WarningSiren.ogg" },
    { key = "WaterDrop", label = "Water Drop", file = "WaterDrop.ogg" },
    { key = "Xylophone", label = "Xylophone", file = "Xylophone.ogg" },
}

-- Human-readable label for a saved sound key (used by the UI).
function TCC.SoundLabel(key)
    for _, s in ipairs(TCC.SOUNDS) do
        if s.key == key then return s.label end
    end
    return key or "?"
end

-- Resolves a sound key to something playable.
-- Returns "file", fullPath   for bundled files, or
--         "kit",  soundKitID for Blizzard SOUNDKIT sounds (with safe fallback).
function TCC.ResolveSound(key)
    local entry
    for _, s in ipairs(TCC.SOUNDS) do
        if s.key == key then entry = s break end
    end
    if entry and entry.file then
        return "file", SOUND_PATH .. entry.file
    end
    if entry and entry.kit and type(SOUNDKIT) == "table" then
        local id = SOUNDKIT[entry.kit]
        if type(id) == "number" then
            return "kit", id
        end
    end
    if type(SOUNDKIT) == "table" and type(SOUNDKIT.RAID_WARNING) == "number" then
        return "kit", SOUNDKIT.RAID_WARNING
    end
    return "kit", FALLBACK_SOUND
end

-- Plays a sound key on the given channel (defaults to Master). Handles both
-- file and SOUNDKIT sounds; a bundled file that fails falls back to a built-in.
function TCC.PlayKey(key, channel)
    channel = channel or "Master"
    local mode, value = TCC.ResolveSound(key)
    if mode == "file" then
        local willPlay = PlaySoundFile(value, channel)
        if not willPlay then
            PlaySound(FALLBACK_SOUND, channel)
        end
    else
        PlaySound(value, channel)
    end
end
