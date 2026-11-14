-- Roni's ItemPedia - core: API shims, saved data, recipe index, click hooks.
local ADDON, ns = ...

ns.TITLE = "Roni's ItemPedia"
ns.TAG = "|cffff8c1aRoni's ItemPedia|r"

---------------------------------------------------------------------------
-- API shims (the Forever client is Classic-based; prefer globals, fall back
-- to the modern C_ namespaces when a global is missing)
---------------------------------------------------------------------------
ns.GetItemInfo  = GetItemInfo  or (C_Item and C_Item.GetItemInfo)
ns.GetItemIcon  = GetItemIcon  or (C_Item and C_Item.GetItemIconByID)
ns.GetItemCount = GetItemCount or (C_Item and C_Item.GetItemCount)

local CC = C_Container
ns.GetContainerNumSlots = (CC and CC.GetContainerNumSlots) or GetContainerNumSlots
ns.GetContainerItemLink = (CC and CC.GetContainerItemLink) or GetContainerItemLink

function ns.SpellInfo(spellID)
    if C_Spell and C_Spell.GetSpellInfo then
        local info = C_Spell.GetSpellInfo(spellID)
        if info then return info.name, info.iconID end
    end
    if GetSpellInfo then
        local name, _, icon = GetSpellInfo(spellID)
        return name, icon
    end
end

function ns.Print(...)
    print(ns.TAG .. ":", ...)
end

-- Item ID from a number, "item:123", a full hyperlink or a numeric string.
function ns.ItemID(ref)
    if type(ref) == "number" then return ref end
    if type(ref) ~= "string" then return nil end
    return tonumber(ref:match("item:(%d+)")) or tonumber(ref)
end

-- Turn anything item-ish into a string usable by GetItemInfo/SetHyperlink.
-- Full links are kept as-is so random suffixes ("of the Bear") survive.
function ns.Normalize(ref)
    if type(ref) == "number" then return "item:" .. ref end
    if type(ref) ~= "string" then return nil end
    if ref:find("|Hitem:") or ref:find("^item:") then return ref end
    local n = tonumber(ref)
    if n then return "item:" .. n end
    local _, link = ns.GetItemInfo(ref) -- by name; only works for cached items
    return link
end

---------------------------------------------------------------------------
-- Saved data
---------------------------------------------------------------------------
local DEFAULTS = {
    history = {},   -- recently viewed links, newest first
    tab = "Bags",
    pos = nil,
}

local function InitDB()
    RonisItemPediaDB = RonisItemPediaDB or {}
    for k, v in pairs(DEFAULTS) do
        if RonisItemPediaDB[k] == nil then
            RonisItemPediaDB[k] = type(v) == "table" and {} or v
        end
    end
    RonisItemPediaDB.recipes = nil -- 0.1.0 learned recipes; replaced by Data/Recipes.lua
    ns.db = RonisItemPediaDB
end

function ns.AddHistory(link)
    local id = ns.ItemID(link)
    local h = ns.db.history
    for i = #h, 1, -1 do
        if ns.ItemID(h[i]) == id then table.remove(h, i) end
    end
    table.insert(h, 1, link)
    while #h > 60 do h[#h] = nil end
end

---------------------------------------------------------------------------
-- Recipe index over Data/Recipes.lua
-- ns.RECIPES[i] = { spellID, profIndex, productID (0 = enchant), min, max, { reagentID, count, ... },
--                  learnSkill (0 = unknown), yellowSkill, greySkill, autoLearned, { recipeItemID, ... } }
---------------------------------------------------------------------------
ns.madeBy, ns.usedIn, ns.bySpell = {}, {}, {}

local function BuildIndex()
    local madeBy, usedIn, bySpell = {}, {}, {}
    for i, r in ipairs(ns.RECIPES or {}) do
        bySpell[r[1]] = i
        if r[3] > 0 then
            madeBy[r[3]] = madeBy[r[3]] or {}
            table.insert(madeBy[r[3]], i)
        end
        local reg = r[6]
        for k = 1, #reg, 2 do
            local id = reg[k]
            local t = usedIn[id]
            if not t then t = {}; usedIn[id] = t end
            if t[#t] ~= i then t[#t + 1] = i end
        end
    end
    ns.madeBy, ns.usedIn, ns.bySpell = madeBy, usedIn, bySpell
end

-- Friendly view of one recipe row.
function ns.Recipe(index)
    local r = ns.RECIPES[index]
    if not r then return nil end
    local reagents = {}
    for k = 1, #r[6], 2 do reagents[#reagents + 1] = { r[6][k], r[6][k + 1] } end
    return {
        spell = r[1],
        prof = ns.RECIPE_PROFS[r[2]] or "?",
        profIndex = r[2],
        product = r[3] > 0 and r[3] or nil,
        min = r[4], max = r[5],
        reagents = reagents,
        learn = (r[7] or 0) > 0 and r[7] or nil,
        yellow = (r[8] or 0) > 0 and r[8] or nil,
        grey = (r[9] or 0) > 0 and r[9] or nil,
        auto = r[10] == 1,
        recipeItems = r[11] or {},
    }
end

---------------------------------------------------------------------------
-- Alt + Left-Click detection
---------------------------------------------------------------------------
local lastID, lastTime = nil, 0
function ns.TryOpen(link)
    local id = ns.ItemID(link)
    if not id then return end
    local now = GetTime()
    if id == lastID and now - lastTime < 0.4 then return end -- several hooks can fire for one click
    lastID, lastTime = id, now
    ns.Open(link)
end

local function InstallHooks()
    -- Bags, bank, character sheet, loot, merchant... (Blizzard modified-click path)
    if HandleModifiedItemClick then
        hooksecurefunc("HandleModifiedItemClick", function(link)
            if not IsAltKeyDown() or type(link) ~= "string" or not link:find("item:") then return end
            local button = GetMouseButtonClicked and GetMouseButtonClicked()
            if button and button ~= "LeftButton" then return end
            ns.TryOpen(link)
        end)
    end

    -- Item links in chat
    hooksecurefunc("SetItemRef", function(link, text, button)
        if not IsAltKeyDown() or button ~= "LeftButton" then return end
        if type(link) ~= "string" or not link:find("^item:") then return end
        if ItemRefTooltip then ItemRefTooltip:Hide() end
        ns.TryOpen((type(text) == "string" and text:find("|Hitem:")) and text or link)
    end)
end

local f = CreateFrame("Frame")
f:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" and arg1 == ADDON then
        InitDB()
        BuildIndex()
    elseif event == "PLAYER_LOGIN" then
        InstallHooks()
        C_Timer.After(5, function() pcall(ns.StartQuestScan) end) -- let login settle first
    elseif event == "GLOBAL_MOUSE_DOWN" then
        -- Anything that shows an item tooltip (also covers bag addons like Bagnon,
        -- quest rewards, auction house rows...). Action buttons are skipped because
        -- Alt-click there is self-cast.
        if arg1 ~= "LeftButton" or not IsAltKeyDown() or not GameTooltip:IsVisible() then return end
        local owner = GameTooltip:GetOwner()
        if owner and owner.action ~= nil then return end
        local _, link = GameTooltip:GetItem()
        if link then ns.TryOpen(link) end
    elseif event == "GET_ITEM_INFO_RECEIVED" then
        if ns.UI and ns.UI.OnItemInfo then ns.UI:OnItemInfo(arg1) end
    elseif event == "BAG_UPDATE_DELAYED" then
        if ns.UI and ns.UI.OnDataChanged then ns.UI:OnDataChanged(false) end
    elseif event == "ZONE_CHANGED_NEW_AREA" then
        -- distances to vendors/mobs changed a lot
        if ns.UI and ns.UI.OnDataChanged then ns.UI:OnDataChanged(true) end
    end
end)

for _, e in ipairs({
    "ADDON_LOADED", "PLAYER_LOGIN", "GLOBAL_MOUSE_DOWN", "GET_ITEM_INFO_RECEIVED", "BAG_UPDATE_DELAYED",
    "ZONE_CHANGED_NEW_AREA",
}) do
    pcall(f.RegisterEvent, f, e) -- tolerate events this client does not know
end

---------------------------------------------------------------------------
-- Slash commands
---------------------------------------------------------------------------
SLASH_RONISITEMPEDIA1 = "/pedia"
SLASH_RONISITEMPEDIA2 = "/ronipedia"
SlashCmdList.RONISITEMPEDIA = function(msg)
    msg = strtrim(msg or "")
    if msg == "" then
        ns.Toggle()
    elseif msg == "reset" then
        ns.db.pos = nil
        if ns.UI.frame then
            ns.UI.frame:ClearAllPoints()
            ns.UI.frame:SetPoint("CENTER")
        end
        ns.Print("window position reset.")
    else
        local link = ns.Normalize(msg)
        if link then ns.Open(link) else ns.Print("no cached item matches '" .. msg .. "'.") end
    end
end
