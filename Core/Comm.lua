---@class Proff
local ns = select(2, ...)

-- Addon messages between guild members (Dyreparken's Core/Comm.lua, smaller: no libraries, text only).
-- Silent: nothing is ever printed; what happens goes to the debug log ("Comm").
--
-- A message is one kind letter and its fields: "H\t1\t<fields>" (tabs between), built from Core/Pack.lua's text,
-- so it needs no serializer. It goes out in chunks of at most 255 bytes, each led by one byte: "S" a whole
-- message, "F" first, "M" middle, "L" last. Chunks from one sender arrive in order (one channel), so the
-- receiver joins them per sender; everything we send goes through one queue, so two messages never interleave.
--
-- Forever (Dyreparken's docs/FOREVER_API.md, "Addon messages"):
--  * 255 bytes a message, any byte but \0; a prefix up to 16 characters.
--  * The server's throttle: 10 messages per prefix, +1 a second; over it, dropped (code 3). Too much traffic
--    across prefixes can disconnect. Our own outbox paces far under it (Config.COMM_BURST, COMM_RATE).
--  * Trial and Veteran accounts can't send at all (they still receive): a refusal that isn't a throttle stops
--    our sending for the session, so they don't retry forever.
--  * Whispers to "First Surname" are unverified (Dyreparken): GUILD only, for everything.
--  * The sender arrives as "First Surname"; our own GUILD messages come back to us.
--  * Anyone can send anything on our prefix: a message is dropped unless it's from a member of our guild on
--    the roster (not ourselves), on GUILD, whole, of a kind someone registered, and within the size limits. One
--    from a sender not on our roster yet (joined since we read it) waits for the next roster (Comm.held).
--    Handlers still check every field (Pack's readers return nil for anything malformed).
--
-- CHAT_MSG_ADDON fires for every addon's messages: it's heard only while we're in a guild, and our prefix is
-- the first thing checked.
---@class Proff.Comm
---@field mute string? why we stopped sending this session (a Trial account's refusal)
local Comm = { handlers = {}, partial = {}, ignored = {}, outbox = {}, held = {}, sent = 0, received = 0 }
ns.Comm = Comm

local CHUNK = 254 -- 255 minus the header byte
Comm.MAX_PARTS = 8 -- chunks in one message, both ways (2 KB)
Comm.RETRIES = 10  -- a throttled chunk's tries before its message is given up

------------------------------------------------------------------------------
-- Sending
------------------------------------------------------------------------------
local tokens, stamp, waiting = nil, nil, false

local function Codes() return type(Enum) == "table" and Enum.SendAddonMessageResult or {} end
local function Busy(r)
    local c = Codes()
    return r == c.AddonMessageThrottle or r == c.ChannelThrottle or r == c.AddOnMessageLockdown
end

local Drain
local function Later(delay)
    if waiting then return end
    waiting = true
    C_Timer.After(delay, function()
        waiting = false
        Drain()
    end)
end

-- Sends what the bucket allows, the rest after a refill. Idle (no timer) with nothing to send.
function Drain()
    local now = GetTime()
    local burst, rate = ns.Config.COMM_BURST, ns.Config.COMM_RATE
    tokens = math.min(burst, (tokens or burst) + (now - (stamp or now)) * rate)
    stamp = now
    local box = Comm.outbox
    while box[1] and tokens >= 1 - 1e-6 do
        local c = box[1]
        -- A message whose check now says no (someone else sent the same meanwhile): gone, whole, before its first
        -- chunk leaves. (A check isn't asked again for its later chunks.)
        while c and c.check and c.first and not c.check() do
            local msg = c.msg
            while box[1] and box[1].msg == msg do table.remove(box, 1) end
            ns.Log("Comm", "dropped %s before sending: no longer needed", c.kind)
            c = box[1]
        end
        if not c then break end
        tokens = tokens - 1
        local ok, r = pcall(C_ChatInfo.SendAddonMessage, ns.Config.COMM_PREFIX, c.text, "GUILD")
        if ok and Busy(r) and (c.tries or 0) < Comm.RETRIES then
            c.tries = (c.tries or 0) + 1
            tokens = 0
            ns.Log("Comm", "busy (code %s): waiting", tostring(r))
            break
        end
        table.remove(box, 1)
        local codes = Codes()
        if not ok or (r ~= nil and r ~= true and r ~= codes.Success) then
            -- The rest of this message can't be put together by anyone: gone too. A refusal other than a throttle
            -- (a Trial account; not in a guild) ends sending for the session.
            while box[1] and box[1].msg == c.msg do table.remove(box, 1) end
            if not Busy(r) then
                Comm.mute = ok and ("code " .. tostring(r)) or tostring(r)
                Comm.outbox = {}
                box = Comm.outbox
            end
            ns.Log("Comm", "gave up %s: %s", c.kind, ok and ("code " .. tostring(r)) or tostring(r))
        end
    end
    if box[1] then Later(math.max(0.1, (1 - tokens) / rate)) end
end

-- A message to the guild: kind (one capital letter) and its fields (strings without tabs). false when it
-- can't go (not in a guild, sending stopped, too big).
function Comm:Send(kind, ...)
    return self:SendIf(nil, kind, ...)
end

-- The same, with check(): asked just before the message goes; false drops it (a reply someone beat us to).
function Comm:SendIf(check, kind, ...)
    if self.mute or not IsInGuild() then return false end
    local fields = { kind, ... }
    for i = 2, #fields do
        local f = tostring(fields[i])
        if f:find("[\t%z]") then error("Comm:Send: a field holds a tab or \\0") end
        fields[i] = f
    end
    local text = table.concat(fields, "\t")
    local parts = math.ceil(#text / CHUNK)
    if parts > self.MAX_PARTS then
        ns.Log("Comm", "not sent %s: %d bytes, over %d parts", kind, #text, self.MAX_PARTS)
        return false
    end
    self.sent = self.sent + 1
    local msg = self.sent
    for i = 1, parts do
        local head = parts == 1 and "S" or (i == 1 and "F" or (i == parts and "L" or "M"))
        self.outbox[#self.outbox + 1] = { text = head .. text:sub((i - 1) * CHUNK + 1, i * CHUNK), kind = kind, msg = msg,
            check = check, first = i == 1 }
    end
    ns.Log("Comm", "send %s: %d bytes, %d part%s", kind, #text, parts, parts == 1 and "" or "s")
    if not waiting then Drain() end
    return true
end

------------------------------------------------------------------------------
-- Receiving
------------------------------------------------------------------------------
-- fn(sender, field, field, ...) for messages of this kind.
function Comm:Register(kind, fn)
    assert(type(kind) == "string" and kind:match("^%u$"), "Comm:Register: a kind is one capital letter")
    self.handlers[kind] = fn
end

local function Deliver(sender, text)
    -- A sender not on our roster may have joined since we read it: held (the newest Config.COMM_HELD) until the
    -- next roster, asked for at the soonest it may be (Guild:Soon); then let in or dropped.
    if ns.Guild:IsMember(sender) ~= true then
        local held = Comm.held
        if #held >= ns.Config.COMM_HELD then table.remove(held, 1) end
        held[#held + 1] = { sender, text }
        ns.Guild:Soon()
        return ns.Log("Comm", "held a message from %s: not on our roster (yet?)", sender)
    end
    local fields = {}
    for f in (text .. "\t"):gmatch("([^\t]*)\t") do fields[#fields + 1] = f end
    local kind = table.remove(fields, 1)
    local fn = Comm.handlers[kind]
    if not fn then return ns.Log("Comm", "unknown kind %q from %s", tostring(kind):sub(1, 8), sender) end
    Comm.received = Comm.received + 1
    local ok, err = pcall(fn, sender, unpack(fields))
    if not ok then ns.Log("Comm", "handler %s failed on %s's message: %s", kind, sender, tostring(err)) end
end

function Comm:OnMessage(prefix, text, channel, sender)
    if prefix ~= ns.Config.COMM_PREFIX then return end
    sender = ns.NormalizeName(ns.Plain(sender))
    if channel ~= "GUILD" or not sender or type(text) ~= "string" then return end
    if sender == ns.PlayerKey() or self.ignored[sender] then return end
    local head, body = text:sub(1, 1), text:sub(2)
    local p = self.partial[sender]
    if head == "S" then
        self.partial[sender] = nil
        return Deliver(sender, body)
    elseif head == "F" then
        self.partial[sender] = { body }
    elseif (head == "M" or head == "L") and p then
        p[#p + 1] = body
        if #p > self.MAX_PARTS then
            self.partial[sender] = nil
            self.ignored[sender] = true
            return ns.Log("Comm", "ignoring %s this session: a message over %d parts", sender, self.MAX_PARTS)
        end
        if head == "L" then
            self.partial[sender] = nil
            return Deliver(sender, table.concat(p))
        end
    else
        ns.Log("Comm", "dropped a stray chunk %q from %s", head, sender)
    end
end

-- A roster came: the held messages of members go through, the rest are dropped.
ns.Bus:On("ROSTER", Comm, function()
    if #Comm.held == 0 then return end
    local held = Comm.held
    Comm.held = {}
    for _, h in ipairs(held) do
        if ns.Guild:IsMember(h[1]) == true then
            Deliver(h[1], h[2])
        else
            ns.Log("Comm", "dropped: %s isn't on our roster", h[1])
        end
    end
end)

-- Heard only while in a guild: CHAT_MSG_ADDON is every addon's traffic.
function Comm:Update()
    local inGuild = IsInGuild()
    if inGuild and not ns.Events:Listening("CHAT_MSG_ADDON", Comm) then
        if not self.registered then
            self.registered = ns.Read(C_ChatInfo.RegisterAddonMessagePrefix, ns.Config.COMM_PREFIX) ~= nil
        end
        ns.Events:On("CHAT_MSG_ADDON", Comm, function(_, _, ...) Comm:OnMessage(...) end)
        ns.Log("Comm", "listening (prefix %s)", ns.Config.COMM_PREFIX)
    elseif not inGuild and ns.Events:Listening("CHAT_MSG_ADDON", Comm) then
        ns.Events:Off("CHAT_MSG_ADDON", Comm)
        self.partial = {}
        ns.Log("Comm", "not in a guild: not listening")
    end
end

ns.Start("login", function()
    if type(C_ChatInfo) ~= "table" then return ns.Log("Comm", "no C_ChatInfo: no sync") end
    Comm:Update()
    ns.Events:On("PLAYER_GUILD_UPDATE", Comm, function() Comm:Update() end)
end)
