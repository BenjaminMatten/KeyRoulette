-- Key Roulette UI - EllesmereUI Inspired Aesthetics
local addonName, KR = ...
local L = KR.L

local mainFrame
local memberRows = {}
local spinTicker
local isSpinning = false
local manualModal

-- Acquire Class Color
local pr, pg, pb, phex, pclass = KR:GetPlayerClassColor()

-- Create Main UI Frame
local function CreateMainFrame()
    if mainFrame then return mainFrame end

    mainFrame = CreateFrame("Frame", "KeyRouletteMainFrame", UIParent, "BackdropTemplate")
    mainFrame:SetSize(420, 490)
    mainFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    mainFrame:SetMovable(true)
    mainFrame:EnableMouse(true)
    mainFrame:RegisterForDrag("LeftButton")
    mainFrame:SetScript("OnDragStart", mainFrame.StartMoving)
    mainFrame:SetScript("OnDragStop", mainFrame.StopMovingOrSizing)
    mainFrame:SetFrameStrata("HIGH")

    -- EllesmereUI Backdrop: Dark Slate with 1px border
    mainFrame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        tile = false, tileSize = 0, edgeSize = 1,
        insets = { left = 0, right = 0, top = 0, bottom = 0 }
    })
    mainFrame:SetBackdropColor(0.05, 0.05, 0.07, 0.95)
    mainFrame:SetBackdropBorderColor(0.18, 0.18, 0.22, 1)

    -- Top Class Color Accent Line
    local accentLine = mainFrame:CreateTexture(nil, "OVERLAY")
    accentLine:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", 0, 0)
    accentLine:SetPoint("TOPRIGHT", mainFrame, "TOPRIGHT", 0, 0)
    accentLine:SetHeight(3)
    accentLine:SetColorTexture(pr, pg, pb, 1)
    mainFrame.accentLine = accentLine

    -- Header Title
    local title = mainFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    title:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", 16, -14)
    title:SetText("|c" .. phex .. "KEY ROULETTE|r")
    title:SetFont("Fonts\\FRIZQT__.TTF", 15, "OUTLINE")

    -- Subtitle
    local subtitle = mainFrame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    subtitle:SetPoint("LEFT", title, "RIGHT", 10, 0)
    subtitle:SetText("Mythic+ Group Roulette")

    -- Close Button
    local closeBtn = CreateFrame("Button", nil, mainFrame)
    closeBtn:SetSize(20, 20)
    closeBtn:SetPoint("TOPRIGHT", mainFrame, "TOPRIGHT", -12, -12)
    closeBtn:SetNormalFontObject("GameFontHighlight")
    closeBtn:SetText("✕")
    closeBtn:SetScript("OnClick", function() mainFrame:Hide() end)

    -- Refresh Button
    local refreshBtn = CreateFrame("Button", nil, mainFrame)
    refreshBtn:SetSize(20, 20)
    refreshBtn:SetPoint("RIGHT", closeBtn, "LEFT", -8, 0)
    refreshBtn:SetNormalFontObject("GameFontHighlight")
    refreshBtn:SetText("🔄")
    refreshBtn:SetScript("OnClick", function()
        KR:RequestGroupKeystones()
        KR:UpdateGroupRoster()
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or 856)
    end)
    refreshBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(L["REFRESH"], 1, 1, 1)
        GameTooltip:Show()
    end)
    refreshBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Member Cards Scroll/List Container
    local listContainer = CreateFrame("Frame", nil, mainFrame, "BackdropTemplate")
    listContainer:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", 14, -45)
    listContainer:SetPoint("TOPRIGHT", mainFrame, "TOPRIGHT", -14, -45)
    listContainer:SetHeight(290)
    listContainer:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        tile = false, tileSize = 0, edgeSize = 1,
        insets = { left = 0, right = 0, top = 0, bottom = 0 }
    })
    listContainer:SetBackdropColor(0.03, 0.03, 0.04, 0.8)
    listContainer:SetBackdropBorderColor(0.12, 0.12, 0.15, 1)
    mainFrame.listContainer = listContainer

    -- Winner Announcement Banner Frame
    local banner = CreateFrame("Frame", nil, mainFrame, "BackdropTemplate")
    banner:SetPoint("TOPLEFT", listContainer, "BOTTOMLEFT", 0, -8)
    banner:SetPoint("TOPRIGHT", listContainer, "BOTTOMRIGHT", 0, -8)
    banner:SetHeight(32)
    banner:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        tile = false, tileSize = 0, edgeSize = 1,
        insets = { left = 0, right = 0, top = 0, bottom = 0 }
    })
    banner:SetBackdropColor(pr * 0.15, pg * 0.15, pb * 0.15, 0.9)
    banner:SetBackdropBorderColor(pr, pg, pb, 0.6)
    
    local bannerText = banner:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    bannerText:SetPoint("CENTER", banner, "CENTER", 0, 0)
    bannerText:SetText("|c" .. phex .. "Ready to spin!|r")
    banner.text = bannerText
    mainFrame.banner = banner

    -- Controls Bar (Channel & Auto-announce)
    local controlsBar = CreateFrame("Frame", nil, mainFrame)
    controlsBar:SetPoint("TOPLEFT", banner, "BOTTOMLEFT", 0, -8)
    controlsBar:SetPoint("TOPRIGHT", banner, "BOTTOMRIGHT", 0, -8)
    controlsBar:SetHeight(28)

    local channelLabel = controlsBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    channelLabel:SetPoint("LEFT", controlsBar, "LEFT", 4, 0)
    channelLabel:SetText(L["CHAT_CHANNEL"])

    -- Channel Dropdown Button
    local chanBtn = CreateFrame("Button", "KeyRouletteChanDropdown", controlsBar, "BackdropTemplate")
    chanBtn:SetSize(110, 22)
    chanBtn:SetPoint("LEFT", channelLabel, "RIGHT", 6, 0)
    chanBtn:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        tile = false, tileSize = 0, edgeSize = 1,
        insets = { left = 0, right = 0, top = 0, bottom = 0 }
    })
    chanBtn:SetBackdropColor(0.08, 0.08, 0.10, 1)
    chanBtn:SetBackdropBorderColor(0.25, 0.25, 0.30, 1)
    
    local chanText = chanBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    chanText:SetPoint("CENTER", chanBtn, "CENTER", 0, 0)
    chanText:SetText(KeyRouletteDB.announceChannel or "PARTY")
    chanBtn.text = chanText

    chanBtn:SetScript("OnClick", function(self)
        local channels = { "PARTY", "RAID", "SAY", "INSTANCE_CHAT", "SELF" }
        local cur = KeyRouletteDB.announceChannel or "PARTY"
        local nextIdx = 1
        for i, c in ipairs(channels) do
            if c == cur then
                nextIdx = (i % #channels) + 1
                break
            end
        end
        KeyRouletteDB.announceChannel = channels[nextIdx]
        chanText:SetText(channels[nextIdx])
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or 856)
    end)

    -- Auto Announce Checkbox
    local autoCheck = CreateFrame("CheckButton", nil, controlsBar, "UICheckButtonTemplate")
    autoCheck:SetSize(22, 22)
    autoCheck:SetPoint("RIGHT", controlsBar, "RIGHT", -4, 0)
    autoCheck:SetChecked(KeyRouletteDB.autoAnnounce)
    autoCheck:SetScript("OnClick", function(self)
        KeyRouletteDB.autoAnnounce = self:GetChecked()
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or 856)
    end)
    
    local autoText = controlsBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    autoText:SetPoint("RIGHT", autoCheck, "LEFT", -2, 0)
    autoText:SetText("Auto-Chat")

    -- Big Spin Action Button (EllesmereUI Accent Style)
    local spinBtn = CreateFrame("Button", nil, mainFrame, "BackdropTemplate")
    spinBtn:SetSize(392, 40)
    spinBtn:SetPoint("BOTTOM", mainFrame, "BOTTOM", 0, 14)
    spinBtn:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        tile = false, tileSize = 0, edgeSize = 1,
        insets = { left = 0, right = 0, top = 0, bottom = 0 }
    })
    spinBtn:SetBackdropColor(pr * 0.25, pg * 0.25, pb * 0.25, 0.95)
    spinBtn:SetBackdropBorderColor(pr, pg, pb, 1)

    local spinText = spinBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    spinText:SetPoint("CENTER", spinBtn, "CENTER", 0, 0)
    spinText:SetText("|c" .. phex .. L["SPIN_BUTTON"] .. "|r")
    spinText:SetFont("Fonts\\FRIZQT__.TTF", 14, "OUTLINE")
    spinBtn.text = spinText

    spinBtn:SetScript("OnEnter", function(self)
        self:SetBackdropColor(pr * 0.4, pg * 0.4, pb * 0.4, 1)
    end)
    spinBtn:SetScript("OnLeave", function(self)
        self:SetBackdropColor(pr * 0.25, pg * 0.25, pb * 0.25, 0.95)
    end)
    spinBtn:SetScript("OnClick", function()
        KR:StartRouletteSpin()
    end)

    mainFrame.spinBtn = spinBtn
    KR.UIFrame = mainFrame
    return mainFrame
end

-- Create Party Member Card Row
local function CreateMemberRow(parent, index)
    local row = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    row:SetSize(384, 50)
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", 4, -4 - ((index - 1) * 56))
    row:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        tile = false, tileSize = 0, edgeSize = 1,
        insets = { left = 0, right = 0, top = 0, bottom = 0 }
    })
    row:SetBackdropColor(0.08, 0.08, 0.10, 0.9)
    row:SetBackdropBorderColor(0.18, 0.18, 0.22, 1)

    -- Exclude Checkbox
    local excludeCheck = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
    excludeCheck:SetSize(20, 20)
    excludeCheck:SetPoint("LEFT", row, "LEFT", 6, 0)
    excludeCheck:SetChecked(true)
    row.excludeCheck = excludeCheck

    -- Role Icon / Badge
    local roleText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    roleText:SetPoint("LEFT", excludeCheck, "RIGHT", 6, 0)
    roleText:SetSize(42, 16)
    row.roleText = roleText

    -- Character Name (Class Colored)
    local nameText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    nameText:SetPoint("LEFT", roleText, "RIGHT", 6, 0)
    nameText:SetWidth(110)
    nameText:SetJustifyH("LEFT")
    row.nameText = nameText

    -- Dungeon Icon
    local icon = row:CreateTexture(nil, "ARTWORK")
    icon:SetSize(32, 32)
    icon:SetPoint("LEFT", nameText, "RIGHT", 6, 0)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    row.icon = icon

    -- Key Info String
    local keyText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    keyText:SetPoint("LEFT", icon, "RIGHT", 8, 0)
    keyText:SetWidth(120)
    keyText:SetJustifyH("LEFT")
    row.keyText = keyText

    -- Edit Button
    local editBtn = CreateFrame("Button", nil, row, "BackdropTemplate")
    editBtn:SetSize(34, 22)
    editBtn:SetPoint("RIGHT", row, "RIGHT", -6, 0)
    editBtn:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        tile = false, tileSize = 0, edgeSize = 1,
        insets = { left = 0, right = 0, top = 0, bottom = 0 }
    })
    editBtn:SetBackdropColor(0.14, 0.14, 0.18, 1)
    editBtn:SetBackdropBorderColor(0.3, 0.3, 0.35, 1)
    
    local editBtnText = editBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    editBtnText:SetPoint("CENTER", editBtn, "CENTER", 0, 0)
    editBtnText:SetText("Edit")
    row.editBtn = editBtn

    memberRows[index] = row
    return row
end

-- Refresh UI Card Display
function KR:OnGroupUpdated()
    if not mainFrame then CreateMainFrame() end
    local members = KR.currentMembers or {}

    for i = 1, 5 do
        local row = memberRows[i] or CreateMemberRow(mainFrame.listContainer, i)
        local member = members[i]

        if member then
            row:Show()
            row.memberData = member

            -- Role display
            local rStr = member.role == "TANK" and "|cff5891e5[TANK]|r"
                      or member.role == "HEALER" and "|cff47d174[HEAL]|r"
                      or member.role == "DAMAGER" and "|cffe25252[DPS]|r"
                      or "[ - ]"
            row.roleText:SetText(rStr)

            -- Class Color Name
            local cr, cg, cb, chex = KR:GetUnitClassColor(member.unit)
            row.nameText:SetText("|c" .. chex .. member.name .. "|r")

            -- Key info
            if member.key and member.key.level and member.key.level > 0 then
                row.icon:SetTexture(member.key.icon or 5254320)
                row.keyText:SetText("|cff00ffcc+" .. member.key.level .. "|r " .. (member.key.dungeonName or "Unknown"))
                row.excludeCheck:SetEnabled(true)
            else
                row.icon:SetTexture(134400) -- Question mark icon
                row.keyText:SetText("|cff888888" .. L["NO_KEY_DETECTED"] .. "|r")
                row.excludeCheck:SetEnabled(false)
            end

            -- Edit button hook
            row.editBtn:SetScript("OnClick", function()
                KR:ShowManualEditModal(member)
            end)
        else
            row:Hide()
        end
    end
end

-- Manual Key Selector Popup Modal
function KR:ShowManualEditModal(member)
    if not manualModal then
        manualModal = CreateFrame("Frame", "KeyRouletteManualModal", UIParent, "BackdropTemplate")
        manualModal:SetSize(320, 220)
        manualModal:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
        manualModal:SetFrameStrata("DIALOG")
        manualModal:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            tile = false, tileSize = 0, edgeSize = 1,
            insets = { left = 0, right = 0, top = 0, bottom = 0 }
        })
        manualModal:SetBackdropColor(0.06, 0.06, 0.08, 0.98)
        manualModal:SetBackdropBorderColor(pr, pg, pb, 1)

        local mTitle = manualModal:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        mTitle:SetPoint("TOP", manualModal, "TOP", 0, -12)
        mTitle:SetText("|c" .. phex .. "Manual Key Entry|r")
        manualModal.title = mTitle

        -- Level EditBox
        local lvlLabel = manualModal:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        lvlLabel:SetPoint("TOPLEFT", manualModal, "TOPLEFT", 20, -50)
        lvlLabel:SetText("Key Level (2-30):")

        local lvlInput = CreateFrame("EditBox", nil, manualModal, "InputBoxTemplate")
        lvlInput:SetSize(60, 22)
        lvlInput:SetPoint("LEFT", lvlLabel, "RIGHT", 10, 0)
        lvlInput:SetNumeric(true)
        lvlInput:SetMaxLetters(2)
        lvlInput:SetAutoFocus(false)
        manualModal.lvlInput = lvlInput

        -- Dungeon Select Label
        local dungLabel = manualModal:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        dungLabel:SetPoint("TOPLEFT", manualModal, "TOPLEFT", 20, -90)
        dungLabel:SetText("Select Dungeon:")

        local dungInput = CreateFrame("EditBox", nil, manualModal, "InputBoxTemplate")
        dungInput:SetSize(260, 22)
        dungInput:SetPoint("TOPLEFT", dungLabel, "BOTTOMLEFT", 0, -8)
        dungInput:SetAutoFocus(false)
        dungInput:SetText("Ara-Kara, City of Echoes")
        manualModal.dungInput = dungInput

        -- Save Button
        local saveBtn = CreateFrame("Button", nil, manualModal, "BackdropTemplate")
        saveBtn:SetSize(100, 26)
        saveBtn:SetPoint("BOTTOMLEFT", manualModal, "BOTTOMLEFT", 30, 16)
        saveBtn:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            tile = false, tileSize = 0, edgeSize = 1,
            insets = { left = 0, right = 0, top = 0, bottom = 0 }
        })
        saveBtn:SetBackdropColor(pr * 0.3, pg * 0.3, pb * 0.3, 1)
        saveBtn:SetBackdropBorderColor(pr, pg, pb, 1)
        local st = saveBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        st:SetPoint("CENTER", saveBtn, "CENTER", 0, 0)
        st:SetText("Save")

        saveBtn:SetScript("OnClick", function()
            if manualModal.targetMember then
                local lvl = tonumber(manualModal.lvlInput:GetText()) or 10
                local dName = manualModal.dungInput:GetText()
                if dName == "" then dName = "Custom Key" end

                KR.manualKeys[manualModal.targetMember.name] = {
                    mapID = 507,
                    level = lvl,
                    dungeonName = dName,
                    icon = 5254320,
                    source = "Manual"
                }
                KR:UpdateGroupRoster()
            end
            manualModal:Hide()
            PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or 856)
        end)

        -- Cancel Button
        local cancelBtn = CreateFrame("Button", nil, manualModal, "BackdropTemplate")
        cancelBtn:SetSize(100, 26)
        cancelBtn:SetPoint("BOTTOMRIGHT", manualModal, "BOTTOMRIGHT", -30, 16)
        cancelBtn:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            tile = false, tileSize = 0, edgeSize = 1,
            insets = { left = 0, right = 0, top = 0, bottom = 0 }
        })
        cancelBtn:SetBackdropColor(0.15, 0.15, 0.18, 1)
        cancelBtn:SetBackdropBorderColor(0.3, 0.3, 0.35, 1)
        local ct = cancelBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        ct:SetPoint("CENTER", cancelBtn, "CENTER", 0, 0)
        ct:SetText("Cancel")
        cancelBtn:SetScript("OnClick", function() manualModal:Hide() end)
    end

    manualModal.targetMember = member
    manualModal.title:SetText("|c" .. phex .. "Manual Key: " .. member.name .. "|r")
    manualModal.lvlInput:SetText(member.key and member.key.level or "10")
    manualModal.dungInput:SetText(member.key and member.key.dungeonName or "Ara-Kara, City of Echoes")
    manualModal:Show()
end

-- Roulette Spin Wheel Animation & Selection Logic
function KR:StartRouletteSpin()
    if isSpinning then return end

    local activeMembers = {}
    local members = KR.currentMembers or {}

    for i, member in ipairs(members) do
        local row = memberRows[i]
        if member.key and member.key.level and member.key.level > 0 then
            if not row or row.excludeCheck:GetChecked() then
                table.insert(activeMembers, { member = member, rowIndex = i })
            end
        end
    end

    if #activeMembers == 0 then
        if mainFrame and mainFrame.banner then
            mainFrame.banner.text:SetText("|cffff4444" .. L["NO_KEYS_FOUND"] .. "|r")
        end
        PlaySound(SOUNDKIT.IG_PLAYER_DEAD or 895)
        return
    end

    isSpinning = true
    if mainFrame and mainFrame.spinBtn then
        mainFrame.spinBtn:Disable()
        mainFrame.spinBtn.text:SetText("|cffaaaaaa" .. L["SPINNING"] .. "|r")
    end

    -- Determine Winner
    local winnerIndex = math.random(1, #activeMembers)
    local winner = activeMembers[winnerIndex].member

    local step = 1
    local totalTicks = 25 + math.random(0, 10)
    local tickDelay = 0.05

    local function RunSpinStep()
        -- Reset Row Borders
        for i = 1, 5 do
            if memberRows[i] then
                memberRows[i]:SetBackdropBorderColor(0.18, 0.18, 0.22, 1)
                memberRows[i]:SetBackdropColor(0.08, 0.08, 0.10, 0.9)
            end
        end

        local currentCandidate = activeMembers[((step - 1) % #activeMembers) + 1]
        local activeRow = memberRows[currentCandidate.rowIndex]

        if activeRow then
            activeRow:SetBackdropBorderColor(pr, pg, pb, 1)
            activeRow:SetBackdropColor(pr * 0.2, pg * 0.2, pb * 0.2, 0.95)
        end

        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or 856)

        step = step + 1
        if step <= totalTicks then
            -- Decelerate timing towards end
            if step > (totalTicks - 8) then
                tickDelay = tickDelay + 0.04
            elseif step > (totalTicks - 15) then
                tickDelay = tickDelay + 0.02
            end
            C_Timer.After(tickDelay, RunSpinStep)
        else
            -- Finish Spin! Highlight Winner
            for i = 1, 5 do
                if memberRows[i] then
                    memberRows[i]:SetBackdropBorderColor(0.18, 0.18, 0.22, 1)
                    memberRows[i]:SetBackdropColor(0.08, 0.08, 0.10, 0.9)
                end
            end

            local winningRow = memberRows[activeMembers[winnerIndex].rowIndex]
            if winningRow then
                winningRow:SetBackdropBorderColor(1, 0.84, 0, 1) -- Golden Winner Glow
                winningRow:SetBackdropColor(0.3, 0.25, 0.05, 0.95)
            end

            if mainFrame and mainFrame.banner then
                mainFrame.banner.text:SetText("|cffffd700🏆 WINNER: " .. winner.name .. " (+" .. winner.key.level .. " " .. winner.key.dungeonName .. ")|r")
            end

            PlaySound(SOUNDKIT.UI_EPICLOOT_TOAST or 31578)

            -- Announce
            if KeyRouletteDB.autoAnnounce then
                KR:AnnounceWinner(winner)
            end

            isSpinning = false
            if mainFrame and mainFrame.spinBtn then
                mainFrame.spinBtn:Enable()
                mainFrame.spinBtn.text:SetText("|c" .. phex .. L["SPIN_BUTTON"] .. "|r")
            end
        end
    end

    RunSpinStep()
end

-- Create Minimap Button
local function CreateMinimapButton()
    local btn = CreateFrame("Button", "KeyRouletteMinimapButton", Minimap, "BackdropTemplate")
    btn:SetSize(32, 32)
    btn:SetFrameStrata("MEDIUM")
    btn:SetPoint("CENTER", Minimap, "CENTER", -60, -60)
    btn:SetMovable(true)
    btn:EnableMouse(true)
    btn:RegisterForClicks("AnyUp")

    btn:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        tile = false, tileSize = 0, edgeSize = 1,
        insets = { left = 0, right = 0, top = 0, bottom = 0 }
    })
    btn:SetBackdropColor(0.06, 0.06, 0.08, 0.95)
    btn:SetBackdropBorderColor(pr, pg, pb, 1)

    local icon = btn:CreateTexture(nil, "ARTWORK")
    icon:SetSize(20, 20)
    icon:SetPoint("CENTER", btn, "CENTER", 0, 0)
    icon:SetTexture(5254320) -- Mythic Keystone Texture

    btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText("Key Roulette", pr, pg, pb)
        GameTooltip:AddLine("Click to open Mythic+ Key Roulette window.", 1, 1, 1)
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    btn:SetScript("OnClick", function()
        if mainFrame then
            mainFrame:SetShown(not mainFrame:IsShown())
        else
            CreateMainFrame():Show()
            KR:UpdateGroupRoster()
        end
    end)
end

-- Auto Initialize UI on Load
local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:SetScript("OnEvent", function()
    CreateMainFrame()
    CreateMinimapButton()
    KR:UpdateGroupRoster()
end)
