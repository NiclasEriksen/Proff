---@class Proff
local ns = select(2, ...)

-- The saved data, account-wide (ProffDB), so every character of the account sees what any of them stored:
--
--   ProffDB = {
--     schema = 3,
--     guilds = { [guild name] = {
--       rev = n,                 -- bumped by every change (Index rebuilds when it moved)
--       members = { ["First Surname"] = {
--         guid = "Player-...",   -- the last one seen (a link carries it; a name change keeps the GUID)
--         profs = { [skill line] = {
--           name = "Alchemy", rank = 150, max = 225,
--           at = serverTime,     -- when its recipes last changed (what sync compares; a relayed one's: its author's)
--           seen = serverTime,   -- when it was last read or received
--           from = "link" | "own",  via = "First Surname"?  -- who relayed it to us (Sync), if not read here
--           n = count, recipes = { [recipeID] = true },
--         } },
--         skills = {             -- their skill sheet: every profession's level, secondaries too (Core/Skills.lua);
--           at = serverTime,     -- read by them from their own client and relayed (Sync), so only Proff users have
--           seen = serverTime,   -- one; at: when a level last changed (what sync compares, as for profs)
--           via = "First Surname"?,
--           lines = { [skill line] = { r = rank, m = max } },
--         },
--       } },
--     } },
--     recipes = { [recipeID] = { n = name, i = icon, l = skill line, c = categoryID,
--                                r = { [itemID] = count } } },  -- shared by guilds; r: its reagents
--     items = { [itemID] = name },  -- the reagents' names (Core/Items.lua), for searching by ingredient
--   }
--
-- A profession is stored whole each time it's read (a linked window shows all of it), never merged: a
-- recipe they no longer show is gone. Changes to this shape go through MIGRATIONS; tests read old data.
---@class Proff.DB
local DB = {}
ns.DB = DB

DB.SCHEMA = 3

-- MIGRATIONS[n] takes the data from schema n - 1 to n.
DB.MIGRATIONS = {
    -- 2 (2026-11-23): reagents (recipes[id].r) and their names (items), for the Guild tab's ingredient search.
    -- Recipes stored before have none until their profession is seen again.
    [2] = function(db) db.items = type(db.items) == "table" and db.items or {} end,
    -- 3 (2026-11-23): members' skill sheets (members[who].skills), shared by sync. Nothing to convert: new field.
    [3] = function() end,
}

-- Bumped whenever an item name is learned (in memory): Index rebuilds, as reagent names are searched.
DB.itemsRev = 0

local function Table(t) return type(t) == "table" and t or {} end

-- A skill sheet as stored (and as Sync builds one from a message before storing it).
function DB.ValidSheet(s)
    if type(s) ~= "table" or type(s.at) ~= "number" or type(s.lines) ~= "table" then return false end
    for line, l in pairs(s.lines) do
        if type(line) ~= "number" or type(l) ~= "table" or type(l.r) ~= "number" then return false end
        if l.m ~= nil and type(l.m) ~= "number" then return false end
    end
    return next(s.lines) ~= nil
end

-- Data that isn't the shape we write is dropped, not trusted: SavedVariables can be hand-edited or broken.
local function Clean(db)
    db.guilds = Table(db.guilds)
    db.recipes = Table(db.recipes)
    db.items = Table(db.items)
    for g, guild in pairs(db.guilds) do
        if type(g) ~= "string" or type(guild) ~= "table" then
            db.guilds[g] = nil
        else
            guild.members = Table(guild.members)
            guild.rev = tonumber(guild.rev) or 0
            for who, m in pairs(guild.members) do
                if type(who) ~= "string" or type(m) ~= "table" then
                    guild.members[who] = nil
                else
                    m.profs = Table(m.profs)
                    if m.skills ~= nil and not DB.ValidSheet(m.skills) then m.skills = nil end
                    for line, p in pairs(m.profs) do
                        if type(line) ~= "number" or type(p) ~= "table" or type(p.recipes) ~= "table" then
                            m.profs[line] = nil
                        end
                    end
                end
            end
        end
    end
    for id, r in pairs(db.recipes) do
        if type(id) ~= "number" or type(r) ~= "table" or type(r.n) ~= "string" then
            db.recipes[id] = nil
        elseif r.r ~= nil then
            local ok = type(r.r) == "table"
            for item, count in pairs(ok and r.r or {}) do
                if type(item) ~= "number" or type(count) ~= "number" then ok = false end
            end
            if not ok then r.r = nil end
        end
    end
    for id, name in pairs(db.items) do
        if type(id) ~= "number" or type(name) ~= "string" then db.items[id] = nil end
    end
end

function DB:Init()
    local db = type(ProffDB) == "table" and ProffDB or {}
    local schema = tonumber(db.schema) or (next(db) and 0 or self.SCHEMA)
    if schema > self.SCHEMA then
        -- Newer data than this version knows (an older copy installed again): kept as it is, not read.
        ns.Log("DB", "schema %d is newer than ours (%d): data left alone", schema, self.SCHEMA)
        self.data = { guilds = {}, recipes = {}, items = {}, schema = self.SCHEMA, readOnly = true }
        return
    end
    for n = schema + 1, self.SCHEMA do
        if self.MIGRATIONS[n] then self.MIGRATIONS[n](db) end
        ns.Log("DB", "migrated to schema %d", n)
    end
    db.schema = self.SCHEMA
    Clean(db)
    ProffDB = db
    self.data = db
end

-- A guild's bucket; created only when asked to (create), so looking doesn't write.
function DB:Guild(key, create)
    if not key then return nil end
    local guilds = self.data.guilds
    local g = guilds[key]
    if not g and create and not self.data.readOnly then
        g = { members = {}, rev = 0 }
        guilds[key] = g
    end
    return g
end

function DB:Recipes() return self.data.recipes end
function DB:Items() return self.data.items end

ns.Start("loaded", function() DB:Init() end)
