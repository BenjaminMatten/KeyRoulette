-- Key Roulette Core Logic
local addonName, KR = ...

-- Global Table
_G["KeyRoulette"] = KR

KeyRouletteDB = KeyRouletteDB or {
    announceChannel = "PARTY",
    autoAnnounce = true,
    showMinimap = true,
    customFormat = "🎲 Key Roulette picked: %s's +%d %s!",
}

KR.frame = CreateFrame("Frame")
KR.groupMembers = {}
KR.manualKeys = {}
KR.excludedKeys = {}
KR.dungeonCache = {}

-- Event Registration
KR.frame:RegisterEvent("ADDON_LOADED")
KR.frame:RegisterEvent("PLAYER_ENTERING_WORLD")
KR.frame:RegisterEvent("GROUP_ROSTER_UPDATE")
KR.frame:RegisterEvent("BAG_UPDATE_DELAYED")
KR.frame:RegisterEvent("CHALLENGE_MODE_KEYSTONE_RECEPTACLE_OPEN")
KR.frame:RegisterEvent("CHAT_MSG_ADDON")

-- Class Colors Helper
function KR:GetPlayerClassColor()
    local _, classFilename = UnitClass("player")
    local color = (CUSTOM_CLASS_COLORS and CUSTOM_CLASS_COLORS[classFilename]) or (classFilename and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFilename])
    if color then
        local hex = string.format("ff%02x%02x%02x", color.r * 255, color.g * 255, color.b * 255)
        return color.r, color.g, color.b, hex, classFilename
    end
    return 0.8, 0.8, 0.8, "ffcccccc", "PRIEST"
end

function KR:GetUnitClassColor(unit)
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

-- Dungeon Info Cache
function KR:GetDungeonInfo(mapID)
    if not mapID or mapID == 0 then return nil end
    if KR.dungeonCache[mapID] then
        return KR.dungeonCache[mapID]
    end

    local name, id, timeLimit, texture, backgroundTexture
    if C_ChallengeMode and C_ChallengeMode.GetMapUIInfo then
        name, id, timeLimit, texture, backgroundTexture = C_ChallengeMode.GetMapUIInfo(mapID)
    end

    if not name or name == "" then
        name = "Unknown Key (" .. mapID .. ")"
        texture = 5254320 -- Default Mythic Keystone Icon
    end

    local info = {
        name = name,
        icon = texture or 5254320,
        mapID = mapID,
    }
    KR.dungeonCache[mapID] = info
    return info
end

-- Scan Player Bag for Mythic+ Keystone
function KR:ScanPlayerKeystone()
    local mapID, level, itemLink

    -- Try C_MythicPlus API
    if C_MythicPlus then
        if C_MythicPlus.GetOwnedKeystoneChallengeMapID then
            mapID = C_MythicPlus.GetOwnedKeystoneChallengeMapID()
        end
        if C_MythicPlus.GetOwnedKeystoneLevel then
            level = C_MythicPlus.GetOwnedKeystoneLevel()
        end
    end

    -- Fallback/Verify via Container Scan
    if not mapID or mapID == 0 or not level or level == 0 then
        for bag = 0, 5 do
            local numSlots = (C_Container and C_Container.GetContainerNumSlots) and C_Container.GetContainerNumSlots(bag) or 0
            for slot = 1, numSlots do
                local link
                if C_Container and C_Container.GetContainerItemLink then
                    link = C_Container.GetContainerItemLink(bag, slot)
                end
                if link and (link:find("keystone:") or link:find("item:180653")) then
                    itemLink = link
                    -- Parse Keystone link string format: |Hkeystone:Item:MapID:Level:...
                    local mID, lvl = link:match("keystone:%d+:(%d+):(%d+)")
                    if mID and lvl then
                        mapID = tonumber(mID)
                        level = tonumber(lvl)
                        break
                    end
                end
            end
            if mapID and mapID > 0 then break end
        end
    end

    if mapID and mapID > 0 and level and level > 0 then
        local dungeon = KR:GetDungeonInfo(mapID)
        KR.playerKey = {
            mapID = mapID,
            level = level,
            dungeonName = dungeon and dungeon.name or ("Map " .. mapID),
            icon = dungeon and dungeon.icon or 5254320,
            link = itemLink,
            source = "Auto"
        }
    else
        KR.playerKey = nil
    end

    return KR.playerKey
end

-- Broadcast Self Keystone to Party
function KR:BroadcastKeystone()
    if not IsInGroup() then return end
    local key = KR:ScanPlayerKeystone()
    if key then
        local msg = string.format("KEY:%d:%d:%s", key.mapID, key.level, key.dungeonName or "")
        C_ChatInfo.SendAddonMessage("KeyRoulette", msg, IsInRaid() and "RAID" or "PARTY")
    end
end

-- Request Group Keystones
function KR:RequestGroupKeystones()
    if not IsInGroup() then return end
    C_ChatInfo.SendAddonMessage("KeyRoulette", "PING", IsInRaid() and "RAID" or "PARTY")
end

-- Update Group Roster Data
function KR:UpdateGroupRoster()
    KR:ScanPlayerKeystone()
    local members = {}

    local playerName = UnitName("player") or "Player"
    local _, playerClass = UnitClass("player")
    local playerRole = UnitGroupRolesAssigned("player") or "NONE"

    -- Add Player
    table.insert(members, {
        unit = "player",
        name = playerName,
        class = playerClass,
        role = playerRole,
        key = KR.manualKeys[playerName] or KR.playerKey,
        isSelf = true,
    })

    -- Add Party / Raid Members
    if IsInGroup() then
        local prefix = IsInRaid() and "raid" or "party"
        local num = GetNumGroupMembers()

        for i = 1, (IsInRaid() and num or (num - 1)) do
            local unit = prefix .. i
            if UnitExists(unit) and not UnitIsUnit(unit, "player") then
                local name = UnitName(unit)
                local _, class = UnitClass(unit)
                local role = UnitGroupRolesAssigned(unit) or "NONE"

                table.insert(members, {
                    unit = unit,
                    name = name,
                    class = class,
                    role = role,
                    key = KR.manualKeys[name] or KR.groupMembers[name],
                    isSelf = false,
                })
            end
        end
    end

    KR.currentMembers = members

    if KR.OnGroupUpdated then
        KR:OnGroupUpdated()
    end
end

-- Event Listener Handler
KR.frame:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        local loadedAddon = ...
        if loadedAddon == addonName then
            KeyRouletteDB = KeyRouletteDB or {}
            KeyRouletteDB.announceChannel = KeyRouletteDB.announceChannel or "PARTY"
            if KeyRouletteDB.autoAnnounce == nil then KeyRouletteDB.autoAnnounce = true end
            if KeyRouletteDB.showMinimap == nil then KeyRouletteDB.showMinimap = true end
            KeyRouletteDB.customFormat = KeyRouletteDB.customFormat or "🎲 Key Roulette picked: %s's +%d %s!"

            C_ChatInfo.RegisterAddonMessagePrefix("KeyRoulette")
            KR:ScanPlayerKeystone()
            KR:UpdateGroupRoster()
        end

    elseif event == "PLAYER_ENTERING_WORLD" then
        C_ChatInfo.RegisterAddonMessagePrefix("KeyRoulette")
        KR:BroadcastKeystone()
        KR:UpdateGroupRoster()

    elseif event == "GROUP_ROSTER_UPDATE" then
        KR:BroadcastKeystone()
        KR:RequestGroupKeystones()
        KR:UpdateGroupRoster()

    elseif event == "BAG_UPDATE_DELAYED" or event == "CHALLENGE_MODE_KEYSTONE_RECEPTACLE_OPEN" then
        KR:ScanPlayerKeystone()
        KR:BroadcastKeystone()
        KR:UpdateGroupRoster()

    elseif event == "CHAT_MSG_ADDON" then
        local prefix, message, channel, sender = ...
        if prefix == "KeyRoulette" then
            local senderName = (Ambiguate and Ambiguate(sender, "none")) or sender:match("([^-]+)") or sender

            if message == "PING" then
                KR:BroadcastKeystone()
            elseif message:sub(1, 4) == "KEY:" then
                local mapID, level, dungeonName = message:match("KEY:(%d+):(%d+):?(.*)")
                if mapID and level then
                    mapID = tonumber(mapID)
                    level = tonumber(level)
                    local dungeon = KR:GetDungeonInfo(mapID)

                    KR.groupMembers[senderName] = {
                        mapID = mapID,
                        level = level,
                        dungeonName = (dungeon and dungeon.name) or (dungeonName ~= "" and dungeonName) or ("Map " .. mapID),
                        icon = dungeon and dungeon.icon or 5254320,
                        source = "Synced"
                    }
                    KR:UpdateGroupRoster()
                end
            end
        end
    end
end)

-- Announce Winner Function
function KR:AnnounceWinner(winner)
    if not winner or not winner.key then return end
    local key = winner.key
    local fmt = (KeyRouletteDB and KeyRouletteDB.customFormat) or "🎲 Key Roulette picked: %s's +%d %s!"
    local msg = string.format(fmt, winner.name, key.level, key.dungeonName)

    local channel = (KeyRouletteDB and KeyRouletteDB.announceChannel) or "PARTY"

    if channel == "SELF" then
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ffcc[Key Roulette]|r " .. msg)
    elseif channel == "PARTY" and IsInGroup() then
        SendChatMessage(msg, IsInRaid() and "RAID" or "PARTY")
    elseif channel == "RAID" and IsInRaid() then
        SendChatMessage(msg, "RAID")
    elseif channel == "SAY" then
        SendChatMessage(msg, "SAY")
    elseif channel == "INSTANCE_CHAT" and IsInGroup() then
        SendChatMessage(msg, "INSTANCE_CHAT")
    else
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ffcc[Key Roulette]|r " .. msg)
    end
end

-- Toggle UI Function
function KR:ToggleUI()
    if not KR.UIFrame then
        if KR.CreateMainFrame then
            KR:CreateMainFrame()
        end
    end

    if KR.UIFrame then
        if KR.UIFrame:IsShown() then
            KR.UIFrame:Hide()
        else
            KR:UpdateGroupRoster()
            KR.UIFrame:Show()
        end
    else
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ffcc[Key Roulette]|r Could not initialize UI frame.")
    end
end

-- Register Slash Commands
SLASH_KEYROULETTE1 = "/kr"
SLASH_KEYROULETTE2 = "/keyroulette"
SLASH_KEYROULETTE3 = "/keyr"

SlashCmdList["KEYROULETTE"] = function(msg)
    msg = (msg and msg:gsub("^%s*(.-)%s*$", "%1"):lower()) or ""
    if msg == "spin" then
        if KR.StartRouletteSpin then
            KR:StartRouletteSpin()
        end
    else
        KR:ToggleUI()
    end
end
