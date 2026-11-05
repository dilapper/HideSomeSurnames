local _, HSS = ...

-- FIRST-RUN DEFAULTS. Surnames and chat channels are edited in-game under
-- Esc > Options > AddOns > HideSomeSurnames (or /hss add, /hss remove) and saved
-- per account. This file only seeds the very first run, and is what
-- "/hss reset" goes back to; changing it later does not affect saved settings.
--
-- Surnames to hide (case-insensitive). Players whose surname is NOT listed
-- keep their full name on screen.
HSS.surnames = {
    "Mhmm",
}

-- Chat channels in which those surnames are hidden. Whispers, world/custom
-- channels, yell, raid and instance chat always show full names.
-- PARTY includes party leader messages.
HSS.chatChannels = {
    SAY     = true,
    PARTY   = true,
    GUILD   = true,
    OFFICER = true,
}
