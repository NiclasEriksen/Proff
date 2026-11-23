---@class Proff
local ns = select(2, ...)

-- Reading recipes as they pass by. Nothing is asked of anyone and nothing is sent: when the profession window
-- shows a guild member's profession (their link, clicked in chat) or your own, its learned recipes are stored.
--
-- 1. A click on a profession link ("trade:<GUID>:<spell>:<skill line>" on retail; Forever's form is read
--    loosely, /proff probe link logs it) is remembered for Config.LINK_FRESH seconds: its GUID says whose.
-- 2. The window: TRADE_SKILL_SHOW starts a session, and only then are TRADE_SKILL_LIST_UPDATE, _DATA_SOURCE_
--    CHANGED and _CLOSE heard. The list comes in bursts, so it's read once it's quiet (Config.READ_DELAY), and
--    not while the data source is changing. An NPC's crafting window or the guild crafters view is skipped.
-- 3. Whose: C_TradeSkillUI.IsTradeSkillLinked() (true, name on retail) says linked or own. A linked one is
--    resolved against the roster (Guild:Resolve: the link's GUID, the window's name, GetPlayerInfoByGUID's).
--    A missing IsTradeSkillLinked falls back on a fresh link click.
-- 4. Only a guild member's is stored. Not knowing yet (no complete roster) holds the capture until the roster
--    comes (Config.HELD_MAX of them); a non-member's is dropped.
---@class Proff.Capture
---@field session table? the window open now: { said, link, read }
---@field pending table? the last profession link clicked: { guid, spell, line, raw, at }
local Capture = { session = nil, pending = nil, held = {} }
ns.Capture = Capture

local Plain = ns.Plain

---------------------------------------------------------------------------
-- The link
---------------------------------------------------------------------------

-- "trade:Player-6841-001BD719:2259:171" -> { guid, spell, line }. The GUID is found anywhere in the data, the
-- first two numbers after it are the spell and the skill line (retail's order); unknown forms give what they can.
function Capture.ParseLink(link)
    if type(link) ~= "string" then return nil end
    local body = link:match("^trade:(.*)$") or link:match("|Htrade:([^|]*)|h")
    if not body then return nil end
    local guid = body:match("(Player%-%d+%-%x+)")
    local rest = guid and body:sub((body:find(guid, 1, true)) + #guid) or body
    local nums = {}
    for n in rest:gmatch("%d+") do nums[#nums + 1] = tonumber(n) end
    return { guid = guid, spell = nums[1], line = nums[2], raw = body }
end

function Capture:OnLink(link)
    local parsed = self.ParseLink(link)
    if not parsed then return end
    parsed.at = GetTime()
    self.pending = parsed
    ns.Log("Capture", "link clicked: %s (guid %s, spell %s, line %s)", parsed.raw, tostring(parsed.guid),
        tostring(parsed.spell), tostring(parsed.line))
end

-- After the client's own SetItemRef (which opens the window): a hook, never a replacement.
hooksecurefunc("SetItemRef", function(link) Capture:OnLink(link) end)

---------------------------------------------------------------------------
-- The window
---------------------------------------------------------------------------

-- The profession shown: its skill line, name and level. Forever's child line says 0/0 while the base one has
-- the real level (AuctionDetonator's note), so the level comes from whichever has a cap.
function Capture:Profession(linkLine)
    local T = C_TradeSkillUI
    local base = ns.Read(T.GetBaseProfessionInfo)
    local child = ns.Read(T.GetChildProfessionInfo)
    base = type(base) == "table" and base or {}
    child = type(child) == "table" and child or {}
    local line = Plain(base.professionID) or Plain(child.parentProfessionID) or linkLine or Plain(child.professionID)
    local name = Plain(base.professionName) or Plain(child.parentProfessionName) or Plain(child.professionName)
    if type(line) ~= "number" or line <= 0 or type(name) ~= "string" then return nil end
    local rank, max
    for _, part in ipairs({ child, base }) do
        local m = Plain(part.maxSkillLevel)
        if type(m) == "number" and m > 0 and not max then rank, max = Plain(part.skillLevel), m end
    end
    return { line = line, name = name, rank = rank, max = max }
end

-- A recipe's reagents, { [itemID] = count }, from its schematic (static data: whoever's window it is). Every
-- slot with an item counts, the optional ones too (a search for an ingredient should find them).
function Capture.Reagents(id)
    local s = ns.Read(C_TradeSkillUI.GetRecipeSchematic, id, false)
    local slots = type(s) == "table" and Plain(s.reagentSlotSchematics)
    if type(slots) ~= "table" then return nil end
    local out = {}
    for _, slot in ipairs(slots) do
        local reagents = type(slot) == "table" and Plain(slot.reagents)
        local first = type(reagents) == "table" and Plain(reagents[1])
        local item = type(first) == "table" and Plain(first.itemID)
        local count = type(slot) == "table" and Plain(slot.quantityRequired)
        if type(item) == "number" then out[item] = type(count) == "number" and count or 1 end
    end
    return out
end

-- The learned recipes in the window, and what each is called. Reagents only for a recipe whose aren't known.
function Capture:Learned()
    local T = C_TradeSkillUI
    local ids = ns.Read(T.GetAllRecipeIDs)
    local set, info, n = {}, {}, 0
    if type(ids) ~= "table" then return set, info, 0 end
    local known = ns.DB:Recipes()
    for _, id in ipairs(ids) do
        id = Plain(id)
        local r = type(id) == "number" and ns.Read(T.GetRecipeInfo, id)
        if type(r) == "table" and Plain(r.learned) == true then
            set[id] = true
            n = n + 1
            info[id] = { n = Plain(r.name), i = Plain(r.icon), c = Plain(r.categoryID),
                r = not (known[id] and known[id].r) and self.Reagents(id) or nil }
        end
    end
    return set, info, n
end

function Capture:Read()
    local T = C_TradeSkillUI
    local s = self.session
    if not (T and s) then return end
    if ns.Yes(T.IsDataSourceChanging) then return ns.Log("Capture", "data source changing: later") end
    if ns.Yes(T.IsNPCCrafting) then return ns.Log("Capture", "an NPC's crafting: skipped") end
    if ns.Yes(T.IsTradeSkillGuild) then return ns.Log("Capture", "guild crafters view: skipped") end
    -- A link clicked just now explains this window (and a new data source in an open one).
    if self.pending and GetTime() - self.pending.at <= ns.Config.LINK_FRESH then
        s.link, self.pending = self.pending, nil
    end
    local linked, linkedName
    if type(T.IsTradeSkillLinked) == "function" then
        linked, linkedName = ns.Read(T.IsTradeSkillLinked)
        linked = linked == true or (type(linked) == "number" and linked ~= 0)
    else
        linked = s.link ~= nil
    end
    local prof = self:Profession(s.link and s.link.line)
    if not prof then return ns.Log("Capture", "no profession read") end
    local recipes, info, n = self:Learned()
    -- The list's later updates in a burst read the same again: once is enough.
    local sig = prof.line .. ":" .. n .. ":" .. tostring(linkedName) .. ":" .. tostring(s.link and s.link.guid)
    for id in pairs(recipes) do sig = sig .. "," .. id end
    if s.read == sig then return end
    s.read = sig
    ns.Log("Capture", "read %s line %d: %d learned, linked %s (%s)", prof.name, prof.line, n, tostring(linked),
        tostring(linkedName))
    local snap = { line = prof.line, name = prof.name, rank = prof.rank, max = prof.max, recipes = recipes, info = info }
    if linked then
        snap.from = "link"
        snap.guid = s.link and s.link.guid
        snap.names = { linkedName }
        if snap.guid then
            local _, _, _, _, _, gname = ns.Read(GetPlayerInfoByGUID, snap.guid)
            snap.names[#snap.names + 1] = gname
        end
    else
        snap.from, snap.who, snap.guid = "own", ns.PlayerKey(), Plain(UnitGUID("player"))
    end
    self:Admit(snap)
end

---------------------------------------------------------------------------
-- Whose, and storing it
---------------------------------------------------------------------------

-- Once per window session, who and profession: what the player is told.
function Capture:Say(snap, key, vars)
    local s = self.session
    -- (the wait for a roster, then what came of it: two things to say)
    local id = (key == "held" and "held\t" or "") .. tostring(snap.who or (snap.names and snap.names[1])) .. "\t" .. snap.line
    if s then
        if s.said[id] then return end
        s.said[id] = true
    end
    ns.Print(ns.T(key, vars))
end

-- Returns what happened: "stored", "same", "held", "outside", "unknown", "noguild", or a store's refusal.
function Capture:Admit(snap)
    local guild = ns.GuildKey()
    if not guild then
        if snap.from == "link" then self:Say(snap, "skip.noguild") end
        return "noguild"
    end
    snap.guild = guild
    local member
    if snap.from == "own" then
        member = snap.who ~= nil
    else
        local who, how = ns.Guild:Resolve(snap.names or {}, snap.guid)
        snap.who = who
        if how == "ambiguous" then
            self:Say(snap, "skip.unknown")
            ns.Log("Capture", "whose? %s: two members have that first name", tostring(who))
            return "unknown"
        end
        if not who then
            -- Nobody yet: the roster may not have been read. Held for it, as a name it couldn't place is.
            if ns.Guild.complete then
                self:Say(snap, "skip.unknown")
                ns.Log("Capture", "whose? names %s, guid %s", table.concat(snap.names or {}, "/"), tostring(snap.guid))
                return "unknown"
            end
            return self:Hold(snap)
        end
        member = ns.Guild:IsMember(who)
        ns.Log("Capture", "whose: %s by %s, member %s", who, how, tostring(member))
    end
    if member == nil then return self:Hold(snap) end
    if member == false then
        self:Say(snap, "skip.notmember", { who = snap.who })
        return "outside"
    end
    local status, n = ns.Recipes:Store(snap)
    if not status then
        ns.Log("Capture", "not stored: %s", tostring(n))
        return n
    end
    local items, read = {}, 0
    for _, r in pairs(snap.info or {}) do
        if r.r then read = read + 1; for item in pairs(r.r) do items[item] = true end end
    end
    if read > 0 then
        ns.Log("Capture", "reagents of %d recipes read", read)
        ns.Items:Want(items, true)
    end
    local vars = { n = n, prof = snap.name, who = snap.who }
    if snap.from == "link" then
        self:Say(snap, status == "same" and "stored.same" or "stored.linked", vars)
    elseif status == "new" then
        self:Say(snap, "stored.own", vars)
    end
    return status == "same" and "same" or "stored"
end

-- A capture whose membership isn't known yet, until the next roster. The newest per who and line.
function Capture:Hold(snap)
    local id = table.concat(snap.names or {}, "/") .. "\t" .. tostring(snap.guid) .. "\t" .. snap.line
    for i, h in ipairs(self.held) do
        if h.id == id then table.remove(self.held, i); break end
    end
    if #self.held >= ns.Config.HELD_MAX then table.remove(self.held, 1) end
    local again = snap.id ~= nil -- (back from a roster that couldn't answer)
    snap.id = id
    self.held[#self.held + 1] = snap
    ns.Log("Capture", "held %s line %d for the roster%s", (id:gsub("\t", " ")), snap.line, again and " (again)" or "")
    if again then
        ns.Guild:Soon() -- (not at once: a roster that came incomplete would come so again, request after request)
    else
        self:Say(snap, "held", { who = snap.who or (snap.names and snap.names[1]) or "?", prof = snap.name })
        ns.Guild:Refresh(true)
    end
    return "held"
end

ns.Bus:On("ROSTER", Capture, function(_, complete)
    if #Capture.held == 0 then return end
    local list = Capture.held
    Capture.held = {}
    for _, snap in ipairs(list) do
        if snap.from ~= "own" then snap.who = nil end
        Capture:Admit(snap) -- (a roster that can't answer puts it back in held, for the next one)
    end
end)

---------------------------------------------------------------------------
-- Events: only TRADE_SKILL_SHOW always; the rest while the window is open.
---------------------------------------------------------------------------
local ReadSoon = ns.Debounce(ns.Config.READ_DELAY, function() Capture:Read() end)

local function OnList() if Capture.session then ReadSoon() end end
local function OnSource()
    if not Capture.session then return end
    Capture.session.said = {} -- (someone else's now: what's said is new again)
    ReadSoon()
end
local function OnClose()
    Capture.session = nil
    ns.Events:Off("TRADE_SKILL_LIST_UPDATE", Capture)
    ns.Events:Off("TRADE_SKILL_DATA_SOURCE_CHANGED", Capture)
    ns.Events:Off("TRADE_SKILL_CLOSE", Capture)
    ns.Log("Capture", "window closed")
end
local function OnShow()
    Capture.session = Capture.session or { said = {} }
    ns.Events:On("TRADE_SKILL_LIST_UPDATE", Capture, OnList)
    ns.Events:On("TRADE_SKILL_DATA_SOURCE_CHANGED", Capture, OnSource)
    ns.Events:On("TRADE_SKILL_CLOSE", Capture, OnClose)
    ns.Log("Capture", "window shown")
    ReadSoon()
end

ns.Start("login", function()
    if not C_TradeSkillUI then return ns.Log("Capture", "no C_TradeSkillUI: nothing to read") end
    ns.Events:On("TRADE_SKILL_SHOW", Capture, OnShow)
end)
