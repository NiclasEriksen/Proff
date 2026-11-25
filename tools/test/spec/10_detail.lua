-- Blizzard's guild member detail panel: the member's primary professions as small icons, their skill and the
-- recipes Proff has on hover; hooked so Guild Roster Manager's script replacements can't undo it.
return function(test, H)
    local function World(quirks)
        local w = H.World()
        for k, v in pairs(quirks or {}) do w.quirks[k] = v end
        w:AddPlayer("Kari Berg", { profs = { [171] = { 2330 }, [333] = { 7418 } } })
        w:AddPlayer("Per Smed", { profs = { [164] = { 2662 } } })
        local ola = w:AddClient("Ola Nord", { profs = { [197] = { 2387 } } })
        w:Settle()
        return w, ola
    end
    local function Icons(c)
        local out = {}
        for _, b in ipairs(c.ns.MemberDetail.icons) do
            if b:IsShown() then out[#out + 1] = tostring(b.line) end
        end
        return table.concat(out, " ")
    end

    test("a member's primaries as icons; hovering says skill and recipes, or that Proff doesn't know", function()
        local w, ola = World()
        H.eq(ola.ns.MemberDetail.panel, nil, "nothing until Blizzard's guild window loads")
        ola:ClickLink("Kari Berg", 333) -- (stored: Enchanting, rank 150 of 225)
        local d = ola:ShowMember("Kari Berg")
        H.eq(ola.ns.MemberDetail.panel, d)
        H.eq(Icons(ola), "171 333", "the club's two, in its order")
        local icons = ola.ns.MemberDetail.icons
        H.eq(icons[1]:GetParent(), d, "inside the panel")
        H.eq(icons[1].points[1][1], "TOPRIGHT")
        H.eq(icons[2].points[1][4], -14 - 19, "the second to the left of the first")
        H.eq(icons[1].tex.tex, 136240 + 71, "Alchemy's")
        icons[2]:Run("OnEnter")
        H.eq(ola.env.GameTooltip:Said(), "Enchanting | Skill |cffffff00150|r/225 | 1 recipes known to Proff, seen just now")
        icons[1]:Run("OnEnter")
        H.eq(ola.env.GameTooltip:Said(), "Alchemy | Skill not known to Proff | Proff hasn't seen their recipes")
        icons[1]:Run("OnLeave")
        H.eq(ola.env.GameTooltip:Said(), nil)
        -- Another member: one profession, the second icon hidden.
        ola:ShowMember("Per Smed")
        H.eq(Icons(ola), "164")
        H.eq(ola:Logged("Detail", "shown: Per Smed, 1 professions"), 1)
        -- No professions in the member's info: the primaries Proff knows (Enchanting, not her Cooking).
        ola.ns.Skills:Store(ola.ns.GuildKey(), "Kari Berg", { [185] = { r = 100, m = 150 }, [333] = { r = 200, m = 225 } }, 5)
        d:DisplayMember(215736082, { name = "Kari Berg" })
        H.eq(Icons(ola), "333")
        icons[1]:Run("OnEnter")
        H.match(ola.env.GameTooltip:Said(), "^Enchanting | Skill |cffffff00200|r/225 |", "the higher: her sheet's")
        -- (and the tooltip follows when the panel changes under the mouse)
        ola:ShowMember("Per Smed")
        H.eq(ola.env.GameTooltip:Said(), "Blacksmithing | Skill not known to Proff | Proff hasn't seen their recipes")
        -- No member info at all: the name the panel shows.
        ola.ns.MemberDetail:Show(d, nil)
        H.eq(Icons(ola), "", "Per Smed: nothing Proff knows")
        d.Name:SetText("Kari Berg")
        ola.ns.MemberDetail:Show(d, nil)
        H.eq(Icons(ola), "333")
    end)

    test("Guild Roster Manager's way: the panel's scripts replaced, our icons still follow", function()
        local w, ola = World()
        local d = ola:ShowMember("Kari Berg")
        -- (what it does: SetScript on OnShow/OnHide, dropping anything hooked before; text above, a button below)
        d:SetScript("OnShow", function(self) self.grm = true end)
        d:SetScript("OnHide", function() end)
        d:Hide()
        ola:ShowMember("Per Smed")
        H.eq(Icons(ola), "164")
        H.ok(d.grm)
        H.eq(ola:Logged("Detail", "attached"), 1)
    end)

    test("the guild window loaded before us: attached at login; no CommunitiesFrame: nothing", function()
        local w = H.World()
        w:AddPlayer("Kari Berg", { profs = { [171] = { 2330 } } })
        local ola = w:AddClient("Ola Nord", { profs = { [197] = { 2387 } },
            patch = function(env, c) H.MakeCommunitiesFrame(c, env) end })
        w:Settle()
        H.ok(ola.ns.MemberDetail.panel)
        ola:ShowMember("Kari Berg")
        H.eq(Icons(ola), "171")
    end)
end
