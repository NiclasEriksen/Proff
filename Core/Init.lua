local addonName = ...
---@class Proff
local ns = select(2, ...)

-- Shared namespace. Every module hangs off ns; nothing is global except the SavedVariables and the slash
-- command. Patterns from Dyreparken (../Dyreparken): its docs/FOREVER_API.md is the client's reference.
ns.name = addonName

local GetMeta = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata

-- A git checkout says "dev" (the TOC's #@debug@ block, which the packager deletes while it uncomments the
-- #@non-debug@ line): a dev build, which logs and has the Dev/ commands. The token itself: a checkout too.
do
    local v = (GetMeta and GetMeta(addonName, "Version")) or ""
    ns.DEV = v == "" or v == "dev" or v:find("@", 1, true) ~= nil
    ns.VERSION = ns.DEV and "dev" or v
end

-- Tunables, in one place.
ns.Config = {
    DEBUG_RING_SIZE = 4000,   -- debug log lines kept (ProffDebugDB.lines)
    READ_DELAY = 0.3,         -- s: TRADE_SKILL_LIST_UPDATE comes in bursts; read once it's quiet
    LINK_FRESH = 30,          -- s: a clicked profession link explains the window that opens within this
    ROSTER_INTERVAL = 60,     -- s: at most one roster request this often
    ROSTER_TIMEOUT = 10,      -- s: the server ignored our roster request; read what the client has
    HELD_MAX = 8,             -- captures waiting for a complete roster (whose membership isn't known yet)
    SEARCH_LIMIT = 50,        -- results a search returns by default
    PRINT_LIMIT = 10,         -- results /proff search prints
    ITEM_WAIT = 10,           -- s: reagent names asked of the server; what hasn't come by then, next time
    ROW_HEIGHT = 18,          -- px: a row of the Guild tab's list
    COMM_PREFIX = "Proff",    -- addon message prefix (16 characters at most)
    COMM_BURST = 4,           -- messages our outbox may send at once (the server allows 10 per prefix)
    COMM_RATE = 0.5,          -- messages a second after that (the server refills 1)
    HELLO_DELAY = 20,         -- s after the settled phase before our hello ...
    HELLO_SPREAD = 40,        -- ... plus up to this, at random: a guild logging in together doesn't speak at once
    SKILLS_INTERVAL = 60,     -- s: the server's guild profession roster asked at most this often
    SKILLS_TIMEOUT = 5,       -- s: its answer given up on
    COMM_HELD = 20,           -- messages from senders not on our roster yet, kept until the next roster
    SYNC_EPOCH = 1767225600,  -- 2026-01-01: sync's times count from here (an index's minutes; older data refused)
    INDEX_WAIT = 6,           -- s (0.2 to 1.2 times): before answering a hello with our index, unless someone did
    INDEX_PAGE = 45,          -- entries in one index message (~450 bytes: two chunks)
    OFFER_WAIT = 4,           -- s (0.5 to 1.5 times): before sending an entry, unless someone did
}

------------------------------------------------------------------------------
-- Values from the client
------------------------------------------------------------------------------

-- A value the client may hand us as a secret (Dyreparken docs/FOREVER_API.md, "Secret values"): nil then, so
-- nothing compares, indexes or prints it. A secret table too (type() says "table").
local function Secret(v)
    return (issecretvalue ~= nil and issecretvalue(v) == true)
        or (type(v) == "table" and issecrettable ~= nil and issecrettable(v) == true)
end
function ns.Plain(v)
    if v == nil or Secret(v) then return nil end
    return v
end
ns.IsSecret = Secret

-- A client call's values, or nil if the function is missing, fails or gives secrets: each one plain.
function ns.Read(fn, ...)
    if type(fn) ~= "function" then return nil end
    local r = { pcall(fn, ...) }
    if not r[1] then return nil end
    -- (at least one value: a function that returned nothing, or a nil, gives a nil, so tostring(ns.Read(...))
    -- can't throw; the window probe did, in game, on an unnamed frame, 2026-11-23)
    local n = math.max(2, table.maxn(r))
    for i = 2, n do r[i] = ns.Plain(r[i]) end
    return unpack(r, 2, n)
end

-- Only a real yes counts: a 0, a secret, a missing function or an error is a no (Mastercraft's lesson, its
-- patch-331: C_TradeSkillUI.IsTradeSkillLinked and friends).
function ns.Yes(fn, ...)
    local v = ns.Read(fn, ...)
    return v == true or (type(v) == "number" and v ~= 0)
end

-- Server time: the same clock for everyone.
function ns.Now() return GetServerTime() end

------------------------------------------------------------------------------
-- Names. On Forever characters have surnames: UnitName gives "First", "Surname" (the second value is not a
-- realm), and roster and chat names are "First Surname". Realms are ignored (Dyreparken's decision,
-- 2026-11-06): a key is "First Surname", and a "-Realm" suffix is stripped.
------------------------------------------------------------------------------
function ns.PlayerKey()
    local first, surname = UnitName("player")
    if ns.IsSecret(first) or ns.IsSecret(surname) then return nil end
    if surname and surname ~= "" then return first .. " " .. surname end
    return first
end

-- Is this text after a "-" a realm? Realm names have no spaces; Forever's look like "CAMWOWEU4Realm1PvE".
-- Checked against the known realms first; the pattern is a fallback so a hyphenated surname survives.
local realms
local function IsRealm(suffix)
    if suffix:find(" ", 1, true) then return false end
    if not realms then
        local own = GetNormalizedRealmName()
        if not own then return suffix:find("%d") ~= nil end
        realms = { [own] = true }
        local list = GetAutoCompleteRealms and GetAutoCompleteRealms()
        if type(list) == "table" then
            for _, r in ipairs(list) do realms[r] = true end
        end
    end
    return realms[suffix] or suffix:find("%u%l*%d") ~= nil
end

-- A name from the client -> "First Surname" (realm suffix stripped, if any); nil for none or a secret.
function ns.NormalizeName(name)
    if type(name) ~= "string" or ns.IsSecret(name) or name == "" then return nil end
    name = name:match("^%s*(.-)%s*$")
    local base, suffix = name:match("^(.+)%-([^%-]+)$")
    if base and IsRealm(suffix) then return base end
    return name ~= "" and name or nil
end

-- The guild's key: its name (guilds don't span rulesets; two same-named guilds on two rulesets would share
-- an entry: accepted, as in Dyreparken). nil outside a guild, or before the client knows the name.
function ns.GuildKey()
    if not IsInGuild() then return nil end
    local name = ns.Read(GetGuildInfo, "player")
    return type(name) == "string" and name ~= "" and name or nil
end

------------------------------------------------------------------------------
-- Text
------------------------------------------------------------------------------

-- Lowercase for matching, Latin-1 letters too: string.lower leaves UTF-8's À..Þ alone (bytes C3 80..9E; their
-- small forms are C3 A0..BE, × and ÷ aside). Recipe names in other client languages have them.
function ns.Fold(s)
    return (s:lower():gsub("\195([\128-\158])", function(b)
        local n = b:byte()
        if n == 0x97 then return "\195" .. b end
        return "\195" .. string.char(n + 32)
    end))
end

-- Our chat frame: the default one (the tests have it as well).
function ns.Print(msg)
    msg = tostring(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cffe0b050Proff:|r " .. msg)
    if ns.Debug and ns.Debug.enabled then ns.Log("Chat", "%s", (msg:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))) end
end

-- ns.L[key] / ns.T(key, vars): the strings (Locale/). A missing key shows as itself, so it's seen.
ns.L = setmetatable({}, { __index = function(_, k) return k end })
function ns.T(key, vars)
    return (ns.L[key]:gsub("{(%w+)}", function(k)
        local v = vars and vars[k]
        return v ~= nil and tostring(v) or nil
    end))
end

------------------------------------------------------------------------------
-- Start-up phases and helpers
------------------------------------------------------------------------------

-- loaded: ADDON_LOADED (SavedVariables are in); login: PLAYER_LOGIN; settled: a few seconds after the first
-- PLAYER_ENTERING_WORLD (the guild's name and roster are known by then).
local starts = { loaded = {}, login = {}, settled = {} }
function ns.Start(phase, fn)
    local list = assert(starts[phase], "unknown start-up phase")
    list[#list + 1] = fn
end
-- One module's error is reported, and the rest of the phase still starts.
function ns.RunPhase(phase)
    for _, fn in ipairs(starts[phase]) do
        local ok, err = pcall(fn)
        if not ok then geterrorhandler()(err) end
    end
end

-- fn once, delay seconds after the first call of a burst (the calls that follow within it are folded in).
function ns.Debounce(delay, fn)
    local pending = false
    return function()
        if pending then return end
        pending = true
        C_Timer.After(delay, function()
            pending = false
            fn()
        end)
    end
end

-- Internal events between modules. Every one is declared here (a typo would otherwise fire into nothing).
---@class Proff.Bus
local Bus = { EVENTS = {
    ROSTER = true,   -- Guild read a roster (complete or not)
    STORED = true,   -- Recipes stored a profession: (guild, who, line, "new" | "changed" | "same");
                     -- line 0: Skills stored a skill sheet
    PRUNED = true,   -- Recipes dropped members who left: (guild, n)
    DEBUG = true,    -- the debug log was turned on or off: (on)
    ITEMS = true,    -- Items learned reagent names (searchable now)
    SKILLS = true,   -- Skills read the server's guild profession roster
}, handlers = {} }
ns.Bus = Bus
function Bus:On(event, owner, fn)
    assert(self.EVENTS[event], "unknown Bus event " .. tostring(event))
    self.handlers[event] = self.handlers[event] or {}
    self.handlers[event][owner] = fn
end
function Bus:Off(event, owner)
    if self.handlers[event] then self.handlers[event][owner] = nil end
end
function Bus:Fire(event, ...)
    assert(self.EVENTS[event], "unknown Bus event " .. tostring(event))
    for owner, fn in pairs(self.handlers[event] or {}) do
        local ok, err = pcall(fn, owner, ...)
        if not ok then geterrorhandler()(err) end
    end
end

ns.Log = function() end -- (Core/Debug.lua binds it)
