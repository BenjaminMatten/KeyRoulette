-- Key Roulette Localization
local addonName, KR = ...

local L = {}
KR.L = L

-- Default English
L["ADDON_TITLE"] = "KEY ROULETTE"
L["SUBTITLE"] = "Mythic+ Group Key Picker"
L["SPIN_BUTTON"] = "SPIN ROULETTE"
L["SPINNING"] = "SPINNING..."
L["NO_KEYS_FOUND"] = "No Mythic+ keys found in group! Make sure group members have keys or edit them manually."
L["WINNER_ANNOUNCE"] = "🎲 Key Roulette picked: %s's +%d %s! Good luck!"
L["WINNER_TITLE"] = "WINNER PICKED!"
L["CHAT_CHANNEL"] = "Chat Output:"
L["MANUAL_EDIT"] = "Manual Edit"
L["DUNGEON"] = "Dungeon"
L["KEY_LEVEL"] = "Key Level"
L["SAVE"] = "Save"
L["CANCEL"] = "Cancel"
L["AUTO_ANNOUNCE"] = "Auto-announce win to chat"
L["EXCLUDE_KEY"] = "Exclude from roll"
L["NO_KEY_DETECTED"] = "No Key Detected"
L["SOURCE_AUTO"] = "Self Auto"
L["SOURCE_SYNC"] = "Synced"
L["SOURCE_MANUAL"] = "Manual"
L["REFRESH"] = "Refresh Group Keys"
L["TOGGLE_MINIMAP"] = "Toggle Minimap Icon"
L["SLASH_HELP"] = "Use /kr or /keyroulette to open UI."

-- Client Locale Overrides
local locale = GetLocale()
if locale == "deDE" then
    L["ADDON_TITLE"] = "KEY ROULETTE"
    L["SPIN_BUTTON"] = "ROULETTE DREHEN"
    L["NO_KEYS_FOUND"] = "Keine Mythisch+ Schlüssel in der Gruppe gefunden!"
elseif locale == "frFR" then
    L["ADDON_TITLE"] = "KEY ROULETTE"
    L["SPIN_BUTTON"] = "LANCER LA ROULETTE"
elseif locale == "esES" or locale == "esMX" then
    L["SPIN_BUTTON"] = "GIRAR RULETA"
elseif locale == "ruRU" then
    L["SPIN_BUTTON"] = "КРУТИТЬ РУЛЕТКУ"
elseif locale == "zhCN" or locale == "zhTW" then
    L["SPIN_BUTTON"] = "开启转盘"
end

setmetatable(L, {
    __index = function(t, k)
        return k
    end
})
