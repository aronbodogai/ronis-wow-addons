-- Roni's One For All - the collection's hub: /roni lists the Roni's addons
-- that are installed, whether they are enabled, and how to use them.
local TAG = "|cffff8c1aRoni's One For All|r"

local ADDONS = {
    { folder = "RonisItemPedia", how = "Alt + Left-Click any item, or /pedia" },
    { folder = "RonisMailMats", how = "panel beside the mailbox, /mailmats, minimap button" },
}

local Meta = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
local Info = (C_AddOns and C_AddOns.GetAddOnInfo) or GetAddOnInfo
local Loaded = (C_AddOns and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded

local function Clean(s)
    return (s or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
end

local function List()
    print(TAG .. ":")
    for _, a in ipairs(ADDONS) do
        local ok, name, _, _, _, reason = pcall(Info, a.folder)
        if ok and name and reason ~= "MISSING" then
            local title = Clean(Meta and Meta(a.folder, "Title") or a.folder)
            local version = Meta and Meta(a.folder, "Version") or "?"
            local state = (Loaded and Loaded(a.folder)) and "" or "  |cffff6040(disabled)|r"
            print(string.format("  |cffffd100%s|r |cff8c8c8c%s|r%s - %s", title, version, state, a.how))
        end
    end
end

SLASH_RONISONEFORALL1 = "/roni"
SlashCmdList.RONISONEFORALL = List
