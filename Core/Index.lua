---@class Proff
local ns = select(2, ...)

-- Search over one guild's stored recipes. Built on demand, the first search after a change (the guild's
-- rev moved, or a reagent's name was learned), and kept in memory only: a few thousand rows at most, so a
-- linear scan over folded text is fast enough and needs no token index. Pure over ns.DB's data (tools/db.lua
-- searches a saved file with it). A word is looked for in the recipe's name, its profession's, the names of
-- who knows it and of its reagents: "kari", "peacebloom", "alchemy healing" all find recipes.
--
--   Index:Search(guild, "major healing", { line = 171, limit = 20 })
--     -> { { id, name, icon, line, prof, holders = { "Ola Nord", ... },
--            reagents = { { id, name?, count }, ... } }, ... }, total
--   Index:Holders(guild, recipeID) -> { "Ola Nord", ... }
--   Index:Member(guild, who) -> { { line, name, rank, max, at, from, n }, ... }
--   Index:Professions(guild) -> { { line, name, members, recipes }, ... }
--   Index:Stats(guild) -> { members, profs, recipes }
---@class Proff.Index
local Index = { built = {} }
ns.Index = Index

local function SortedKeys(t)
    local list = {}
    for k in pairs(t) do list[#list + 1] = k end
    table.sort(list)
    return list
end

-- rows: one per recipe someone in the guild knows; byId: the same rows by recipe id.
function Index:Build(guild)
    local g = ns.DB:Guild(guild)
    if not g then return nil end
    local cached = self.built[guild]
    local itemsRev = ns.DB.itemsRev or 0
    if cached and cached.rev == g.rev and cached.bucket == g and cached.itemsRev == itemsRev then return cached end
    local names, items = ns.DB:Recipes(), ns.DB:Items() or {}
    local byId, rows, profNames = {}, {}, {}
    for who, m in pairs(g.members) do
        for line, p in pairs(m.profs) do
            if type(p.name) == "string" then profNames[line] = profNames[line] or p.name end
            for id in pairs(p.recipes) do
                local row = byId[id]
                if not row then
                    local r = names[id]
                    row = { id = id, name = r and r.n or ("#" .. id), icon = r and r.i, line = line, holders = {},
                        reagents = {} }
                    for item, count in pairs(r and r.r or {}) do
                        row.reagents[#row.reagents + 1] = { id = item, name = items[item], count = count }
                    end
                    table.sort(row.reagents, function(a, b) return a.id < b.id end)
                    byId[id] = row
                    rows[#rows + 1] = row
                end
                row.holders[#row.holders + 1] = who
            end
        end
    end
    for _, row in ipairs(rows) do
        table.sort(row.holders)
        row.prof = profNames[row.line] or ("#" .. row.line)
        row.fold = ns.Fold(row.name)
        local hay = { row.fold, ns.Fold(row.prof) }
        for _, who in ipairs(row.holders) do hay[#hay + 1] = ns.Fold(who) end
        for _, re in ipairs(row.reagents) do if re.name then hay[#hay + 1] = ns.Fold(re.name) end end
        row.hay = table.concat(hay, "\n") -- (a word can't match across two of them)
    end
    table.sort(rows, function(a, b)
        if a.fold ~= b.fold then return a.fold < b.fold end
        return a.id < b.id
    end)
    local built = { rev = g.rev, bucket = g, itemsRev = itemsRev, rows = rows, byId = byId, profNames = profNames }
    self.built[guild] = built
    ns.Log("Index", "built %s: %d recipes (rev %d)", guild, #rows, g.rev)
    return built
end

local function Words(query)
    local words = {}
    for w in ns.Fold(query):gmatch("%S+") do words[#words + 1] = w end
    return words
end

-- How well a row matches (lower is better), or nil for no match: every word must be in its name, its
-- profession's, a holder's or a reagent's; a number matches the recipe id too. The whole query starting the
-- name ranks first, then every word starting a word of the name, then the rest.
local function Rank(row, words, whole)
    local starts = true
    for _, w in ipairs(words) do
        if not row.hay:find(w, 1, true) and tostring(row.id) ~= w then return nil end
        if starts and not (row.fold:sub(1, #w) == w or row.fold:find(" " .. w, 1, true)) then starts = false end
    end
    if row.fold:sub(1, #whole) == whole then return 0 end
    return starts and 1 or 2
end

function Index:Search(guild, query, opts)
    opts = opts or {}
    local built = self:Build(guild)
    if not built or type(query) ~= "string" then return {}, 0 end
    local words = Words(query)
    if #words == 0 and not opts.all then return {}, 0 end
    local whole = table.concat(words, " ")
    local hits = {}
    for _, row in ipairs(built.rows) do
        if not opts.line or row.line == opts.line then
            local rank = #words == 0 and 0 or Rank(row, words, whole)
            if rank then hits[#hits + 1] = { row = row, rank = rank } end
        end
    end
    -- (stable: rows are in name order already, so a rank's ties keep it)
    for i, h in ipairs(hits) do h.i = i end
    table.sort(hits, function(a, b)
        if a.rank ~= b.rank then return a.rank < b.rank end
        return a.i < b.i
    end)
    local limit = opts.limit or ns.Config.SEARCH_LIMIT
    local out = {}
    for i = 1, math.min(limit, #hits) do
        local r = hits[i].row
        local holders = {}
        for j, who in ipairs(r.holders) do holders[j] = who end
        local reagents = {}
        for j, re in ipairs(r.reagents) do reagents[j] = { id = re.id, name = re.name, count = re.count } end
        out[i] = { id = r.id, name = r.name, icon = r.icon, line = r.line, prof = r.prof, holders = holders,
            reagents = reagents }
    end
    return out, #hits
end

function Index:Holders(guild, id)
    local built = self:Build(guild)
    local row = built and built.byId[id]
    if not row then return {} end
    local out = {}
    for i, who in ipairs(row.holders) do out[i] = who end
    return out
end

function Index:Member(guild, who)
    local g = ns.DB:Guild(guild)
    local m = g and g.members[who]
    if not m then return {} end
    local out = {}
    for _, line in ipairs(SortedKeys(m.profs)) do
        local p = m.profs[line]
        out[#out + 1] = { line = line, name = p.name, rank = p.rank, max = p.max, at = p.at, seen = p.seen, from = p.from,
            via = p.via, n = p.n }
    end
    return out
end

function Index:Professions(guild)
    local built = self:Build(guild)
    if not built then return {} end
    local g = ns.DB:Guild(guild)
    local per = {}
    for _, m in pairs(g.members) do
        for line in pairs(m.profs) do
            per[line] = per[line] or { line = line, name = built.profNames[line] or ("#" .. line), members = 0, recipes = 0 }
            per[line].members = per[line].members + 1
        end
    end
    for _, row in ipairs(built.rows) do if per[row.line] then per[row.line].recipes = per[row.line].recipes + 1 end end
    local out = {}
    for _, line in ipairs(SortedKeys(per)) do out[#out + 1] = per[line] end
    table.sort(out, function(a, b) return a.name < b.name end)
    return out
end

function Index:Stats(guild)
    local built = self:Build(guild)
    if not built then return { members = 0, profs = 0, recipes = 0 } end
    local members, profs = 0, 0
    for _, m in pairs(ns.DB:Guild(guild).members) do
        -- (one with a skill sheet only: no recipes known)
        if next(m.profs) then members = members + 1 end
        for _ in pairs(m.profs) do profs = profs + 1 end
    end
    return { members = members, profs = profs, recipes = #built.rows }
end
