local ADDON_NAME, HSS = ...

local VERSION = "0.2.0"
local PREFIX = "|cff33ff99HideSomeSurnames|r "

local IsSecret = HSS.IsSecret
local surnameSet = HSS.BuildSurnameSet(HSS.surnames)
local chatEvents = HSS.ChatEventList(HSS.chatChannels)

local function Print(msg)
    print(PREFIX .. msg)
end

-- Safety rule for this whole file: if we can't hide a surname, it stays
-- visible. Everything handed to the game goes through HSS.Try, and a feature
-- that keeps failing switches itself off (see Core.lua).

HSS.onFeatureDisabled = function(feature)
    Print("|cffff5555" .. feature .. " hiding switched off after repeated errors;|r "
        .. "names are shown in full. Run /hss debug for details.")
end

-- ============================================================
-- UNIT FRAMES / NAMEPLATES
-- ============================================================
-- Blizzard writes the full name first; this runs afterwards as a secure
-- post-hook and overwrites only the visible text. Nothing is replaced, and
-- the unit's real name is never changed.

local function UpdateFrameName(frame)
    if not frame then
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

-- ============================================================
-- EVENTS
-- ============================================================

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

    HSS.InitChat(chatEvents, surnameSet)

    if #chatEvents > 0 then
        if HSS.HasChatTransformApi() then
            HSS.ScheduleChatPass() -- chat history restored at login
        else
            Print("|cffff5555warning:|r chat API not found; chat names will be shown in full. "
                .. "Run /hss debug.")
        end
    end
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_ENTERING_WORLD")

-- Only the channels enabled in Config.lua are ever registered.
for _, event in ipairs(chatEvents) do
    events:RegisterEvent(event)
end

events:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        HSS.Try("startup", OnLogin)
    elseif event == "PLAYER_ENTERING_WORLD" then
        HSS.Try("chat", HSS.ScheduleChatPass)
    else
        HSS.ScheduleChatPass() -- already failure-proof
    end
end)

-- ============================================================
-- SLASH COMMANDS
-- ============================================================

local function Debug()
    Print("v" .. VERSION .. " debug")

    local version, build, _, interface = GetBuildInfo()
    print("  client: " .. tostring(version) .. " build " .. tostring(build)
        .. " interface " .. tostring(interface) .. " (TOC says 16001)")

    print("  issecretvalue available: " .. tostring(issecretvalue ~= nil))

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
    print("  events registered: "
        .. (#chatEvents > 0 and table.concat(chatEvents, ", ") or "(none)"))
    print("  TransformMessages + C_Timer available: " .. tostring(HSS.HasChatTransformApi()))
    print("  passes=" .. stats.passes .. " linesSeen=" .. stats.seen
        .. " rewritten=" .. stats.transformed
        .. " skippedNoEvent=" .. stats.noEvent
        .. " lastEvent=" .. tostring(stats.lastEvent))
    if stats.noEvent > 0 and stats.lastEvent == nil then
        print("  |cffff5555the event argument never reached us; chat cannot be filtered by channel|r")
    end

    print("  -- safety --")
    for _, name in ipairs({ "frames", "chat", "startup" }) do
        local state = HSS.GetFeatureState(name)
        print("  " .. name .. ": failures=" .. state.failures
            .. " disabled=" .. tostring(state.disabled)
            .. (state.lastError and (" lastError=" .. state.lastError) or ""))
    end
end

local function HandleSlash(msg)
    msg = strtrim(msg or ""):lower()

    if msg == "debug" then
        Debug()
        return
    end

    Print("v" .. VERSION)
    local list = {}
    for _, surname in ipairs(HSS.surnames) do
        list[#list + 1] = surname
    end
    print("Hiding surname(s): " .. (#list > 0 and table.concat(list, ", ") or "(none)"))
    local channels = {}
    for _, channel in ipairs({ "SAY", "PARTY", "GUILD", "OFFICER" }) do
        if HSS.chatChannels and HSS.chatChannels[channel] then
            channels[#channels + 1] = channel:lower()
        end
    end
    print("In chat: " .. (#channels > 0 and table.concat(channels, ", ") or "(none)")
        .. " (plus nameplates and unit frames)")
    print("|cffffff00/hss debug|r - show diagnostics")
end

SLASH_HIDESOMESURNAMES1 = "/hss"
SLASH_HIDESOMESURNAMES2 = "/hidesomesurnames"

SlashCmdList.HIDESOMESURNAMES = function(msg)
    local ok, err = pcall(HandleSlash, msg)
    if not ok then
        Print("|cffff5555command failed:|r " .. tostring(err))
    end
end
