-- The stored recipes, read outside the game (read-only), through the addon's own DB and Index code. Run from
-- the addon folder after a /reload or logout (the client writes SavedVariables only then):
--
--   luajit tools/db.lua                      every guild: members, professions, recipes
--   luajit tools/db.lua search <words>       who knows a recipe, as /proff search finds it (every guild)
--   luajit tools/db.lua who <First Surname>  one member's professions
--   luajit tools/db.lua check                what DB:Init would drop or migrate (a file that's not our shape)
--   -f <file>                                another SavedVariables file (default: WTF/Account/*/SavedVariables)
--   -g <guild>                               only this guild
local args = { ... }
local opt = {}
local words = {}
local i = 1
while i <= #args do
    local a = args[i]
    if a == "-f" then i = i + 1; opt.file = args[i]
    elseif a == "-g" then i = i + 1; opt.guild = args[i]
    elseif a == "-h" or a == "--help" then
        for line in io.lines(arg[0]) do
            if not line:find("^%-%-") then break end
            print((line:gsub("^%-%- ?", "")))
        end
        os.exit(0)
    else words[#words + 1] = a end
    i = i + 1
end
local cmd = table.remove(words, 1) or "summary"

local here = arg[0]:match("^(.*)/tools/db%.lua$") or "."
local file = opt.file
if not file then
    local p = io.popen('ls -d "' .. here .. '/../../../WTF/Account/"*/SavedVariables/Proff.lua 2>/dev/null')
    file = p:read("*l")
    p:close()
    if not file then io.stderr:write("no WTF/Account/*/SavedVariables/Proff.lua: give one with -f\n"); os.exit(1) end
end
local chunk, err = loadfile(file)
if not chunk then io.stderr:write("can't read ", file, ": ", tostring(err), "\n"); os.exit(1) end
local saved = {}
setfenv(chunk, saved)
chunk()

-- The addon's pure parts in an environment of their own, with the few client calls they make.
local env = setmetatable({
    ProffDB = saved.ProffDB, GetServerTime = os.time, IsInGuild = function() return false end,
    geterrorhandler = function() return function(e) io.stderr:write(tostring(e), "\n") end end,
}, { __index = _G })
local ns = {}
for _, path in ipairs({ "Core/Init.lua", "Core/DB.lua", "Core/Recipes.lua", "Core/Index.lua" }) do
    local f = assert(loadfile(here .. "/" .. path))
    setfenv(f, env)
    f("Proff", ns)
end
local function Copy(t)
    if type(t) ~= "table" then return t end
    local c = {}
    for k, v in pairs(t) do c[k] = Copy(v) end
    return c
end
local raw = Copy(saved.ProffDB) or {} -- (as the file has it: DB:Init cleans in place)
ns.DB:Init()
local data = ns.DB.data

local guilds = {}
for g in pairs(data.guilds) do
    if not opt.guild or g == opt.guild then guilds[#guilds + 1] = g end
end
table.sort(guilds)

if cmd == "summary" then
    print(("%s: schema %s, %d recipe names"):format(file, tostring(data.schema), (function()
        local n = 0
        for _ in pairs(data.recipes) do n = n + 1 end
        return n
    end)()))
    for _, g in ipairs(guilds) do
        local s = ns.Index:Stats(g)
        print(("\n%s: %d members, %d professions, %d recipes (rev %d)"):format(g, s.members, s.profs, s.recipes, data.guilds[g].rev))
        for _, p in ipairs(ns.Index:Professions(g)) do
            print(("  %-16s %3d members %4d recipes"):format(p.name, p.members, p.recipes))
        end
    end
elseif cmd == "search" then
    local q = table.concat(words, " ")
    for _, g in ipairs(guilds) do
        local rows, total = ns.Index:Search(g, q, { limit = 40 })
        print(("%s: %d match %q"):format(g, total, q))
        for _, r in ipairs(rows) do
            print(("  %-40s %-14s %s"):format(r.name, r.prof, table.concat(r.holders, ", ")))
        end
    end
elseif cmd == "who" then
    local who = table.concat(words, " ")
    for _, g in ipairs(guilds) do
        for _, p in ipairs(ns.Index:Member(g, who)) do
            print(("%s: %s %s/%s, %d recipes, from %s, %s"):format(g, p.name, tostring(p.rank), tostring(p.max), p.n,
                tostring(p.from), os.date("%Y-%m-%d %H:%M", p.at or 0)))
        end
    end
elseif cmd == "check" then
    -- What DB:Init kept, against the file as it is.
    local function Count(t, depth)
        if type(t) ~= "table" then return 0 end
        local n = 0
        for _, v in pairs(t) do n = n + (depth > 1 and Count(v, depth - 1) or 1) end
        return n
    end
    print(("schema in file %s, ours %d%s"):format(tostring(raw.schema), ns.DB.SCHEMA, data.readOnly and " (newer: not read)" or ""))
    print(("guilds %d, recipe names %d (after cleaning; the file's: %d, %d)"):format(Count(data.guilds, 1),
        Count(data.recipes, 1), Count(raw.guilds, 1), Count(raw.recipes, 1)))
else
    io.stderr:write("unknown command ", cmd, " (-h for help)\n")
    os.exit(2)
end
