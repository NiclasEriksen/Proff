-- The Guild page's views (Recipes, Members: tabs under the window) and the Members view: who has which
-- profession at what skill, from the server's guild profession roster and what Proff stored.
return function(test, H)
    local function World(quirks)
        local w = H.World()
        for k, v in pairs(quirks or {}) do w.quirks[k] = v end
        w:AddPlayer("Kari Berg", { profs = { [171] = { 2330 }, [333] = { 7418 } }, skills = { [171] = 280, [333] = 120 } })
        w:AddPlayer("Siri Dahl", { profs = { [171] = { 2330 } }, skills = { [171] = 280 } })
        w:AddPlayer("Arne Dahl", { profs = { [171] = { 2330 } }, skills = { [171] = 250 } })
        w:AddPlayer("Per Smed", { profs = { [164] = { 2662 } }, skills = { [164] = 75 } })
        w:AddPlayer("Per Fremmed", { guild = false, profs = { [164] = { 2662 } } })
        local ola = w:AddClient("Ola Nord", { profs = { [197] = { 2387 } } })
        w:Settle()
        return w, ola
    end
    local function Members(ola)
        ola:OpenProfession(197)
        ola:OpenGuildTab()
        local tabs = ola.ns.GuildTab:Cover().tabs
        tabs[2]:Click()
        ola.world:Run(0.5)
        return ola.ns.GuildMembers
    end
    -- The rows in view: "name: cell cell ..." (cells "-" when empty).
    local function Shown(ola)
        local out = {}
        for _, row in ipairs(ola.ns.GuildMembers.rows) do
            if row:IsShown() and row.data then
                local cells = {}
                for i = 1, #ola.ns.GuildMembers.columns do
                    local t = row.cells[i].plain
                    cells[i] = t == "" and "-" or t
                end
                out[#out + 1] = H.StripColors(row.name.text) .. ": " .. table.concat(cells, " ")
            end
        end
        return table.concat(out, " | ")
    end
    H.StripColors = H.StripColors or function(s) return (s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end

    test("two views under the window: Recipes when the page opens, Members a click away", function()
        local w, ola = World()
        ola:OpenProfession(197)
        ola:OpenGuildTab()
        local T = ola.ns.GuildTab
        local tabs = T:Cover().tabs
        H.eq(#tabs, 2)
        H.eq(tabs[1].Text.text, "Recipes")
        H.eq(tabs[2].Text.text, "Members")
        H.eq(tabs[1].points[1][2], ola.env.ProfessionsFrame, "under the window's bottom edge")
        H.eq(T:View(), "recipes")
        tabs[2]:Click()
        H.eq(T:View(), "members")
        H.no(ola:GuildPage().box:IsVisible())
        T:Close()
        T:Open()
        H.eq(T:View(), "recipes", "Recipes again when the page opens")
        T:Close()
        H.no(tabs[1]:IsVisible(), "the tabs go with the page")
    end)

    test("members: a slim column per profession, skill in the cell, nothing without; the server's roster restored", function()
        local w, ola = World()
        local M = Members(ola)
        local names = {}
        for _, c in ipairs(M.columns) do names[#names + 1] = c.name end
        H.eq(table.concat(names, ", "), "Alchemy, Blacksmithing, Enchanting, Tailoring")
        H.eq(Shown(ola), "Arne Dahl: 250 - - - | Kari Berg: 280 - 120 - | Ola Nord: - - - 150 | Per Smed: - 75 - -"
            .. " | Siri Dahl: 280 - - -", "by name at first")
        H.eq(M.count.text, "5 members")
        H.eq(next(ola.skillOpen), nil, "the headers we opened, collapsed again")
        H.eq(ola:Logged("Skills", "expanded: 4 professions, 6 member rows, 4 headers expanded"), 1)
        H.eq(ola:Logged("Skills", " professions, "), 1, "read once: the updates our own expanding fires ignored")
        H.no(ola.ns.Events:Listening("GUILD_TRADESKILL_UPDATE"), "heard only while asking")
        -- A column's head: the icon only, its name on hover.
        local head = M.heads[1]
        H.ok(head.icon.tex)
        head:Run("OnEnter")
        H.match(ola.env.GameTooltip:Said(), "^Alchemy | 3 members")
        -- A row's hover: each profession with its skill, and the recipes Proff knows.
        M.rows[3]:Run("OnEnter")
        H.eq(H.StripColors(ola.env.GameTooltip:Said()), "Ola Nord | Tailoring 150 (1 recipes known)")
    end)

    test("a server that answers expanding a moment later (not inside the call): read once, closed again", function()
        local w, ola = World({ skillAsync = true })
        Members(ola)
        H.eq(Shown(ola), "Arne Dahl: 250 - - - | Kari Berg: 280 - 120 - | Ola Nord: - - - 150 | Per Smed: - 75 - -"
            .. " | Siri Dahl: 280 - - -")
        H.eq(ola:Logged("Skills", " professions, "), 1)
        H.eq(next(ola.skillOpen), nil)
    end)

    test("sorting by a profession: who has it first, highest skill first, then first name; the name head sorts back", function()
        local w, ola = World()
        local M = Members(ola)
        M.heads[1]:Click()
        H.eq(Shown(ola), "Kari Berg: 280 - 120 - | Siri Dahl: 280 - - - | Arne Dahl: 250 - - - | Ola Nord: - - - 150"
            .. " | Per Smed: - 75 - -", "highest first (Arne's 250 under the 280s), then first name")
        H.ok(M.heads[1].sorted:IsShown())
        H.no(M.nameHead.sorted:IsShown())
        M.heads[2]:Click()
        H.eq(Shown(ola):match("^[^:]+"), "Per Smed")
        M.nameHead:Click()
        H.eq(Shown(ola):match("^[^:]+"), "Arne Dahl")
        H.ok(M.nameHead.sorted:IsShown())
    end)

    test("asked of the server once a minute at most; without its members, the ranks Proff stored", function()
        local w, ola = World()
        Members(ola)
        local asked = ola.skillQueries
        ola.ns.GuildTab:Close()
        ola.ns.GuildTab:Open()
        ola.ns.GuildTab:ShowView("members")
        w:Run(1)
        H.eq(ola.skillQueries, asked, "not again within the minute")
        w:Run(61)
        ola.ns.GuildTab:ShowView("recipes")
        ola.ns.GuildTab:ShowView("members")
        w:Run(1)
        H.eq(ola.skillQueries, asked + 1)
        -- A server that keeps the members to itself, or answers nothing: what Proff stored (rank with recipes).
        -- (the server's headers still give every profession its column)
        for _, q in ipairs({ { { noSkillRows = true }, "Kari Berg: - - 150 - | Ola Nord: - - - 150" },
            { { guildRecipes = false }, "Kari Berg: 150 - | Ola Nord: - 150" } }) do
            local w2, kari = World(q[1])
            kari:ClickLink("Kari Berg", 333)
            Members(kari)
            H.eq(Shown(kari), q[2], next(q[1]))
            w2:Run(6)
            H.eq(next(kari.skillOpen), nil, "collapsed again")
        end
        -- Recipes stored but no skill known: "?", and sorted under every known skill.
        local w3, siri = World({ guildRecipes = false })
        siri:ClickLink("Kari Berg", 333)
        siri:Bucket().members["Kari Berg"].profs[333].rank = nil
        local M = Members(siri)
        H.eq(Shown(siri), "Kari Berg: ? - | Ola Nord: - 150")
        M.heads[1]:Click()
        H.eq(Shown(siri), "Kari Berg: ? - | Ola Nord: - 150")
        -- Not in a guild: said so.
        local w4 = H.World()
        local per = w4:AddClient("Per Ute", { guild = false, profs = { [197] = { 2387 } } })
        w4:Settle()
        Members(per)
        H.eq(per.ns.GuildMembers.empty.text, "You're not in a guild.")
    end)

    test("skills colored by band; Forever's 1 for a primary profession is 'unknown', a stored rank wins", function()
        local w = H.World()
        w:AddPlayer("Kari Berg", { profs = { [171] = { 2330 }, [333] = { 7418 } }, skills = { [171] = 1, [333] = 300 } })
        w:AddPlayer("Siri Dahl", { profs = { [171] = { 2330 } }, skills = { [171] = 1 } })
        w:AddPlayer("Arne Dahl", { profs = { [171] = { 2330 } }, skills = { [171] = 201 } })
        w:AddPlayer("Per Smed", { profs = { [164] = { 2662 } }, skills = { [164] = 100 } })
        local ola = w:AddClient("Ola Nord", { profs = { [197] = { 2387 } } })
        w:Settle()
        w.players["Siri Dahl"].rank = 250
        ola:ClickLink("Siri Dahl", 171) -- (her link: rank 250 stored)
        local M = Members(ola)
        H.eq(Shown(ola), "Arne Dahl: 201 - - - | Kari Berg: ? - 300 - | Ola Nord: - - - 150 | Per Smed: - 100 - -"
            .. " | Siri Dahl: 250 - - -")
        M.heads[1]:Click()
        H.eq(Shown(ola):match("^(.-) | Ola"), "Siri Dahl: 250 - - - | Arne Dahl: 201 - - - | Kari Berg: ? - 300 -",
            "unknown under every known skill")
        local SC = M.SkillColor
        H.eq(SC(300), "66ccff"); H.eq(SC(301), "66ccff")
        H.eq(SC(299), "ff8040"); H.eq(SC(225), "ff8040")
        H.eq(SC(224), "ffff00"); H.eq(SC(150), "ffff00")
        H.eq(SC(149), "40c040"); H.eq(SC(75), "40c040")
        H.eq(SC(74), "808080"); H.eq(SC(1), "808080")
        H.match(M.rows[1].cells[1].text, "^|cffff8040250|r$")
        -- The grid: a filled cell where they have it (its band's color; grey when the skill is unknown), none where
        -- not; a line on each column's edge, one after the last.
        H.eq(table.concat(M.rows[1].fills[1].color, ","), "1,0.50196078431373,0.25098039215686,0.22")
        H.ok(M.rows[1].fills[1]:IsShown())
        H.no(M.rows[1].fills[2]:IsShown())
        H.eq(table.concat(M.rows[3].fills[1].color, ","), "0.6,0.6,0.6,0.16", "Kari's unknown Alchemy")
        H.eq(#M.bands, #M.columns + 1)
        for _, line in ipairs(M.bands) do H.ok(line:IsShown()) end
        H.eq(M.bands[2].points[1][4], M.heads[2].points[1][4], "a line where its column's head starts")
        H.ok(ola:Logged("Skills", "a member row: ") >= 1, "a raw row in the log, to see what Forever sends")
        -- The tabs: side by side, not overlapping.
        local tabs = ola.ns.GuildTab:Cover().tabs
        H.eq(tabs[2].points[1][2], tabs[1])
        H.eq(tabs[2].points[1][4], 3)
    end)

    test("secondary professions last, at the right; the rest by name", function()
        local w = H.World()
        w:AddPlayer("Kari Berg", { profs = { [185] = { 2538 }, [333] = { 7418 } }, skills = { [333] = 120 } })
        local ola = w:AddClient("Ola Nord", { profs = { [197] = { 2387 } } })
        w:Settle()
        w.players["Kari Berg"].rank = 90
        ola:ClickLink("Kari Berg", 185)
        local M = Members(ola)
        local names = {}
        for _, c in ipairs(M.columns) do names[#names + 1] = c.name end
        H.eq(table.concat(names, ", "), "Enchanting, Tailoring, Cooking")
        H.eq(Shown(ola), "Kari Berg: 120 - 90 | Ola Nord: - 150 -")
    end)

    test("skill sheets fill in what the server doesn't say: real levels, secondary professions", function()
        local w = H.World()
        local kari = w:AddClient("Kari Berg", { profs = { [333] = { 7418 }, [185] = { 2538 } } })
        kari.player.skills = { [333] = 280, [185] = 225 }
        local ola = w:AddClient("Ola Nord", { profs = { [197] = { 2387 } } })
        w:Settle()
        w:Run(70)
        kari.player.skills = { [333] = 1 } -- (what Forever's roster says from here on; her sheet knows better)
        local M = Members(ola)
        local names = {}
        for _, c in ipairs(M.columns) do names[#names + 1] = c.name end
        H.eq(table.concat(names, ", "), "Enchanting, Tailoring, Cooking", "Cooking from her sheet, at the right")
        H.eq(Shown(ola), "Kari Berg: 280 - 225 | Ola Nord: - 150 -")
    end)

    test("a header someone left open stays open; the collapsed ones are still opened, read, and closed again", function()
        local w = H.World()
        w:AddPlayer("Kari Berg", { profs = { [171] = { 2330 }, [333] = { 7418 } }, skills = { [171] = 280, [333] = 120 } })
        w:AddPlayer("Per Smed", { profs = { [164] = { 2662 } }, skills = { [164] = 75 } })
        local ola = w:AddClient("Ola Nord", { profs = { [197] = { 2387 } } })
        w:Settle()
        ola.env.ExpandGuildTradeSkillHeader(171) -- (Blizzard's guild window left Alchemy open)
        w:Run(1)
        Members(ola)
        H.eq(Shown(ola), "Kari Berg: 280 - 120 - | Ola Nord: - - - 150 | Per Smed: - 75 - -")
        H.ok(ola.skillOpen[171], "theirs still open")
        H.eq(ola.skillOpen[333], nil, "ours closed again")
        H.eq(ola:Logged("Skills", "expanded: 4 professions, 4 member rows, 3 headers expanded"), 1)
        -- Our own skill went up and we open the profession again (same recipes): shown at once, while it's open.
        ola.player.rank = 175
        ola.ns.GuildTab:Close()
        ola:CloseProfession()
        ola:OpenProfession(197)
        ola:OpenGuildTab()
        ola.ns.GuildTab:ShowView("members")
        w:Run(1)
        H.match(Shown(ola), "Ola Nord: %- %- %- 175")
    end)
end
