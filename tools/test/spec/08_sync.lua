-- Guild sync's groundwork: the compact text (Pack), addon messages (Comm: paced, chunked, members only, silent),
-- the hello (Sync), and the probe of the server's own guild recipe system.
return function(test, H)
    local function World(quirks)
        local w = H.World()
        for k, v in pairs(quirks or {}) do w.quirks[k] = v end
        w:AddPlayer("Per Fremmed", { guild = false })
        local ola = w:AddClient("Ola Nord", { profs = { [197] = { 2387, 2393 } } })
        local kari = w:AddClient("Kari Berg", { profs = { [171] = { 2330, 3447 } } })
        w:Settle()
        return w, ola, kari
    end

    test("Pack: numbers and recipe sets round trip, small; malformed text is nil", function()
        local w = H.World()
        local P = w:AddClient("Ola Nord").ns.Pack
        for _, n in ipairs({ 0, 1, 31, 32, 1023, 1024, 1263056, 2 ^ 40 - 1 }) do
            local s = P.Num(n)
            H.eq(P.ReadNum(s), n, tostring(n))
            H.eq(select(2, P.ReadNum(s .. "x")), #s + 1, "stops at its own end")
        end
        H.eq(#P.Num(31), 1)
        H.eq(#P.Num(1023), 2)
        H.eq(P.ReadNum(""), nil)
        H.eq(P.ReadNum("0"), nil, "unfinished")
        H.eq(P.ReadNum("|"), nil)
        -- A profession like Enchanting: 104 ids from 7000 up, some of Forever's own past a million.
        local set = {}
        local id = 7000
        for i = 1, 100 do id = id + 1 + (i * 7) % 40; set[id] = true end
        for _, big in ipairs({ 1230643, 1248805, 1263056, 1263060 }) do set[big] = true end
        local s = P.Set(set)
        H.ok(#s < 240, "one message: " .. #s .. " bytes")
        H.no(s:find("[|\t\n]"))
        local back, n = P.ReadSet(s)
        H.eq(n, 104)
        for k in pairs(set) do H.ok(back[k], tostring(k)) end
        H.eq(P.ReadSet(s, 50), nil, "over the max")
        H.eq(P.ReadSet("W"), nil, "a gap of 0")
        H.eq(P.ReadSet(42), nil)
        H.eq(P.Set({ 5, 3, 3 }), P.Set({ [3] = true, [5] = true }), "a list too, duplicates once")
        H.eq(P.Sum(set), P.Sum(back))
        set[7001] = not set[7001] or nil
        H.no(P.Sum(set) == P.Sum(back), "one recipe more or less: another sum")
        H.ok(not pcall(P.Num, -1))
        H.ok(not pcall(P.Num, 1.5))
    end)

    -- Three Proff users (Ola, Kari, Siri) and Nils, a guild member without Proff.
    local function Guild(quirks)
        local w = H.World()
        for k, v in pairs(quirks or {}) do w.quirks[k] = v end
        w:AddPlayer("Nils Tom", { profs = { [333] = { 7418, 13661 } } })
        w:AddPlayer("Per Fremmed", { guild = false, profs = { [164] = { 2662 } } })
        local ola = w:AddClient("Ola Nord", { profs = { [197] = { 2387, 2393 } } })
        local kari = w:AddClient("Kari Berg", { profs = { [171] = { 2330, 3447 } } })
        local siri = w:AddClient("Siri Dahl")
        w:Settle()
        w:Run(70) -- (past everyone's hello)
        return w, ola, kari, siri
    end

    test("relay: what one user captures reaches every user, a non-user's profession too; names found locally", function()
        local w, ola, kari, siri = Guild()
        for _, c in ipairs({ ola, kari, siri }) do c:Mark() end
        ola:OpenProfession(197)
        ola:CloseProfession()
        kari:ClickLink("Nils Tom", 333)
        w:Run(15)
        H.eq(siri:Holders("Linen Cloak"), "Ola Nord", "Ola's own, relayed")
        H.eq(siri:Holders("Enchant Bracer - Strength"), "Nils Tom", "Nils doesn't run Proff: Kari's click was enough")
        H.eq(ola:Holders("Enchant Bracer - Strength"), "Nils Tom")
        H.eq(kari:Holders("Linen Cloak"), "Ola Nord")
        H.eq(w:Sent("D", "Ola Nord"), 1, "one data message each, not one per listener")
        H.eq(w:Sent("D", "Kari Berg"), 1)
        local p = siri:Bucket().members["Nils Tom"].profs[333]
        H.eq(p.via, "Kari Berg")
        H.eq(p.from, "link")
        H.eq(p.at, kari:Bucket().members["Nils Tom"].profs[333].at, "the author's time, not ours")
        -- Siri never saw those recipes: named from their spells ("Enchanting: " dropped), reagents read.
        local r = siri.ns.DB:Recipes()[7418]
        H.eq(r.n, "Enchant Bracer - Minor Health")
        H.ok(r.i)
        H.eq(r.r[10940], 1)
        H.eq(siri:Logged("Spells", "0 recipes named now, 2 asked for"), 2, "asked of the client: Ola's two, Nils' two")
        H.eq(#siri:Said(), 0, "nothing said in chat by sync")
    end)

    test("relayed recipes the client knows: named at once, their reagents' names asked for once for all", function()
        local w, ola, kari, siri = Guild({ spellsCached = true })
        w.players["Kari Berg"]:Learn(171, { 17556 })
        kari:OpenProfession(171)
        kari:CloseProfession()
        w:Run(15)
        H.eq(siri:Holders("Major Healing Potion"), "Kari Berg")
        H.eq(siri.ns.DB:Recipes()[17556].n, "Major Healing Potion")
        H.eq(siri:Logged("Items", "names known now"), 1, "one request for every reagent of the three recipes")
        H.eq(siri:Logged("Items", "0 names known now, 8 asked for"), 1, "(Empty Vial once)")
        H.eq(siri:Logged("Spells", "3 recipes named now, 0 asked for"), 1, "(verify's sync:names)")
    end)

    test("a newcomer catches up after its hello: one index answers, it asks for what it lacks", function()
        local w, ola, kari, siri = Guild()
        ola:OpenProfession(197)
        ola:CloseProfession()
        kari:ClickLink("Nils Tom", 333)
        w:Run(15)
        local mark = w:Mark()
        local tor = w:AddClient("Tor Ny")
        w:Settle()
        w:Run(120)
        H.eq(w:Sent("H", "Tor Ny", mark), 1)
        H.eq(w:Sent("I", nil, mark), 1, "one index: the others had the same, and kept quiet")
        H.eq(w:Sent("R", "Tor Ny", mark), 1)
        H.eq(tor:Holders("Linen Cloak"), "Ola Nord")
        H.eq(tor:Holders("Healing Potion"), nil, "Kari never opened her own window: nobody has it")
        H.eq(tor:Holders("Enchant Bracer - Strength"), "Nils Tom")
        H.eq(#tor:Said(), 0)
        -- Everyone the same now: a reload's hello is answered by nobody.
        mark = w:Mark()
        ola:Reload()
        w:Run(120)
        H.eq(w:Sent("H", "Ola Nord", mark), 1)
        H.eq(w:Sent("I", nil, mark), 0)
        H.eq(w:Sent("D", nil, mark), 0)
    end)

    test("what a newcomer has that others lack is pushed when it hears their index", function()
        local w, ola, kari, siri = Guild()
        local mark = w:Mark()
        local tor = w:AddClient("Tor Ny", { profs = { [164] = { 2662, 2663 } } })
        w:Settle()
        tor:OpenProfession(164) -- (before its hello: stored and offered to all at once)
        tor:CloseProfession()
        w:Run(120)
        H.eq(ola:Holders("Copper Bracers"), "Tor Ny")
        H.eq(siri:Holders("Copper Bracers"), "Tor Ny")
        local _ = mark
    end)

    test("newer wins: an older copy is ignored and answered with ours; outsiders' data and junk dropped", function()
        local w, ola, kari, siri = Guild()
        kari:ClickLink("Nils Tom", 333)
        w:Run(15)
        local old = siri:Bucket().members["Nils Tom"].profs[333].at
        -- Nils learns a recipe; Siri opens his link later: changed, newer, relayed.
        w:Run(120)
        w.players["Nils Tom"]:Learn(333, { 20025 })
        siri:ClickLink("Nils Tom", 333)
        w:Run(15)
        H.ok(kari:Bucket().members["Nils Tom"].profs[333].at > old)
        H.eq(kari:Holders("Enchant Chest - Greater Stats"), "Nils Tom")
        H.eq(kari:Bucket().members["Nils Tom"].profs[333].via, "Siri Dahl")
        -- An older copy (a client that was offline): ignored, and the newer one sent back.
        local set = kari.ns.Pack.Set({ 7418 })
        local mark = w:Mark()
        w:Inject("Tor Gammel", ("SD\t3\tNils Tom\t333\t%d\tlink\t\t\tEnchanting\t%s"):format(old, set))
        w:Run(61)
        H.eq(kari:Holders("Enchant Chest - Greater Stats"), "Nils Tom", "Tor Gammel isn't in the guild: dropped")
        H.eq(kari:Logged("Comm", "dropped: Tor Gammel isn't on our roster"), 1)
        w:Inject("Ola Nord", ("SD\t3\tNils Tom\t333\t%d\tlink\t\t\tEnchanting\t%s"):format(old, set))
        w:Run(15)
        H.eq(kari:Holders("Enchant Chest - Greater Stats"), "Nils Tom", "older: ignored")
        H.eq(w:Sent("D", nil, mark), 1, "and the newer sent once, by one of them")
        -- About someone outside the guild, malformed, from the future: dropped.
        kari:Mark()
        w:Inject("Ola Nord", ("SD\t3\tPer Fremmed\t164\t%d\town\t\t\tBlacksmithing\t%s"):format(old, set))
        w:Inject("Ola Nord", ("SD\t3\tNils Tom\t333\t%d\tlink\t\t\tEnchanting\t%s"):format(w:ServerTime() + 9999, set))
        w:Inject("Ola Nord", "SD\t3\tNils Tom\t333\t1\tlink\t\t\tEnchanting\tW")
        w:Inject("Ola Nord", ("SD\t3\tNils Tom\t333\t%d\tlink\t\t\tEnchanting\t|"):format(old))
        w:Inject("Ola Nord", "SI\t3\tx\t1\t1\t|")
        w:Inject("Ola Nord", "SI\t3\tx\t3\t1\tW")
        w:Inject("Ola Nord", "SR\t3\tKari Berg\t|")
        w:Inject("Ola Nord", "SD\t1\told protocol")
        w:Inject("Ola Nord", "SH\t1\tW\tW")
        w:Run(2)
        H.eq(kari:Logged("Sync", "data from Ola Nord about Per Fremmed: not a member"), 1)
        H.eq(kari:Logged("Sync", "data from Ola Nord: malformed"), 2)
        H.eq(kari:Logged("Sync", "data from Ola Nord: malformed recipes"), 1)
        H.eq(kari:Logged("Sync", "index from Ola Nord: malformed"), 2)
        H.eq(kari:Logged("Sync", "request from Ola Nord: malformed"), 1)
        H.eq(kari:Logged("Sync", "hello from Ola Nord: not ours (1)"), 1)
        H.eq(kari:Bucket().members["Per Fremmed"], nil)
        H.eq(#kari:Said(), 0)
    end)

    test("comm: only guild members, on GUILD, whole and well formed; a long message in parts", function()
        local w, ola, kari = World()
        local got = {}
        kari.ns.Comm:Register("T", function(sender, a, b) got[#got + 1] = sender .. ":" .. tostring(a) .. ":" .. tostring(b) end)
        ola.ns.Comm:Send("T", "x", ("y"):rep(600))
        w:Run(5)
        H.eq(#got, 1)
        H.eq(got[1], "Ola Nord:x:" .. ("y"):rep(600))
        H.eq(w:Sent("T"), 1, "one message ...")
        H.eq(#w.wire - 0 >= 3, true, "... in three parts")
        -- Outsiders, other channels, strays and unknown kinds are dropped; a sender past the size limit ignored.
        w:Inject("Per Fremmed", "ST\tforged\t1")
        w:Inject("Ola Nord", "ST\twhisper\t1", nil, "WHISPER")
        w:Inject("Ola Nord", "Mstray")
        w:Inject("Ola Nord", "SQ\tunknown")
        w:Inject("Ola Nord", "ST\tother prefix", "Other")
        w:Run(61) -- (an unknown sender waits for the next roster)
        H.eq(#got, 1)
        H.eq(kari:Logged("Comm", "dropped: Per Fremmed isn't on our roster"), 1)
        H.eq(kari:Logged("Comm", "unknown kind \"Q\" from Ola Nord"), 1)
        H.eq(kari:Logged("Comm", "stray chunk"), 1)
        w:Inject("Ola Nord", "Fa")
        for _ = 1, 9 do w:Inject("Ola Nord", "Mb") end
        w:Run(1)
        H.eq(kari:Logged("Comm", "ignoring Ola Nord this session"), 1)
        ola.ns.Comm:Send("T", "after", "ignored")
        w:Run(2)
        H.eq(#got, 1, "ignored for the session")
        -- A handler's error is logged, not raised.
        kari.ns.Comm.ignored = {}
        kari.ns.Comm:Register("T", function() error("handler broke") end)
        ola.ns.Comm:Send("T", "a", "b")
        w:Run(2)
        H.eq(kari:Logged("Comm", "handler T failed"), 1)
        -- Too big for anyone to take: not sent. A field with a tab: refused.
        H.eq(ola.ns.Comm:Send("T", ("z"):rep(254 * 9)), false)
        H.ok(not pcall(ola.ns.Comm.Send, ola.ns.Comm, "T", "a\tb"))
        H.ok(not pcall(ola.ns.Comm.Register, ola.ns.Comm, "toolong", print))
    end)

    test("comm: paced under the server's throttle; a Trial account stops trying; outside a guild, deaf", function()
        local w, ola, kari = World()
        local got = 0
        kari.ns.Comm:Register("T", function() got = got + 1 end)
        for i = 1, 30 do ola.ns.Comm:Send("T", tostring(i)) end
        w:Run(2)
        H.ok(got < 30, "not all at once")
        w:Run(70)
        H.eq(got, 30, "all of them, in time")
        H.eq(w.throttled or 0, 0, "never past the server's throttle")
        -- A server that throttles anyway (another addon on our prefix?): the chunk waits and goes.
        local busy = 3
        local send = ola.env.C_ChatInfo.SendAddonMessage
        ola.env.C_ChatInfo.SendAddonMessage = function(...)
            if busy > 0 then busy = busy - 1; return 3 end
            return send(...)
        end
        ola.ns.Comm:Send("T", "late")
        w:Run(20)
        H.eq(got, 31)
        H.ok(ola:Logged("Comm", "busy (code 3)") >= 1)
        -- A Trial account: refused once, then quiet for the session.
        local trial = w:AddClient("Tor Prøve", { trial = true })
        w:Settle()
        w:Run(61)
        H.eq(trial:Logged("Comm", "gave up H: code 7"), 1)
        H.ok(trial.ns.Comm.mute)
        H.eq(trial.ns.Comm:Send("T", "x"), false)
        H.eq(#trial:Said(), 0)
        -- Not in a guild: no listening to every addon's traffic, nothing sent.
        local per = w:AddClient("Per Ute", { guild = false })
        w:Settle()
        H.no(per.ns.Events:Listening("CHAT_MSG_ADDON"))
        H.eq(per.ns.Comm:Send("T", "x"), false)
        H.ok(kari.ns.Events:Listening("CHAT_MSG_ADDON"))
        -- Leaving the guild: deaf from then on.
        kari.player.guild = false
        kari:Fire("PLAYER_GUILD_UPDATE", "player")
        H.no(kari.ns.Events:Listening("CHAT_MSG_ADDON"))
        kari.player.guild = true
        kari:Fire("PLAYER_GUILD_UPDATE", "player")
        H.ok(kari.ns.Events:Listening("CHAT_MSG_ADDON"))
    end)

    test("index text: keys and minutes read back; junk refused", function()
        local w = H.World()
        local S = w:AddClient("Ola Nord").ns.Sync
        local P = S.Key
        local N = w.clients[1].ns.Pack.Num
        local text = P("Kari Berg", 171) .. N(3) .. P("Nils Tom", 333) .. N(5)
        local e = S.ReadIndex(text, 10)
        H.eq(#e, 2)
        H.eq(e[1].key, P("Kari Berg", 171))
        H.eq(e[2].minute, 5)
        H.eq(S.ReadIndex(text, 1), nil, "over the max")
        H.eq(S.ReadIndex("W", 10), nil)
        H.eq(S.ReadIndex(nil, 10), nil)
        H.eq(S.Minute(0), 0)
    end)

    test("/proff probe guild: the server's guild recipe system, answered or not, saved after a wait", function()
        local function Run(quirks)
            local w = H.World()
            for k, v in pairs(quirks or {}) do w.quirks[k] = v end
            w:AddPlayer("Kari Berg", { profs = { [171] = { 2330, 3447 } } })
            local ola = w:AddClient("Ola Nord", { profs = { [171] = { 2330 } } })
            w:Settle()
            ola:OpenProfession(171)
            ola:CloseProfession()
            ola:Mark()
            ola:Slash("probe guild")
            H.eq(ola:CountPrinted("Guild probe asked"), 1)
            w:Run(6)
            H.eq(ola:CountPrinted("Guild probe done"), 1)
            return rawget(ola.env, "ProffDebugDB").probe.guild
        end
        local g = Run()
        H.eq(g.enabled, "true")
        H.eq(g.asked, "line 171, recipe 2330")
        H.eq(g.events.GUILD_RECIPE_KNOWN_BY_MEMBERS, "ok")
        H.eq(#g.fired, 2)
        H.eq(g.post, "line 171, recipe 2330, 2 members")
        H.eq(H.lines(g.members), "\"Kari Berg\", true | \"Ola Nord\", true")
        H.ok(g.tradeSkills > 0)
        H.match(g.tradeSkillRows[1], "Alchemy")
        local off = Run({ guildRecipes = false })
        H.eq(off.enabled, "false")
        H.eq(#off.fired, 0)
        H.eq(off.after.tradeSkills, 0)
    end)

    -- Skill sheets: each Proff user's own levels (secondaries too), read at login, relayed by everyone.
    test("skill sheets: ours read at login and sent; relayed to one who logs in later; a level up sent again", function()
        local w = H.World()
        w:AddPlayer("Nils Tom", { profs = { [333] = { 7418 } } })
        local ola = w:AddClient("Ola Nord", { profs = { [197] = { 2387 }, [185] = { 2538 } } })
        ola.player.skills = { [197] = 300, [185] = 120 }
        local kari = w:AddClient("Kari Berg", { profs = { [171] = { 2330 } } })
        w:Settle()
        w:Run(70)
        local sheet = ola:Bucket().members["Ola Nord"].skills
        H.eq(sheet.lines[197].r, 300)
        H.eq(sheet.lines[185].r, 120, "Cooking: the server's roster leaves it out")
        H.eq(sheet.lines[197].m, 225)
        local got = kari:Bucket().members["Ola Nord"].skills
        H.eq(got.lines[185].r, 120, "sent to the guild")
        H.eq(got.at, sheet.at, "the author's time")
        H.eq(got.via, "Ola Nord")
        H.eq(w:Sent("K", "Ola Nord"), 1)
        -- Ola logs out; Siri logs in later: Kari relays Ola's sheet.
        ola:Logout()
        local siri = w:AddClient("Siri Dahl")
        w:Settle()
        w:Run(120)
        H.eq(siri:Bucket().members["Ola Nord"].skills.lines[185].r, 120, "relayed")
        H.eq(siri:Bucket().members["Ola Nord"].skills.via, "Kari Berg")
        H.eq(siri:Bucket().members["Kari Berg"].skills.lines[171].r, 150)
        -- Ola levels Tailoring and opens it: sent again, newer; unchanged levels aren't.
        ola:Login()
        w:Settle()
        w:Run(120)
        local mark = w:Mark()
        ola.player.skills[197] = 301
        ola:OpenProfession(197)
        ola:CloseProfession()
        w:Run(15)
        H.eq(w:Sent("K", nil, mark), 1)
        H.eq(siri:Bucket().members["Ola Nord"].skills.lines[197].r, 301)
        mark = w:Mark()
        ola:OpenProfession(197)
        ola:CloseProfession()
        w:Run(15)
        H.eq(w:Sent("K", nil, mark), 0, "the same levels: nothing sent")
        H.eq(#siri:Said() + #kari:Said(), 0, "silent")
    end)

    test("skill sheets: older answered with ours; about us, outsiders, junk and old protocols dropped", function()
        local w, ola, kari = World()
        w:Run(70)
        local mine = kari:Bucket().members["Ola Nord"].skills
        H.ok(mine, "Ola's sheet reached Kari")
        local Levels = kari.ns.Sync.Levels
        local old = Levels({ [197] = { r = 100, m = 150 } })
        local mark = w:Mark()
        w:Inject("Kari Berg", ("SK\t3\tOla Nord\t%d\t%s"):format(mine.at - 600, old))
        w:Run(15)
        H.eq(ola:Bucket().members["Ola Nord"].skills.lines[197].r, 150, "ours, never replaced by someone else's")
        H.eq(kari:Bucket().members["Ola Nord"].skills.lines[197].r, 150, "older: ignored")
        H.eq(w:Sent("K", nil, mark), 1, "and the newer sent back")
        local now = w:ServerTime()
        for _, text in ipairs({
            ("SK\t3\tPer Fremmed\t%d\t%s"):format(now, old), -- not a member
            ("SK\t3\tOla Nord\t%d\t%s"):format(now + 9999, old), -- the future
            ("SK\t3\tOla Nord\t%d\t"):format(now), -- no levels
            ("SK\t3\tOla Nord\t%d\t|"):format(now),
            ("SK\t3\tOla Nord\t%d\t%s"):format(now, Levels({ [197] = { r = 5000 } })),
            ("SK\t3\tOla Nord\t%d\t%s%s"):format(now, old, old), -- a line twice
            ("SK\t2\tOla Nord\t%d\t%s"):format(now, old), -- an older protocol
        }) do
            w:Inject("Kari Berg", text)
        end
        w:Run(15)
        H.eq(kari:Bucket().members["Ola Nord"].skills.lines[197].r, 150)
        H.eq(kari:Bucket().members["Per Fremmed"], nil)
        H.eq(kari:Logged("Sync", "skills from Kari Berg: malformed"), 0, "(Kari's own echo isn't heard)")
        H.ok(ola:Logged("Sync", "skills from Kari Berg: malformed") >= 1, "(repeats fold into one line)")
        local L = {}
        for i = 1, 13 do L[i] = { r = 1 } end
        H.eq(kari.ns.Sync.ReadLevels(Levels(L)), nil, "over the limit")
        H.eq(kari.ns.Sync.ReadLevels(Levels({ [1] = { r = 3 } }))[1].m, nil, "max 0: unknown")
        -- A client without the functions: no sheet, nothing else changes.
        local w2 = H.World()
        w2.quirks.noProfessions = true
        local per = w2:AddClient("Per Ute", { profs = { [197] = { 2387 } } })
        w2:Settle()
        w2:Run(70)
        H.eq(per:Bucket(), nil)
        -- A newer sheet about Ola from someone else (forged): Ola keeps hers and doesn't argue.
        mark = w:Mark()
        w:Inject("Kari Berg", ("SK\t3\tOla Nord\t%d\t%s"):format(now, old))
        w:Run(15)
        H.eq(ola:Bucket().members["Ola Nord"].skills.lines[197].r, 150)
        H.eq(ola:Logged("Sync", "skills from Kari Berg about us: ignored"), 1)
        H.eq(w:Sent("K", nil, mark), 0)
    end)
end
