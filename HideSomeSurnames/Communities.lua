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

HSS.communitiesStats = {
    found = false,
    path = nil,
    passes = 0,
    rewritten = 0,
    noScheduler = false,
    registered = {},   -- events we registered
    failed = {},       -- events the client rejected
    shownHooked = false,
}

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
local function ShouldTransform(message)
    if not HSS.IsChannelEnabled("GUILD") then
        return false
    end
    if IsSecret(message) or type(message) ~= "string" then
        return false
    end
    return message:find("[", 1, true) ~= nil
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

local passScheduled = false

local function RunPass()
    passScheduled = false

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

    stats.passes = stats.passes + 1
    HSS.Try("communities", frame.TransformMessages, frame, predicate, transform)
end

-- One pass on the next tick (after Blizzard has rendered); calls in the same
-- tick are coalesced. Never throws.
function HSS.ScheduleCommunitiesPass()
    if passScheduled or not HSS.FeatureEnabled("communities") then
        return
    end

    if not (C_Timer and type(C_Timer.After) == "function") then
        HSS.communitiesStats.noScheduler = true
        return
    end

    passScheduled = true
    local ok = HSS.Try("communities", C_Timer.After, 0, function()
        HSS.Try("communities", RunPass)
        passScheduled = false
    end)

    if not ok then
        passScheduled = false
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
        HSS.ScheduleCommunitiesPass()
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
