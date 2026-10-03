-- Key Roulette UI - EllesmereUI Inspired Aesthetics
local addonName, KR = ...
KR = KR or _G["KeyRoulette"] or {}
_G["KeyRoulette"] = KR

local L = KR.L or {}
setmetatable(L, { __index = function(t, k) return k end })

-- Class Color Helper Fallbacks
KR.GetPlayerClassColor = KR.GetPlayerClassColor or function(self)
    local _, classFilename = UnitClass("player")
    local color = (CUSTOM_CLASS_COLORS and CUSTOM_CLASS_COLORS[classFilename]) or (classFilename and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFilename])
    if color then
        local hex = string.format("ff%02x%02x%02x", color.r * 255, color.g * 255, color.b * 255)
        return color.r, color.g, color.b, hex, classFilename
    end
    return 0.8, 0.8, 0.8, "ffcccccc", "PRIEST"
end

KR.GetUnitClassColor = KR.GetUnitClassColor or function(self, unit)
    if not unit or not UnitExists(unit) then
        return 0.8, 0.8, 0.8, "ffcccccc", "PRIEST"
    end
    local _, classFilename = UnitClass(unit)
    local color = (CUSTOM_CLASS_COLORS and CUSTOM_CLASS_COLORS[classFilename]) or (classFilename and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFilename])
    if color then
        local hex = string.format("ff%02x%02x%02x", color.r * 255, color.g * 255, color.b * 255)
        return color.r, color.g, color.b, hex, classFilename
    end
    return 0.8, 0.8, 0.8, "ffcccccc", "PRIEST"
end

local mainFrame
local memberRows = {}
local isSpinning = false
local manualModal

-- Safe Frame Style Utility (BackdropTemplate Compatible)
local function ApplyStyle(frame, bgR, bgG, bgB, bgA, borderR, borderG, borderB, borderA)
    if frame.SetBackdrop then
        pcall(function()
            frame:SetBackdrop({
                bgFile = "Interface\\Buttons\\WHITE8X8",
                edgeFile = "Interface\\Buttons\\WHITE8X8",
                tile = false, tileSize = 0, edgeSize = 1,
                insets = { left = 0, right = 0, top = 0, bottom = 0 }
            })
            frame:SetBackdropColor(bgR or 0.05, bgG or 0.05, bgB or 0.07, bgA or 0.95)
            frame:SetBackdropBorderColor(borderR or 0.18, borderG or 0.18, borderB or 0.22, borderA or 1)
        end)
    else
        if not frame.krBgTex then
            frame.krBgTex = frame:CreateTexture(nil, "BACKGROUND")
            frame.krBgTex:SetAllPoints(frame)
        end
        frame.krBgTex:SetColorTexture(bgR or 0.05, bgG or 0.05, bgB or 0.07, bgA or 0.95)
    end
end

-- Create Main UI Frame
local function CreateMainFrame()
    if mainFrame then return mainFrame end

    local pr, pg, pb, phex = KR:GetPlayerClassColor()
    local template = BackdropTemplateMixin and "BackdropTemplate" or nil

    mainFrame = CreateFrame("Frame", "KeyRouletteMainFrame", UIParent, template)
    mainFrame:SetSize(420, 490)
    mainFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    mainFrame:SetMovable(true)
    mainFrame:EnableMouse(true)
    mainFrame:RegisterForDrag("LeftButton")
    mainFrame:SetScript("OnDragStart", function(self) self:StartMoving() end)
    mainFrame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    mainFrame:SetFrameStrata("HIGH")

    -- Hide initially
    mainFrame:Hide()

    -- Apply EllesmereUI Dark Theme
    ApplyStyle(mainFrame, 0.05, 0.05, 0.07, 0.95, 0.18, 0.18, 0.22, 1)

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

    -- Debug Copy Button
    local debugBtn = CreateFrame("Button", nil, mainFrame)
    debugBtn:SetSize(20, 20)
    debugBtn:SetPoint("RIGHT", closeBtn, "LEFT", -6, 0)
    debugBtn:SetNormalFontObject("GameFontHighlight")
    debugBtn:SetText("📋")
    debugBtn:SetScript("OnClick", function()
        if KR.RunDebug then KR:RunDebug() end
    end)

    -- Refresh Button
    local refreshBtn = CreateFrame("Button", nil, mainFrame)
    refreshBtn:SetSize(20, 20)
    refreshBtn:SetPoint("RIGHT", debugBtn, "LEFT", -6, 0)
    refreshBtn:SetNormalFontObject("GameFontHighlight")
    refreshBtn:SetText("🔄")
    refreshBtn:SetScript("OnClick", function()
        if KR.ResyncAllKeys then
            KR:ResyncAllKeys()
        else
            if KR.RequestGroupKeystones then KR:RequestGroupKeystones() end
            if KR.UpdateGroupRoster then KR:UpdateGroupRoster() end
        end
    end)

    -- Member Cards Scroll/List Container
    local listContainer = CreateFrame("Frame", nil, mainFrame, template)
    listContainer:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", 14, -45)
    listContainer:SetPoint("TOPRIGHT", mainFrame, "TOPRIGHT", -14, -45)
    listContainer:SetHeight(290)
    ApplyStyle(listContainer, 0.03, 0.03, 0.04, 0.8, 0.12, 0.12, 0.15, 1)
    mainFrame.listContainer = listContainer

    -- Winner Announcement Banner Frame
    local banner = CreateFrame("Frame", nil, mainFrame, template)
    banner:SetPoint("TOPLEFT", listContainer, "BOTTOMLEFT", 0, -8)
    banner:SetPoint("TOPRIGHT", listContainer, "BOTTOMRIGHT", 0, -8)
    banner:SetHeight(32)
    ApplyStyle(banner, pr * 0.15, pg * 0.15, pb * 0.15, 0.9, pr, pg, pb, 0.6)
    
    local bannerText = banner:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    bannerText:SetPoint("CENTER", banner, "CENTER", 0, 0)
    bannerText:SetText("|c" .. phex .. "Ready to spin!|r")
    banner.text = bannerText
    mainFrame.banner = banner

    -- Controls Bar
    local controlsBar = CreateFrame("Frame", nil, mainFrame)
    controlsBar:SetPoint("TOPLEFT", banner, "BOTTOMLEFT", 0, -8)
    controlsBar:SetPoint("TOPRIGHT", banner, "BOTTOMRIGHT", 0, -8)
    controlsBar:SetHeight(28)

    local channelLabel = controlsBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    channelLabel:SetPoint("LEFT", controlsBar, "LEFT", 4, 0)
    channelLabel:SetText(L["CHAT_CHANNEL"] or "Chat Output:")

    -- Channel Dropdown Button
    local chanBtn = CreateFrame("Button", "KeyRouletteChanDropdown", controlsBar, template)
    chanBtn:SetSize(110, 22)
    chanBtn:SetPoint("LEFT", channelLabel, "RIGHT", 6, 0)
    ApplyStyle(chanBtn, 0.08, 0.08, 0.10, 1, 0.25, 0.25, 0.30, 1)
    
    local chanText = chanBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    chanText:SetPoint("CENTER", chanBtn, "CENTER", 0, 0)
    chanText:SetText((KeyRouletteDB and KeyRouletteDB.announceChannel) or "PARTY")
    chanBtn.text = chanText

    chanBtn:SetScript("OnClick", function(self)
        local channels = { "PARTY", "RAID", "SAY", "INSTANCE_CHAT", "SELF" }
        local cur = (KeyRouletteDB and KeyRouletteDB.announceChannel) or "PARTY"
        local nextIdx = 1
        for i, c in ipairs(channels) do
            if c == cur then
                nextIdx = (i % #channels) + 1
                break
            end
        end
        if KeyRouletteDB then
            KeyRouletteDB.announceChannel = channels[nextIdx]
        end
        chanText:SetText(channels[nextIdx])
        pcall(PlaySound, SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or 856)
    end)

    -- Auto Announce Checkbox
    local autoCheck = CreateFrame("CheckButton", nil, controlsBar)
    autoCheck:SetSize(20, 20)
    autoCheck:SetPoint("RIGHT", controlsBar, "RIGHT", -4, 0)
    autoCheck:SetNormalTexture("Interface\\Buttons\\UI-CheckBox-Up")
    autoCheck:SetPushedTexture("Interface\\Buttons\\UI-CheckBox-Down")
    autoCheck:SetHighlightTexture("Interface\\Buttons\\UI-CheckBox-Highlight")
    autoCheck:SetCheckedTexture("Interface\\Buttons\\UI-CheckBox-Check")
    autoCheck:SetChecked(KeyRouletteDB and KeyRouletteDB.autoAnnounce)
    autoCheck:SetScript("OnClick", function(self)
        if KeyRouletteDB then
            KeyRouletteDB.autoAnnounce = self:GetChecked()
        end
        pcall(PlaySound, SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or 856)
    end)
    
    local autoText = controlsBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    autoText:SetPoint("RIGHT", autoCheck, "LEFT", -2, 0)
    autoText:SetText("Auto-Chat")

    -- Resync Keys Button
    local resyncBtn = CreateFrame("Button", nil, mainFrame, template)
    resyncBtn:SetSize(110, 40)
    resyncBtn:SetPoint("BOTTOMLEFT", mainFrame, "BOTTOMLEFT", 14, 14)
    ApplyStyle(resyncBtn, 0.12, 0.12, 0.16, 0.95, 0.3, 0.3, 0.35, 1)

    local resyncText = resyncBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    resyncText:SetPoint("CENTER", resyncBtn, "CENTER", 0, 0)
    resyncText:SetText("🔄 Resync")
    resyncBtn.text = resyncText

    resyncBtn:SetScript("OnEnter", function(self)
        ApplyStyle(self, 0.20, 0.20, 0.26, 1, 0.4, 0.4, 0.45, 1)
    end)
    resyncBtn:SetScript("OnLeave", function(self)
        ApplyStyle(self, 0.12, 0.12, 0.16, 0.95, 0.3, 0.3, 0.35, 1)
    end)
    resyncBtn:SetScript("OnClick", function()
        if KR.ResyncAllKeys then KR:ResyncAllKeys() end
    end)

    -- Big Spin Action Button
    local spinBtn = CreateFrame("Button", nil, mainFrame, template)
    spinBtn:SetSize(274, 40)
    spinBtn:SetPoint("BOTTOMRIGHT", mainFrame, "BOTTOMRIGHT", -14, 14)
    ApplyStyle(spinBtn, pr * 0.25, pg * 0.25, pb * 0.25, 0.95, pr, pg, pb, 1)

    local spinText = spinBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    spinText:SetPoint("CENTER", spinBtn, "CENTER", 0, 0)
    spinText:SetText("|c" .. phex .. (L["SPIN_BUTTON"] or "SPIN ROULETTE") .. "|r")
    spinBtn.text = spinText

    spinBtn:SetScript("OnEnter", function(self)
        ApplyStyle(self, pr * 0.4, pg * 0.4, pb * 0.4, 1, pr, pg, pb, 1)
    end)
    spinBtn:SetScript("OnLeave", function(self)
        ApplyStyle(self, pr * 0.25, pg * 0.25, pb * 0.25, 0.95, pr, pg, pb, 1)
    end)
    spinBtn:SetScript("OnClick", function()
        if KR.StartRouletteSpin then KR:StartRouletteSpin() end
    end)

    mainFrame.spinBtn = spinBtn
    mainFrame.resyncBtn = resyncBtn
    KR.UIFrame = mainFrame
    return mainFrame
end

KR.CreateMainFrame = CreateMainFrame

-- Create Party Member Card Row
local function CreateMemberRow(parent, index)
    local template = BackdropTemplateMixin and "BackdropTemplate" or nil
    local row = CreateFrame("Frame", nil, parent, template)
    row:SetSize(384, 50)
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", 4, -4 - ((index - 1) * 56))
    ApplyStyle(row, 0.08, 0.08, 0.10, 0.9, 0.18, 0.18, 0.22, 1)

    -- Exclude Checkbox
    local excludeCheck = CreateFrame("CheckButton", nil, row)
    excludeCheck:SetSize(18, 18)
    excludeCheck:SetPoint("LEFT", row, "LEFT", 6, 0)
    excludeCheck:SetNormalTexture("Interface\\Buttons\\UI-CheckBox-Up")
    excludeCheck:SetPushedTexture("Interface\\Buttons\\UI-CheckBox-Down")
    excludeCheck:SetHighlightTexture("Interface\\Buttons\\UI-CheckBox-Highlight")
    excludeCheck:SetCheckedTexture("Interface\\Buttons\\UI-CheckBox-Check")
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
    local editBtn = CreateFrame("Button", nil, row, template)
    editBtn:SetSize(34, 22)
    editBtn:SetPoint("RIGHT", row, "RIGHT", -6, 0)
    ApplyStyle(editBtn, 0.14, 0.14, 0.18, 1, 0.3, 0.3, 0.35, 1)
    
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
            row.nameText:SetText("|c" .. chex .. (member.name or "Player") .. "|r")

            -- Key info
            if member.key and member.key.level and member.key.level > 0 then
                row.icon:SetTexture(member.key.icon or 5254320)
                row.keyText:SetText("|cff00ffcc+" .. member.key.level .. "|r " .. (member.key.dungeonName or "Unknown"))
                row.excludeCheck:SetEnabled(true)
            else
                row.icon:SetTexture(134400)
                row.keyText:SetText("|cff888888" .. (L["NO_KEY_DETECTED"] or "No Key Detected") .. "|r")
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
    local pr, pg, pb, phex = KR:GetPlayerClassColor()
    local template = BackdropTemplateMixin and "BackdropTemplate" or nil

    if not manualModal then
        manualModal = CreateFrame("Frame", "KeyRouletteManualModal", UIParent, template)
        manualModal:SetSize(320, 220)
        manualModal:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
        manualModal:SetFrameStrata("DIALOG")
        ApplyStyle(manualModal, 0.06, 0.06, 0.08, 0.98, pr, pg, pb, 1)

        local mTitle = manualModal:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        mTitle:SetPoint("TOP", manualModal, "TOP", 0, -12)
        mTitle:SetText("|c" .. phex .. "Manual Key Entry|r")
        manualModal.title = mTitle

        -- Level EditBox
        local lvlLabel = manualModal:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        lvlLabel:SetPoint("TOPLEFT", manualModal, "TOPLEFT", 20, -50)
        lvlLabel:SetText("Key Level (2-30):")

        local lvlInput = CreateFrame("EditBox", nil, manualModal)
        lvlInput:SetSize(60, 22)
        lvlInput:SetPoint("LEFT", lvlLabel, "RIGHT", 10, 0)
        lvlInput:SetFontObject("GameFontHighlight")
        lvlInput:SetNumeric(true)
        lvlInput:SetMaxLetters(2)
        lvlInput:SetAutoFocus(false)
        ApplyStyle(lvlInput, 0.12, 0.12, 0.15, 1, 0.3, 0.3, 0.35, 1)
        manualModal.lvlInput = lvlInput

        -- Dungeon Select Label
        local dungLabel = manualModal:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        dungLabel:SetPoint("TOPLEFT", manualModal, "TOPLEFT", 20, -90)
        dungLabel:SetText("Select Dungeon:")

        local dungInput = CreateFrame("EditBox", nil, manualModal)
        dungInput:SetSize(260, 22)
        dungInput:SetPoint("TOPLEFT", dungLabel, "BOTTOMLEFT", 0, -8)
        dungInput:SetFontObject("GameFontHighlight")
        dungInput:SetAutoFocus(false)
        dungInput:SetText("Ara-Kara, City of Echoes")
        ApplyStyle(dungInput, 0.12, 0.12, 0.15, 1, 0.3, 0.3, 0.35, 1)
        manualModal.dungInput = dungInput

        -- Save Button
        local saveBtn = CreateFrame("Button", nil, manualModal, template)
        saveBtn:SetSize(100, 26)
        saveBtn:SetPoint("BOTTOMLEFT", manualModal, "BOTTOMLEFT", 30, 16)
        ApplyStyle(saveBtn, pr * 0.3, pg * 0.3, pb * 0.3, 1, pr, pg, pb, 1)
        local st = saveBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        st:SetPoint("CENTER", saveBtn, "CENTER", 0, 0)
        st:SetText("Save")

        saveBtn:SetScript("OnClick", function()
            if manualModal.targetMember then
                local lvl = tonumber(manualModal.lvlInput:GetText()) or 10
                local dName = manualModal.dungInput:GetText()
                if dName == "" then dName = "Custom Key" end
                local mName = manualModal.targetMember.name

                KR.manualKeys[mName] = {
                    mapID = 507,
                    level = lvl,
                    dungeonName = dName,
                    icon = 5254320,
                    source = "Manual"
                }
                KR:SaveMemberKey(mName, 507, lvl, "Manual")
                if KR.groupMembers[mName] then
                    KR.groupMembers[mName].dungeonName = dName
                end
                if KR.UpdateGroupRoster then KR:UpdateGroupRoster() end
            end
            manualModal:Hide()
            pcall(PlaySound, SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or 856)
        end)

        -- Cancel Button
        local cancelBtn = CreateFrame("Button", nil, manualModal, template)
        cancelBtn:SetSize(100, 26)
        cancelBtn:SetPoint("BOTTOMRIGHT", manualModal, "BOTTOMRIGHT", -30, 16)
        ApplyStyle(cancelBtn, 0.15, 0.15, 0.18, 1, 0.3, 0.3, 0.35, 1)
        local ct = cancelBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        ct:SetPoint("CENTER", cancelBtn, "CENTER", 0, 0)
        ct:SetText("Cancel")
        cancelBtn:SetScript("OnClick", function() manualModal:Hide() end)
    end

    manualModal.targetMember = member
    manualModal.title:SetText("|c" .. phex .. "Manual Key: " .. (member.name or "Player") .. "|r")
    manualModal.lvlInput:SetText(tostring(member.key and member.key.level or "10"))
    manualModal.dungInput:SetText(member.key and member.key.dungeonName or "Ara-Kara, City of Echoes")
    manualModal:Show()
end

local copyModal

-- Copy Log Window Modal
function KR:ShowCopyWindow(text)
    local pr, pg, pb, phex = KR:GetPlayerClassColor()
    local template = BackdropTemplateMixin and "BackdropTemplate" or nil

    if not copyModal then
        copyModal = CreateFrame("Frame", "KeyRouletteCopyModal", UIParent, template)
        copyModal:SetSize(480, 320)
        copyModal:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
        copyModal:SetFrameStrata("DIALOG")
        copyModal:EnableMouse(true)
        copyModal:SetMovable(true)
        copyModal:RegisterForDrag("LeftButton")
        copyModal:SetScript("OnDragStart", function(self) self:StartMoving() end)
        copyModal:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
        ApplyStyle(copyModal, 0.06, 0.06, 0.08, 0.98, pr, pg, pb, 1)

        local title = copyModal:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        title:SetPoint("TOPLEFT", copyModal, "TOPLEFT", 16, -14)
        title:SetText("|c" .. phex .. "Key Roulette Debug Log|r")

        local subtitle = copyModal:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        subtitle:SetPoint("LEFT", title, "RIGHT", 10, 0)
        subtitle:SetText("Press Cmd+C / Ctrl+C to copy")

        local closeBtn = CreateFrame("Button", nil, copyModal)
        closeBtn:SetSize(20, 20)
        closeBtn:SetPoint("TOPRIGHT", copyModal, "TOPRIGHT", -12, -12)
        closeBtn:SetNormalFontObject("GameFontHighlight")
        closeBtn:SetText("✕")
        closeBtn:SetScript("OnClick", function() copyModal:Hide() end)

        local scrollArea = CreateFrame("ScrollFrame", "KeyRouletteCopyScroll", copyModal, "UIPanelScrollFrameTemplate")
        scrollArea:SetPoint("TOPLEFT", copyModal, "TOPLEFT", 16, -42)
        scrollArea:SetPoint("BOTTOMRIGHT", copyModal, "BOTTOMRIGHT", -36, 45)
        ApplyStyle(scrollArea, 0.03, 0.03, 0.04, 0.8, 0.12, 0.12, 0.15, 1)

        local editBox = CreateFrame("EditBox", nil, scrollArea)
        editBox:SetMultiLine(true)
        editBox:SetMaxLetters(99999)
        editBox:SetFontObject("ChatFontNormal")
        editBox:SetWidth(410)
        editBox:SetAutoFocus(true)
        editBox:SetScript("OnEscapePressed", function() copyModal:Hide() end)

        scrollArea:SetScrollChild(editBox)
        copyModal.editBox = editBox

        local doneBtn = CreateFrame("Button", nil, copyModal, template)
        doneBtn:SetSize(120, 26)
        doneBtn:SetPoint("BOTTOM", copyModal, "BOTTOM", 0, 10)
        ApplyStyle(doneBtn, pr * 0.3, pg * 0.3, pb * 0.3, 1, pr, pg, pb, 1)
        local dt = doneBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        dt:SetPoint("CENTER", doneBtn, "CENTER", 0, 0)
        dt:SetText("Close")
        doneBtn:SetScript("OnClick", function() copyModal:Hide() end)
    end

    copyModal.editBox:SetText(text or "")
    copyModal.editBox:HighlightText()
    copyModal.editBox:SetFocus()
    copyModal:Show()
end

-- Roulette Spin Wheel Animation & Selection Logic
function KR:StartRouletteSpin()
    if isSpinning then return end
    local pr, pg, pb, phex = KR:GetPlayerClassColor()

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
            mainFrame.banner.text:SetText("|cffffaa00No keys found! Click 'Edit' to add a key.|r")
        end
        pcall(PlaySound, SOUNDKIT.IG_PLAYER_DEAD or 895)
        return
    end

    isSpinning = true
    if mainFrame and mainFrame.spinBtn then
        mainFrame.spinBtn:Disable()
        mainFrame.spinBtn.text:SetText("|cffaaaaaa" .. (L["SPINNING"] or "SPINNING...") .. "|r")
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
                ApplyStyle(memberRows[i], 0.08, 0.08, 0.10, 0.9, 0.18, 0.18, 0.22, 1)
            end
        end

        local currentCandidate = activeMembers[((step - 1) % #activeMembers) + 1]
        local activeRow = memberRows[currentCandidate.rowIndex]

        if activeRow then
            ApplyStyle(activeRow, pr * 0.2, pg * 0.2, pb * 0.2, 0.95, pr, pg, pb, 1)
        end

        pcall(PlaySound, SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or 856)

        step = step + 1
        if step <= totalTicks then
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
                    ApplyStyle(memberRows[i], 0.08, 0.08, 0.10, 0.9, 0.18, 0.18, 0.22, 1)
                end
            end

            local winningRow = memberRows[activeMembers[winnerIndex].rowIndex]
            if winningRow then
                ApplyStyle(winningRow, 0.3, 0.25, 0.05, 0.95, 1, 0.84, 0, 1)
            end

            if mainFrame and mainFrame.banner then
                mainFrame.banner.text:SetText("|cffffd700🏆 WINNER: " .. (winner.name or "Player") .. " (+" .. winner.key.level .. " " .. winner.key.dungeonName .. ")|r")
            end

            pcall(PlaySound, SOUNDKIT.UI_EPICLOOT_TOAST or 31578)

            -- Announce
            if KeyRouletteDB and KeyRouletteDB.autoAnnounce then
                if KR.AnnounceWinner then KR:AnnounceWinner(winner) end
            end

            isSpinning = false
            if mainFrame and mainFrame.spinBtn then
                mainFrame.spinBtn:Enable()
                mainFrame.spinBtn.text:SetText("|c" .. phex .. (L["SPIN_BUTTON"] or "SPIN ROULETTE") .. "|r")
            end
        end
    end

    RunSpinStep()
end

-- Create Minimap Button
local function CreateMinimapButton()
    local pr, pg, pb = KR:GetPlayerClassColor()
    local template = BackdropTemplateMixin and "BackdropTemplate" or nil

    local btn = CreateFrame("Button", "KeyRouletteMinimapButton", Minimap, template)
    btn:SetSize(32, 32)
    btn:SetFrameStrata("MEDIUM")
    btn:SetPoint("CENTER", Minimap, "CENTER", -60, -60)
    btn:SetMovable(true)
    btn:EnableMouse(true)
    btn:RegisterForClicks("AnyUp")

    ApplyStyle(btn, 0.06, 0.06, 0.08, 0.95, pr, pg, pb, 1)

    local icon = btn:CreateTexture(nil, "ARTWORK")
    icon:SetSize(20, 20)
    icon:SetPoint("CENTER", btn, "CENTER", 0, 0)
    icon:SetTexture(5254320)

    btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText("Key Roulette", pr, pg, pb)
        GameTooltip:AddLine("Click to open Mythic+ Key Roulette window.", 1, 1, 1)
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    btn:SetScript("OnClick", function()
        if KR.ToggleUI then KR:ToggleUI() end
    end)
end

-- Auto Initialize UI on Load
local initFrame = CreateFrame("Frame")
pcall(function() initFrame:RegisterEvent("PLAYER_LOGIN") end)
initFrame:SetScript("OnEvent", function()
    CreateMainFrame()
    CreateMinimapButton()
    if KR.UpdateGroupRoster then KR:UpdateGroupRoster() end
end)
