local ADDON_NAME, HSS = ...

local VERSION = "0.5.0"
local PREFIX = "|cff33ff99HideSomeSurnames|r "

local IsSecret = HSS.IsSecret

-- Live sets owned by Settings.lua. They start empty (nothing is hidden) and are
-- filled from the saved settings at ADDON_LOADED; edits update them in place.
local surnameSet = HSS.surnameSet

local function Print(msg)
    print(PREFIX .. msg)
end

-- Safety rule for this whole file: if we can't hide a surname, it stays
-- visible. Everything handed to the game goes through HSS.Try, and a feature
-- that keeps failing switches itself off (see Core.lua).

HSS.onFeatureDisabled = function(feature)
    if feature == "ui" then
        Print("|cffff5555the settings panel switched off after repeated errors.|r "
            .. "Use /hss add, /hss remove and /hss list instead.")
    else
        Print("|cffff5555" .. feature .. " hiding switched off after repeated errors;|r "
            .. "names are shown in full. Run /hss debug for details.")
    end
end

-- ============================================================
-- UNIT FRAMES / NAMEPLATES
-- ============================================================
-- Blizzard writes the full name first; this runs afterwards as a secure
-- post-hook and overwrites only the visible text. Nothing is replaced, and
-- the unit's real name is never changed.

local function UpdateFrameName(frame)
    -- Nothing to hide: skip all the unit lookups (this runs on every frame update).
    if not frame or next(surnameSet) == nil then
        return
    end

    -- Forbidden frames (e.g. nameplates in restricted content) allow almost
    -- nothing; IsForbidden must be checked before any other access.
    if frame.IsForbidden and frame:IsForbidden() then
        return
    end

    local unit = frame.unit
    local nameRegion = frame.name

    if not unit or not nameRegion or IsSecret(unit) or type(unit) ~= "string" then
        return
    end

    if nameRegion.IsForbidden and nameRegion:IsForbidden() then
        return
    end

    if not UnitExists(unit) or not UnitIsPlayer(unit) then
        return
    end

    local fullName = GetUnitName(unit, true)
    if IsSecret(fullName) or type(fullName) ~= "string" then
        return
    end

    local display = HSS.StripSurname(fullName, surnameSet)
    if display ~= fullName then
        nameRegion:SetText(display)
    end
end

local function SafeUpdateFrameName(frame)
    HSS.Try("frames", UpdateFrameName, frame)
end

local hookTargets = {
    "CompactUnitFrame_UpdateName", -- nameplates, raid-style party frames
    "UnitFrame_Update",            -- player / target / focus / party frames
}

local hooked = {}

local function InstallHooks()
    for _, funcName in ipairs(hookTargets) do
        if not hooked[funcName] and type(_G[funcName]) == "function" then
            hooksecurefunc(funcName, SafeUpdateFrameName)
            hooked[funcName] = true
        end
    end
end

-- After a settings change: hide newly added surnames on frames that are
-- already on screen. Names that should be shown again come back the next time
-- Blizzard refreshes that frame (we never call Blizzard's update functions
-- ourselves). Best effort and failure-proof.
local function RefreshVisibleFrames()
    if C_NamePlate and type(C_NamePlate.GetNamePlates) == "function" then
        for _, plate in ipairs(C_NamePlate.GetNamePlates() or {}) do
            if plate and not (plate.IsForbidden and plate:IsForbidden()) then
                SafeUpdateFrameName(plate.UnitFrame)
            end
        end
    end

    for _, frameName in ipairs({ "PlayerFrame", "TargetFrame", "FocusFrame",
        "PartyMemberFrame1", "PartyMemberFrame2", "PartyMemberFrame3", "PartyMemberFrame4" }) do
        SafeUpdateFrameName(_G[frameName])
    end
end

HSS.onSettingsChanged = function()
    HSS.ScheduleChatPass()
    HSS.ScheduleCommunitiesPass()
    RefreshVisibleFrames()
end

-- ============================================================
-- EVENTS
-- ============================================================

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_ENTERING_WORLD")

-- Exactly the four channels that can ever be enabled (never whisper, instance,
-- raid, ...). Which of them actually act is decided live by the event set.
do
    local all = {}
    for _, channel in ipairs(HSS.CHAT_CHANNELS) do
        all[channel] = true
    end
    for _, event in ipairs(HSS.ChatEventList(all)) do
        events:RegisterEvent(event)
    end
end

-- Guild & Communities window chat: each event is registered separately because
-- an unknown event name raises an error (see Communities.lua).
HSS.RegisterCommunitiesEvents(events)

local function LoadSavedSettings()
    local defaults = { surnames = HSS.surnames, chatChannels = HSS.chatChannels }
    local saved = _G.HideSomeSurnamesDB

    local ok, db = HSS.Try("startup", HSS.LoadSettings, saved, defaults)
    if ok and type(db) == "table" then
        _G.HideSomeSurnamesDB = db
    else
        -- Unusable saved data: run on the defaults for this session.
        HSS.Try("startup", HSS.LoadSettings, nil, defaults)
    end
end

local function OnLogin()
    InstallHooks()

    local missing = {}
    for _, funcName in ipairs(hookTargets) do
        if not hooked[funcName] then
            missing[#missing + 1] = funcName
        end
    end

    if #missing > 0 then
        Print("|cffff5555warning:|r Blizzard function(s) not found: "
            .. table.concat(missing, ", ")
            .. ". Some names may not be shortened. Run /hss debug.")
    end

    HSS.InitChat(HSS.chatEventSet, surnameSet)

    if HSS.HasChatTransformApi() then
        HSS.ScheduleChatPass() -- chat history restored at login
    else
        Print("|cffff5555warning:|r chat API not found; chat names will be shown in full. "
            .. "Run /hss debug.")
    end

    if not HSS.InstallTooltipHook() then
        Print("|cffff5555warning:|r tooltip API not found; pet titles in tooltips will be shown "
            .. "in full. Run /hss debug titles.")
    end

    if not HSS.BuildOptions() then
        Print("The settings panel isn't available on this client; "
            .. "use /hss add, /hss remove and /hss list.")
    end

    -- The Communities window may already exist, or load later (see ADDON_LOADED).
    HSS.Try("communities", HSS.HookCommunitiesWindow)
end

events:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 == ADDON_NAME then
            LoadSavedSettings()
        elseif arg1 == "Blizzard_Communities" then
            HSS.Try("communities", HSS.HookCommunitiesWindow)
        end
    elseif event == "PLAYER_LOGIN" then
        HSS.Try("startup", OnLogin)
    elseif HSS.IsCommunitiesEvent(event) then
        HSS.ScheduleCommunitiesPass() -- already failure-proof
    else
        HSS.ScheduleChatPass() -- chat events and PLAYER_ENTERING_WORLD; already failure-proof
    end
end)

-- ============================================================
-- SLASH COMMANDS
-- ============================================================

local function Status()
    Print("v" .. VERSION)

    local list = HSS.GetSurnameList()
    print("Hiding surname(s): " .. (#list > 0 and table.concat(list, ", ") or "(none)"))

    local channels = {}
    for _, channel in ipairs(HSS.CHAT_CHANNELS) do
        if HSS.IsChannelEnabled(channel) then
            channels[#channels + 1] = channel:lower()
        end
    end
    print("In chat: " .. (#channels > 0 and table.concat(channels, ", ") or "(none)")
        .. " (plus nameplates, unit frames, pet titles in tooltips and the Guild & Communities chat pane)")

    print("|cffffff00/hss config|r - open settings    |cffffff00/hss add <surname>|r    "
        .. "|cffffff00/hss remove <surname>|r    |cffffff00/hss list|r    "
        .. "|cffffff00/hss reset|r    |cffffff00/hss debug|r")
end

local function Debug()
    Print("v" .. VERSION .. " debug")

    local version, build, _, interface = GetBuildInfo()
    print("  client: " .. tostring(version) .. " build " .. tostring(build)
        .. " interface " .. tostring(interface) .. " (TOC says 16001)")

    print("  issecretvalue available: " .. tostring(issecretvalue ~= nil))
    print("  saved settings loaded: " .. tostring(HSS.db ~= nil))
    print("  settings panel registered via: " .. tostring(HSS.ui and HSS.ui.api or "none"))

    print("  -- frames --")
    for _, funcName in ipairs(hookTargets) do
        print("  " .. funcName .. ": exists="
            .. tostring(type(_G[funcName]) == "function")
            .. " hooked=" .. tostring(hooked[funcName] == true))
    end

    if UnitExists("target") then
        local raw = GetUnitName("target", true)
        if IsSecret(raw) then
            print("  target name is a secret value")
        else
            print("  target: '" .. tostring(raw) .. "' -> '"
                .. tostring(HSS.StripSurname(raw, surnameSet)) .. "'")
        end
    else
        print("  no target selected (target a player and run again)")
    end

    print("  -- chat --")
    local stats = HSS.chatStats
    local active = {}
    for event in pairs(HSS.chatEventSet) do
        active[#active + 1] = event
    end
    table.sort(active)
    print("  active events: " .. (#active > 0 and table.concat(active, ", ") or "(none)"))
    print("  TransformMessages + C_Timer available: " .. tostring(HSS.HasChatTransformApi()))
    print("  passes=" .. stats.passes .. " linesSeen=" .. stats.seen
        .. " rewritten=" .. stats.transformed
        .. " skippedNoEvent=" .. stats.noEvent
        .. " lastEvent=" .. tostring(stats.lastEvent))
    if stats.noEvent > 0 and stats.lastEvent == nil then
        print("  |cffff5555the event argument never reached us; chat cannot be filtered by channel|r")
    end

    print("  -- pet titles --")
    print("  tooltip handler registered: " .. tostring(HSS.tooltipStats.registered)
        .. " rewritten=" .. HSS.tooltipStats.rewritten
        .. "  (details: /hss debug titles)")

    print("  -- guild & communities chat pane --")
    local cstats = HSS.communitiesStats
    print("  window message frame found: " .. tostring(cstats.found)
        .. "  passes=" .. cstats.passes .. " rewritten=" .. cstats.rewritten
        .. " windowHooked=" .. tostring(cstats.shownHooked))
    print("  events registered: "
        .. (#cstats.registered > 0 and table.concat(cstats.registered, ", ") or "(none)")
        .. (#cstats.failed > 0 and ("  rejected by client: " .. table.concat(cstats.failed, ", ")) or ""))

    print("  -- safety --")
    for _, name in ipairs({ "frames", "chat", "tooltip", "communities", "ui", "startup" }) do
        local state = HSS.GetFeatureState(name)
        print("  " .. name .. ": failures=" .. state.failures
            .. " disabled=" .. tostring(state.disabled)
            .. (state.lastError and (" lastError=" .. state.lastError) or ""))
    end
end

local function HandleSlash(msg)
    msg = strtrim(msg or "")
    local command, argument = msg:match("^(%S+)%s*(.-)$")
    command = (command or ""):lower()

    if command == "debug" then
        if argument:lower() == "titles" then
            HSS.DumpTitles(print)
        else
            Debug()
        end
    elseif command == "config" or command == "options" then
        if not HSS.OpenOptions() then
            Print("The settings panel isn't available; use /hss add, /hss remove and /hss list.")
        end
    elseif command == "add" then
        local ok, result = HSS.AddSurname(argument)
        Print(ok and ("now hiding the surname " .. result .. ".")
            or ("|cffff5555couldn't add:|r " .. tostring(result) .. "."))
    elseif command == "remove" then
        local ok, result = HSS.RemoveSurname(argument)
        Print(ok and ("no longer hiding " .. result .. ".")
            or ("|cffff5555couldn't remove:|r " .. tostring(result) .. "."))
    elseif command == "list" then
        local list = HSS.GetSurnameList()
        Print("hiding: " .. (#list > 0 and table.concat(list, ", ") or "(none)"))
    elseif command == "reset" then
        Print(HSS.ResetSettings() and "settings reset to the defaults in Config.lua."
            or "settings aren't loaded yet.")
    else
        Status()
    end
end

SLASH_HIDESOMESURNAMES1 = "/hss"
SLASH_HIDESOMESURNAMES2 = "/hidesomesurnames"

SlashCmdList.HIDESOMESURNAMES = function(msg)
    local ok, err = pcall(HandleSlash, msg)
    if not ok then
        Print("|cffff5555command failed:|r " .. tostring(err))
    end
end
