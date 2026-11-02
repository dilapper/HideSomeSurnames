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
