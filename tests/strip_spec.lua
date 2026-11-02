-- Run from the repo root:  lua tests/strip_spec.lua
local HSS = {}
assert(loadfile("HideSomeSurnames/Core.lua"))("HideSomeSurnames", HSS)

local set = HSS.BuildSurnameSet({ "Mhmm", "Other" })
local failures = 0

local function check(name, input, expected)
    local got = HSS.StripSurname(input, set)
    if got ~= expected then
        failures = failures + 1
        print(("FAIL %s: %s -> %s (expected %s)"):format(name, tostring(input), tostring(got), tostring(expected)))
    else
        print("ok   " .. name)
    end
end

check("matching surname",        "Dave Mhmm",        "Dave")
check("case-insensitive",        "Dave mHMM",        "Dave")
check("second listed surname",   "Matt Other",       "Matt")
check("non-matching kept",       "Dave Smith",       "Dave Smith")
check("no surname",              "Dave",             "Dave")
check("extra spaces",            "Dave   Mhmm  ",    "Dave")
check("realm suffix kept",       "Dave Mhmm-Realm",  "Dave-Realm")
check("realm, other surname",    "Dave Smith-Realm", "Dave Smith-Realm")
check("no surname, realm only",  "Dave-Realm",       "Dave-Realm")
check("partial surname no match","Dave Mhmmm",       "Dave Mhmmm")
check("empty string",            "",                 "")
check("nil",                     nil,                nil)
check("non-string",              42,                 42)

local empty = HSS.StripSurname("Dave Mhmm", HSS.BuildSurnameSet({}))
if empty ~= "Dave Mhmm" then failures = failures + 1; print("FAIL empty set") else print("ok   empty set") end

local function expect(name, got, expected)
    if got ~= expected then
        failures = failures + 1
        print(("FAIL %s: got %s (expected %s)"):format(name, tostring(got), tostring(expected)))
    else
        print("ok   " .. name)
    end
end

-- ---------- player links in chat lines ----------
assert(loadfile("HideSomeSurnames/Chat.lua"))("HideSomeSurnames", HSS)

local function links(input) return HSS.StripSurnameInLinks(input, set) end

expect("link: bracketed sender",
    links("|Hplayer:Dave Mhmm:12:GUILD|h[Dave Mhmm]|h: hi"),
    "|Hplayer:Dave Mhmm:12:GUILD|h[Dave]|h: hi")
expect("link: colour codes survive",
    links("|cffc79c6e|Hplayer:Dave Mhmm:1:SAY|h[Dave Mhmm]|h|r says: yo"),
    "|cffc79c6e|Hplayer:Dave Mhmm:1:SAY|h[Dave]|h|r says: yo")
expect("link: non-matching surname untouched",
    links("|Hplayer:Dave Smith:1:SAY|h[Dave Smith]|h says: yo"),
    "|Hplayer:Dave Smith:1:SAY|h[Dave Smith]|h says: yo")
expect("link: two links, only matching one changed",
    links("|Hplayer:A Mhmm:1|h[A Mhmm]|h and |Hplayer:B Smith:2|h[B Smith]|h"),
    "|Hplayer:A Mhmm:1|h[A]|h and |Hplayer:B Smith:2|h[B Smith]|h")
expect("link: idempotent",
    links(links("|Hplayer:Dave Mhmm:1|h[Dave Mhmm]|h x")),
    "|Hplayer:Dave Mhmm:1|h[Dave]|h x")
expect("link: no links unchanged", links("just text Dave Mhmm"), "just text Dave Mhmm")
expect("link: plain-text name in body untouched",
    links("|Hplayer:A Mhmm:1|h[A Mhmm]|h: tell Dave Mhmm"),
    "|Hplayer:A Mhmm:1|h[A]|h: tell Dave Mhmm")
expect("link: realm in payload, visible without realm",
    links("|Hplayer:Dave Mhmm-Realm:1|h[Dave Mhmm]|h"),
    "|Hplayer:Dave Mhmm-Realm:1|h[Dave]|h")
expect("link: payload never altered",
    select(2, links("|Hplayer:Dave Mhmm:1|h[Dave Mhmm]|h"):find("|Hplayer:Dave Mhmm:1|h", 1, true)) ~= nil,
    true)
expect("link: nil", links(nil), nil)
expect("link: number", links(7), 7)

-- ---------- chat channel filter ----------
local eventList = HSS.ChatEventList({ SAY = true, PARTY = true, GUILD = true, OFFICER = true, WHISPER = true })
expect("channels: five events only", table.concat(eventList, ","),
    "CHAT_MSG_SAY,CHAT_MSG_PARTY,CHAT_MSG_PARTY_LEADER,CHAT_MSG_GUILD,CHAT_MSG_OFFICER")
expect("channels: disabled channel dropped",
    table.concat(HSS.ChatEventList({ SAY = true, GUILD = false }), ","), "CHAT_MSG_SAY")
expect("channels: nil config", #HSS.ChatEventList(nil), 0)

local predicate, transform = HSS.MakeChatTransformers(eventList, set)
local LINE = "|Hplayer:Dave Mhmm:1|h[Dave Mhmm]|h: hi"

local function offered(event)
    -- message, r, g, b, infoID, accessID, typeID, event, eventArgs
    return predicate(LINE, 1, 1, 1, 10, 11, 12, event, {})
end

for _, event in ipairs(eventList) do
    expect("predicate accepts " .. event, offered(event), true)
end
for _, event in ipairs({ "CHAT_MSG_WHISPER", "CHAT_MSG_WHISPER_INFORM", "CHAT_MSG_INSTANCE_CHAT",
    "CHAT_MSG_INSTANCE_CHAT_LEADER", "CHAT_MSG_RAID", "CHAT_MSG_YELL", "CHAT_MSG_CHANNEL",
    "CHAT_MSG_EMOTE" }) do
    expect("predicate rejects " .. event, offered(event), false)
end
expect("predicate rejects nil event", offered(nil), false)
expect("predicate rejects non-string message",
    predicate(nil, 1, 1, 1, 10, 11, 12, "CHAT_MSG_SAY", {}), false)
expect("predicate rejects line without links",
    predicate("hello", 1, 1, 1, 10, 11, 12, "CHAT_MSG_SAY", {}), false)

local out, r, g, b, infoID, accessID, typeID, event, args, fmt, extra =
    transform(LINE, 0.1, 0.2, 0.3, 10, 11, 12, "CHAT_MSG_SAY", "ARGS", "FMT", "EXTRA")
expect("transform rewrites message", out, "|Hplayer:Dave Mhmm:1|h[Dave]|h: hi")
expect("transform passes other args through",
    table.concat({ r, g, b, infoID, accessID, typeID, event, args, fmt, extra }, ","),
    "0.1,0.2,0.3,10,11,12,CHAT_MSG_SAY,ARGS,FMT,EXTRA")

-- ---------- safety: never throw, fall back to full name ----------
local realStrip = HSS.StripSurnameInLinks
HSS.StripSurnameInLinks = function() error("boom") end

local okCall, outBad, rBad, extraBad
okCall, outBad, rBad, extraBad = pcall(function()
    local p, t = HSS.MakeChatTransformers(eventList, set) -- fresh closures use patched fn
    return t(LINE, 0.5, "X")
end)
expect("safety: transform error does not propagate", okCall, true)
expect("safety: failed transform returns original message", outBad, LINE)
expect("safety: failed transform keeps args", tostring(rBad) .. tostring(extraBad), "0.5X")

local state = HSS.GetFeatureState("chat")
expect("safety: failures counted", state.failures, 1)
expect("safety: error text recorded", state.lastError ~= nil, true)

local notified
HSS.onFeatureDisabled = function(feature) notified = feature end
local _, t2 = HSS.MakeChatTransformers(eventList, set)
t2(LINE); t2(LINE)
expect("safety: breaker trips after 3 failures", HSS.FeatureEnabled("chat"), false)
expect("safety: disable callback fired", notified, "chat")

HSS.StripSurnameInLinks = realStrip -- the broken function is "fixed", but the feature stays off
local outOff = t2(LINE)
expect("safety: disabled feature shows full name", outOff, LINE)
expect("safety: disabled predicate rejects", predicate(LINE, 1, 1, 1, 10, 11, 12, "CHAT_MSG_SAY", {}), false)

local okTry, resTry = HSS.Try("other", function() error("x") end)
expect("safety: Try swallows errors", okTry, false)
expect("safety: Try success path", select(2, HSS.Try("fine", function(a) return a * 2 end, 21)), 42)

if failures > 0 then os.exit(1) end
print("all passed")
