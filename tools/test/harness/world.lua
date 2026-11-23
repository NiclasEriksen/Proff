-- World: the shared clock (w.t, GetTime; w:ServerTime()), timers (C_Timer.After), the guild and its roster,
-- and the other players (w:AddPlayer: their GUIDs and professions, for links). Clients are added with
-- w:AddClient (client.lua).
local H, P = ...

local World = {}
World.__index = World
P.World = World
H.START = 1795000000 -- server time at t = 0 (2026-11-18)
World.STEP = 0.05
World.ROSTER_LATENCY = 0.5
-- World:Settle: past Main.SETTLE (5 s) and the roster's answer.
World.SETTLE = 7

function H.World(opts)
    opts = opts or {}
    local w = setmetatable({ t = 0, timers = {}, clients = {}, byName = {}, players = {}, order = {},
        guildName = opts.guild or "Proffene", quirks = {}, nextGuid = 0x100, wire = {} }, World)
    H.worlds[#H.worlds + 1] = w
    return w
end
H.worlds = {}

function World:ServerTime() return H.START + math.floor(self.t) end

function World:After(delay, fn, owner)
    self.timers[#self.timers + 1] = { at = self.t + math.max(delay, 0), fn = fn, owner = owner }
end

-- Advance time: due timers run in order (a timer of a client that's gone offline doesn't).
function World:Run(seconds)
    local stop = self.t + (seconds or 0)
    repeat
        local due
        repeat
            due = nil
            for i, tm in ipairs(self.timers) do
                if tm.at <= self.t and (not due or tm.at < self.timers[due].at) then due = i end
            end
            if due then
                local tm = table.remove(self.timers, due)
                if not tm.owner or tm.owner.online then tm.fn() end
            end
        until not due
        if self.t >= stop then break end
        self.t = math.min(stop, self.t + self.STEP)
    until false
end

function World:Settle() self:Run(self.SETTLE) end

local Player = {}
Player.__index = Player
H.Player = Player
function Player:Learn(line, ids)
    assert(H.PROFESSIONS[line], "no such profession in the stub: " .. tostring(line))
    self.profs[line] = self.profs[line] or {}
    for _, id in ipairs(ids) do
        assert(H.PROFESSIONS[line].recipes[id], "no recipe " .. id .. " in " .. line)
        self.profs[line][id] = true
    end
end
function Player:Unlearn(line, id) if self.profs[line] then self.profs[line][id] = nil end end

-- A player in the world: name "First Surname"; opts.guild (default true: in the world's guild), opts.guid,
-- opts.profs ({ [skill line] = { recipe ids learned } }), opts.rank / opts.max (skill).
function World:AddPlayer(name, opts)
    opts = opts or {}
    assert(not self.players[name], "duplicate player " .. name)
    self.nextGuid = self.nextGuid + 1
    local p = setmetatable({ name = name, guid = opts.guid or ("Player-6841-%08X"):format(self.nextGuid),
        guild = opts.guild ~= false, profs = {}, rank = opts.rank or 150, max = opts.max or 225, skills = opts.skills }, Player)
    for line, ids in pairs(opts.profs or {}) do p:Learn(line, ids) end
    self.players[name] = p
    self.order[#self.order + 1] = name
    return p
end

-- The world's guild roster, in the order players joined.
function World:Roster()
    local rows = {}
    for _, name in ipairs(self.order) do
        local p = self.players[name]
        if p.guild then rows[#rows + 1] = p end
    end
    return rows
end

function World:Leave(name) self.players[name].guild = false end
function World:Join(name) self.players[name].guild = true end

-- A world with clients named in order and settled: H.Setup{ "Ola Nord", "Kari Berg" } or with options
-- ({ name, opts }). Returns the world, then each client.
function H.Setup(list)
    local w = H.World()
    local clients = {}
    for _, e in ipairs(list or { "Ola Nord" }) do
        local name, opts = e, nil
        if type(e) == "table" then name, opts = e[1], e[2] end
        clients[#clients + 1] = w:AddClient(name, opts)
    end
    w:Settle()
    return w, unpack(clients)
end

-- Addon messages (env/comm.lua) sent since a mark: the decoded kind letter of each whole message or first chunk,
-- optionally from one client. A message from someone who isn't a client (an outsider, a forger): w:Inject.
function World:Mark() return #self.wire end
function World:Sent(kind, from, since)
    local n = 0
    for i = (since or 0) + 1, #self.wire do
        local m = self.wire[i]
        local head, k = m.text:sub(1, 1), m.text:sub(2, 2)
        if (head == "S" or head == "F") and (not kind or k == kind) and (not from or m.from == from) then n = n + 1 end
    end
    return n
end
function World:Inject(sender, text, prefix, chan)
    self:After(0.1, function()
        for _, r in ipairs(self.clients) do
            if r.online and r.player.guild and r.prefixes[prefix or "Proff"] then
                r:Fire("CHAT_MSG_ADDON", prefix or "Proff", text, chan or "GUILD", sender, r.name, 0, 0, "", 0)
            end
        end
    end)
end
