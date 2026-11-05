local _, HSS = ...

-- Saved settings and the live lookup sets the rest of the addon reads.
-- Pure Lua (no frame APIs), so it can be tested with a plain interpreter.
--
-- Config.lua holds first-run defaults. After that HideSomeSurnamesDB is the
-- source of truth. Loading never throws: bad saved data falls back to defaults.

local MAX_SURNAMES = 20
local MAX_LENGTH = 32

HSS.MAX_SURNAMES = MAX_SURNAMES

-- Live tables. They are created once and only ever mutated in place, so the
-- frame hooks and chat closures that captured them always see current values.
HSS.surnameSet = {}
HSS.chatEventSet = {}

HSS.db = nil
HSS.defaults = nil

-- Called after any change (UI/slash) so the game-facing layer can refresh.
HSS.onSettingsChanged = nil

local function Clear(t)
    for key in pairs(t) do
        t[key] = nil
    end
end

local function IsKnownChannel(channel)
    for _, known in ipairs(HSS.CHAT_CHANNELS) do
        if known == channel then
            return true
        end
    end
    return false
end

-- Returns true, cleanedSurname  or  false, reason.
function HSS.NormalizeSurname(input)
    if type(input) ~= "string" then
        return false, "that isn't text"
    end

    local surname = input:match("^%s*(.-)%s*$")

    if surname == "" then
        return false, "type a surname first"
    end
    if #surname > MAX_LENGTH then
        return false, "that surname is too long"
    end
    if surname:find("%s") then
        return false, "a surname is a single word"
    end
    if surname:find("[-|:]") then
        return false, "a surname can't contain - | or :"
    end

    return true, surname
end

local function IndexOfSurname(surname)
    local lowered = surname:lower()
    for index, existing in ipairs(HSS.db.surnames) do
        if existing:lower() == lowered then
            return index
        end
    end
    return nil
end

-- Rebuilds the live sets from the saved settings.
local function RebuildLive()
    Clear(HSS.surnameSet)
    Clear(HSS.chatEventSet)

    if not HSS.db then
        return
    end

    for _, surname in ipairs(HSS.db.surnames) do
        HSS.surnameSet[surname:lower()] = true
    end

    HSS.FillChatEventSet(HSS.chatEventSet, HSS.db.chatChannels)
end

local function Changed()
    RebuildLive()
    if HSS.onSettingsChanged then
        HSS.Try("ui", HSS.onSettingsChanged)
    end
end

-- Copies the defaults into `db` (keeping the same table, because the game's
-- saved-variable global points at it).
local function SeedFromDefaults(db, defaults)
    Clear(db)
    db.surnames = {}
    db.chatChannels = {}

    for _, surname in ipairs((defaults and defaults.surnames) or {}) do
        local ok, cleaned = HSS.NormalizeSurname(surname)
        if ok and #db.surnames < MAX_SURNAMES then
            db.surnames[#db.surnames + 1] = cleaned
        end
    end

    for _, channel in ipairs(HSS.CHAT_CHANNELS) do
        db.chatChannels[channel] = defaults ~= nil
            and type(defaults.chatChannels) == "table"
            and defaults.chatChannels[channel] == true
    end
end

-- Validates saved data and returns the table to store as HideSomeSurnamesDB.
function HSS.LoadSettings(db, defaults)
    HSS.defaults = defaults

    if type(db) ~= "table" then
        db = {}
    end

    if type(db.surnames) ~= "table" then
        -- First run (or unusable data): start from the defaults.
        SeedFromDefaults(db, defaults)
    else
        local cleanList, seen = {}, {}
        for _, value in ipairs(db.surnames) do
            local ok, cleaned = HSS.NormalizeSurname(value)
            if ok and not seen[cleaned:lower()] and #cleanList < MAX_SURNAMES then
                seen[cleaned:lower()] = true
                cleanList[#cleanList + 1] = cleaned
            end
        end
        db.surnames = cleanList

        local channels = type(db.chatChannels) == "table" and db.chatChannels or {}
        local cleanChannels = {}
        for _, channel in ipairs(HSS.CHAT_CHANNELS) do
            if type(channels[channel]) == "boolean" then
                cleanChannels[channel] = channels[channel]
            else
                cleanChannels[channel] = defaults ~= nil
                    and type(defaults.chatChannels) == "table"
                    and defaults.chatChannels[channel] == true
            end
        end
        db.chatChannels = cleanChannels
    end

    HSS.db = db
    RebuildLive()
    return db
end

-- The surnames in display order (a copy; safe to hold on to).
function HSS.GetSurnameList()
    local list = {}
    if HSS.db then
        for _, surname in ipairs(HSS.db.surnames) do
            list[#list + 1] = surname
        end
    end
    return list
end

function HSS.IsChannelEnabled(channel)
    return HSS.db ~= nil and HSS.db.chatChannels[channel] == true
end

-- Returns true, surname  or  false, reason.
function HSS.AddSurname(input)
    if not HSS.db then
        return false, "settings aren't loaded yet"
    end

    local ok, surname = HSS.NormalizeSurname(input)
    if not ok then
        return false, surname
    end

    if IndexOfSurname(surname) then
        return false, surname .. " is already in the list"
    end

    if #HSS.db.surnames >= MAX_SURNAMES then
        return false, "the list is full (" .. MAX_SURNAMES .. " surnames)"
    end

    HSS.db.surnames[#HSS.db.surnames + 1] = surname
    Changed()
    return true, surname
end

-- Returns true, surname  or  false, reason.
function HSS.RemoveSurname(input)
    if not HSS.db then
        return false, "settings aren't loaded yet"
    end

    if type(input) ~= "string" then
        return false, "that isn't text"
    end

    local wanted = input:match("^%s*(.-)%s*$")
    local index = wanted ~= "" and IndexOfSurname(wanted) or nil
    if not index then
        return false, (wanted ~= "" and wanted or "that") .. " isn't in the list"
    end

    local removed = table.remove(HSS.db.surnames, index)
    Changed()
    return true, removed
end

-- Only the known channels can be switched; anything else (whisper, instance
-- chat, ...) is rejected so it can never be enabled.
function HSS.SetChannel(channel, enabled)
    if not HSS.db or not IsKnownChannel(channel) then
        return false
    end

    HSS.db.chatChannels[channel] = enabled == true
    Changed()
    return true
end

function HSS.ResetSettings()
    if not HSS.db then
        return false
    end

    SeedFromDefaults(HSS.db, HSS.defaults)
    Changed()
    return true
end
