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

-- Universal MapID and Level Extractor (Handles tables, multi-returns, string pairs, and prevents level/map swaps)
local function ExtractMapAndLevel(res1, res2)
    local mID, lvl

    if type(res1) == "table" then
        local rawMap = res1.mapID or res1.challengeMapID or res1.dungeonID or res1.dungeon_id or res1.map_id or res1.keyID or res1.map or res1.keystoneMapID or res1.keystoneMap or res1.challengeMapId or res1.dungeon or res1.mID or res1[1]
        local rawLvl = res1.level or res1.keyLevel or res1.key_level or res1.levelNumber or res1.level_num or res1.keystoneLevel or res1.keyLvl or res1.key or res1.lvl or res1[2]

        local n1 = tonumber(rawMap)
        local n2 = tonumber(rawLvl)

        if n1 and n2 then
            if n1 > 100 and n2 <= 50 then
                mID, lvl = n1, n2
            elseif n2 > 100 and n1 <= 50 then
                mID, lvl = n2, n1
            else
                mID, lvl = n1, n2
            end
        elseif n1 and n1 > 100 then
            mID = n1
        elseif n2 and n2 <= 50 then
            lvl = n2
        end

    elseif type(res1) == "number" and type(res2) == "number" then
        if res1 > 100 and res2 <= 50 then
            mID, lvl = res1, res2
        elseif res2 > 100 and res1 <= 50 then
            mID, lvl = res2, res1
        else
            mID, lvl = res1, res2
        end

    elseif type(res1) == "string" then
        local n1, n2 = res1:match("(%d+)[:#,%s]+(%d+)")
        if n1 and n2 then
            n1, n2 = tonumber(n1), tonumber(n2)
            if n1 > 100 and n2 <= 50 then
                mID, lvl = n1, n2
            elseif n2 > 100 and n1 <= 50 then
                mID, lvl = n2, n1
            else
                mID, lvl = n1, n2
            end
        end
    end

    if mID and lvl and mID > 0 and lvl > 0 then
        return mID, lvl
    end
    return nil, nil
end

-- Helper Table Matcher for Addon DBs (EllesmereUI, KeystoneLoot, Details, etc.)
local function CheckTableForMemberKey(tbl, searchNames)
    if not tbl or type(tbl) ~= "table" then return nil, nil end

    -- Direct key indexing (tbl["PlayerName"] or tbl["playername"])
    for _, sName in ipairs(searchNames) do
        if sName then
            local entry = tbl[sName] or tbl[sName:lower()]
            if entry then
                local mID, lvl = ExtractMapAndLevel(entry)
                if mID and lvl then return mID, lvl end
            end
        end
    end

    -- 1-level table iteration for array records ({ name = "...", map = ..., level = ... })
    for k, v in pairs(tbl) do
        if type(v) == "table" then
            local sender = v.name or v.sender or v.player or v.unit or (type(k) == "string" and k)
            if type(sender) == "string" then
                local sShort = sender:match("([^-]+)") or sender
                for _, sName in ipairs(searchNames) do
                    if sName and (sender == sName or sender:lower() == sName:lower() or sShort == sName or sShort:lower() == sName:lower()) then
                        local mID, lvl = ExtractMapAndLevel(v)
                        if mID and lvl then return mID, lvl end
                    end
                end
            end
        end
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
    if not name then return nil end
    local shortName = name:match("([^-]+)") or name
    local realm = GetNormalizedRealmName() or GetRealmName() or ""
    local fullName = name:find("-") and name or (shortName .. "-" .. realm)
    local guid = UnitExists(unit) and UnitGUID(unit)
    local searchNames = { fullName, shortName, name, guid }

    -- Purge any legacy RaiderIO caches
    KR:PurgeRaiderIOData()

    -- 1. Check manual user override (Edit button in UI)
    if KR.manualKeys[name] then return KR.manualKeys[name] end
    if KR.manualKeys[shortName] then return KR.manualKeys[shortName] end
    if KR.manualKeys[fullName] then return KR.manualKeys[fullName] end

    -- 2. Check EllesmereUI / EUIKeysPopup / EllesmereUIDB
    if _G.EllesmereUIDB or _G.EllesmereUI or _G.EUIKeysPopup or _G.EUIKeys then
        pcall(function()
            local eui = _G.EllesmereUIDB or _G.EllesmereUI or _G.EUIKeysPopup or _G.EUIKeys
            local mID, lvl
            if _G.EllesmereUIDB and type(_G.EllesmereUIDB.keystonePopup) == "table" then
                mID, lvl = CheckTableForMemberKey(_G.EllesmereUIDB.keystonePopup, searchNames)
            end
            if not mID and type(eui) == "table" then
                mID, lvl = CheckTableForMemberKey(eui, searchNames)
            end
            if mID and lvl then
                KR:SaveMemberKey(name, mID, lvl, "EllesmereUI")
            end
        end)
        if KR.groupMembers[name] and KR.groupMembers[name].source == "EllesmereUI" then
            return KR.groupMembers[name]
        end
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

            local mID, lvl = ExtractMapAndLevel(r1, r2)
            if mID and lvl then
                KR:SaveMemberKey(name, mID, lvl, "LibOpenRaid")
            end
        end)
        if KR.groupMembers[name] and KR.groupMembers[name].source == "LibOpenRaid" then
            return KR.groupMembers[name]
        end
    end

    -- 4. Check KeystoneLoot
    if _G.KeystoneLootDB or _G.KeystoneLootAPI or _G.KeystoneLootCharDB then
        pcall(function()
            local kl = _G.KeystoneLootCharDB or _G.KeystoneLootDB or _G.KeystoneLootAPI
            local mID, lvl = CheckTableForMemberKey(kl, searchNames)
            if mID and lvl then
                KR:SaveMemberKey(name, mID, lvl, "KeystoneLoot")
            end
        end)
        if KR.groupMembers[name] and KR.groupMembers[name].source == "KeystoneLoot" then
            return KR.groupMembers[name]
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

            local mID, lvl = ExtractMapAndLevel(r1, r2)
            if mID and lvl then
                KR:SaveMemberKey(name, mID, lvl, "LibTomoKeystoneSync")
            end
        end)
        if KR.groupMembers[name] and KR.groupMembers[name].source == "LibTomoKeystoneSync" then
            return KR.groupMembers[name]
        end
    end

    -- 6. Check LibOpenKeystone
    local lok = (LibStub and (LibStub("LibOpenKeystone-1.0", true) or LibStub("LibOpenKeystone", true))) or _G.LibOpenKeystone
    if lok then
        pcall(function()
            local r1, r2
            if lok.GetKeystone then r1, r2 = lok:GetKeystone(unit) end
            if not r1 and lok.keystones then r1 = lok.keystones[fullName] or lok.keystones[shortName] end

            local mID, lvl = ExtractMapAndLevel(r1, r2)
            if mID and lvl then
                KR:SaveMemberKey(name, mID, lvl, "LibOpenKeystone")
            end
        end)
        if KR.groupMembers[name] and KR.groupMembers[name].source == "LibOpenKeystone" then
            return KR.groupMembers[name]
        end
    end

    -- 7. Check Details & AstralKeys
    if _G.Details and _G.Details.Keystones then
        pcall(function()
            local dKey = _G.Details.Keystones[fullName] or _G.Details.Keystones[shortName] or _G.Details.Keystones[name]
            local mID, lvl = ExtractMapAndLevel(dKey)
            if mID and lvl then
                KR:SaveMemberKey(name, mID, lvl, "Details")
            end
        end)
        if KR.groupMembers[name] and KR.groupMembers[name].source == "Details" then
            return KR.groupMembers[name]
        end
    end

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
        if KR.groupMembers[name] and KR.groupMembers[name].source == "AstralKeys" then
            return KR.groupMembers[name]
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
                                    KR:SaveMemberKey(name, 507, l, "Tooltip")
                                    if KR.groupMembers[name] then
                                        KR.groupMembers[name].dungeonName = dName:gsub("^%s*(.-)%s*$", "%1")
                                    end
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

    -- 10. Deep Global Recursive Searcher (ONLY executed during explicit /kr resync or /kr debug)
    if allowDeepSearch then
        if _G.EllesmereUIDB or _G.EllesmereUI or _G.EUIKeysPopup then
            pcall(function()
                local eui = _G.EllesmereUIDB or _G.EllesmereUI or _G.EUIKeysPopup
                local mID, lvl = DeepSearchTable(eui, searchNames, 0)
                if mID and lvl then
                    KR:SaveMemberKey(name, mID, lvl, "EllesmereUI")
                end
            end)
            if KR.groupMembers[name] and KR.groupMembers[name].source == "EllesmereUI" then return KR.groupMembers[name] end
        end

        for gName, gVal in pairs(_G) do
            if type(gName) == "string" and (gName:find("Ellesmere") or gName:find("EUI") or gName:find("Tomo") or gName:find("Keystone")) and type(gVal) == "table" and gName ~= "RaiderIO" then
                pcall(function()
                    local mID, lvl = DeepSearchTable(gVal, searchNames, 0)
                    if mID and lvl then
                        KR:SaveMemberKey(name, mID, lvl, gName)
                    end
                end)
                if KR.groupMembers[name] then return KR.groupMembers[name] end
            end
        end
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
    -- Dump EUIKeysPopup and EllesmereUIDB
    if _G.EUIKeysPopup then
        AddLog("=== EUIKeysPopup Table Dump ===")
        pcall(function()
            for k, v in pairs(_G.EUIKeysPopup) do
                if type(v) ~= "function" then
                    AddLog("  EUIKeysPopup." .. tostring(k) .. " = " .. tostring(v))
                    if type(v) == "table" then
                        for k2, v2 in pairs(v) do
                            AddLog("    EUIKeysPopup." .. tostring(k) .. "." .. tostring(k2) .. " = " .. tostring(v2))
                        end
                    end
                end
            end
        end)
    end
    if _G.EllesmereUIDB then
        AddLog("=== EllesmereUIDB Table Dump ===")
        pcall(function()
            if _G.EllesmereUIDB.keystonePopup and type(_G.EllesmereUIDB.keystonePopup) == "table" then
                AddLog("  [EllesmereUIDB.keystonePopup Contents]:")
                for k, v in pairs(_G.EllesmereUIDB.keystonePopup) do
                    AddLog("    keystonePopup[" .. tostring(k) .. "] = " .. tostring(v))
                    if type(v) == "table" then
                        for k2, v2 in pairs(v) do
                            AddLog("      [" .. tostring(k2) .. "] = " .. tostring(v2))
                            if type(v2) == "table" then
                                for k3, v3 in pairs(v2) do
                                    AddLog("        [" .. tostring(k3) .. "] = " .. tostring(v3))
                                end
                            end
                        end
                    end
                end
            else
                for k, v in pairs(_G.EllesmereUIDB) do
                    if type(k) == "string" and (k:lower():find("key") or k:lower():find("party") or k:lower():find("roster")) then
                        AddLog("  EllesmereUIDB." .. tostring(k) .. " = " .. tostring(v))
                    end
                end
            end
        end)
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
                        local prof = _G.RaiderIO.GetProfile(unit) or _G.RaiderIO.GetProfile(shortName) or _G.RaiderIO.GetProfile(name)
                        if prof then
                            AddLog("  [RaiderIO.GetProfile]: profile object found for " .. name)
                            if type(prof) == "table" then
                                for k, v in pairs(prof) do
                                    if type(v) ~= "function" then
                                        if type(v) == "table" then
                                            AddLog("    prof." .. tostring(k) .. " (table):")
                                            for k2, v2 in pairs(v) do
                                                if type(v2) ~= "function" then
                                                    AddLog("      prof." .. tostring(k) .. "." .. tostring(k2) .. " = " .. tostring(v2))
                                                end
                                            end
                                        else
                                            AddLog("    prof." .. tostring(k) .. " = " .. tostring(v))
                                        end
                                    end
                                end
                            end
                        end
                    end)
                end

                -- KeystoneLoot check
                if _G.KeystoneLootDB then
                    pcall(function()
                        AddLog("  [KeystoneLootDB dump for " .. name .. "]:")
                        for k, v in pairs(_G.KeystoneLootDB) do
                            if type(k) == "string" and (k:find(shortName) or k:find(name) or k == "characters" or k == "keys" or k == "keystones") then
                                AddLog("    KeystoneLootDB[" .. tostring(k) .. "] = " .. tostring(v))
                                if type(v) == "table" then
                                    for k2, v2 in pairs(v) do
                                        AddLog("      [" .. tostring(k2) .. "] = " .. tostring(v2))
                                    end
                                end
                            end
                        end
                    end)
                end
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

-- Scan Guild Roster Notes for Keystone Info
function KR:ScanGuildRosterKeys()
    if not IsInGuild() then return end
    pcall(function()
        if C_GuildInfo and C_GuildInfo.GuildRoster then
            C_GuildInfo.GuildRoster()
        end
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
                                KR:SaveMemberKey(shortName, 507, l, "Guild Note")
                                if KR.groupMembers[shortName] then
                                    KR.groupMembers[shortName].dungeonName = dName:gsub("^%s*(.-)%s*$", "%1")
                                end
                            end
                        end
                    end
                end
            end
        end
    end)
end

-- Helper function to safely send addon messages with channel verification
local function SafeSendAddonMsg(prefix, text, targetChan)
    if not targetChan then return end
    if (targetChan == "PARTY" or targetChan == "RAID") and not IsInGroup() then return end
    if targetChan == "RAID" and not IsInRaid() then return end
    if targetChan == "GUILD" and not IsInGuild() then return end
    pcall(C_ChatInfo.SendAddonMessage, prefix, text, targetChan)
end

-- Broadcast Self Keystone to Party & Guild
function KR:BroadcastKeystone()
    if InCombatLockdown() or KR.inCombat then return end
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
        SafeSendAddonMsg("LibOpenKeystone", string.format("KEY:%d:%d", key.mapID, key.level), targetChan)
        SafeSendAddonMsg("LibTomoKeystoneSync", string.format("KEY:%d:%d", key.mapID, key.level), targetChan)
        SafeSendAddonMsg("LibOpenRaid", string.format("KEY,%d,%d", key.mapID, key.level), targetChan)
    end
end

-- Request Group & Guild Keystones
function KR:RequestGroupKeystones()
    if InCombatLockdown() or KR.inCombat then return end

    local channels = {}
    if IsInGroup() then
        table.insert(channels, IsInRaid() and "RAID" or "PARTY")
    end
    if IsInGuild() then
        table.insert(channels, "GUILD")
    end

    if #channels > 0 then
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

        -- Send network pings to active channels
        for _, targetChan in ipairs(channels) do
            SafeSendAddonMsg("KeyRoulette", "PING", targetChan)
            SafeSendAddonMsg("EllesmereUI", "REQUEST", targetChan)
            SafeSendAddonMsg("LibOpenKeystone", "REQUEST", targetChan)
            SafeSendAddonMsg("LibTomoKeystoneSync", "REQUEST", targetChan)
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
    KR:RequestGroupKeystones()
end

-- Manual Resync All Keys Action
function KR:ResyncAllKeys()
    if InCombatLockdown() or KR.inCombat then
        if DEFAULT_CHAT_FRAME then
            DEFAULT_CHAT_FRAME:AddMessage("|cff00ffcc[Key Roulette]|r Cannot resync keys during combat.")
        end
        return
    end
    KR:ScanPlayerKeystone()
    if IsInGroup() or IsInGuild() then
        KR:RequestGroupKeystones()
        KR:BroadcastKeystone()
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
                if not InCombatLockdown() then
                    KR:ScanPlayerKeystone()
                    KR:UpdateGroupRoster()
                end
            end)
        end
        return
    end

    -- Strict Combat Protection Guard: Freeze all background calculations during dungeon fights!
    if InCombatLockdown() or KR.inCombat then
        if event == "GROUP_ROSTER_UPDATE" or event == "BAG_UPDATE_DELAYED" then
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

    elseif event == "GROUP_ROSTER_UPDATE" or event == "GUILD_ROSTER_UPDATE" then
        local now = GetTime()
        if not KR.lastRosterUpdate or (now - KR.lastRosterUpdate) > 2 then
            KR.lastRosterUpdate = now
            KR:ScanGuildRosterKeys()
            KR:BroadcastKeystone()
            KR:RequestGroupKeystones()
            KR:UpdateGroupRoster()
        end

    elseif event == "BAG_UPDATE_DELAYED" then
        local now = GetTime()
        if not KR.lastBagScan or (now - KR.lastBagScan) > 5 then
            KR.lastBagScan = now
            KR:ScanPlayerKeystone()
            KR:BroadcastKeystone()
            KR:UpdateGroupRoster()
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
                KR:UpdateGroupRoster()
            else
                local lvl, dName = text:match("%+(%d+)%s+([^%]+)]?")
                if not lvl then dName, lvl = text:match("([^%+%[b]+)%s*%+(%d+)") end
                if lvl and dName then
                    lvl = tonumber(lvl)
                    if lvl and lvl > 0 then
                        KR:SaveMemberKey(senderName, 507, lvl, "Chat Text")
                        if KR.groupMembers[senderName] then
                            KR.groupMembers[senderName].dungeonName = dName:gsub("^%s*(.-)%s*$", "%1")
                        end
                        KR:UpdateGroupRoster()
                    end
                end
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

        elseif prefix == "AstralKeys" or prefix == "Details" or prefix == "MythicKeystones" then
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
