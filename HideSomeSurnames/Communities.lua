local _, HSS = ...

-- Chat pane of the Guild & Communities window (the pane only: never the member
-- roster, the guild name, or names inside message text).
--
-- That pane is the window's own message display, so the normal chat support
-- never sees it. We let Blizzard render, then use the pane's own
-- TransformMessages() to rewrite the visible name in each player link. Nothing
-- is replaced, link data is untouched, and any failure leaves the line exactly
-- as Blizzard wrote it.
--
-- Nothing here touches WoW globals at load time (testable with plain Lua).

local IsSecret = HSS.IsSecret

local MESSAGE_EVENTS = {
    "CLUB_MESSAGE_ADDED",
    "CLUB_MESSAGE_HISTORY_RECEIVED",
    "CLUB_MESSAGE_UPDATED",
}

HSS.communitiesStats = {
    found = false,
    passes = 0,
    rewritten = 0,
    registered = {},   -- events we registered
    failed = {},       -- events the client rejected
    shownHooked = false,
    addMessageHooked = false,
}

local function IsForbidden(object)
    return object.IsForbidden ~= nil and object:IsForbidden()
end

local function HasTransform(object)
    return type(object) == "table"
        and type(object.TransformMessages) == "function"
        and not IsForbidden(object)
end

-- The pane's message frame, or nil.
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
        return chat.MessageFrame
    end

    return nil
end

-- TransformMessages callbacks. These lines don't come from CHAT_MSG_* events,
-- so there is no channel to look at: the window follows the Guild checkbox.
local function ShouldTransform(message)
    return HSS.IsChannelEnabled("GUILD")
        and not IsSecret(message)
        and type(message) == "string"
        and message:find("|H", 1, true) ~= nil
end

local function predicate(...)
    local ok, result = HSS.Try("communities", ShouldTransform, ...)
    return ok and result == true
end

local function transform(message, ...)
    local ok, result = HSS.Try("communities", HSS.StripSurnameInCommunityLinks, message, HSS.surnameSet)
    if ok and type(result) == "string" and not IsSecret(result) then
        if result ~= message then
            HSS.communitiesStats.rewritten = HSS.communitiesStats.rewritten + 1
        end
        return result, ...
    end

    return message, ...
end

local scheduled = {}   -- delay -> true while a pass with that delay is pending
local inPass = false    -- true while our own TransformMessages call is running
local hookedFrames = setmetatable({}, { __mode = "k" })

-- Rewrite whenever a line is added to the pane, so history that arrives after
-- our first pass is still handled. Ignored while our own pass runs so it can
-- never feed itself.
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
    local frame = HSS.FindCommunitiesMessageFrame()
    stats.found = frame ~= nil

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
