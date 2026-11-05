local _, HSS = ...

-- Options panel for Esc > Options > AddOns. Plain frames and long-standing
-- templates only. Every script handler is wrapped so a UI problem can never
-- raise a Lua error; if the panel can't be built, the slash commands still
-- work (see HideSomeSurnames.lua).

local PANEL_NAME = "HideSomeSurnames"

local CHANNEL_LABELS = {
    SAY     = "Say",
    PARTY   = "Party (incl. party leader)",
    GUILD   = "Guild",
    OFFICER = "Guild officer",
}

local ui = {
    api = "none",   -- which Options API registered the panel
    panel = nil,
    category = nil,
}
HSS.ui = ui

local input, statusText, addButton
local rows = {}
local checkboxes = {}

-- Wraps a script handler so it can't throw into the game.
local function Safe(fn)
    return function(...)
        HSS.Try("ui", fn, ...)
    end
end

local function SetStatus(message, isError)
    if not statusText then
        return
    end
    statusText:SetText(message or "")
    if isError then
        statusText:SetTextColor(1, 0.35, 0.35)
    else
        statusText:SetTextColor(0.4, 1, 0.4)
    end
end

local function Refresh()
    local list = HSS.GetSurnameList()

    for index, row in ipairs(rows) do
        local surname = list[index]
        if surname then
            row.label:SetText(surname)
            row.surname = surname
            row.frame:Show()
        else
            row.surname = nil
            row.frame:Hide()
        end
    end

    for channel, checkbox in pairs(checkboxes) do
        checkbox:SetChecked(HSS.IsChannelEnabled(channel))
    end
end

local function DoAdd()
    local ok, result = HSS.AddSurname(input:GetText())
    if ok then
        input:SetText("")
        SetStatus("Added " .. result .. ".")
    else
        SetStatus("Couldn't add: " .. tostring(result) .. ".", true)
    end
    Refresh()
end

local function BuildPanel()
    local panel = CreateFrame("Frame", "HideSomeSurnamesOptionsPanel")
    panel.name = PANEL_NAME

    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("HideSomeSurnames")

    local description = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    description:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    description:SetWidth(580)
    description:SetJustifyH("LEFT")
    description:SetText("Players with these surnames are shown by forename only on nameplates, "
        .. "unit frames and in the chosen chat channels. Whispers, mail and invites still "
        .. "use the full name. Other players' surnames stay visible.")

    -- Left column: surnames ------------------------------------------------
    local surnameHeader = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    surnameHeader:SetPoint("TOPLEFT", description, "BOTTOMLEFT", 0, -20)
    surnameHeader:SetText("Surnames to hide")

    input = CreateFrame("EditBox", "HideSomeSurnamesInput", panel, "InputBoxTemplate")
    input:SetSize(160, 24)
    input:SetPoint("TOPLEFT", surnameHeader, "BOTTOMLEFT", 6, -8)
    input:SetAutoFocus(false)
    input:SetMaxLetters(32)
    input:SetScript("OnEnterPressed", Safe(function()
        DoAdd()
        input:ClearFocus()
    end))
    input:SetScript("OnEscapePressed", Safe(function()
        input:ClearFocus()
    end))

    addButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    addButton:SetSize(60, 24)
    addButton:SetPoint("LEFT", input, "RIGHT", 8, 0)
    addButton:SetText("Add")
    addButton:SetScript("OnClick", Safe(DoAdd))

    statusText = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    statusText:SetPoint("TOPLEFT", input, "BOTTOMLEFT", -6, -6)
    statusText:SetWidth(280)
    statusText:SetJustifyH("LEFT")
    statusText:SetText("")

    for index = 1, HSS.MAX_SURNAMES do
        local frame = CreateFrame("Frame", nil, panel)
        frame:SetSize(280, 22)
        frame:SetPoint("TOPLEFT", statusText, "BOTTOMLEFT", 0, -6 - (index - 1) * 22)

        local label = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        label:SetPoint("LEFT", frame, "LEFT", 6, 0)
        label:SetJustifyH("LEFT")

        local remove = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
        remove:SetSize(70, 20)
        remove:SetPoint("RIGHT", frame, "RIGHT", 0, 0)
        remove:SetText("Remove")

        local row = { frame = frame, label = label }
        remove:SetScript("OnClick", Safe(function()
            if row.surname then
                local ok, result = HSS.RemoveSurname(row.surname)
                if ok then
                    SetStatus("Removed " .. result .. ".")
                else
                    SetStatus("Couldn't remove: " .. tostring(result) .. ".", true)
                end
                Refresh()
            end
        end))

        frame:Hide()
        rows[index] = row
    end

    -- Right column: chat channels -------------------------------------------
    local chatHeader = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    chatHeader:SetPoint("TOPLEFT", surnameHeader, "TOPLEFT", 340, 0)
    chatHeader:SetText("Hide in these chat channels")

    local previous = chatHeader
    for _, channel in ipairs(HSS.CHAT_CHANNELS) do
        local checkbox = CreateFrame("CheckButton", "HideSomeSurnamesCheck" .. channel, panel,
            "UICheckButtonTemplate")
        checkbox:SetSize(26, 26)
        checkbox:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", 0, -4)

        local label = checkbox.Text or _G["HideSomeSurnamesCheck" .. channel .. "Text"]
        if label then
            label:SetText(CHANNEL_LABELS[channel] or channel)
        end

        checkbox:SetScript("OnClick", Safe(function(self)
            HSS.SetChannel(channel, self:GetChecked() and true or false)
            Refresh()
        end))

        checkboxes[channel] = checkbox
        previous = checkbox
    end

    local note = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    note:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", 0, -12)
    note:SetWidth(240)
    note:SetJustifyH("LEFT")
    note:SetText("Whispers, world/custom channels, yell, raid and instance chat always show full "
        .. "names.\n\nRemoving a surname or turning a channel off can't restore names in chat "
        .. "lines that were already shortened; new lines show the full name.")

    panel:SetScript("OnShow", Safe(Refresh))

    ui.panel = panel
    Refresh()
    return panel
end

local function Register(panel)
    if type(Settings) == "table"
        and type(Settings.RegisterCanvasLayoutCategory) == "function"
        and type(Settings.RegisterAddOnCategory) == "function"
    then
        local category = Settings.RegisterCanvasLayoutCategory(panel, PANEL_NAME)
        Settings.RegisterAddOnCategory(category)
        ui.category = category
        ui.api = "Settings"
        return true
    end

    if type(InterfaceOptions_AddCategory) == "function" then
        InterfaceOptions_AddCategory(panel)
        ui.api = "InterfaceOptions"
        return true
    end

    return false
end

-- Builds and registers the panel. Returns true on success; never throws.
function HSS.BuildOptions()
    if ui.panel then
        return true
    end

    local ok, result = HSS.Try("ui", function()
        local panel = BuildPanel()
        return Register(panel)
    end)

    return ok and result == true
end

-- Opens the panel. Returns true if an Options API accepted the request.
function HSS.OpenOptions()
    if not ui.panel then
        return false
    end

    local ok, result = HSS.Try("ui", function()
        if ui.api == "Settings" and type(Settings.OpenToCategory) == "function" then
            local target = ui.category
            if target and type(target.GetID) == "function" then
                Settings.OpenToCategory(target:GetID())
            else
                Settings.OpenToCategory(PANEL_NAME)
            end
            return true
        end

        if ui.api == "InterfaceOptions" and type(InterfaceOptionsFrame_OpenToCategory) == "function" then
            -- Called twice: the first call can open the window on the wrong page.
            InterfaceOptionsFrame_OpenToCategory(ui.panel)
            InterfaceOptionsFrame_OpenToCategory(ui.panel)
            return true
        end

        return false
    end)

    return ok and result == true
end
