-- Roni's MailMats - recipient suggestions.
--
-- People you might want to set up as recipients, from your friend list,
-- Battle.net friends on this realm, your guild, people you have mailed and
-- people who mailed you. Your own characters and existing recipients are
-- left out. A mage suggests scrolls, a rogue lockboxes.
local ADDON, ns = ...

-- Localized class name -> class token ("Mage" -> "MAGE").
local CLASS_TOKEN
local function ClassToken(name)
    if not name then return nil end
    if RAID_CLASS_COLORS and RAID_CLASS_COLORS[name] then return name end
    if not CLASS_TOKEN then
        CLASS_TOKEN = {}
        for _, t in ipairs({ LOCALIZED_CLASS_NAMES_MALE, LOCALIZED_CLASS_NAMES_FEMALE }) do
            for token, loc in pairs(t or {}) do CLASS_TOKEN[loc] = token end
        end
    end
    return CLASS_TOKEN[name] or name:upper()
end

-- Categories a class is likely to want.
local CLASS_HINT = { MAGE = { "Comprehension" }, ROGUE = { "Lockpicking" } }

-- "Name-Realm" -> "Name" when the realm is ours (mail needs no realm then).
local function Short(name)
    if not name then return nil end
    local n, realm = name:match("^([^-]+)-(.+)$")
    if not n then return name end
    local mine = GetNormalizedRealmName and GetNormalizedRealmName()
    if realm == mine or realm == (ns.realm or ""):gsub("[%s%-]", "") then return n end
    return name
end

---------------------------------------------------------------------------
-- Recent mail partners: every mail you send is remembered (last 15).
---------------------------------------------------------------------------
local MAX_RECENT = 15

function ns.RememberRecipient(name)
    name = Short(strtrim(name or ""))
    if not ns.db or name == "" then return end
    local list = ns.db.recent[ns.realm] or {}
    for i = #list, 1, -1 do
        if list[i]:lower() == name:lower() then table.remove(list, i) end
    end
    table.insert(list, 1, name)
    while #list > MAX_RECENT do table.remove(list) end
    ns.db.recent[ns.realm] = list
end

---------------------------------------------------------------------------
-- Collecting suggestions
---------------------------------------------------------------------------
-- Returns { { name, why = "friend, Mage 30", cats = {...} }, ... }, best first.
function ns.Suggestions(max)
    max = max or 8
    local out, seen = {}, {}
    seen[(ns.me or ""):lower()] = true
    for name in pairs(ns.db.chars[ns.realm] or {}) do seen[name:lower()] = true end
    for name in pairs(ns.db.targets[ns.realm] or {}) do seen[name:lower()] = true end

    local function Add(name, why, class, level)
        name = Short(name)
        if not name or name == "" or name:find("%s") then return end -- NPC senders have spaces
        local key = name:lower()
        if seen[key] then return end
        seen[key] = true
        local token = ClassToken(class)
        local detail = why
        if class then
            local cls = (LOCALIZED_CLASS_NAMES_MALE and token and LOCALIZED_CLASS_NAMES_MALE[token]) or class
            detail = detail .. ", " .. cls .. ((level and level > 0) and (" " .. level) or "")
        end
        out[#out + 1] = { name = name, why = detail, cats = CLASS_HINT[token] or {} }
    end

    -- friends (online first)
    local FL = C_FriendList
    if FL and FL.GetNumFriends and FL.GetFriendInfoByIndex then
        local friends = {}
        for i = 1, FL.GetNumFriends() or 0 do
            local f = FL.GetFriendInfoByIndex(i)
            if f and f.name then friends[#friends + 1] = f end
        end
        table.sort(friends, function(a, b)
            if (a.connected and true) ~= (b.connected and true) then return a.connected and true or false end
            return a.name < b.name
        end)
        for _, f in ipairs(friends) do Add(f.name, "friend", f.className, f.level) end
    end

    -- Battle.net friends playing a character on this realm and faction
    local BN = C_BattleNet
    if BNGetNumFriends and BN and BN.GetFriendNumGameAccounts and BN.GetFriendGameAccountInfo then
        for i = 1, (BNGetNumFriends()) or 0 do
            for j = 1, BN.GetFriendNumGameAccounts(i) or 0 do
                local g = BN.GetFriendGameAccountInfo(i, j)
                if g and g.characterName and g.realmName == ns.realm
                    and (not g.factionName or g.factionName == ns.faction) then
                    Add(g.characterName, "Battle.net friend", g.className, g.characterLevel)
                end
            end
        end
    end

    -- people you mailed, then people who mailed you (open inbox only)
    for _, name in ipairs(ns.db.recent[ns.realm] or {}) do Add(name, "you mailed") end
    if GetInboxNumItems and GetInboxHeaderInfo then
        for i = 1, GetInboxNumItems() or 0 do
            local _, _, sender, _, _, _, _, _, _, _, _, _, isGM = GetInboxHeaderInfo(i)
            if sender and not isGM then Add(sender, "mailed you") end
        end
    end

    -- guild members (online first)
    if IsInGuild and IsInGuild() and GetNumGuildMembers and GetGuildRosterInfo then
        local online, offline = {}, {}
        for i = 1, GetNumGuildMembers() or 0 do
            local name, _, _, level, class, _, _, _, isOnline, _, classFile = GetGuildRosterInfo(i)
            if name then
                table.insert(isOnline and online or offline, { name, classFile or class, level })
            end
        end
        for _, m in ipairs(online) do Add(m[1], "guild", m[2], m[3]) end
        for _, m in ipairs(offline) do Add(m[1], "guild", m[2], m[3]) end
    end

    while #out > max do table.remove(out) end
    return out
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
function ns.InitSocial()
    ns.db.recent = ns.db.recent or {} -- [realm] = { name, ... } most recent first
    -- the guild roster is only filled after asking for it
    if IsInGuild and IsInGuild() and C_GuildInfo and C_GuildInfo.GuildRoster then C_GuildInfo.GuildRoster() end
    if hooksecurefunc and SendMail then
        hooksecurefunc("SendMail", function(name) ns.RememberRecipient(name) end)
    end
end
