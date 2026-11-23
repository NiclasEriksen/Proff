---@class Proff
local ns = select(2, ...)

-- /proff probe: what this client really has, instead of guessing (Dyreparken's Dev/ApiProbe.lua pattern).
-- Read-only: nothing is set, sent or opened; no filter of the profession window is touched. Results go to
-- ProffDebugDB.probe (not the log's ring, which they'd flood), on disk after /reload:
--   api      every C_TradeSkillUI field, the globals Capture and Guild rely on, which events register
--   roster   GetGuildRosterInfo's every value for the first rows (which one is the GUID?), GetGuildInfo
--   window   the profession window open now: linked or not and whose, base/child profession, recipe counts,
--            one learned recipe's every field, ProfessionsFrame's tabs and children (for the Guild tab)
--   guild    the server's guild profession system (QueryGuildRecipes, QueryGuildMembersForRecipe): answered or not,
--            saved Probe.GUILD_WAIT seconds later (not part of the plain `/proff probe`)
--   link     (on until "link off" or a /reload) every profession window that opens: each event with its time,
--            and the window read at each, into probe.link (the newest Probe.KEEP windows): click a guildmate's
--            profession link in chat with it on
-- `/proff probe` runs api, roster and window; `/proff probe <section>` one; `clear` forgets them.
-- Read the results with `luajit tools/log.lua --dump probe.window` (or .api, .roster, .link).
---@class Proff.Probe
local Probe = { KEEP = 6 }
ns.Probe = Probe

local function Show(v, depth)
    if ns.IsSecret(v) then return "<secret>" end
    local t = type(v)
    if t == "string" then return ("%q"):format(v) end
    if t == "table" then
        if (depth or 0) > 1 then return "{...}" end
        local keys = {}
        for k in pairs(v) do keys[#keys + 1] = k end
        table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
        local parts = {}
        for i, k in ipairs(keys) do
            if i > 40 then parts[#parts + 1] = "..."; break end
            parts[#parts + 1] = tostring(k) .. "=" .. Show(v[k], (depth or 0) + 1)
        end
        return "{" .. table.concat(parts, ", ") .. "}"
    end
    return tostring(v)
end
Probe.Show = Show

-- fn's values as text, or why it failed ("missing" for no such function).
local function Try(fn, ...)
    if type(fn) ~= "function" then return "missing" end
    local r = { pcall(fn, ...) }
    if not r[1] then return "error: " .. tostring(r[2]) end
    local parts = {}
    for i = 2, math.max(2, table.maxn(r)) do parts[#parts + 1] = Show(r[i]) end
    return table.concat(parts, ", ")
end
Probe.Try = Try

-- A field of a Blizzard frame, or nil: what one client build has another may not (and the tests' frames throw
-- for a method they lack).
local function Field(t, k)
    local ok, v = pcall(function() return t[k] end)
    return ok and v or nil
end

local function Save(section, data)
    ProffDebugDB.probe = ProffDebugDB.probe or {}
    ProffDebugDB.probe[section] = data
end

-- The events Capture and the next round would use: which the client knows.
Probe.EVENTS = { "TRADE_SKILL_SHOW", "TRADE_SKILL_CLOSE", "TRADE_SKILL_LIST_UPDATE", "TRADE_SKILL_DATA_SOURCE_CHANGED",
    "TRADE_SKILL_DATA_SOURCE_CHANGING", "TRADE_SKILL_NAME_UPDATE", "NEW_RECIPE_LEARNED", "SKILL_LINES_CHANGED",
    "GUILD_ROSTER_UPDATE", "GUILD_TRADESKILL_UPDATE", "TRADE_SKILL_FAVORITES_CHANGED", "TRADE_SKILL_DETAILS_UPDATE" }
Probe.GLOBALS = { "SetItemRef", "GetPlayerInfoByGUID", "GetGuildRosterInfo", "GetNumGuildMembers", "GetGuildInfo",
    "IsInGuild", "UnitGUID", "ProfessionsFrame", "ProfessionsFrame_LoadUI", "TradeSkillFrame", "GetProfessions",
    "GetProfessionInfo", "GetTradeSkillLine", "GetNumTradeSkills", "GetTradeSkillInfo", "GetTradeSkillRecipeLink",
    "CanViewGuildRecipes", "QueryGuildRecipes", "GetGuildRecipeInfoPostQuery", "ViewGuildRecipes" }

function Probe:Api()
    local out = { tradeskill = {}, globals = {}, events = {} }
    local T = C_TradeSkillUI
    if type(T) == "table" then
        for k, v in pairs(T) do out.tradeskill[#out.tradeskill + 1] = tostring(k) .. (type(v) == "function" and "" or (" (" .. type(v) .. ")")) end
        table.sort(out.tradeskill)
    else
        out.tradeskill = "missing"
    end
    for _, g in ipairs(self.GLOBALS) do out.globals[g] = type(rawget(_G, g)) end
    local f = CreateFrame("Frame")
    for _, e in ipairs(self.EVENTS) do
        out.events[e] = pcall(f.RegisterEvent, f, e) and "ok" or "unknown"
        pcall(f.UnregisterEvent, f, e)
    end
    local n = type(out.tradeskill) == "table" and #out.tradeskill or 0
    ns.Log("Probe", "api: C_TradeSkillUI %d fields; events %s", n, Show(out.events))
    Save("api", out)
    return out
end

function Probe:Roster()
    local out = { inGuild = Try(IsInGuild), guildInfo = Try(GetGuildInfo, "player"), total = Try(GetNumGuildMembers),
        rows = {} }
    local total = ns.Read(GetNumGuildMembers) or 0
    for i = 1, math.min(5, total) do
        local r = { pcall(GetGuildRosterInfo, i) }
        local row = {}
        for j = 2, table.maxn(r) do row[#row + 1] = ("%d=%s"):format(j - 1, Show(r[j])) end
        out.rows[i] = table.concat(row, " ")
    end
    out.byGuid = 0
    for _ in pairs(ns.Guild.byGuid) do out.byGuid = out.byGuid + 1 end
    out.complete = ns.Guild.complete
    ns.Log("Probe", "roster: %s members, row 1: %s", tostring(out.total), tostring(out.rows[1]))
    Save("roster", out)
    return out
end

-- What the open profession window says, every way we could ask.
function Probe:ReadWindow()
    local T = C_TradeSkillUI
    if type(T) ~= "table" then return { tradeskill = "missing" } end
    local out = {
        linked = Try(T.IsTradeSkillLinked), guild = Try(T.IsTradeSkillGuild), guildMember = Try(T.IsTradeSkillGuildMember),
        npc = Try(T.IsNPCCrafting), ready = Try(T.IsTradeSkillReady), changing = Try(T.IsDataSourceChanging),
        base = Try(T.GetBaseProfessionInfo), child = Try(T.GetChildProfessionInfo), line = Try(T.GetTradeSkillLine),
        displayName = Try(T.GetTradeSkillDisplayName), listLink = Try(T.GetTradeSkillListLink),
        pending = Show(ns.Capture.pending),
        frameShown = rawget(_G, "ProfessionsFrame") and Try(Field(rawget(_G, "ProfessionsFrame"), "IsShown"), rawget(_G, "ProfessionsFrame"))
            or "no ProfessionsFrame",
    }
    local ids = ns.Read(T.GetAllRecipeIDs)
    if type(ids) == "table" then
        local learned, sample = 0, nil
        for _, id in ipairs(ids) do
            local r = ns.Read(T.GetRecipeInfo, id)
            if type(r) == "table" and ns.Plain(r.learned) == true then
                learned = learned + 1
                sample = sample or r
            end
        end
        out.recipes = ("%d ids, %d learned"):format(#ids, learned)
        out.sample = sample and Show(sample) or "none learned"
        Probe.sampleID = sample and ns.Plain(sample.recipeID)
        if sample then
            out.sampleLink = Try(T.GetRecipeLink, sample.recipeID)
            out.sampleOutput = Try(T.GetRecipeOutputItemData, sample.recipeID)
            out.sampleBySkill = Try(T.GetProfessionInfoByRecipeID, sample.recipeID)
            out.sampleReagents = Show(ns.Capture.Reagents(sample.recipeID))
            local schematic = ns.Read(T.GetRecipeSchematic, sample.recipeID, false)
            local slots = type(schematic) == "table" and schematic.reagentSlotSchematics
            out.sampleSlot = type(slots) == "table" and Show(slots[1]) or Show(schematic)
        end
    else
        out.recipes = Try(T.GetAllRecipeIDs)
    end
    local link = ns.Capture.session and ns.Capture.session.link
    if link then
        out.link = Show(link)
        out.linkPlayer = link.guid and Try(GetPlayerInfoByGUID, link.guid) or "no guid"
        out.linkLine = link.line and Try(T.GetProfessionInfoBySkillLineID, link.line) or "no line"
    end
    return out
end

-- The key a frame has in its parent's table (a parentKey), or nil. Secret fields are skipped: comparing one
-- throws on Forever.
local function KeyOf(parent, child)
    for k, v in pairs(parent) do
        if type(k) == "string" and not ns.IsSecret(v) and rawequal(v, child) then return k end
    end
    return nil
end

-- One part of a probe: its error is kept in the results (out.errors[name]) and logged, the other parts still
-- run. (An error in game left nothing to read: SavedVariables aren't written for a part that throws first.)
local function Part(out, name, fn)
    local ok, err = pcall(fn)
    if not ok then
        out.errors = out.errors or {}
        out.errors[name] = tostring(err)
        ns.Log("Probe", "part %s failed: %s", name, tostring(err))
    end
end
Probe.Part = Part

-- ProfessionsFrame's layout: its children, its profession tabs (the Guild tab goes under them), what's drawn
-- highest (the Guild tab's page goes above it), the parts the page lifts, and the recipe tooltip.
function Probe:Frame()
    local pf = rawget(_G, "ProfessionsFrame")
    if not pf then return "no ProfessionsFrame (open a profession first)" end
    local out = { children = {}, sideTabs = {}, highest = {}, lift = {} }
    Part(out, "size", function()
        out.size = Try(Field(pf, "GetSize"), pf)
        out.level = Try(Field(pf, "GetFrameLevel"), pf) .. " " .. Try(Field(pf, "GetFrameStrata"), pf)
        out.tabSystem = type(Field(pf, "TabSystem"))
    end)
    Part(out, "children", function()
        for i, child in ipairs({ pf:GetChildren() }) do
            if i > 40 then break end
            out.children[#out.children + 1] = ("%s %s %s shown=%s level=%s"):format(tostring(KeyOf(pf, child)),
                tostring(ns.Read(Field(child, "GetName"), child)), tostring(ns.Read(Field(child, "GetObjectType"), child)),
                tostring(ns.Read(Field(child, "IsShown"), child)), tostring(ns.Read(Field(child, "GetFrameLevel"), child)))
        end
    end)
    -- Each profession tab's line, size, place, level and its textures' atlases.
    Part(out, "sideTabs", function()
        local list = Field(pf, "rightProfessionTabs")
        out.sideTabsType = type(list)
        for i, t in ipairs(type(list) == "table" and list or {}) do
            local atlases = {}
            for _, r in ipairs({ t:GetRegions() }) do
                atlases[#atlases + 1] = tostring(ns.Read(Field(r, "GetAtlas"), r))
                    .. (ns.Read(Field(r, "IsShown"), r) and "" or "(hidden)")
            end
            out.sideTabs[i] = ("line=%s shown=%s type=%s size=%s top=%s level=%s OnClick=%s parent=%s atlases=%s"):format(
                tostring(ns.Plain(Field(t, "skillLine"))), Try(Field(t, "IsShown"), t), Try(Field(t, "GetObjectType"), t),
                Try(Field(t, "GetSize"), t), Try(Field(t, "GetTop"), t), Try(Field(t, "GetFrameLevel"), t),
                type(Field(t, "OnClick")), tostring(ns.Read(Field(t, "GetParent"), t) == pf and "window" or "other"),
                table.concat(atlases, " "))
        end
    end)
    -- Every texture of the shown tabs (and ours), each property the Guild tab copies: what makes a selected tab
    -- look selected.
    Part(out, "tabArt", function()
        out.tabArt = {}
        local list = {}
        for _, t in ipairs(Field(pf, "rightProfessionTabs") or {}) do
            if ns.Read(Field(t, "IsShown"), t) then list[#list + 1] = t end
        end
        list[#list + 1] = ns.GuildTab:Tab()
        for i, t in ipairs(list) do
            local rows = {}
            for _, r in ipairs({ t:GetRegions() }) do
                rows[#rows + 1] = ("%s %s shown=%s alpha=%s blend=%s color=%s size=%s point=%s"):format(
                    Try(Field(r, "GetAtlas"), r), Try(Field(r, "GetDrawLayer"), r), Try(Field(r, "IsShown"), r),
                    Try(Field(r, "GetAlpha"), r), Try(Field(r, "GetBlendMode"), r), Try(Field(r, "GetVertexColor"), r),
                    Try(Field(r, "GetSize"), r), Try(Field(r, "GetPoint"), r, 1):gsub("table: %x+", "frame"))
            end
            out.tabArt[i] = { line = tostring(ns.Plain(Field(t, "skillLine")) or (t == ns.GuildTab:Tab() and "ours")),
                alpha = Try(Field(t, "GetAlpha"), t), regions = rows }
        end
    end)
    -- What's over the Guild tab: the window's shown parts whose rectangle holds its middle, at its level or above.
    Part(out, "overTab", function()
        local tab = ns.GuildTab:Tab()
        out.overTab = {}
        local x, y
        if tab then x, y = ns.Read(Field(tab, "GetCenter"), tab) end
        if not (x and y) then out.overTab = "no Guild tab placed"; return end
        out.tabLevel = Try(Field(tab, "GetFrameLevel"), tab) .. " " .. Try(Field(tab, "GetFrameStrata"), tab)
        local function Walk(f, depth, path)
            for i, ch in ipairs({ f:GetChildren() }) do
                local key = path .. "." .. (KeyOf(f, ch) or i)
                if ch ~= tab and ns.Read(Field(ch, "IsVisible"), ch) then
                    local l, b, w, h = ns.Read(Field(ch, "GetRect"), ch)
                    if l and b and w and h and x >= l and x <= l + w and y >= b and y <= b + h then
                        out.overTab[#out.overTab + 1] = ("%s level=%s %s mouse=%s size=%.0fx%.0f"):format(key,
                            tostring(ns.Read(Field(ch, "GetFrameLevel"), ch)), tostring(ns.Read(Field(ch, "GetFrameStrata"), ch)),
                            tostring(ns.Read(Field(ch, "IsMouseEnabled"), ch)), w, h)
                    end
                end
                if depth < 6 then Walk(ch, depth + 1, key) end
            end
        end
        Walk(pf, 1, "pf")
    end)
    -- The highest levels among the window's parts.
    Part(out, "highest", function()
        local levels = {}
        local function Walk(f, depth, path)
            for i, ch in ipairs({ f:GetChildren() }) do
                local key = path .. "." .. (KeyOf(f, ch) or i)
                levels[#levels + 1] = { ns.Read(Field(ch, "GetFrameLevel"), ch) or 0, key,
                    tostring(ns.Read(Field(ch, "GetFrameStrata"), ch)), tostring(ns.Read(Field(ch, "IsShown"), ch)) }
                if depth < 5 then Walk(ch, depth + 1, key) end
            end
        end
        Walk(pf, 1, "pf")
        table.sort(levels, function(x, y) return x[1] > y[1] end)
        for i = 1, math.min(12, #levels) do out.highest[i] = table.concat(levels[i], " ") end
    end)
    Part(out, "lift", function()
        for _, k in ipairs({ "NineSlice", "PortraitContainer", "TitleContainer", "CloseButton", "Bg", "CraftingPage",
            "SpecPage", "OrdersPage" }) do
            out.lift[k] = type(rawget(pf, k))
        end
        local bg = rawget(pf, "Bg")
        out.bg = bg and Try(Field(bg, "GetObjectType"), bg) .. " " .. Try(Field(bg, "GetAtlas"), bg) or "none"
        for _, k in ipairs({ "recipesTabID", "specializationsTabID", "craftingOrdersTabID" }) do out[k] = Show(Field(pf, k)) end
    end)
    Part(out, "guildTab", function()
        local tab = ns.GuildTab:Tab()
        out.guildTab = "not attached"
        if tab then
            local point, rel, relPoint, x, y = tab:GetPoint(1)
            out.guildTab = { open = ns.GuildTab:IsOpen(), shown = tab:IsShown(), size = Try(Field(tab, "GetSize"), tab),
                point = ("%s %s %s %s %s"):format(tostring(point), rel == pf and "window" or tostring(rel and KeyOf(pf, rel) or rel),
                    tostring(relPoint), tostring(x), tostring(y)) }
        end
    end)
    Part(out, "tooltip", function()
        local tip = rawget(_G, "GameTooltip")
        if not (tip and self.sampleID) then return end
        tip:SetOwner(pf, "ANCHOR_NONE")
        out.spellTooltip = Try(Field(tip, "SetSpellByID"), tip, self.sampleID) .. "; lines " .. Try(Field(tip, "NumLines"), tip)
        local lines = {}
        for i = 1, math.min(8, ns.Read(Field(tip, "NumLines"), tip) or 0) do
            local fs = rawget(_G, "GameTooltipTextLeft" .. i)
            lines[i] = fs and Try(Field(fs, "GetText"), fs) or "?"
        end
        out.spellTooltipLines = lines
        tip:Hide()
    end)
    return out
end

function Probe:Window()
    local out = {}
    Part(out, "read", function()
        for k, v in pairs(self:ReadWindow()) do out[k] = v end
    end)
    Part(out, "frame", function() out.frame = self:Frame() end)
    ns.Log("Probe", "window: linked %s, base %s, %s", tostring(out.linked), tostring(out.base), tostring(out.recipes))
    Save("window", out)
    return out
end

-- The server's own guild profession system (Cataclysm's, still in the client: Dyreparken's API dump has
-- QueryGuildRecipes, GetGuildTradeSkillInfo, C_GuildInfo.QueryGuildMembersForRecipe, GetGuildRecipeMember). If
-- the server answers, "who in the guild knows this recipe" needs no addon messages at all. Asked silently (no
-- window opens: ViewGuildRecipes, which would, isn't called); the answers come as events, so the results are
-- saved Probe.GUILD_WAIT seconds later.
Probe.GUILD_WAIT = 5
Probe.GUILD_EVENTS = { "GUILD_TRADESKILL_UPDATE", "GUILD_RECIPE_KNOWN_BY_MEMBERS" }
function Probe:Guild()
    local T = C_TradeSkillUI or {}
    local out = { enabled = Try(T.IsGuildTradeSkillsEnabled), events = {}, fired = {} }
    -- A recipe of our own to ask about (the lowest id of our first stored profession).
    local g = ns.DB:Guild(ns.GuildKey())
    local own = g and g.members[ns.PlayerKey() or ""]
    local line, recipe
    for l, p in pairs(own and own.profs or {}) do
        if not line or l < line then
            line, recipe = l, nil
            for id in pairs(p.recipes) do if not recipe or id < recipe then recipe = id end end
        end
    end
    out.asked = ("line %s, recipe %s"):format(tostring(line), tostring(recipe))
    out.canView = line and Try(CanViewGuildRecipes, line) or "no own profession stored"
    local started = GetTime()
    local f = CreateFrame("Frame")
    for _, e in ipairs(self.GUILD_EVENTS) do out.events[e] = pcall(f.RegisterEvent, f, e) and "ok" or "unknown" end
    local function Rows()
        local n = ns.Read(GetNumGuildTradeSkill) or 0
        local rows = {}
        for i = 1, math.min(15, n) do rows[i] = Try(GetGuildTradeSkillInfo, i) end
        return n, rows
    end
    local function Members()
        local l, id, n = ns.Read(GetGuildRecipeInfoPostQuery)
        local who = {}
        for i = 1, math.min(10, tonumber(n) or 0) do who[i] = Try(GetGuildRecipeMember, i) end
        return ("line %s, recipe %s, %s members"):format(tostring(l), tostring(id), tostring(n)), who
    end
    f:SetScript("OnEvent", function(_, event, ...)
        out.fired[#out.fired + 1] = ("%s +%.2f %s"):format(event, GetTime() - started, Show({ ... }))
        if event == "GUILD_TRADESKILL_UPDATE" then out.tradeSkills, out.tradeSkillRows = Rows()
        else out.post, out.members = Members() end
    end)
    out.queryRecipes = Try(QueryGuildRecipes)
    out.queryMembers = recipe and Try(C_GuildInfo and C_GuildInfo.QueryGuildMembersForRecipe, line, recipe) or "not asked"
    Save("guild", out)
    C_Timer.After(self.GUILD_WAIT, function()
        f:UnregisterAllEvents()
        out.after = { tradeSkills = (Rows()), post = (Members()) }
        ns.Log("Probe", "guild: enabled %s, %d events, %s trade skill rows, %s", tostring(out.enabled), #out.fired,
            tostring(out.after.tradeSkills), tostring(out.after.post))
        ns.Print("Guild probe done: /reload, then luajit tools/log.lua --dump probe.guild.")
    end)
    return out
end

-- The link watch: each profession window from its first event to its close, every event read.
local watching, current
local function OnWindowEvent(_, event, ...)
    local db = ProffDebugDB.probe and ProffDebugDB.probe.link
    if not db then return end
    if event == "TRADE_SKILL_SHOW" or not current then
        current = { started = GetTime(), events = {} }
        table.insert(db, 1, current)
        while #db > Probe.KEEP do table.remove(db) end
    end
    local read = Probe:ReadWindow()
    current.events[#current.events + 1] = { event = event, at = ("+%.2f"):format(GetTime() - current.started),
        args = Show({ ... }), read = read }
    ns.Log("Probe", "link %s +%.2f: linked %s, %s", event, GetTime() - current.started, tostring(read.linked), tostring(read.recipes))
    if event == "TRADE_SKILL_CLOSE" then current = nil end
end
function Probe:Link(arg)
    local on = arg ~= "off"
    for _, e in ipairs({ "TRADE_SKILL_SHOW", "TRADE_SKILL_LIST_UPDATE", "TRADE_SKILL_DATA_SOURCE_CHANGED",
        "TRADE_SKILL_DATA_SOURCE_CHANGING", "TRADE_SKILL_CLOSE" }) do
        if on then ns.Events:On(e, Probe, OnWindowEvent) else ns.Events:Off(e, Probe) end
    end
    watching = on
    if on then
        ProffDebugDB.probe = ProffDebugDB.probe or {}
        ProffDebugDB.probe.link = ProffDebugDB.probe.link or {}
    end
    ns.Print(on and "Link probe on: click a guildmate's profession link in chat, then /reload to save."
        or "Link probe off.")
end
function Probe:Watching() return watching end

local SECTIONS = { api = "Api", roster = "Roster", window = "Window", guild = "Guild" }
function Probe:Run(arg)
    if not ns.Debug.enabled then ns.Debug:SetEnabled(true, ns.Debug.echo) end
    if arg == "clear" then
        ProffDebugDB.probe = nil
        return ns.Print("Probe results cleared.")
    elseif arg == "link" or arg == "link off" then
        return self:Link(arg == "link off" and "off" or nil)
    elseif arg and not SECTIONS[arg] then
        return ns.Print("No probe section \"" .. arg .. "\": api, roster, window, guild, link [off], verify, clear.")
    end
    -- (a section that throws is saved as its error, and the others still run)
    for _, name in ipairs(arg and { arg } or { "api", "roster", "window" }) do
        local ok, err = pcall(self[SECTIONS[name]], self)
        if not ok then
            Save(name, { error = tostring(err) })
            ns.Log("Probe", "%s failed: %s", name, tostring(err))
            ns.Print("Probe " .. name .. " failed: " .. tostring(err))
        end
    end
    if arg == "guild" then return ns.Print("Guild probe asked: its answers are saved in " .. self.GUILD_WAIT .. " s.") end
    ns.Print("Probe done: /reload, then luajit tools/log.lua --dump probe" .. (arg and ("." .. arg) or "") .. ".")
end
