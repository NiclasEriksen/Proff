-- The harness's foundations: the addon's name, the stub client's known events, what Forever lacks, the
-- professions' data, reading the TOC, compiling the addon's files once (Load) and a clean Lua 5.1 global
-- environment with WoW's extras (NewEnv).
local H, P = ...

local ADDON = "Proff"
H.ADDON = ADDON

-- A value the client hides from addons (Forever "secret values").
H.SECRET = setmetatable({}, { __tostring = function() return "<secret>" end })

-- What Forever doesn't have (Dyreparken docs/FOREVER_API.md, "Missing"): the stub client lacks it too
-- (01_core checks), so the addon can't come to rely on it. Keep this in step with docs/FOREVER_API.md.
H.MISSING = {
    globals = { "GetSpellInfo", "GetItemInfo", "UnitAura", "GetNumSkillLines", "GetSkillLineInfo", "GetNumAddOns",
        "GetTradeSkillLine", "GetNumTradeSkills", "GetTradeSkillInfo", "GetCraftInfo", "CombatLogGetCurrentEventInfo",
        "require", "dofile", "loadfile", "io" },
    events = { "COMBAT_LOG_EVENT_UNFILTERED", "TRADE_SKILL_UPDATE", "CRAFT_SHOW" },
}

-- Events the stub client knows. Registering anything else throws, like the real client, which catches typos.
local KNOWN_EVENTS = {}
for e in ([[ADDON_LOADED PLAYER_LOGIN PLAYER_LOGOUT PLAYER_ENTERING_WORLD GUILD_ROSTER_UPDATE PLAYER_GUILD_UPDATE
    TRADE_SKILL_SHOW TRADE_SKILL_CLOSE TRADE_SKILL_LIST_UPDATE TRADE_SKILL_DATA_SOURCE_CHANGED
    TRADE_SKILL_DATA_SOURCE_CHANGING TRADE_SKILL_NAME_UPDATE NEW_RECIPE_LEARNED SKILL_LINES_CHANGED
    TRADE_SKILL_FAVORITES_CHANGED TRADE_SKILL_DETAILS_UPDATE ITEM_DATA_LOAD_RESULT GET_ITEM_INFO_RECEIVED
    GUILD_TRADESKILL_UPDATE GUILD_RECIPE_KNOWN_BY_MEMBERS CHAT_MSG_ADDON SPELL_DATA_LOAD_RESULT]]):gmatch("%S+") do
    KNOWN_EVENTS[e] = true
end

-- Professions as the stub client has them: base skill line, the child line the window shows, the spell a
-- link carries, and recipes (id -> name). Ids are retail's where known; the data is the tests' own.
H.PROFESSIONS = {
    [171] = { name = "Alchemy", child = 2485, spell = 2259, recipes = {
        [2330] = "Minor Healing Potion", [2331] = "Minor Mana Potion", [2332] = "Minor Rejuvenation Potion",
        [3447] = "Healing Potion", [7181] = "Greater Healing Potion", [11457] = "Superior Healing Potion",
        [17556] = "Major Healing Potion", [17635] = "Flask of the Titans" } },
    [164] = { name = "Blacksmithing", child = 2477, spell = 2018, recipes = {
        [2662] = "Copper Chain Pants", [2663] = "Copper Bracers", [3115] = "Rough Sharpening Stone",
        [16728] = "Helm of the Great Chief" } },
    [197] = { name = "Tailoring", child = 2540, spell = 3908, recipes = {
        [2387] = "Linen Cloak", [2393] = "White Linen Shirt", [3914] = "Brown Linen Pants",
        [18560] = "Mooncloth", [12092] = "Dreamweave Circlet" } },
    [333] = { name = "Enchanting", child = 2494, spell = 7411, recipes = {
        [7418] = "Enchant Bracer - Minor Health", [13661] = "Enchant Bracer - Strength",
        [20025] = "Enchant Chest - Greater Stats", [25124] = "Minor Wizard Oil" } },
    -- (a secondary profession: Forever's guild profession roster leaves these out)
    [185] = { name = "Cooking", child = 2548, spell = 2550, secondary = true, recipes = {
        [2538] = "Charred Wolf Meat", [2540] = "Roasted Boar Meat" } },
}

-- Reagents (GetRecipeSchematic's slots: item id -> count) of some recipes, and the items' names. A recipe not
-- listed has an empty schematic.
H.REAGENTS = {
    [2330] = { [2447] = 1, [765] = 1, [3371] = 1 },   -- Minor Healing Potion: Peacebloom, Silverleaf, Empty Vial
    [3447] = { [2453] = 1, [2450] = 1, [3371] = 1 },  -- Healing Potion: Bruiseweed, Briarthorn, Empty Vial
    [17556] = { [13464] = 2, [13465] = 1, [8925] = 1 }, -- Major Healing Potion: Golden Sansam, Mountain Silversage
    [2387] = { [2996] = 2, [2320] = 1 },              -- Linen Cloak: Bolt of Linen Cloth, Coarse Thread
    [7418] = { [10940] = 1 },                         -- Enchant Bracer - Minor Health: Strange Dust
}
H.ITEMS = { [2447] = "Peacebloom", [765] = "Silverleaf", [3371] = "Empty Vial", [2453] = "Bruiseweed",
    [2450] = "Briarthorn", [13464] = "Golden Sansam", [13465] = "Mountain Silversage", [8925] = "Crystal Vial",
    [2996] = "Bolt of Linen Cloth", [2320] = "Coarse Thread", [10940] = "Strange Dust" }

------------------------------------------------------------------------------
-- Sources and the TOC
------------------------------------------------------------------------------
local sources = {}
local function Source(path)
    if not sources[path] then
        local f = assert(io.open(path, "rb"), "missing " .. path)
        sources[path] = f:read("*a")
        f:close()
    end
    return sources[path]
end

-- files: every file, as a git checkout loads them; release: without the #@do-not-package@ blocks (Dev/).
local function ParseTOC(text)
    local toc = { files = {}, release = {}, meta = {} }
    local packaged = true
    for line in text:gmatch("[^\r\n]+") do
        local k, v = line:match("^##%s*([^:]+):%s*(.-)%s*$")
        if k then
            toc.meta[k] = v
        elseif line:match("^#@do%-not%-package@") then
            packaged = false
        elseif line:match("^#@end%-do%-not%-package@") then
            packaged = true
        elseif not line:match("^%s*#") and line:match("%S") then
            local path = (line:gsub("\\", "/"))
            toc.files[#toc.files + 1] = path
            if packaged then toc.release[#toc.release + 1] = path end
        end
    end
    assert(packaged, "a #@do-not-package@ block without its end")
    return toc
end
local TOC = ParseTOC(Source(ADDON .. ".toc"))
H.TOC = TOC
H.ParseTOC = ParseTOC

-- Compiled once per path, then loaded from bytecode (the line info survives for coverage and errors).
local compiled = {}
local function Load(env, path, ...)
    if not compiled[path] then compiled[path] = string.dump(assert(loadstring(Source(path), "@" .. path))) end
    local chunk = assert(loadstring(compiled[path], "@" .. path))
    setfenv(chunk, env)
    return chunk(...)
end

------------------------------------------------------------------------------
-- A clean global environment with Lua 5.1 and WoW's Lua extras
------------------------------------------------------------------------------
local STD = { "assert", "error", "ipairs", "next", "pairs", "pcall", "rawequal", "rawget", "rawset", "select",
    "setmetatable", "getmetatable", "tonumber", "tostring", "type", "unpack", "xpcall", "loadstring",
    "setfenv", "getfenv", "string", "table", "math", "coroutine", "bit", "_VERSION", "collectgarbage" }

local function strsplit(delim, s, pieces)
    local out, pos = {}, 1
    while true do
        if pieces and #out == pieces - 1 then out[#out + 1] = s:sub(pos); break end
        local a, b = s:find("[" .. delim:gsub("%p", "%%%0") .. "]", pos)
        if not a then out[#out + 1] = s:sub(pos); break end
        out[#out + 1] = s:sub(pos, a - 1)
        pos = b + 1
    end
    return unpack(out)
end

local function CopyTable(t)
    local c = {}
    for k, v in pairs(t) do c[k] = type(v) == "table" and CopyTable(v) or v end
    return c
end
H.CopyTable = CopyTable

local function NewEnv()
    local env = {}
    for _, k in ipairs(STD) do env[k] = _G[k] end
    env.os = { time = os.time, date = os.date, clock = os.clock }
    env._G = env
    env.strtrim = function(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
    env.strsplit = strsplit
    env.wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
    env.CopyTable = CopyTable
    env.tinsert, env.tremove, env.sort = table.insert, table.remove, table.sort
    env.strsub, env.strlen, env.strbyte, env.strchar = string.sub, string.len, string.byte, string.char
    env.strfind, env.strmatch, env.strlower, env.strupper = string.find, string.match, string.lower, string.upper
    env.strrep, env.format, env.gsub = string.rep, string.format, string.gsub
    env.floor, env.ceil, env.min, env.max, env.abs = math.floor, math.ceil, math.min, math.max, math.abs
    return env
end

P.ADDON, P.KNOWN_EVENTS = ADDON, KNOWN_EVENTS
P.Source, P.TOC, P.Load, P.NewEnv, P.CopyTable = Source, TOC, Load, NewEnv, CopyTable
