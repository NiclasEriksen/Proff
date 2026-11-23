---@class Proff
local ns = select(2, ...)

-- The guild roster, read when we need it (at settled, and when a capture needs a membership answer), at
-- most once per Config.ROSTER_INTERVAL. GUILD_ROSTER_UPDATE is heard only while we wait for an answer: it
-- fires a lot in a busy guild.
--
--   Guild.members[key] = true   ("First Surname", as the roster names them; Forever's have no realm)
--   Guild.byGuid[guid] = key    (GetGuildRosterInfo's 17th value on retail; unverified on Forever: /proff
--                                probe roster logs it, and a GUID that doesn't look like one is ignored)
--   Guild.firsts[first] = key   (a first name only one member has; false when two share it)
--   Guild.complete              true only when as many rows were read as the server says the guild has.
-- Decisions that drop data (a member left) need a complete roster, so a half-loaded one can't delete anyone.
---@class Proff.Guild
local Guild = { members = {}, byGuid = {}, firsts = {}, complete = false, at = 0, key = nil }
ns.Guild = Guild

local waiting, timeoutAt

local function Read(stale)
    local total = ns.Read(GetNumGuildMembers) or 0
    local members, byGuid, firsts, read = {}, {}, {}, 0
    for i = 1, total do
        local name = ns.Read(GetGuildRosterInfo, i)
        local guid = ns.Plain((select(17, GetGuildRosterInfo(i))))
        local key = ns.NormalizeName(name)
        if key then
            members[key] = true
            read = read + 1
            if type(guid) == "string" and guid:find("^Player%-") then byGuid[guid] = key end
            local first = key:match("^(%S+)")
            if first then firsts[first] = firsts[first] == nil and key or false end
        end
    end
    Guild.members, Guild.byGuid, Guild.firsts = members, byGuid, firsts
    Guild.at, Guild.key = ns.Now(), ns.GuildKey()
    Guild.complete = not stale and total > 0 and read == total
    local guids = 0
    for _ in pairs(byGuid) do guids = guids + 1 end
    ns.Log("Guild", "roster: %d/%d rows%s, %d GUIDs", read, total, stale and " (stale)" or "", guids)
    ns.Bus:Fire("ROSTER", Guild.complete)
end

-- Ask the server for the roster (force: now, whatever the interval).
function Guild:Refresh(force)
    if not IsInGuild() or waiting then return end
    if not force and ns.Now() - self.at < ns.Config.ROSTER_INTERVAL then return end
    waiting = true
    local token = {}
    timeoutAt = token
    ns.Events:On("GUILD_ROSTER_UPDATE", Guild, function()
        ns.Events:Off("GUILD_ROSTER_UPDATE", Guild)
        waiting, timeoutAt = false, nil
        Read()
    end)
    C_GuildInfo.GuildRoster()
    -- The server may ignore a request (it's throttled): don't wait forever, read what the client has.
    C_Timer.After(ns.Config.ROSTER_TIMEOUT, function()
        if timeoutAt ~= token then return end
        ns.Events:Off("GUILD_ROSTER_UPDATE", Guild)
        waiting, timeoutAt = false, nil
        if (ns.Read(GetNumGuildMembers) or 0) > 0 then Read(true) end
    end)
end

-- A roster read once Config.ROSTER_INTERVAL has passed since the last: for a capture the last one couldn't
-- place (it came incomplete or stale). One at a time.
local soon
function Guild:Soon()
    if soon or not IsInGuild() then return end
    soon = true
    C_Timer.After(math.max(1, self.at + ns.Config.ROSTER_INTERVAL - ns.Now()), function()
        soon = false
        Guild:Refresh(true)
    end)
end

-- true / false, or nil when we don't know (no complete roster yet, or another guild's).
function Guild:IsMember(key)
    if not key then return nil end
    if self.key ~= ns.GuildKey() then return nil end
    if self.members[key] then return true end
    if self.complete then return false end
    return nil
end

-- Who a linked profession belongs to, from what the client gave us: the link's GUID, the name the window
-- has, GetPlayerInfoByGUID's name. Returns key, how ("guid", "name", "first") or nil. A roster member is
-- preferred over a name the roster doesn't have; a name not on the roster is still returned (how "outside")
-- so the caller can say who it was; a first name alone that two members share is "ambiguous".
function Guild:Resolve(names, guid)
    if guid and self.byGuid[guid] then return self.byGuid[guid], "guid" end
    local outside
    for _, n in ipairs(names) do
        local key = ns.NormalizeName(n)
        if key then
            if self.members[key] then return key, "name" end
            -- A first name alone (no surname: a client name without it) that only one member has.
            if not key:find(" ", 1, true) and self.firsts[key] ~= nil then
                if self.firsts[key] then return self.firsts[key], "first" end
                return key, "ambiguous"
            end
            outside = outside or key
        end
    end
    if outside then return outside, "outside" end
    return nil
end

ns.Start("settled", function() Guild:Refresh(true) end)
