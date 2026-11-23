-- The store: kept across logins and characters, pruned when a member leaves, checked when read back.
return function(test, H)
    local function World()
        local w = H.World()
        w:AddPlayer("Kari Berg", { profs = { [171] = { 2330, 2331, 3447 } } })
        w:AddPlayer("Siri Dahl", { profs = { [333] = { 7418, 25124 } } })
        local ola = w:AddClient("Ola Nord", { profs = { [197] = { 2387 } } })
        w:Settle()
        ola:ClickLink("Kari Berg", 171)
        ola:ClickLink("Siri Dahl", 333)
        ola:CloseProfession()
        return w, ola
    end

    test("kept across a reload, and seen by another character of the account", function()
        local w, ola = World()
        ola:Reload()
        H.eq(ola:Holders("Healing Potion"), "Kari Berg")
        H.eq(ola:Holders("Minor Wizard Oil"), "Siri Dahl")
        ola:Logout()
        local alt = w:AddClient("Ola Alt", { saved = ola.saved })
        w:Settle()
        H.eq(alt:Holders("Healing Potion"), "Kari Berg")
    end)

    test("a member who left is pruned by a complete roster, not by an incomplete one", function()
        local w, ola = World()
        w:Leave("Kari Berg")
        w.quirks.rosterPartial = 1
        ola.ns.Guild:Refresh(true)
        w:Run(1)
        H.eq(ola:Holders("Healing Potion"), "Kari Berg", "an incomplete roster deletes nobody")
        w.quirks.rosterPartial = nil
        ola.ns.Guild:Refresh(true)
        w:Run(1)
        H.eq(ola:Holders("Healing Potion"), nil)
        H.eq(ola:Holders("Minor Wizard Oil"), "Siri Dahl")
        H.eq(ola:Logged("Recipes", "pruned 1 who left"), 1)
    end)

    test("another guild's bucket is left alone", function()
        local w, ola = World()
        ola.ns.DB.data.guilds["Others"] = { rev = 0, members = { ["Zed Zed"] = { profs = {} } } }
        ola.ns.Guild:Refresh(true)
        w:Run(1)
        H.ok(ola.ns.DB.data.guilds["Others"].members["Zed Zed"])
    end)

    test("/proff who and /proff forget, by a name's start too", function()
        local w, ola = World()
        ola:Mark()
        ola:Slash("who kari")
        H.eq(H.lines(ola:Said()), "Alchemy: 3 recipes, 150/225, seen just now")
        w:Run(3 * 3600)
        ola:Mark()
        ola:Slash("who Kari Berg")
        H.eq(H.lines(ola:Said()), "Alchemy: 3 recipes, 150/225, seen 3 h ago")
        ola:Mark()
        ola:Slash("who Nobody")
        H.eq(H.lines(ola:Said()), "No recipes stored for Nobody.")
        ola:Mark()
        ola:Slash("forget siri")
        H.eq(H.lines(ola:Said()), "Forgot Siri Dahl's recipes.")
        H.eq(ola:Holders("Minor Wizard Oil"), nil)
        ola:Mark()
        ola:Slash("forget siri")
        H.eq(H.lines(ola:Said()), "Nothing stored for siri.")
    end)

    test("forget one profession; the last one takes the member", function()
        local w, ola = World()
        local R = ola.ns.Recipes
        H.no(R:Forget("Proffene", "Kari Berg", 333))
        H.ok(R:Forget("Proffene", "Kari Berg", 171))
        H.eq(ola:Bucket().members["Kari Berg"], nil)
        H.no(R:Forget("Nowhere", "Kari Berg"))
    end)

    test("a store refuses what isn't its shape", function()
        local w, ola = World()
        local R = ola.ns.Recipes
        H.eq(select(2, R:Store(nil)), "shape")
        H.eq(select(2, R:Store({ guild = "G", who = "A B", line = "x", recipes = {} })), "shape")
        H.eq(select(2, R:Store({ guild = "G", who = "A B", line = 1, recipes = { x = true, [2] = "yes" } })), "empty")
        H.eq(R:Store({ guild = "G", who = "A B", line = 1, recipes = { [5] = true }, info = { [5] = { n = "" } } }), "new")
        H.eq(ola.ns.DB:Recipes()[5], nil, "a blank name isn't kept")
    end)

    test("saved data that isn't our shape is dropped when read", function()
        local w = H.World()
        local saved = { ProffDB = { schema = 1, recipes = { [1] = { n = "Ok" }, [2] = "bad", x = { n = "key" } },
            guilds = { Good = { rev = "7", members = {
                ["A B"] = { profs = { [171] = { name = "Alchemy", recipes = { [1] = true } }, [5] = { recipes = "no" },
                    x = { recipes = {} } } },
                [3] = { profs = {} }, ["C D"] = "bad" } }, [4] = {}, Bad = "x" } } }
        local ola = w:AddClient("Ola Nord", { saved = saved })
        w:Settle()
        local data = ola.ns.DB.data
        H.eq(data.recipes[1].n, "Ok")
        H.eq(data.recipes[2], nil)
        H.eq(data.recipes.x, nil)
        H.eq(data.guilds.Bad, nil)
        H.eq(data.guilds[4], nil)
        local g = data.guilds.Good
        H.eq(g.rev, 7)
        H.eq(g.members["C D"], nil)
        H.eq(g.members[3], nil)
        H.ok(g.members["A B"].profs[171])
        H.eq(g.members["A B"].profs[5], nil)
        H.eq(g.members["A B"].profs.x, nil)
    end)

    test("data from before schemas is migrated; a newer schema is left alone, and nothing's written", function()
        local w = H.World()
        local old = w:AddClient("Ola Nord", { saved = { ProffDB = { guilds = {} } } })
        w:Settle()
        H.eq(old.ns.DB.data.schema, old.ns.DB.SCHEMA)
        H.eq(old:Logged("DB", "migrated to schema 1"), 1)
        H.eq(old:Logged("DB", "migrated to schema 2"), 1)
        local future = { schema = 99, guilds = { Proffene = { rev = 1, members = {}, futureField = true } } }
        local kari = w:AddClient("Kari Berg", { saved = { ProffDB = future }, profs = { [197] = { 2387 } } })
        w:Settle()
        H.ok(kari.ns.DB.data.readOnly)
        kari:OpenProfession(197)
        H.eq(kari:Logged("Capture", "not stored: readonly"), 1)
        kari:Logout()
        H.eq(kari.saved.ProffDB.schema, 99)
        H.ok(kari.saved.ProffDB.guilds.Proffene.futureField)
    end)

    test("a migration runs in order from the saved schema", function()
        local w = H.World()
        local ola = w:AddClient("Ola Nord")
        local DB = ola.ns.DB
        local S, ran = DB.SCHEMA, {}
        DB.SCHEMA = S + 2
        DB.MIGRATIONS[S + 1] = function(db) ran[#ran + 1] = S + 1; db.next = true end
        DB.MIGRATIONS[S + 2] = function(db) ran[#ran + 1] = S + 2; H.ok(db.next) end
        DB:Init()
        H.eq(table.concat(ran, ","), (S + 1) .. "," .. (S + 2))
        H.eq(DB.data.schema, S + 2)
    end)

    test("schema 1 to 2: reagents and their names come; broken ones are dropped", function()
        local w = H.World()
        local v1 = { schema = 1, guilds = {}, recipes = {
            [2330] = { n = "Minor Healing Potion", l = 171 },
            [2331] = { n = "Minor Mana Potion", l = 171, r = { [2447] = 1, x = 2 } },
            [3447] = { n = "Healing Potion", l = 171, r = "lots" },
            [7181] = { n = "Greater Healing Potion", l = 171, r = { [3356] = 1 } } } }
        local ola = w:AddClient("Ola Nord", { saved = { ProffDB = v1 } })
        local data = ola.ns.DB.data
        H.eq(data.schema, ola.ns.DB.SCHEMA)
        H.eq(type(data.items), "table")
        H.eq(data.recipes[2330].r, nil)
        H.eq(data.recipes[2331].r, nil, "a reagent list with a bad key")
        H.eq(data.recipes[3447].r, nil)
        H.eq(data.recipes[7181].r[3356], 1)
        local bad = { schema = 2, guilds = {}, recipes = {}, items = { [2447] = "Peacebloom", [1] = 5, x = "y" } }
        local kari = w:AddClient("Kari Berg", { saved = { ProffDB = bad } })
        H.eq(kari.ns.DB.data.items[2447], "Peacebloom")
        H.eq(kari.ns.DB.data.items[1], nil)
        H.eq(kari.ns.DB.data.items.x, nil)
    end)
end
