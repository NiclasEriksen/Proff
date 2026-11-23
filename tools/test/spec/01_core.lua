-- The addon's frame: loading, the stub client's honesty, the TOC, helpers, events, the debug log.
return function(test, H)
    test("logs in clean, and reads no global the stub client lacks but the optional ones", function()
        local w, ola = H.Setup{ { "Ola Nord", { profs = { [197] = { 2387, 2393 } } } } }
        ola:OpenProfession(197)
        ola:ClickLink("Ola Nord", 197)
        ola:Slash("search linen")
        ola:Slash("probe")
        -- Read only behind an existence check (Dev/Errors: BugGrabber, EventRegistry; Init: GetAddOnMetadata).
        local OPTIONAL = { BugGrabber = true, EventRegistry = true, GetAddOnMetadata = true,
            ProffDB = true, ProffDebugDB = true } -- (ours: nil until the first logout writes them)
        for k in pairs(ola.missingGlobals) do
            H.ok(OPTIONAL[k], "read a global the stub client lacks: " .. tostring(k))
        end
    end)

    test("the stub client lacks what Forever lacks", function()
        local w, ola = H.Setup{ "Ola Nord" }
        for _, g in ipairs(H.MISSING.globals) do H.eq(rawget(ola.env, g), nil, g) end
        local f = ola.env.CreateFrame("Frame")
        for _, e in ipairs(H.MISSING.events) do H.no(pcall(f.RegisterEvent, f, e), e) end
        H.no(pcall(function() return f.SetBackdrop end), "an unknown frame method throws")
    end)

    test("the TOC: every file exists, Dev/ only in a checkout, the version token", function()
        local toc = H.TOC
        H.eq(toc.meta.Interface, "16001")
        H.eq(toc.meta.Version, "dev")
        H.eq(toc.meta.SavedVariables, "ProffDB, ProffDebugDB")
        for _, f in ipairs(toc.files) do H.ok(io.open(f), "missing " .. f) end
        for _, f in ipairs(toc.release) do H.no(f:find("^Dev/"), "packaged: " .. f) end
        H.ok(#toc.release < #toc.files)
        local text = io.open("Proff.toc"):read("*a")
        H.match(text, "#@non%-debug@\n# ## Version: @project%-version@\n#@end%-non%-debug@")
    end)

    test("a release has no developer commands and keeps no log", function()
        local w = H.World()
        local ola = w:AddClient("Ola Nord", { release = true, saved = { ProffDebugDB = { enabled = true, lines = { head = 1, "x" } } } })
        w:Settle()
        H.no(ola.ns.DEV)
        H.eq(ola.ns.VERSION, "v1.0.0")
        ola:Mark()
        ola:Slash("probe")
        H.eq(ola:CountPrinted("/proff search"), 1, "the help, not a probe")
        H.eq(ola.ns.Commands.list.debug, nil)
        H.no(ola.ns.Debug.enabled)
        H.eq(#ola:Log(), 0)
    end)

    test("names: realms stripped, surnames kept, secrets and blanks nil", function()
        local w, ola = H.Setup{ "Ola Nord" }
        local N = ola.ns.NormalizeName
        H.eq(N("Kari Berg-CAMWOWEU4Realm5PvE"), "Kari Berg")
        H.eq(N("Kari Berg-Hansen"), "Kari Berg-Hansen")
        H.eq(N("  Kari Berg "), "Kari Berg")
        H.eq(N(""), nil)
        H.eq(N(nil), nil)
        H.eq(N(H.SECRET), nil)
        H.eq(ola.ns.PlayerKey(), "Ola Nord")
        H.eq(ola.ns.Fold("ÆØÅ Élan ×"), "æøå élan ×")
        H.eq(ola.ns.Fold("Major HEALING"), "major healing")
        H.eq(ola.ns.T("search.none", { q = "x" }), "No recipe matches \"x\".")
        H.eq(ola.ns.L["no.such.key"], "no.such.key")
        H.ok(ola.ns.Yes(function() return 1 end))
        H.no(ola.ns.Yes(function() return 0 end))
        H.no(ola.ns.Yes(function() error("x") end))
        H.no(ola.ns.Yes(function() return H.SECRET end))
        H.no(ola.ns.Yes(nil))
    end)

    test("ns.Read: a client call's values, secrets nil, and always one value (tostring can't throw)", function()
        local w = H.World()
        local ola = w:AddClient("Ola Nord")
        local Read = ola.ns.Read
        H.eq(select("#", Read(function() end)), 1, "nothing returned: one nil")
        H.eq(select("#", Read(function() return nil end)), 1)
        H.eq(tostring(Read(function() end)), "nil")
        H.eq(select("#", Read(nil)), 1)
        H.eq(select("#", Read(error)), 1)
        local a, b, c = Read(function() return 1, H.SECRET, 3 end)
        H.eq(a, 1); H.eq(b, nil); H.eq(c, 3)
    end)

    test("the Bus refuses undeclared events; a handler's error is reported, the rest still run", function()
        local w, ola = H.Setup{ "Ola Nord" }
        local Bus = ola.ns.Bus
        H.no(pcall(Bus.Fire, Bus, "NOPE"))
        H.no(pcall(Bus.On, Bus, "NOPE", {}, function() end))
        local ran = false
        Bus:On("DEBUG", "a", function() error("boom") end)
        Bus:On("DEBUG", "b", function() ran = true end)
        Bus:Fire("DEBUG", true)
        H.ok(ran)
        H.eq(#ola:TakeErrors(), 1)
        Bus:Off("DEBUG", "a")
        Bus:Off("DEBUG", "b")
    end)

    test("events: an unknown one is refused and logged, the last listener's Off unregisters", function()
        local w, ola = H.Setup{ "Ola Nord" }
        local E = ola.ns.Events
        H.no(E:On("NO_SUCH_EVENT", {}, function() end))
        H.eq(ola:Logged("Events", "unknown event NO_SUCH_EVENT"), 1)
        local a, b = {}, {}
        local n = 0
        E:On("SKILL_LINES_CHANGED", a, function() n = n + 1; E:Off("SKILL_LINES_CHANGED", b) end)
        E:On("SKILL_LINES_CHANGED", b, function() n = n + 10 end)
        ola:Fire("SKILL_LINES_CHANGED")
        H.ok(n == 1 or n == 11, "b may or may not have run first")
        H.ok(E:Listening("SKILL_LINES_CHANGED", a))
        E:Off("SKILL_LINES_CHANGED", a)
        H.no(ola:Listening("SKILL_LINES_CHANGED"))
        E:Off("SKILL_LINES_CHANGED", a) -- (again: nothing)
        local bad = {}
        E:On("SKILL_LINES_CHANGED", bad, function() error("handler") end)
        ola:Fire("SKILL_LINES_CHANGED")
        H.eq(#ola:TakeErrors(), 1)
    end)

    test("the debug log: a session line, repeats folded, the ring wraps, mute, clear, echo", function()
        local w, ola = H.Setup{ "Ola Nord" }
        local ns = ola.ns
        H.eq(ola:Logged("Session", "start dev, Ola Nord"), 1)
        ns.Log("T", "same")
        ns.Log("T", "same")
        ns.Log("T", "same")
        local log = ola:Log()
        H.match(log[#log], "\tT\tsame %(x3%)$")
        ns.Log("T", "bad %d", "x") -- (a format error logs the format)
        H.match(ola:Log()[#ola:Log()], "bad %%d$")
        ns.Debug:Mute("T", true)
        ns.Log("T", "quiet")
        H.eq(ola:Logged("T", "quiet"), 0)
        H.eq(H.lines(ns.Debug:Mute()), "T")
        ns.Debug:Mute("T", false)
        ns.Config.DEBUG_RING_SIZE = 5
        for i = 1, 12 do ns.Log("R", "line %d", i) end
        H.eq(ola:Logged("R"), 5)
        H.eq(ola:Logged("R", "line 12"), 1)
        ns.Debug:Clear()
        H.eq(#ola:Log(), 0)
        ns.Debug:SetEnabled(true, true)
        ola:Mark()
        ns.Log("E", "echoed")
        H.eq(ola:CountPrinted("[E] echoed"), 1)
        ns.Debug:SetEnabled(false)
        ns.Log("E", "off now")
        H.eq(ola:Logged("E", "off now"), 0)
    end)

    test("a phase's error is reported and the rest of it still starts", function()
        local w, ola = H.Setup{ "Ola Nord" }
        local ran = false
        ola.ns.Start("settled", function() error("broken module") end)
        ola.ns.Start("settled", function() ran = true end)
        ola.ns.RunPhase("settled")
        H.ok(ran)
        H.eq(#ola:TakeErrors(), 1)
        H.no(pcall(ola.ns.Start, "nope", function() end))
    end)

    test("our own Lua errors go into the debug log, once each, then counted", function()
        local w, ola = H.Setup{ "Ola Nord" }
        local handler = ola.env.geterrorhandler()
        for _ = 1, 10 do handler("Interface/AddOns/Proff/Core/Index.lua:1: boom") end
        handler("Interface/AddOns/Other/x.lua:1: not ours")
        H.eq(ola:Logged("Error", "Index.lua:1: boom"), 2, "the first, and again at 10")
        H.eq(ola:Logged("Error", "not ours"), 0)
        H.eq(#ola:TakeErrors(), 11, "still passed on to the client's handler")
    end)
end
