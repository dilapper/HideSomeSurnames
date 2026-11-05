local _, HSS = ...

-- Chat pane of the Guild & Communities window (the pane only: never the member
-- roster, the guild name, or names inside message text).
--
-- That pane is the window's own message display, so the normal chat support
-- never sees it. We find its message frame, let Blizzard render, then use the
-- frame's own TransformMessages() to rewrite the visible "[Forename Surname]"
-- text. Nothing is replaced, link data is untouched, and any failure leaves
-- the line exactly as Blizzard wrote it.
--
-- The frame path, event names and line format are unverified; /hss debug and
-- /hss debug under show what the client really has.
--
-- Nothing here touches WoW globals at load time (testable with plain Lua).

local IsSecret = HSS.IsSecret

local MESSAGE_EVENTS = {
    "CLUB_MESSAGE_ADDED",
    "CLUB_MESSAGE_HISTORY_RECEIVED",
    "CLUB_MESSAGE_UPDATED",
}

local SEARCH_DEPTH = 4

local SAMPLES_MAX = 6

HSS.communitiesStats = {
    found = false,
    path = nil,
    passes = 0,
    rewritten = 0,
    noScheduler = false,
    registered = {},   -- events we registered
    failed = {},       -- events the client rejected
    shownHooked = false,
    addMessageHooked = false,
    predicateCalls = 0,    -- lines offered to the predicate
    noBracket = 0,         -- of those, lines without any "["
    samples = {},          -- recent lines containing "[" (escaped), for /hss debug
}

-- Makes a raw line printable: "|" doubled so colour/link codes show up.
local function Escape(message)
    if IsSecret(message) then
        return "<secret>"
    end
    if type(message) ~= "string" then
        return "<" .. type(message) .. ">"
    end
    local text = message:gsub("|", "||")
    if #text > 200 then
        text = text:sub(1, 200) .. "..."
    end
    return text
end

local function RecordSample(message, accepted, ...)
    local stats = HSS.communitiesStats
    local types = {}
    for index = 1, math.min(select("#", ...), 4) do
        types[#types + 1] = type((select(index, ...)))
    end

    stats.samples[#stats.samples + 1] = {
        text = Escape(message),
        accepted = accepted,
        args = (type(message)) .. (#types > 0 and ("," .. table.concat(types, ",")) or ""),
    }
    if #stats.samples > SAMPLES_MAX then
        table.remove(stats.samples, 1)
    end
end

local function IsForbidden(object)
    return object.IsForbidden ~= nil and object:IsForbidden()
end

local function HasTransform(object)
    return type(object) == "table"
        and type(object.TransformMessages) == "function"
        and not IsForbidden(object)
end

-- Looks for a frame with TransformMessages in `frame`'s fields, then in its
-- children (depth-limited). Returns frame, path or nil.
local function Search(frame, path, depth, seen)
    if depth > SEARCH_DEPTH or seen[frame] or IsForbidden(frame) then
        return nil
    end
    seen[frame] = true

    for key, value in pairs(frame) do
        if type(key) == "string" and HasTransform(value) then
            return value, path .. "." .. key
        end
    end

    if type(frame.GetChildren) == "function" then
        for index, child in ipairs({ frame:GetChildren() }) do
            if type(child) == "table" then
                if HasTransform(child) then
                    return child, path .. ".child" .. index
                end
                local found, foundPath = Search(child, path .. ".child" .. index, depth + 1, seen)
                if found then
                    return found, foundPath
                end
            end
        end
    end

    return nil
end

-- Returns messageFrame, pathDescription  or nil.
function HSS.FindCommunitiesMessageFrame()
    local window = _G.CommunitiesFrame
    if type(window) ~= "table" or IsForbidden(window) then
        return nil
    end

    local chat = window.Chat
    if type(chat) ~= "table" or IsForbidden(chat) then
        return nil
    end

    if HasTransform(chat.MessageFrame) then
        return chat.MessageFrame, "CommunitiesFrame.Chat.MessageFrame"
    end

    return Search(chat, "CommunitiesFrame.Chat", 0, {})
end

-- TransformMessages callbacks. These lines don't come from CHAT_MSG_* events,
-- so there is no channel to look at: the window follows the Guild checkbox.
local function ShouldTransform(message, ...)
    local stats = HSS.communitiesStats
    stats.predicateCalls = stats.predicateCalls + 1

    local bracketed = not IsSecret(message) and type(message) == "string"
        and message:find("[", 1, true) ~= nil
    if bracketed then
        RecordSample(message, HSS.IsChannelEnabled("GUILD"), ...)
    else
        stats.noBracket = stats.noBracket + 1
    end

    if not HSS.IsChannelEnabled("GUILD") then
        return false
    end
    return bracketed
end

local function predicate(...)
    local ok, result = HSS.Try("communities", ShouldTransform, ...)
    return ok and result == true
end

local function transform(message, ...)
    if not HSS.FeatureEnabled("communities") then
        return message, ...
    end

    local ok, result = HSS.Try("communities", HSS.StripSurnameInBracketNames, message, HSS.surnameSet)
    if ok and type(result) == "string" and not IsSecret(result) then
        if result ~= message then
            HSS.communitiesStats.rewritten = HSS.communitiesStats.rewritten + 1
        end
        return result, ...
    end

    return message, ...
end

-- Exposed for tests.
HSS.CommunitiesPredicate = predicate
HSS.CommunitiesTransform = transform

local scheduled = {}   -- delay -> true while a pass with that delay is pending
local inPass = false    -- true while our own TransformMessages call is running
local hookedFrames = setmetatable({}, { __mode = "k" })

-- Rewrite whenever a line is added to the pane, so history that arrives after
-- our first pass is still handled. (A guess at why a single pass wasn't enough;
-- ignored while our own pass runs so it can never feed itself.)
local function HookAddMessage(frame)
    if hookedFrames[frame] or type(frame.AddMessage) ~= "function"
        or type(hooksecurefunc) ~= "function"
    then
        return
    end

    if pcall(hooksecurefunc, frame, "AddMessage", function()
        if not inPass then
            HSS.ScheduleCommunitiesPass()
        end
    end) then
        hookedFrames[frame] = true
        HSS.communitiesStats.addMessageHooked = true
    end
end

local function RunPass()
    if not HSS.FeatureEnabled("communities") then
        return
    end

    local stats = HSS.communitiesStats
    local frame, path = HSS.FindCommunitiesMessageFrame()
    stats.found = frame ~= nil
    stats.path = path

    if not frame then
        return
    end

    HookAddMessage(frame)

    stats.passes = stats.passes + 1
    inPass = true
    HSS.Try("communities", frame.TransformMessages, frame, predicate, transform)
    inPass = false
end

-- One pass after `delay` seconds (default: the next tick, after Blizzard has
-- rendered). Calls with the same delay are coalesced. Never throws.
function HSS.ScheduleCommunitiesPass(delay)
    delay = delay or 0
    if scheduled[delay] or not HSS.FeatureEnabled("communities") then
        return
    end

    if not (C_Timer and type(C_Timer.After) == "function") then
        HSS.communitiesStats.noScheduler = true
        return
    end

    scheduled[delay] = true
    local ok = HSS.Try("communities", C_Timer.After, delay, function()
        scheduled[delay] = nil
        HSS.Try("communities", RunPass)
    end)

    if not ok then
        scheduled[delay] = nil
    end
end

function HSS.IsCommunitiesEvent(event)
    for _, name in ipairs(MESSAGE_EVENTS) do
        if name == event then
            return true
        end
    end
    return false
end

-- Registers each event on `eventFrame` separately. An unknown event name makes
-- RegisterEvent raise an error, so each call is protected on its own and a
-- rejected name is only recorded (it does not count toward the breaker).
function HSS.RegisterCommunitiesEvents(eventFrame)
    local stats = HSS.communitiesStats
    for _, event in ipairs(MESSAGE_EVENTS) do
        if pcall(eventFrame.RegisterEvent, eventFrame, event) then
            stats.registered[#stats.registered + 1] = event
        else
            stats.failed[#stats.failed + 1] = event
        end
    end
end

-- Hooks the window's OnShow once it exists (also catches history re-added when
-- the window is reopened). Safe to call repeatedly; never throws through Try.
function HSS.HookCommunitiesWindow()
    local stats = HSS.communitiesStats
    local window = _G.CommunitiesFrame

    if stats.shownHooked or type(window) ~= "table" or IsForbidden(window)
        or type(window.HookScript) ~= "function"
    then
        return stats.shownHooked
    end

    window:HookScript("OnShow", function()
        -- History can arrive a little after the window opens.
        HSS.ScheduleCommunitiesPass()
        HSS.ScheduleCommunitiesPass(0.5)
        HSS.ScheduleCommunitiesPass(2)
    end)
    stats.shownHooked = true
    HSS.ScheduleCommunitiesPass()
    return true
end

-- ============================================================
-- /hss debug under [seconds]
-- ============================================================
-- Prints the frame under the mouse and its parents after a short delay, so you
-- can point at the chat pane and show me what it really is. `out` is a print
-- function.

local function MouseFrame()
    if type(GetMouseFoci) == "function" then
        local foci = GetMouseFoci()
        return type(foci) == "table" and foci[1] or nil
    end
    if type(GetMouseFocus) == "function" then
        return GetMouseFocus()
    end
    return nil
end

local function KeyInParent(object, parent)
    if type(parent) ~= "table" or IsForbidden(parent) then
        return nil
    end
    local found
    pcall(function()
        for key, value in pairs(parent) do
            if value == object and type(key) == "string" then
                found = key
                return
            end
        end
    end)
    return found
end

local function DescribeUnderMouse(out)
    local frame = MouseFrame()
    if not frame then
        out("under mouse: nothing found (or no mouse-focus API)")
        return
    end

    out("under mouse (innermost first):")
    local current, level = frame, 0
    while current and level < 8 do
        if IsForbidden(current) then
            out(("  [%d] forbidden frame"):format(level))
            break
        end

        local name = type(current.GetName) == "function" and current:GetName() or nil
        local kind = type(current.GetObjectType) == "function" and current:GetObjectType() or "?"
        local parent = type(current.GetParent) == "function" and current:GetParent() or nil
        out(("  [%d] %s name=%s key=%s TransformMessages=%s"):format(level, kind, tostring(name),
            tostring(KeyInParent(current, parent)), tostring(type(current.TransformMessages) == "function")))

        current = parent
        level = level + 1
    end

    local found, path = HSS.FindCommunitiesMessageFrame()
    out("  communities message frame via our search: " .. (found and path or "not found"))
end

function HSS.DumpUnderMouse(out, seconds)
    seconds = tonumber(seconds) or 3
    if seconds < 1 then seconds = 1 end
    if seconds > 30 then seconds = 30 end

    if not (C_Timer and type(C_Timer.After) == "function") then
        out("no timer available; can't delay the dump")
        return
    end

    out("hover the frame you want to inspect; dumping in " .. seconds .. "s...")
    C_Timer.After(seconds, function()
        local ok, err = pcall(DescribeUnderMouse, out)
        if not ok then
            out("dump failed: " .. tostring(err))
        end
    end)
end
