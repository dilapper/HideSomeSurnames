local _, HSS = ...

-- Pet/owner titles in the mouseover tooltip.
--
-- We don't know which tooltip line type carries the title, so the same small
-- handler is registered for every line type. It matches on the text, so the
-- type doesn't matter. Nothing is replaced; the lines are edited as they are
-- built, and a failure leaves the line exactly as Blizzard wrote it.
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

    local count = 0
    for name, lineType in pairs(Enum.TooltipDataLineType) do
        if type(lineType) == "number" then
            lineTypeNames[lineType] = name
            local ok = HSS.Try("tooltip", TooltipDataProcessor.AddLinePreCall, lineType,
                function(_, lineData)
                    HSS.Try("tooltip", RewriteLine, lineType, lineData)
                end)
            if ok then
                count = count + 1
            end
        end
    end

    HSS.tooltipStats.lineTypes = count
    installed = count > 0
    return installed
end
