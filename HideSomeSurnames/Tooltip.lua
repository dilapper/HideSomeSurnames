local _, HSS = ...

-- Pet/owner titles in the mouseover tooltip.
--
-- Nothing is replaced; the line is edited as it is built, and a failure
-- leaves it exactly as Blizzard wrote it. Matching is by text.
--
-- Nothing here touches WoW globals at load time (testable with plain Lua).

local IsSecret = HSS.IsSecret

local RECENT_MAX = 6

HSS.tooltipStats = {
    lineTypes = 0,     -- how many line types we registered for
    rewritten = 0,     -- title lines actually rewritten
    recent = {},       -- recent possessive-looking lines, for /hss debug titles
}

local lineTypeNames = {}

local function Remember(lineType, before, after)
    local recent = HSS.tooltipStats.recent
    recent[#recent + 1] = {
        lineType = lineTypeNames[lineType] or tostring(lineType),
        before = before,
        after = after,
    }
    if #recent > RECENT_MAX then
        table.remove(recent, 1)
    end
end

-- Handles one tooltip line. `lineData` is the table Blizzard is about to show.
local function RewriteLine(lineType, lineData)
    if type(lineData) ~= "table" then
        return
    end

    local text = lineData.leftText
    if IsSecret(text) or type(text) ~= "string" or not text:find("'", 1, true) then
        return
    end

    local result = HSS.StripSurnameInTitle(text, HSS.surnameSet)
    Remember(lineType, text, result ~= text and result or nil)

    if result ~= text then
        lineData.leftText = result
        HSS.tooltipStats.rewritten = HSS.tooltipStats.rewritten + 1
    end
end

local installed = false

-- Returns true if the handler is registered. Never throws.
function HSS.InstallTooltipHook()
    if installed then
        return true
    end

    if type(TooltipDataProcessor) ~= "table"
        or type(TooltipDataProcessor.AddLinePreCall) ~= "function"
        or type(Enum) ~= "table"
        or type(Enum.TooltipDataLineType) ~= "table"
    then
        return false
    end

    -- Confirmed in game: the owner title ("<Lappy Mhmm's Pet>") is its own
    -- UnitOwner line. If this client has no such line type, fall back to
    -- checking every line type (matching is by text, so that still works).
    local wanted = {}
    local ownerType = Enum.TooltipDataLineType.UnitOwner
    if type(ownerType) == "number" then
        wanted[#wanted + 1] = { name = "UnitOwner", lineType = ownerType }
    else
        for name, lineType in pairs(Enum.TooltipDataLineType) do
            if type(lineType) == "number" then
                wanted[#wanted + 1] = { name = name, lineType = lineType }
            end
        end
    end

    local count = 0
    for _, entry in ipairs(wanted) do
        local lineType = entry.lineType
        lineTypeNames[lineType] = entry.name
        local ok = HSS.Try("tooltip", TooltipDataProcessor.AddLinePreCall, lineType,
            function(_, lineData)
                HSS.Try("tooltip", RewriteLine, lineType, lineData)
            end)
        if ok then
            count = count + 1
        end
    end

    HSS.tooltipStats.lineTypes = count
    installed = count > 0
    return installed
end

-- /hss debug titles: what the tooltip handler has seen. `out` is a print
-- function. (The overhead name above a unit is drawn by the game engine and
-- is not reachable from an addon, so there is nothing to dump for it.)
function HSS.DumpTitles(out)
    out("titles debug")

    local tooltip = HSS.tooltipStats
    out("  tooltip: registered for " .. tooltip.lineTypes .. " line type(s), rewritten="
        .. tooltip.rewritten)
    if #tooltip.recent == 0 then
        out("  tooltip: no possessive-looking lines seen yet (hover a pet, then run this again)")
    end
    for _, entry in ipairs(tooltip.recent) do
        out(("  tooltip line [%s]: '%s' -> %s"):format(entry.lineType, tostring(entry.before),
            entry.after and ("'" .. entry.after .. "'") or "(unchanged)"))
    end
end
