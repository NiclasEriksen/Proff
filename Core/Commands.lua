---@class Proff
local ns = select(2, ...)

-- /proff: the round-one way to ask the store (the Guild tab in the profession window comes next).
---@class Proff.Commands
local Commands = { list = {} }
ns.Commands = Commands

function Commands.Add(name, usage, fn) Commands.list[name] = { usage = usage, fn = fn } end

function Commands.Ago(t)
    local s = math.max(0, ns.Now() - (t or 0))
    if s < 60 then return ns.L["ago.now"] end
    if s < 3600 then return ns.T("ago.min", { n = math.floor(s / 60) }) end
    if s < 86400 then return ns.T("ago.hour", { n = math.floor(s / 3600) }) end
    return ns.T("ago.day", { n = math.floor(s / 86400) })
end

local function Guild()
    local g = ns.GuildKey()
    if not g then ns.Print(ns.L["stats.noguild"]) end
    return g
end

-- A name as typed, to a stored member: exact first, then the one member whose name starts so (any case).
local function Member(guild, typed)
    local g = ns.DB:Guild(guild)
    typed = ns.NormalizeName(typed)
    if not (g and typed) then return typed end
    if g.members[typed] then return typed end
    local want, found = ns.Fold(typed), nil
    for who in pairs(g.members) do
        if ns.Fold(who):sub(1, #want) == want then
            if found then return typed end
            found = who
        end
    end
    return found or typed
end

Commands.Add("search", "search <words>", function(q)
    local guild = Guild()
    if not guild then return end
    if not q or not q:find("%S") then return ns.Print(ns.L["search.usage"]) end
    local rows, total = ns.Index:Search(guild, q, { limit = ns.Config.PRINT_LIMIT })
    if total == 0 then return ns.Print(ns.T("search.none", { q = q })) end
    ns.Print(ns.T("search.head", { n = total, q = q }))
    for _, r in ipairs(rows) do
        ns.Print(ns.T("search.row", { name = r.name, prof = r.prof, who = table.concat(r.holders, ", ") }))
    end
    if total > #rows then ns.Print(ns.T("search.more", { n = total - #rows })) end
end)

Commands.Add("who", "who <name>", function(typed)
    local guild = Guild()
    if not guild then return end
    local who = Member(guild, typed or ns.PlayerKey())
    local profs = ns.Index:Member(guild, who)
    if #profs == 0 then return ns.Print(ns.T("who.none", { who = tostring(who) })) end
    for _, p in ipairs(profs) do
        ns.Print(ns.T("who.row", { prof = p.name, n = p.n, ago = Commands.Ago(p.seen or p.at),
            rank = p.max and (p.rank or "?") .. "/" .. p.max .. ", " or "" }))
    end
end)

Commands.Add("stats", "stats", function()
    local guild = Guild()
    if not guild then return end
    local s = ns.Index:Stats(guild)
    ns.Print(ns.T("stats", { guild = guild, members = s.members, profs = s.profs, recipes = s.recipes }))
end)

Commands.Add("forget", "forget <name>", function(typed)
    local guild = Guild()
    if not guild or not typed then return end
    local who = Member(guild, typed)
    ns.Print(ns.T(ns.Recipes:Forget(guild, who) and "forget.done" or "forget.none", { who = tostring(who) }))
end)

function Commands.Run(msg)
    local word, rest = (msg or ""):match("^%s*(%S*)%s*(.-)%s*$")
    local c = Commands.list[word:lower()]
    if c then return c.fn(rest ~= "" and rest or nil) end
    ns.Print(ns.L["help"])
end

SLASH_PROFF1 = "/proff"
SlashCmdList.PROFF = function(msg) Commands.Run(msg) end
