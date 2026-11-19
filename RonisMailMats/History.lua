-- Mail history: every item you send or take from the mailbox is logged, and
-- a dashboard sums up what went to (or came from) other players over the
-- last day, 7 days, 30 days, 6 months, year and all time.
local _, ns = ...

local GetItemInfo = GetItemInfo or (C_Item and C_Item.GetItemInfo)
local GetItemIcon = GetItemIcon or (C_Item and C_Item.GetItemIconByID)

local MAX_LOG = 20000 -- oldest entries are dropped past this
local DAY = 86400
ns.TIMEFRAMES = {
    { "1 day", DAY }, { "7 days", 7 * DAY }, { "30 days", 30 * DAY },
    { "6 months", 182 * DAY }, { "1 year", 365 * DAY }, { "All time", nil },
}

---------------------------------------------------------------------------
-- Log: ns.db.log = { {t = time, d = "s"|"r", who = name, id = itemID, n = count, me = character}, ... }
---------------------------------------------------------------------------
local function Log()
    ns.db.log = ns.db.log or {}
    return ns.db.log
end

function ns.RecordMail(dir, who, id, n, t)
    if not (who and id and n and n > 0) then return end
    local log = Log()
    log[#log + 1] = { t = t or time(), d = dir, who = who, id = id, n = n, me = ns.me }
    if #log > MAX_LOG then table.remove(log, 1) end
end

-- Whether `name` is one of your characters (any realm). Names may carry a
-- "-Realm" suffix, and older saves keep only first names.
function ns.IsMyChar(name)
    if not name then return false end
    local bare = name:gsub("%-.*$", ""):lower()
    local first = bare:match("^(%S+)")
    for _, chars in pairs(ns.db.chars or {}) do
        for n in pairs(chars) do
            local mine = n:lower()
            if mine == bare or (not mine:find(" ") and mine == first) or (not bare:find(" ") and mine:match("^(%S+)") == bare) then
                return true
            end
        end
    end
    return false
end

---------------------------------------------------------------------------
-- Capture: sent mail when the server confirms it, taken attachments as you
-- take them.
---------------------------------------------------------------------------
local pending

local function OnSendMail(to)
    pending = nil
    if not GetSendMailItem then return end
    local items = {}
    for i = 1, ATTACHMENTS_MAX_SEND or 12 do
        local _, id, _, count = GetSendMailItem(i)
        if id then items[#items + 1] = { id, count or 1 } end
    end
    if #items > 0 then pending = { to = to, items = items } end
end

local function Sender(i)
    local _, _, sender = GetInboxHeaderInfo(i)
    return sender
end

local function OnTake(i, a)
    local sender = Sender(i)
    local _, id, _, count = GetInboxItem(i, a)
    if id then ns.RecordMail("r", sender or "Unknown", id, count or 1) end
end

local function OnAutoLoot(i)
    local sender = Sender(i)
    for a = 1, 16 do -- ATTACHMENTS_MAX_RECEIVE
        local _, id, _, count = GetInboxItem(i, a)
        if id then ns.RecordMail("r", sender or "Unknown", id, count or 1) end
    end
end

function ns.InitHistory()
    if ns.historyHooked then return end
    ns.historyHooked = true
    if SendMail then hooksecurefunc("SendMail", OnSendMail) end
    if TakeInboxItem and GetInboxItem then hooksecurefunc("TakeInboxItem", OnTake) end
    if AutoLootMailItem and GetInboxItem then hooksecurefunc("AutoLootMailItem", OnAutoLoot) end
    local ev = CreateFrame("Frame")
    ev:RegisterEvent("MAIL_SEND_SUCCESS")
    ev:RegisterEvent("MAIL_FAILED")
    ev:SetScript("OnEvent", function(_, event)
        if event == "MAIL_SEND_SUCCESS" and pending then
            for _, it in ipairs(pending.items) do ns.RecordMail("s", pending.to, it[1], it[2]) end
            if ns.RefreshHistory then ns.RefreshHistory() end
        end
        pending = nil
    end)
end

---------------------------------------------------------------------------
-- Summaries
---------------------------------------------------------------------------
-- Totals for direction `dir` ("s" or "r"), one person or everyone (nil),
-- leaving out your own characters unless `alts`.
-- Returns items = { {id, counts = {per timeframe}} } (most first),
-- total = {per timeframe}, people = { {name, all-time count} } (most first).
function ns.HistorySummary(dir, who, alts, now)
    now = now or time()
    local byItem, list, total, byPerson = {}, {}, {}, {}
    for k = 1, #ns.TIMEFRAMES do total[k] = 0 end
    local mine = {}
    for _, e in ipairs(Log()) do
        if e.d == dir then
            if mine[e.who] == nil then mine[e.who] = ns.IsMyChar(e.who) end
            if alts or not mine[e.who] then
                byPerson[e.who] = (byPerson[e.who] or 0) + e.n
                if not who or e.who == who then
                    local row = byItem[e.id]
                    if not row then
                        row = { id = e.id, counts = {} }
                        for k = 1, #ns.TIMEFRAMES do row.counts[k] = 0 end
                        byItem[e.id] = row
                        list[#list + 1] = row
                    end
                    local age = now - e.t
                    for k, tf in ipairs(ns.TIMEFRAMES) do
                        if not tf[2] or age < tf[2] then
                            row.counts[k] = row.counts[k] + e.n
                            total[k] = total[k] + e.n
                        end
                    end
                end
            end
        end
    end
    local last = #ns.TIMEFRAMES
    table.sort(list, function(a, b)
        if a.counts[last] ~= b.counts[last] then return a.counts[last] > b.counts[last] end
        return a.id < b.id
    end)
    local people = {}
    for name, n in pairs(byPerson) do people[#people + 1] = { name, n } end
    table.sort(people, function(a, b) if a[2] ~= b[2] then return a[2] > b[2] end return a[1] < b[1] end)
    return list, total, people
end

---------------------------------------------------------------------------
-- Dashboard window
---------------------------------------------------------------------------
local W, H, PAD = 640, 440, 12
local LEFT_W = 160
local ROWS, ROW_H = 13, 22
local COL_W = 58
local win, rows, people = nil, {}, {}
local state = { dir = "s", who = nil, alts = false, page = 1, ppage = 1 }

local function ItemLabel(id)
    local name, _, quality = GetItemInfo(id)
    local color = (quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality] and ITEM_QUALITY_COLORS[quality].hex) or "|cffffffff"
    return color .. (name or ("item " .. id)) .. "|r"
end

local function SetCounts(r, counts)
    for k, fs in ipairs(r.cols) do
        local n = counts[k] or 0
        fs:SetText(n > 0 and tostring(n) or "|cff666666-|r")
    end
end

function ns.RefreshHistory()
    if not (win and win:IsShown()) then return end
    local items, total, plist = ns.HistorySummary(state.dir, state.who, state.alts)
    win.sent:SetEnabled(state.dir ~= "s")
    win.received:SetEnabled(state.dir ~= "r")
    win.alts:SetChecked(state.alts)

    -- people: Everyone, then by count
    local entries = { { nil, "Everyone" } }
    for _, p in ipairs(plist) do entries[#entries + 1] = { p[1], ("%s |cff999999%d|r"):format(p[1], p[2]) } end
    local ppages = math.max(1, math.ceil(#entries / ROWS))
    if state.ppage > ppages then state.ppage = ppages end
    for i = 1, ROWS do
        local b, e = people[i], entries[(state.ppage - 1) * ROWS + i]
        if e then
            b.who = e[1]
            b.text:SetText(((state.who == e[1]) and "|cffffd100> |r" or "") .. e[2])
            b:Show()
        else
            b:Hide()
        end
    end
    win.pprev:SetEnabled(state.ppage > 1)
    win.pnext:SetEnabled(state.ppage < ppages)

    local verb = state.dir == "s" and "sent to" or "received from"
    win.title:SetText(("Items %s %s%s"):format(verb, state.who or "other players",
        state.alts and not state.who and " |cff999999(alts included)|r" or ""))
    win.totalRow.text:SetText("|cffffd100All items|r")
    SetCounts(win.totalRow, total)

    local pages = math.max(1, math.ceil(#items / ROWS))
    if state.page > pages then state.page = pages end
    for i = 1, ROWS do
        local r, it = rows[i], items[(state.page - 1) * ROWS + i]
        if it then
            r.id = it.id
            local icon = GetItemIcon and GetItemIcon(it.id)
            r.icon:SetTexture(icon)
            r.text:SetText(ItemLabel(it.id))
            SetCounts(r, it.counts)
            r:Show()
        else
            r.id = nil
            r:Hide()
        end
    end
    win.empty:SetShown(#items == 0)
    win.prev:SetEnabled(state.page > 1)
    win.next:SetEnabled(state.page < pages)
    win.pageText:SetText(("Page %d / %d  |cff999999(%d items)|r"):format(state.page, pages, #items))
end

local function Button(parent, text, w, onClick)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(w, 20)
    b:SetText(text)
    b:SetScript("OnClick", onClick)
    return b
end

local function Cols(r, font)
    r.cols = {}
    for k = #ns.TIMEFRAMES, 1, -1 do
        local fs = r:CreateFontString(nil, "OVERLAY", font)
        fs:SetWidth(COL_W)
        fs:SetJustifyH("RIGHT")
        fs:SetPoint("RIGHT", -(#ns.TIMEFRAMES - k) * COL_W, 0)
        r.cols[k] = fs
    end
end

local function Build()
    win = CreateFrame("Frame", "RonisMailMatsHistory", UIParent, "BackdropTemplate")
    win:SetSize(W, H)
    win:SetPoint("CENTER")
    ns.StyleWindow(win, true)
    win:SetFrameStrata("DIALOG")
    win:EnableMouse(true)
    win:SetMovable(true)
    win:SetClampedToScreen(true)
    win:RegisterForDrag("LeftButton")
    win:SetScript("OnDragStart", function(self) self:StartMoving() end)
    win:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    win:SetScript("OnShow", ns.RefreshHistory)
    if UISpecialFrames then table.insert(UISpecialFrames, "RonisMailMatsHistory") end

    local head = win:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    head:SetPoint("TOPLEFT", PAD, -PAD)
    head:SetText(ns.TAG .. " history")
    Button(win, "X", 22, function() win:Hide() end):SetPoint("TOPRIGHT", -8, -8)

    win.sent = Button(win, "Sent", 70, function() state.dir, state.who, state.page = "s", nil, 1; ns.RefreshHistory() end)
    win.sent:SetPoint("TOPLEFT", PAD, -36)
    win.received = Button(win, "Received", 80, function() state.dir, state.who, state.page = "r", nil, 1; ns.RefreshHistory() end)
    win.received:SetPoint("LEFT", win.sent, "RIGHT", 4, 0)

    win.alts = CreateFrame("CheckButton", nil, win, "UICheckButtonTemplate")
    win.alts:SetSize(22, 22)
    win.alts:SetPoint("LEFT", win.received, "RIGHT", 12, 0)
    win.alts:SetScript("OnClick", function(self) state.alts = self:GetChecked() and true or false; ns.RefreshHistory() end)
    local altsLabel = win:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    altsLabel:SetPoint("LEFT", win.alts, "RIGHT", 2, 0)
    altsLabel:SetText("Include my alts")

    -- left: people
    local top = -64
    for i = 1, ROWS do
        local b = CreateFrame("Button", nil, win)
        b:SetSize(LEFT_W - 8, ROW_H - 2)
        b:SetPoint("TOPLEFT", PAD, top - (i - 1) * ROW_H)
        b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        b.text:SetPoint("LEFT", 2, 0)
        b.text:SetWidth(LEFT_W - 10)
        b.text:SetJustifyH("LEFT")
        b:SetScript("OnClick", function(self) state.who, state.page = self.who, 1; ns.RefreshHistory() end)
        people[i] = b
    end
    local by = top - ROWS * ROW_H - 4
    win.pprev = Button(win, "<", 24, function() state.ppage = state.ppage - 1; ns.RefreshHistory() end)
    win.pprev:SetPoint("TOPLEFT", PAD, by)
    win.pnext = Button(win, ">", 24, function() state.ppage = state.ppage + 1; ns.RefreshHistory() end)
    win.pnext:SetPoint("LEFT", win.pprev, "RIGHT", 4, 0)

    -- right: title, column heads, total row, item rows
    local x = PAD + LEFT_W
    local rw = W - x - PAD
    win.title = win:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    win.title:SetPoint("TOPLEFT", x, -40)
    win.title:SetWidth(rw - 100)
    win.title:SetJustifyH("LEFT")

    local heads = CreateFrame("Frame", nil, win)
    heads:SetSize(rw, 16)
    heads:SetPoint("TOPLEFT", x, top + 16)
    Cols(heads, "GameFontNormalSmall")
    for k, tf in ipairs(ns.TIMEFRAMES) do heads.cols[k]:SetText(tf[1]) end

    local function Row(y)
        local r = CreateFrame("Button", nil, win)
        r:SetSize(rw, ROW_H - 2)
        r:SetPoint("TOPLEFT", x, y)
        r.icon = r:CreateTexture(nil, "ARTWORK")
        r.icon:SetSize(18, 18)
        r.icon:SetPoint("LEFT", 0, 0)
        r.text = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        r.text:SetPoint("LEFT", 22, 0)
        r.text:SetWidth(rw - 22 - #ns.TIMEFRAMES * COL_W - 4)
        r.text:SetJustifyH("LEFT")
        Cols(r, "GameFontHighlightSmall")
        r:SetScript("OnEnter", function(self)
            if not self.id then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            if GameTooltip.SetItemByID then GameTooltip:SetItemByID(self.id) end
            GameTooltip:Show()
        end)
        r:SetScript("OnLeave", function() GameTooltip:Hide() end)
        return r
    end
    win.totalRow = Row(top)
    for i = 1, ROWS do rows[i] = Row(top - i * ROW_H) end

    win.empty = win:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    win.empty:SetPoint("TOPLEFT", x, top - ROW_H - 4)
    win.empty:SetWidth(rw)
    win.empty:SetJustifyH("LEFT")
    win.empty:SetText("Nothing yet. Items are counted from now on, as mail is sent or taken from the mailbox.")

    by = top - (ROWS + 1) * ROW_H - 4
    win.prev = Button(win, "< Prev", 60, function() state.page = state.page - 1; ns.RefreshHistory() end)
    win.prev:SetPoint("TOPLEFT", x, by)
    win.next = Button(win, "Next >", 60, function() state.page = state.page + 1; ns.RefreshHistory() end)
    win.next:SetPoint("LEFT", win.prev, "RIGHT", 4, 0)
    win.pageText = win:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    win.pageText:SetPoint("LEFT", win.next, "RIGHT", 8, 0)

    win:Hide()
end

function ns.ToggleHistory(dir)
    if not win then Build() end
    if dir then state.dir, state.who, state.page = dir, nil, 1 end
    if win:IsShown() and not dir then win:Hide() else win:Show(); ns.RefreshHistory() end
end
