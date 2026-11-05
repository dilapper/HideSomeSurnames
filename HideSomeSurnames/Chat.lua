local _, HSS = ...

-- Chat support. Blizzard renders each line normally; afterwards we call the
-- chat frame's own TransformMessages() to rewrite only the visible name inside
-- player links. We never replace any Blizzard chat function, never touch the
-- link payload, and never touch whispers.
--
-- Nothing here touches WoW globals at load time, so the logic can be tested
-- with a plain Lua interpreter.

local IsSecret = HSS.IsSecret

-- Config channel name -> chat events. Only channels listed here can ever be
-- enabled; anything else in the config (e.g. WHISPER) is ignored.
local CHANNEL_EVENTS = {
    SAY     = { "CHAT_MSG_SAY" },
    PARTY   = { "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER" },
    GUILD   = { "CHAT_MSG_GUILD" },
    OFFICER = { "CHAT_MSG_OFFICER" },
}

local CHANNEL_ORDER = { "SAY", "PARTY", "GUILD", "OFFICER" }

-- Returns an ordered list of event names for the enabled channels.
function HSS.ChatEventList(chatChannels)
    local list = {}
    for _, channel in ipairs(CHANNEL_ORDER) do
        if chatChannels and chatChannels[channel] then
            for _, event in ipairs(CHANNEL_EVENTS[channel]) do
                list[#list + 1] = event
            end
        end
    end
    return list
end

local function ToSet(list)
    local set = {}
    for _, value in ipairs(list) do
        set[value] = true
    end
    return set
end

HSS.chatStats = {
    seen = 0,          -- lines offered to the predicate
    noEvent = 0,       -- lines skipped because the event arg was missing/secret
    transformed = 0,   -- lines actually rewritten
    lastEvent = nil,
    passes = 0,
    noScheduler = false,
}

-- TransformMessages callback arguments:
--   message, r, g, b, infoID, accessID, typeID, event, eventArgs, formatter, ...
local function ShouldTransform(eventSet, message, _, _, _, _, _, _, event)
    local stats = HSS.chatStats
    stats.seen = stats.seen + 1

    if IsSecret(event) or type(event) ~= "string" then
        stats.noEvent = stats.noEvent + 1
        return false
    end

    stats.lastEvent = event

    if not eventSet[event] then
        return false
    end

    if IsSecret(message) or type(message) ~= "string" then
        return false
    end

    return message:find("|Hplayer:", 1, true) ~= nil
end

-- Builds the predicate/transform pair handed to TransformMessages.
-- Both are failure-proof: a predicate error means "leave the line alone", a
-- transform error returns the original line and arguments untouched.
function HSS.MakeChatTransformers(eventList, surnameSet)
    local eventSet = ToSet(eventList)

    local function predicate(...)
        local ok, result = HSS.Try("chat", ShouldTransform, eventSet, ...)
        return ok and result == true
    end

    local function transform(message, ...)
        if not HSS.FeatureEnabled("chat") then
            return message, ...
        end

        local ok, result = HSS.Try("chat", HSS.StripSurnameInLinks, message, surnameSet)
        if ok and type(result) == "string" and not IsSecret(result) then
            if result ~= message then
                HSS.chatStats.transformed = HSS.chatStats.transformed + 1
            end
            return result, ...
        end

        return message, ...
    end

    return predicate, transform
end

-- ============================================================
-- Passes over the live chat frames (needs the WoW client)
-- ============================================================

local predicate, transform
local passScheduled = false

local function ForEachChatFrame(fn)
    local seen = {}

    local function visit(frame)
        if frame and not seen[frame] then
            seen[frame] = true
            if not (frame.IsForbidden and frame:IsForbidden()) then
                fn(frame)
            end
        end
    end

    if type(CHAT_FRAMES) == "table" then
        for _, frameName in pairs(CHAT_FRAMES) do
            visit(_G[frameName])
        end
    end

    for i = 1, NUM_CHAT_WINDOWS or 10 do
        visit(_G["ChatFrame" .. i])
    end
end

function HSS.HasChatTransformApi()
    local frame = _G.ChatFrame1
    return frame ~= nil
        and type(frame.TransformMessages) == "function"
        and C_Timer ~= nil
        and type(C_Timer.After) == "function"
end

local function RunPass()
    passScheduled = false

    if not HSS.FeatureEnabled("chat") or not predicate then
        return
    end

    HSS.chatStats.passes = HSS.chatStats.passes + 1

    ForEachChatFrame(function(frame)
        if type(frame.TransformMessages) == "function" then
            HSS.Try("chat", frame.TransformMessages, frame, predicate, transform)
        end
    end)
end

-- Call once at login with the configured events/surnames.
function HSS.InitChat(eventList, surnameSet)
    predicate, transform = HSS.MakeChatTransformers(eventList, surnameSet)
end

-- Schedules one pass on the next tick (after Blizzard has finished rendering).
-- Multiple calls in the same tick are coalesced.
function HSS.ScheduleChatPass()
    if passScheduled or not predicate or not HSS.FeatureEnabled("chat") then
        return
    end

    if not (C_Timer and type(C_Timer.After) == "function") then
        HSS.chatStats.noScheduler = true
        return
    end

    passScheduled = true
    local ok = HSS.Try("chat", C_Timer.After, 0, function()
        HSS.Try("chat", RunPass)
        passScheduled = false
    end)

    if not ok then
        passScheduled = false
    end
end
