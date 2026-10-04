-- Key Roulette Embedded Libraries (LibStub, LibKeystone, LibOpenKeystone, LibTomo, LibOpenRaid)
-- Guarantees full network sync compatibility even if BigWigs, AstralKeys, or Details are not installed.

-- 1. LibStub v1.0
local LIBSTUB_MAJOR, LIBSTUB_MINOR = "LibStub", 2
local LibStub = _G.LibStub

if not LibStub or (LibStub.minor or 0) < LIBSTUB_MINOR then
    LibStub = LibStub or { libs = {}, minors = {} }
    _G.LibStub = LibStub
    LibStub.minor = LIBSTUB_MINOR

    function LibStub:NewLibrary(major, minor)
        assert(type(major) == "string", "Bad argument #1 to `NewLibrary` (string expected)")
        minor = assert(tonumber(minor), "Bad argument #2 to `NewLibrary` (number expected)")
        if self.minors[major] and self.minors[major] >= minor then return nil end
        self.minors[major] = minor
        self.libs[major] = self.libs[major] or {}
        return self.libs[major], self.minors[major]
    end

    function LibStub:GetLibrary(major, silent)
        if not self.libs[major] and not silent then
            error("Cannot find a library instance of " .. tostring(major) .. ".", 2)
        end
        return self.libs[major], self.minors[major]
    end

    function LibStub:IterateLibraries()
        return pairs(self.libs)
    end

    setmetatable(LibStub, { __call = LibStub.GetLibrary })
end

-- 2. LibKeystone-1.0 (BigWigs / LittleWigs Keystone Library Provider)
local libK = LibStub:NewLibrary("LibKeystone-1.0", 1)
if libK then
    libK.keystones = libK.keystones or {}
    libK.callbacks = libK.callbacks or {}

    function libK:GetKeystone(unitOrName)
        if not unitOrName then return nil end
        local short = unitOrName:match("([^-]+)") or unitOrName
        return libK.keystones[unitOrName] or libK.keystones[short] or libK.keystones[unitOrName:lower()]
    end

    function libK:RequestKeystones(channel)
        channel = channel or (IsInRaid() and "RAID" or "PARTY")
        if (channel == "PARTY" or channel == "RAID") and not IsInGroup() then return end
        pcall(C_ChatInfo.SendAddonMessage, "LibKeystone", "REQUEST", channel)
        pcall(C_ChatInfo.SendAddonMessage, "LKS", "REQ", channel)
    end

    function libK:SendKeystone(channel)
        if _G.KeyRoulette and _G.KeyRoulette.BroadcastKeystone then
            _G.KeyRoulette:BroadcastKeystone()
        end
    end
end

-- 3. LibOpenKeystone-1.0 Provider
local libOK = LibStub:NewLibrary("LibOpenKeystone-1.0", 1)
if libOK then
    libOK.keystones = libOK.keystones or {}
    function libOK:GetKeystone(unitOrName)
        if not unitOrName then return nil end
        local short = unitOrName:match("([^-]+)") or unitOrName
        return libOK.keystones[unitOrName] or libOK.keystones[short] or libOK.keystones[unitOrName:lower()]
    end
    function libOK:RequestKeystones(channel)
        channel = channel or (IsInRaid() and "RAID" or "PARTY")
        if (channel == "PARTY" or channel == "RAID") and not IsInGroup() then return end
        pcall(C_ChatInfo.SendAddonMessage, "LibOpenKeystone", "REQUEST", channel)
    end
end

-- 4. LibTomoKeystoneSync-1.0 Provider
local libTomo = LibStub:NewLibrary("LibTomoKeystoneSync-1.0", 1)
if libTomo then
    libTomo.keys = libTomo.keys or {}
    function libTomo:GetKeystone(unitOrName)
        if not unitOrName then return nil end
        local short = unitOrName:match("([^-]+)") or unitOrName
        return libTomo.keys[unitOrName] or libTomo.keys[short] or libTomo.keys[unitOrName:lower()]
    end
    function libTomo:RequestKeystones(channel)
        channel = channel or (IsInRaid() and "RAID" or "PARTY")
        if (channel == "PARTY" or channel == "RAID") and not IsInGroup() then return end
        pcall(C_ChatInfo.SendAddonMessage, "LibTomoKeystoneSync", "REQUEST", channel)
    end
end

-- 5. LibOpenRaid-1.0 Provider (Details! OpenRaid Library)
local libLOR = LibStub:NewLibrary("LibOpenRaid-1.0", 1)
if libLOR then
    libLOR.keystones = libLOR.keystones or {}
    libLOR.allyData = libLOR.allyData or {}

    function libLOR:GetKeystoneInfo(unitOrName)
        if not unitOrName then return nil end
        local short = unitOrName:match("([^-]+)") or unitOrName
        local record = libLOR.keystones[unitOrName] or libLOR.keystones[short] or libLOR.keystones[unitOrName:lower()]
        if record then return record.mapID, record.level end
        return nil
    end

    function libLOR:RequestKeystoneInfo(channel)
        channel = channel or (IsInRaid() and "RAID" or "PARTY")
        if (channel == "PARTY" or channel == "RAID") and not IsInGroup() then return end
        pcall(C_ChatInfo.SendAddonMessage, "LibOpenRaid", "REQUEST_KEY", channel)
    end
end
