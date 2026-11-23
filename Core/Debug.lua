---@class Proff
local ns = select(2, ...)

-- Debug log (Dyreparken's Core/Debug.lua, smaller). With debug on, lines go to a capped ring buffer in
-- ProffDebugDB, which the client writes to WTF/Account/<ACCOUNT>/SavedVariables/Proff.lua on /reload or
-- logout. Each line is one tab-separated string, "<serverTime>\t<GetTime>\t<module>\t<message>"
-- (tools/log.lua reads it). With debug off, ns.Log is a no-op that doesn't even format its arguments.
-- A line like the one before it adds " (xN)" instead of a new line; a muted module logs nothing; every
-- login starts with a "Session" line, where tools/log.lua splits the log. Only a git checkout logs.
---@class Proff.Debug
---@field tap fun(module: string, msg: string)? Dev/Verify.lua: every line written (a release leaves it nil)
local Debug = { enabled = false }
ns.Debug = Debug

local buf -- ProffDebugDB.lines
local mute = {} -- ProffDebugDB.mute: module -> true
local last, again, first

local function noop() end

local tapping
local function Write(module, fmt, ...)
    module = tostring(module)
    local tap = not tapping and Debug.tap
    if mute[module] and not tap then return end
    local ok, msg = pcall(string.format, fmt, ...)
    if not ok then msg = tostring(fmt) end
    if not mute[module] then
        local key = module .. "\t" .. msg
        if key == last and buf[buf.head] then
            again = again + 1
            buf[buf.head] = first .. " (x" .. again .. ")"
        else
            last, again = key, 1
            first = ns.Now() .. "\t" .. string.format("%.3f", GetTime()) .. "\t" .. key
            local i = (buf.head % ns.Config.DEBUG_RING_SIZE) + 1
            buf.head = i
            buf[i] = first
            if Debug.echo then DEFAULT_CHAT_FRAME:AddMessage("|cffe0b050Proff:|r |cff999999[" .. module .. "]|r " .. msg) end
        end
    end
    -- Dev/Verify.lua's checklist reads every line, after it's written, protected: a probe's error mustn't
    -- raise in whoever logged.
    if tap then
        tapping = true
        local fine, err = pcall(tap, module, msg)
        if not fine then Write("Debug", "tap failed on %s: %s", module, tostring(err)) end
        tapping = false
    end
end

-- module muted (true), heard again (false), or nil to list them.
function Debug:Mute(module, on)
    if module ~= nil then
        mute[module] = on and true or nil
        ProffDebugDB.mute = mute
    end
    local list = {}
    for m in pairs(mute) do list[#list + 1] = m end
    table.sort(list)
    return list
end

-- Where a session starts in the log: who, which build.
function Debug:Session()
    if not self.enabled then return end
    local version, build, _, interface = ns.Read(GetBuildInfo)
    ns.Log("Session", "start %s, %s, client %s (%s, %s), guild %s", tostring(ns.VERSION), tostring(ns.PlayerKey()),
        tostring(version), tostring(build), tostring(interface), tostring(ns.GuildKey()))
end

function Debug:Init()
    -- A release keeps nothing of a log: a log left from a checkout would be read and written at every login.
    if not ns.DEV then ProffDebugDB = nil end
    ProffDebugDB = ProffDebugDB or {}
    local db = ProffDebugDB
    db.lines = db.lines or { head = 0 }
    buf = db.lines
    mute = type(db.mute) == "table" and db.mute or {}
    last = nil
    self:SetEnabled(ns.DEV and db.enabled, db.echo, true)
end

function Debug:SetEnabled(on, echo, starting)
    local was = self.enabled
    self.enabled, self.echo = not not on, not not echo
    ProffDebugDB.enabled, ProffDebugDB.echo = self.enabled, self.echo
    ns.Log = self.enabled and Write or noop
    if starting or (self.enabled and not was) then self:Session() end
    ns.Log("Debug", "enabled %s, echo=%s", ns.VERSION, tostring(self.echo))
    ns.Bus:Fire("DEBUG", self.enabled)
end

function Debug:Clear()
    ProffDebugDB.lines = { head = 0 }
    buf = ProffDebugDB.lines
    last = nil
end

ns.Start("loaded", function() Debug:Init() end) -- (first: everything after may log)
