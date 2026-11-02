local ADDON_NAME, HSS = ...

local VERSION = "0.1.0"
local PREFIX = "|cff33ff99HideSomeSurnames|r "

local IsSecret = HSS.IsSecret
local surnameSet = HSS.BuildSurnameSet(HSS.surnames)

local function Print(msg)
    print(PREFIX .. msg)
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

local hookTargets = {
    "CompactUnitFrame_UpdateName", -- nameplates, raid-style party frames
    "UnitFrame_Update",            -- player / target / focus / party frames
}

local hooked = {}

local function InstallHooks()
    for _, funcName in ipairs(hookTargets) do
        if not hooked[funcName] and type(_G[funcName]) == "function" then
            hooksecurefunc(funcName, UpdateFrameName)
            hooked[funcName] = true
        end
    end
end

-- ============================================================
-- EVENTS
-- ============================================================

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")

events:SetScript("OnEvent", function()
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
end)

-- ============================================================
-- SLASH COMMANDS
-- ============================================================

local function Debug()
    Print("v" .. VERSION .. " debug")

    local version, build, _, interface = GetBuildInfo()
    print("  client: " .. tostring(version) .. " build " .. tostring(build)
        .. " interface " .. tostring(interface) .. " (TOC says 16001)")

    for _, funcName in ipairs(hookTargets) do
        print("  " .. funcName .. ": exists="
            .. tostring(type(_G[funcName]) == "function")
            .. " hooked=" .. tostring(hooked[funcName] == true))
    end

    print("  issecretvalue available: " .. tostring(issecretvalue ~= nil))

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
end

SLASH_HIDESOMESURNAMES1 = "/hss"
SLASH_HIDESOMESURNAMES2 = "/hidesomesurnames"

SlashCmdList.HIDESOMESURNAMES = function(msg)
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
    print("|cffffff00/hss debug|r - show diagnostics")
end
