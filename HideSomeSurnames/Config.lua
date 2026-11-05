local _, HSS = ...

-- Surnames to hide (case-insensitive). Players whose surname is NOT listed
-- here keep their full name on screen.
--
-- v0.1: edit this list and /reload. A later version will move this into
-- SavedVariables with an in-game editor.
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
