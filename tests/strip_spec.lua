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

-- ---------- pet / owner titles ----------
local titleSet = HSS.BuildSurnameSet({ "Mhmm", "Jones" })
local function title(text) return HSS.StripSurnameInTitle(text, titleSet) end

expect("title: pet", title("<Lappy Mhmm's Pet>"), "<Lappy's Pet>")
expect("title: no brackets", title("Lappy Mhmm's Pet"), "Lappy's Pet")
expect("title: minion", title("<Lappy Mhmm's Minion>"), "<Lappy's Minion>")
expect("title: multi-word suffix", title("<Lappy Mhmm's Water Elemental>"), "<Lappy's Water Elemental>")
expect("title: surname case-insensitive", title("<Lappy mHMM's Pet>"), "<Lappy's Pet>")
expect("title: bare apostrophe becomes 's", title("<Lappy Jones' Pet>"), "<Lappy's Pet>")
expect("title: forename ending in s keeps bare apostrophe", title("<Chris Jones' Pet>"), "<Chris' Pet>")
expect("title: other surname unchanged", title("<Dave Smith's Pet>"), "<Dave Smith's Pet>")
expect("title: already short unchanged", title("<Lappy's Pet>"), "<Lappy's Pet>")
expect("title: idempotent", title(title("<Lappy Mhmm's Pet>")), "<Lappy's Pet>")
expect("title: guild tag unchanged", title("<The Mhmm Crew>"), "<The Mhmm Crew>")
expect("title: plain player name unchanged", title("Dave Mhmm"), "Dave Mhmm")
expect("title: empty", title(""), "")
expect("title: nil", title(nil), nil)
expect("title: number", title(3), 3)
expect("title: empty set hides nothing",
    HSS.StripSurnameInTitle("<Lappy Mhmm's Pet>", HSS.BuildSurnameSet({})), "<Lappy Mhmm's Pet>")

local function loadTitleModules()
    local H = {}
    for _, file in ipairs({ "Core", "Chat", "Settings", "Tooltip" }) do
        assert(loadfile("HideSomeSurnames/" .. file .. ".lua"))("HideSomeSurnames", H)
    end
    H.LoadSettings(nil, DEFAULTS)
    return H
end

local function withGlobals(values, fn)
    local saved = {}
    for key in pairs(values) do saved[key] = _G[key] end
    for key, value in pairs(values) do _G[key] = value end
    local ok, err = pcall(fn)
    for key in pairs(values) do _G[key] = saved[key] end
    if not ok then error(err, 0) end
end

-- tooltip
do
    local T = loadTitleModules()
    local handlers = {}
    local fakeProcessor = { AddLinePreCall = function(lineType, fn) handlers[lineType] = fn end }
    local fakeEnum = { TooltipDataLineType = { None = 0, UnitName = 2, UnitOwner = 7, notANumber = "x" } }

    withGlobals({ TooltipDataProcessor = fakeProcessor, Enum = fakeEnum,
        issecretvalue = function(v) return v == "SECRET" end }, function()
        expect("tooltip: installs", T.InstallTooltipHook(), true)
        expect("tooltip: registers for UnitOwner only", T.tooltipStats.lineTypes, 1)
        expect("tooltip: nothing registered for other line types",
            handlers[0] == nil and handlers[2] == nil and handlers[7] ~= nil, true)
        expect("tooltip: second install is a no-op", T.InstallTooltipHook(), true)

        local line = { leftText = "<Lappy Mhmm's Pet>" }
        handlers[7](nil, line)
        expect("tooltip: rewrites pet title", line.leftText, "<Lappy's Pet>")
        local noBrackets = { leftText = "Lappy Mhmm's Pet" }
        handlers[7](nil, noBrackets)
        expect("tooltip: rewrites pet title without brackets", noBrackets.leftText, "Lappy's Pet")
        expect("tooltip: rewrites counted", T.tooltipStats.rewritten, 2)

        local other = { leftText = "<Dave Smith's Pet>" }
        handlers[7](nil, other)
        expect("tooltip: other surname untouched", other.leftText, "<Dave Smith's Pet>")

        local plain = { leftText = "Level 10 Beast" }
        handlers[7](nil, plain)
        expect("tooltip: unrelated line untouched", plain.leftText, "Level 10 Beast")

        local secret = { leftText = "SECRET" }
        handlers[7](nil, secret)
        expect("tooltip: secret text untouched", secret.leftText, "SECRET")

        expect("tooltip: nil lineData does not throw", pcall(handlers[7], nil, nil), true)
        expect("tooltip: non-table lineData does not throw", pcall(handlers[7], nil, "text"), true)
        expect("tooltip: recent lines recorded for debugging", #T.tooltipStats.recent >= 2, true)

        local dumped = {}
        T.DumpTitles(function(text) dumped[#dumped + 1] = text end)
        expect("tooltip: debug dump shows recent lines",
            table.concat(dumped, "\n"):find("Lappy Mhmm's Pet", 1, true) ~= nil, true)

        -- a failing stripper never reaches the game and trips the breaker at 3
        T.StripSurnameInTitle = function() error("boom") end
        local bad = { leftText = "<Lappy Mhmm's Pet>" }
        for _ = 1, 4 do
            expect("tooltip: failing stripper does not throw", pcall(handlers[7], nil, bad), true)
        end
        expect("tooltip: failing stripper leaves the line alone", bad.leftText, "<Lappy Mhmm's Pet>")
        expect("tooltip: breaker trips after 3 failures", T.FeatureEnabled("tooltip"), false)
    end)

    -- a client without a UnitOwner line type: fall back to every numeric type
    local T3 = loadTitleModules()
    local fallbackHandlers = {}
    withGlobals({
        TooltipDataProcessor = { AddLinePreCall = function(lineType, fn) fallbackHandlers[lineType] = fn end },
        Enum = { TooltipDataLineType = { None = 0, UnitName = 2, Other = 5 } },
    }, function()
        expect("tooltip fallback: installs", T3.InstallTooltipHook(), true)
        expect("tooltip fallback: registers for every numeric line type", T3.tooltipStats.lineTypes, 3)
        local line = { leftText = "<Lappy Mhmm's Pet>" }
        fallbackHandlers[5](nil, line)
        expect("tooltip fallback: still rewrites", line.leftText, "<Lappy's Pet>")
    end)

    local T2 = loadTitleModules()
    withGlobals({ TooltipDataProcessor = false, Enum = false }, function()
        expect("tooltip: no API -> reports false, no throw", select(2, pcall(T2.InstallTooltipHook)), false)
    end)
end

-- ---------- bracketed names (Guild & Communities chat pane) ----------
local function bracket(text) return HSS.StripSurnameInBracketNames(text, set) end

expect("bracket: player link",
    bracket("|Hplayer:Lappy Mhmm:1|h[Lappy Mhmm]|h: hello"),
    "|Hplayer:Lappy Mhmm:1|h[Lappy]|h: hello")
expect("bracket: other link type",
    bracket("|HcommunityPlayer:Lappy Mhmm:123|h[Lappy Mhmm]|h: hi"),
    "|HcommunityPlayer:Lappy Mhmm:123|h[Lappy]|h: hi")
expect("bracket: colour-wrapped link",
    bracket("|cff00ff00|Hplayer:Lappy Mhmm:1|h[Lappy Mhmm]|h|r: hi"),
    "|cff00ff00|Hplayer:Lappy Mhmm:1|h[Lappy]|h|r: hi")
expect("bracket: plain line start", bracket("[Lappy Mhmm]: hello"), "[Lappy]: hello")
expect("bracket: plain after colour code", bracket("|cff00ff00[Lappy Mhmm]: hello|r"), "|cff00ff00[Lappy]: hello|r")
expect("bracket: plain with colour reset before colon", bracket("|cff00ff00[Lappy Mhmm]|r: hi"),
    "|cff00ff00[Lappy]|r: hi")
expect("bracket: other surname untouched", bracket("[Dave Smith]: hello"), "[Dave Smith]: hello")
expect("bracket: link, other surname untouched",
    bracket("|Hplayer:Dave Smith:1|h[Dave Smith]|h: hello"), "|Hplayer:Dave Smith:1|h[Dave Smith]|h: hello")
expect("bracket: name later in the body untouched",
    bracket("hello [Lappy Mhmm]: hi"), "hello [Lappy Mhmm]: hi")
expect("bracket: plain name in body untouched after a link",
    bracket("|Hplayer:Lappy Mhmm:1|h[Lappy Mhmm]|h: see [Dave Mhmm]: ok"),
    "|Hplayer:Lappy Mhmm:1|h[Lappy]|h: see [Dave Mhmm]: ok")
expect("bracket: plain bracket without colon untouched", bracket("[Lappy Mhmm] hello"), "[Lappy Mhmm] hello")
expect("bracket: several links",
    bracket("|Hplayer:A Mhmm:1|h[A Mhmm]|h and |Hplayer:B Smith:2|h[B Smith]|h"),
    "|Hplayer:A Mhmm:1|h[A]|h and |Hplayer:B Smith:2|h[B Smith]|h")
expect("bracket: idempotent",
    bracket(bracket("|Hplayer:Lappy Mhmm:1|h[Lappy Mhmm]|h: hello")),
    "|Hplayer:Lappy Mhmm:1|h[Lappy]|h: hello")
expect("bracket: idempotent (plain)", bracket(bracket("[Lappy Mhmm]: hello")), "[Lappy]: hello")
expect("bracket: no brackets", bracket("just text"), "just text")
expect("bracket: empty set hides nothing",
    HSS.StripSurnameInBracketNames("[Lappy Mhmm]: hi", HSS.BuildSurnameSet({})), "[Lappy Mhmm]: hi")
expect("bracket: nil", bracket(nil), nil)
expect("bracket: number", bracket(4), 4)

-- the exact layout captured in game from the Guild & Communities pane
local REAL_LINE = "[|HplayerCommunity:Lappy Mhmm:215722452:1:1793849258293000:21228272429055|h"
    .. "|cffaad372Lappy Mhmm|r|h]: |Kw131|k"
expect("bracket (real pane line): brackets outside the link, colour-wrapped name",
    bracket(REAL_LINE),
    "[|HplayerCommunity:Lappy Mhmm:215722452:1:1793849258293000:21228272429055|h"
    .. "|cffaad372Lappy|r|h]: |Kw131|k")
expect("bracket (real pane line): idempotent", bracket(bracket(REAL_LINE)), bracket(REAL_LINE))
expect("bracket (real pane line): payload and trailing token untouched",
    bracket(REAL_LINE):find("|HplayerCommunity:Lappy Mhmm:215722452:1:1793849258293000:21228272429055|h", 1, true) ~= nil
        and bracket(REAL_LINE):sub(-11) == "]: |Kw131|k", true)
expect("bracket (real pane line): other surname untouched",
    bracket("[|HplayerCommunity:Dave Smith:1:1:2:3|h|cffaad372Dave Smith|r|h]: hi"),
    "[|HplayerCommunity:Dave Smith:1:1:2:3|h|cffaad372Dave Smith|r|h]: hi")
expect("bracket: colour-wrapped name without brackets",
    bracket("|Hplayer:Lappy Mhmm:1|h|cffaad372Lappy Mhmm|r|h: hi"),
    "|Hplayer:Lappy Mhmm:1|h|cffaad372Lappy|r|h: hi")
expect("bracket: uncoloured name without brackets",
    bracket("[|Hplayer:Lappy Mhmm:1|hLappy Mhmm|h]: hi"), "[|Hplayer:Lappy Mhmm:1|hLappy|h]: hi")
expect("bracket: brackets inside a colour-wrapped link",
    bracket("|Hplayer:Lappy Mhmm:1|h|cffaad372[Lappy Mhmm]|r|h: hi"),
    "|Hplayer:Lappy Mhmm:1|h|cffaad372[Lappy]|r|h: hi")
expect("bracket: link text with other markup is left alone",
    bracket("|Hplayer:Lappy Mhmm:1|h|cffaad372|TInterface\\Icons\\X:0|t Lappy Mhmm|r|h: hi"),
    "|Hplayer:Lappy Mhmm:1|h|cffaad372|TInterface\\Icons\\X:0|t Lappy Mhmm|r|h: hi")
expect("bracket: two real-format links, only the matching one changes",
    bracket("[|HplayerCommunity:A Mhmm:1|h|cff111111A Mhmm|r|h] [|HplayerCommunity:B Smith:2|h|cff222222B Smith|r|h]"),
    "[|HplayerCommunity:A Mhmm:1|h|cff111111A|r|h] [|HplayerCommunity:B Smith:2|h|cff222222B Smith|r|h]")
expect("bracket: a non-name link is left alone",
    bracket("|Hitem:1234:0|h[Cavalier's Boots]|h"), "|Hitem:1234:0|h[Cavalier's Boots]|h")

-- ---------- Guild & Communities pane (stubbed client) ----------
local function loadCommunities()
    local H = {}
    for _, file in ipairs({ "Core", "Chat", "Settings", "Communities" }) do
        assert(loadfile("HideSomeSurnames/" .. file .. ".lua"))("HideSomeSurnames", H)
    end
    H.LoadSettings(nil, DEFAULTS)
    return H
end

local function fakeMessageFrame(record)
    local f = {}
    function f:TransformMessages(predicateFn, transformFn)
        record.calls = (record.calls or 0) + 1
        record.predicate, record.transform = predicateFn, transformFn
    end
    return f
end

local immediateTimer = { After = function(_, fn) fn() end }

do
    -- found at the likely path
    local C = loadCommunities()
    local record = {}
    withGlobals({ CommunitiesFrame = { Chat = { MessageFrame = fakeMessageFrame(record) } },
        C_Timer = immediateTimer }, function()
        C.ScheduleCommunitiesPass()
        expect("communities: message frame found at the likely path", C.communitiesStats.path,
            "CommunitiesFrame.Chat.MessageFrame")
        expect("communities: TransformMessages called once", record.calls, 1)

        expect("communities: predicate accepts a name line", record.predicate("[Lappy Mhmm]: hi"), true)
        expect("communities: predicate rejects a line without brackets", record.predicate("hello"), false)
        expect("communities: predicate rejects nil", record.predicate(nil), false)
        local out, r, extra = record.transform("[Lappy Mhmm]: hi", 0.5, "EXTRA")
        expect("communities: transform rewrites the name", out, "[Lappy]: hi")
        expect("communities: transform keeps other args", tostring(r) .. tostring(extra), "0.5EXTRA")
        expect("communities: rewrite counted", C.communitiesStats.rewritten, 1)

        C.SetChannel("GUILD", false)
        expect("communities: Guild checkbox off -> predicate rejects", record.predicate("[Lappy Mhmm]: hi"), false)
        C.SetChannel("GUILD", true)
        expect("communities: Guild checkbox on again", record.predicate("[Lappy Mhmm]: hi"), true)

        -- a failing stripper never reaches the game and trips the breaker at 3
        C.StripSurnameInBracketNames = function() error("boom") end
        local last
        for _ = 1, 4 do last = record.transform("[Lappy Mhmm]: hi") end
        expect("communities: failing stripper returns the original line", last, "[Lappy Mhmm]: hi")
        expect("communities: breaker trips after 3 failures", C.FeatureEnabled("communities"), false)
        local before = record.calls
        C.ScheduleCommunitiesPass()
        expect("communities: disabled feature does no more passes", record.calls, before)
    end)

    -- found by searching the Chat subtree
    local D = loadCommunities()
    local recordD = {}
    local grandchild = fakeMessageFrame(recordD)
    local child = { GetChildren = function() return grandchild end }
    withGlobals({ CommunitiesFrame = { Chat = { GetChildren = function() return child end } },
        C_Timer = immediateTimer }, function()
        D.ScheduleCommunitiesPass()
        expect("communities: found by subtree search", D.communitiesStats.found, true)
        expect("communities: search path recorded", D.communitiesStats.path:find("child", 1, true) ~= nil, true)
        expect("communities: search result got the transform", recordD.calls, 1)
    end)

    -- found by field name inside Chat
    local D2 = loadCommunities()
    local recordD2 = {}
    withGlobals({ CommunitiesFrame = { Chat = { Messages = fakeMessageFrame(recordD2) } },
        C_Timer = immediateTimer }, function()
        D2.ScheduleCommunitiesPass()
        expect("communities: found by field search", D2.communitiesStats.path, "CommunitiesFrame.Chat.Messages")
    end)

    -- not available: no window, a frame without TransformMessages, a forbidden window
    for label, window in pairs({
        ["no window"] = false,
        ["no TransformMessages"] = { Chat = { MessageFrame = {} } },
        ["forbidden window"] = { IsForbidden = function() return true end, Chat = {} },
    }) do
        local E = loadCommunities()
        withGlobals({ CommunitiesFrame = window, C_Timer = immediateTimer }, function()
            local ok = pcall(E.ScheduleCommunitiesPass)
            expect("communities (" .. label .. "): does not throw", ok, true)
            expect("communities (" .. label .. "): reports not found", E.communitiesStats.found, false)
        end)
    end

    -- no timer API
    local F = loadCommunities()
    withGlobals({ CommunitiesFrame = { Chat = { MessageFrame = fakeMessageFrame({}) } }, C_Timer = false }, function()
        expect("communities (no timer): does not throw", pcall(F.ScheduleCommunitiesPass), true)
        expect("communities (no timer): recorded", F.communitiesStats.noScheduler, true)
    end)

    -- event registration: a rejected name must not throw or trip the breaker
    local G = loadCommunities()
    local registered = {}
    local eventFrame = { RegisterEvent = function(_, event)
        if event == "CLUB_MESSAGE_UPDATED" then error("unknown event") end
        registered[#registered + 1] = event
    end }
    expect("communities events: registration does not throw", pcall(G.RegisterCommunitiesEvents, eventFrame), true)
    expect("communities events: accepted ones registered", table.concat(G.communitiesStats.registered, ","),
        "CLUB_MESSAGE_ADDED,CLUB_MESSAGE_HISTORY_RECEIVED")
    expect("communities events: rejected one recorded", table.concat(G.communitiesStats.failed, ","),
        "CLUB_MESSAGE_UPDATED")
    expect("communities events: rejection doesn't count as a failure", G.GetFeatureState("communities").failures, 0)
    expect("communities events: recognises its events", G.IsCommunitiesEvent("CLUB_MESSAGE_ADDED"), true)
    expect("communities events: ignores chat events", G.IsCommunitiesEvent("CHAT_MSG_GUILD"), false)

    -- window OnShow hook
    local H2 = loadCommunities()
    local recordH = {}
    local shownHandlers = {}
    local window = { Chat = { MessageFrame = fakeMessageFrame(recordH) },
        HookScript = function(_, event, fn) shownHandlers[event] = fn end }
    withGlobals({ CommunitiesFrame = window, C_Timer = immediateTimer }, function()
        expect("communities hook: hooks the window", H2.HookCommunitiesWindow(), true)
        expect("communities hook: hooks OnShow", type(shownHandlers.OnShow), "function")
        local callsAfterHook = recordH.calls
        shownHandlers.OnShow()
        -- OnShow schedules passes at 0, 0.5 and 2 seconds (all immediate under this stub timer)
        expect("communities hook: OnShow triggers its passes", recordH.calls, callsAfterHook + 3)
        shownHandlers.OnShow = nil
        expect("communities hook: second call is a no-op", H2.HookCommunitiesWindow(), true)
        expect("communities hook: not hooked twice", shownHandlers.OnShow, nil)
    end)
    withGlobals({ CommunitiesFrame = false }, function()
        local I = loadCommunities()
        expect("communities hook: no window -> false, no throw", select(2, pcall(I.HookCommunitiesWindow)), false)
    end)

    -- delayed passes use their own delays and coalesce per delay
    local K = loadCommunities()
    local delays, pending = {}, {}
    local manualTimer = { After = function(delay, fn) delays[#delays + 1] = delay; pending[#pending + 1] = fn end }
    withGlobals({ CommunitiesFrame = { Chat = { MessageFrame = fakeMessageFrame({}) } }, C_Timer = manualTimer }, function()
        K.ScheduleCommunitiesPass(); K.ScheduleCommunitiesPass()
        K.ScheduleCommunitiesPass(0.5); K.ScheduleCommunitiesPass(0.5)
        expect("communities: same-delay passes are coalesced", table.concat(delays, ","), "0,0.5")
        for _, fn in ipairs(pending) do fn() end
        K.ScheduleCommunitiesPass()
        expect("communities: can schedule again after it ran", #delays, 3)
    end)

    -- diagnostics: raw lines are recorded, escaped, with their argument types
    local L = loadCommunities()
    local recordL = {}
    withGlobals({ CommunitiesFrame = { Chat = { MessageFrame = fakeMessageFrame(recordL) } },
        C_Timer = immediateTimer, issecretvalue = function(v) return v == "SECRET" end }, function()
        L.ScheduleCommunitiesPass()
        recordL.predicate("|Hplayer:Lappy Mhmm:1|h[Lappy Mhmm]|h: hi", 1, 0.5, "x")
        recordL.predicate("no brackets here")
        recordL.predicate("SECRET")
        recordL.predicate(nil)
        local stats = L.communitiesStats
        expect("diag: lines counted", stats.predicateCalls, 4)
        expect("diag: lines without a bracket counted", stats.noBracket, 3)
        expect("diag: bracketed line sampled", #stats.samples, 1)
        expect("diag: sample is escaped so link codes are visible",
            stats.samples[1].text, "||Hplayer:Lappy Mhmm:1||h[Lappy Mhmm]||h: hi")
        expect("diag: argument types recorded", stats.samples[1].args, "string,number,number,string")
        expect("diag: accepted flag recorded", stats.samples[1].accepted, true)
        for i = 1, 10 do recordL.predicate("[Name " .. i .. "]: x") end
        expect("diag: samples are capped", #stats.samples, 6)
    end)

    -- hooking AddMessage: new lines trigger a pass, our own pass cannot loop
    local M = loadCommunities()
    local hookCount = 0
    local passCount = 0
    local msgFrame = { AddMessage = function() end }
    function msgFrame:TransformMessages()
        passCount = passCount + 1
        self:AddMessage("re-added by our own pass") -- worst case: a transform that re-adds lines
    end
    withGlobals({
        CommunitiesFrame = { Chat = { MessageFrame = msgFrame } },
        C_Timer = immediateTimer,
        -- behaves like the real one: the original runs, then the hook
        hooksecurefunc = function(frame, name, fn)
            local original = frame[name]
            frame[name] = function(...) original(...); fn(...) end
            hookCount = hookCount + 1
        end,
    }, function()
        M.ScheduleCommunitiesPass()
        expect("addmessage: hook installed once", hookCount, 1)
        expect("addmessage: reported as hooked", M.communitiesStats.addMessageHooked, true)
        expect("addmessage: our own pass did not trigger another", passCount, 1)

        msgFrame:AddMessage("the game adds a line")
        expect("addmessage: a new line triggers a pass", passCount, 2)

        M.ScheduleCommunitiesPass()
        expect("addmessage: not hooked again", hookCount, 1)
    end)
    withGlobals({ CommunitiesFrame = { Chat = { MessageFrame = fakeMessageFrame({}) } },
        C_Timer = immediateTimer, hooksecurefunc = function() error("no such method") end }, function()
        local N = loadCommunities()
        expect("addmessage: a failing hook does not throw", pcall(N.ScheduleCommunitiesPass), true)
    end)

    -- /hss debug under
    local J = loadCommunities()
    local focus = { GetObjectType = function() return "Frame" end, GetName = function() return "SomeFrame" end,
        GetParent = function() return nil end, TransformMessages = function() end }
    local dumped = {}
    withGlobals({ GetMouseFoci = function() return { focus } end, C_Timer = immediateTimer,
        CommunitiesFrame = false }, function()
        J.DumpUnderMouse(function(line) dumped[#dumped + 1] = line end, "2")
        local text = table.concat(dumped, "\n")
        expect("under: reports the frame under the mouse", text:find("SomeFrame", 1, true) ~= nil, true)
        expect("under: reports TransformMessages", text:find("TransformMessages=true", 1, true) ~= nil, true)
    end)
    local noApi = {}
    withGlobals({ GetMouseFoci = false, GetMouseFocus = false, C_Timer = immediateTimer }, function()
        expect("under: no mouse API does not throw",
            pcall(J.DumpUnderMouse, function(line) noApi[#noApi + 1] = line end, 1), true)
        expect("under: no mouse API is reported", table.concat(noApi, "\n"):find("nothing found", 1, true) ~= nil, true)
    end)
end

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
