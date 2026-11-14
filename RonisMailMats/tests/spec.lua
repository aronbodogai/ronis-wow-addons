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

    -----------------------------------------------------------------------
    -- Lockpicking and Comprehension (skills, not professions)
    -----------------------------------------------------------------------
    local LOCKBOX_BAGS = { { 4632, 1 }, { 16882, 1 }, { 4636, 1 }, { 211780, 1 }, { 213543, 2 }, { 2589, 20 } }

    local function RogueAndMageSaved()
        local saved = T.Logout(T.Login({ name = "Sneaky", class = "ROGUE",
            skills = { { id = 633, name = "Lockpicking", rank = 80, max = 100 } } }))
        return T.Logout(T.Login({ name = "Wizard", class = "MAGE",
            skills = { { id = 3012, name = "Comprehension", rank = 20, max = 75 } } }, saved))
    end

    test("Lockpicking and Comprehension are read from C_SkillInfo", function()
        local saved = RogueAndMageSaved()
        eq(Char(saved, "Sneaky").profs.Lockpicking.rank, 80, "Lockpicking rank")
        eq(Char(saved, "Sneaky").profs.Lockpicking.max, 100, "Lockpicking max")
        eq(Char(saved, "Wizard").profs.Comprehension.rank, 20, "Comprehension rank")
    end)

    test("skills are found by walking the skill list when the by-ID lookup fails", function()
        local saved = T.Logout(T.Login({ name = "Sneaky", class = "ROGUE", skillsByID = false,
            skills = { { id = 633, name = "Lockpicking", rank = 80, max = 100 } } }))
        eq(Char(saved, "Sneaky").profs.Lockpicking.rank, 80, "Lockpicking rank")
    end)

    test("a rogue alt gets a lockbox button and a mage alt a scroll button", function()
        local S = MainAtMailbox(RogueAndMageSaved(), { bags = Bags(LOCKBOX_BAGS) })
        eq(T.Button(S, "lockboxes"):GetText(), "Send lockboxes (3)", "lockbox button")
        eq(T.Button(S, "lockboxes").alt, "Sneaky", "lockboxes go to the rogue")
        eq(T.Button(S, "scrolls"):GetText(), "Send scrolls (2)", "scroll button")
        eq(T.Button(S, "scrolls").alt, "Wizard", "scrolls go to the mage")
    end)

    test("drafting lockboxes attaches only lockboxes", function()
        local S = MainAtMailbox(RogueAndMageSaved(), { bags = Bags(LOCKBOX_BAGS) })
        T.Button(S, "lockboxes"):Click()
        S.Advance(1)
        local ids = {}
        for _, a in ipairs(S.Attachments()) do ids[#ids + 1] = a.id end
        table.sort(ids)
        eq(table.concat(ids, ","), "4632,4636,16882", "attached")
        eq(S.env.SendMailNameEditBox:GetText(), "Sneaky", "recipient")
        eq(S.env.SendMailSubjectEditBox:GetText(), "Lockboxes", "subject")
        eq(#S.sent, 0, "nothing sent")
    end)

    test("tooltip marks lockboxes above the rogue's skill", function()
        local S = MainAtMailbox(RogueAndMageSaved(), { bags = Bags(LOCKBOX_BAGS) })
        local b = T.Button(S, "lockboxes")
        b._scripts.OnEnter(b)
        contains(S.env.GameTooltip._lines, "Strong Iron Lockbox.*needs 125", "too hard")
        for _, l in ipairs(S.env.GameTooltip._lines) do
            ok(not tostring(l):find("Battered Junkbox.*needs"), "junkbox is openable: " .. tostring(l))
        end
    end)

    test("a rogue main keeps its own lockboxes until unticked", function()
        local LP = { { id = 633, name = "Lockpicking", rank = 80, max = 100 } }
        local saved = T.Logout(T.Login({ name = "Other", class = "ROGUE", skills = LP }))
        local S = MainAtMailbox(saved, { class = "ROGUE", skills = LP, bags = Bags(LOCKBOX_BAGS) })
        eq(T.Button(S, "lockboxes"):GetText(), "Send lockboxes (0)", "kept")
        local box = T.Panel(S)
        for _, f in ipairs(S.frames) do
            if f._type == "CheckButton" and f._parent == box then f:Click() end
        end
        eq(T.Button(S, "lockboxes"):GetText(), "Send lockboxes (3)", "after unticking")
    end)

    test("selftest shows the raw skill line data", function()
        local S = MainAtMailbox(TailorAltSaved(), { skills = { { id = 633, name = "Lockpicking", rank = 80, max = 100 } } })
        S.Slash("/mailmats", "selftest")
        contains(S.printLog, "Lockpicking %(633%):.*rank=80", "raw fields")
        contains(S.printLog, "Comprehension %(3012%): not known", "unknown skill")
        contains(S.printLog, "Self test passed", "selftest")
    end)

    -----------------------------------------------------------------------
    -- Gear upgrades for alts
    -----------------------------------------------------------------------
    -- bag 0: 1 Cloth Hood, 2 Leather Cap, 3 High Level Hood, 4 Bound Hood (BoP),
    -- 5 Fine Ring, 6 Iron Shield, 7 Spellbook, 8 soulbound Cloth Hood, 9 cloth
    local GEAR_BAGS = { { 9001, 1 }, { 9003, 1 }, { 9004, 1 }, { 9005, 1 }, { 9006, 1 },
                        { 9007, 1 }, { 9009, 1 }, { 9001, 1, true }, { 2589, 5 } }

    local function GearAltsSaved()
        local saved = T.Logout(T.Login({ name = "Wiz", class = "MAGE", level = 20,
            equipped = { [1] = 9002 } }))
        return T.Logout(T.Login({ name = "Tank", class = "WARRIOR", level = 20,
            equipped = { [16] = 9008 } }, saved))
    end

    local function TooltipText(S, id)
        return table.concat(S.ShowItemTooltip(id), " / ")
    end

    test("login records the item level worn in each slot", function()
        local saved = GearAltsSaved()
        local g = Char(saved, "Wiz").gear
        eq(g[1], 10, "head")
        eq(g[11], 0, "empty ring slot")
        ok(Char(saved, "Tank").gear.twoHand, "two-hander noted")
    end)

    test("tooltip says which alt an item upgrades and by how much", function()
        local S = MainAtMailbox(GearAltsSaved(), { bags = Bags(GEAR_BAGS) })
        contains(S.ShowItemTooltip(9001), "Upgrade for Wiz %(%+10 item level%)", "cloth hood")
        local ring = TooltipText(S, 9006)
        ok(ring:find("Upgrade for Wiz") and ring:find("Upgrade for Tank"), "ring for both: " .. ring)
    end)

    test("no upgrade line for gear the alt cannot use or receive", function()
        local S = MainAtMailbox(GearAltsSaved(), { bags = Bags(GEAR_BAGS) })
        for id, why in pairs({ [9003] = "leather on a mage, mail-wearer warrior",
                               [9004] = "level too high", [9005] = "bind on pickup",
                               [9007] = "shield: mage cannot, warrior wields a two-hander" }) do
            ok(not TooltipText(S, id):find("Upgrade for"), why)
        end
    end)

    test("mailbox panel offers the alt's upgrades and drafts them", function()
        local S = MainAtMailbox(GearAltsSaved(), { bags = Bags(GEAR_BAGS) })
        local b, tank
        for _, x in ipairs(T.Buttons(S)) do
            if (x._text or ""):find("upgrades") then
                if x.alt == "Wiz" then b = x elseif x.alt == "Tank" then tank = x end
            end
        end
        ok(b, "Wiz has an upgrades button")
        eq(b:GetText(), "Send upgrades (3)", "hood, ring, spellbook; not the soulbound hood")
        eq(tank and tank:GetText(), "Send upgrades (1)", "the ring for Tank")
        b:Click()
        S.Advance(1)
        local ids = {}
        for _, a in ipairs(S.Attachments()) do ids[#ids + 1] = a.id end
        table.sort(ids)
        eq(table.concat(ids, ","), "9001,9006,9009", "attached")
        eq(S.env.SendMailSubjectEditBox:GetText(), "Upgrades", "subject")
        eq(#S.sent, 0, "nothing sent")
    end)

    test("Bagnon item buttons get the mail icon on upgrades", function()
        local S = MainAtMailbox(GearAltsSaved(), { bags = Bags(GEAR_BAGS), bagnon = true })
        local function BagnonButton(slot)
            local f = S.env.CreateFrame("Button")
            f.GetBag = function() return 0 end
            f.GetID = function() return slot end
            f.info = { hyperlink = S.env.C_Container.GetContainerItemLink(0, slot) }
            S.env.Bagnon.Item.UpdateUpgradeIcon(f)
            return f
        end
        local hood, cap, bound = BagnonButton(1), BagnonButton(2), BagnonButton(8)
        ok(hood.RonisMailMatsIcon and hood.RonisMailMatsIcon:IsShown(), "icon on the hood")
        ok(not (cap.RonisMailMatsIcon and cap.RonisMailMatsIcon:IsShown()), "no icon on the leather cap")
        ok(not (bound.RonisMailMatsIcon and bound.RonisMailMatsIcon:IsShown()), "no icon on a soulbound item")
    end)

    -----------------------------------------------------------------------
    -- Other recipients (friends, anyone): one button for several categories
    -----------------------------------------------------------------------
    local function TargetButton(S, name)
        return T.Button(S, "Send all to " .. name)
    end

    test("/mailmats target saves a recipient with several categories", function()
        local S = MainAtMailbox(nil, { bags = Bags(LOCKBOX_BAGS) })
        S.Slash("/mailmats", "target bob tailoring, scrolls")
        local t = S.env.RonisMailMatsDB.targets[REALM].Bob
        eq(t and table.concat(t.cats, ","), "Tailoring,Comprehension", "stored in panel order")
        contains(S.printLog, "Bob will get Tailoring mats, scrolls", "confirmation")
        S.Slash("/mailmats", "target bob nonsense")
        contains(S.printLog, "Unknown category 'nonsense'", "bad category")
        eq(table.concat(S.env.RonisMailMatsDB.targets[REALM].Bob.cats, ","), "Tailoring,Comprehension", "unchanged")
    end)

    test("one button drafts everything the recipient wants in one mail", function()
        local S = MainAtMailbox(nil, { bags = Bags(LOCKBOX_BAGS) })
        S.Slash("/mailmats", "target Bob tailoring, comprehension")
        local b = TargetButton(S, "Bob")
        eq(b:GetText(), "Send all to Bob (3)", "linen + 2 scroll stacks, no lockboxes")
        b:Click()
        S.Advance(1)
        local ids = {}
        for _, a in ipairs(S.Attachments()) do ids[#ids + 1] = a.id end
        table.sort(ids)
        eq(table.concat(ids, ","), "2589,211780,213543", "attached")
        eq(S.env.SendMailNameEditBox:GetText(), "Bob", "recipient")
        eq(S.env.SendMailSubjectEditBox:GetText(), "Tailoring mats, scrolls", "subject")
        eq(#S.sent, 0, "nothing sent")
    end)

    test("recipients survive a relog and can be removed", function()
        local S = MainAtMailbox(nil, { bags = Bags(LOCKBOX_BAGS) })
        S.Slash("/mailmats", "target Bob lockpicking")
        local S2 = MainAtMailbox(T.Logout(S), { bags = Bags(LOCKBOX_BAGS) })
        eq(TargetButton(S2, "Bob"):GetText(), "Send all to Bob (3)", "lockboxes after relog")
        S2.Slash("/mailmats", "untarget bob")
        for _, x in ipairs(T.Buttons(S2)) do
            ok(not (x._text or ""):find("Send all to"), "removed: " .. tostring(x._text))
        end
    end)

    test("the editor adds, changes and deletes a recipient", function()
        local S = MainAtMailbox(nil, { bags = Bags(LOCKBOX_BAGS) })
        for _, f in ipairs(S.frames) do
            if f._type == "Button" and (f._text or ""):find("Add a recipient") then f:Click() end
        end
        local ed = S.env.RonisMailMatsEditor
        ok(ed and ed:IsShown(), "editor open")
        ed.nameBox:SetText("Friend")
        for _, cb in ipairs(ed.boxes) do
            if cb.cat == "Comprehension" then cb:Click() end
        end
        ed.save:Click()
        ok(not ed:IsShown(), "closed on save")
        eq(TargetButton(S, "Friend"):GetText(), "Send all to Friend (2)", "scrolls")
        -- right-click the button to edit: boxes come back ticked
        TargetButton(S, "Friend")._scripts.OnClick(TargetButton(S, "Friend"), "RightButton")
        ok(ed:IsShown(), "editor reopened")
        local ticked = {}
        for _, cb in ipairs(ed.boxes) do if cb:GetChecked() then ticked[#ticked + 1] = cb.cat end end
        eq(table.concat(ticked, ","), "Comprehension", "prefilled")
        for _, cb in ipairs(ed.boxes) do if cb.cat == "Tailoring" then cb:Click() end end
        ed.save:Click()
        eq(TargetButton(S, "Friend"):GetText(), "Send all to Friend (3)", "scrolls and cloth")
        TargetButton(S, "Friend")._scripts.OnClick(TargetButton(S, "Friend"), "RightButton")
        ed.delete:Click()
        eq(S.env.RonisMailMatsDB.targets[REALM].Friend, nil, "deleted")
    end)
end
