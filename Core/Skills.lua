---@class Proff
local ns = select(2, ...)

-- Who in the guild has which profession, at what skill: the server's guild profession roster (Cataclysm's,
-- still on Forever: /proff probe guild, 2026-11-23), asked when the Guild tab's Members view wants it, at most
-- every Config.SKILLS_INTERVAL. Its recipe half is off on Forever; this half answers.
--
--   QueryGuildRecipes()         -> GUILD_TRADESKILL_UPDATE (at once, probed)
--   GetGuildTradeSkillInfo(i)   -> a header per profession: skillID, isCollapsed, icon, name, numOnline,
--                                  numVisible, numPlayers; under an expanded header, its members: ..., playerName,
--                                  playerNameWithRealm, class, online, zone, skill, classFileName
-- Forever hands the headers collapsed (probed): we expand the collapsed ones (ExpandGuildTradeSkillHeader), read the
-- members, and collapse them again, so Blizzard's own guild window finds them as it left them. Whether expanding
-- gives member rows on Forever: yes (2026-11-23, 51 rows). A header left open (Blizzard's guild window) stays open.
--
-- Forever's skill in it is always 1 (seen 2026-11-23: our own Enchanting 281 and Herbalism 300 said 1), and it
-- lists primary professions only (no Cooking, Fishing, First Aid), so a skill of 1 or less is read as "has it, skill
-- unknown" (m.has); a rank Proff stored takes its place (Skills:Table), and secondaries come from Proff alone.
--
-- GUILD_TRADESKILL_UPDATE is heard only while a query is out. Nothing is saved: the server's answer is fresh each
-- session. Skills:Table merges in the skill levels Proff stored with recipes (Core/Recipes.lua's rank), the higher
-- of the two, so a member is listed even when the server's roster doesn't say.
---@class Proff.Skills
local Skills = { profs = {}, members = {}, at = 0, busy = false }
ns.Skills = Skills

local Plain = ns.Plain

-- Skill lines of the secondary professions: Cooking, Fishing, First Aid.
Skills.SECONDARY = { [185] = true, [356] = true, [129] = true }

-- Every row the client has now: headers into profs, members into members.
local function Read()
    local n = ns.Read(GetNumGuildTradeSkill) or 0
    local profs, members, rows, collapsed = {}, {}, 0, {}
    local line
    for i = 1, n do
        local r = { pcall(GetGuildTradeSkillInfo, i) }
        if r[1] then
            for j = 2, 17 do r[j] = Plain(r[j]) end
            local skillID, isCollapsed, icon, header, _, _, players = r[2], r[3], r[4], r[5], r[6], r[7], r[8]
            local who, class, online, skill, classFile = r[9], r[11], r[12], r[14], r[15]
            if type(header) == "string" and type(skillID) == "number" then
                line = skillID
                -- (Forever lists a "Test Profession [DNT]" nobody has)
                if not header:find("[DNT]", 1, true) then
                    profs[line] = { line = line, name = header, icon = icon, players = tonumber(players) or 0 }
                    if isCollapsed then collapsed[#collapsed + 1] = line end
                end
            elseif type(who) == "string" and line then
                who = ns.NormalizeName(who)
                if who then
                    rows = rows + 1
                    local m = members[who] or { skills = {}, has = {} }
                    members[who] = m
                    m.class, m.online = classFile or class, online
                    skill = tonumber(skill)
                    m.has[skillID or line] = true
                    if skill and skill > 1 then m.skills[skillID or line] = skill end
                    -- (what Forever really sends, for the log: one row a query)
                    if rows == 1 then
                        local parts = {}
                        for j = 2, 17 do parts[#parts + 1] = tostring(r[j]) end
                        Skills.sample = table.concat(parts, ", ")
                    end
                end
            end
        end
    end
    return profs, members, rows, collapsed
end

local expanded = {}
local function Finish(why)
    ns.Events:Off("GUILD_TRADESKILL_UPDATE", Skills)
    Skills.busy = false
    local profs, members, rows = Read()
    -- Put back what we opened.
    for _, line in ipairs(expanded) do pcall(CollapseGuildTradeSkillHeader, line) end
    local opened = #expanded
    expanded = {}
    local count = 0
    for _ in pairs(profs) do count = count + 1 end
    if count > 0 then Skills.profs, Skills.members, Skills.at = profs, members, ns.Now() end
    ns.Log("Skills", "%s: %d professions, %d member rows, %d headers expanded", why, count, rows, opened)
    if Skills.sample then ns.Log("Skills", "a member row: %s", Skills.sample); Skills.sample = nil end
    ns.Bus:Fire("SKILLS")
end

local function OnUpdate()
    if not Skills.busy then return end
    local _, _, rows, collapsed = Read()
    -- (a header someone left open shows its members already: the collapsed ones still need opening, 2026-11-23)
    if #collapsed == 0 or #expanded > 0 then return Finish(#expanded > 0 and "expanded" or "answered") end
    -- Collapsed: opened (theirs to keep as it was), and read again now or at the next update.
    for _, line in ipairs(collapsed) do
        if pcall(ExpandGuildTradeSkillHeader, line) then expanded[#expanded + 1] = line end
    end
    local _, _, now, still = Read()
    if now > rows and #still == 0 then Finish("expanded") end
end

------------------------------------------------------------------------------
-- Skill sheets: every profession's level, as the player's own client knows it (secondaries too, which the
-- server's roster leaves out). Ours is read at login and when a profession window shows ours; Sync relays
-- everyone's (the user, 2026-11-23: a stale level beats none). Stored as members[who].skills (Core/DB.lua).
------------------------------------------------------------------------------

-- Our own levels now: { [skill line] = { r, m } } and their names, or nil (none, or the API missing).
-- GetProfessions gives slot indexes (primary, primary, archaeology, fishing, cooking; nil for an empty one).
function Skills.ReadOwn()
    if type(GetProfessions) ~= "function" or type(GetProfessionInfo) ~= "function" then return nil end
    local slots = { pcall(GetProfessions) }
    if not slots[1] then return nil end
    local lines, names = {}, {}
    for i = 2, table.maxn(slots) do
        local index = Plain(slots[i])
        if type(index) == "number" then
            local r = { pcall(GetProfessionInfo, index) }
            local name, rank, max, line = Plain(r[2]), Plain(r[4]), Plain(r[5]), Plain(r[8])
            if r[1] and type(line) == "number" and line > 0 and type(rank) == "number" then
                lines[line] = { r = rank, m = type(max) == "number" and max or nil }
                names[line] = type(name) == "string" and name or nil
            end
        end
    end
    if not next(lines) then return nil end
    return lines, names
end

local function SameLines(a, b)
    for line, l in pairs(a) do
        local o = b[line]
        if not o or o.r ~= l.r or o.m ~= l.m then return false end
    end
    for line in pairs(b) do if not a[line] then return false end end
    return true
end

-- Stores a member's sheet: ours (at nil: now, if a level changed) or a relayed one (at, via). Older than what's
-- stored: kept as it is. Returns "new" | "changed" | "same" | nil.
function Skills:Store(guild, who, lines, at, via)
    local g = ns.DB:Guild(guild, true)
    if not g or type(who) ~= "string" or type(lines) ~= "table" or not next(lines) then return nil end
    local m = g.members[who]
    if not m then
        m = { profs = {} }
        g.members[who] = m
    end
    local old = m.skills
    if old and at and old.at >= at then return nil end
    local status = not old and "new" or (SameLines(old.lines, lines) and "same" or "changed")
    local now = ns.Now()
    m.skills = { at = at or (status == "same" and old.at) or now, seen = now, via = via, lines = lines }
    ns.Log("Skills", "sheet %s %s%s", status, who, via and (" via " .. via) or "")
    ns.Bus:Fire("STORED", guild, who, 0, status)
    return status
end

-- Reads our own levels into our sheet (in a guild). Names are kept for columns nobody's recipes name.
Skills.names = {}
function Skills:Own()
    local guild, me = ns.GuildKey(), ns.PlayerKey()
    if not guild or not me or ns.DB.data.readOnly then return nil end
    local lines, names = Skills.ReadOwn()
    if not lines then return nil end
    local parts = {}
    for line, name in pairs(names) do
        self.names[line] = name
        parts[#parts + 1] = ("%d %s %d/%s"):format(line, name, lines[line].r, tostring(lines[line].m))
    end
    table.sort(parts)
    ns.Log("Skills", "own levels: %s", table.concat(parts, ", "))
    return self:Store(guild, me, lines)
end

-- A profession's name for a column: what we read, else the client's.
function Skills.Name(line)
    if Skills.names[line] then return Skills.names[line] end
    local info = ns.Read(C_TradeSkillUI.GetProfessionInfoBySkillLineID, line)
    local name = type(info) == "table" and Plain(info.professionName)
    return type(name) == "string" and name ~= "" and name or nil
end

ns.Start("settled", function() Skills:Own() end)
-- Our own profession stored (the window showed it): our levels may have moved.
ns.Bus:On("STORED", Skills, function(_, guild, who, line)
    if line ~= 0 and who == ns.PlayerKey() and guild == ns.GuildKey() then Skills:Own() end
end)

-- Asks the server (force: whatever the interval). Answers come as Bus SKILLS.
function Skills:Refresh(force)
    if self.busy or not IsInGuild() or type(QueryGuildRecipes) ~= "function" then return false end
    if not force and ns.Now() - self.at < ns.Config.SKILLS_INTERVAL then return false end
    if not ns.Events:On("GUILD_TRADESKILL_UPDATE", Skills, OnUpdate) then return false end
    self.busy = true
    local token = {}
    self.token = token
    pcall(QueryGuildRecipes)
    C_Timer.After(ns.Config.SKILLS_TIMEOUT, function()
        if Skills.token == token and Skills.busy then Finish("timed out") end
    end)
    return true
end

-- The Members view's table: columns (professions, by name) and rows (members with any of them):
--   columns: { { line, name, icon }, ... }
--   rows:    { { who, class, online, skills = { [line] = skill }, has = { [line] = true }, recipes = { [line] = n } }, ... }
--            (has: the server says they have it, skill unknown)
-- The server's skills, and for what it doesn't say, the rank stored with a member's recipes.
function Skills:Table(guild)
    local cols, rows, byWho = {}, {}, {}
    local function Col(line, name, icon)
        if not cols[line] then cols[line] = { line = line, name = name, icon = icon } end
        local c = cols[line]
        c.name, c.icon = c.name or name, c.icon or icon
    end
    local function Row(who)
        local r = byWho[who]
        if not r then
            r = { who = who, skills = {}, has = {}, recipes = {} }
            byWho[who] = r
            rows[#rows + 1] = r
        end
        return r
    end
    for line, p in pairs(self.profs) do Col(line, p.name, p.icon) end
    for who, m in pairs(self.members) do
        local r = Row(who)
        r.class, r.online = m.class, m.online
        for line, skill in pairs(m.skills) do r.skills[line] = skill end
        for line in pairs(m.has or {}) do r.has[line] = true end
    end
    local g = guild and ns.DB:Guild(guild)
    for who, m in pairs(g and g.members or {}) do
        for line, p in pairs(m.profs) do
            local r = Row(who)
            r.recipes[line] = p.n
            -- (the higher: skills only rise, and either may be the older; the server's is cached a minute)
            if type(p.rank) == "number" and p.rank > 1 and p.rank > (r.skills[line] or 0) then r.skills[line] = p.rank end
            Col(line, p.name, ns.Read(C_TradeSkillUI.GetTradeSkillTexture, line))
        end
        -- (their own client's levels, maybe older than a link's: the higher, as above)
        for line, l in pairs(m.skills and m.skills.lines or {}) do
            local r = Row(who)
            if l.r > 1 and l.r > (r.skills[line] or 0) then r.skills[line] = l.r end
            Col(line, Skills.Name(line), ns.Read(C_TradeSkillUI.GetTradeSkillTexture, line))
        end
    end
    local list = {}
    for _, c in pairs(cols) do list[#list + 1] = c end
    -- (secondary professions last, at the right: the user, 2026-11-23, "they're not important")
    table.sort(list, function(a, b)
        local sa, sb = Skills.SECONDARY[a.line] or false, Skills.SECONDARY[b.line] or false
        if sa ~= sb then return sb end
        return tostring(a.name) < tostring(b.name)
    end)
    -- (rows without any profession aren't shown)
    local out = {}
    for _, r in ipairs(rows) do if next(r.skills) or next(r.recipes) or next(r.has) then out[#out + 1] = r end end
    return list, out
end

-- Sorted in place: by a profession (its holders first, highest skill first, then by first name; the rest by
-- name), or by name (line nil).
function Skills.Sort(rows, line)
    local function First(who) return (who:match("^(%S+)") or who):lower(), who:lower() end
    table.sort(rows, function(a, b)
        if line then
            -- (has it, skill unknown: ranked under every known skill)
            local sa = a.skills[line] or ((a.recipes[line] or a.has[line]) and -1)
            local sb = b.skills[line] or ((b.recipes[line] or b.has[line]) and -1)
            if (sa ~= nil) ~= (sb ~= nil) then return sa ~= nil end
            if sa and sb and sa ~= sb then return sa > sb end
        end
        local fa, wa = First(a.who)
        local fb, wb = First(b.who)
        if fa ~= fb then return fa < fb end
        return wa < wb
    end)
    return rows
end
