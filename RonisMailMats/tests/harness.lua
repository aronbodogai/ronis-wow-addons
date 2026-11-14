-- Test runner (run by run.js inside fengari). Returns the number of failures.
local function Require(name)
    local src = assert(READFILE(TEST_DIR .. "/" .. name .. ".lua"))
    return assert(load(src, "@" .. name .. ".lua"))()
end

local mock = Require("wowmock")
local T = { mock = mock, sessions = {}, ADDON = "RonisMailMats", DIR = ADDON_DIR }

---------------------------------------------------------------------------
-- Assertions
---------------------------------------------------------------------------
local function Fmt(v)
    if type(v) == "string" then return ("%q"):format(v) end
    return tostring(v)
end
function T.eq(got, want, what)
    if got ~= want then
        error(("%s: expected %s, got %s"):format(what or "value", Fmt(want), Fmt(got)), 2)
    end
end
function T.ok(v, what)
    if not v then error((what or "assertion") .. " failed", 2) end
end
function T.contains(list, pattern, what)
    for _, s in ipairs(list) do
        if tostring(s):find(pattern) then return s end
    end
    error(("%s: no line matching %q in:\n    %s"):format(what or "list", pattern, table.concat(list, "\n    ")), 2)
end

---------------------------------------------------------------------------
-- Sessions
---------------------------------------------------------------------------
-- T.Login(opts, saved) -> session; saved = table of saved variables
function T.Login(opts, saved)
    opts.saved = mock.CopySaved(saved or {})
    local S = mock.NewSession(opts)
    S.flavor = opts.flavor or "forever"
    T.sessions[#T.sessions + 1] = S
    S.Login(T.DIR, T.ADDON)
    return S
end
-- Saved variables written at logout.
function T.Logout(S)
    return { RonisMailMatsDB = mock.CopySaved(S.env.RonisMailMatsDB) }
end

-- Panel helpers
function T.Panel(S) return S.env.RonisMailMatsPanel end
function T.Buttons(S)
    local out = {}
    for _, f in ipairs(S.frames) do
        if f._type == "Button" and f._parent == T.Panel(S) and f._shown and rawget(f, "prof") ~= nil then
            out[#out + 1] = f
        end
    end
    return out
end
function T.Button(S, pattern)
    for _, b in ipairs(T.Buttons(S)) do
        if (b._text or ""):find(pattern) then return b end
    end
    local texts = {}
    for _, b in ipairs(T.Buttons(S)) do texts[#texts + 1] = b._text end
    error(("no panel button matching %q (have: %s)"):format(pattern, table.concat(texts, ", ")), 2)
end

---------------------------------------------------------------------------
-- Run specs
---------------------------------------------------------------------------
local tests = {}
function T.test(name, fn) tests[#tests + 1] = { name = name, fn = fn } end
local specFn = Require("spec")
specFn(T)

local failures = 0
for _, t in ipairs(tests) do
    local ok, err = xpcall(t.fn, debug.traceback)
    if ok then
        print("ok   " .. t.name)
    else
        failures = failures + 1
        print("FAIL " .. t.name .. "\n     " .. tostring(err):gsub("\n", "\n     "))
    end
end

---------------------------------------------------------------------------
-- API check against the Forever client's API dump
---------------------------------------------------------------------------
-- Globals the addon reads only as a guarded fallback for other clients.
local FALLBACKS = {
    GetNumSkillLines = true, GetSkillLineInfo = true, ExpandSkillHeader = true,
    GetContainerNumSlots = true, GetContainerItemID = true, GetContainerItemInfo = true,
    PickupContainerItem = true, GetItemIcon = true, GetItemInfo = true, ItemLocation = true,
    GetContainerItemLink = true,
    -- FrameXML tables and other addons, all read behind a nil check
    ItemRefTooltip = true, Bagnon = true,
}
for i = 1, 13 do FALLBACKS["ContainerFrame" .. i] = true end
if FOREVER_API then
    local bad = {}
    local seenMock, missingReads = {}, {}
    for _, S in ipairs(T.sessions) do
        if S.flavor == "forever" then
            for _, fn in ipairs(mock.DefinedFunctions(S.env)) do
                if not FOREVER_API[fn] and not seenMock[fn] then
                    seenMock[fn] = true
                    bad[#bad + 1] = "mock defines " .. fn .. ", which the Forever client does not have"
                end
            end
            for name in pairs(S.missing) do missingReads[name] = true end
        end
    end
    for name in pairs(missingReads) do
        if FOREVER_API[name] then
            bad[#bad + 1] = "addon reads " .. name .. " (exists on Forever) but the mock lacks it - extend wowmock.lua"
        elseif not FALLBACKS[name] and not name:match("^SLASH_") and name ~= "RonisMailMatsDB" then
            bad[#bad + 1] = "addon reads global " .. name .. ", which is not in the Forever API (typo or missing API?)"
        end
    end
    table.sort(bad)
    if #bad == 0 then
        print("ok   API check: mock and addon only use functions the Forever client has")
    else
        failures = failures + 1
        print("FAIL API check:\n     " .. table.concat(bad, "\n     "))
    end
else
    print("skip API check (no Forever API dump)")
end

return failures
