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

    -----------------------------------------------------------------------
    -- Removing recipients, suggestions
    -----------------------------------------------------------------------
    local function Removers(S)
        local out = {}
        for _, f in ipairs(S.frames) do
            if f._type == "Button" and f._parent == T.Panel(S) and f._shown and f._text == "X" then
                out[#out + 1] = f
            end
        end
        return out
    end

    test("each recipient has an X button that removes it", function()
        local S = MainAtMailbox(nil, { bags = Bags(LOCKBOX_BAGS) })
        S.Slash("/mailmats", "target Bob tailoring")
        S.Slash("/mailmats", "target Ann scrolls")
        eq(#Removers(S), 2, "one per recipient")
        local bob
        for _, r in ipairs(Removers(S)) do if r.target == "Bob" then bob = r end end
        bob:Click()
        eq(S.env.RonisMailMatsDB.targets[REALM].Bob, nil, "Bob removed")
        ok(S.env.RonisMailMatsDB.targets[REALM].Ann, "Ann kept")
        eq(#Removers(S), 1, "one left")
        contains(S.printLog, "Removed Bob", "message")
    end)

    local SOCIAL = {
        friends = { { "Offlinepal", "Warrior", 40, false }, { "Mageybff", "Mage", 25, true }, { "Alt", "Priest", 10, true } },
        bnet = { { "Bnetrogue", REALM, "Alliance", "Rogue", 30 }, { "Farrealm", "Other Realm", "Alliance", "Mage", 30 },
                 { "Hordie", REALM, "Horde", "Mage", 30 } },
        guild = { { "Guildie-TestRealm", 20, "Priest", "PRIEST", true }, { "Mageybff-TestRealm", 25, "Mage", "MAGE", true } },
        inbox = { { "Stormwind Auction House" }, { "Gamemaster", true }, { "Pen-pal" } },
    }

    test("suggestions come from friends, Battle.net, mail and guild", function()
        local saved = TailorAltSaved()
        local opts = { bags = Bags(LOCKBOX_BAGS) }
        for k, v in pairs(SOCIAL) do opts[k] = v end
        local S = MainAtMailbox(saved, opts)
        S.Slash("/mailmats", "target Offlinepal tailoring")
        S.env.SendMail("Mailbuddy", "hi", "")
        local names = {}
        for _, s in ipairs(S.ns.Suggestions(20)) do names[#names + 1] = s.name .. ":" .. s.why end
        local got = table.concat(names, " / ")
        eq(got, "Mageybff:friend, Mage 25 / Bnetrogue:Battle.net friend, Rogue 30 / Mailbuddy:you mailed"
            .. " / Pen-pal:mailed you / Guildie:guild, Priest 20", "order and sources")
        ok(S.rosterRequests > 0, "guild roster requested")
    end)

    test("the editor lists suggestions and a click fills the name and hint", function()
        local opts = { bags = Bags(LOCKBOX_BAGS) }
        for k, v in pairs(SOCIAL) do opts[k] = v end
        local S = MainAtMailbox(TailorAltSaved(), opts)
        S.ns.OpenEditor(nil)
        local ed = S.env.RonisMailMatsEditor
        local first
        for _, b in ipairs(ed.sugButtons) do if b._shown and not first then first = b end end
        ok(first and first._text:find("Mageybff"), "first suggestion: " .. tostring(first and first._text))
        first:Click()
        eq(ed.nameBox:GetText(), "Mageybff", "name filled")
        local ticked = {}
        for _, cb in ipairs(ed.boxes) do if cb:GetChecked() then ticked[#ticked + 1] = cb.cat end end
        eq(table.concat(ticked, ","), "Comprehension", "a mage gets scrolls ticked")
        ed.save:Click()
        ok(S.env.RonisMailMatsDB.targets[REALM].Mageybff, "saved")
        -- editing an existing recipient shows no suggestions
        S.ns.OpenEditor("Mageybff")
        for _, b in ipairs(ed.sugButtons) do ok(not b._shown, "hidden when editing") end
    end)

    -----------------------------------------------------------------------
    -- Forever surnames: mail needs "First Last"
    -----------------------------------------------------------------------
    test("characters are saved and mailed under first name and surname", function()
        local saved = T.Logout(T.Login({ name = "Silva", surname = "Moonbrook", class = "PRIEST", profs = TAILOR }))
        ok(Char(saved, "Silva Moonbrook"), "saved with surname")
        eq(Char(saved, "Silva"), nil, "not under the first name")
        local S = MainAtMailbox(saved, { surname = "Hammer" })
        eq(S.ns.me, "Main Hammer", "own full name")
        local b = T.Button(S, "Tailoring")
        eq(b.alt, "Silva Moonbrook", "button alt")
        b:Click()
        S.Advance(1)
        eq(S.env.SendMailNameEditBox:GetText(), "Silva Moonbrook", "recipient has the surname")
    end)

    test("an entry from before surnames moves to the full name on login", function()
        local old = T.Logout(T.Login({ name = "Silva", class = "PRIEST", profs = TAILOR }))
        old = T.Logout(T.Login({ name = "Other", class = "MAGE" }, old))
        -- a different character sharing the first name keeps its old entry
        local saved = T.Logout(T.Login({ name = "Silva", surname = "Moonbrook", class = "PRIEST", profs = TAILOR }, old))
        ok(Char(saved, "Silva Moonbrook"), "moved")
        eq(Char(saved, "Silva"), nil, "old key gone")
        local saved2 = T.Logout(T.Login({ name = "Other", surname = "Person", class = "WARRIOR" }, old))
        ok(Char(saved2, "Other"), "other class: old entry kept")
    end)

    test("alts saved without a surname are flagged until they log in", function()
        local old = T.Logout(T.Login({ name = "Silva", class = "PRIEST", profs = TAILOR }))
        local S = MainAtMailbox(old, { surname = "Hammer" })
        ok(S.ns.NeedsFullName("Silva"), "flagged")
        ok(not S.ns.NeedsFullName("Silva Moonbrook"), "full name fine")
    end)

    test("recipients can have a surname", function()
        local S = MainAtMailbox(nil, { surname = "Hammer", bags = Bags(LOCKBOX_BAGS) })
        S.Slash("/mailmats", "target bob smith: tailoring, scrolls")
        local t = S.env.RonisMailMatsDB.targets[REALM]["Bob smith"]
        ok(t, "stored with surname")
        eq(T.Button(S, "Send all to Bob smith"):GetText(), "Send all to Bob smith (3)", "button")
        S.Slash("/mailmats", "untarget bob smith")
        eq(S.env.RonisMailMatsDB.targets[REALM]["Bob smith"], nil, "removed")
    end)

    test("suggestions keep surnames but skip NPC senders", function()
        local S = MainAtMailbox(nil, { surname = "Hammer",
            friends = { { "Ann Lee", "Mage", 20, true } },
            inbox = { { "Stormwind Auction House" }, { "Pen Pal" } } })
        local names = {}
        for _, s in ipairs(S.ns.Suggestions(20)) do names[#names + 1] = s.name end
        eq(table.concat(names, ","), "Ann Lee,Pen Pal", "suggested")
    end)

    -----------------------------------------------------------------------
    -- Groups window and minimap button
    -----------------------------------------------------------------------
    local function Win(S) return S.env.RonisMailMatsGroups end
    local function Rows(S)
        local out = {}
        for _, f in ipairs(S.frames) do
            if f._parent == Win(S) and rawget(f, "remove") and f._shown then out[#out + 1] = f end
        end
        return out
    end
    local function RowFor(S, id)
        for _, r in ipairs(Rows(S)) do if r.id == id then return r end end
    end

    test("/mailmats groups shows the items in a group", function()
        local S = MainAtMailbox(nil)
        S.Slash("/mailmats", "groups tailoring")
        ok(Win(S) and Win(S):IsShown(), "window open")
        local n = 0
        for _ in pairs(S.ns.IS_REAGENT.Tailoring) do n = n + 1 end
        contains({ Win(S).title:GetText() }, "Tailoring.*" .. n .. " items, built%-in", "title")
        eq(#Rows(S), 12, "a page of rows")
        ok(Win(S).next:IsEnabled(), "more pages")
        Win(S).next:Click()
        contains({ Win(S).pageText:GetText() }, "Page 2 /", "page 2")
    end)

    test("removing and re-adding items, and reset", function()
        local S = MainAtMailbox(TailorAltSaved(), { bags = Bags(MAIN_BAGS) })
        eq(T.Button(S, "Tailoring"):GetText(), "Send Tailoring mats (3)", "before")
        S.Slash("/mailmats", "groups Tailoring")
        -- find Wool Cloth on whatever page it is
        local row
        for _ = 1, 20 do
            row = RowFor(S, 2592)
            if row or not Win(S).next:IsEnabled() then break end
            Win(S).next:Click()
        end
        ok(row, "Wool Cloth listed")
        row.remove:Click()
        eq(S.ns.IS_REAGENT.Tailoring[2592], nil, "removed")
        ok(S.ns.GroupEdited("Tailoring"), "marked edited")
        eq(T.Button(S, "Tailoring"):GetText(), "Send Tailoring mats (2)", "button follows")
        Win(S).addBox:SetText("2592")
        Win(S).add:Click()
        ok(S.ns.IS_REAGENT.Tailoring[2592], "added back by id")
        ok(not S.ns.GroupEdited("Tailoring"), "same as default again")
        Win(S).addBox:SetText("6948") -- Hearthstone
        Win(S).add:Click()
        ok(S.ns.IS_REAGENT.Tailoring[6948], "extra item added")
        Win(S).reset:Click()
        eq(S.ns.IS_REAGENT.Tailoring[6948], nil, "reset")
        -- edits survive a relog
        S.ns.GroupRemove("Tailoring", 2589)
        local S2 = MainAtMailbox(T.Logout(S), { bags = Bags(MAIN_BAGS) })
        eq(S2.ns.IS_REAGENT.Tailoring[2589], nil, "kept after relog")
    end)

    test("dropping an item on the window adds it", function()
        local S = MainAtMailbox(nil, { bags = Bags({ { 6948, 1 } }) })
        S.Slash("/mailmats", "groups cooking")
        S.env.C_Container.PickupContainerItem(0, 1)
        Win(S)._scripts.OnReceiveDrag(Win(S))
        ok(S.ns.IS_REAGENT.Cooking[6948], "added")
        ok(not S.env.CursorHasItem(), "cursor cleared")
    end)

    test("custom groups: create, fill, give to a recipient, delete", function()
        local S = MainAtMailbox(nil, { bags = Bags(GEAR_BAGS) })
        S.Slash("/mailmats", "groups")
        Win(S).newBox:SetText("Bob stuff")
        Win(S).new:Click()
        contains({ Win(S).title:GetText() }, "Bob stuff.*0 items, your group", "new group selected")
        Win(S).addBox:SetText("9001")
        Win(S).add:Click()
        Win(S).addBox:SetText("9006")
        Win(S).add:Click()
        S.Slash("/mailmats", "target Bob: bob stuff, tailoring")
        eq(table.concat(S.env.RonisMailMatsDB.targets[REALM].Bob.cats, ","), "Tailoring,Bob stuff", "custom group on recipient")
        eq(T.Button(S, "Send all to Bob"):GetText(), "Send all to Bob (3)", "hood + ring + linen; the soulbound hood stays")
        -- the recipient editor offers the custom group too
        S.ns.OpenEditor("Bob")
        local ticked = {}
        for _, cb in ipairs(S.env.RonisMailMatsEditor.boxes) do if cb:GetChecked() then ticked[#ticked + 1] = cb.cat end end
        eq(table.concat(ticked, ","), "Tailoring,Bob stuff", "editor ticks the custom group")
        -- duplicate names are refused
        Win(S).newBox:SetText("tailoring")
        Win(S).new:Click()
        contains(S.printLog, "already a group called Tailoring", "duplicate")
        -- delete
        S.Slash("/mailmats", "groups bob stuff")
        Win(S).reset:Click()
        eq(S.env.RonisMailMatsDB.groups.custom["Bob stuff"], nil, "deleted")
        eq(table.concat(S.env.RonisMailMatsDB.targets[REALM].Bob.cats, ","), "Tailoring", "taken off the recipient")
    end)

    test("the Roni's minimap button opens the MailMats tab and can be hidden", function()
        local S = MainAtMailbox(nil)
        local b = S.env.RonisHubMinimapButton
        ok(b and b:IsShown(), "button shown")
        eq(b:GetParent(), S.env.Minimap, "on the minimap")
        b._scripts.OnClick(b, "LeftButton")
        local hub = S.env.RonisHub
        ok(S.env.RonisHubFrame:IsShown(), "Roni's window opened")
        eq(hub.selected, "mailmats", "on the MailMats tab")
        ok(not hub.tabs.health:IsEnabled(), "Health not installed here")
        -- the tab's buttons and settings
        local groups, greens
        for _, f in ipairs(S.frames) do
            if f._type == "Button" and f:GetText() == "Item groups" then groups = f end
            if f._type == "CheckButton" and f.Text and tostring(f.Text:GetText()):find("BoE green") then greens = f end
        end
        groups:Click()
        ok(Win(S):IsShown(), "groups window opened")
        ok(greens:GetChecked(), "greens on by default")
        greens:Click()
        ok(S.env.RonisMailMatsDB.noGreens, "greens off")
        b._scripts.OnClick(b, "LeftButton")
        ok(not S.env.RonisHubFrame:IsShown(), "toggled closed")
        S.Slash("/mailmats", "minimap")
        ok(not b:IsShown(), "hidden")
        local S2 = MainAtMailbox(T.Logout(S))
        ok(not S2.env.RonisHubMinimapButton:IsShown(), "stays hidden after relog")
    end)

    test("the old minimap button's place and hidden state carry over", function()
        local saved = T.Logout(MainAtMailbox(nil))
        saved.RonisMailMatsDB.hub = nil
        saved.RonisMailMatsDB.minimapAngle = 45
        saved.RonisMailMatsDB.hideMinimap = true
        local S = MainAtMailbox(saved)
        eq(S.env.RonisHub:Get("angle"), 45)
        ok(not S.env.RonisHubMinimapButton:IsShown(), "still hidden")
        eq(S.env.RonisMailMatsDB.minimapAngle, nil, "old field cleared")
    end)

    -----------------------------------------------------------------------
    -- Keep mats for: per profession (regression: cloth held for First Aid)
    -----------------------------------------------------------------------
    local FIRST_AID = { line = 129, name = "First Aid", rank = 80, max = 150 }
    local SMITH = { line = 164, name = "Blacksmithing", rank = 105, max = 150 }

    test("regression: a First Aid sender still sends cloth to the tailor", function()
        local S = MainAtMailbox(TailorAltSaved(), { profs = { FIRST_AID } })
        eq(T.Button(S, "Tailoring"):GetText(), "Send Tailoring mats (3)", "linen and wool go")
    end)

    test("held items are listed in the tooltip, and Choose changes what is kept", function()
        local S = MainAtMailbox(TailorAltSaved(), { profs = { SMITH, FIRST_AID } })
        -- Blacksmithing uses Linen Cloth (kept by default), not Wool Cloth
        eq(T.Button(S, "Tailoring"):GetText(), "Send Tailoring mats (1)", "wool only")
        local b = T.Button(S, "Tailoring")
        b._scripts.OnEnter(b)
        contains(S.env.GameTooltip._lines, "Linen Cloth x25 | kept for your Blacksmithing", "reason shown")
        -- the panel says what is kept, and Choose opens the per-profession list
        local choose
        for _, f in ipairs(S.frames) do
            if f._parent == T.Panel(S) and f._text == "Choose" then choose = f end
        end
        ok(choose and choose:IsShown(), "Choose button")
        choose:Click()
        local keep = S.env.RonisMailMatsKeep
        ok(keep and keep:IsShown(), "chooser open")
        local smith
        for _, f in ipairs(S.frames) do
            if f._parent == keep and f._type == "CheckButton" and f._shown then
                if f.prof == "Blacksmithing" then smith = f end
                if f.prof == "First Aid" then ok(not f:GetChecked(), "First Aid not kept by default") end
            end
        end
        ok(smith:GetChecked(), "Blacksmithing kept by default")
        smith:Click()
        eq(T.Button(S, "Tailoring"):GetText(), "Send Tailoring mats (3)", "linen goes after unticking")
        local S2 = MainAtMailbox(T.Logout(S), { profs = { SMITH, FIRST_AID } })
        eq(T.Button(S2, "Tailoring"):GetText(), "Send Tailoring mats (3)", "choice kept after relog")
    end)

    -----------------------------------------------------------------------
    -- Window look: solid, fades only while moving (like the world map)
    -----------------------------------------------------------------------
    test("windows are solid and fade while moving unless hovered", function()
        local S = MainAtMailbox(nil)
        S.Slash("/mailmats", "groups")
        local win = S.env.RonisMailMatsGroups
        eq(win._backdrop.bgFile, "Interface\\Buttons\\WHITE8X8", "solid background")
        local tick = function() for _ = 1, 10 do win._scripts.OnUpdate(win, 0.1) end end
        tick()
        eq(win:GetAlpha(), 1, "standing still: solid")
        S.moving = true
        tick()
        ok(win:GetAlpha() < 0.5, "moving: faded, alpha " .. tostring(win:GetAlpha()))
        win._mouseOver = true
        tick()
        eq(win:GetAlpha(), 1, "moving but hovered: solid")
        win._mouseOver = false
        tick()
        S.moving = false
        tick()
        eq(win:GetAlpha(), 1, "stopped: solid again")
        local panel = T.Panel(S)
        ok(panel._scripts.OnUpdate, "mailbox panel fades too")
    end)

    -----------------------------------------------------------------------
    -- Random mail messages
    -----------------------------------------------------------------------
    local function Body(S) return S.env.SendMailBodyEditBox:GetText() end
    local function MsgButton(S)
        for _, f in ipairs(S.frames) do
            if f._parent == T.Panel(S) and f._text == "New message" then return f end
        end
    end

    test("drafts get a random message with the name and what filled in", function()
        local S = MainAtMailbox(nil, { bags = Bags(LOCKBOX_BAGS) })
        eq(#S.ns.MESSAGES, 100, "100 messages")
        S.Slash("/mailmats", "target Bob Smith: tailoring, scrolls")
        T.Button(S, "Send all to Bob Smith"):Click()
        S.Advance(1)
        local body = Body(S)
        ok(body ~= "", "body filled")
        ok(not body:find("[{}]"), "placeholders replaced: " .. body)
        ok(not body:find("Smith"), "first name only: " .. body)
    end)

    test("New message rotates to a different one and never replaces typed text", function()
        local S = MainAtMailbox(TailorAltSaved())
        T.Button(S, "Tailoring"):Click()
        S.Advance(1)
        local seen, last = {}, Body(S)
        seen[last] = true
        for _ = 1, 30 do
            MsgButton(S):Click()
            local now = Body(S)
            ok(now ~= last, "a different message each click")
            seen[now], last = true, now
        end
        local n = 0
        for _ in pairs(seen) do n = n + 1 end
        ok(n > 10, "many different messages: " .. n)
        S.env.SendMailBodyEditBox:SetText("my own words")
        MsgButton(S):Click()
        eq(Body(S), "my own words", "typed text kept")
        contains(S.printLog, "has your own text", "explained")
        T.Button(S, "Tailoring"):Click()
        S.Advance(1)
        eq(Body(S), "my own words", "drafting again keeps it too")
    end)

    test("/mailmats message off leaves the body empty", function()
        local S = MainAtMailbox(TailorAltSaved())
        S.Slash("/mailmats", "message off")
        T.Button(S, "Tailoring"):Click()
        S.Advance(1)
        eq(Body(S), "", "no message")
        MsgButton(S):Click()
        ok(Body(S) ~= "", "the button still works")
    end)

    -----------------------------------------------------------------------
    -- Waylaid crates, BoE greens for enchanters
    -----------------------------------------------------------------------
    local LW = { line = 165, name = "Leatherworking", rank = 100, max = 150 }
    local ALCH = { line = 171, name = "Alchemy", rank = 100, max = 150 }
    local ENCH = { line = 333, name = "Enchanting", rank = 100, max = 150 }

    test("Waylaid crates go to the profession that fills them", function()
        local saved = T.Logout(T.Login({ name = "Tailor", class = "PRIEST", profs = TAILOR }))
        saved = T.Logout(T.Login({ name = "Leather", class = "ROGUE", profs = { LW } }, saved))
        saved = T.Logout(T.Login({ name = "Herbs", class = "DRUID", profs = { ALCH } }, saved))
        local S = MainAtMailbox(saved, { bags = Bags({ { 248705, 1 }, { 248682, 1 } }) })
        local function count(alt, prof)
            for _, b in ipairs(T.Buttons(S)) do
                if b.alt == alt and b.prof == prof then return b:GetText():match("%((%d+)%)") end
            end
        end
        eq(count("Tailor", "Tailoring"), "1", "fabrics crate to the tailor")
        eq(count("Leather", "Leatherworking"), "1", "and the leatherworker (cured hides)")
        eq(count("Herbs", "Alchemy"), "1", "herb crate to the alchemist")
        ok(S.ns.CRATES[248705] and #S.ns.CRATES[248705] == 2, "crate data loaded")
    end)

    test("BoE green weapons and armor go to Enchanting", function()
        local saved = T.Logout(T.Login({ name = "Dusty", class = "PRIEST", profs = { ENCH } }))
        local bags = Bags({ { 9010, 1 }, { 9011, 1 }, { 9012, 1 }, { 9010, 1, true } })
        local S = MainAtMailbox(saved, { bags = bags })
        local b = T.Button(S, "Enchanting")
        eq(b:GetText(), "Send Enchanting mats (1)", "BoE green only: not BoP, not white, not soulbound")
        S.Slash("/mailmats", "greens off")
        eq(T.Button(S, "Enchanting"):GetText(), "Send Enchanting mats (0)", "greens off")
        S.Slash("/mailmats", "greens on")
        S.Slash("/mailmats", "groups enchanting")
        contains({ S.env.RonisMailMatsGroups.title:GetText() }, "BoE green", "groups window explains it")
    end)

    test("a green that upgrades an alt is not offered for disenchanting", function()
        local saved = T.Logout(T.Login({ name = "Dusty", class = "PRIEST", profs = { ENCH } }))
        saved = T.Logout(T.Login({ name = "Wiz", class = "MAGE", level = 20, equipped = { [1] = 9002 } }, saved))
        local S = MainAtMailbox(saved, { bags = Bags({ { 9001, 1 }, { 9010, 1 } }) })
        eq(T.Button(S, "Enchanting"):GetText(), "Send Enchanting mats (1)", "the axe, not the hood")
        local up
        for _, x in ipairs(T.Buttons(S)) do if x.alt == "Wiz" and x.prof == "Upgrades" then up = x end end
        eq(up and up:GetText(), "Send upgrades (1)", "the hood goes to Wiz")
    end)

    -----------------------------------------------------------------------
    -- Cash on delivery for greens
    -----------------------------------------------------------------------
    local function CodButton(S)
        for _, f in ipairs(S.frames) do
            if f._parent == T.Panel(S) and (f._text or ""):find("^Greens") then return f end
        end
    end

    test("greens to another player ask their vendor price as COD", function()
        -- Green Axe sells for 10c in the mock; Strange Dust is a plain enchanting reagent
        local S = MainAtMailbox(nil, { bags = Bags({ { 9010, 1 }, { 9010, 1 }, { 10940, 5 } }) })
        S.Slash("/mailmats", "target Bob: enchanting")
        T.Button(S, "Send all to Bob"):Click()
        S.Advance(1)
        eq(#S.Attachments(), 3, "two axes and the dust")
        eq(S.mailMoney, 20, "COD = 2 x 10c, the dust is not counted")
        eq(S.mailMode, 2, "COD selected")
        contains(S.printLog, "Cash on delivery: 20c %(100%% of", "told")
        -- after sending, the next draft uses the new share; "off" clears our COD
        local function Again(setting)
            local S2 = MainAtMailbox(T.Logout(S), { bags = Bags({ { 9010, 1 }, { 9010, 1 }, { 10940, 5 } }) })
            S2.Slash("/mailmats", "cod " .. setting)
            T.Button(S2, "Send all to Bob"):Click()
            S2.Advance(1)
            return S2
        end
        eq(Again("50").mailMoney, 10, "50%")
        local S3 = Again("50")
        S3.Slash("/mailmats", "cod off")
        S3.ns.SetDraftCOD("Bob", 20)
        eq(S3.mailMoney, 0, "off clears our COD")
        eq(S3.mailMode, 1, "back to Send Money")
    end)

    test("no COD when the enchanter is one of your characters", function()
        local saved = T.Logout(T.Login({ name = "Dusty", class = "PRIEST", profs = { ENCH } }))
        local S = MainAtMailbox(saved, { bags = Bags({ { 9010, 1 } }) })
        T.Button(S, "Enchanting"):Click()
        S.Advance(1)
        eq(#S.Attachments(), 1, "axe attached")
        eq(S.mailMoney, 0, "no COD to yourself")
        eq(S.mailMode, 1, "money mode untouched")
    end)

    test("the panel button cycles the COD share", function()
        local S = MainAtMailbox(nil)
        local b = CodButton(S)
        eq(b:GetText(), "Greens COD: 100% of vendor", "default")
        b._scripts.OnClick(b, "LeftButton")
        eq(CodButton(S):GetText(), "Greens COD: 150% of vendor", "next")
        b._scripts.OnClick(b, "RightButton")
        b._scripts.OnClick(b, "RightButton")
        eq(CodButton(S):GetText(), "Greens COD: 75% of vendor", "previous twice")
        for _ = 1, 3 do b._scripts.OnClick(b, "RightButton") end
        eq(CodButton(S):GetText(), "Greens: no COD", "off")
        local S2 = MainAtMailbox(T.Logout(S))
        eq(CodButton(S2):GetText(), "Greens: no COD", "kept after relog")
    end)

    -----------------------------------------------------------------------
    -- Upgrades a few levels ahead
    -----------------------------------------------------------------------
    test("gear an alt can wear within a few levels counts as an upgrade", function()
        local saved = T.Logout(T.Login({ name = "Wiz", class = "MAGE", level = 20, equipped = { [1] = 9002 } }))
        local S = MainAtMailbox(saved, { bags = Bags({ { 9013, 1 } }) })
        contains(S.ShowItemTooltip(9013), "Upgrade for Wiz at level 22 %(%+20 item level%)", "level-22 hood for a level-20 alt")
        local up = T.Button(S, "upgrades")
        eq(up:GetText(), "Send upgrades (1)", "offered")
        up._scripts.OnEnter(up)
        contains(S.env.GameTooltip._lines, "Next Level Hood.*%(level 22%)", "marked in the button tooltip")
        S.Slash("/mailmats", "ahead 1")
        local lines = table.concat(S.ShowItemTooltip(9013), " / ")
        ok(not lines:find("Upgrade for"), "1 level ahead: too far: " .. lines)
        S.Slash("/mailmats", "ahead 0")
        contains(S.printLog, "only gear your alts can wear now", "ahead 0")
        local S2 = MainAtMailbox(T.Logout(S), { bags = Bags({ { 9013, 1 } }) })
        ok(not table.concat(S2.ShowItemTooltip(9013), " "):find("Upgrade for"), "setting kept after relog")
    end)
end
