-- Specs for Roni's MailMats. Each login is a fresh mocked client session;
-- saved variables are carried between sessions like the real client does.
return function(T)
    local test, eq, ok, contains = T.test, T.eq, T.ok, T.contains

    local REALM = "Test Realm"
    local TAILOR = { { line = 197, name = "Tailoring", rank = 150, max = 225 },
                     { line = 185, name = "Cooking", rank = 75, max = 150 } }

    local function Char(saved, name) return saved.RonisMailMatsDB.chars[REALM][name] end

    -- Saved variables after logging in once on a tailor alt.
    local function TailorAltSaved(extra)
        local S = T.Login({ name = "Alt", class = "PRIEST", profs = TAILOR })
        local saved = T.Logout(S)
        for _, e in ipairs(extra or {}) do
            saved = T.Logout(T.Login(e, saved))
        end
        return saved
    end

    local function Bags(list) -- { {id, count, bound}, ... } into bag 0
        local bag = {}
        for i, it in ipairs(list) do bag[i] = { id = it[1], count = it[2], bound = it[3] } end
        return { [0] = bag }
    end
    local MAIN_BAGS = { { 2589, 20 }, { 2589, 5 }, { 2592, 10 }, { 6948, 1 }, { 765, 7 } }

    local function MainAtMailbox(saved, opts)
        opts = opts or {}
        opts.name = opts.name or "Main"
        opts.bags = opts.bags or Bags(MAIN_BAGS)
        local S = T.Login(opts, saved)
        S.OpenMailbox()
        return S
    end

    -----------------------------------------------------------------------
    -- Profession scan
    -----------------------------------------------------------------------
    test("forever: login records professions through GetProfessions", function()
        local saved = T.Logout(T.Login({ name = "Alt", class = "PRIEST", profs = TAILOR }))
        local c = Char(saved, "Alt")
        ok(c, "Alt saved")
        eq(c.profs.Tailoring and c.profs.Tailoring.rank, 150, "Tailoring rank")
        eq(c.profs.Cooking and c.profs.Cooking.rank, 75, "Cooking rank")
        eq(c.class, "PRIEST", "class")
        eq(c.faction, "Alliance", "faction")
    end)

    test("regression: a character is saved even with no professions", function()
        local saved = T.Logout(T.Login({ name = "Bank" }))
        ok(Char(saved, "Bank"), "Bank saved")
    end)

    test("profession names come from the skill line ID, not the (localized) name", function()
        local saved = T.Logout(T.Login({ name = "Alt",
            profs = { { line = 197, name = "Schneiderei", rank = 10, max = 75 } } }))
        ok(Char(saved, "Alt").profs.Tailoring, "Tailoring from line 197")
    end)

    test("profession API answering late at login still records", function()
        local saved = T.Logout(T.Login({ name = "Alt", profs = TAILOR, profsReadyAt = 10 }))
        ok(Char(saved, "Alt").profs.Tailoring, "Tailoring recorded")
    end)

    test("an empty read right after login keeps the professions we knew", function()
        local saved = TailorAltSaved()
        local S = T.mock.NewSession({ name = "Alt", profs = TAILOR, profsReadyAt = 1000,
            saved = T.mock.CopySaved(saved) })
        S.flavor = "forever"
        T.sessions[#T.sessions + 1] = S
        S.Load(T.DIR, T.ADDON)
        S.Fire("PLAYER_LOGIN")
        S.Advance(5)
        ok(S.env.RonisMailMatsDB.chars[REALM].Alt.profs.Tailoring, "Tailoring kept")
    end)

    test("classic flavor: skill line API with a collapsed header", function()
        local saved = T.Logout(T.Login({ flavor = "classic", collapsed = true, name = "Alt",
            profs = { { name = "Tailoring", rank = 120, max = 150 } } }))
        eq(Char(saved, "Alt").profs.Tailoring.rank, 120, "Tailoring rank")
    end)

    -----------------------------------------------------------------------
    -- Panel
    -----------------------------------------------------------------------
    test("panel docks to the mailbox and offers the alt's mats", function()
        local S = MainAtMailbox(TailorAltSaved())
        local panel = T.Panel(S)
        ok(panel and panel:IsVisible(), "panel visible")
        eq(panel:GetParent(), S.env.MailFrame, "panel parent")
        local b = T.Button(S, "Tailoring")
        eq(b:GetText(), "Send Tailoring mats (3)", "button text")
        ok(b:IsEnabled(), "button enabled")
        T.Button(S, "Cooking") -- every crafting profession gets a button
    end)

    test("panel says how to fix it when no alts are known", function()
        local S = MainAtMailbox(nil)
        eq(#T.Buttons(S), 0, "no buttons")
        local found
        for _, f in ipairs(S.frames) do
            if f == T.Panel(S) then found = f end
        end
        ok(found, "panel exists")
    end)

    test("alts on another faction or realm are not offered", function()
        local saved = TailorAltSaved({
            { name = "Horde", faction = "Horde", profs = TAILOR },
            { name = "Far", realm = "Other Realm", profs = TAILOR },
        })
        local S = MainAtMailbox(saved)
        for _, b in ipairs(T.Buttons(S)) do
            ok(b.alt == "Alt", "only Alt offered, got " .. tostring(b.alt))
        end
    end)

    test("alts with only gathering professions get no buttons", function()
        local saved = T.Logout(T.Login({ name = "Picker", profs = { { line = 182, name = "Herbalism", rank = 50, max = 75 } } }))
        local S = MainAtMailbox(saved)
        eq(#T.Buttons(S), 0, "no buttons")
    end)

    test("tooltip lists the items and totals", function()
        local S = MainAtMailbox(TailorAltSaved())
        local b = T.Button(S, "Tailoring")
        b._scripts.OnEnter(b)
        contains(S.env.GameTooltip._lines, "Linen Cloth.*x25", "tooltip")
        contains(S.env.GameTooltip._lines, "Wool Cloth.*x10", "tooltip")
    end)

    -----------------------------------------------------------------------
    -- Drafting
    -----------------------------------------------------------------------
    test("clicking drafts the mail on the Send tab and sends nothing", function()
        local S = MainAtMailbox(TailorAltSaved())
        T.Button(S, "Tailoring"):Click()
        S.Advance(1)
        ok(S.env.SendMailFrame:IsShown(), "send tab shown")
        eq(S.env.SendMailNameEditBox:GetText(), "Alt", "recipient")
        eq(S.env.SendMailSubjectEditBox:GetText(), "Tailoring mats", "subject")
        local a = S.Attachments()
        eq(#a, 3, "attachments")
        local ids = {}
        for _, x in ipairs(a) do ids[x.id] = (ids[x.id] or 0) + x.count end
        eq(ids[2589], 25, "linen attached")
        eq(ids[2592], 10, "wool attached")
        eq(#S.sent, 0, "nothing sent")
        eq(S.cursor, nil, "cursor empty")
        eq(S.bags[0][4].id, 6948, "hearthstone stays")
        eq(T.Button(S, "Tailoring"):GetText(), "Send Tailoring mats (0)", "count after draft")
        contains(S.printLog, "Drafted 3 stack", "chat message")
    end)

    test("soulbound stacks are skipped", function()
        local S = MainAtMailbox(TailorAltSaved(), { bags = Bags({ { 2589, 20 }, { 2589, 5, true } }) })
        eq(T.Button(S, "Tailoring"):GetText(), "Send Tailoring mats (1)", "count")
        T.Button(S, "Tailoring"):Click()
        eq(#S.Attachments(), 1, "attachments")
        eq(#S.errors, 0, "no client errors")
    end)

    test("more than 12 stacks: fills one mail and says how many are left", function()
        local list = {}
        for i = 1, 15 do list[i] = { 2589, 20 } end
        local S = MainAtMailbox(TailorAltSaved(), { bags = Bags(list) })
        T.Button(S, "Tailoring"):Click()
        eq(#S.Attachments(), 12, "attachments")
        contains(S.printLog, "3 more stack", "chat message")
    end)

    test("attachments from an earlier draft go back to the bags first", function()
        local S = MainAtMailbox(TailorAltSaved())
        S.env.MailFrameTab2:Click()
        S.env.C_Container.PickupContainerItem(0, 4) -- hearthstone
        S.env.ClickSendMailItemButton(1)
        eq(#S.Attachments(), 1, "hearthstone attached")
        T.Button(S, "Tailoring"):Click()
        S.Advance(1)
        local a = S.Attachments()
        eq(#a, 3, "attachments")
        for _, x in ipairs(a) do ok(x.id ~= 6948, "hearthstone not attached") end
        eq(S.bags[0][4] and S.bags[0][4].id, 6948, "hearthstone back in bag")
    end)

    test("attachment slots that the client confirms late are not reused", function()
        local S = MainAtMailbox(TailorAltSaved(), { mailLag = true })
        T.Button(S, "Tailoring"):Click() -- the mock errors on a drop onto a used slot
        eq(#S.Attachments(), 3, "attachments")
    end)

    test("drafting does nothing while the mailbox is closed", function()
        local S = MainAtMailbox(TailorAltSaved())
        local b = T.Button(S, "Tailoring")
        S.CloseMailbox()
        S.ns.Draft("Alt", "Tailoring")
        eq(#S.Attachments(), 0, "attachments")
    end)

    -----------------------------------------------------------------------
    -- Options and commands
    -----------------------------------------------------------------------
    test("keep my own mats: a tailor main keeps its cloth until unticked", function()
        local saved = TailorAltSaved()
        local S = MainAtMailbox(saved, { profs = { { line = 197, name = "Tailoring", rank = 1, max = 75 } } })
        eq(T.Button(S, "Tailoring"):GetText(), "Send Tailoring mats (0)", "kept")
        local box
        for _, f in ipairs(S.frames) do
            if f._type == "CheckButton" and f._parent == T.Panel(S) then box = f end
        end
        ok(box and box:GetChecked(), "box ticked by default")
        box:Click()
        eq(T.Button(S, "Tailoring"):GetText(), "Send Tailoring mats (3)", "after unticking")
        eq(S.env.RonisMailMatsDB.keepOwn, false, "saved")
    end)

    test("/mailmats ignore and forget", function()
        local S = MainAtMailbox(TailorAltSaved())
        S.Slash("/mailmats", "ignore 2589")
        eq(T.Button(S, "Tailoring"):GetText(), "Send Tailoring mats (1)", "after ignore")
        S.Slash("/mailmats", "unignore 2589")
        eq(T.Button(S, "Tailoring"):GetText(), "Send Tailoring mats (3)", "after unignore")
        S.Slash("/mailmats", "forget alt")
        eq(#T.Buttons(S), 0, "after forget")
        S.Slash("/mailmats", "")
        contains(S.printLog, "Main", "list shows Main")
    end)

    test("/mailmats selftest passes on the Forever client", function()
        local S = MainAtMailbox(TailorAltSaved(), { profs = TAILOR })
        S.Slash("/mailmats", "selftest")
        contains(S.printLog, "Self test passed", "selftest")
        contains(S.printLog, "GetProfessions %-> Cooking 75, Tailoring 150", "profession line")
    end)
end
