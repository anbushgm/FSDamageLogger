local Details = _G.Details
---@type detailsframework
local DF = _G.DetailsFramework
local _, FSDamageLogger = ...
local _GetSpellInfo = Details.GetSpellInfo

local LibWindow = LibStub("LibWindow-1.1")
local playerSerial = UnitGUID("player")

-- for collecting split parts
local pendingParts = {}
local expectedTotal = nil

function FSDamageLogger:ScrollDamage()
    if (not FSDamageLoggerFrame) then

        FSDamageLoggerFrame = DF:CreateSimplePanel(UIParent, 460, 400, ".debug fsdl")
        FSDamageLoggerFrame.Data = {}
        FSDamageLoggerFrame:ClearAllPoints()
        FSDamageLoggerFrame:SetPoint("CENTER")
        FSDamageLoggerFrame:SetFrameStrata("DIALOG")
        FSDamageLoggerFrame:Hide()

        if (not Details.damage_scroll_position) then
            Details.damage_scroll_position = {point = "CENTER", x = 0, y = 0, scale = 1}
        end

        LibWindow.RegisterConfig(FSDamageLoggerFrame, Details.damage_scroll_position)
        LibWindow.MakeDraggable(FSDamageLoggerFrame)
        LibWindow.RestorePosition(FSDamageLoggerFrame)
        FSDamageLoggerFrame:SetScale(Details.damage_scroll_position.scale)

        local scroll_width = 410
        local scroll_height = 290
        local scroll_lines = 14
        local scroll_line_height = 20

        local backdrop_color = {.2, .2, .2, 0.2}
        local backdrop_color_on_enter = {.8, .8, .8, 0.4}

        local headerTable =
        {
            {text = "", width = 20},
            {text = "Spell Name", width = 90},
            {text = "Amount", width = 60},
            {text = "Source", width = 100},
            {text = "DmgType", width = 70},
            {text = "Spell ID", width = 70},
        }

        local headerOptions = {padding = 2}
        FSDamageLoggerFrame.Header = DF:CreateHeader(FSDamageLoggerFrame, headerTable, headerOptions)
        FSDamageLoggerFrame.Header:SetPoint("TOPLEFT", FSDamageLoggerFrame, "TOPLEFT", 5, -30)

        local function OpenDetailWindow(spellName, spellID, amount, logText)
            if not FSDamageLogger.DetailWindow then
                local detail = DF:CreateSimplePanel(UIParent, 500, 400, "Spell Logs")
                detail:SetFrameStrata("DIALOG")

                local scrollFrame = CreateFrame("ScrollFrame", nil, detail, "UIPanelScrollFrameTemplate")
                scrollFrame:SetPoint("TOPLEFT", 10, -50)
                scrollFrame:SetPoint("BOTTOMRIGHT", -30, 10)

                local editBox = CreateFrame("EditBox", nil, scrollFrame)
                editBox:SetMultiLine(true)
                editBox:SetFontObject("GameFontHighlightSmall")
                editBox:SetAutoFocus(false)
                editBox:SetWidth(440)
                editBox:SetJustifyH("LEFT")
                editBox:SetJustifyV("TOP")
                editBox:EnableMouse(true)

                scrollFrame:SetScrollChild(editBox)

                detail.editBox = editBox
                FSDamageLogger.DetailWindow = detail
            end

            local textContent = string.format("Spell Name: |cffffd100%s|r\nSpell ID: |cff00ccff%d|r\nDamage: |cffff5555%d|r",
                spellName, spellID, amount
            )

            if logText and logText ~= "" then
                textContent = textContent .. "\n\nLog Data:\n" .. logText
            end

            local frame = FSDamageLogger.DetailWindow
            frame.editBox:SetText(textContent)
            frame.editBox:HighlightText(0, 0)

            frame:Show()
        end

        local function createLineFunc(self, index)
            local line = CreateFrame("button", "$parentLine" .. index, self, "BackdropTemplate")
            line:SetPoint("TOPLEFT", self, "TOPLEFT", 1, -((index-1)*(scroll_line_height+1)) - 1)
            line:SetSize(scroll_width - 2, scroll_line_height)

            line:SetBackdrop({bgFile = [[Interface\Tooltips\UI-Tooltip-Background]], tileSize = 64, tile = true})
            line:SetBackdropColor(unpack(backdrop_color))

            DF:Mixin(line, DF.HeaderFunctions)

            local icon = line:CreateTexture("$parentSpellIcon", "OVERLAY")
            icon:SetSize(scroll_line_height - 2, scroll_line_height - 2)

            local iconFrame = CreateFrame("frame", "$parentIconFrame", line)
            iconFrame:SetAllPoints(icon)

            local spellNameText = DF:CreateLabel(line, "", 10, "white")
            local damageText = DF:CreateLabel(line, "", 10, "white")
            local sourceNameText = DF:CreateLabel(line, "", 10, "white")
            local dmgTypeText = DF:CreateLabel(line, "", 10, "white")
            local spellIDText = DF:CreateLabel(line, "", 10, "white")

            line:SetScript("OnEnter", function(self)
                self:SetBackdropColor(unpack(backdrop_color_on_enter))
            end)
            line:SetScript("OnLeave", function(self)
                self:SetBackdropColor(unpack(backdrop_color))
            end)

            line:SetScript("OnClick", function(self)
                OpenDetailWindow(self.SpellName or "Unknown", self.SpellID or 0, self.Amount or 0, self.Log)
            end)

            line:AddFrameToHeaderAlignment(icon)
            line:AddFrameToHeaderAlignment(spellNameText)
            line:AddFrameToHeaderAlignment(damageText)
            line:AddFrameToHeaderAlignment(sourceNameText)
            line:AddFrameToHeaderAlignment(dmgTypeText)
            line:AddFrameToHeaderAlignment(spellIDText)
            line:AlignWithHeader(FSDamageLoggerFrame.Header, "left")

            line.Icon = icon
            line.IconFrame = iconFrame
            line.SpellNameText = spellNameText
            line.DamageText = damageText
            line.SourceNameText = sourceNameText
            line.DmgTypeText = dmgTypeText
            line.SpellIDText = spellIDText

            return line
        end

        local refreshFunc = function(self, data, offset, totalLines)
            local ToK = Details:GetCurrentToKFunction()

            for i = 1, totalLines do
                local index = i + offset
                local event = data[index]
                if event then
                    local line = self:GetLine(i)

                    local time, token, hidding, sourceSerial, sourceName, sourceFlag, sourceFlag2,
                          targetSerial, targetName, targetFlag, targetFlag2,
                          spellID, spellName, spellType, amount,
                          overkill, school, resisted, blocked, absorbed,
                          Log, DamageType = unpack(event)

                    Log = Log or ""

                    local name, _, icon = _GetSpellInfo(spellID or 1)

                    line.SpellID = spellID
                    line.SpellName = name
                    line.Amount = amount
                    line.Log = Log

                    if name then
                        line.Icon:SetTexture(icon)
                        line.Icon:SetTexCoord(.1, .9, .1, .9)
                        line.DamageText.text = " " .. ToK(_, amount)
                        line.SourceNameText.text = sourceName or "Unknown"
                        line.DmgTypeText.text = DamageType or "-"
                        line.SpellIDText.text = spellID
                        line.SpellNameText.text = name
                    else
                        line:Hide()
                    end
                end
            end
        end

        local damageScroll = DF:CreateScrollBox(FSDamageLoggerFrame, "$parentSpellScroll", refreshFunc, FSDamageLoggerFrame.Data, scroll_width, scroll_height, scroll_lines, scroll_line_height)
        DF:ReskinSlider(damageScroll)
        damageScroll:SetPoint("TOPLEFT", FSDamageLoggerFrame, "TOPLEFT", 5, -70)

        function damageScroll:RefreshScroll()
            damageScroll:SetData(FSDamageLoggerFrame.Data)
            damageScroll:Refresh()
        end

        for i = 1, scroll_lines do
            damageScroll:CreateLine(createLineFunc)
        end

        C_ChatInfo.RegisterAddonMessagePrefix("FSDL_DAMAGE")
        local serverCombatLogReader = CreateFrame("Frame")
        serverCombatLogReader:SetScript("OnEvent", function(self, event, prefix, message, channel, sender)
            if event == "CHAT_MSG_ADDON" and prefix == "FSDL_DAMAGE" then
                -- handle split parts
                local part, total, chunk = message:match("^PART%|(%d+)%/(%d+)%|(.*)$")
                if part then
                    part = tonumber(part); total = tonumber(total)
                    pendingParts[part] = chunk
                    if not expectedTotal then expectedTotal = total end
                    local count = 0 for _ in pairs(pendingParts) do count = count + 1 end
                    if count < expectedTotal then return end
                    message = table.concat(pendingParts)
                    wipe(pendingParts)
                    expectedTotal = nil
                end

                -- parse full message
                local data = {}
                for chunkPart in string.gmatch(message, "([^|]+)") do
                    local key, value = chunkPart:match("([^=]+)=(.*)")
                    if key and value then data[key] = value end
                end

                local damageType = data["DamageType"]
                if damageType == "DIRECT_DAMAGE" then damageType = "SWING" end

                local spellID = tonumber(data["SpellID"])
                local spellName = _GetSpellInfo(spellID)
                local amount = tonumber(data["Amount"])
                local absorbed = tonumber(data["Absorbed"])
                local logData = data["Log"] or ""

                local sourceGUID = UnitGUID("player")
                local sourceName = data["SourceName"]

                if not FSDamageLoggerFrame.Data.Started then FSDamageLoggerFrame.Data.Started = time() end

                table.insert(FSDamageLoggerFrame.Data, 1, {
                    time(), "SPELL_DAMAGE", false,
                    sourceGUID, sourceName, 0, 0,
                    0, UnitGUID("target"), UnitName("target"), 0,
                    spellID, spellName, 1, amount,
                    0, 0, 0, 0, absorbed, logData, damageType
                })
                damageScroll:RefreshScroll()
            end
        end)

        FSDamageLoggerFrame:SetScript("OnShow", function()
            wipe(FSDamageLoggerFrame.Data)
            serverCombatLogReader:RegisterEvent("CHAT_MSG_ADDON")
            damageScroll:RefreshScroll()
        end)

        FSDamageLoggerFrame:SetScript("OnHide", function()
            serverCombatLogReader:UnregisterEvent("CHAT_MSG_ADDON")
        end)
    end

    FSDamageLoggerFrame:Show()
end

SLASH_FSDAMAGELOGGER1 = "/fsdamagelogger"
SLASH_FSDAMAGELOGGER2 = "/fsdl"
SlashCmdList["FSDAMAGELOGGER"] = function() FSDamageLogger:ScrollDamage() end
