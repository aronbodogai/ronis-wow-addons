-- Minimal mock of the WoW Forever client for Roni's Health's offline tests.
--
-- mock.NewSession(opts) builds a fresh global environment for one login.
-- Addon files run inside it with their own globals; saved variables are
-- carried between sessions like the real client does.
--
-- opts = {
--   saved  = { RonisHealthDB = ... },  -- from a previous session
--   epoch  = wall clock (time()) at login, default 1800000000
-- }
-- Session controls: S.Advance(sec), S.Fire(event, ...), S.SetCombat(bool),
-- S.SetAFK(bool), S.SetInstance(kind or nil, name), S.Slash(cmd, msg).
local mock = {}

local function Builtins(S)
    return {
        string = string, table = table, math = math,
        pairs = pairs, ipairs = ipairs, next = next, select = select, type = type,
        tostring = tostring, tonumber = tonumber, pcall = pcall, xpcall = xpcall,
        error = error, assert = assert, setmetatable = setmetatable,
        getmetatable = getmetatable, rawget = rawget, rawset = rawset, rawequal = rawequal,
        unpack = table.unpack, format = string.format, strlen = string.len,
        strlower = string.lower, strupper = string.upper, strsub = string.sub, strfind = string.find,
        floor = math.floor, max = math.max, min = math.min, tinsert = table.insert,
        tremove = table.remove, sort = table.sort,
        strtrim = function(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end,
        wipe = function(t) for k in pairs(t) do t[k] = nil end return t end,
        -- wall clock follows the session clock so tests can move through time
        time = function() return S.epoch + math.floor(S.now) end,
        date = function(fmt, t) return os.date(fmt, t or (S.epoch + math.floor(S.now))) end,
        print = function(...)
            local parts = {}
            for i = 1, select("#", ...) do parts[#parts + 1] = tostring(select(i, ...)) end
            S.printLog[#S.printLog + 1] = table.concat(parts, " ")
        end,
    }
end

function mock.NewSession(opts)
    local S = {
        now = 0, epoch = opts.epoch or 1800000000, timers = {}, frames = {}, printLog = {},
        missing = {}, sounds = {}, flashes = 0, opts = opts,
        combat = false, afk = false, instance = nil,
    }
    local env = {}
    local builtins = Builtins(S)
    S.env = env

    setmetatable(env, { __index = function(_, k)
        local v = builtins[k]
        if v ~= nil then return v end
        S.missing[k] = true -- read of a global the mock does not define
        return nil
    end })
    env._G = env
    for k, v in pairs(opts.saved or {}) do env[k] = v end

    -------------------------------------------------------------------------
    -- Time, timers, events
    -------------------------------------------------------------------------
    env.GetTime = function() return S.now end
    env.C_Timer = {
        After = function(sec, fn)
            S.timers[#S.timers + 1] = { due = S.now + sec, fn = fn }
        end,
    }

    -- Run the clock forward, firing timers in order (one second at a time is
    -- what the addon's own ticker does, so this follows it exactly).
    function S.Advance(sec)
        local target = S.now + (sec or 0)
        while true do
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
        if type(k) == "string" and k:sub(1, 1) == "_" then return nil end
        local kindMethods = rawget(self, "_kindMethods")
        if kindMethods and kindMethods[k] then return kindMethods[k] end
        return nil -- addon's own fields on frames
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
    function Region:SetSize(w, h) self._w, self._h = w, h end
    function Region:SetWidth(w) self._w = w end
    function Region:SetHeight(h) self._h = h end
    function Region:GetWidth() return self._w or 0 end
    function Region:GetHeight() return self._h or 0 end
    function Region:GetLeft() return 100 end
    function Region:GetTop() return 700 end
    function Region:GetParent() return self._parent end
    function Region:GetName() return self._name end
    function Region:SetAlpha(a) self._alpha = a end
    function Region:GetAlpha() return self._alpha or 1 end

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
    function FrameMethods:EnableMouse() end
    function FrameMethods:SetMovable() end
    function FrameMethods:RegisterForDrag() end
    function FrameMethods:SetClampedToScreen() end
    function FrameMethods:SetFrameStrata() end
    function FrameMethods:StartMoving() end
    function FrameMethods:StopMovingOrSizing() end
    function FrameMethods:CreateFontString(name)
        local fs = setmetatable({ _type = "FontString", _shown = true, _points = {}, _parent = self,
            _kindMethods = FontStringMethods, _name = name }, Region)
        self._children[#self._children + 1] = fs
        return fs
    end
    function FrameMethods:CreateTexture()
        return setmetatable({ _type = "Texture", _shown = true, _points = {}, _parent = self,
            _kindMethods = { SetTexture = function(t, p) t._texture = p end,
                SetAllPoints = function() end, SetColorTexture = function() end } }, Region)
    end
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

    local function Merge(...)
        local out = {}
        for i = 1, select("#", ...) do
            for k, v in pairs((select(i, ...))) do out[k] = v end
        end
        return out
    end

    local KNOWN_TEMPLATES = { BackdropTemplate = true, UIPanelButtonTemplate = true, UICheckButtonTemplate = true }

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
        local f = setmetatable({
            _type = kind, _name = name, _parent = parent, _shown = true, _points = {},
            _scripts = {}, _events = {}, _children = {}, _enabled = true,
            _kindMethods = Merge(table.unpack(methods)),
        }, Region)
        if template and template:find("UICheckButtonTemplate") then
            -- modern templates name it Text; the old lowercase alias may be absent
            f.Text = f:CreateFontString()
        end
        if parent then table.insert(parent._children, f) end
        S.frames[#S.frames + 1] = f
        if name then env[name] = f end
        return f
    end

    env.UIParent = env.CreateFrame("Frame", "UIParent")
    env.UISpecialFrames = {}
    env.SlashCmdList = {}
    env.SOUNDKIT = { TELL_MESSAGE = 3081, READY_CHECK = 8960 }

    -------------------------------------------------------------------------
    -- Player state
    -------------------------------------------------------------------------
    env.InCombatLockdown = function() return S.combat end
    env.UnitAffectingCombat = function(u) return u == "player" and S.combat end
    env.UnitIsAFK = function(u) return u == "player" and S.afk end
    env.IsInInstance = function()
        if S.instance then return true, S.instance end
        return false, "none"
    end
    env.GetInstanceInfo = function()
        if S.instance then return S.instanceName or "Test Dungeon", S.instance end
        return "Elwynn Forest", "none"
    end
    env.PlaySound = function(id) S.sounds[#S.sounds + 1] = id; return true end
    env.FlashClientIcon = function() S.flashes = S.flashes + 1 end

    function S.SetCombat(v)
        S.combat = v
        S.Fire(v and "PLAYER_REGEN_DISABLED" or "PLAYER_REGEN_ENABLED")
    end
    function S.SetAFK(v)
        S.afk = v
        S.Fire("PLAYER_FLAGS_CHANGED", "player")
    end
    function S.SetInstance(kind, name) S.instance, S.instanceName = kind, name end

    -- Flight paths: S.taxiNodes = { {name, type}, ... } at the flight master.
    S.onTaxi, S.taxiNodes, S.auras = false, {}, {}
    env.UnitOnTaxi = function(u) return u == "player" and S.onTaxi end
    env.NumTaxiNodes = function() return #S.taxiNodes end
    env.TaxiNodeName = function(i) return S.taxiNodes[i] and S.taxiNodes[i][1] end
    env.TaxiNodeGetType = function(i) return S.taxiNodes[i] and S.taxiNodes[i][2] end
    env.TakeTaxiNode = function() end
    env.hooksecurefunc = function(a, b, c)
        local tbl, name, fn = env, a, b
        if type(a) == "table" then tbl, name, fn = a, b, c end
        local old = tbl[name]
        tbl[name] = function(...)
            local r = { old(...) }
            fn(...)
            return table.unpack(r)
        end
    end
    -- Take a flight from one node to another (the player picks it on the map).
    function S.TakeFlight(from, to)
        S.taxiNodes = { { from, "CURRENT" }, { to, "REACHABLE" } }
        env.TakeTaxiNode(2)
        S.onTaxi = true
    end
    function S.Land() S.onTaxi = false end

    -- Buffs on the player: S.SetAuras({ "Cozy Fire", ... })
    env.C_UnitAuras = {
        GetAuraDataByIndex = function(unit, i)
            local name = unit == "player" and S.auras[i]
            if name then return { name = name, spellId = 1000 + i } end
            return nil
        end,
    }
    function S.SetAuras(list) S.auras = list or {} end
    function S.TurnInQuest() S.Fire("QUEST_TURNED_IN", 1, 0, 0) end

    -------------------------------------------------------------------------
    -- Loading
    -------------------------------------------------------------------------
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
