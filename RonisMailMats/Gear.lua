-- Roni's MailMats - gear upgrades for alts.
--
-- Every character records the item level it wears in each slot. An item in
-- your bags is an upgrade for an alt when the alt can wear it now (level,
-- armor type, weapon skill its class can learn) and its item level beats what
-- the alt wears there. Upgrades get a mail icon on the bag slot (Bagnon and
-- the default bags), a line in the item tooltip and a "Send upgrades" button
-- on the mailbox panel.
local ADDON, ns = ...

local GetItemInfo = GetItemInfo or (C_Item and C_Item.GetItemInfo)
local CC = C_Container
local GetContainerItemLink = (CC and CC.GetContainerItemLink) or GetContainerItemLink

ns.UPGRADE_ICON = "Interface\\Icons\\INV_Letter_15"
ns.UPGRADES = "Upgrades" -- pseudo profession key used by the panel and drafting

---------------------------------------------------------------------------
-- What a class can wear (Classic rules)
---------------------------------------------------------------------------
local ARMOR, WEAPON = 4, 2
-- armor subclasses: 0 misc, 1 cloth, 2 leather, 3 mail, 4 plate, 6 shield,
-- 7 libram, 8 idol, 9 totem
-- weapon subclasses: 0 axe, 1 2h axe, 2 bow, 3 gun, 4 mace, 5 2h mace,
-- 6 polearm, 7 sword, 8 2h sword, 10 staff, 13 fist, 15 dagger, 16 thrown,
-- 18 crossbow, 19 wand
local function Set(...)
    local s = {}
    for i = 1, select("#", ...) do s[select(i, ...)] = true end
    return s
end

-- body armor: the best type the class wears, and the level it gets better
local BODY = {
    WARRIOR = { 3, 4, 40 }, PALADIN = { 3, 4, 40 },
    HUNTER = { 2, 3, 40 }, SHAMAN = { 2, 3, 40 },
    ROGUE = { 2 }, DRUID = { 2 },
    PRIEST = { 1 }, MAGE = { 1 }, WARLOCK = { 1 },
}
local SHIELD = Set("WARRIOR", "PALADIN", "SHAMAN")
local RELIC = { PALADIN = 7, DRUID = 8, SHAMAN = 9 }
local WEAPONS = {
    WARRIOR = Set(0, 1, 2, 3, 4, 5, 6, 7, 8, 10, 13, 15, 16, 18),
    PALADIN = Set(0, 1, 4, 5, 6, 7, 8),
    HUNTER = Set(0, 1, 2, 3, 6, 7, 8, 10, 13, 15, 16, 18),
    ROGUE = Set(2, 3, 4, 7, 13, 15, 16, 18),
    PRIEST = Set(4, 10, 15, 19),
    SHAMAN = Set(0, 1, 4, 5, 10, 13, 15),
    MAGE = Set(7, 10, 15, 19),
    WARLOCK = Set(7, 10, 15, 19),
    DRUID = Set(4, 5, 10, 13, 15),
}

-- equip location -> inventory slots it can go in
local SLOTS = {
    INVTYPE_HEAD = { 1 }, INVTYPE_NECK = { 2 }, INVTYPE_SHOULDER = { 3 },
    INVTYPE_CHEST = { 5 }, INVTYPE_ROBE = { 5 }, INVTYPE_WAIST = { 6 },
    INVTYPE_LEGS = { 7 }, INVTYPE_FEET = { 8 }, INVTYPE_WRIST = { 9 },
    INVTYPE_HAND = { 10 }, INVTYPE_FINGER = { 11, 12 }, INVTYPE_TRINKET = { 13, 14 },
    INVTYPE_CLOAK = { 15 },
    INVTYPE_WEAPON = { 16 }, INVTYPE_2HWEAPON = { 16 }, INVTYPE_WEAPONMAINHAND = { 16 },
    INVTYPE_WEAPONOFFHAND = { 17 }, INVTYPE_SHIELD = { 17 }, INVTYPE_HOLDABLE = { 17 },
    INVTYPE_RANGED = { 18 }, INVTYPE_RANGEDRIGHT = { 18 }, INVTYPE_THROWN = { 18 },
    INVTYPE_RELIC = { 18 },
}
local BODY_SLOT = Set("INVTYPE_HEAD", "INVTYPE_SHOULDER", "INVTYPE_CHEST", "INVTYPE_ROBE",
    "INVTYPE_WAIST", "INVTYPE_LEGS", "INVTYPE_FEET", "INVTYPE_WRIST", "INVTYPE_HAND")
local OFF_HAND = Set("INVTYPE_WEAPONOFFHAND", "INVTYPE_SHIELD", "INVTYPE_HOLDABLE")
ns.GEAR_SLOTS = { 1, 2, 3, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18 }

local function CanWear(class, level, equipLoc, classID, subID)
    if classID == ARMOR then
        if BODY_SLOT[equipLoc] then
            local b = BODY[class]
            if not b then return false end
            local best = (b[3] and level >= b[3]) and b[2] or b[1]
            return subID == best
        end
        if equipLoc == "INVTYPE_SHIELD" then return SHIELD[class] or false end
        if equipLoc == "INVTYPE_RELIC" then return RELIC[class] == subID end
        return true -- cloak, neck, rings, trinkets, off-hand frills
    elseif classID == WEAPON then
        local w = WEAPONS[class]
        return (w and w[subID]) or false
    end
    return false
end

-- Item level and the fields we need, or nil while the item is not cached.
local function ItemData(item)
    local name, _, _, ilvl, minLevel, _, _, _, equipLoc, _, _, classID, subID, bindType = GetItemInfo(item)
    if not name then return nil end
    if C_Item and C_Item.GetDetailedItemLevelInfo then
        ilvl = C_Item.GetDetailedItemLevelInfo(item) or ilvl
    end
    return { ilvl = ilvl or 0, minLevel = minLevel or 0, equipLoc = equipLoc, classID = classID,
             subID = subID, bindType = bindType }
end

---------------------------------------------------------------------------
-- Recording what this character wears
---------------------------------------------------------------------------
-- c.gear = { [slot] = item level (0 = empty), twoHand = true/nil }
function ns.ScanGear()
    local me = ns.db and ns.MyChar()
    if not me then return end
    local old = me.gear or {}
    local gear = {}
    for _, slot in ipairs(ns.GEAR_SLOTS) do
        local link = GetInventoryItemLink("player", slot)
        if not link then
            gear[slot] = 0
        else
            local d = ItemData(link)
            gear[slot] = d and d.ilvl or old[slot] or 0 -- not cached yet: keep what we knew
            if slot == 16 and d and d.equipLoc == "INVTYPE_2HWEAPON" then gear.twoHand = true end
            if slot == 16 and not d then gear.twoHand = old.twoHand end
        end
    end
    me.gear = gear
end

---------------------------------------------------------------------------
-- Upgrade checks
---------------------------------------------------------------------------
-- How much better `item` is for alt c (item level gained), or nil.
-- How many levels ahead an item may be and still count (db.upgradeAhead,
-- default 3): a level-18 item is worth mailing to a level-16 alt.
function ns.UpgradeAhead()
    local v = ns.db and ns.db.upgradeAhead
    if v == nil then return 3 end
    return v
end

-- Returns the item level gained and, for an item the alt cannot wear yet,
-- the level it needs.
local function Gain(c, d)
    if not (c.gear and c.class and d.equipLoc) then return nil end
    local slots = SLOTS[d.equipLoc]
    if not slots then return nil end
    local level = c.level or 0
    if d.minLevel > level + ns.UpgradeAhead() then return nil end
    local wearAt = math.max(level, d.minLevel) -- armor type at the level it will be worn
    if not CanWear(c.class, wearAt, d.equipLoc, d.classID, d.subID) then return nil end
    if OFF_HAND[d.equipLoc] and c.gear.twoHand then return nil end
    -- compare with the weakest of the slots it can go in (rings, trinkets)
    local worst
    for _, s in ipairs(slots) do
        local v = c.gear[s] or 0
        if not worst or v < worst then worst = v end
    end
    local gain = d.ilvl - worst
    if gain <= 0 then return nil end
    return gain, (d.minLevel > level) and d.minLevel or nil
end

-- { {alt = name, gain = n, at = level or nil}, ... } for every mailable alt
-- the item upgrades (`at`: the level it can be worn from, when not yet).
function ns.UpgradesFor(item)
    if not (ns.db and item) then return {} end
    local d = ItemData(item)
    if not d or d.bindType == 1 then return {} end -- bind on pickup: cannot be mailed
    local out = {}
    for _, alt in ipairs(ns.Alts()) do
        local gain, at = Gain(ns.db.chars[ns.realm][alt], d)
        if gain then out[#out + 1] = { alt = alt, gain = gain, at = at } end
    end
    return out
end

-- Is the item in this bag slot an upgrade for `alt` (or any alt)?
function ns.IsUpgradeIn(bag, slot, alt)
    local link = GetContainerItemLink(bag, slot)
    if not link then return false end
    local info = CC and CC.GetContainerItemInfo and CC.GetContainerItemInfo(bag, slot)
    if info and info.isBound then return false end -- soulbound: cannot be mailed
    for _, u in ipairs(ns.UpgradesFor(link)) do
        if not alt or u.alt == alt then return true end
    end
    return false
end

---------------------------------------------------------------------------
-- Tooltip line
---------------------------------------------------------------------------
local function AddTooltipLines(tt, link)
    if not link then return end
    for _, u in ipairs(ns.UpgradesFor(link)) do
        if u.at then
            tt:AddLine(("|T%s:14|t Upgrade for %s at level %d (+%d item level)"):format(ns.UPGRADE_ICON, u.alt, u.at, u.gain),
                0.6, 0.9, 0.3)
        else
            tt:AddLine(("|T%s:14|t Upgrade for %s (+%d item level)"):format(ns.UPGRADE_ICON, u.alt, u.gain),
                0.25, 1, 0.25)
        end
    end
end

local function HookTooltips()
    if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tt)
            if tt ~= GameTooltip and tt ~= ItemRefTooltip then return end
            local _, link = tt:GetItem()
            AddTooltipLines(tt, link)
        end)
    elseif GameTooltip and GameTooltip.HookScript then
        GameTooltip:HookScript("OnTooltipSetItem", function(tt)
            local _, link = tt:GetItem()
            AddTooltipLines(tt, link)
        end)
    end
end

---------------------------------------------------------------------------
-- Bag slot icon
---------------------------------------------------------------------------
local function SetIcon(button, show)
    local tex = button.RonisMailMatsIcon
    if not tex then
        if not show then return end
        tex = button:CreateTexture(nil, "OVERLAY")
        tex:SetSize(14, 14)
        tex:SetPoint("TOPLEFT", 2, -2)
        tex:SetTexture(ns.UPGRADE_ICON)
        button.RonisMailMatsIcon = tex
    end
    tex:SetShown(show and true or false)
end
ns.SetUpgradeIcon = SetIcon

local function IsLiveBag(bag)
    return type(bag) == "number" and bag >= 0 and bag <= (NUM_BAG_SLOTS or 4)
end

-- Bagnon: its item buttons call UpdateUpgradeIcon on every update.
local function HookBagnon()
    local item = Bagnon and Bagnon.Item
    if not (item and item.UpdateUpgradeIcon) or item.RonisMailMatsHooked then return end
    item.RonisMailMatsHooked = true
    hooksecurefunc(item, "UpdateUpgradeIcon", function(button)
        local bag, slot = button.GetBag and button:GetBag(), button:GetID()
        local show = false
        -- only this character's own bags (Bagnon also shows other characters')
        if IsLiveBag(bag) and button.info and button.info.hyperlink
            and GetContainerItemLink(bag, slot) == button.info.hyperlink then
            show = ns.IsUpgradeIn(bag, slot)
        end
        SetIcon(button, show)
    end)
end

-- Default bags: ContainerFrame1..13 item buttons.
local function UpdateDefaultBags()
    for i = 1, 13 do
        local frame = _G["ContainerFrame" .. i]
        if frame and frame:IsShown() then
            local name = frame:GetName()
            for j = 1, 36 do
                local b = (frame.Items and frame.Items[j]) or _G[name .. "Item" .. j]
                if not b then break end
                local bag = (b.GetBagID and b:GetBagID()) or frame:GetID()
                SetIcon(b, IsLiveBag(bag) and ns.IsUpgradeIn(bag, b:GetID()))
            end
        end
    end
end
ns.UpdateDefaultBags = UpdateDefaultBags

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
-- Called from Core's PLAYER_LOGIN handler once the saved data is ready.
function ns.InitGear()
    ns.ScanGear()
    C_Timer.After(3, ns.ScanGear) -- equipped items may not be cached at login
    HookTooltips()
    HookBagnon()
    for i = 1, 13 do
        local frame = _G["ContainerFrame" .. i]
        if frame and frame.HookScript then frame:HookScript("OnShow", UpdateDefaultBags) end
    end
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
ev:RegisterEvent("BAG_UPDATE_DELAYED")
ev:RegisterEvent("GET_ITEM_INFO_RECEIVED")
ev:SetScript("OnEvent", function(_, event)
    if not ns.db then return end
    if event == "PLAYER_EQUIPMENT_CHANGED" then
        ns.ScanGear()
    else
        UpdateDefaultBags()
    end
end)
