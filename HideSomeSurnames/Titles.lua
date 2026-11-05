local _, HSS = ...

-- Pet/owner titles drawn on unit frames and nameplates ("<Lappy Mhmm's Pet>").
--
-- We don't know which field holds the title, so instead of guessing a name we
-- look at the FontStrings the frame itself owns and rewrite any whose text is
-- an owner title with a hidden surname. Only non-player units are scanned
-- (pets, minions); player names are handled separately.
--
-- Nothing here touches WoW globals at load time (testable with plain Lua).

local IsSecret = HSS.IsSecret

HSS.titleStats = {
    scanned = 0,    -- frames scanned
    rewritten = 0,  -- title regions actually rewritten
}

local function IsForbidden(object)
    return object.IsForbidden ~= nil and object:IsForbidden()
end

-- Called from the same post-hooks as the name handling. Never throws when
-- called through HSS.Try.
function HSS.ShortenTitleRegions(frame)
    if not frame or next(HSS.surnameSet) == nil then
        return
    end

    -- IsForbidden must be checked before any other access.
    if IsForbidden(frame) then
        return
    end

    local unit = frame.unit
    if IsSecret(unit) or type(unit) ~= "string" then
        return
    end

    if not UnitExists(unit) or UnitIsPlayer(unit) then
        return
    end

    if type(frame.GetRegions) ~= "function" then
        return
    end

    HSS.titleStats.scanned = HSS.titleStats.scanned + 1

    for _, region in ipairs({ frame:GetRegions() }) do
        if not IsForbidden(region)
            and type(region.GetObjectType) == "function"
            and region:GetObjectType() == "FontString"
            and type(region.GetText) == "function"
            and type(region.SetText) == "function"
        then
            local text = region:GetText()
            local result = HSS.StripSurnameInTitle(text, HSS.surnameSet)
            if result ~= text then
                region:SetText(result)
                HSS.titleStats.rewritten = HSS.titleStats.rewritten + 1
            end
        end
    end
end

-- ============================================================
-- /hss debug titles
-- ============================================================
-- Prints what the client actually builds for the current target, so we can
-- see where a title lives instead of guessing. `out` is a print function.

local function Describe(out, label, frame)
    if not frame then
        out("  " .. label .. ": (none)")
        return
    end

    if IsForbidden(frame) then
        out("  " .. label .. ": forbidden")
        return
    end

    out("  " .. label .. ":")

    -- Find the field name each region is stored under, when there is one.
    local keys = {}
    pcall(function()
        for key, value in pairs(frame) do
            if type(value) == "table" then
                keys[value] = key
            end
        end
    end)

    if type(frame.GetRegions) ~= "function" then
        out("    (no regions)")
        return
    end

    for index, region in ipairs({ frame:GetRegions() }) do
        local kind = type(region.GetObjectType) == "function" and region:GetObjectType() or "?"
        local text = "-"
        if kind == "FontString" and type(region.GetText) == "function" then
            local value = region:GetText()
            text = IsSecret(value) and "<secret>" or tostring(value)
        end
        out(("    [%d] %s key=%s text=%s"):format(index, kind, tostring(keys[region]), text))
    end
end

function HSS.DumpTitles(out)
    out("titles debug")

    local stats = HSS.titleStats
    out("  frames scanned=" .. stats.scanned .. " title regions rewritten=" .. stats.rewritten)

    local tooltip = HSS.tooltipStats
    out("  tooltip: registered for " .. tooltip.lineTypes .. " line types, rewritten="
        .. tooltip.rewritten)
    if #tooltip.recent == 0 then
        out("  tooltip: no possessive-looking lines seen yet (hover your pet, then run this again)")
    end
    for _, entry in ipairs(tooltip.recent) do
        out(("  tooltip line [%s]: '%s' -> %s"):format(entry.lineType, tostring(entry.before),
            entry.after and ("'" .. entry.after .. "'") or "(unchanged)"))
    end

    if not UnitExists("target") then
        out("  no target: target the pet and run this again to see its nameplate")
        return
    end

    local plate = C_NamePlate and type(C_NamePlate.GetNamePlateForUnit) == "function"
        and C_NamePlate.GetNamePlateForUnit("target") or nil

    if not plate then
        out("  target has no visible nameplate (turn nameplates on / get it in range)")
        return
    end

    Describe(out, "nameplate", plate)
    local unitFrame = plate.UnitFrame
    Describe(out, "nameplate.UnitFrame", unitFrame)

    if unitFrame and not IsForbidden(unitFrame) and type(unitFrame.GetChildren) == "function" then
        for index, child in ipairs({ unitFrame:GetChildren() }) do
            Describe(out, "nameplate.UnitFrame child " .. index, child)
        end
    end
end
