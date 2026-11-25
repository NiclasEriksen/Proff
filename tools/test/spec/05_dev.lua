-- The developer tools (Dev/): probes, the verify checklist, /proff debug. Only in a checkout.
return function(test, H)
    local function World(quirks)
        local w = H.World()
        for k, v in pairs(quirks or {}) do w.quirks[k] = v end
        w:AddPlayer("Kari Berg", { profs = { [171] = { 2330, 3447 } } })
        w:AddPlayer("Per Fremmed", { guild = false, profs = { [164] = { 2662 } } })
        local ola = w:AddClient("Ola Nord", { profs = { [197] = { 2387 } } })
        w:Settle()
        return w, ola
    end
    local function Probe(c) return rawget(c.env, "ProffDebugDB").probe end

    test("/proff probe: api, roster and the window, saved for the log tool", function()
        local w, ola = World()
        ola:ClickLink("Kari Berg", 171)
        ola:Mark()
        ola:Slash("probe")
        H.eq(ola:CountPrinted("Probe done"), 1)
        local p = Probe(ola)
        H.eq(p.api.events.TRADE_SKILL_SHOW, "ok")
        H.eq(p.api.events.GUILD_TRADESKILL_UPDATE, "ok")
        H.eq(p.api.globals.SetItemRef, "function")
        H.eq(p.api.globals.GetTradeSkillLine, "nil", "Forever lacks the classic ones")
        H.ok(table.concat(p.api.tradeskill, " "):find("IsTradeSkillLinked", 1, true))
        H.match(p.roster.rows[1], "17=\"Player%-")
        H.eq(p.window.linked, "true, \"Kari Berg\"")
        H.eq(p.window.recipes, "8 ids, 2 learned")
        H.match(p.window.sample, "learned=true")
        H.match(p.window.link, "guid=\"Player%-")
        H.match(p.window.linkPlayer, "\"Kari Berg\"")
        H.match(p.window.linkLine, "Alchemy")
        H.eq(type(p.window.frame), "table")
        H.eq(p.window.frame.recipesTabID, "nil", "no retail tab ids on the stub's Forever window")
        -- The Guild tab's assumptions.
        local f = p.window.frame
        H.eq(f.sideTabs[1], "line=197 shown=true type=\"Frame\" size=55, 55 top=nil level=2 OnClick=function parent=window"
            .. " atlases=common-sidetab nil common-sidetab-mask common-sidetab-selected(hidden) common-sidetab-selected common-sidetab-hover")
        H.eq(f.tabSystem, "nil")
        H.eq(f.tabArt[#f.tabArt].line, "ours")
        H.match(f.tabArt[1].regions[5], "^\"common%-sidetab%-selected\" \"OVERLAY\", 0 shown=true alpha=0 blend=\"ADD\"")
        H.match(f.highest[1], "^700 pf.BookPage.1 MEDIUM")
        H.eq(f.lift.CloseButton, "table")
        H.eq(f.bg, "\"Texture\" \"Profession-Background-Overview\"")
        H.eq(f.guildTab.shown, true)
        H.match(f.spellTooltip, "lines 2$")
        H.match(p.window.sampleReagents, "2447=1")
        H.match(p.window.sampleSlot, "quantityRequired=1")
        ola:Slash("probe roster")
        ola:Mark()
        ola:Slash("probe clear")
        H.eq(Probe(ola), nil)
        ola:Mark()
        ola:Slash("probe nope")
        H.eq(ola:CountPrinted("No probe section \"nope\""), 1)
    end)

    test("a probe part or section that throws: its error saved and said, the rest still there", function()
        local w, ola = World()
        ola:OpenProfession(197)
        local pf = ola.env.ProfessionsFrame
        pf.rightProfessionTabs = { "tabs broke" } -- (not a frame: indexing its methods throws)
        pf.odd = H.SECRET -- (a secret field: skipped when finding parentKeys)
        ola:Mark()
        ola:Slash("probe window")
        local f = Probe(ola).window.frame
        H.match(f.errors.sideTabs, "GetRegions")
        H.eq(f.errors.children, nil); H.ok(#f.children > 0, "the other parts ran")
        H.ok(#f.highest > 0)
        H.eq(ola:Logged("Probe", "part sideTabs failed"), 1)
        ola.ns.Probe.Roster = function() error("roster broke") end
        ola:Mark()
        ola:Slash("probe")
        H.match(Probe(ola).roster.error, "roster broke")
        H.ok(Probe(ola).window.frame, "window still probed")
        H.eq(ola:CountPrinted("Probe roster failed"), 1)
        H.eq(ola:CountPrinted("Probe done"), 1)
        ola.ns.Probe.ReadWindow = function() error("read broke") end
        ola:Slash("probe window")
        H.match(Probe(ola).window.errors.read, "read broke")
    end)

    test("the window probe with nothing open, and on a client without C_TradeSkillUI", function()
        local w, ola = World()
        ola:Slash("probe window")
        H.eq(Probe(ola).window.frame, "no ProfessionsFrame (open a profession first)")
        H.eq(Probe(ola).window.recipes, "0 ids, 0 learned")
        local bare = w:AddClient("Kari Berg2", { patch = function(env) env.C_TradeSkillUI = nil end })
        w:Settle()
        bare:Slash("probe")
        H.eq(Probe(bare).api.tradeskill, "missing")
        H.eq(Probe(bare).window.tradeskill, "missing")
        H.eq(bare:Logged("Capture", "no C_TradeSkillUI"), 1)
    end)

    test("the communities probe: the guild window's list rows and detail panel, part by part", function()
        local w, ola = World()
        ola:Slash("probe communities")
        H.eq(Probe(ola).communities.frame, "no CommunitiesFrame (open the guild window first)")
        -- A stand-in for the guild window (the stub client has none yet): a list with two rows, a detail panel.
        local env = ola.env
        local cf = env.CreateFrame("Frame", "CommunitiesFrame", env.UIParent)
        rawset(env, "CommunitiesFrame", cf)
        cf.MemberList = env.CreateFrame("Frame", nil, cf)
        local box = env.CreateFrame("Frame", nil, cf.MemberList)
        cf.MemberList.ScrollBox = box
        local rows = {}
        for i = 1, 3 do
            local row = env.CreateFrame("Button", nil, box)
            row:SetSize(300, 20)
            row.NameFrame = env.CreateFrame("Frame", nil, row)
            row.NameFrame.Name = row.NameFrame:CreateFontString(nil, "ARTWORK")
            row.NameFrame.Name:SetText("Kari Berg")
            row.NameFrame:SetPoint("LEFT", row, "LEFT", 4, 0)
            row.memberInfo = { name = "Kari Berg", profession1ID = 171, profession1Rank = 1 }
            rows[i] = row
        end
        box.ForEachFrame = function(_, fn) for _, r in ipairs(rows) do fn(r) end end
        cf.GuildMemberDetailFrame = env.CreateFrame("Frame", nil, cf)
        cf.GuildMemberDetailFrame.DisplayMember = function() end
        ola:Slash("probe communities")
        local p = Probe(ola).communities
        H.eq(p.rows, "3 rows in view")
        H.match(p.row1.member, "profession1ID=171")
        H.match(table.concat(p.row1.parts, "\n"), "row%.NameFrame%.Name FontString  0x0 %[unplaced%] shown=true .* text=\"Kari Berg\"")
        H.match(table.concat(p.row1.parts, "\n"), "row%.NameFrame Frame  0x0 %[LEFT parent LEFT 4 0%]")
        H.eq(p.row2 ~= nil and p.row3 == nil, true, "two rows described")
        H.eq(p.hooks["detail.DisplayMember"], "function")
        H.eq(p.hooks["row.Init"], "nil")
        H.match(p.detail, "^shown=true")
        H.eq(p.grm.loaded, "nil")
        H.eq(ola:Logged("Probe", "communities: shown=true"), 1)
        box.GetFrames = function() return { rows[1] } end
        ola:Slash("probe communities")
        H.eq(Probe(ola).communities.rows, "1 rows in view")
    end)

    test("the link probe: each window's events and reads, the newest KEEP", function()
        local w, ola = World()
        ola:Slash("probe link")
        H.ok(ola.ns.Probe:Watching())
        ola:ClickLink("Kari Berg", 171)
        ola:CloseProfession()
        local link = Probe(ola).link
        H.eq(#link, 1)
        local events = {}
        for _, e in ipairs(link[1].events) do events[#events + 1] = e.event end
        H.eq(table.concat(events, " "), "TRADE_SKILL_SHOW TRADE_SKILL_DATA_SOURCE_CHANGING TRADE_SKILL_DATA_SOURCE_CHANGED "
            .. "TRADE_SKILL_LIST_UPDATE TRADE_SKILL_LIST_UPDATE TRADE_SKILL_LIST_UPDATE TRADE_SKILL_LIST_UPDATE TRADE_SKILL_CLOSE")
        H.eq(link[1].events[2].read.changing, "true")
        H.eq(link[1].events[4].read.linked, "true, \"Kari Berg\"")
        ola.ns.Probe.KEEP = 2
        for _ = 1, 3 do ola:OpenProfession(197); ola:CloseProfession() end
        H.eq(#Probe(ola).link, 2)
        ola:Slash("probe link off")
        H.no(ola.ns.Probe:Watching())
        ola:OpenProfession(197)
        H.eq(#Probe(ola).link, 2)
    end)

    test("verify: items tick as they happen, stay ticked across a reload, by hand too", function()
        local w, ola = World()
        ola:Mark()
        ola:Slash("probe verify")
        H.match(ola:Said()[1], "^Verify on: 0 of %d+ confirmed")
        ola:OpenProfession(197)
        ola:CloseProfession()
        ola:ClickLink("Kari Berg", 171)
        ola:ClickLink("Per Fremmed", 164)
        local ticks = rawget(ola.env, "ProffDebugDB").verify
        for _, id in ipairs({ "api:show", "api:learned", "api:own", "api:linkclick", "api:linkguid", "api:linked",
            "api:linkedname", "api:linkedlearned", "capture:byguid", "capture:stored", "capture:outside" }) do
            H.ok(ticks[id], id .. " ticked")
        end
        H.no(ticks["capture:prune"])
        H.no(ticks["ui:open"])
        ola:OpenProfession(197)
        ola:OpenGuildTab()
        ola:GuildPage().rows[1]:Run("OnEnter")
        ola.env.ProfessionsFrame.rightProfessionTabs[1]:Press()
        for _, id in ipairs({ "capture:reagents", "capture:itemnames", "ui:tab", "ui:open", "ui:leave",
            "ui:tooltip" }) do
            H.ok(ticks[id], id .. " ticked")
        end
        ola:CloseProfession()
        H.eq(ola:CountPrinted("verified api:show"), 1)
        ola:Reload()
        ola:ClickLink("Kari Berg", 171)
        H.ok(rawget(ola.env, "ProffDebugDB").verify["capture:same"], "still on after the reload")
        H.ok(rawget(ola.env, "ProffDebugDB").verify["api:rosterguid"])
        H.ok(rawget(ola.env, "ProffDebugDB").verify["api:rostercomplete"])
        ola:Mark()
        ola:Slash("probe verify ok capture:prune")
        H.eq(ola:CountPrinted("verified capture:prune"), 1)
        ola:Mark()
        ola:Slash("probe verify ok nope")
        H.eq(ola:CountPrinted("no item"), 1)
        ola:Mark()
        ola:Slash("probe verify")
        H.match(ola:Said()[1], "Still open:$")
        ola:Slash("probe verify reset")
        H.eq(next(rawget(ola.env, "ProffDebugDB").verify), nil)
        ola:Slash("probe verify off")
        ola:Reload()
        H.eq(ola.ns.Debug.tap, nil)
    end)

    test("verify: a probe's error in the tap is logged, never raised in whoever logged", function()
        local w, ola = World()
        ola:Slash("probe verify")
        ola.ns.Verify.ITEMS[#ola.ns.Verify.ITEMS + 1] = { "x:boom", "boom", "Capture", function() error("tap broke") end }
        ola:OpenProfession(197)
        H.ok(ola:Logged("Debug", "tap failed on Capture") > 0)
    end)

    test("/proff debug: on, off, echo, mute, clear", function()
        local w, ola = World()
        ola:Mark()
        ola:Slash("debug off")
        H.no(ola.ns.Debug.enabled)
        ola:Slash("debug")
        H.ok(ola.ns.Debug.enabled)
        ola:Slash("debug echo")
        H.ok(ola.ns.Debug.echo)
        H.eq(ola:CountPrinted("[Chat] Debug on (echo to chat)."), 1, "echoed: what's logged, to chat")
        ola:Slash("debug echo")
        ola:Slash("debug mute Capture")
        H.eq(ola:CountPrinted("Muted in the log: Capture."), 1)
        ola:Slash("debug unmute Capture")
        ola:Slash("debug clear")
        H.eq(ola:CountPrinted("Debug log cleared."), 1)
        H.eq(H.lines(ola:Said("Debug o")), "Debug off. | Debug on. | Debug on (echo to chat). | [Chat] Debug on (echo to chat). | Debug on.")
    end)
end
