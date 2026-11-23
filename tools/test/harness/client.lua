-- A Client: one player's game, with its own global environment (BuildEnv, from env/*.lua), its own copy of
-- the addon and its SavedVariables (login, logout, reload), its events and frames, and the checks run after
-- every test (H.Invariants).
local H, P = ...
local ADDON, TOC, Load, CopyTable = P.ADDON, P.TOC, P.Load, P.CopyTable
local World = P.World

local Client = {}
Client.__index = Client
H.Client = Client

-- opts: trial (a Trial account: can't send addon messages), guild (false: not in the world's guild), profs ({ [line] = { recipe ids } }: your own), guid,
--   release (true: a packaged release: no Dev/ files, a release's version, so ns.DEV is false),
--   version (the TOC's Version), debug (false: debug log off), login (false: create offline),
--   saved (SavedVariables to start with: { ProffDB = {...} }),
--   patch (function(env, c): change the stub API before the addon loads, at every login)
function World:AddClient(name, opts)
    opts = opts or {}
    assert(not self.byName[name], "duplicate client " .. name)
    local first, surname = name:match("^(%S+)%s*(.*)$")
    local player = self:AddPlayer(name, { guild = opts.guild, profs = opts.profs, guid = opts.guid })
    local c = setmetatable({
        world = self, name = name, first = first, surname = surname, player = player,
        version = opts.version or (opts.release and "v1.0.0") or TOC.meta.Version, release = opts.release,
        saved = opts.saved and CopyTable(opts.saved) or {}, online = false, errors = {}, printed = {},
        patch = opts.patch, trial = opts.trial,
    }, Client)
    if opts.debug ~= false and not c.saved.ProffDebugDB then c.saved.ProffDebugDB = { enabled = true } end
    self.clients[#self.clients + 1] = c
    self.byName[name] = c
    if opts.login ~= false then c:Login() end
    return c
end

function Client:Fire(event, ...)
    if not self.online then return end
    for _, f in ipairs(self.frames) do
        if f.events[event] and f.scripts.OnEvent then f.scripts.OnEvent(f, event, ...) end
    end
end

-- Is any frame of ours registered for this event?
function Client:Listening(event)
    for _, f in ipairs(self.frames) do if f.events[event] then return true end end
    return false
end

local SAVED = { "ProffDB", "ProffDebugDB" }
H.ALLOWED_GLOBALS = { ProffDB = true, ProffDebugDB = true, SLASH_PROFF1 = true }

-- SavedVariables are written as Lua text: only plain data survives.
local function SaveCopy(v, path)
    local t = type(v)
    if t == "table" then
        local c = {}
        for k, x in pairs(v) do
            assert(type(k) == "string" or type(k) == "number" or type(k) == "boolean",
                "SavedVariables key of type " .. type(k) .. " at " .. path)
            c[k] = SaveCopy(x, path .. "." .. tostring(k))
        end
        return c
    end
    assert(t == "string" or t == "number" or t == "boolean", "SavedVariables can't hold a " .. t .. " at " .. path)
    return v
end

-- The stub client's API: env/*.lua, each `return function(c, env) ... end`.
local ENV_PARTS = { "core", "player", "guild", "tradeskill", "item", "ui", "comm" }
local parts = {}
for _, name in ipairs(ENV_PARTS) do parts[name] = assert(loadfile(P.dir .. "env/" .. name .. ".lua"))(H, P) end
function Client:BuildEnv()
    local env = P.NewEnv()
    for _, name in ipairs(ENV_PARTS) do parts[name](self, env) end
    if self.patch then self.patch(env, self) end
    return env
end

function Client:Login()
    assert(not self.online, self.name .. " is already online")
    self.online = true
    self.frames, self.missingGlobals, self.newGlobals = {}, {}, {}
    self.window, self.rosterCache = nil, nil
    local env = self:BuildEnv()
    self.env = env
    for _, k in ipairs(SAVED) do
        if self.saved[k] ~= nil then env[k] = CopyTable(self.saved[k]) end
    end
    -- From here on: reads of globals the stubs lack are recorded, new globals too (H.Invariants).
    local c = self
    setmetatable(env, {
        __index = function(_, k)
            c.missingGlobals[k] = true
            return nil
        end,
        __newindex = function(t, k, v)
            c.newGlobals[k] = true
            rawset(t, k, v)
        end,
    })
    local ns = {}
    self.ns = ns
    for _, path in ipairs(self.release and TOC.release or TOC.files) do
        local ok, err = pcall(Load, env, path, ADDON, ns)
        if not ok then self.errors[#self.errors + 1] = "loading " .. path .. ": " .. tostring(err) end
    end
    self.rosterCache = self.world:Roster() -- (the client has the roster it logged in with)
    self:Fire("ADDON_LOADED", ADDON)
    self:Fire("PLAYER_LOGIN")
    self:Fire("PLAYER_ENTERING_WORLD", true, false)
end

function Client:Logout()
    assert(self.online, self.name .. " is offline")
    if self.window then self:CloseProfession() end
    self:Fire("PLAYER_LOGOUT")
    for _, k in ipairs(SAVED) do
        local v = rawget(self.env, k)
        self.saved[k] = v ~= nil and SaveCopy(v, k) or nil
    end
    self.online = false
end

-- Logout and login, the SavedVariables kept; then past the settled phase.
function Client:Reload(settle)
    self:Logout()
    self:Login()
    if settle ~= false then self.world:Settle() end
end

-- The debug log, oldest line first.
function Client:Log()
    local db = self.env and rawget(self.env, "ProffDebugDB")
    local lines = db and db.lines
    if not lines then return {} end
    local out, size = {}, self.ns.Config and self.ns.Config.DEBUG_RING_SIZE or 4000
    local head = lines.head or 0
    for i = 1, size do
        local idx = ((head + i - 1) % size) + 1
        if lines[idx] then out[#out + 1] = lines[idx] end
    end
    return out
end

-- Log lines whose module and message match (plain text).
function Client:Logged(module, text)
    local n = 0
    for _, line in ipairs(self:Log()) do
        local _, _, m, msg = line:match("^([^\t]*)\t([^\t]*)\t([^\t]*)\t(.*)$")
        if m == module and (not text or msg:find(text, 1, true)) then n = n + 1 end
    end
    return n
end

-- Errors a test causes on purpose: taken, so the runner doesn't fail it.
function Client:TakeErrors()
    local e = self.errors
    self.errors = {}
    return e
end

-- What the runner checks after every test.
function H.Invariants(c)
    local out = {}
    for k in pairs(c.newGlobals or {}) do
        if not H.ALLOWED_GLOBALS[k] then out[#out + 1] = "wrote a stray global: " .. tostring(k) end
    end
    for _, line in ipairs(c.printed) do
        if line:find("{%w+}") then out[#out + 1] = "printed an unfilled placeholder: " .. line end
    end
    return out
end

-- The SavedVariables file the client writes (after a logout or reload): Lua text, for the tools' tests.
local function Serialize(v, indent)
    local t = type(v)
    if t == "string" then return ("%q"):format(v) end
    if t ~= "table" then return tostring(v) end
    local keys = {}
    for k in pairs(v) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b)
        if type(a) == type(b) then return a < b end
        return type(a) == "number"
    end)
    local out = { "{" }
    for _, k in ipairs(keys) do
        local key = type(k) == "string" and ("[%q]"):format(k) or ("[" .. tostring(k) .. "]")
        out[#out + 1] = indent .. "\t" .. key .. " = " .. Serialize(v[k], indent .. "\t") .. ","
    end
    out[#out + 1] = indent .. "}"
    return table.concat(out, "\n")
end
function Client:WriteSaved(path)
    local f = assert(io.open(path, "w"))
    for _, k in ipairs(SAVED) do
        if self.saved[k] ~= nil then f:write("\n", k, " = ", Serialize(self.saved[k], ""), "\n") end
    end
    f:close()
end
