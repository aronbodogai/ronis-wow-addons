-- Minimal mock of the WoW Forever client for offline tests.
--
-- mock.NewSession(opts) builds a fresh global environment for one login of
-- one character. Addon files run inside it with their own globals, so
-- several logins (characters) can be simulated with saved variables carried
-- over between them, like the real client does.
--
-- opts = {
--   flavor   = "forever" (GetProfessions API) | "classic" (skill line API),
--   name, surname (Forever: UnitName gives both), realm, faction, class, level,
--   profs    = { { line = 197, name = "Tailoring", rank = 150, max = 225 }, ... },
--   profsReadyAt = seconds after login before the profession API answers,
--   skills   = { { id = 633, name = "Lockpicking", rank = 80, max = 100 } }:
--              plain skill lines, read with C_SkillInfo (forever flavor);
--   skillsByID = false: C_SkillInfo.GetSkillLineInfoByID always returns nil
--   bags     = { [0] = { [slot] = { id = 2589, count = 20, bound = false } } },
--   saved    = { RonisMailMatsDB = ... },   -- from a previous session
--   mailLag  = true: HasSendMailItem only updates on the next timer tick
--   equipped = { [inventory slot] = itemID }
--   bagnon   = true: a minimal Bagnon (Bagnon.Item with UpdateUpgradeIcon)
--   friends  = { { name, className, level, connected } }
--   bnet     = { { characterName, realmName, factionName, className, characterLevel } }
--   guild    = { { name ("Name-Realm"), level, class, classFile, online } }
--   inbox    = { { sender, isGM } }
-- }
local mock = {}

local ITEMS = {
    [2589] = { "Linen Cloth", 1 }, [2592] = { "Wool Cloth", 1 }, [4306] = { "Silk Cloth", 1 },
    [4338] = { "Mageweave Cloth", 1 }, [2996] = { "Bolt of Linen Cloth", 1 },
    [2318] = { "Light Leather", 1 }, [2319] = { "Medium Leather", 1 },
    [2770] = { "Copper Ore", 1 }, [2840] = { "Copper Bar", 1 },
    [765] = { "Silverleaf", 1 }, [2447] = { "Peacebloom", 1 }, [785] = { "Mageroyal", 1 },
    [10940] = { "Strange Dust", 1 }, [6948] = { "Hearthstone", 1 },
    [2320] = { "Coarse Thread", 1 }, [3371] = { "Crystal Vial", 1 },
    [4632] = { "Ornate Bronze Lockbox", 2 }, [16882] = { "Battered Junkbox", 1 },
    [4636] = { "Strong Iron Lockbox", 2 },
    [211780] = { "Scroll: KWYJIBO", 1 }, [213543] = { "Scroll: UPDOG", 1 },
    -- gear: { name, quality, ilvl, minLevel, equipLoc, classID, subclassID, bindType }
    [9001] = { "Cloth Hood", 2, 20, 15, "INVTYPE_HEAD", 4, 1, 2 },
    [9002] = { "Old Cloth Hood", 1, 10, 5, "INVTYPE_HEAD", 4, 1, 2 },
    [9003] = { "Leather Cap", 2, 25, 15, "INVTYPE_HEAD", 4, 2, 2 },
    [9004] = { "High Level Hood", 3, 60, 55, "INVTYPE_HEAD", 4, 1, 2 },
    [9005] = { "Bound Hood", 3, 30, 15, "INVTYPE_HEAD", 4, 1, 1 },
    [9006] = { "Fine Ring", 2, 22, 10, "INVTYPE_FINGER", 4, 0, 2 },
    [9007] = { "Iron Shield", 2, 22, 10, "INVTYPE_SHIELD", 4, 6, 2 },
    [9008] = { "Oak Staff", 2, 22, 10, "INVTYPE_2HWEAPON", 2, 10, 2 },
    [9009] = { "Spellbook", 2, 25, 10, "INVTYPE_HOLDABLE", 4, 0, 2 },
}

-- Lua builtins visible to addon code (WoW runs Lua 5.1 plus a few helpers).
local function Builtins(printLog)
    return {
        string = string, table = table, math = math, os = { time = os.time, date = os.date },
        pairs = pairs, ipairs = ipairs, next = next, select = select, type = type,
        tostring = tostring, tonumber = tonumber, pcall = pcall, xpcall = xpcall,
        error = error, assert = assert, setmetatable = setmetatable,
        getmetatable = getmetatable, rawget = rawget, rawset = rawset, rawequal = rawequal,
        unpack = table.unpack, time = os.time, date = os.date,
        format = string.format, strlen = string.len, strlower = string.lower,
        strupper = string.upper, strsub = string.sub, strfind = string.find,
        floor = math.floor, max = math.max, min = math.min, tinsert = table.insert,
        tremove = table.remove, sort = table.sort,
        strtrim = function(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end,
        wipe = function(t) for k in pairs(t) do t[k] = nil end return t end,
        print = function(...)
            local parts = {}
            for i = 1, select("#", ...) do parts[#parts + 1] = tostring(select(i, ...)) end
            printLog[#printLog + 1] = table.concat(parts, " ")
        end,
    }
end

function mock.NewSession(opts)
    local S = {
        now = 0, timers = {}, frames = {}, printLog = {}, missing = {},
        sent = {}, attach = {}, pendingAttach = nil, cursor = nil,
        opts = opts, errors = {},
    }
    local env = {}
    local builtins = Builtins(S.printLog)
    S.env = env

    setmetatable(env, { __index = function(_, k)
        local v = builtins[k]
        if v ~= nil then return v end
        S.missing[k] = true -- read of a global the mock does not define
        return nil
    end })
    env._G = env

    -------------------------------------------------------------------------
    -- Timers and events
    -------------------------------------------------------------------------
    env.C_Timer = {
        After = function(sec, fn)
            S.timers[#S.timers + 1] = { due = S.now + sec, fn = fn, seq = #S.timers }
        end,
    }

    function S.Advance(sec)
        local target = S.now + (sec or 0)
        while true do
            if S.pendingAttach then -- server confirms attachments
                for i, v in pairs(S.pendingAttach) do S.committed[i] = v or nil end
                S.pendingAttach = nil
            end
            local best, bi
            for i, t in ipairs(S.timers) do
                if t.due <= target and (not best or t.due < best.due) then best, bi = t, i end
            end
            if not best then break end
            table.remove(S.timers, bi)
            S.now = math.max(S.now, best.due)
            best.fn()
        end
        S.now = target
    end

    function S.Fire(event, ...)
        for _, f in ipairs(S.frames) do
            if f._events[event] and f._scripts.OnEvent then
                f._scripts.OnEvent(f, event, ...)
            end
        end
    end

    -------------------------------------------------------------------------
    -- Widgets
    -------------------------------------------------------------------------
    local Region = {}
    Region.__index = function(self, k)
        local m = Region[k]
        if m then return m end
        if type(k) == "string" and k:sub(1, 1) == "_" then return nil end -- unset mock field
        if type(k) == "string" and k:find("^RonisMailMats") then return nil end -- addon's own field
        local kindMethods = rawget(self, "_kindMethods")
        if kindMethods and kindMethods[k] then return kindMethods[k] end
        error(("mock: %s has no method %s"):format(self._type, tostring(k)), 2)
    end

    local function IsVisible(self)
        if not self._shown then return false end
        if self._parent then return IsVisible(self._parent) end
        return true
    end
    local function FireShow(self)
        if self._scripts and self._scripts.OnShow then self._scripts.OnShow(self) end
        for _, c in ipairs(self._children or {}) do
            if c._shown then FireShow(c) end
        end
    end

    function Region:Show()
        if self._shown then return end
        self._shown = true
        if IsVisible(self) then FireShow(self) end
    end
    function Region:Hide() self._shown = false end
    function Region:SetShown(v) if v then self:Show() else self:Hide() end end
    function Region:IsShown() return self._shown end
    function Region:IsVisible() return IsVisible(self) end
    function Region:SetPoint(...) self._points[#self._points + 1] = { ... } end
    function Region:ClearAllPoints() self._points = {} end
    function Region:GetNumPoints() return #self._points end
    function Region:SetSize(w, h) self._w, self._h = w, h end
    function Region:SetWidth(w) self._w = w end
    function Region:SetHeight(h) self._h = h end
    function Region:GetWidth() return self._w or 0 end
    function Region:GetHeight() return self._h or 0 end
    function Region:GetParent() return self._parent end
    function Region:GetName() return self._name end
    function Region:SetAlpha(a) self._alpha = a end
    function Region:GetAlpha() return self._alpha or 1 end
    function Region:IsMouseOver() return self._mouseOver or false end
    function Region:GetObjectType() return self._type end

    local FontStringMethods = {
        SetText = function(self, t) self._text = t end,
        GetText = function(self) return self._text end,
        SetJustifyH = function() end, SetJustifyV = function() end,
        SetWordWrap = function() end, SetTextColor = function() end,
        SetFontObject = function() end,
        GetStringHeight = function(self)
            local len = #(tostring(self._text or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
            local per = math.max(1, math.floor((self._w or 200) / 6))
            return 13 * math.max(1, math.ceil(len / per))
        end,
    }

    local FrameMethods = {}
    function FrameMethods:SetScript(name, fn) self._scripts[name] = fn end
    function FrameMethods:GetScript(name) return self._scripts[name] end
    function FrameMethods:HookScript(name, fn)
        local old = self._scripts[name]
        self._scripts[name] = function(...) if old then old(...) end fn(...) end
    end
    function FrameMethods:RegisterEvent(e) self._events[e] = true end
    function FrameMethods:UnregisterEvent(e) self._events[e] = nil end
    function FrameMethods:UnregisterAllEvents() self._events = {} end
    function FrameMethods:IsEventRegistered(e) return self._events[e] or false end
    function FrameMethods:EnableMouse() end
    function FrameMethods:SetMovable() end
    function FrameMethods:RegisterForDrag() end
    function FrameMethods:RegisterForClicks() end
    function FrameMethods:SetClampedToScreen() end
    function FrameMethods:SetFrameStrata() end
    function FrameMethods:SetFrameLevel() end
    function FrameMethods:StartMoving() end
    function FrameMethods:StopMovingOrSizing() end
    function FrameMethods:GetCenter() return 100, 100 end
    function FrameMethods:GetEffectiveScale() return 1 end
    function FrameMethods:GetFrameLevel() return 1 end
    function FrameMethods:CreateFontString(name)
        local fs = setmetatable({ _type = "FontString", _shown = true, _points = {}, _parent = self,
            _kindMethods = FontStringMethods, _name = name }, Region)
        if name then env[name] = fs end
        return fs
    end
    function FrameMethods:CreateTexture()
        return setmetatable({ _type = "Texture", _shown = true, _points = {}, _parent = self,
            _kindMethods = { SetTexture = function() end, SetAllPoints = function() end,
                SetColorTexture = function() end, SetTexCoord = function() end } }, Region)
    end
    -- BackdropTemplate only
    local BackdropMethods = {
        SetBackdrop = function(self, b) self._backdrop = b end,
        SetBackdropColor = function() end, SetBackdropBorderColor = function() end,
    }
    local ButtonMethods = {
        SetText = function(self, t) self._text = t end,
        GetText = function(self) return self._text end,
        SetEnabled = function(self, v) self._enabled = v and true or false end,
        Enable = function(self) self._enabled = true end,
        Disable = function(self) self._enabled = false end,
        IsEnabled = function(self) return self._enabled end,
        Click = function(self, button)
            if self._enabled and self._scripts.OnClick then self._scripts.OnClick(self, button or "LeftButton", false) end
        end,
        SetNormalFontObject = function() end,
    }
    local CheckButtonMethods = {
        SetChecked = function(self, v) self._checked = v and true or false end,
        GetChecked = function(self) return self._checked end,
        Click = function(self, button)
            if not self._enabled then return end
            self._checked = not self._checked
            if self._scripts.OnClick then self._scripts.OnClick(self, button or "LeftButton", false) end
        end,
    }
    local EditBoxMethods = {
        SetText = function(self, t) self._text = t end,
        GetText = function(self) return self._text or "" end,
        SetFocus = function() end, ClearFocus = function() end,
        SetAutoFocus = function() end, SetMaxLetters = function() end,
    }

    local function Merge(...)
        local out = {}
        for i = 1, select("#", ...) do
            for k, v in pairs((select(i, ...))) do out[k] = v end
        end
        return out
    end

    local KNOWN_TEMPLATES = { BackdropTemplate = true, UIPanelButtonTemplate = true, UICheckButtonTemplate = true,
        InputBoxTemplate = true }

    function env.CreateFrame(kind, name, parent, template)
        if template then
            for t in template:gmatch("[^,%s]+") do
                if not KNOWN_TEMPLATES[t] then error("mock: unknown template " .. t, 2) end
            end
        end
        local methods = { FrameMethods }
        if template and template:find("BackdropTemplate") then methods[#methods + 1] = BackdropMethods end
        if kind == "Button" then methods[#methods + 1] = ButtonMethods end
        if kind == "CheckButton" then
            methods[#methods + 1] = ButtonMethods
            methods[#methods + 1] = CheckButtonMethods
        end
        if kind == "EditBox" then methods[#methods + 1] = EditBoxMethods end
        local f = setmetatable({
            _type = kind, _name = name, _parent = parent, _shown = true, _points = {},
            _scripts = {}, _events = {}, _children = {}, _enabled = true,
            _kindMethods = Merge(table.unpack(methods)),
        }, Region)
        if template and template:find("UICheckButtonTemplate") then
            f.text = f:CreateFontString()
            f.Text = f.text
        end
        if parent then table.insert(parent._children, f) end
        S.frames[#S.frames + 1] = f
        if name then env[name] = f end
        return f
    end

    env.UIParent = env.CreateFrame("Frame", "UIParent")

    env.Minimap = env.CreateFrame("Frame", "Minimap", env.UIParent)
    env.UISpecialFrames = {}
    env.GetCursorPosition = function() return 0, 0 end

    env.GameTooltip = env.CreateFrame("Frame", "GameTooltip", env.UIParent)
    env.GameTooltip:Hide()
    env.GameTooltip._kindMethods.SetOwner = function(self, owner) self._owner = owner; self._lines = {} end
    env.GameTooltip._kindMethods.GetItem = function(self)
        if self._item then return env.C_Item.GetItemInfo(self._item) end
    end
    env.GameTooltip._kindMethods.SetItemByID = function(self, id) self._item = id end
    env.GameTooltip._kindMethods.ClearLines = function(self) self._lines = {} end
    env.GameTooltip._kindMethods.AddLine = function(self, t) table.insert(self._lines, t) end
    env.GameTooltip._kindMethods.AddDoubleLine = function(self, a, b) table.insert(self._lines, a .. " | " .. b) end

    env.RAID_CLASS_COLORS = {
        MAGE = { r = 0.25, g = 0.78, b = 0.92, colorStr = "ff3fc7eb" },
        WARRIOR = { r = 0.78, g = 0.61, b = 0.43, colorStr = "ffc69b6d" },
        PRIEST = { r = 1, g = 1, b = 1, colorStr = "ffffffff" },
    }
    env.ITEM_QUALITY_COLORS = { [1] = { r = 1, g = 1, b = 1 } }
    env.ATTACHMENTS_MAX_SEND = 12
    env.NUM_BAG_SLOTS = 4
    env.SlashCmdList = {}

    -------------------------------------------------------------------------
    -- Player, items
    -------------------------------------------------------------------------
    env.GetRealmName = function() return opts.realm or "Test Realm" end
    env.UnitName = function(u) if u == "player" then return opts.name, opts.surname end end
    env.UnitClass = function(u)
        if u == "player" then
            local c = opts.class or "MAGE"
            return c:sub(1, 1) .. c:sub(2):lower(), c, 8
        end
    end
    env.UnitFactionGroup = function(u) if u == "player" then return opts.faction or "Alliance", opts.faction or "Alliance" end end
    env.UnitLevel = function(u) if u == "player" then return opts.level or 60 end end
    env.InCombatLockdown = function() return S.inCombat or false end

    local function ItemLink(id)
        local it = ITEMS[id]
        return it and ("|cffffffff|Hitem:%d::::::::60:::::|h[%s]|h|r"):format(id, it[1])
    end
    local function GetItemInfo(ref)
        local id = type(ref) == "number" and ref or tonumber(tostring(ref):match("item:(%d+)") or ref)
        local it = id and ITEMS[id]
        if not it then return nil end
        if it[5] then
            return it[1], ItemLink(id), it[2], it[3], it[4], "Armor", "Misc", 1, it[5], 134400, 10, it[6], it[7], it[8]
        end
        return it[1], ItemLink(id), it[2], 10, 1, "Trade Goods", "Cloth", 200, "", 134400, 10, 7, 5, 0
    end
    env.C_Item = {
        GetItemInfo = GetItemInfo,
        GetItemIconByID = function(id) return ITEMS[id] and 134400 or nil end,
        IsBound = function() return false end,
        GetDetailedItemLevelInfo = function(ref)
            local _, _, _, ilvl = GetItemInfo(ref)
            return ilvl
        end,
    }
    local equipped = opts.equipped or {}
    env.GetInventoryItemLink = function(unit, slot)
        if unit == "player" and equipped[slot] then return ItemLink(equipped[slot]) end
    end
    env.hooksecurefunc = function(t, name, fn)
        if type(t) == "string" then t, name, fn = env, t, name end
        local old = t[name]
        t[name] = function(...) local r = { old(...) }; fn(...); return table.unpack(r) end
    end
    -- Item tooltips: FrameXML's TooltipDataProcessor post calls.
    env.Enum = { TooltipDataType = { Item = 0 } }
    local postCalls = {}
    env.TooltipDataProcessor = {
        AddTooltipPostCall = function(kind, fn) postCalls[#postCalls + 1] = { kind, fn } end,
    }
    function S.ShowItemTooltip(id)
        local tt = env.GameTooltip
        tt:SetOwner(env.UIParent)
        tt._item = id
        for _, p in ipairs(postCalls) do if p[1] == env.Enum.TooltipDataType.Item then p[2](tt) end end
        return tt._lines
    end
    if opts.bagnon then
        env.Bagnon = { Item = { UpdateUpgradeIcon = function(self) end } }
    end
    -- No global GetItemInfo / GetItemIcon: the Forever client only has the
    -- C_Item versions (the API check enforces this).

    -------------------------------------------------------------------------
    -- Professions
    -------------------------------------------------------------------------
    local function ProfsReady() return S.now >= (opts.profsReadyAt or 0) end
    local profs = opts.profs or {}
    if (opts.flavor or "forever") == "forever" then
        -- order: prof1, prof2, archaeology, fishing, cooking, first aid
        local SECONDARY = { [356] = 4, [185] = 5, [129] = 6 }
        env.GetProfessions = function()
            if not ProfsReady() then return end
            local slots, primary = {}, 0
            for i, p in ipairs(profs) do
                local s = SECONDARY[p.line]
                if not s then primary = primary + 1; s = primary end
                slots[s] = i
            end
            return slots[1], slots[2], slots[3], slots[4], slots[5], slots[6]
        end
        env.GetProfessionInfo = function(i)
            local p = profs[i]
            if not p then return end
            return p.name, 136240, p.rank, p.max, 5, 0, p.line, 0
        end
        -- Plain skill lines (Lockpicking, Comprehension, weapon skills).
        local skillList = { { name = "Secondary Skills", isHeader = true } }
        for _, s in ipairs(opts.skills or {}) do
            skillList[#skillList + 1] = { name = s.name, rank = s.rank, maxRank = s.max, skillID = s.id,
                                          isHeader = false, modifier = 0 }
        end
        skillList[#skillList + 1] = { name = "Swords", rank = 100, maxRank = 300, skillID = 43, isHeader = false, modifier = 0 }
        env.C_SkillInfo = {
            GetNumSkillLines = function() return ProfsReady() and #skillList or 0 end,
            GetSkillLineInfo = function(i) return ProfsReady() and skillList[i] or nil end,
            GetSkillLineInfoByID = function(id)
                if opts.skillsByID == false or not ProfsReady() then return nil end
                for _, s in ipairs(skillList) do
                    if s.skillID == id then return s end
                end
            end,
        }
    else
        local lines = {}
        local function Build()
            lines = { { name = "Professions", header = true, expanded = not opts.collapsed } }
            if not opts.collapsed then
                for _, p in ipairs(profs) do
                    lines[#lines + 1] = { name = p.name, rank = p.rank, max = p.max }
                end
            end
            lines[#lines + 1] = { name = "Weapon Skills", header = true, expanded = true }
            lines[#lines + 1] = { name = "Swords", rank = 100, max = 300 }
        end
        Build()
        env.GetNumSkillLines = function() return ProfsReady() and #lines or 0 end
        env.GetSkillLineInfo = function(i)
            local l = lines[i]
            if not l then return end
            return l.name, l.header or false, l.expanded or false, l.rank or 0, 0, 0, l.max or 0
        end
        env.ExpandSkillHeader = function() opts.collapsed = false; Build() end
    end

    -------------------------------------------------------------------------
    -- Bags and cursor
    -------------------------------------------------------------------------
    local bags = opts.bags or {}
    S.bags = bags
    local function Slot(bag, slot) return bags[bag] and bags[bag][slot] end

    env.C_Container = {
        GetContainerNumSlots = function(bag)
            if bag < 0 or bag > env.NUM_BAG_SLOTS then return 0 end
            return bag == 0 and 16 or (bags[bag] and 16 or 0)
        end,
        GetContainerItemID = function(bag, slot)
            local s = Slot(bag, slot)
            return s and s.id or nil
        end,
        GetContainerItemLink = function(bag, slot)
            local s = Slot(bag, slot)
            return s and ItemLink(s.id) or nil
        end,
        GetContainerItemInfo = function(bag, slot)
            local s = Slot(bag, slot)
            if not s then return nil end
            return { iconFileID = 134400, stackCount = s.count or 1, isLocked = s.locked or false,
                quality = 1, isReadable = false, hasLoot = false, hyperlink = ItemLink(s.id),
                isFiltered = false, hasNoValue = false, itemID = s.id, isBound = s.bound or false }
        end,
        PickupContainerItem = function(bag, slot)
            local s = Slot(bag, slot)
            if S.cursor then -- drop cursor item into the slot (only same-slot put-back here)
                if S.cursor.bag == bag and S.cursor.slot == slot then
                    S.cursor.item.locked = false
                    S.cursor = nil
                end
                return
            end
            if s and not s.locked then
                s.locked = true
                S.cursor = { bag = bag, slot = slot, item = s }
            end
        end,
    }
    env.CursorHasItem = function() return S.cursor ~= nil end
    S.moving = false
    env.IsPlayerMoving = function() return S.moving end
    env.GetCursorInfo = function()
        if S.cursor then return "item", S.cursor.item.id end
    end
    env.ClearCursor = function()
        if S.cursor then S.cursor.item.locked = false; S.cursor = nil end
    end

    -------------------------------------------------------------------------
    -- Mail
    -------------------------------------------------------------------------
    S.committed = {} -- what HasSendMailItem reports
    local function Committed()
        return S.committed
    end
    local function SetAttach(i, v)
        S.attach[i] = v
        if opts.mailLag then
            S.pendingAttach = S.pendingAttach or {}
            S.pendingAttach[i] = v or false
        else
            S.committed[i] = v
        end
    end
    env.HasSendMailItem = function(i) return Committed()[i] ~= nil end
    env.ClickSendMailItemButton = function(i, clear)
        i = i or 1
        if clear then
            local a = S.attach[i]
            if a then
                bags[a.bag] = bags[a.bag] or {}
                bags[a.bag][a.slot] = a.item
                a.item.locked = false
                SetAttach(i, nil)
            end
            return
        end
        if not S.cursor then return end
        if S.attach[i] then error("mock: dropped an item on occupied attachment slot " .. i) end
        local c = S.cursor
        if c.item.bound then
            S.errors[#S.errors + 1] = "You can't mail soulbound items."
            return -- cursor keeps the item, like the real client
        end
        bags[c.bag][c.slot] = nil
        c.item.locked = false
        SetAttach(i, c)
        S.cursor = nil
    end
    env.SendMail = function(to, subject, body) S.sent[#S.sent + 1] = { to = to, subject = subject } end

    -- Mail frame tree (subset of Blizzard_MailFrame)
    env.MailFrame = env.CreateFrame("Frame", "MailFrame", env.UIParent)
    env.MailFrame:Hide()
    env.InboxFrame = env.CreateFrame("Frame", "InboxFrame", env.MailFrame)
    env.SendMailFrame = env.CreateFrame("Frame", "SendMailFrame", env.MailFrame)
    env.SendMailFrame:Hide()
    env.SendMailNameEditBox = env.CreateFrame("EditBox", "SendMailNameEditBox", env.SendMailFrame)
    env.SendMailSubjectEditBox = env.CreateFrame("EditBox", "SendMailSubjectEditBox", env.SendMailFrame)
    env.SendMailBodyEditBox = env.CreateFrame("EditBox", "SendMailBodyEditBox", env.SendMailFrame)
    env.MailFrameTab1 = env.CreateFrame("Button", "MailFrameTab1", env.MailFrame)
    env.MailFrameTab2 = env.CreateFrame("Button", "MailFrameTab2", env.MailFrame)
    env.MailFrameTab1:SetScript("OnClick", function() env.InboxFrame:Show(); env.SendMailFrame:Hide() end)
    env.MailFrameTab2:SetScript("OnClick", function() env.InboxFrame:Hide(); env.SendMailFrame:Show() end)

    function S.OpenMailbox()
        env.InboxFrame:Show()
        env.SendMailFrame:Hide()
        env.MailFrame:Show()
        S.Fire("MAIL_SHOW")
        S.Advance(0.2)
    end
    function S.CloseMailbox()
        env.MailFrame:Hide()
        S.Fire("MAIL_CLOSED")
    end
    function S.Attachments()
        local out = {}
        for i = 1, 12 do
            local a = S.attach[i]
            if a then out[#out + 1] = { slot = i, id = a.item.id, count = a.item.count } end
        end
        return out
    end

    -------------------------------------------------------------------------
    -- Friends, Battle.net, guild, inbox
    -------------------------------------------------------------------------
    env.LOCALIZED_CLASS_NAMES_MALE = { MAGE = "Mage", ROGUE = "Rogue", WARRIOR = "Warrior", PRIEST = "Priest" }
    env.LOCALIZED_CLASS_NAMES_FEMALE = { MAGE = "Mage", ROGUE = "Rogue", WARRIOR = "Warrior", PRIEST = "Priest" }
    env.GetNormalizedRealmName = function() return (env.GetRealmName():gsub("[%s%-]", "")) end
    local friends = opts.friends or {}
    env.C_FriendList = {
        GetNumFriends = function() return #friends end,
        GetFriendInfoByIndex = function(i)
            local f = friends[i]
            return f and { name = f[1], className = f[2], level = f[3], connected = f[4] or false } or nil
        end,
    }
    local bnet = opts.bnet or {}
    env.BNGetNumFriends = function() return #bnet, #bnet end
    env.C_BattleNet = {
        GetFriendNumGameAccounts = function(i) return bnet[i] and 1 or 0 end,
        GetFriendGameAccountInfo = function(i, j)
            local g = bnet[i]
            if not g or j ~= 1 then return nil end
            return { characterName = g[1], realmName = g[2], factionName = g[3], className = g[4],
                     characterLevel = g[5], clientProgram = "WoW" }
        end,
    }
    local guild = opts.guild or {}
    env.IsInGuild = function() return #guild > 0 end
    env.GetNumGuildMembers = function() return #guild, #guild end
    env.GetGuildRosterInfo = function(i)
        local g = guild[i]
        if not g then return nil end
        return g[1], "Member", 1, g[2], g[3], "Elwynn", "", "", g[5] or false, 0, g[4]
    end
    S.rosterRequests = 0
    env.C_GuildInfo = { GuildRoster = function() S.rosterRequests = S.rosterRequests + 1 end }
    local inbox = opts.inbox or {}
    env.GetInboxNumItems = function() return #inbox, #inbox end
    env.GetInboxHeaderInfo = function(i)
        local mail = inbox[i]
        if not mail then return nil end
        return nil, nil, mail[1], "subject", 0, 0, 30, false, true, false, false, false, mail[2] or false
    end

    -------------------------------------------------------------------------
    -- Saved variables, addon loading, login
    -------------------------------------------------------------------------
    for k, v in pairs(opts.saved or {}) do env[k] = v end

    function S.Load(addonDir, addonName)
        local toc = assert(READFILE(addonDir .. "/" .. addonName .. ".toc"))
        local ns = {}
        for line in toc:gmatch("[^\r\n]+") do
            if not line:match("^%s*#") and line:match("%S") then
                local file = line:gsub("\\", "/"):match("^%s*(.-)%s*$")
                local src = assert(READFILE(addonDir .. "/" .. file), "missing file " .. file)
                local chunk, err = load(src, "@" .. addonName .. "/" .. file, "t", env)
                if not chunk then error(err, 0) end
                chunk(addonName, ns)
            end
        end
        S.ns = ns
        return ns
    end

    function S.Login(addonDir, addonName)
        S.Load(addonDir, addonName)
        S.Fire("ADDON_LOADED", addonName)
        S.Fire("PLAYER_LOGIN")
        S.Fire("PLAYER_ENTERING_WORLD", true, false)
        S.Advance(20)
    end

    function S.Slash(cmd, msg)
        for k, fn in pairs(env.SlashCmdList) do
            for i = 1, 9 do
                if env["SLASH_" .. k .. i] == cmd then return fn(msg or "") end
            end
        end
        error("unknown slash command " .. cmd)
    end

    return S
end

-- Deep copy of saved variables between sessions (data only, like the client).
function mock.CopySaved(v)
    if type(v) ~= "table" then
        if type(v) == "function" or type(v) == "userdata" then return nil end
        return v
    end
    local out = {}
    for k, x in pairs(v) do out[mock.CopySaved(k)] = mock.CopySaved(x) end
    return out
end

-- Every function the mock defines, as "Name" or "C_X.Name" (for the API check).
function mock.DefinedFunctions(env)
    local out = {}
    for k, v in pairs(env) do
        if type(k) == "string" and type(v) == "function" then out[#out + 1] = k end
        if type(k) == "string" and k:match("^C_") and type(v) == "table" then
            for k2, v2 in pairs(v) do
                if type(v2) == "function" then out[#out + 1] = k .. "." .. k2 end
            end
        end
    end
    table.sort(out)
    return out
end

return mock
