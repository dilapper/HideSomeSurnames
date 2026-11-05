local _, HSS = ...

-- Pure name logic. Deliberately uses no WoW frame APIs so it can be tested
-- with a plain Lua interpreter (see tests/strip_spec.lua).

local function IsSecret(value)
    return issecretvalue ~= nil and issecretvalue(value) or false
end

HSS.IsSecret = IsSecret

-- Turns { "Mhmm", "Other" } into a lowercase lookup set.
function HSS.BuildSurnameSet(list)
    local set = {}
    for _, surname in ipairs(list or {}) do
        if type(surname) == "string" and surname ~= "" then
            set[surname:lower()] = true
        end
    end
    return set
end

-- "Dave Mhmm" -> "Dave" when "mhmm" is in the set; anything else is returned
-- unchanged. A cross-realm suffix is kept: "Dave Mhmm-Realm" -> "Dave-Realm".
function HSS.StripSurname(fullName, surnameSet)
    if IsSecret(fullName) or type(fullName) ~= "string" then
        return fullName
    end

    local forename, rest = fullName:match("^(%S+)%s+(.-)%s*$")
    if not forename or rest == "" then
        return fullName
    end

    local surname, realm = rest:match("^([^-]+)(-.*)$")
    if not surname then
        surname, realm = rest, ""
    end

    if surnameSet and surnameSet[surname:lower()] then
        return forename .. realm
    end

    return fullName
end

-- Rewrites the VISIBLE text of player hyperlinks in a rendered chat line:
--   |Hplayer:Dave Mhmm:...|h[Dave Mhmm]|h  ->  |Hplayer:Dave Mhmm:...|h[Dave]|h
-- The link payload (what click-to-whisper reads) is never modified. Running it
-- twice gives the same result as running it once.
function HSS.StripSurnameInLinks(message, surnameSet)
    if IsSecret(message) or type(message) ~= "string" then
        return message
    end

    if not message:find("|Hplayer:", 1, true) then
        return message
    end

    local result = message:gsub("(|Hplayer:([^|]*)|h)(.-)(|h)", function(openTag, payload, visible, closeTag)
        local fullName = payload:match("^([^:]*)")
        if not fullName or fullName == "" then
            return nil
        end

        -- The visible text may show the name with or without the realm.
        local candidates = { fullName }
        local withoutRealm = fullName:match("^(.-)%-")
        if withoutRealm and withoutRealm ~= "" then
            candidates[#candidates + 1] = withoutRealm
        end

        for _, candidate in ipairs(candidates) do
            local short = HSS.StripSurname(candidate, surnameSet)
            if short ~= candidate then
                local s, e = visible:find(candidate, 1, true)
                if s then
                    return openTag .. visible:sub(1, s - 1) .. short .. visible:sub(e + 1) .. closeTag
                end
            end
        end

        return nil -- leave this link exactly as Blizzard wrote it
    end)

    return result
end

-- Owner titles on pets and similar units:
--   <Lappy Mhmm's Pet>  ->  <Lappy's Pet>
-- Matches on the text ("Forename Surname's ..."), so it doesn't matter which
-- unit or UI element it came from. Only rewrites when the surname is in the
-- set; everything else (other surnames, guild tags, already-short titles,
-- non-strings, secret values) is returned unchanged.
function HSS.StripSurnameInTitle(text, surnameSet)
    if IsSecret(text) or type(text) ~= "string" then
        return text
    end

    if not text:find("'", 1, true) then
        return text
    end

    -- Optional "<", forename, surname, then a possessive ('s, or a bare ' for
    -- names ending in s) and the rest of the title.
    local open, forename, surname, rest = text:match("^(<?)(%S+)%s+([^%s']+)('s?%s.*)$")
    if not forename then
        return text
    end

    if surnameSet and surnameSet[surname:lower()] then
        -- "Lappy Jones' Pet" ends in a bare apostrophe because "Jones" ends in
        -- s; once the surname is gone the forename needs its own 's.
        if rest:find("^'%s") and not forename:lower():find("s$") then
            rest = "'s" .. rest:sub(2)
        end
        return open .. forename .. rest
    end

    return text
end

-- ============================================================
-- SAFETY
-- ============================================================
-- Rule: if we can't hide a surname, the surname stays visible. Nothing we hand
-- to the game may throw. Entry points go through HSS.Try; a feature that fails
-- MAX_FAILURES times switches itself off for the session.

local MAX_FAILURES = 3
local features = {}

function HSS.GetFeatureState(name)
    local state = features[name]
    if not state then
        state = { failures = 0, disabled = false, lastError = nil }
        features[name] = state
    end
    return state
end

function HSS.FeatureEnabled(name)
    return not HSS.GetFeatureState(name).disabled
end

-- Optional hook so the UI layer can tell the user a feature switched off.
HSS.onFeatureDisabled = nil

-- Calls fn(...) in protected mode. Returns ok, result (single result).
-- Failures are counted against `feature` and never propagate.
function HSS.Try(feature, fn, ...)
    local state = HSS.GetFeatureState(feature)
    if state.disabled then
        return false
    end

    local ok, result = pcall(fn, ...)
    if ok then
        return true, result
    end

    state.failures = state.failures + 1
    state.lastError = tostring(result)

    if state.failures >= MAX_FAILURES then
        state.disabled = true
        if HSS.onFeatureDisabled then
            pcall(HSS.onFeatureDisabled, feature, state.lastError)
        end
    end

    return false
end
