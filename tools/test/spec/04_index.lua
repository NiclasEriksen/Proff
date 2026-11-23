-- Search: words in any order and case, the profession's name too, best matches first, built on demand.
return function(test, H)
    local function World()
        local w = H.World()
        w:AddPlayer("Kari Berg", { profs = { [171] = { 2330, 2331, 3447, 7181, 17556 } } })
        w:AddPlayer("Siri Dahl", { profs = { [171] = { 2330, 11457 }, [333] = { 7418, 13661, 25124 } } })
        w:AddPlayer("Per Smed", { profs = { [164] = { 2662, 2663, 3115 } } })
        local ola = w:AddClient("Ola Nord", { profs = { [197] = { 2387, 2393, 3914, 18560 } } })
        w:Settle()
        ola:OpenProfession(197)
        ola:ClickLink("Kari Berg", 171)
        ola:ClickLink("Siri Dahl", 171)
        ola:ClickLink("Siri Dahl", 333)
        ola:ClickLink("Per Smed", 164)
        ola:CloseProfession()
        return w, ola
    end
    local function Names(rows)
        local out = {}
        for i, r in ipairs(rows) do out[i] = r.name end
        return table.concat(out, " | ")
    end

    test("words in any order and case; the whole query starting a name first, then word starts", function()
        local w, ola = World()
        local I = ola.ns.Index
        H.eq(Names(I:Search("Proffene", "healing")),
            "Healing Potion | Greater Healing Potion | Major Healing Potion | Minor Healing Potion | Superior Healing Potion")
        H.eq(Names(I:Search("Proffene", "POTION minor")), "Minor Healing Potion | Minor Mana Potion")
        H.eq(Names(I:Search("Proffene", "heal")), "Healing Potion | Enchant Bracer - Minor Health | Greater Healing Potion"
            .. " | Major Healing Potion | Minor Healing Potion | Superior Healing Potion", "a word's start: name order")
        H.eq(Names(I:Search("Proffene", "otio")), "Greater Healing Potion | Healing Potion | Major Healing Potion | Minor Healing Potion | Minor Mana Potion | Superior Healing Potion",
            "inside a word: last, in name order")
    end)

    test("the profession's name is searched too, and a recipe id", function()
        local w, ola = World()
        local I = ola.ns.Index
        H.eq(Names(I:Search("Proffene", "enchanting bracer")), "Enchant Bracer - Minor Health | Enchant Bracer - Strength")
        H.eq(#I:Search("Proffene", "blacksmithing"), 3)
        H.eq(Names(I:Search("Proffene", "18560")), "Mooncloth")
    end)

    test("holders, line filter, limit and total", function()
        local w, ola = World()
        local I = ola.ns.Index
        local rows = I:Search("Proffene", "minor healing")
        H.eq(H.lines(rows[1].holders), "Kari Berg | Siri Dahl")
        H.eq(rows[1].prof, "Alchemy")
        H.eq(rows[1].line, 171)
        H.ok(rows[1].icon)
        local some, total = I:Search("Proffene", "potion", { limit = 2 })
        H.eq(#some, 2)
        H.eq(total, 6)
        H.eq(Names(I:Search("Proffene", "minor", { line = 333 })), "Minor Wizard Oil | Enchant Bracer - Minor Health")
        H.eq(#I:Search("Proffene", "", {}), 0, "no words: nothing")
        H.eq(#I:Search("Proffene", "  "), 0)
        H.eq(select(2, I:Search("Proffene", "", { all = true, limit = 1 })), 16)
        H.eq(#I:Search("Nowhere", "potion"), 0)
        H.eq(#I:Search("Proffene", nil), 0)
        rows[1].holders[1] = "changed" -- (a copy: the index isn't changed through it)
        H.eq(I:Search("Proffene", "minor healing")[1].holders[1], "Kari Berg")
        H.eq(H.lines(I:Holders("Proffene", 2330)), "Kari Berg | Siri Dahl")
        H.eq(#I:Holders("Proffene", 999999), 0)
        H.eq(#I:Holders("Nowhere", 2330), 0)
    end)

    test("Latin-1 letters fold: a name with Æ found by æ", function()
        local w, ola = World()
        ola.ns.DB:Recipes()[2387] = { n = "Kappe av LIN ÆØÅ", l = 197 }
        ola:Bucket().rev = ola:Bucket().rev + 1
        H.eq(Names(ola.ns.Index:Search("Proffene", "æøå")), "Kappe av LIN ÆØÅ")
    end)

    test("built once per change: a search after a store rebuilds, others don't", function()
        local w, ola = World()
        local I = ola.ns.Index
        I:Search("Proffene", "potion")
        local built = I.built["Proffene"]
        I:Search("Proffene", "cloak")
        H.ok(I.built["Proffene"] == built)
        w.players["Kari Berg"]:Learn(171, { 17635 })
        ola:ClickLink("Kari Berg", 171)
        H.eq(Names(I:Search("Proffene", "titans")), "Flask of the Titans")
        H.ok(I.built["Proffene"] ~= built)
    end)

    test("professions, members and stats", function()
        local w, ola = World()
        local I = ola.ns.Index
        local profs = {}
        for _, p in ipairs(I:Professions("Proffene")) do profs[#profs + 1] = ("%s %d/%d"):format(p.name, p.members, p.recipes) end
        H.eq(table.concat(profs, ", "), "Alchemy 2/6, Blacksmithing 1/3, Enchanting 1/3, Tailoring 1/4")
        local s = I:Stats("Proffene")
        H.eq(s.members, 4)
        H.eq(s.profs, 5)
        H.eq(s.recipes, 16)
        local m = I:Member("Proffene", "Siri Dahl")
        H.eq(#m, 2)
        H.eq(m[1].name, "Alchemy")
        H.eq(m[2].n, 3)
        H.eq(#I:Member("Proffene", "Nobody"), 0)
        H.eq(I:Stats("Nowhere").recipes, 0)
        H.eq(#I:Professions("Nowhere"), 0)
    end)

    test("/proff search and /proff stats print what's found", function()
        local w, ola = World()
        ola:Mark()
        ola:Slash("search minor healing")
        H.eq(H.lines(ola:Said()), "1 recipes match \"minor healing\": | Minor Healing Potion (Alchemy): Kari Berg, Siri Dahl")
        ola.ns.Config.PRINT_LIMIT = 2
        ola:Mark()
        ola:Slash("search potion")
        H.eq(#ola:Said(), 4)
        H.eq(ola:Said()[4], "... and 4 more.")
        ola:Mark()
        ola:Slash("search zzz")
        H.eq(H.lines(ola:Said()), "No recipe matches \"zzz\".")
        ola:Mark()
        ola:Slash("search")
        H.eq(H.lines(ola:Said()), "/proff search <words>: who in the guild knows a recipe.")
        ola:Mark()
        ola:Slash("stats")
        H.eq(H.lines(ola:Said()), "Proffene: 4 members, 5 professions, 16 different recipes.")
        ola:Mark()
        ola:Slash("nonsense")
        H.eq(H.lines(ola:Said()), "/proff search <words> | who <name> | stats | forget <name>")
    end)

    test("outside a guild the commands say so", function()
        local w = H.World()
        local ola = w:AddClient("Ola Nord", { guild = false })
        w:Settle()
        for _, cmd in ipairs({ "search potion", "who", "stats", "forget x" }) do
            ola:Mark()
            ola:Slash(cmd)
            H.eq(H.lines(ola:Said()), "You're not in a guild.", cmd)
        end
    end)
end
