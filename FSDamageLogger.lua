local _, FSDamageLogger = ...

local function RegisterSlashCommand(handler)
    SlashCmdList["FSDAMAGELOGGER"] = handler
    SLASH_FSDAMAGELOGGER1 = "/fsdl"
    SLASH_FSDAMAGELOGGER2 = "/fsdamagelogger"
end

local Details = _G.Details
---@type detailsframework
local DF = _G.DetailsFramework
if not Details or not DF then
    RegisterSlashCommand(function()
        print("|cffff2020FSDL: Details is not loaded. Enable Details and run /reload.|r")
    end)
    return
end

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
local PANEL_W, PANEL_H = 760, 420
local LINE_H = 20

local headerTable = {
    {text="",            width=20},
    {text="Spell Name",  width=180, canSort=true, key="spellname"},
    {text="Amount",      width=80, canSort=true, key="amount"},
    {text="Time",        width=90, canSort=true, key="time", selected=true},
    {text="Source",      width=120},
    {text="DmgType",     width=70},
    {text="Spell ID",    width=60, canSort=true, key="spellid"},
}
local headerOptions = { padding=2 }

local F = {} -- refs
local SORT_COLUMN_INDEX = 4
local SORT_ORDER = "DESC"
local SEARCH_TEXT = ""
local IS_PAUSED = false
local DETAIL_W, DETAIL_H = 520, 420

local function GetSortValue(row, columnIndex)
    if columnIndex == 2 then
        return string.lower(tostring(row[2] or ""))
    elseif columnIndex == 3 then
        return tonumber(row[3]) or 0
    elseif columnIndex == 4 then
        return tonumber(row[6]) or 0
    elseif columnIndex == 7 then
        return tonumber(row[1]) or 0
    end
    return 0
end

local function SortTabData(tabKey)
    local rows = DATA[tabKey]
    if not rows or #rows <= 1 or not SORT_COLUMN_INDEX then return end

    table.sort(rows, function(a, b)
        local av = GetSortValue(a, SORT_COLUMN_INDEX)
        local bv = GetSortValue(b, SORT_COLUMN_INDEX)
        if av == bv then
            local at = tonumber(a[6]) or 0
            local bt = tonumber(b[6]) or 0
            if at == bt then
                return (tonumber(a[3]) or 0) > (tonumber(b[3]) or 0)
            end
            return at > bt
        end

        if SORT_ORDER == "ASC" then
            return av < bv
        end
        return av > bv
    end)
end

local function NormalizeSearchText(text)
    local q = string.lower(tostring(text or ""))
    q = q:gsub("^%s+", ""):gsub("%s+$", "")
    return q
end

local function RowMatchesSearch(row, query)
    if query == "" then
        return true
    end

    local spellID = tostring(row[1] or "")
    local spellName = string.lower(tostring(row[2] or ""))
    local amountValue = tonumber(row[3]) or 0
    local amountRaw = tostring(amountValue)
    local sourceName = string.lower(tostring(row[4] or ""))

    local ToK = Details:GetCurrentToKFunction()
    local amountShort = string.lower(tostring(ToK and ToK(_, amountValue) or amountRaw))

    if spellName:find(query, 1, true) then return true end
    if spellID:find(query, 1, true) then return true end
    if sourceName:find(query, 1, true) then return true end
    if amountRaw:find(query, 1, true) then return true end
    if amountShort:find(query, 1, true) then return true end

    return false
end

local function FormatTimeMS(timeMS)
    if not timeMS then
        return "-"
    end
    local total = tonumber(timeMS) or 0
    if total < 0 then total = 0 end
    local sec = math.floor(total / 1000)
    local ms = total % 1000
    return string.format("%d.%03d", sec, ms)
end

local function BuildVisibleData(tabKey)
    local rows = DATA[tabKey] or {}
    if SEARCH_TEXT == "" then
        return rows
    end

    local filtered = {}
    for i = 1, #rows do
        local row = rows[i]
        if RowMatchesSearch(row, SEARCH_TEXT) then
            filtered[#filtered + 1] = row
        end
    end
    return filtered
end

local function RefreshActiveScroll()
    if not F.Scroll then return end
    F.Scroll:SetData(BuildVisibleData(ACTIVE_TAB))
    F.Scroll:Refresh()
end

local function SetPaused(paused)
    IS_PAUSED = paused and true or false
    if F.PauseButton then
        F.PauseButton:SetText(IS_PAUSED and "Resume" or "Pause")
    end
end

local function OpenDetailWindow(spellName, spellID, amount, logText)
    if not F.Detail then
        local detail = DF:CreateSimplePanel(UIParent, DETAIL_W, DETAIL_H, "Spell Logs")
        detail:SetFrameStrata("DIALOG")
        detail.userPositioned = false
        detail.autoPositioned = false
        detail:HookScript("OnDragStop", function(self)
            self.userPositioned = true
        end)

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

    if not F.Detail.userPositioned and (not F.Detail.autoPositioned) and F.Frame and F.Frame:IsShown() then
        local parentW = UIParent:GetWidth() or 0
        local mainLeft = F.Frame:GetLeft()
        local mainRight = F.Frame:GetRight()
        local gap = 12
        local margin = 8

        F.Detail:ClearAllPoints()
        if mainRight and parentW > 0 and (mainRight + gap + DETAIL_W + margin) <= parentW then
            F.Detail:SetPoint("TOPLEFT", F.Frame, "TOPRIGHT", gap, 0)
        elseif mainLeft and (mainLeft - gap - DETAIL_W - margin) >= 0 then
            F.Detail:SetPoint("TOPRIGHT", F.Frame, "TOPLEFT", -gap, 0)
        else
            F.Detail:SetPoint("CENTER", UIParent, "CENTER")
        end
        F.Detail.autoPositioned = true
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
    local timeText      = DF:CreateLabel(line, "", 10, "white")
    local sourceText    = DF:CreateLabel(line, "", 10, "white")
    local dmgTypeText   = DF:CreateLabel(line, "", 10, "white")
    local spellIDText   = DF:CreateLabel(line, "", 10, "white")

    line:AddFrameToHeaderAlignment(icon)
    line:AddFrameToHeaderAlignment(spellNameText)
    line:AddFrameToHeaderAlignment(damageText)
    line:AddFrameToHeaderAlignment(timeText)
    line:AddFrameToHeaderAlignment(sourceText)
    line:AddFrameToHeaderAlignment(dmgTypeText)
    line:AddFrameToHeaderAlignment(spellIDText)
    line:AlignWithHeader(F.Header, "left")

    line.Icon = icon
    line.SpellNameText = spellNameText
    line.DamageText    = damageText
    line.TimeText      = timeText
    line.SourceNameText= sourceText
    line.DmgTypeText   = dmgTypeText
    line.SpellIDText   = spellIDText

    line.SetEmpty = function(s)
        s.SpellName=nil; s.SpellID=nil; s.Amount=nil; s.TimeMS=nil; s.Log=nil
        s.Icon:SetTexture(nil)
        s.SpellNameText.text=""; s.DamageText.text=""; s.SourceNameText.text=""
        s.TimeText.text=""
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
                local spellID, spellName, amount, sourceName, dmgType, timeMS, logText = unpack(ev)
                local name, _, icon = _GetSpellInfo(spellID or 1)
                local shownName = name or spellName or "Unknown"

                line.SpellID   = spellID
                line.SpellName = shownName
                line.Amount    = amount or 0
                line.TimeMS    = timeMS
                line.Log       = logText or ""

                line.Icon:SetTexture(icon)
                line.Icon:SetTexCoord(.1,.9,.1,.9)
                line.SpellNameText.text = shownName
                line.DamageText.text    = " " .. ToK(_, line.Amount)
                line.TimeText.text      = " " .. FormatTimeMS(timeMS)
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
    btn:SetAlpha(hl and 1 or 0.78)
    if btn.OriginalLabel and type(btn.SetText) == "function" then
        if hl then
            btn:SetText("|cffffd100" .. btn.OriginalLabel .. "|r")
        else
            btn:SetText("|cffd6d6d6" .. btn.OriginalLabel .. "|r")
        end
    end
end

local function SwitchTab(key)
    ACTIVE_TAB = key
    SortTabData(ACTIVE_TAB)
    RefreshActiveScroll()
    for k, b in pairs(F.TabButtons) do
        highlightTab(b, k==ACTIVE_TAB)
    end
end

headerOptions.header_click_callback = function(_, _, columnIndex, columnOrder)
    SORT_COLUMN_INDEX = columnIndex
    SORT_ORDER = columnOrder
    SortTabData(ACTIVE_TAB)
    RefreshActiveScroll()
end

local sessionTimeStartAt
local function GetNowSec()
    if GetTimePreciseSec then
        return GetTimePreciseSec()
    end
    return GetTime()
end

local function GetClientEventTimeMS()
    local nowSec = GetNowSec()
    if not sessionTimeStartAt then
        sessionTimeStartAt = nowSec
    end

    return math.floor(((nowSec - sessionTimeStartAt) * 1000) + 0.5)
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

    -- vertical tabs
    local sidebarX = 8
    local sidebarY = -32
    local sidebarW = 130
    local sidebarH = PANEL_H - 40
    local tabH = 22
    local tabGap = 4

    local sidebar = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    sidebar:SetPoint("TOPLEFT", frame, "TOPLEFT", sidebarX, sidebarY)
    sidebar:SetSize(sidebarW, sidebarH)
    sidebar:SetBackdrop({
        bgFile = [[Interface\Tooltips\UI-Tooltip-Background]],
        edgeFile = [[Interface\Buttons\WHITE8X8]],
        edgeSize = 1,
    })
    sidebar:SetBackdropColor(0.06, 0.06, 0.06, 0.85)
    sidebar:SetBackdropBorderColor(0.35, 0.35, 0.35, 0.9)

    F.TabButtons = {}
    for i, t in ipairs(TABS) do
        local b = DF:CreateButton(frame, function() SwitchTab(t.key) end, 1, 1, t.label)
        b:SetPoint("TOPLEFT", sidebar, "TOPLEFT", 4, -4 - ((i - 1) * (tabH + tabGap)))
        b:SetSize(sidebarW - 8, tabH)
        b.OriginalLabel = t.label
        F.TabButtons[t.key] = b
    end

    local contentX = sidebarX + sidebarW + 8
    local contentW = PANEL_W - contentX - 8
    local controlsY = -32

    local pauseButton = DF:CreateButton(frame, function()
        SetPaused(not IS_PAUSED)
    end, 1, 1, "Pause")
    pauseButton:SetPoint("TOPLEFT", frame, "TOPLEFT", contentX, controlsY)
    pauseButton:SetSize(78, 20)
    if pauseButton.widget and pauseButton.widget.SetBackdrop then
        pauseButton.widget:SetBackdrop({
            bgFile = [[Interface\Tooltips\UI-Tooltip-Background]],
            edgeFile = [[Interface\Buttons\WHITE8X8]],
            edgeSize = 1,
        })
        pauseButton.widget:SetBackdropColor(0.10, 0.10, 0.10, 0.9)
        pauseButton.widget:SetBackdropBorderColor(0.65, 0.65, 0.65, 0.95)
    elseif pauseButton.SetBackdrop then
        pauseButton:SetBackdrop({
            bgFile = [[Interface\Tooltips\UI-Tooltip-Background]],
            edgeFile = [[Interface\Buttons\WHITE8X8]],
            edgeSize = 1,
        })
        pauseButton:SetBackdropColor(0.10, 0.10, 0.10, 0.9)
        pauseButton:SetBackdropBorderColor(0.65, 0.65, 0.65, 0.95)
    end
    F.PauseButton = pauseButton

    local searchBox = DF:CreateTextEntry(frame, function() end, 250, 20, nil, nil, nil, DF:GetTemplate("dropdown", "OPTIONS_DROPDOWN_TEMPLATE"))
    searchBox:SetPoint("LEFT", pauseButton, "RIGHT", 50, 0)

    local searchLabel = DF:CreateLabel(frame, "search", 10, "silver")
    searchLabel:SetPoint("RIGHT", searchBox, "LEFT", -10, 0)

    local searchHint = DF:CreateLabel(searchBox, "spell / id / amount / source", 10, "silver")
    searchHint:SetPoint("LEFT", searchBox, "LEFT", 4, 0)

    local clearSearchButton = DF:CreateButton(searchBox, function()
        searchBox:SetText("")
        SEARCH_TEXT = ""
        searchHint:Show()
        if F.ClearSearchButton then
            F.ClearSearchButton:Hide()
        end
        RefreshActiveScroll()
    end, 16, 16, "x")
    clearSearchButton:SetPoint("RIGHT", searchBox, "RIGHT", -1, 0)
    clearSearchButton:Hide()

    searchBox:SetHook("OnTextChanged", function()
        local currentText = tostring(searchBox.text or "")
        SEARCH_TEXT = NormalizeSearchText(currentText)
        searchHint:SetShown(currentText == "")
        clearSearchButton:SetShown(currentText ~= "")
        RefreshActiveScroll()
    end)
    F.SearchBox = searchBox
    F.ClearSearchButton = clearSearchButton

    -- scale headers to fit right content area
    local scaledHeaderTable = {}
    local baseHeaderWidth = 0
    for _, col in ipairs(headerTable) do
        baseHeaderWidth = baseHeaderWidth + col.width
    end
    local scale = contentW / baseHeaderWidth
    local usedWidth = 0
    for i, col in ipairs(headerTable) do
        local w = math.floor(col.width * scale)
        if w < 16 then w = 16 end
        scaledHeaderTable[i] = {
            text = col.text,
            width = w,
            canSort = col.canSort,
            key = col.key,
            selected = col.selected,
        }
        usedWidth = usedWidth + w
    end
    local remainder = contentW - usedWidth
    if scaledHeaderTable[2] then
        scaledHeaderTable[2].width = scaledHeaderTable[2].width + remainder
    end

    -- header
    local header = DF:CreateHeader(frame, scaledHeaderTable, headerOptions)
    header:SetPoint("TOPLEFT", frame, "TOPLEFT", contentX, -58)
    F.Header = header

    -- dynamic calculating of height and lines count
    local scrollTopOffset = 78
    local scrollH = PANEL_H - scrollTopOffset - 20
    local lines = math.floor((scrollH - 2) / (LINE_H + 1))
    if lines < 8 then lines = 8 end

    local scroll = DF:CreateScrollBox(frame, "$parentScroll", makeRefreshFunc(), DATA[ACTIVE_TAB], contentW, scrollH, lines, LINE_H)
    DF:ReskinSlider(scroll)
    scroll:SetPoint("TOPLEFT", frame, "TOPLEFT", contentX, -scrollTopOffset)
    F.Scroll = scroll
    for i=1,lines do scroll:CreateLine(createLineFunc) end

    SetPaused(false)
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
    -- line structure: {spellID, spellName, amount, sourceName, dmgType, timeMS, logText}
    local spellID = tonumber(data["SpellID"])
    local spellName = data["SpellName"] or _GetSpellInfo(spellID) or "Unknown"
    local amount = tonumber(data["Amount"]) or 0
    local sourceName = data["SourceName"] or "Unknown"
    local dt = data["DamageType"]
    if dt == "DIRECT_DAMAGE" then dt = "SWING" end
    local timeMS = GetClientEventTimeMS()
    local logText = data["Log"] or ""

    table.insert(DATA[tabKey], 1, { spellID, spellName, amount, sourceName, dt or "-", timeMS, logText })
    SortTabData(tabKey)

    if F.Scroll and ACTIVE_TAB == tabKey then
        RefreshActiveScroll()
    end
end

local listener = CreateFrame("Frame")
listener:RegisterEvent("CHAT_MSG_ADDON")
listener:SetScript("OnEvent", function(_, event, prefix, message, channel, sender)
    local tabKey = prefixToTab[prefix]
    if not tabKey then return end
    if IS_PAUSED then return end

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
RegisterSlashCommand(function()
    if not sessionTimeStartAt then
        sessionTimeStartAt = GetNowSec()
    end
    if not F.Frame then CreateMainWindow() end
    F.Frame:Show()
end)
