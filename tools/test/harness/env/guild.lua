-- The guild: membership, its name, and the roster. The client has the roster it logged in with
-- (c.rosterCache); C_GuildInfo.GuildRoster asks the server, whose answer (GUILD_ROSTER_UPDATE) refreshes it
-- World.ROSTER_LATENCY later, unless w.quirks.rosterIgnored. w.quirks.rosterPartial = n: only n rows read.
local H, P = ...

return function(c, env)
    local w = c.world
    env.IsInGuild = function() return c.player.guild end
    env.GetGuildInfo = function(unit)
        if unit ~= "player" or not c.player.guild then return nil end
        return w.guildName, "Member", 3, "CAMWOWEU4Realm5PvE"
    end
    env.GetNumGuildMembers = function()
        if not c.player.guild then return 0, 0, 0 end
        local n = #(c.rosterCache or {})
        return n, n, n
    end
    -- name, rankName, rankIndex, level, classDisplayName, zone, publicNote, officerNote, isOnline, status,
    -- class, achievementPoints, achievementRank, isMobile, canSoR, repStanding, guid
    env.GetGuildRosterInfo = function(i)
        local p = c.player.guild and c.rosterCache and c.rosterCache[i]
        if not p then return nil end
        if w.quirks.rosterPartial and i > w.quirks.rosterPartial then return nil end
        local guid = w.quirks.rosterGuid ~= false and p.guid or nil
        return p.name, "Member", 3, 60, "Warrior", "Orgrimmar", "", "", w.byName[p.name] ~= nil and w.byName[p.name].online,
            0, "WARRIOR", 0, 0, false, false, 4, guid
    end
    env.C_GuildInfo = {
        GuildRoster = function()
            c.rosterAsked = (c.rosterAsked or 0) + 1
            if w.quirks.rosterIgnored or not c.player.guild then return end
            w:After(w.ROSTER_LATENCY, function()
                c.rosterCache = w:Roster()
                c:Fire("GUILD_ROSTER_UPDATE", false)
            end, c)
        end,
        IsGuildOfficer = function() return false end,
        -- The server's guild recipe system (retail's): who in the guild knows a recipe, answered a moment later
        -- as GUILD_RECIPE_KNOWN_BY_MEMBERS, read with GetGuildRecipeInfoPostQuery / GetGuildRecipeMember.
        QueryGuildMembersForRecipe = function(line, id)
            c.recipeQueries = (c.recipeQueries or 0) + 1
            if w.quirks.guildRecipes == false or not c.player.guild then return end
            w:After(0.3, function()
                local who = {}
                for _, name in ipairs(w.order) do
                    local p = w.players[name]
                    if p.guild and (p.profs[line] or {})[id] then who[#who + 1] = p end
                end
                c.recipePost = { line = line, id = id, who = who }
                c:Fire("GUILD_RECIPE_KNOWN_BY_MEMBERS")
            end, c)
        end,
    }
    -- The guild's professions roster (Cataclysm's guild profession list): a header per profession, collapsed
    -- (as Forever hands them, probed 2026-11-23), its members under it once expanded (Expand/
    -- CollapseGuildTradeSkillHeader, each answered by GUILD_TRADESKILL_UPDATE a moment later). A member's skill:
    -- p.skills[line] or p.rank. w.quirks.guildRecipes = false: the server answers none of this;
    -- w.quirks.noSkillRows: expanding shows no members (a server that keeps them to itself).
    c.skillOpen = c.skillOpen or {}
    local function Build()
        local rows = {}
        local lines = {}
        for line, prof in pairs(H.PROFESSIONS) do
            if not prof.secondary then lines[#lines + 1] = line end
        end
        table.sort(lines, function(a, b) return H.PROFESSIONS[a].name < H.PROFESSIONS[b].name end)
        for _, line in ipairs(lines) do
            local members = {}
            for _, name in ipairs(w.order) do
                local p = w.players[name]
                if p.guild and p.profs[line] then members[#members + 1] = p end
            end
            if #members > 0 then
                local open = c.skillOpen[line] == true
                rows[#rows + 1] = { header = true, line = line, name = H.PROFESSIONS[line].name, n = #members, collapsed = not open }
                if open and not w.quirks.noSkillRows then
                    for _, p in ipairs(members) do rows[#rows + 1] = { line = line, player = p } end
                end
            end
        end
        rows[#rows + 1] = { header = true, line = 2933, name = "Test Profession [DNT]", n = 0, collapsed = true }
        c.guildSkills = rows
    end
    local function Answer()
        w:After(0.05, function()
            Build()
            c:Fire("GUILD_TRADESKILL_UPDATE")
        end, c)
    end
    env.CanViewGuildRecipes = function() return w.quirks.guildRecipes ~= false end
    env.QueryGuildRecipes = function()
        c.skillQueries = (c.skillQueries or 0) + 1
        if w.quirks.guildRecipes == false or not c.player.guild then return end
        Answer()
    end
    env.ExpandGuildTradeSkillHeader = function(line) c.skillOpen[line] = true; Build(); Answer() end
    env.CollapseGuildTradeSkillHeader = function(line) c.skillOpen[line] = nil; Build(); Answer() end
    env.GetNumGuildTradeSkill = function() return #(c.guildSkills or {}) end
    -- skillID, isCollapsed, iconTexture, headerName, numOnline, numVisible, numPlayers, playerName,
    -- playerNameWithRealm, class, online, zone, skill, classFileName, isMobile, isAway
    env.GetGuildTradeSkillInfo = function(i)
        local r = (c.guildSkills or {})[i]
        if not r then return nil end
        if r.header then return r.line, r.collapsed, 136240 + r.line % 100, r.name, r.n, r.n, r.n end
        local p = r.player
        local online = w.byName[p.name] ~= nil and w.byName[p.name].online or false
        return r.line, nil, nil, nil, nil, nil, nil, p.name, p.name, "Warrior", online, "Orgrimmar",
            (p.skills or {})[r.line] or p.rank, "WARRIOR", false, false
    end
    env.GetGuildRecipeInfoPostQuery = function()
        local q = c.recipePost
        if not q then return nil end
        return q.line, q.id, #q.who
    end
    env.GetGuildRecipeMember = function(i)
        local p = c.recipePost and c.recipePost.who[i]
        if not p then return nil end
        return p.name, true
    end
end
