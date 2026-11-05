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
    registered = false, -- handler installed on the UnitOwner line
    rewritten = 0,      -- title lines actually rewritten
    recent = {},        -- recent possessive-looking lines, for /hss debug titles
}

local function Remember(before, after)
    local recent = HSS.tooltipStats.recent
    recent[#recent + 1] = { before = before, after = after }
    if #recent > RECENT_MAX then
        table.remove(recent, 1)
    end
end

-- Handles the owner-title line. `lineData` is the table Blizzard is about to show.
local function RewriteLine(lineData)
    if type(lineData) ~= "table" then
        return
    end

    local text = lineData.leftText
    if IsSecret(text) or type(text) ~= "string" or not text:find("'", 1, true) then
        return
    end

    local result = HSS.StripSurnameInTitle(text, HSS.surnameSet)
    Remember(text, result ~= text and result or nil)

    if result ~= text then
        lineData.leftText = result
        HSS.tooltipStats.rewritten = HSS.tooltipStats.rewritten + 1
    end
end

-- Returns true if the handler is registered. Never throws.
function HSS.InstallTooltipHook()
    local stats = HSS.tooltipStats
    if stats.registered then
        return true
    end

    -- The owner title ("<Lappy Mhmm's Pet>") is its own UnitOwner line.
    if type(TooltipDataProcessor) ~= "table"
        or type(TooltipDataProcessor.AddLinePreCall) ~= "function"
        or type(Enum) ~= "table"
        or type(Enum.TooltipDataLineType) ~= "table"
        or type(Enum.TooltipDataLineType.UnitOwner) ~= "number"
    then
        return false
    end

    stats.registered = HSS.Try("tooltip", TooltipDataProcessor.AddLinePreCall,
        Enum.TooltipDataLineType.UnitOwner,
        function(_, lineData)
            HSS.Try("tooltip", RewriteLine, lineData)
        end)

    return stats.registered
end

-- /hss debug titles: what the tooltip handler has seen. `out` is a print
-- function. (The overhead name above a unit is drawn by the game engine and
-- is not reachable from an addon, so there is nothing to dump for it.)
function HSS.DumpTitles(out)
    out("titles debug")

    local tooltip = HSS.tooltipStats
    out("  tooltip: registered=" .. tostring(tooltip.registered) .. " rewritten=" .. tooltip.rewritten)
    if #tooltip.recent == 0 then
        out("  tooltip: no possessive-looking lines seen yet (hover a pet, then run this again)")
    end
    for _, entry in ipairs(tooltip.recent) do
        out(("  tooltip line: '%s' -> %s"):format(tostring(entry.before),
            entry.after and ("'" .. entry.after .. "'") or "(unchanged)"))
    end
end
