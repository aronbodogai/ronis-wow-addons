-- Roni's ItemPedia - core: API shims, saved data, recipe learning, click hooks.
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
    recipes = {},   -- ["Profession:Recipe"] = { prof, name, product, icon, made = {min,max}, reagents = {{id,count},...} }
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
-- Recipe knowledge (learned whenever a profession window is open)
---------------------------------------------------------------------------
ns.madeBy, ns.usedIn, ns.known = {}, {}, {}

function ns.BuildIndex()
    local madeBy, usedIn, known = {}, {}, {}
    for key, r in pairs(ns.db.recipes) do
        if r.product then
            madeBy[r.product] = madeBy[r.product] or {}
            table.insert(madeBy[r.product], key)
            known[r.product] = true
        end
        for _, rg in ipairs(r.reagents) do
            usedIn[rg[1]] = usedIn[rg[1]] or {}
            table.insert(usedIn[rg[1]], key)
            known[rg[1]] = true
        end
    end
    for _, t in pairs(madeBy) do table.sort(t) end
    for _, t in pairs(usedIn) do table.sort(t) end
    ns.madeBy, ns.usedIn, ns.known = madeBy, usedIn, known
end

local function StoreRecipe(prof, name, product, icon, minMade, maxMade, reagents)
    if #reagents == 0 then return end
    ns.db.recipes[prof .. ":" .. name] = {
        prof = prof, name = name, product = product, icon = icon,
        made = { minMade or 1, maxMade or minMade or 1 },
        reagents = reagents,
    }
end

local function ScanTradeSkill()
    if not (GetTradeSkillLine and GetNumTradeSkills) then return end
    local prof = GetTradeSkillLine()
    if not prof or prof == "UNKNOWN" then return end
    for i = 1, GetNumTradeSkills() do
        local name, kind = GetTradeSkillInfo(i)
        if name and kind ~= "header" and kind ~= "subheader" then
            local reagents, complete = {}, true
            for r = 1, GetTradeSkillNumReagents(i) or 0 do
                local _, _, count = GetTradeSkillReagentInfo(i, r)
                local rid = ns.ItemID(GetTradeSkillReagentItemLink(i, r))
                if not rid then complete = false break end
                reagents[#reagents + 1] = { rid, count or 1 }
            end
            if complete then
                local minMade, maxMade = GetTradeSkillNumMade(i)
                StoreRecipe(prof, name, ns.ItemID(GetTradeSkillItemLink(i)),
                    GetTradeSkillIcon and GetTradeSkillIcon(i), minMade, maxMade, reagents)
            end
        end
    end
end

-- Enchanting (and Beast Training, which has no reagents and is skipped)
local function ScanCraft()
    if not (GetCraftDisplaySkillLine and GetNumCrafts) then return end
    local prof = GetCraftDisplaySkillLine()
    if not prof then return end
    for i = 1, GetNumCrafts() do
        local name, _, kind = GetCraftInfo(i)
        if name and kind ~= "header" then
            local reagents, complete = {}, true
            for r = 1, GetCraftNumReagents(i) or 0 do
                local _, _, count = GetCraftReagentInfo(i, r)
                local rid = ns.ItemID(GetCraftReagentItemLink(i, r))
                if not rid then complete = false break end
                reagents[#reagents + 1] = { rid, count or 1 }
            end
            if complete then
                local product = GetCraftItemLink and ns.ItemID(GetCraftItemLink(i))
                StoreRecipe(prof, name, product, GetCraftIcon and GetCraftIcon(i), 1, 1, reagents)
            end
        end
    end
end

local scanQueued = false
local function QueueScan()
    if scanQueued then return end
    scanQueued = true
    C_Timer.After(0.3, function()
        scanQueued = false
        pcall(ScanTradeSkill)
        pcall(ScanCraft)
        ns.BuildIndex()
        if ns.UI and ns.UI.OnDataChanged then ns.UI:OnDataChanged(true) end
    end)
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
        ns.BuildIndex()
    elseif event == "PLAYER_LOGIN" then
        InstallHooks()
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
        if ns.UI and ns.UI.OnDataChanged then ns.UI:OnDataChanged() end
    else -- TRADE_SKILL_* / CRAFT_*
        QueueScan()
    end
end)

for _, e in ipairs({
    "ADDON_LOADED", "PLAYER_LOGIN", "GLOBAL_MOUSE_DOWN", "GET_ITEM_INFO_RECEIVED", "BAG_UPDATE_DELAYED",
    "TRADE_SKILL_SHOW", "TRADE_SKILL_UPDATE", "CRAFT_SHOW", "CRAFT_UPDATE",
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
    elseif msg == "forget" then
        wipe(ns.db.recipes)
        ns.BuildIndex()
        ns.UI:OnDataChanged(true)
        ns.Print("recipe knowledge cleared. Open your profession windows to relearn.")
    else
        local link = ns.Normalize(msg)
        if link then ns.Open(link) else ns.Print("no cached item matches '" .. msg .. "'.") end
    end
end
