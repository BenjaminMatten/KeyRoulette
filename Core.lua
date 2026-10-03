-- Key Roulette Core Logic
local addonName, KR = ...

-- Global Table
_G["KeyRoulette"] = KR

KeyRouletteDB = KeyRouletteDB or {
    announceChannel = "PARTY",
    autoAnnounce = true,
    showMinimap = true,
    customFormat = "🎲 Key Roulette picked: %s's +%d %s!",
    groupKeys = {},
}

KR.frame = CreateFrame("Frame")
KR.groupMembers = {}
KR.manualKeys = {}
KR.excludedKeys = {}
KR.dungeonCache = {}

-- Safe Event Registration
local function SafeRegisterEvent(evt)
    pcall(function() KR.frame:RegisterEvent(evt) end)
end

SafeRegisterEvent("ADDON_LOADED")
SafeRegisterEvent("PLAYER_ENTERING_WORLD")
SafeRegisterEvent("GROUP_ROSTER_UPDATE")
SafeRegisterEvent("BAG_UPDATE_DELAYED")
SafeRegisterEvent("CHAT_MSG_ADDON")
SafeRegisterEvent("CHAT_MSG_PARTY")
SafeRegisterEvent("CHAT_MSG_PARTY_LEADER")
SafeRegisterEvent("CHAT_MSG_RAID")
SafeRegisterEvent("CHAT_MSG_RAID_LEADER")
SafeRegisterEvent("CHAT_MSG_SAY")
SafeRegisterEvent("CHAT_MSG_INSTANCE_CHAT")

-- Register Addon Communication Prefixes
local function RegisterAddonPrefixes()
    local prefixes = {
        "KeyRoulette", "EllesmereUI", "Ellesmere", "LibOpenKeystone", "LibOpenKeystone-1.0",
        "LibTomoKeystoneSync", "LibTomoKeystoneSync-1.0", "TomoKeystoneSync", "TomoKeys", "LTKS",
        "LibKeystone", "LibKeystone-1.0", "LKS", "LKS1", "LibDungeonKeys-1.0",
        "LibOpenRaid", "LibOpenRaid-1.0", "LOR", "LOR1", "OpenRaid",
        "AstralKeys", "Details", "MythicKeystones", "RaiderIO"
    }
    for _, p in ipairs(prefixes) do
        pcall(C_ChatInfo.RegisterAddonMessagePrefix, p)
    end
end

-- Register Library Event Callbacks
local function RegisterLibraryCallbacks()
    local lor = (LibStub and LibStub("LibOpenRaid-1.0", true)) or _G.LibOpenRaid
    if lor and lor.RegisterCallback then
        pcall(function()
            lor:RegisterCallback("KeystoneUpdate", function() KR:UpdateGroupRoster() end)
        end)
    end

    local tomo = (LibStub and (LibStub("LibTomoKeystoneSync-1.0", true) or LibStub("LibTomoKeystoneSync", true)))
              or _G.LibTomoKeystoneSync or _G.TomoKeystoneSync
    if tomo and tomo.RegisterCallback then
        pcall(function()
            tomo:RegisterCallback("KeystoneUpdate", function() KR:UpdateGroupRoster() end)
        end)
    end

    local lok = (LibStub and (LibStub("LibOpenKeystone-1.0", true) or LibStub("LibOpenKeystone", true))) or _G.LibOpenKeystone
    if lok and lok.RegisterCallback then
        pcall(function()
            lok:RegisterCallback("KeystoneUpdate", function() KR:UpdateGroupRoster() end)
        end)
    end
end

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
        texture = 5254320
    end

    local info = {
        name = name,
        icon = texture or 5254320,
        mapID = mapID,
    }
    KR.dungeonCache[mapID] = info
    return info
end

-- Save Member Key with Name Normalization & SavedVariables Persistence
function KR:SaveMemberKey(rawName, mapID, level, source)
    if not rawName or not mapID or not level or mapID <= 0 or level <= 0 then return end
    local shortName = rawName:match("([^-]+)") or rawName
    local realm = GetNormalizedRealmName() or GetRealmName() or ""
    local fullName = rawName:find("-") and rawName or (shortName .. "-" .. realm)

    local dungeon = KR:GetDungeonInfo(mapID)
    local keyData = {
        mapID = mapID,
        level = level,
        dungeonName = dungeon and dungeon.name or ("Map " .. mapID),
        icon = dungeon and dungeon.icon or 5254320,
        source = source or "Synced",
        timestamp = time()
    }

    -- Memory cache
    KR.groupMembers[rawName] = keyData
    KR.groupMembers[shortName] = keyData
    KR.groupMembers[fullName] = keyData
    KR.groupMembers[rawName:lower()] = keyData
    KR.groupMembers[shortName:lower()] = keyData

    -- Persistent SavedVariables cache
    KeyRouletteDB = KeyRouletteDB or {}
    KeyRouletteDB.groupKeys = KeyRouletteDB.groupKeys or {}
    KeyRouletteDB.groupKeys[rawName] = keyData
    KeyRouletteDB.groupKeys[shortName] = keyData
    KeyRouletteDB.groupKeys[fullName] = keyData
end

-- Universal MapID and Level Extractor (Handles tables, multi-returns, string pairs)
local function ExtractMapAndLevel(res1, res2)
    if type(res1) == "table" then
        local mID = tonumber(res1.mapID or res1.challengeMapID or res1.dungeonID or res1.dungeon_id or res1.map_id or res1.keyID or res1.map or res1[1])
        local lvl = tonumber(res1.level or res1.keyLevel or res1.key_level or res1.levelNumber or res1.key_level or res1.level_num or res1[2])
        return mID, lvl
    elseif type(res1) == "number" and type(res2) == "number" then
        return res1, res2
    elseif type(res1) == "string" then
        local mID, lvl = res1:match("(%d+):(%d+)") or res1:match("(%d+),(%d+)") or res1:match("(%d+)#(%d+)")
        if mID and lvl then return tonumber(mID), tonumber(lvl) end
    end
    return nil, nil
end

-- Deep Global Table Recursive Searcher (Finds keystone mapID + level for player name in any table)
local function DeepSearchTable(tbl, searchNames, depth)
    if not tbl or type(tbl) ~= "table" or (depth and depth > 4) then return nil, nil end
    depth = (depth or 0) + 1

    for key, val in pairs(tbl) do
        if type(key) == "string" then
            for _, sName in ipairs(searchNames) do
                if key == sName or key:lower() == sName:lower() or key:find(sName, 1, true) then
                    local mID, lvl = ExtractMapAndLevel(val)
                    if mID and lvl then return mID, lvl end
                end
            end
        end

        if type(val) == "table" and key ~= "_G" and key ~= "KR" and key ~= "KeyRoulette" and key ~= "UIParent" and key ~= "WorldFrame" then
            local mID, lvl = DeepSearchTable(val, searchNames, depth)
            if mID and lvl then return mID, lvl end
        end
    end
    return nil, nil
end

-- Comprehensive Keystone Lookup Engine
function KR:FindPartyMemberKey(unit, name)
    if not name then return nil end
    local shortName = name:match("([^-]+)") or name
    local realm = GetNormalizedRealmName() or GetRealmName() or ""
    local fullName = name:find("-") and name or (shortName .. "-" .. realm)
    local guid = UnitExists(unit) and UnitGUID(unit)
    local searchNames = { fullName, shortName, name, guid }

    -- 1. Check manual override
    if KR.manualKeys[name] then return KR.manualKeys[name] end
    if KR.manualKeys[shortName] then return KR.manualKeys[shortName] end
    if KR.manualKeys[fullName] then return KR.manualKeys[fullName] end

    -- 2. Check in-memory sync cache
    local cached = KR.groupMembers[name] or KR.groupMembers[shortName] or KR.groupMembers[fullName]
                or KR.groupMembers[name:lower()] or KR.groupMembers[shortName:lower()]
    if cached then return cached end

    -- 3. Check persistent SavedVariables DB cache
    if KeyRouletteDB and KeyRouletteDB.groupKeys then
        local saved = KeyRouletteDB.groupKeys[name] or KeyRouletteDB.groupKeys[shortName] or KeyRouletteDB.groupKeys[fullName]
        if saved then
            KR.groupMembers[name] = saved
            return saved
        end
    end

    -- 4. Check LibOpenRaid (Queries unit, guid, shortName, fullName)
    local lor = (LibStub and LibStub("LibOpenRaid-1.0", true)) or _G.LibOpenRaid
    if lor then
        pcall(function()
            local r1, r2
            if lor.GetKeystoneInfo then
                r1, r2 = lor:GetKeystoneInfo(unit)
                if not r1 and guid then r1, r2 = lor:GetKeystoneInfo(guid) end
                if not r1 then r1, r2 = lor:GetKeystoneInfo(shortName) end
                if not r1 then r1, r2 = lor:GetKeystoneInfo(fullName) end
            end
            if not r1 and lor.GetPlayerKeystone then
                r1, r2 = lor:GetPlayerKeystone(unit)
                if not r1 and guid then r1, r2 = lor:GetPlayerKeystone(guid) end
                if not r1 then r1, r2 = lor:GetPlayerKeystone(shortName) end
            end
            if not r1 and lor.GetKeystones then
                local allKeys = lor:GetKeystones()
                if type(allKeys) == "table" then
                    r1 = allKeys[unit] or (guid and allKeys[guid]) or allKeys[shortName] or allKeys[fullName]
                end
            end
            if not r1 and lor.keystones then r1 = lor.keystones[unit] or (guid and lor.keystones[guid]) or lor.keystones[shortName] or lor.keystones[fullName] end
            if not r1 and lor.KeystoneInfo then r1 = lor.KeystoneInfo[unit] or (guid and lor.KeystoneInfo[guid]) or lor.KeystoneInfo[shortName] or lor.KeystoneInfo[fullName] end
            if not r1 and lor.allyData then
                local ally = lor.allyData[unit] or (guid and lor.allyData[guid]) or lor.allyData[shortName] or lor.allyData[fullName]
                if ally then r1 = ally.keystone or ally.keystoneInfo or ally end
            end

            local mID, lvl = ExtractMapAndLevel(r1, r2)
            if mID and lvl then
                KR:SaveMemberKey(name, mID, lvl, "LibOpenRaid")
            end
        end)
        if KR.groupMembers[name] then return KR.groupMembers[name] end
    end

    -- 5. Check KeystoneLoot (KeystoneLootDB, KeystoneLootCharDB, KeystoneLootAPI)
    if _G.KeystoneLootDB or _G.KeystoneLootAPI or _G.KeystoneLootCharDB then
        pcall(function()
            local kl = _G.KeystoneLootDB or _G.KeystoneLootAPI or _G.KeystoneLootCharDB
            if kl then
                local mID, lvl = DeepSearchTable(kl, searchNames, 0)
                if mID and lvl then
                    KR:SaveMemberKey(name, mID, lvl, "KeystoneLoot")
                end
            end
        end)
        if KR.groupMembers[name] then return KR.groupMembers[name] end
    end

    -- 6. Check LibTomoKeystoneSync
    local tomo = (LibStub and (LibStub("LibTomoKeystoneSync-1.0", true) or LibStub("LibTomoKeystoneSync", true)))
              or _G.LibTomoKeystoneSync or _G.TomoKeystoneSync or _G.TomoKeys
    if tomo then
        pcall(function()
            local r1, r2
            if tomo.GetKeystone then r1, r2 = tomo:GetKeystone(unit) end
            if not r1 and tomo.GetKeystoneInfo then r1, r2 = tomo:GetKeystoneInfo(unit) end
            if not r1 and tomo.GetPlayerKeystone then r1, r2 = tomo:GetPlayerKeystone(unit) end
            if not r1 and tomo.GetKey then r1, r2 = tomo:GetKey(unit) end
            if not r1 and tomo.GetKeystoneInfo then r1, r2 = tomo:GetKeystoneInfo(shortName) end
            if not r1 and tomo.keys then r1 = tomo.keys[fullName] or tomo.keys[shortName] or tomo.keys[unit] end
            if not r1 and tomo.keystones then r1 = tomo.keystones[fullName] or tomo.keystones[shortName] or tomo.keystones[unit] end

            local mID, lvl = ExtractMapAndLevel(r1, r2)
            if mID and lvl then
                KR:SaveMemberKey(name, mID, lvl, "LibTomoKeystoneSync")
            end
        end)
        if KR.groupMembers[name] then return KR.groupMembers[name] end
    end

    -- 7. Check LibOpenKeystone
    local lok = (LibStub and (LibStub("LibOpenKeystone-1.0", true) or LibStub("LibOpenKeystone", true))) or _G.LibOpenKeystone
    if lok then
        pcall(function()
            local r1, r2
            if lok.GetKeystone then r1, r2 = lok:GetKeystone(unit) end
            if not r1 and lok.GetKeystoneInfo then r1, r2 = lok:GetKeystoneInfo(unit) end
            if not r1 and lok.keystones then r1 = lok.keystones[fullName] or lok.keystones[shortName] end

            local mID, lvl = ExtractMapAndLevel(r1, r2)
            if mID and lvl then
                KR:SaveMemberKey(name, mID, lvl, "LibOpenKeystone")
            end
        end)
        if KR.groupMembers[name] then return KR.groupMembers[name] end
    end

    -- 8. Check RaiderIO
    if _G.RaiderIO then
        pcall(function()
            if _G.RaiderIO.GetProfile then
                local prof = _G.RaiderIO.GetProfile(unit) or _G.RaiderIO.GetProfile(shortName) or _G.RaiderIO.GetProfile(fullName)
                if prof then
                    local mID, lvl = ExtractMapAndLevel(prof.keystone or prof.currentKeystone or prof.mythicKeystone or prof)
                    if not mID and type(prof) == "table" then
                        for k, v in pairs(prof) do
                            if type(k) == "string" and (k:lower():find("key") or k:lower():find("dungeon")) then
                                mID, lvl = ExtractMapAndLevel(v)
                                if mID and lvl then break end
                            end
                        end
                    end
                    if mID and lvl then
                        KR:SaveMemberKey(name, mID, lvl, "RaiderIO")
                    end
                end
            end
        end)
        if KR.groupMembers[name] then return KR.groupMembers[name] end
    end

    -- 9. Check Details!
    if _G.Details and _G.Details.Keystones then
        pcall(function()
            local dKey = _G.Details.Keystones[fullName] or _G.Details.Keystones[shortName] or _G.Details.Keystones[name]
            local mID, lvl = ExtractMapAndLevel(dKey)
            if mID and lvl then
                KR:SaveMemberKey(name, mID, lvl, "Details")
            end
        end)
        if KR.groupMembers[name] then return KR.groupMembers[name] end
    end

    -- 10. Check AstralKeys
    if _G.AstralKeys then
        pcall(function()
            local aKey
            if _G.AstralKeys.GetKey then aKey = _G.AstralKeys:GetKey(shortName) or _G.AstralKeys:GetKey(fullName) end
            if not aKey and type(_G.AstralKeys) == "table" then aKey = _G.AstralKeys[shortName] or _G.AstralKeys[fullName] end

            local mID, lvl = ExtractMapAndLevel(aKey)
            if mID and lvl then
                KR:SaveMemberKey(name, mID, lvl, "AstralKeys")
            end
        end)
        if KR.groupMembers[name] then return KR.groupMembers[name] end
    end

    -- 11. Deep Global Scanner for EllesmereUI, EUI, KeystoneLoot, Tomo, ElvUI, Cell, OmniCD, etc.
    for gName, gVal in pairs(_G) do
        if type(gName) == "string" and (gName:find("Ellesmere") or gName:find("Tust") or gName:find("EUI") or gName:find("Tomo") or gName:find("Elv") or gName:find("Key") or gName:find("Cell") or gName:find("Omni")) and type(gVal) == "table" then
            pcall(function()
                local mID, lvl = DeepSearchTable(gVal, searchNames, 0)
                if mID and lvl then
                    KR:SaveMemberKey(name, mID, lvl, gName)
                end
            end)
            if KR.groupMembers[name] then return KR.groupMembers[name] end
        end
    end

    -- 12. Tooltip Unit Scanner (C_TooltipInfo)
    if C_TooltipInfo and C_TooltipInfo.GetUnit then
        pcall(function()
            local data = C_TooltipInfo.GetUnit(unit)
            if data and data.lines then
                for _, line in ipairs(data.lines) do
                    if line.leftText then
                        local lvl, dName = line.leftText:match("%+(%d+)%s+(.+)")
                        if not lvl then dName, lvl = line.leftText:match("(.+)%s+%+(%d+)") end
                        if lvl and dName then
                            lvl = tonumber(lvl)
                            if lvl and lvl > 0 then
                                KR:SaveMemberKey(name, 507, lvl, "Tooltip")
                            end
                        end
                    end
                end
            end
        end)
    end

    return KR.groupMembers[name] or KR.groupMembers[shortName]
end

-- Diagnostic Debug Command (Saves to SavedVariables & Triggers Copy Window)
function KR:RunDebug()
    local logLines = {}
    local function AddLog(msg)
        table.insert(logLines, msg)
        if DEFAULT_CHAT_FRAME then
            DEFAULT_CHAT_FRAME:AddMessage(msg)
        end
    end

    AddLog("|cff00ffcc=== KEY ROULETTE DEBUG ===|r")
    AddLog("Time: " .. date("%Y-%m-%d %H:%M:%S"))
    AddLog("In Group: " .. tostring(IsInGroup()) .. " | Num Members: " .. tostring(GetNumGroupMembers()))
    
    -- Check globals
    AddLog("EllesmereUI: " .. tostring(_G.EllesmereUI ~= nil) .. " | EllesmereUIDB: " .. tostring(_G.EllesmereUIDB ~= nil))
    AddLog("Details: " .. tostring(_G.Details ~= nil) .. " | AstralKeys: " .. tostring(_G.AstralKeys ~= nil))
    AddLog("RaiderIO: " .. tostring(_G.RaiderIO ~= nil) .. " | ElvUI: " .. tostring(_G.ElvUI ~= nil))
    AddLog("LibOpenRaid: " .. tostring(LibStub and LibStub("LibOpenRaid-1.0", true) ~= nil))
    AddLog("LibTomo: " .. tostring(LibStub and (LibStub("LibTomoKeystoneSync-1.0", true) or LibStub("LibTomoKeystoneSync", true)) ~= nil))
    AddLog("LibOpenKeystone: " .. tostring(LibStub and (LibStub("LibOpenKeystone-1.0", true) or LibStub("LibOpenKeystone", true)) ~= nil))
    AddLog("LibKeystone: " .. tostring(LibStub and LibStub("LibKeystone-1.0", true) ~= nil))

    -- List all loaded keystone-related globals
    local foundGlobals = {}
    for gName in pairs(_G) do
        if type(gName) == "string" and (gName:find("Ellesmere") or gName:find("EUI") or gName:find("Keystone") or gName:find("Tomo") or gName:find("OpenRaid")) then
            table.insert(foundGlobals, gName)
        end
    end
    if #foundGlobals > 0 then
        AddLog("Found Related Globals: " .. table.concat(foundGlobals, ", "))
    else
        AddLog("No specific Ellesmere/Keystone globals found in _G.")
    end

    -- Deep Member Inspection Trace
    if IsInGroup() then
        local num = GetNumGroupMembers()
        for i = 1, (num - 1) do
            local unit = "party" .. i
            if UnitExists(unit) then
                local name = UnitName(unit)
                local guid = UnitGUID(unit)
                local shortName = name:match("([^-]+)") or name
                AddLog("--- Inspecting Party Member " .. i .. ": " .. tostring(name) .. " (GUID: " .. tostring(guid) .. ") ---")

                -- LibOpenRaid check
                local lor = (LibStub and LibStub("LibOpenRaid-1.0", true)) or _G.LibOpenRaid
                if lor then
                    pcall(function()
                        if lor.GetKeystoneInfo then
                            local m, l = lor:GetKeystoneInfo(unit)
                            if not m and guid then m, l = lor:GetKeystoneInfo(guid) end
                            if m and l then AddLog("  [LibOpenRaid:GetKeystoneInfo]: +" .. tostring(l) .. " (Map " .. tostring(m) .. ")") end
                        end
                        if lor.allyData then
                            local ally = lor.allyData[unit] or (guid and lor.allyData[guid]) or lor.allyData[shortName]
                            if ally then AddLog("  [LibOpenRaid.allyData]: found ally record") end
                        end
                    end)
                end

                -- RaiderIO check
                if _G.RaiderIO and _G.RaiderIO.GetProfile then
                    pcall(function()
                        local prof = _G.RaiderIO.GetProfile(unit) or _G.RaiderIO.GetProfile(shortName)
                        if prof then AddLog("  [RaiderIO.GetProfile]: profile object found") end
                    end)
                end

                -- KeystoneLoot check
                if _G.KeystoneLootDB then AddLog("  [KeystoneLootDB]: present") end
            end
        end
    end

    -- Dump cached keys
    local count = 0
    if KR.groupMembers then
        for k, v in pairs(KR.groupMembers) do
            count = count + 1
            AddLog("Cached Key [" .. tostring(k) .. "]: " .. tostring(v.dungeonName) .. " +" .. tostring(v.level) .. " (" .. tostring(v.source) .. ")")
        end
    end
    if count == 0 then
        AddLog("No cached keys in memory.")
    end

    -- Dump Party Member 1-4
    if IsInGroup() then
        local num = GetNumGroupMembers()
        for i = 1, (num - 1) do
            local unit = "party" .. i
            if UnitExists(unit) then
                local name = UnitName(unit)
                local key = KR:FindPartyMemberKey(unit, name)
                AddLog("Party Member " .. i .. " (" .. tostring(name) .. "): " .. (key and ("+" .. key.level .. " " .. key.dungeonName .. " [" .. key.source .. "]") or "No Key Detected (Click 'Edit' to set)"))
            end
        end
    else
        AddLog("Not in group (Solo).")
    end
    AddLog("|cff00ffcc===========================|r")

    local reportText = table.concat(logLines, "\n")

    -- Save to SavedVariables for file persistence
    KeyRouletteDB = KeyRouletteDB or {}
    KeyRouletteDB.latestDebugReport = reportText
    KeyRouletteDB.debugLog = logLines

    -- Show Copy Window Modal in UI
    if KR.ShowCopyWindow then
        KR:ShowCopyWindow(reportText)
    end

    return reportText
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
        local targetChan = IsInRaid() and "RAID" or "PARTY"
        pcall(C_ChatInfo.SendAddonMessage, "KeyRoulette", string.format("KEY:%d:%d:%s", key.mapID, key.level, key.dungeonName or ""), targetChan)
        pcall(C_ChatInfo.SendAddonMessage, "EllesmereUI", string.format("KEY:%d:%d", key.mapID, key.level), targetChan)
        pcall(C_ChatInfo.SendAddonMessage, "LibOpenKeystone", string.format("KEY:%d:%d", key.mapID, key.level), targetChan)
        pcall(C_ChatInfo.SendAddonMessage, "LibTomoKeystoneSync", string.format("KEY:%d:%d", key.mapID, key.level), targetChan)
        pcall(C_ChatInfo.SendAddonMessage, "LTKS", string.format("%d:%d", key.mapID, key.level), targetChan)
        pcall(C_ChatInfo.SendAddonMessage, "LibKeystone", string.format("KEY:%d:%d", key.mapID, key.level), targetChan)
        pcall(C_ChatInfo.SendAddonMessage, "LKS", string.format("%d:%d", key.mapID, key.level), targetChan)
        pcall(C_ChatInfo.SendAddonMessage, "LibOpenRaid", string.format("KEY,%d,%d", key.mapID, key.level), targetChan)
        pcall(C_ChatInfo.SendAddonMessage, "LOR", string.format("KEY,%d,%d", key.mapID, key.level), targetChan)
    end
end

-- Request Group Keystones
function KR:RequestGroupKeystones()
    if not IsInGroup() then return end
    local targetChan = IsInRaid() and "RAID" or "PARTY"

    -- Invoke EllesmereUI functions
    local eui = _G.EllesmereUI or _G.Ellesmere
    if eui then
        pcall(function()
            if eui.RequestKeystones then eui:RequestKeystones() end
            if eui.SyncKeystones then eui:SyncKeystones() end
        end)
    end

    -- Invoke LibOpenKeystone functions
    local lok = (LibStub and (LibStub("LibOpenKeystone-1.0", true) or LibStub("LibOpenKeystone", true))) or _G.LibOpenKeystone
    if lok then
        pcall(function()
            if lok.RequestKeystones then lok:RequestKeystones() end
            if lok.SendKeystone then lok:SendKeystone() end
        end)
    end

    -- Invoke LibOpenRaid functions
    local lor = (LibStub and LibStub("LibOpenRaid-1.0", true)) or _G.LibOpenRaid
    if lor then
        pcall(function()
            if lor.RequestKeystoneInfo then lor:RequestKeystoneInfo() end
            if lor.SendKeystoneInfo then lor:SendKeystoneInfo() end
            if lor.RequestAllAlliesData then lor:RequestAllAlliesData() end
        end)
    end

    -- Invoke LibTomoKeystoneSync functions
    local tomo = (LibStub and (LibStub("LibTomoKeystoneSync-1.0", true) or LibStub("LibTomoKeystoneSync", true)))
              or _G.LibTomoKeystoneSync or _G.TomoKeystoneSync
    if tomo then
        pcall(function()
            if tomo.RequestKeystones then tomo:RequestKeystones() end
            if tomo.RequestKeys then tomo:RequestKeys() end
            if tomo.SendKeystone then tomo:SendKeystone() end
            if tomo.Sync then tomo:Sync() end
        end)
    end

    -- Invoke LibKeystone functions
    local lks = LibStub and LibStub("LibKeystone-1.0", true)
    if lks then
        pcall(function()
            if lks.RequestKeystones then lks:RequestKeystones() end
            if lks.SendKeystone then lks:SendKeystone() end
        end)
    end

    -- Send network pings
    pcall(C_ChatInfo.SendAddonMessage, "KeyRoulette", "PING", targetChan)
    pcall(C_ChatInfo.SendAddonMessage, "EllesmereUI", "REQUEST", targetChan)
    pcall(C_ChatInfo.SendAddonMessage, "LibOpenKeystone", "REQUEST", targetChan)
    pcall(C_ChatInfo.SendAddonMessage, "LibTomoKeystoneSync", "REQUEST", targetChan)
    pcall(C_ChatInfo.SendAddonMessage, "LTKS", "REQ", targetChan)
    pcall(C_ChatInfo.SendAddonMessage, "LibKeystone", "REQUEST", targetChan)
    pcall(C_ChatInfo.SendAddonMessage, "LKS", "REQ", targetChan)
    pcall(C_ChatInfo.SendAddonMessage, "LibOpenRaid", "REQUEST_KEY", targetChan)
    pcall(C_ChatInfo.SendAddonMessage, "LOR", "REQ_KEY", targetChan)
end

-- Manual Resync All Keys Action
function KR:ResyncAllKeys()
    KR:ScanPlayerKeystone()
    KR:RequestGroupKeystones()
    KR:BroadcastKeystone()
    KR:UpdateGroupRoster()

    -- Staggered async timers to capture network responses
    C_Timer.After(0.4, function()
        KR:RequestGroupKeystones()
        KR:UpdateGroupRoster()
    end)
    C_Timer.After(1.2, function()
        KR:UpdateGroupRoster()
    end)

    if KR.UIFrame and KR.UIFrame.banner then
        KR.UIFrame.banner.text:SetText("|cff00ffcc🔄 Resynced group keys!|r")
    end
    pcall(PlaySound, SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or 856)
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
                    key = KR:FindPartyMemberKey(unit, name),
                    isSelf = false,
                })
            end
        end
    end

    KR.currentMembers = members

    if KR.OnGroupUpdated then
        pcall(KR.OnGroupUpdated, KR)
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
            KeyRouletteDB.groupKeys = KeyRouletteDB.groupKeys or {}

            RegisterAddonPrefixes()
            RegisterLibraryCallbacks()
            KR:ScanPlayerKeystone()
            KR:UpdateGroupRoster()
        end

    elseif event == "PLAYER_ENTERING_WORLD" then
        RegisterAddonPrefixes()
        RegisterLibraryCallbacks()
        KR:BroadcastKeystone()
        KR:UpdateGroupRoster()
        if DEFAULT_CHAT_FRAME then
            DEFAULT_CHAT_FRAME:AddMessage("|cff00ffcc[Key Roulette]|r Addon Loaded! Type |cffffd700/kr|r or |cffffd700/keyroulette|r to open.")
        end

    elseif event == "GROUP_ROSTER_UPDATE" then
        KR:BroadcastKeystone()
        KR:RequestGroupKeystones()
        KR:UpdateGroupRoster()

    elseif event == "BAG_UPDATE_DELAYED" then
        KR:ScanPlayerKeystone()
        KR:BroadcastKeystone()
        KR:UpdateGroupRoster()

    elseif event:sub(1, 8) == "CHAT_MSG" and event ~= "CHAT_MSG_ADDON" then
        -- Party Chat Keystone Link Auto-Parser!
        local text, sender = ...
        if text and text:find("keystone:") then
            local senderName = (Ambiguate and Ambiguate(sender, "none")) or sender:match("([^-]+)") or sender
            local mapID, level = text:match("keystone:%d+:(%d+):(%d+)")
            if mapID and level then
                mapID = tonumber(mapID)
                level = tonumber(level)
                KR:SaveMemberKey(senderName, mapID, level, "Chat Link")
                KR:UpdateGroupRoster()
            end
        end

    elseif event == "CHAT_MSG_ADDON" then
        local prefix, message, channel, sender = ...
        local senderName = (Ambiguate and Ambiguate(sender, "none")) or sender:match("([^-]+)") or sender

        if prefix == "KeyRoulette" then
            if message == "PING" then
                KR:BroadcastKeystone()
            elseif message:sub(1, 4) == "KEY:" then
                local mapID, level = message:match("KEY:(%d+):(%d+)")
                if mapID and level then
                    KR:SaveMemberKey(senderName, tonumber(mapID), tonumber(level), "Synced")
                    KR:UpdateGroupRoster()
                end
            end

        elseif prefix == "EllesmereUI" or prefix == "Ellesmere" or prefix == "LibOpenKeystone" or prefix == "LibOpenKeystone-1.0" then
            if message == "REQUEST" or message == "REQ" or message == "PING" then
                KR:BroadcastKeystone()
            else
                local mID, lvl = message:match("KEY:(%d+):(%d+)")
                              or message:match("KEY,(%d+),(%d+)")
                              or message:match("(%d+):(%d+)")
                              or message:match("(%d+),(%d+)")
                if mID and lvl then
                    KR:SaveMemberKey(senderName, tonumber(mID), tonumber(lvl), "EllesmereUI")
                    KR:UpdateGroupRoster()
                end
            end

        elseif prefix == "LibTomoKeystoneSync" or prefix == "LibTomoKeystoneSync-1.0" or prefix == "TomoKeystoneSync" or prefix == "TomoKeys" or prefix == "LTKS" then
            if message == "REQUEST" or message == "REQ" or message == "PING" or message == "QUERY" then
                KR:BroadcastKeystone()
            else
                local mID, lvl = message:match("KEY:(%d+):(%d+)")
                              or message:match("KEY,(%d+),(%d+)")
                              or message:match("(%d+):(%d+)")
                              or message:match("(%d+),(%d+)")
                              or message:match("(%d+)#(%d+)")
                if mID and lvl then
                    KR:SaveMemberKey(senderName, tonumber(mID), tonumber(lvl), "LibTomoKeystoneSync")
                    KR:UpdateGroupRoster()
                end
            end

        elseif prefix == "LibKeystone" or prefix == "LibKeystone-1.0" or prefix == "LKS" or prefix == "LKS1" or prefix == "LibDungeonKeys-1.0" then
            if message == "REQUEST" or message == "REQ" or message == "PING" then
                KR:BroadcastKeystone()
            else
                local mID, lvl = message:match("KEY:(%d+):(%d+)")
                              or message:match("(%d+):(%d+)")
                              or message:match("(%d+)#(%d+)")
                              or message:match("UPDATE:(%d+):(%d+)")
                if mID and lvl then
                    KR:SaveMemberKey(senderName, tonumber(mID), tonumber(lvl), "LibKeystone")
                    KR:UpdateGroupRoster()
                end
            end

        elseif prefix == "LibOpenRaid" or prefix == "LibOpenRaid-1.0" or prefix == "LOR" or prefix == "LOR1" or prefix == "OpenRaid" then
            if message == "REQUEST_KEY" or message == "REQ_KEY" or message == "QUERY" or message == "PING" then
                KR:BroadcastKeystone()
            else
                local mID, lvl = message:match("KEY,(%d+),(%d+)")
                              or message:match("MKEY,(%d+),(%d+)")
                              or message:match("(%d+),(%d+)")
                              or message:match("KEY:(%d+):(%d+)")
                              or message:match("(%d+):(%d+)")
                if mID and lvl then
                    KR:SaveMemberKey(senderName, tonumber(mID), tonumber(lvl), "LibOpenRaid")
                    KR:UpdateGroupRoster()
                end
            end

        elseif prefix == "AstralKeys" or prefix == "Details" or prefix == "MythicKeystones" or prefix == "RaiderIO" then
            if message and (message:find("(%d+):(%d+)") or message:find("(%d+),(%d+)")) then
                local mID, lvl = message:match("(%d+):(%d+)") or message:match("(%d+),(%d+)")
                if mID and lvl then
                    KR:SaveMemberKey(senderName, tonumber(mID), tonumber(lvl), "Addon Sync")
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
    elseif msg == "resync" or msg == "sync" then
        if KR.ResyncAllKeys then
            KR:ResyncAllKeys()
        end
    elseif msg == "debug" then
        if KR.RunDebug then
            KR:RunDebug()
        end
    else
        local ok, err = pcall(function() KR:ToggleUI() end)
        if not ok then
            DEFAULT_CHAT_FRAME:AddMessage("|cffff4444[Key Roulette Error]|r " .. tostring(err))
        end
    end
end
