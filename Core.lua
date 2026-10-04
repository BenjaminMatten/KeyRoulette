-- Key Roulette Core Logic
local addonName, KR = ...

-- Global Table
_G["KeyRoulette"] = KR

KeyRouletteDB = KeyRouletteDB or {
    announceChannel = "PARTY",
    autoAnnounce = true,
    showMinimap = true,
    customFormat = "[Key Roulette] picked: %s's +%d %s!",
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
SafeRegisterEvent("GUILD_ROSTER_UPDATE")
SafeRegisterEvent("BAG_UPDATE_DELAYED")
SafeRegisterEvent("PLAYER_REGEN_DISABLED")
SafeRegisterEvent("PLAYER_REGEN_ENABLED")
SafeRegisterEvent("CHAT_MSG_ADDON")
SafeRegisterEvent("CHAT_MSG_PARTY")
SafeRegisterEvent("CHAT_MSG_PARTY_LEADER")
SafeRegisterEvent("CHAT_MSG_RAID")
SafeRegisterEvent("CHAT_MSG_RAID_LEADER")
SafeRegisterEvent("CHAT_MSG_GUILD")
SafeRegisterEvent("CHAT_MSG_OFFICER")
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
            lor:RegisterCallback("KeystoneUpdate", function() KR:ScheduleRosterUpdate(0.2) end)
        end)
    end

    local tomo = (LibStub and (LibStub("LibTomoKeystoneSync-1.0", true) or LibStub("LibTomoKeystoneSync", true)))
              or _G.LibTomoKeystoneSync or _G.TomoKeystoneSync
    if tomo and tomo.RegisterCallback then
        pcall(function()
            tomo:RegisterCallback("KeystoneUpdate", function() KR:ScheduleRosterUpdate(0.2) end)
        end)
    end

    local lok = (LibStub and (LibStub("LibOpenKeystone-1.0", true) or LibStub("LibOpenKeystone", true))) or _G.LibOpenKeystone
    if lok and lok.RegisterCallback then
        pcall(function()
            lok:RegisterCallback("KeystoneUpdate", function() KR:ScheduleRosterUpdate(0.2) end)
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

-- Dynamic Season Dungeon Map Lookup & Cache
KR.seasonDungeonsByName = KR.seasonDungeonsByName or {}
KR.seasonDungeonsByID = KR.seasonDungeonsByID or {}

function KR:UpdateSeasonDungeons()
    if not C_ChallengeMode or not C_ChallengeMode.GetMapTable then return end
    local mapIDs = C_ChallengeMode.GetMapTable()
    if not mapIDs then return end

    for _, mID in ipairs(mapIDs) do
        local name, id, timeLimit, texture = C_ChallengeMode.GetMapUIInfo(mID)
        if name and name ~= "" then
            local info = { mapID = mID, name = name, icon = texture or 5254320 }
            KR.seasonDungeonsByID[mID] = info
            KR.seasonDungeonsByName[name:lower()] = info
            local clean = name:gsub("^The%s+", ""):lower()
            KR.seasonDungeonsByName[clean] = info
        end
    end
end

function KR:GetDungeonInfo(mapID, dungeonName)
    KR:UpdateSeasonDungeons()

    -- 1. Try lookup by mapID if valid positive number
    if type(mapID) == "number" and mapID > 0 then
        if KR.seasonDungeonsByID[mapID] then
            return KR.seasonDungeonsByID[mapID]
        end
        if C_ChallengeMode and C_ChallengeMode.GetMapUIInfo then
            local name, id, timeLimit, texture = C_ChallengeMode.GetMapUIInfo(mapID)
            if name and name ~= "" then
                local info = { mapID = mapID, name = name, icon = texture or 5254320 }
                KR.seasonDungeonsByID[mapID] = info
                return info
            end
        end
        if C_Map and C_Map.GetMapInfo then
            local mapInfo = C_Map.GetMapInfo(mapID)
            if mapInfo and mapInfo.name and mapInfo.name ~= "" then
                local info = { mapID = mapID, name = mapInfo.name, icon = 5254320 }
                return info
            end
        end
        if GetRealZoneText then
            local zName = GetRealZoneText(mapID)
            if zName and zName ~= "" then
                local info = { mapID = mapID, name = zName, icon = 5254320 }
                return info
            end
        end
    end

    -- 2. Try lookup by dungeonName text string
    if type(dungeonName) == "string" and dungeonName ~= "" then
        local key = dungeonName:gsub("^%s*(.-)%s*$", "%1"):lower()
        if KR.seasonDungeonsByName[key] then
            return KR.seasonDungeonsByName[key]
        end
        for sName, info in pairs(KR.seasonDungeonsByName) do
            if sName:find(key, 1, true) or key:find(sName, 1, true) then
                return info
            end
        end
        local cleanKey = key:gsub("^the%s+", "")
        if KR.seasonDungeonsByName[cleanKey] then
            return KR.seasonDungeonsByName[cleanKey]
        end
        for sName, info in pairs(KR.seasonDungeonsByName) do
            if sName:find(cleanKey, 1, true) or cleanKey:find(sName, 1, true) then
                return info
            end
        end
        return { mapID = mapID or 0, name = dungeonName, icon = 5254320 }
    end

    if type(mapID) == "number" and mapID > 0 then
        return { mapID = mapID, name = "Map " .. mapID, icon = 5254320 }
    end

    return { mapID = 0, name = "Unknown Key", icon = 5254320 }
end

-- Save Member Key with Name Normalization & SavedVariables Persistence
function KR:SaveMemberKey(rawName, mapID, level, source, customDungeonName)
    if not rawName or not level or level <= 0 then return end
    local shortName = rawName:match("([^-]+)") or rawName
    local realm = GetNormalizedRealmName() or GetRealmName() or ""
    local fullName = rawName:find("-") and rawName or (shortName .. "-" .. realm)

    -- Dynamic season resolution: resolve dungeon info from mapID OR customDungeonName
    local dungeon = KR:GetDungeonInfo(mapID, customDungeonName)
    local resolvedMapID = (dungeon and dungeon.mapID and dungeon.mapID > 0) and dungeon.mapID or (type(mapID) == "number" and mapID > 0 and mapID or 0)
    local dName = (customDungeonName and customDungeonName ~= "") and customDungeonName or (dungeon and dungeon.name) or (resolvedMapID > 0 and ("Map " .. resolvedMapID) or "Unknown Key")

    local keyData = {
        mapID = resolvedMapID,
        level = level,
        dungeonName = dName,
        icon = (dungeon and dungeon.icon) or 5254320,
        source = source or "Synced",
        timestamp = time()
    }

    -- Memory cache
    KR.groupMembers[rawName] = keyData
    KR.groupMembers[shortName] = keyData
    KR.groupMembers[fullName] = keyData
    KR.groupMembers[rawName:lower()] = keyData
    KR.groupMembers[shortName:lower()] = keyData

    -- Embedded Library Sync Caches
    pcall(function()
        local lks = LibStub and LibStub("LibKeystone-1.0", true)
        if lks and lks.keystones then
            lks.keystones[rawName] = keyData
            lks.keystones[shortName] = keyData
            lks.keystones[fullName] = keyData
        end
        local lok = LibStub and LibStub("LibOpenKeystone-1.0", true)
        if lok and lok.keystones then
            lok.keystones[rawName] = keyData
            lok.keystones[shortName] = keyData
            lok.keystones[fullName] = keyData
        end
        local lor = LibStub and LibStub("LibOpenRaid-1.0", true)
        if lor and lor.keystones then
            lor.keystones[rawName] = keyData
            lor.keystones[shortName] = keyData
            lor.keystones[fullName] = keyData
        end
    end)

    -- Persistent SavedVariables cache
    KeyRouletteDB = KeyRouletteDB or {}
    KeyRouletteDB.groupKeys = KeyRouletteDB.groupKeys or {}
    KeyRouletteDB.groupKeys[rawName] = keyData
    KeyRouletteDB.groupKeys[shortName] = keyData
    KeyRouletteDB.groupKeys[fullName] = keyData
end

-- Universal MapID and Level Extractor (Handles tables, multi-returns, string pairs, and prevents level/map swaps)
local function ExtractMapAndLevel(res1, res2)
    local mID, lvl, dName

    -- Direct (number, number) call
    if type(res1) == "number" and type(res2) == "number" then
        if res1 > 50 and res2 <= 50 then
            mID, lvl = res1, res2
        elseif res2 > 50 and res1 <= 50 then
            mID, lvl = res2, res1
        else
            mID, lvl = res1, res2
        end
    end

    -- Table res1
    if type(res1) == "table" then
        local sub = res1.key or res1.keystone or res1.keyData or res1.info or res1
        if type(sub) == "table" then
            local rawMap = sub.mapID or sub.mapId or sub.challengeMapID or sub.challengeMapId or sub.dungeonID or sub.dungeonId or sub.dungeon_id or sub.map_id or sub.keyID or sub.keyId or sub.map or sub.keystoneMapID or sub.keystoneMapId or sub.mID or sub.mId or sub.zoneID or sub.zoneId or sub[1]
            local rawLvl = sub.level or sub.keyLevel or sub.key_level or sub.levelNumber or sub.keystoneLevel or sub.keyLvl or sub.lvl or sub.levelNum or sub[2]
            if type(rawLvl) == "number" then lvl = rawLvl end
            if type(rawMap) == "number" then mID = rawMap end
            if not dName then dName = sub.dungeonName or sub.dungeon_name or sub.dungeon or sub.name or sub.zone or sub.mapName or sub.map_name or sub.title end
        end

        if not lvl and type(res1.level) == "number" then lvl = res1.level end
        if not lvl and type(res1.keyLevel) == "number" then lvl = res1.keyLevel end
        if not lvl and type(res1.key_level) == "number" then lvl = res1.key_level end
        if not lvl and type(res1.key) == "number" then lvl = res1.key end

        if not mID and type(res1.mapID) == "number" then mID = res1.mapID end
        if not mID and type(res1.mapId) == "number" then mID = res1.mapId end
        if not mID and type(res1.map) == "number" then mID = res1.map end
        if not mID and type(res1.dungeonID) == "number" then mID = res1.dungeonID end
        if not mID and type(res1.dungeonId) == "number" then mID = res1.dungeonId end
        if not mID and type(res1.challengeMapID) == "number" then mID = res1.challengeMapID end

        if not dName then dName = res1.dungeonName or res1.dungeon_name or res1.dungeon or res1.name or res1.zone or res1.mapName or res1.map_name or res1.title end
    end

    -- String res1
    if not lvl and type(res1) == "string" then
        -- Pattern 1: keystone item string (keystone:180653:507:9)
        local kMap, kLvl = res1:match("keystone:%d+:(%d+):(%d+)")
        if kMap and kLvl then
            mID, lvl = tonumber(kMap), tonumber(kLvl)
        end

        -- Pattern 2: KEY:507:9 or KEY:9:507 or 507:9 or 9:507 or KEY:9:Altar of Fangs
        if not lvl then
            local n1, n2 = res1:match("(%d+)[:#,%s]+(%d+)")
            if n1 and n2 then
                n1, n2 = tonumber(n1), tonumber(n2)
                if n1 > 50 and n2 <= 50 then
                    mID, lvl = n1, n2
                elseif n2 > 50 and n1 <= 50 then
                    mID, lvl = n2, n1
                else
                    mID, lvl = n1, n2
                end
            end
        end

        -- Pattern 3: +9 Altar of Fangs or Altar of Fangs +9 or +9
        if not lvl then
            local lStr, dStr = res1:match("%+(%d+)%s*(.*)")
            if not lStr then dStr, lStr = res1:match("(.-)%s*%+(%d+)") end
            if lStr then
                lvl = tonumber(lStr)
                if dStr and dStr ~= "" then dName = dStr:gsub("^%s*(.-)%s*$", "%1") end
            end
        end
    end

    if lvl and lvl > 0 then
        return mID or 0, lvl, dName
    end
    return nil, nil, nil
end

-- Helper Table Matcher for Addon DBs (EllesmereUI, KeystoneLoot, Details, etc.)
local function CheckTableForMemberKey(tbl, searchNames)
    if not tbl or type(tbl) ~= "table" then return nil, nil, nil end

    -- 1. Direct member indexing: tbl["Izani"]
    for _, sName in ipairs(searchNames) do
        if sName then
            local entry = tbl[sName] or tbl[sName:lower()]
            if entry then
                local mID, lvl, dName = ExtractMapAndLevel(entry)
                if lvl and lvl > 0 then return mID, lvl, dName end
            end
        end
    end

    -- 2. Known sub-tables (keystones, keys, keystonePopup, partyKeys, groupKeys, party, profiles)
    local subTables = { tbl.keystones, tbl.keys, tbl.keystonePopup, tbl.partyKeys, tbl.groupKeys, tbl.party, tbl.profiles }
    for _, sub in ipairs(subTables) do
        if type(sub) == "table" then
            for _, sName in ipairs(searchNames) do
                if sName then
                    local entry = sub[sName] or sub[sName:lower()]
                    if entry then
                        local mID, lvl, dName = ExtractMapAndLevel(entry)
                        if lvl and lvl > 0 then return mID, lvl, dName end
                    end
                end
            end
        end
    end

    -- 3. Array / Record iteration: { { name = "Izani", level = 9, mapID = 507 }, ... }
    for k, v in pairs(tbl) do
        if type(v) == "table" then
            local sender = v.name or v.sender or v.player or v.unit or (type(k) == "string" and k)
            if type(sender) == "string" then
                local sShort = sender:match("([^-]+)") or sender
                for _, sName in ipairs(searchNames) do
                    if sName and (sender == sName or sender:lower() == sName:lower() or sShort == sName or sShort:lower() == sName:lower()) then
                        local mID, lvl, dName = ExtractMapAndLevel(v)
                        if lvl and lvl > 0 then return mID, lvl, dName end
                    end
                end
            end
        end
    end

    return nil, nil, nil
end

-- Deep Global Table Recursive Searcher (Finds keystone mapID + level for player name in any table)
local function DeepSearchTable(tbl, searchNames, depth)
    if not tbl or type(tbl) ~= "table" or (depth and depth > 5) then return nil, nil, nil end
    depth = (depth or 0) + 1

    for key, val in pairs(tbl) do
        if type(key) == "string" then
            for _, sName in ipairs(searchNames) do
                if sName and sName ~= "" and (key == sName or key:lower() == sName:lower() or key:find(sName, 1, true)) then
                    local mID, lvl, dName = ExtractMapAndLevel(val)
                    if lvl and lvl > 0 then return mID, lvl, dName end
                end
            end
        end

        if type(val) == "table" and key ~= "_G" and key ~= "KR" and key ~= "KeyRoulette" and key ~= "UIParent" and key ~= "WorldFrame" then
            local mID, lvl, dName = DeepSearchTable(val, searchNames, depth)
            if lvl and lvl > 0 then return mID, lvl, dName end
        end
    end
    return nil, nil, nil
end

-- UI Frame Node Scanner (Extracts key info from EllesmereUI & standard UI text elements)
local function ScanFrameForMemberKey(parentFrame, searchNames)
    if not parentFrame then return nil, nil, nil end

    local function SearchFrameNode(f, depth)
        if not f or depth > 6 then return nil, nil, nil end

        local hasMemberName = false
        local foundMapID, foundLevel, foundDungeonName

        local fontStrings = {}
        if f.GetRegions then
            local regions = { f:GetRegions() }
            for _, reg in ipairs(regions) do
                if reg and reg.GetObjectType and reg:GetObjectType() == "FontString" then
                    local text = reg:GetText()
                    if text and type(text) == "string" and text ~= "" then
                        table.insert(fontStrings, text)
                    end
                end
            end
        end

        for _, text in ipairs(fontStrings) do
            for _, sName in ipairs(searchNames) do
                if sName and sName ~= "" then
                    local sClean = sName:match("([^-]+)") or sName
                    if text:find(sName, 1, true) or text:lower():find(sName:lower(), 1, true)
                       or text:find(sClean, 1, true) or text:lower():find(sClean:lower(), 1, true) then
                        hasMemberName = true
                    end
                end
            end

            local mID, lvl, dName = ExtractMapAndLevel(text)
            if lvl and lvl > 0 then
                foundLevel = lvl
                if mID and mID > 0 then foundMapID = mID end
                if dName and dName ~= "" then foundDungeonName = dName end
            end
        end

        if foundLevel and not foundDungeonName then
            for _, text in ipairs(fontStrings) do
                local dInfo = KR:GetDungeonInfo(nil, text)
                if dInfo and dInfo.name and dInfo.name ~= "Unknown Key" then
                    foundDungeonName = dInfo.name
                    if dInfo.mapID and dInfo.mapID > 0 then
                        foundMapID = dInfo.mapID
                    end
                    break
                end
            end
        end

        if hasMemberName and foundLevel and (foundDungeonName or (foundMapID and foundMapID > 0)) then
            return foundMapID or 0, foundLevel, foundDungeonName
        end

        if f.GetChildren then
            local children = { f:GetChildren() }
            for _, child in ipairs(children) do
                local mID, lvl, dName = SearchFrameNode(child, depth + 1)
                if mID and lvl then return mID, lvl, dName end
            end
        end

        if hasMemberName and foundLevel then
            return foundMapID or 0, foundLevel, foundDungeonName
        end

        return nil, nil, nil
    end

    return SearchFrameNode(parentFrame, 0)
end

-- Purge Stale RaiderIO Entries from SavedVariables and Cache
function KR:PurgeRaiderIOData()
    if KR.groupMembers then
        for k, v in pairs(KR.groupMembers) do
            if v and v.source == "RaiderIO" then
                KR.groupMembers[k] = nil
            end
        end
    end
    if KeyRouletteDB and KeyRouletteDB.groupKeys then
        for k, v in pairs(KeyRouletteDB.groupKeys) do
            if v and v.source == "RaiderIO" then
                KeyRouletteDB.groupKeys[k] = nil
            end
        end
    end
end

-- Comprehensive Keystone Lookup Engine (Live Addon Sync First)
function KR:FindPartyMemberKey(unit, name, allowDeepSearch)
    if not name and unit and UnitExists(unit) then
        name = GetUnitName(unit, true) or UnitName(unit)
    end
    if not name then return nil end

    local uName, uRealm = (unit and UnitExists(unit)) and UnitName(unit) or nil
    local shortName = name:match("([^-]+)") or uName or name
    local realm = (uRealm and uRealm ~= "") and uRealm or (GetNormalizedRealmName() or GetRealmName() or "")
    local fullName = name:find("-") and name or (shortName .. "-" .. realm)
    local guid = (unit and UnitExists(unit)) and UnitGUID(unit) or nil

    local searchNames = { fullName, shortName, name, guid }
    if uName and uRealm and uRealm ~= "" then
        table.insert(searchNames, uName .. "-" .. uRealm)
    end

    -- Purge any legacy RaiderIO caches
    KR:PurgeRaiderIOData()

    -- 1. Check manual user override (Edit button in UI)
    if KR.manualKeys[name] then return KR.manualKeys[name] end
    if KR.manualKeys[shortName] then return KR.manualKeys[shortName] end
    if KR.manualKeys[fullName] then return KR.manualKeys[fullName] end

    -- 2. Check EllesmereUI / EUIKeysPopup / EllesmereUIDB / EUIKeys / EUI
    pcall(function()
        local mID, lvl, dName
        -- A. Check UI frame text elements first (EllesmereUI key popup windows)
        local euiFrames = { _G.EUIKeysPopup, _G.EUIKeys, _G.EUI_Keys, _G.EllesmereUIFrame }
        for _, frame in ipairs(euiFrames) do
            if not mID and frame then
                mID, lvl, dName = ScanFrameForMemberKey(frame, searchNames)
            end
        end

        -- B. Check EllesmereUI tables
        local euiTables = { _G.EllesmereUIDB, _G.EllesmereUI, _G.EUIKeysPopup, _G.EUIKeys, _G.EUI_Keys, _G.EUI }
        for _, euiTbl in ipairs(euiTables) do
            if not mID and euiTbl and type(euiTbl) == "table" then
                mID, lvl, dName = CheckTableForMemberKey(euiTbl, searchNames)
                if not mID then
                    mID, lvl, dName = DeepSearchTable(euiTbl, searchNames, 0)
                end
            end
        end

        if lvl and lvl > 0 then
            KR:SaveMemberKey(name, mID, lvl, "EllesmereUI", dName)
        end
    end)
    local euiKey = KR.groupMembers[name] or KR.groupMembers[shortName] or KR.groupMembers[fullName]
    if euiKey and euiKey.source == "EllesmereUI" and euiKey.dungeonName and euiKey.dungeonName ~= "Unknown Key" then
        return euiKey
    end

    -- 3. Check LibOpenRaid
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
            end
            if not r1 and lor.keystones then
                r1 = lor.keystones[unit] or (guid and lor.keystones[guid]) or lor.keystones[shortName] or lor.keystones[fullName]
            end
            if not r1 and lor.KeystoneInfo then
                r1 = lor.KeystoneInfo[unit] or (guid and lor.KeystoneInfo[guid]) or lor.KeystoneInfo[shortName] or lor.KeystoneInfo[fullName]
            end
            if not r1 and lor.allyData then
                local ally = lor.allyData[unit] or (guid and lor.allyData[guid]) or lor.allyData[shortName] or lor.allyData[fullName]
                if ally then r1 = ally.keystone or ally.keystoneInfo or ally end
            end

            local mID, lvl, dName = ExtractMapAndLevel(r1, r2)
            if lvl and lvl > 0 then
                KR:SaveMemberKey(name, mID, lvl, "LibOpenRaid", dName)
            end
        end)
        local lorKey = KR.groupMembers[name] or KR.groupMembers[shortName] or KR.groupMembers[fullName]
        if lorKey and lorKey.source == "LibOpenRaid" and lorKey.dungeonName and lorKey.dungeonName ~= "Unknown Key" then
            return lorKey
        end
    end

    -- 4. Check KeystoneLoot
    if _G.KeystoneLootDB or _G.KeystoneLootAPI or _G.KeystoneLootCharDB then
        pcall(function()
            local kl = _G.KeystoneLootCharDB or _G.KeystoneLootDB or _G.KeystoneLootAPI
            local mID, lvl, dName = CheckTableForMemberKey(kl, searchNames)
            if lvl and lvl > 0 then
                KR:SaveMemberKey(name, mID, lvl, "KeystoneLoot", dName)
            end
        end)
        local klKey = KR.groupMembers[name] or KR.groupMembers[shortName] or KR.groupMembers[fullName]
        if klKey and klKey.source == "KeystoneLoot" and klKey.dungeonName and klKey.dungeonName ~= "Unknown Key" then
            return klKey
        end
    end

    -- 5. Check LibTomoKeystoneSync
    local tomo = (LibStub and (LibStub("LibTomoKeystoneSync-1.0", true) or LibStub("LibTomoKeystoneSync", true)))
              or _G.LibTomoKeystoneSync or _G.TomoKeystoneSync or _G.TomoKeys
    if tomo then
        pcall(function()
            local r1, r2
            if tomo.GetKeystone then r1, r2 = tomo:GetKeystone(unit) end
            if not r1 and tomo.GetKeystoneInfo then r1, r2 = tomo:GetKeystoneInfo(unit) end
            if not r1 and tomo.keys then r1 = tomo.keys[fullName] or tomo.keys[shortName] or tomo.keys[unit] end
            if not r1 and tomo.keystones then r1 = tomo.keystones[fullName] or tomo.keystones[shortName] or tomo.keystones[unit] end

            local mID, lvl, dName = ExtractMapAndLevel(r1, r2)
            if lvl and lvl > 0 then
                KR:SaveMemberKey(name, mID, lvl, "LibTomoKeystoneSync", dName)
            end
        end)
        local tomoKey = KR.groupMembers[name] or KR.groupMembers[shortName] or KR.groupMembers[fullName]
        if tomoKey and tomoKey.source == "LibTomoKeystoneSync" and tomoKey.dungeonName and tomoKey.dungeonName ~= "Unknown Key" then
            return tomoKey
        end
    end

    -- 6. Check LibOpenKeystone
    local lok = (LibStub and (LibStub("LibOpenKeystone-1.0", true) or LibStub("LibOpenKeystone", true))) or _G.LibOpenKeystone
    if lok then
        pcall(function()
            local r1, r2
            if lok.GetKeystone then r1, r2 = lok:GetKeystone(unit) end
            if not r1 and lok.keystones then r1 = lok.keystones[fullName] or lok.keystones[shortName] end

            local mID, lvl, dName = ExtractMapAndLevel(r1, r2)
            if lvl and lvl > 0 then
                KR:SaveMemberKey(name, mID, lvl, "LibOpenKeystone", dName)
            end
        end)
        local lokKey = KR.groupMembers[name] or KR.groupMembers[shortName] or KR.groupMembers[fullName]
        if lokKey and lokKey.source == "LibOpenKeystone" and lokKey.dungeonName and lokKey.dungeonName ~= "Unknown Key" then
            return lokKey
        end
    end

    -- 7. Check Details & AstralKeys
    if _G.Details and _G.Details.Keystones then
        pcall(function()
            local dKey = _G.Details.Keystones[fullName] or _G.Details.Keystones[shortName] or _G.Details.Keystones[name]
            local mID, lvl, dName = ExtractMapAndLevel(dKey)
            if lvl and lvl > 0 then
                KR:SaveMemberKey(name, mID, lvl, "Details", dName)
            end
        end)
        local detKey = KR.groupMembers[name] or KR.groupMembers[shortName] or KR.groupMembers[fullName]
        if detKey and detKey.source == "Details" and detKey.dungeonName and detKey.dungeonName ~= "Unknown Key" then
            return detKey
        end
    end

    if _G.AstralKeys then
        pcall(function()
            local aKey
            if _G.AstralKeys.GetKey then aKey = _G.AstralKeys:GetKey(shortName) or _G.AstralKeys:GetKey(fullName) end
            if not aKey and type(_G.AstralKeys) == "table" then aKey = _G.AstralKeys[shortName] or _G.AstralKeys[fullName] end

            local mID, lvl, dName = ExtractMapAndLevel(aKey)
            if lvl and lvl > 0 then
                KR:SaveMemberKey(name, mID, lvl, "AstralKeys", dName)
            end
        end)
        local akKey = KR.groupMembers[name] or KR.groupMembers[shortName] or KR.groupMembers[fullName]
        if akKey and akKey.source == "AstralKeys" and akKey.dungeonName and akKey.dungeonName ~= "Unknown Key" then
            return akKey
        end
    end

    -- 8. Tooltip Unit Scanner (For Standard UI players without sync addons)
    if C_TooltipInfo and C_TooltipInfo.GetUnit then
        pcall(function()
            local data = C_TooltipInfo.GetUnit(unit)
            if data and data.lines then
                for _, line in ipairs(data.lines) do
                    if line.leftText then
                        local mID, lvl = ExtractMapAndLevel(line.leftText)
                        if mID and lvl then
                            KR:SaveMemberKey(name, mID, lvl, "Tooltip")
                        else
                            local lvlText, dName = line.leftText:match("%+(%d+)%s+([^%]+)]?")
                            if not lvlText then dName, lvlText = line.leftText:match("([^%+%[b]+)%s*%+(%d+)") end
                            if lvlText and dName then
                                local l = tonumber(lvlText)
                                if l and l > 0 then
                                    KR:SaveMemberKey(name, 0, l, "Tooltip", dName:gsub("^%s*(.-)%s*$", "%1"))
                                end
                            end
                        end
                    end
                end
            end
        end)
        if KR.groupMembers[name] and KR.groupMembers[name].source == "Tooltip" then
            return KR.groupMembers[name]
        end
    end

    -- 9. Check in-memory sync cache (non-RaiderIO)
    local cached = KR.groupMembers[name] or KR.groupMembers[shortName] or KR.groupMembers[fullName]
                or KR.groupMembers[name:lower()] or KR.groupMembers[shortName:lower()]
    if cached and cached.source ~= "RaiderIO" then
        return cached
    end

    -- 10. Check persistent SavedVariables DB cache (non-RaiderIO)
    if KeyRouletteDB and KeyRouletteDB.groupKeys then
        local saved = KeyRouletteDB.groupKeys[name] or KeyRouletteDB.groupKeys[shortName] or KeyRouletteDB.groupKeys[fullName]
        if saved and saved.source ~= "RaiderIO" then
            KR.groupMembers[name] = saved
            return saved
        end
    end

    -- 11. Deep Global Recursive Searcher (Only run when explicitly resyncing or UI is active)
    if allowDeepSearch or (KR.UIFrame and KR.UIFrame:IsShown()) then
        pcall(function()
            for gName, gVal in pairs(_G) do
                if type(gName) == "string" and (gName:find("Ellesmere") or gName:find("EUI") or gName:find("Tomo") or gName:find("Keystone") or gName:find("Key")) and type(gVal) == "table" and gName ~= "RaiderIO" and gName ~= "_G" and gName ~= "KR" and gName ~= "KeyRoulette" and gName ~= "UIParent" and gName ~= "WorldFrame" then
                    local mID, lvl, dName = CheckTableForMemberKey(gVal, searchNames)
                    if not mID then
                        mID, lvl, dName = DeepSearchTable(gVal, searchNames, 0)
                    end
                    if mID and lvl then
                        KR:SaveMemberKey(name, mID, lvl, gName, dName)
                        break
                    end
                end
            end
        end)
    end

    local finalKey = KR.groupMembers[name] or KR.groupMembers[shortName]
    if finalKey and finalKey.source == "RaiderIO" then
        return nil
    end
    return finalKey
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
    AddLog("Globals Found: " .. table.concat(foundGlobals, ", "))

    -- Dump EllesmereUIDB safely
    if _G.EllesmereUIDB and type(_G.EllesmereUIDB) == "table" then
        AddLog("=== EllesmereUIDB Table Dump ===")
        pcall(function()
            for k, v in pairs(_G.EllesmereUIDB) do
                AddLog("  EllesmereUIDB." .. tostring(k) .. " = " .. tostring(v))
                if type(v) == "table" then
                    for k2, v2 in pairs(v) do
                        AddLog("    [" .. tostring(k2) .. "] = " .. tostring(v2))
                    end
                end
            end
        end)
    end

    -- Deep Member Inspection Trace
    if IsInGroup() then
        local num = GetNumGroupMembers()
        local prefix = IsInRaid() and "raid" or "party"
        for i = 1, (IsInRaid() and num or (num - 1)) do
            local unit = prefix .. i
            if UnitExists(unit) and not UnitIsUnit(unit, "player") then
                local uName, uRealm = UnitName(unit)
                local fullName = GetUnitName(unit, true) or (uRealm and uRealm ~= "" and (uName .. "-" .. uRealm)) or uName or "Unknown"
                local guid = UnitGUID(unit)
                AddLog("--- Party Member " .. i .. ": " .. tostring(fullName) .. " (GUID: " .. tostring(guid) .. ") ---")

                -- LibOpenRaid check
                local lor = (LibStub and LibStub("LibOpenRaid-1.0", true)) or _G.LibOpenRaid
                if lor then
                    pcall(function()
                        if lor.GetKeystoneInfo then
                            local m, l = lor:GetKeystoneInfo(unit)
                            if not m and guid then m, l = lor:GetKeystoneInfo(guid) end
                            if m and l then AddLog("  [LibOpenRaid:GetKeystoneInfo]: +" .. tostring(l) .. " (Map " .. tostring(m) .. ")") end
                        end
                    end)
                end

                -- Key Lookup Check
                local key = KR:FindPartyMemberKey(unit, fullName, true)
                AddLog("  Key Detection Result: " .. (key and ("+" .. key.level .. " " .. key.dungeonName .. " [" .. key.source .. "]") or "No Key Detected"))
            end
        end
    else
        AddLog("Not in group (Solo).")
    end
    AddLog("|cff00ffcc===========================|r")

    local reportText = table.concat(logLines, "\n")

    -- Save to SavedVariables for persistence
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
    if InCombatLockdown() or KR.inCombat then
        return KR.playerKey
    end
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

-- Scan Guild Roster Notes for Keystone Info (Rate-limited to once per 60s to prevent event loops)
local lastGuildScanTime = 0
function KR:ScanGuildRosterKeys()
    if not IsInGuild() then return end
    local now = GetTime()
    if (now - lastGuildScanTime) < 60 then return end
    lastGuildScanTime = now

    pcall(function()
        local numTotal = GetNumGuildMembers() or 0
        for i = 1, numTotal do
            local name, rank, rankIndex, level, class, zone, note, officerNote = GetGuildRosterInfo(i)
            if name then
                local shortName = name:match("([^-]+)") or name
                local combinedNote = (note or "") .. " " .. (officerNote or "")
                if combinedNote and combinedNote ~= "" then
                    local mID, lvl = combinedNote:match("keystone:%d+:(%d+):(%d+)")
                                  or combinedNote:match("(%d+)[:#,%s]+(%d+)")
                    if mID and lvl then
                        mID, lvl = tonumber(mID), tonumber(lvl)
                        if mID and lvl and mID > 0 and lvl > 0 then
                            KR:SaveMemberKey(shortName, mID, lvl, "Guild Note")
                        end
                    else
                        local lvlText, dName = combinedNote:match("%+(%d+)%s+([^%]+)]?")
                        if not lvlText then dName, lvlText = combinedNote:match("([^%+%[b]+)%s*%+(%d+)") end
                        if lvlText and dName then
                            local l = tonumber(lvlText)
                            if l and l > 0 then
                                KR:SaveMemberKey(shortName, 0, l, "Guild Note", dName:gsub("^%s*(.-)%s*$", "%1"))
                            end
                        end
                    end
                end
            end
        end
    end)
end

-- Queue and delay manager to enforce WoW client chat rate limits
local sendQueue = {}
local isProcessingQueue = false

local function ProcessSendQueue()
    if #sendQueue == 0 then
        isProcessingQueue = false
        return
    end

    isProcessingQueue = true
    local item = table.remove(sendQueue, 1)

    if item then
        local prefix, text, targetChan = item.prefix, item.text, item.targetChan
        if targetChan and ((targetChan == "PARTY" and IsInGroup()) or (targetChan == "RAID" and IsInRaid()) or (targetChan == "GUILD" and IsInGuild())) then
            pcall(C_ChatInfo.SendAddonMessage, prefix, text, targetChan)
        end
    end

    if #sendQueue > 0 then
        C_Timer.After(0.15, ProcessSendQueue)
    else
        isProcessingQueue = false
    end
end

-- Helper function to safely send addon messages with channel verification and queue throttling
local function SafeSendAddonMsg(prefix, text, targetChan)
    if not targetChan then return end
    if (targetChan == "PARTY" or targetChan == "RAID") and not IsInGroup() then return end
    if targetChan == "RAID" and not IsInRaid() then return end
    if targetChan == "GUILD" and not IsInGuild() then return end

    -- Deduplicate identical queued messages
    for _, item in ipairs(sendQueue) do
        if item.prefix == prefix and item.text == text and item.targetChan == targetChan then
            return
        end
    end

    table.insert(sendQueue, { prefix = prefix, text = text, targetChan = targetChan })

    if not isProcessingQueue then
        ProcessSendQueue()
    end
end

-- Check if UI window is currently open
function KR:IsWindowVisible()
    return KR.UIFrame and KR.UIFrame:IsShown()
end

-- Broadcast Self Keystone to Party & Guild (Only when window is open or force requested)
function KR:BroadcastKeystone(force)
    if InCombatLockdown() or KR.inCombat then return end
    if not force and not KR:IsWindowVisible() then return end

    local key = KR:ScanPlayerKeystone()
    if not key then return end

    local channels = {}
    if IsInGroup() then
        table.insert(channels, IsInRaid() and "RAID" or "PARTY")
    end
    if IsInGuild() then
        table.insert(channels, "GUILD")
    end

    if #channels == 0 then return end

    for _, targetChan in ipairs(channels) do
        SafeSendAddonMsg("KeyRoulette", string.format("KEY:%d:%d:%s", key.mapID, key.level, key.dungeonName or ""), targetChan)
        SafeSendAddonMsg("EllesmereUI", string.format("KEY:%d:%d", key.mapID, key.level), targetChan)
        SafeSendAddonMsg("LibOpenRaid", string.format("KEY,%d,%d", key.mapID, key.level), targetChan)
    end
end

-- Request Group & Guild Keystones (Only when window is open or force requested)
function KR:RequestGroupKeystones(force)
    if InCombatLockdown() or KR.inCombat then return end
    if not force and not KR:IsWindowVisible() then return end

    local channels = {}
    if IsInGroup() then
        table.insert(channels, IsInRaid() and "RAID" or "PARTY")
    end
    if IsInGuild() then
        table.insert(channels, "GUILD")
    end

    if #channels > 0 then
        -- Invoke external libraries safely
        pcall(function()
            local eui = _G.EllesmereUI or _G.Ellesmere
            if eui and eui.RequestKeystones then eui:RequestKeystones() end

            local lor = (LibStub and LibStub("LibOpenRaid-1.0", true)) or _G.LibOpenRaid
            if lor and lor.RequestKeystoneInfo then lor:RequestKeystoneInfo() end

            local lok = (LibStub and (LibStub("LibOpenKeystone-1.0", true) or LibStub("LibOpenKeystone", true))) or _G.LibOpenKeystone
            if lok and lok.RequestKeystones then lok:RequestKeystones() end
        end)

        -- Send queued network pings to active channels with 150ms delay spacing
        for _, targetChan in ipairs(channels) do
            SafeSendAddonMsg("KeyRoulette", "PING", targetChan)
            SafeSendAddonMsg("EllesmereUI", "REQUEST", targetChan)
            SafeSendAddonMsg("LibOpenRaid", "REQUEST_KEY", targetChan)
        end
    end
end

-- Ask Party for Keys Chat Prompt (For standard UI players)
function KR:AskPartyForKeys()
    if not IsInGroup() then
        if DEFAULT_CHAT_FRAME then
            DEFAULT_CHAT_FRAME:AddMessage("|cff00ffcc[Key Roulette]|r You are not currently in a party or raid group.")
        end
        return
    end
    local msg = "[Key Roulette]: Please link your Mythic+ keystone in chat!"
    SendChatMessage(msg, IsInRaid() and "RAID" or "PARTY")
    KR:RequestGroupKeystones(true)
end

-- Manual Resync All Keys Action (Triggered by Sync button or /kr resync)
function KR:ResyncAllKeys()
    if InCombatLockdown() or KR.inCombat then
        if DEFAULT_CHAT_FRAME then
            DEFAULT_CHAT_FRAME:AddMessage("|cff00ffcc[Key Roulette]|r Cannot resync keys during combat.")
        end
        return
    end
    KR:ScanPlayerKeystone()
    if IsInGroup() or IsInGuild() then
        KR:RequestGroupKeystones(true)
        KR:BroadcastKeystone(true)
    end
    KR:UpdateGroupRoster(true)

    if KR.UIFrame and KR.UIFrame.banner then
        if IsInGroup() then
            KR.UIFrame.banner.text:SetText("|cff00ffccResynced group keys!|r")
        elseif IsInGuild() then
            KR.UIFrame.banner.text:SetText("|cff00ffccResynced guild keys!|r")
        else
            KR.UIFrame.banner.text:SetText("|cffffaa00Updated solo player key!|r")
        end
    end
    pcall(PlaySound, SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or 856)
end

-- Throttled/Debounced Roster Update Scheduler to Prevent FPS Stutters
local rosterUpdateTimer = nil
function KR:ScheduleRosterUpdate(delay, force)
    if InCombatLockdown() or KR.inCombat then
        KR.pendingRosterUpdate = true
        return
    end
    if not force and not KR:IsWindowVisible() then return end

    delay = delay or 0.25
    if rosterUpdateTimer then return end
    rosterUpdateTimer = C_Timer.NewTimer(delay, function()
        rosterUpdateTimer = nil
        if not InCombatLockdown() and not KR.inCombat and (force or KR:IsWindowVisible()) then
            KR:UpdateGroupRoster(force)
        else
            KR.pendingRosterUpdate = true
        end
    end)
end

-- Update Group Roster Data
function KR:UpdateGroupRoster(allowDeepSearch)
    if InCombatLockdown() or KR.inCombat then
        KR.pendingRosterUpdate = true
        return
    end
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
                    key = KR:FindPartyMemberKey(unit, name, allowDeepSearch),
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
    if event == "PLAYER_REGEN_DISABLED" then
        KR.inCombat = true
        return
    elseif event == "PLAYER_REGEN_ENABLED" then
        KR.inCombat = false
        if KR.pendingRosterUpdate then
            KR.pendingRosterUpdate = false
            C_Timer.After(0.5, function()
                if not InCombatLockdown() and KR:IsWindowVisible() then
                    KR:ScanPlayerKeystone()
                    KR:ScheduleRosterUpdate(0.1, true)
                end
            end)
        end
        return
    end

    -- Strict Combat Protection Guard: Freeze all calculations during fights!
    if InCombatLockdown() or KR.inCombat then
        if event == "GROUP_ROSTER_UPDATE" or event == "BAG_UPDATE_DELAYED" or event == "CHAT_MSG_ADDON" then
            KR.pendingRosterUpdate = true
        end
        return
    end

    if event == "ADDON_LOADED" then
        local loadedAddon = ...
        if loadedAddon == addonName then
            KeyRouletteDB = KeyRouletteDB or {}
            KeyRouletteDB.announceChannel = KeyRouletteDB.announceChannel or "PARTY"
            if KeyRouletteDB.autoAnnounce == nil then KeyRouletteDB.autoAnnounce = true end
            if KeyRouletteDB.showMinimap == nil then KeyRouletteDB.showMinimap = true end
            KeyRouletteDB.customFormat = KeyRouletteDB.customFormat or "[Key Roulette] picked: %s's +%d %s!"
            KeyRouletteDB.groupKeys = KeyRouletteDB.groupKeys or {}

            RegisterAddonPrefixes()
            RegisterLibraryCallbacks()
            KR:ScanPlayerKeystone()
        end

    elseif event == "PLAYER_ENTERING_WORLD" then
        RegisterAddonPrefixes()
        RegisterLibraryCallbacks()
        if DEFAULT_CHAT_FRAME then
            DEFAULT_CHAT_FRAME:AddMessage("|cff00ffcc[Key Roulette]|r Addon Loaded! Type |cffffd700/kr|r or |cffffd700/keyroulette|r to open.")
        end

    elseif event == "GROUP_ROSTER_UPDATE" then
        if KR:IsWindowVisible() then
            local now = GetTime()
            if not KR.lastRosterUpdate or (now - KR.lastRosterUpdate) > 3 then
                KR.lastRosterUpdate = now
                KR:BroadcastKeystone()
                KR:RequestGroupKeystones()
                KR:ScheduleRosterUpdate(0.3)
            end
        end

    elseif event == "GUILD_ROSTER_UPDATE" then
        if KR:IsWindowVisible() then
            KR:ScanGuildRosterKeys()
        end

    elseif event == "BAG_UPDATE_DELAYED" then
        if KR:IsWindowVisible() then
            local now = GetTime()
            if not KR.lastBagScan or (now - KR.lastBagScan) > 5 then
                KR.lastBagScan = now
                KR:ScanPlayerKeystone()
                KR:BroadcastKeystone()
                KR:ScheduleRosterUpdate(0.3)
            end
        end

    elseif event:sub(1, 8) == "CHAT_MSG" and event ~= "CHAT_MSG_ADDON" then
        -- Party Chat Keystone Link Auto-Parser!
        local text, sender = ...
        if text and sender then
            local senderName = (Ambiguate and Ambiguate(sender, "none")) or sender:match("([^-]+)") or sender
            local mapID, level = text:match("keystone:%d+:(%d+):(%d+)")
            if mapID and level then
                mapID = tonumber(mapID)
                level = tonumber(level)
                KR:SaveMemberKey(senderName, mapID, level, "Chat Link")
                if KR:IsWindowVisible() then KR:ScheduleRosterUpdate(0.2) end
            else
                local lvl, dName = text:match("%+(%d+)%s+([^%]+)]?")
                if not lvl then dName, lvl = text:match("([^%+%[b]+)%s*%+(%d+)") end
                if lvl and dName then
                    lvl = tonumber(lvl)
                    if lvl and lvl > 0 then
                        KR:SaveMemberKey(senderName, 0, lvl, "Chat Text", dName:gsub("^%s*(.-)%s*$", "%1"))
                        if KR:IsWindowVisible() then KR:ScheduleRosterUpdate(0.2) end
                    end
                end
            end
        end

    elseif event == "CHAT_MSG_ADDON" then
        local prefix, message, channel, sender = ...
        if not sender or not message then return end
        local senderName = (Ambiguate and Ambiguate(sender, "none")) or sender:match("([^-]+)") or sender

        -- Handle network ping / sync requests (only reply if window is open)
        if message == "PING" or message == "REQUEST" or message == "REQ" or message == "QUERY" or message == "REQUEST_KEY" or message == "REQ_KEY" then
            if (message == "PING" or message == "REQUEST" or message == "REQ" or message == "REQUEST_KEY") and KR:IsWindowVisible() then
                KR:BroadcastKeystone(true)
            end
            return
        end

        -- Extract keystone data from any supported payload format
        local mID, lvl, dName = ExtractMapAndLevel(message)
        if mID and lvl then
            KR:SaveMemberKey(senderName, mID, lvl, prefix, dName)
            if KR:IsWindowVisible() then KR:ScheduleRosterUpdate(0.2) end
        end
    end
end)

-- Announce Winner Function
function KR:AnnounceWinner(winner)
    if not winner or not winner.key then return end
    local key = winner.key
    local fmt = (KeyRouletteDB and KeyRouletteDB.customFormat) or "[Key Roulette] picked: %s's +%d %s!"
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
    if InCombatLockdown() or KR.inCombat then
        if DEFAULT_CHAT_FRAME then
            DEFAULT_CHAT_FRAME:AddMessage("|cff00ffcc[Key Roulette]|r Cannot open UI frame during combat.")
        end
        return
    end

    if not KR.UIFrame then
        if KR.CreateMainFrame then
            KR:CreateMainFrame()
        end
    end

    if KR.UIFrame then
        if KR.UIFrame:IsShown() then
            KR.UIFrame:Hide()
        else
            KR.UIFrame:Show()
            KR:ScanPlayerKeystone()
            KR:RequestGroupKeystones(true)
            KR:BroadcastKeystone(true)
            KR:UpdateGroupRoster(true)
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
