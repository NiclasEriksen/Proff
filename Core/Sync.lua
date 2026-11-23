---@class Proff
local ns = select(2, ...)

-- Guild sync: every Proff user in the guild ends up holding every guild member's professions any of them has
-- stored, relayed (the user, 2026-11-23: "Yes, relay"): one guildmate opening Kari's link is enough for all,
-- Kari needn't run Proff. Silent (the debug log, "Sync", only); cheap (a few bytes per login when nothing's new);
-- slow is fine (Comm's paced outbox).
--
-- What's compared is an ENTRY: one member's one profession, versioned by its `at` (when its recipes last changed:
-- Recipes:Store; opening the same again doesn't move it), or one member's skill sheet (line 0 in its key: every
-- profession's level as their own client read it, Core/Skills.lua; only Proff users make one, everyone relays it). Newer wins, from whoever sends it; about members only
-- (a non-member's entry is dropped, as Capture drops their links). Data from guildmates is trusted as far as
-- that: a forged entry is possible, and replaced by the next newer read of the real thing.
--
-- Messages (Comm: GUILD, tab-separated fields; numbers are Pack text unless said):
--   H hello    proto, count, digest     — once a login (Config.HELLO_DELAY + up to HELLO_SPREAD), ~15 bytes.
--                                          digest: a hash of our index; the same digest means the same entries.
--   I index    proto, digest, page, pages, entries
--                                        — sent by one who heard a hello with another digest than theirs (after
--                                          a random wait; not if someone with our digest sent theirs meanwhile).
--                                          entries: for each, Hash(who), line, minute of `at` (Config.SYNC_EPOCH),
--                                          back to back, ~10 bytes; Config.INDEX_PAGE a page. Pages stand alone.
--   R request  proto, target, keys       — to the index's sender (others ignore it, but note it as asked):
--                                          the entries of theirs that are newer than ours (Hash(who), line).
--   D data     proto, who, line, at, from, rank, max, profession name, recipes (Pack.Set)
--                                        — one entry, whole, to everyone: answers a request, and is pushed when
--                                          an index lacks it or has it older, and when we capture something new.
--                                          Each D waits a moment and is dropped before it leaves if a D for that
--                                          entry, as new as ours, was heard meanwhile (Comm:SendIf).
--   K skills   proto, who, at, levels   — one skill sheet, whole, as D is (same offers, same dropping).
--                                          levels: for each profession, line, rank, max (0: unknown), back to back.
-- Only ids travel: names, icons and reagents are found by the receiver (Core/Spells.lua).
-- A wire change bumps PROTOCOL; a newer peer's message is read as far as ours goes.
---@class Proff.Sync
local Sync = { PROTOCOL = 3, heard = {}, asked = {}, indexes = {}, seenIndex = {}, offered = {} }
ns.Sync = Sync

local Pack = ns.Pack
local LIMIT = { WHO = 48, NAME = 40, RECIPES = 2000, PER_PAGE = 120, KEYS = 120, LEVELS = 12 }

------------------------------------------------------------------------------
-- What we hold
------------------------------------------------------------------------------
function Sync.Key(who, line) return Pack.Num(Pack.Hash(who)) .. Pack.Num(line) end
function Sync.Minute(at) return math.max(0, math.floor(((at or 0) - ns.Config.SYNC_EPOCH) / 60)) end

-- Our entries: key -> { who, line, p }, and the keys sorted. A skill sheet's line is 0, its p the sheet.
function Sync:Entries()
    local g = ns.DB:Guild(ns.GuildKey())
    local by, keys = {}, {}
    for who, m in pairs(g and g.members or {}) do
        for line, p in pairs(m.profs) do
            local k = Sync.Key(who, line)
            -- (two members whose names hash alike: neither is synced, rather than one in the other's place)
            if by[k] then by[k].clash = true else by[k] = { who = who, line = line, p = p }; keys[#keys + 1] = k end
        end
        if m.skills then
            local k = Sync.Key(who, 0)
            if by[k] then by[k].clash = true else by[k] = { who = who, line = 0, p = m.skills }; keys[#keys + 1] = k end
        end
    end
    for k, e in pairs(by) do if e.clash then by[k] = nil end end
    local out = {}
    for _, k in ipairs(keys) do if by[k] then out[#out + 1] = k end end
    table.sort(out)
    return by, out
end

-- The index text of our entries, and its digest.
function Sync:Index()
    local by, keys = self:Entries()
    local parts = {}
    for i, k in ipairs(keys) do parts[i] = k .. Pack.Num(Sync.Minute(by[k].p.at)) end
    local text = table.concat(parts)
    return by, keys, parts, Pack.Num(Pack.Hash(text)) .. Pack.Num(#keys)
end

-- A sheet's levels as text (line, rank, max: Pack numbers), and back: { [line] = { r, m } }, nil if malformed.
function Sync.Levels(lines)
    local ids = {}
    for line in pairs(lines) do ids[#ids + 1] = line end
    table.sort(ids)
    local parts = {}
    for i, line in ipairs(ids) do
        local l = lines[line]
        parts[i] = Pack.Num(line) .. Pack.Num(math.max(0, math.floor(l.r))) .. Pack.Num(math.max(0, math.floor(l.m or 0)))
    end
    return table.concat(parts)
end
function Sync.ReadLevels(s)
    if type(s) ~= "string" or s == "" then return nil end
    local out, n, pos = {}, 0, 1
    while pos <= #s do
        local line, r, m
        line, pos = Pack.ReadNum(s, pos)
        if line then r, pos = Pack.ReadNum(s, pos) end
        if r then m, pos = Pack.ReadNum(s, pos) end
        if not m or line < 1 or line > 1e6 or r > 1000 or m > 1000 or out[line] then return nil end
        n = n + 1
        if n > LIMIT.LEVELS then return nil end
        out[line] = { r = r, m = m > 0 and m or nil }
    end
    return out
end

------------------------------------------------------------------------------
-- Sending
------------------------------------------------------------------------------
function Sync:Hello()
    if not ns.GuildKey() then return false end
    ns.Skills:Own() -- (the guild may not have been known when we logged in)
    local _, keys, _, digest = self:Index()
    return ns.Comm:Send("H", self.PROTOCOL, Pack.Num(#keys), digest)
end

function Sync:SendIndex()
    local _, keys, parts, digest = self:Index()
    local per = ns.Config.INDEX_PAGE
    local pages = math.max(1, math.ceil(#keys / per))
    for page = 1, pages do
        local chunk = table.concat(parts, "", (page - 1) * per + 1, math.min(#parts, page * per))
        ns.Comm:Send("I", self.PROTOCOL, digest, page, pages, chunk)
    end
    ns.Log("Sync", "index sent: %d entries, %d pages", #keys, pages)
end

-- One entry to everyone, a moment from now, unless someone sends it (as new) first.
function Sync:Offer(key, why)
    local by = self:Entries()
    local e = by[key]
    if not e then return false end
    local p = e.p
    local at = p.at or 0
    -- (one waiting offer for an entry as it is: several indexes may want it at once)
    if self.offered[key] == at then return false end
    self.offered[key] = at
    local since = GetTime()
    -- Still ours as it was, and nobody sent it (as new) since we offered.
    local function Needed()
        local cur = Sync:Entries()[key]
        local h = Sync.heard[key]
        return cur ~= nil and cur.p.at == at and not (h and h.time >= since and h.at >= at)
    end
    C_Timer.After(ns.Config.OFFER_WAIT * (0.5 + math.random()), function()
        Sync.offered[key] = nil
        if not Needed() then return end
        if e.line == 0 then
            ns.Comm:SendIf(Needed, "K", Sync.PROTOCOL, e.who, at, Sync.Levels(p.lines))
        else
            ns.Comm:SendIf(Needed, "D", Sync.PROTOCOL, e.who, e.line, at, p.from or "", p.rank or "", p.max or "",
                p.name or "", Pack.Set(p.recipes))
        end
        ns.Log("Sync", "offered %s line %d (%s)", e.who, e.line, why)
    end)
    return true
end

------------------------------------------------------------------------------
-- Receiving
------------------------------------------------------------------------------
local function Proto(p)
    p = tonumber(p)
    return p and p >= Sync.PROTOCOL
end

-- Reads entries text: { key -> minute } in order; nil if malformed or over max.
function Sync.ReadIndex(s, max)
    if type(s) ~= "string" then return nil end
    local out, n, pos = {}, 0, 1
    while pos <= #s do
        local start = pos
        local h, line, minute, keyEnd
        h, pos = Pack.ReadNum(s, pos)
        if h then line, pos = Pack.ReadNum(s, pos) end
        if line then keyEnd = pos; minute, pos = Pack.ReadNum(s, pos) end
        if not minute then return nil end
        n = n + 1
        if n > max then return nil end
        out[#out + 1] = { key = s:sub(start, keyEnd - 1), minute = minute }
    end
    return out
end

ns.Comm:Register("H", function(sender, proto, count, digest)
    if not Proto(proto) or type(digest) ~= "string" then return ns.Log("Sync", "hello from %s: not ours (%s)", sender, tostring(proto)) end
    local _, _, _, ours = Sync:Index()
    ns.Log("Sync", "hello from %s: %s entries, %s", sender, tostring(Pack.ReadNum(count or "")), digest == ours and "same" or "differs")
    if digest == ours then return end
    -- Someone should answer with their index: we do, after a while, unless one with our digest has by then.
    local asked = ns.Now()
    C_Timer.After(ns.Config.INDEX_WAIT * (0.2 + math.random()), function()
        local _, _, _, now = Sync:Index()
        if (Sync.seenIndex[now] or 0) >= asked then return ns.Log("Sync", "index: someone with ours answered") end
        Sync:SendIndex()
    end)
end)

ns.Comm:Register("I", function(sender, proto, digest, page, pages, text)
    page, pages = tonumber(page), tonumber(pages)
    if not Proto(proto) or not page or not pages or page < 1 or pages > 50 or page > pages then
        return ns.Log("Sync", "index from %s: malformed", sender)
    end
    Sync.seenIndex[digest or ""] = ns.Now()
    local entries = Sync.ReadIndex(text or "", LIMIT.PER_PAGE)
    if not entries then return ns.Log("Sync", "index from %s: malformed entries", sender) end
    local by = Sync:Entries()
    local seen = Sync.indexes[sender]
    if page == 1 or not seen then seen = {}; Sync.indexes[sender] = seen end
    local want = {}
    for _, e in ipairs(entries) do
        seen[e.key] = true
        local mine = by[e.key]
        local ours = mine and Sync.Minute(mine.p.at)
        if not mine or ours < e.minute then
            if (Sync.asked[e.key] or 0) < ns.Now() - 60 then want[#want + 1] = e.key; Sync.asked[e.key] = ns.Now() end
        elseif ours > e.minute then
            Sync:Offer(e.key, "their index has it older")
        end
    end
    -- (who asks is unknown to a key: the member's name comes with its data)
    for i = 1, #want, LIMIT.KEYS do
        ns.Comm:Send("R", Sync.PROTOCOL, sender, table.concat(want, "", i, math.min(#want, i + LIMIT.KEYS - 1)))
    end
    if #want > 0 then ns.Log("Sync", "asked %s for %d entries", sender, #want) end
    -- Their whole index heard: what they don't have at all, pushed.
    if page == pages then
        local pushed = 0
        for key in pairs(by) do
            if not seen[key] then
                Sync:Offer(key, "their index lacks it")
                pushed = pushed + 1
            end
        end
        Sync.indexes[sender] = nil
        ns.Log("Sync", "index from %s: %d pages, %d of ours they lack", sender, pages, pushed)
    end
end)

-- Keys text -> list of keys (Hash(who), line pairs).
local function ReadKeys(s)
    local out, pos = {}, 1
    while type(s) == "string" and pos <= #s do
        local start = pos
        local h, line
        h, pos = Pack.ReadNum(s, pos)
        if h then line, pos = Pack.ReadNum(s, pos) end
        if not line then return nil end
        out[#out + 1] = s:sub(start, pos - 1)
        if #out > LIMIT.KEYS then return nil end
    end
    return out
end

ns.Comm:Register("R", function(sender, proto, target, text)
    if not Proto(proto) then return end
    local keys = ReadKeys(text)
    if not keys then return ns.Log("Sync", "request from %s: malformed", sender) end
    if target ~= ns.PlayerKey() then
        for _, k in ipairs(keys) do Sync.asked[k] = ns.Now() end
        return
    end
    for _, k in ipairs(keys) do Sync:Offer(k, "asked by " .. sender) end
    ns.Log("Sync", "%s asked us for %d entries", sender, #keys)
end)

ns.Comm:Register("D", function(sender, proto, who, line, at, from, rank, max, name, text)
    if not Proto(proto) then return end
    line, at, rank, max = tonumber(line), tonumber(at), tonumber(rank), tonumber(max)
    who = ns.NormalizeName(who)
    local now = ns.Now()
    if not who or #who > LIMIT.WHO or not line or line < 1 or line > 1e6 or line ~= math.floor(line) or not at
        or at < ns.Config.SYNC_EPOCH or at > now + 300 or (from ~= "own" and from ~= "link")
        or type(name) ~= "string" or #name > LIMIT.NAME or name:find("|", 1, true) then
        return ns.Log("Sync", "data from %s: malformed", sender)
    end
    local set, n = Pack.ReadSet(text, LIMIT.RECIPES)
    if not set or n == 0 then return ns.Log("Sync", "data from %s: malformed recipes", sender) end
    local key = Sync.Key(who, line)
    if not Sync.heard[key] or Sync.heard[key].at <= at then Sync.heard[key] = { at = at, time = GetTime() } end
    if ns.Guild:IsMember(who) ~= true then return ns.Log("Sync", "data from %s about %s: not a member", sender, who) end
    local by = Sync:Entries()
    local mine = by[key]
    if mine and mine.who == who and (mine.p.at or 0) >= at then
        if mine.p.at > at then Sync:Offer(key, "theirs was older") end
        return
    end
    Sync.storing = true
    local status = ns.Recipes:Store({ guild = ns.GuildKey(), who = who, line = line, name = name, rank = rank, max = max,
        from = from, at = at, via = sender, recipes = set })
    Sync.storing = false
    ns.Log("Sync", "data from %s: %s line %d, %d recipes: %s", sender, who, line, n, tostring(status))
    if status then ns.Spells:Want(set, line, name) end
end)

ns.Comm:Register("K", function(sender, proto, who, at, text)
    if not Proto(proto) then return end
    at = tonumber(at)
    who = ns.NormalizeName(who)
    local lines = Sync.ReadLevels(text)
    if not who or #who > LIMIT.WHO or not at or at < ns.Config.SYNC_EPOCH or at > ns.Now() + 300 or not lines then
        return ns.Log("Sync", "skills from %s: malformed", sender)
    end
    local key = Sync.Key(who, 0)
    if not Sync.heard[key] or Sync.heard[key].at <= at then Sync.heard[key] = { at = at, time = GetTime() } end
    if ns.Guild:IsMember(who) ~= true then return ns.Log("Sync", "skills from %s about %s: not a member", sender, who) end
    local mine = Sync:Entries()[key]
    if mine and mine.who == who and mine.p.at >= at then
        if mine.p.at > at then Sync:Offer(key, "theirs was older") end
        return
    end
    -- (our own sheet is ours to read: a newer one about us from someone else is forged; answering it with ours
    -- would bounce between us, so it's let be)
    if who == ns.PlayerKey() then return ns.Log("Sync", "skills from %s about us: ignored", sender) end
    Sync.storing = true
    local status = ns.Skills:Store(ns.GuildKey(), who, lines, at, sender)
    Sync.storing = false
    ns.Log("Sync", "skills from %s: %s, %s", sender, who, tostring(status))
end)

------------------------------------------------------------------------------
-- When
------------------------------------------------------------------------------
ns.Start("settled", function()
    if not IsInGuild() then return end
    local cfg = ns.Config
    C_Timer.After(cfg.HELLO_DELAY + math.random() * cfg.HELLO_SPREAD, function() Sync:Hello() end)
end)

-- Something new we captured ourselves (a link, our own window): to everyone, without waiting for a hello.
ns.Bus:On("STORED", Sync, function(_, guild, who, line, status)
    if Sync.storing or status == "same" or guild ~= ns.GuildKey() then return end
    Sync:Offer(Sync.Key(who, line), "captured")
end)
