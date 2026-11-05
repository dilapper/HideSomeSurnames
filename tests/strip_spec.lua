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
assert(loadfile("HideSomeSurnames/Settings.lua"))("HideSomeSurnames", HSS)

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

local eventSet = HSS.FillChatEventSet({}, { SAY = true, PARTY = true, GUILD = true, OFFICER = true })
local predicate, transform = HSS.MakeChatTransformers(eventSet, set)
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

-- ---------- settings ----------
local function loadAll()
    local H = {}
    for _, file in ipairs({ "Core", "Chat", "Settings", "UI" }) do
        assert(loadfile("HideSomeSurnames/" .. file .. ".lua"))("HideSomeSurnames", H)
    end
    return H
end

local DEFAULTS = {
    surnames = { "Mhmm" },
    chatChannels = { SAY = true, PARTY = true, GUILD = true, OFFICER = true },
}

local function sorted(t)
    local keys = {}
    for key in pairs(t) do keys[#keys + 1] = key end
    table.sort(keys)
    return table.concat(keys, ",")
end

do
    local S = loadAll()

    -- normalisation
    local function norm(input) local ok, value = S.NormalizeSurname(input); return ok and value or false end
    expect("normalize: plain", norm("Mhmm"), "Mhmm")
    expect("normalize: trims", norm("  Mhmm  "), "Mhmm")
    expect("normalize: empty", norm("   "), false)
    expect("normalize: inner space", norm("Two Words"), false)
    expect("normalize: hyphen", norm("Mhmm-Realm"), false)
    expect("normalize: pipe", norm("Mh|mm"), false)
    expect("normalize: colon", norm("Mh:mm"), false)
    expect("normalize: too long", norm(("x"):rep(33)), false)
    expect("normalize: max length ok", norm(("x"):rep(32)), ("x"):rep(32))
    expect("normalize: nil", norm(nil), false)
    expect("normalize: number", norm(5), false)

    -- first run seeds from defaults
    local db = S.LoadSettings(nil, DEFAULTS)
    expect("load: first run surnames", table.concat(db.surnames, ","), "Mhmm")
    expect("load: first run channels", sorted(S.chatEventSet),
        "CHAT_MSG_GUILD,CHAT_MSG_OFFICER,CHAT_MSG_PARTY,CHAT_MSG_PARTY_LEADER,CHAT_MSG_SAY")
    expect("load: live surname set", S.surnameSet.mhmm, true)

    -- saved data wins, same table is kept
    local saved = { surnames = { "Smith" }, chatChannels = { SAY = false, GUILD = true } }
    local loaded = S.LoadSettings(saved, DEFAULTS)
    expect("load: keeps the saved table", loaded == saved, true)
    expect("load: saved surnames win", table.concat(loaded.surnames, ","), "Smith")
    expect("load: saved false is kept", loaded.chatChannels.SAY, false)
    expect("load: missing channel uses default", loaded.chatChannels.PARTY, true)
    expect("load: live set reflects saved", S.surnameSet.mhmm == nil and S.surnameSet.smith, true)

    -- a user can legitimately empty the list
    local emptied = S.LoadSettings({ surnames = {}, chatChannels = {} }, DEFAULTS)
    expect("load: empty list stays empty", #emptied.surnames, 0)

    -- garbage never errors and never leaks through
    for index, garbage in ipairs({ "text", 42, true, {}, { surnames = "x" }, { surnames = 5, chatChannels = 5 } }) do
        local ok, result = pcall(S.LoadSettings, garbage, DEFAULTS)
        expect("load: garbage #" .. index .. " does not throw", ok, true)
        expect("load: garbage #" .. index .. " yields a table", type(result), "table")
    end
    local dirty = S.LoadSettings({
        surnames = { 1, {}, "Good", "bad name", "good", "Pi|pe", "Fine" },
        chatChannels = { SAY = "yes", WHISPER = true, GUILD = false },
    }, DEFAULTS)
    expect("load: sanitises surnames", table.concat(dirty.surnames, ","), "Good,Fine")
    expect("load: non-boolean channel uses default", dirty.chatChannels.SAY, true)
    expect("load: unknown channel dropped", dirty.chatChannels.WHISPER, nil)
    expect("load: boolean channel kept", dirty.chatChannels.GUILD, false)

    local capped = {}
    for i = 1, 30 do capped[i] = "S" .. i end
    expect("load: list capped", #S.LoadSettings({ surnames = capped }, DEFAULTS).surnames, S.MAX_SURNAMES)

    -- add / remove
    S.LoadSettings(nil, DEFAULTS)
    local changes = 0
    S.onSettingsChanged = function() changes = changes + 1 end

    local ok1 = S.AddSurname("Smith")
    expect("add: ok", ok1, true)
    expect("add: change notified", changes, 1)
    expect("add: live set updated", S.surnameSet.smith, true)
    expect("add: Dave Smith now hidden", S.StripSurname("Dave Smith", S.surnameSet), "Dave")
    local okDup, reasonDup = S.AddSurname("sMiTh")
    expect("add: duplicate (any case) rejected", okDup, false)
    expect("add: duplicate has a reason", type(reasonDup), "string")
    expect("add: rejected add does not notify", changes, 1)
    expect("add: invalid rejected", (S.AddSurname("two words")), false)
    expect("add: keeps typed casing", S.GetSurnameList()[2], "Smith")

    local okRem = S.RemoveSurname("SMITH")
    expect("remove: ok (any case)", okRem, true)
    expect("remove: live set updated", S.surnameSet.smith, nil)
    expect("remove: Dave Smith shown again", S.StripSurname("Dave Smith", S.surnameSet), "Dave Smith")
    expect("remove: missing rejected", (S.RemoveSurname("Nobody")), false)
    expect("remove: nil rejected", (S.RemoveSurname(nil)), false)

    for i = 1, S.MAX_SURNAMES do S.AddSurname("X" .. i) end
    local okFull, reasonFull = S.AddSurname("Overflow")
    expect("add: cap enforced", okFull, false)
    expect("add: cap reason", reasonFull:find("full") ~= nil, true)

    -- channels
    S.LoadSettings(nil, DEFAULTS)
    expect("channel: toggle known", S.SetChannel("GUILD", false), true)
    expect("channel: disabled", S.IsChannelEnabled("GUILD"), false)
    expect("channel: live set drops GUILD", S.chatEventSet.CHAT_MSG_GUILD, nil)
    for _, bad in ipairs({ "WHISPER", "INSTANCE_CHAT", "RAID", "YELL", "CHANNEL", "say", "", 5 }) do
        expect("channel: rejects " .. tostring(bad), S.SetChannel(bad, true), false)
    end
    expect("channel: nothing unknown stored", sorted(S.db.chatChannels), "GUILD,OFFICER,PARTY,SAY")

    -- reset
    S.AddSurname("Smith"); S.SetChannel("SAY", false)
    expect("reset: ok", S.ResetSettings(), true)
    expect("reset: surnames back to defaults", table.concat(S.GetSurnameList(), ","), "Mhmm")
    expect("reset: channels back to defaults", S.IsChannelEnabled("SAY") and S.IsChannelEnabled("GUILD"), true)

    -- a failing refresh callback never propagates
    S.onSettingsChanged = function() error("refresh blew up") end
    local okThrow = pcall(S.AddSurname, "Jones")
    expect("callback error: does not propagate", okThrow, true)
    expect("callback error: change still applied", S.surnameSet.jones, true)
    expect("callback error: counted", S.GetFeatureState("ui").failures, 1)
    S.onSettingsChanged = nil

    -- live chat filtering follows the settings, without rebuilding anything
    S.LoadSettings(nil, DEFAULTS)
    local livePredicate = S.MakeChatTransformers(S.chatEventSet, S.surnameSet)
    local function liveOffered(event) return livePredicate(LINE, 1, 1, 1, 10, 11, 12, event, {}) end
    expect("live chat: SAY on", liveOffered("CHAT_MSG_SAY"), true)
    S.SetChannel("SAY", false)
    expect("live chat: SAY off", liveOffered("CHAT_MSG_SAY"), false)
    S.SetChannel("SAY", true)
    expect("live chat: SAY back on", liveOffered("CHAT_MSG_SAY"), true)
    expect("live chat: whisper never", liveOffered("CHAT_MSG_WHISPER"), false)
end

-- ---------- options panel (stubbed client) ----------
local function makeFakeFrame(created, kind, name)
    local frame = { _scripts = {}, _text = "", _checked = false, kind = kind }
    function frame:SetScript(event, fn) self._scripts[event] = fn end
    function frame:GetText() return self._text end
    function frame:SetText(text) self._text = text end
    function frame:SetChecked(value) self._checked = value end
    function frame:GetChecked() return self._checked end
    function frame:CreateFontString() return makeFakeFrame(created, "fontstring") end
    function frame:CreateTexture() return makeFakeFrame(created, "texture") end
    setmetatable(frame, { __index = function(_, key)
        if type(key) == "string" and (key:find("^Set") or key:find("^Get") or key:find("^Show")
            or key:find("^Hide") or key:find("^Clear") or key:find("^Is")) then
            return function() end
        end
    end })
    if name then created[name] = frame end
    return frame
end

local function withClient(setup, fn)
    local saved = { CreateFrame = _G.CreateFrame, Settings = _G.Settings,
        InterfaceOptions_AddCategory = _G.InterfaceOptions_AddCategory,
        InterfaceOptionsFrame_OpenToCategory = _G.InterfaceOptionsFrame_OpenToCategory }
    local created = {}
    _G.CreateFrame = function(kind, name) return makeFakeFrame(created, kind, name) end
    _G.Settings, _G.InterfaceOptions_AddCategory, _G.InterfaceOptionsFrame_OpenToCategory = nil, nil, nil
    setup(created)
    local ok, err = pcall(fn, created)
    for key, value in pairs(saved) do _G[key] = value end
    if not ok then error(err, 0) end
end

withClient(function(created)
    created.registered = {}
    _G.Settings = {
        RegisterCanvasLayoutCategory = function(panel, name)
            return { panel = panel, name = name, GetID = function() return 77 end }
        end,
        RegisterAddOnCategory = function(category) created.registered[#created.registered + 1] = category end,
        OpenToCategory = function(id) created.openedId = id end,
    }
end, function(created)
    local U = loadAll()
    U.LoadSettings(nil, DEFAULTS)
    expect("panel (Settings API): builds", U.BuildOptions(), true)
    expect("panel (Settings API): api recorded", U.ui.api, "Settings")
    expect("panel (Settings API): registered once", #created.registered, 1)
    expect("panel (Settings API): opens by id", (U.OpenOptions()) and created.openedId, 77)

    local input = created.HideSomeSurnamesInput
    input._text = "Smith"
    input._scripts.OnEnterPressed(input)
    expect("panel: Enter in the box adds the surname", U.surnameSet.smith, true)
    expect("panel: box cleared after add", input._text, "")

    created.HideSomeSurnamesCheckGUILD._checked = false
    created.HideSomeSurnamesCheckGUILD._scripts.OnClick(created.HideSomeSurnamesCheckGUILD)
    expect("panel: unticking Guild disables it", U.IsChannelEnabled("GUILD"), false)
    expect("panel: no WHISPER checkbox exists", created.HideSomeSurnamesCheckWHISPER, nil)

    input._text = "bad name"
    local okBad = pcall(input._scripts.OnEnterPressed, input)
    expect("panel: invalid input does not throw", okBad, true)
    expect("panel: invalid input not added", U.surnameSet["bad name"], nil)
end)

withClient(function(created)
    _G.InterfaceOptions_AddCategory = function(panel) created.added = panel end
    _G.InterfaceOptionsFrame_OpenToCategory = function(panel) created.openCalls = (created.openCalls or 0) + 1 end
end, function(created)
    local U = loadAll()
    U.LoadSettings(nil, DEFAULTS)
    expect("panel (InterfaceOptions): builds", U.BuildOptions(), true)
    expect("panel (InterfaceOptions): api recorded", U.ui.api, "InterfaceOptions")
    expect("panel (InterfaceOptions): panel registered", created.added ~= nil, true)
    expect("panel (InterfaceOptions): opens", U.OpenOptions(), true)
end)

withClient(function() end, function()
    local U = loadAll()
    local ok, result = pcall(U.BuildOptions)
    expect("panel (no Options API): does not throw", ok, true)
    expect("panel (no Options API): reports unavailable", result, false)
    expect("panel (no Options API): open reports unavailable", U.OpenOptions(), false)
end)

withClient(function() end, function()
    _G.CreateFrame = function() error("template missing") end
    local U = loadAll()
    local ok, result = pcall(U.BuildOptions)
    expect("panel (CreateFrame fails): does not throw", ok, true)
    expect("panel (CreateFrame fails): reports unavailable", result, false)
end)

-- ---------- safety: never throw, fall back to full name ----------
local realStrip = HSS.StripSurnameInLinks
HSS.StripSurnameInLinks = function() error("boom") end

local okCall, outBad, rBad, extraBad
okCall, outBad, rBad, extraBad = pcall(function()
    local p, t = HSS.MakeChatTransformers(eventSet, set) -- fresh closures use patched fn
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
local _, t2 = HSS.MakeChatTransformers(eventSet, set)
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
