---@class Proff
local ns = select(2, ...)

-- The store: one guild member's profession at a time, whole (Core/DB.lua has the shape). Pure over ns.DB's
-- data, so tools/db.lua runs it outside the game too. Capture decides whose and whether they're a member;
-- this only writes what it's handed, after checking its shape.
---@class Proff.Recipes
local Recipes = {}
ns.Recipes = Recipes

local function Same(a, b)
    for id in pairs(a) do if not b[id] then return false end end
    for id in pairs(b) do if not a[id] then return false end end
    return true
end

-- snap = { guild, who, guid?, line, name, rank?, max?, from = "link"|"own", recipes = { [id] = true },
--          info = { [id] = { n = name, i = icon, c = categoryID, r = { [itemID] = count }? } },
--          at? (when its recipes changed, a relayed one's: Sync), via? (who relayed it) }
-- `at` moves only when the recipes change (it's what sync compares: opening the same profession again mustn't
-- look like news to the guild); `seen` is when it was last read or received.
-- Returns "new" | "changed" | "same", and the count; or nil, why.
function Recipes:Store(snap)
    if type(snap) ~= "table" or type(snap.guild) ~= "string" or type(snap.who) ~= "string" then return nil, "shape" end
    if type(snap.line) ~= "number" or type(snap.recipes) ~= "table" then return nil, "shape" end
    local g = ns.DB:Guild(snap.guild, true)
    if not g then return nil, "readonly" end
    local set, n = {}, 0
    for id, yes in pairs(snap.recipes) do
        if type(id) == "number" and yes == true then set[id] = true; n = n + 1 end
    end
    -- An empty list is a window that hadn't loaded (or a profession with nothing learned): never over a real one.
    if n == 0 then return nil, "empty" end
    local names = ns.DB:Recipes()
    for id in pairs(set) do
        local r = snap.info and snap.info[id]
        if type(r) == "table" and type(r.n) == "string" and r.n ~= "" then
            -- (reagents are read once per recipe: a snapshot without them keeps what's known)
            local reagents = type(r.r) == "table" and r.r or (names[id] and names[id].r)
            names[id] = { n = r.n, i = r.i, l = snap.line, c = r.c, r = reagents }
        end
    end
    local m = g.members[snap.who]
    if not m then
        m = { profs = {} }
        g.members[snap.who] = m
    end
    if snap.guid then m.guid = snap.guid end
    local old = m.profs[snap.line]
    local status = not old and "new" or (Same(old.recipes, set) and "same" or "changed")
    local now = ns.Now()
    local at = snap.at or (status == "same" and old.at) or now
    m.profs[snap.line] = { name = snap.name, rank = snap.rank, max = snap.max, at = at, seen = now, from = snap.from,
        via = snap.via, n = n, recipes = set }
    if status ~= "same" then g.rev = g.rev + 1 end
    ns.Log("Recipes", "%s %s %s (%d) %s", status, snap.who, tostring(snap.name), n, snap.guild)
    ns.Bus:Fire("STORED", snap.guild, snap.who, snap.line, status)
    return status, n
end

-- A member's recipes, gone (line: only that profession). true if there was something.
function Recipes:Forget(guild, who, line)
    local g = ns.DB:Guild(guild)
    local m = g and g.members[who]
    if not m then return false end
    if line then
        if not m.profs[line] then return false end
        m.profs[line] = nil
        if next(m.profs) == nil and not m.skills then g.members[who] = nil end
    else
        g.members[who] = nil
    end
    g.rev = g.rev + 1
    ns.Log("Recipes", "forgot %s%s", who, line and (" line " .. line) or "")
    return true
end

-- Members no longer on a complete roster: gone. isMember(key) -> true/false/nil; only a false drops anyone.
function Recipes:Prune(guild, isMember)
    local g = ns.DB:Guild(guild)
    if not g then return 0 end
    local n = 0
    for who in pairs(g.members) do
        if isMember(who) == false then
            g.members[who] = nil
            n = n + 1
        end
    end
    if n > 0 then
        g.rev = g.rev + 1
        ns.Log("Recipes", "pruned %d who left %s", n, guild)
        ns.Bus:Fire("PRUNED", guild, n)
    end
    return n
end

-- A complete roster of our own guild prunes its bucket.
ns.Bus:On("ROSTER", Recipes, function(_, complete)
    if not complete then return end
    local guild = ns.GuildKey()
    if guild then Recipes:Prune(guild, function(who) return ns.Guild:IsMember(who) end) end
end)
