local Details = _G.Details
---@type detailsframework
local DF = _G.DetailsFramework
local _, FSDamageLogger = ...
local _GetSpellInfo = Details.GetSpellInfo
local LibWindow = LibStub("LibWindow-1.1")

-- =========================
-- Version (from .toc / C_AddOns)
-- =========================
local function GetMeta(addon, key)
    if C_AddOns and C_AddOns.GetAddOnMetadata then
        return C_AddOns.GetAddOnMetadata(addon, key)
    elseif GetAddOnMetadata then
        return GetAddOnMetadata(addon, key)
    end
end
local ADDON_VERSION = GetMeta("FSDamageLogger", "Version") or "unknown"
C_ChatInfo.RegisterAddonMessagePrefix("FSDL_VERSION")
local verFrame = CreateFrame("Frame")
verFrame:RegisterEvent("CHAT_MSG_ADDON")
verFrame:SetScript("OnEvent", function(_, event, prefix, message)
    if event ~= "CHAT_MSG_ADDON" or prefix ~= "FSDL_VERSION" then return end
    local serverVersion = tostring(message or "")
    if serverVersion ~= ADDON_VERSION then
        print("|cffff2020FSDL is outdated, please update the AddOn. [https://github.com/anbushgm/FSDamageLogger]|r (required:", serverVersion .. ", current:", ADDON_VERSION .. ")")
    end
end)

-- =========================
-- Data from 4 independant tables
-- =========================
local DATA = {
    DAMAGE       = {}, -- FSDL_DAMAGE
    HEAL         = {}, -- FSDL_HEAL
    DAMAGE_TAKEN = {}, -- FSDL_DAMAGE_T
    HEAL_TAKEN   = {}, -- FSDL_HEAL_T
}
local ACTIVE_TAB = "DAMAGE"
local TABS = {
    { key="DAMAGE",       label="Damage" },
    { key="HEAL",         label="Heal" },
    { key="DAMAGE_TAKEN", label="Damage Taken" },
    { key="HEAL_TAKEN",   label="Heal Taken" },
}

-- Chunks: (prefix, sender)
local chunkBuffers = {}  -- [prefix] = { [sender] = {parts={}, total=nil} }

-- =========================
-- UI sizes
-- =========================
local PANEL_W, PANEL_H = 520, 420
local LINE_H = 20

local headerTable = {
    {text="",            width=20},
    {text="Spell Name",  width=150},
    {text="Amount",      width=80},
    {text="Source",      width=120},
    {text="DmgType",     width=70},
    {text="Spell ID",    width=60},
}
local headerOptions = { padding=2 }

local F = {} -- refs

local function OpenDetailWindow(spellName, spellID, amount, logText)
    if not F.Detail then
        local detail = DF:CreateSimplePanel(UIParent, 520, 420, "Spell Logs")
        detail:SetFrameStrata("DIALOG")

        local scroll = CreateFrame("ScrollFrame", nil, detail, "UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT", 10, -50)
        scroll:SetPoint("BOTTOMRIGHT", -30, 10)

        local edit = CreateFrame("EditBox", nil, scroll)
        edit:SetMultiLine(true)
        edit:SetFontObject("GameFontHighlightSmall")
        edit:SetAutoFocus(false)
        edit:SetWidth(460)
        edit:SetJustifyH("LEFT")
        edit:SetJustifyV("TOP")
        edit:EnableMouse(true)
        scroll:SetScrollChild(edit)

        detail.edit = edit
        F.Detail = detail
    end

    local txt = string.format("Spell Name: |cffffd100%s|r\nSpell ID: |cff00ccff%d|r\nAmount: |cffff5555%d|r",
        spellName or "Unknown", spellID or 0, amount or 0)
    if logText and logText ~= "" then
        txt = txt .. "\n\nLog Data:\n" .. logText
    end

    F.Detail.edit:SetText(txt)
    F.Detail.edit:HighlightText(0, 0)
    F.Detail:Show()
end

local function createLineFunc(self, index)
    local line = CreateFrame("button", "$parentLine" .. index, self, "BackdropTemplate")
    line:SetPoint("TOPLEFT", self, "TOPLEFT", 1, -((index-1)*(LINE_H+1)) - 1)
    line:SetSize(self:GetWidth()-12, LINE_H)
    line:SetBackdrop({bgFile=[[Interface\Tooltips\UI-Tooltip-Background]], tileSize=64, tile=true})
    line:SetBackdropColor(.2,.2,.2,0.2)

    line:SetScript("OnEnter", function(s) s:SetBackdropColor(.8,.8,.8,0.4) end)
    line:SetScript("OnLeave", function(s) s:SetBackdropColor(.2,.2,.2,0.2) end)

    DF:Mixin(line, DF.HeaderFunctions)

    local icon = line:CreateTexture("$parentSpellIcon", "OVERLAY")
    icon:SetSize(LINE_H-2, LINE_H-2)

    local spellNameText = DF:CreateLabel(line, "", 10, "white")
    local damageText    = DF:CreateLabel(line, "", 10, "white")
    local sourceText    = DF:CreateLabel(line, "", 10, "white")
    local dmgTypeText   = DF:CreateLabel(line, "", 10, "white")
    local spellIDText   = DF:CreateLabel(line, "", 10, "white")

    line:AddFrameToHeaderAlignment(icon)
    line:AddFrameToHeaderAlignment(spellNameText)
    line:AddFrameToHeaderAlignment(damageText)
    line:AddFrameToHeaderAlignment(sourceText)
    line:AddFrameToHeaderAlignment(dmgTypeText)
    line:AddFrameToHeaderAlignment(spellIDText)
    line:AlignWithHeader(F.Header, "left")

    line.Icon = icon
    line.SpellNameText = spellNameText
    line.DamageText    = damageText
    line.SourceNameText= sourceText
    line.DmgTypeText   = dmgTypeText
    line.SpellIDText   = spellIDText

    line.SetEmpty = function(s)
        s.SpellName=nil; s.SpellID=nil; s.Amount=nil; s.Log=nil
        s.Icon:SetTexture(nil)
        s.SpellNameText.text=""; s.DamageText.text=""; s.SourceNameText.text=""
        s.DmgTypeText.text=""; s.SpellIDText.text=""
    end

    line:SetScript("OnClick", function(s)
        OpenDetailWindow(s.SpellName, s.SpellID, s.Amount, s.Log)
    end)

    return line
end

local function makeRefreshFunc()
    return function(self, data, offset, totalLines)
        local ToK = Details:GetCurrentToKFunction()

        for i=1,totalLines do
            local idx = i + offset
            local ev = data[idx]
            local line = self:GetLine(i)

            if ev then
                local spellID, spellName, amount, sourceName, dmgType, logText = unpack(ev)
                local name, _, icon = _GetSpellInfo(spellID or 1)
                local shownName = name or spellName or "Unknown"

                line.SpellID   = spellID
                line.SpellName = shownName
                line.Amount    = amount or 0
                line.Log       = logText or ""

                line.Icon:SetTexture(icon)
                line.Icon:SetTexCoord(.1,.9,.1,.9)
                line.SpellNameText.text = shownName
                line.DamageText.text    = " " .. ToK(_, line.Amount)
                line.SourceNameText.text= sourceName or "Unknown"
                line.DmgTypeText.text   = dmgType or "-"
                line.SpellIDText.text   = spellID or ""
                line:Show()
            else
                line:SetEmpty()
                line:Hide()
            end
        end
    end
end

local function highlightTab(btn, hl)
    if not btn then return end
    btn:SetAlpha(hl and 1 or 0.65)
end

local function SwitchTab(key)
    ACTIVE_TAB = key
    if F.Scroll then
        F.Scroll:SetData(DATA[ACTIVE_TAB])
        F.Scroll:Refresh()
    end
    for k, b in pairs(F.TabButtons) do
        highlightTab(b, k==ACTIVE_TAB)
    end
end

local function CreateMainWindow()
    local frame = DF:CreateSimplePanel(UIParent, PANEL_W, PANEL_H, ".debug fsdl")
    frame:SetFrameStrata("DIALOG")
    frame:Hide()
    F.Frame = frame

    if not Details.damage_scroll_position then
        Details.damage_scroll_position = {point="CENTER", x=0, y=0, scale=1}
    end
    LibWindow.RegisterConfig(frame, Details.damage_scroll_position)
    LibWindow.MakeDraggable(frame)
    LibWindow.RestorePosition(frame)
    frame:SetScale(Details.damage_scroll_position.scale)

    -- вкладки
    F.TabButtons = {}
    local x = 8
    for _, t in ipairs(TABS) do
        local b = DF:CreateButton(frame, function() SwitchTab(t.key) end, 1, 1, t.label)
        b:SetPoint("TOPLEFT", frame, "TOPLEFT", x, -32)
        b:SetSize(120, 22)
        F.TabButtons[t.key] = b
        x = x + 125
    end

    -- title
    local header = DF:CreateHeader(frame, headerTable, headerOptions)
    header:SetPoint("TOPLEFT", frame, "TOPLEFT", 5, -70)
    F.Header = header

    -- dynamic calculating of height and lines count
    local scrollTopOffset = 90
    local scrollH = PANEL_H - scrollTopOffset - 20
    local lines = math.floor((scrollH - 2) / (LINE_H + 1))
    if lines < 8 then lines = 8 end

    local scroll = DF:CreateScrollBox(frame, "$parentScroll", makeRefreshFunc(), DATA[ACTIVE_TAB], PANEL_W-20, scrollH, lines, LINE_H)
    DF:ReskinSlider(scroll)
    scroll:SetPoint("TOPLEFT", frame, "TOPLEFT", 5, -scrollTopOffset)
    F.Scroll = scroll
    for i=1,lines do scroll:CreateLine(createLineFunc) end

    SwitchTab(ACTIVE_TAB)
    return frame
end

-- =========================
-- Messages recieving
-- =========================
C_ChatInfo.RegisterAddonMessagePrefix("FSDL_DAMAGE")
C_ChatInfo.RegisterAddonMessagePrefix("FSDL_HEAL")
C_ChatInfo.RegisterAddonMessagePrefix("FSDL_DAMAGE_T")
C_ChatInfo.RegisterAddonMessagePrefix("FSDL_HEAL_T")

local prefixToTab = {
    FSDL_DAMAGE   = "DAMAGE",
    FSDL_HEAL     = "HEAL",
    FSDL_DAMAGE_T = "DAMAGE_TAKEN",
    FSDL_HEAL_T   = "HEAL_TAKEN",
}

local function addRow(tabKey, data)
    -- line structure: {spellID, spellName, amount, sourceName, dmgType, logText}
    local spellID = tonumber(data["SpellID"])
    local spellName = data["SpellName"] or _GetSpellInfo(spellID) or "Unknown"
    local amount = tonumber(data["Amount"]) or 0
    local sourceName = data["SourceName"] or "Unknown"
    local dt = data["DamageType"]
    if dt == "DIRECT_DAMAGE" then dt = "SWING" end
    local logText = data["Log"] or ""

    table.insert(DATA[tabKey], 1, { spellID, spellName, amount, sourceName, dt or "-", logText })

    if F.Scroll and ACTIVE_TAB == tabKey then
        F.Scroll:SetData(DATA[ACTIVE_TAB])
        F.Scroll:Refresh()
    end
end

local listener = CreateFrame("Frame")
listener:RegisterEvent("CHAT_MSG_ADDON")
listener:SetScript("OnEvent", function(_, _, prefix, message, channel, sender)
    local tabKey = prefixToTab[prefix]
    if not tabKey then return end

    -- buffer by key prefix+sender
    chunkBuffers[prefix] = chunkBuffers[prefix] or {}
    local bucket = chunkBuffers[prefix][sender] or { parts={}, total=nil }
    chunkBuffers[prefix][sender] = bucket

    local part, total, chunk = message:match("^PART%|(%d+)%/(%d+)%|(.*)$")
    if part then
        part = tonumber(part); total = tonumber(total)
        bucket.parts[part] = chunk
        if not bucket.total then bucket.total = total end
        local count = 0 for _ in pairs(bucket.parts) do count = count + 1 end
        if count < bucket.total then return end
        -- build and clean
        local list = {}
        for i=1,bucket.total do list[i] = bucket.parts[i] or "" end
        message = table.concat(list)
        bucket.parts = {}; bucket.total = nil
    end

    local data = {}
    for piece in string.gmatch(message, "([^|]+)") do
        local k,v = piece:match("([^=]+)=(.*)")
        if k and v then data[k]=v end
    end

    addRow(tabKey, data)
end)

-- =========================
-- Command
-- =========================
SlashCmdList["FSDAMAGELOGGER"] = function()
    if not F.Frame then CreateMainWindow() end
    F.Frame:Show()
end
SLASH_FSDAMAGELOGGER1 = "/fsdl"
SLASH_FSDAMAGELOGGER2 = "/fsdamagelogger"
