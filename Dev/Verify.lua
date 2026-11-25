---@class Proff
local ns = select(2, ...)

-- /proff probe verify: one checklist of what's still unconfirmed in game (Dyreparken's Dev/Verify.lua, smaller).
-- With it on, play as usual: each item ticks itself the first time its log line is written (Debug.tap sees
-- every line), a chat line says so, and the ticks are kept account-wide (ProffDebugDB.verify), so the list
-- only shrinks. `ok <id>` ticks one by hand. It stays on across logins until `off`.
-- Nothing here changes what the addon does: it only listens to the debug log (on while it runs).
---@class Proff.Verify
local Verify = {}
ns.Verify = Verify

-- id, what to do, and the module and pattern (or a test of the message) that ticks it.
Verify.ITEMS = {
    { "api:show", "open any profession window", "Capture", "^window shown" },
    { "api:learned", "open your own profession: its learned recipes read", "Capture", "^read .* line %d+: [1-9]%d* learned" },
    { "api:own", "open your own profession: IsTradeSkillLinked says false", "Capture", "^read .* linked false" },
    { "api:linkclick", "click a profession link in chat (SetItemRef sees it)", "Capture", "^link clicked" },
    { "api:linkguid", "a clicked profession link carries a GUID", "Capture", "^link clicked: .* %(guid Player%-" },
    { "api:linked", "a guildmate's linked window: IsTradeSkillLinked says true", "Capture", "^read .* linked true" },
    { "api:linkedname", "... and gives their name", "Capture", function(m)
        return m:find("^read ") and m:find("linked true (", 1, true) and not m:find("linked true (nil)", 1, true) end },
    { "api:linkedlearned", "a linked window lists their learned recipes", "Capture", "^read .*: [1-9]%d* learned, linked true" },
    { "api:rosterguid", "the guild roster gives GUIDs (GetGuildRosterInfo's 17th)", "Guild", "rows.*, [1-9]%d* GUIDs$" },
    { "api:rostercomplete", "a complete guild roster read", "Guild", function(m)
        local a, b = m:match("^roster: (%d+)/(%d+) rows,")
        return a ~= nil and a == b and a ~= "0" end },
    { "capture:byguid", "a linked profession placed by its GUID", "Capture", "^whose: .* by guid" },
    { "capture:byname", "a linked profession placed by name", "Capture", "^whose: .* by name" },
    { "capture:stored", "a guildmate's profession stored", "Recipes", function(m)
        return (m:find("^new ") or m:find("^changed ")) and true or false end },
    { "capture:same", "the same profession opened again: up to date", "Recipes", "^same " },
    { "capture:outside", "a non-member's link: not stored", "Capture", "member false" },
    { "capture:prune", "a member who left the guild pruned", "Recipes", "^pruned " },
    { "capture:reagents", "a profession's reagents read (GetRecipeSchematic)", "Capture", "^reagents of [1-9]%d* recipes read" },
    { "capture:itemnames", "the reagents' names came from the server", "Items", "^every name asked for came" },
    { "ui:tab", "open a profession: the Guild tab sits under the profession tabs", "Tab", "^layout: [1-9]%d* profession tabs, ours under" },
    { "ui:open", "click the Guild tab: the page opens", "Tab", "^opened" },
    { "ui:leave", "click a profession tab while it's open: back to that profession", "Tab", "^closed" },
    { "sync:sent", "a hello sent to the guild (addon messages work for this account)", "Comm", "^send H:" },
    { "sync:heard", "a hello heard from a guildmate running Proff", "Sync", "^hello from .*: %d+ entries" },
    { "sync:data", "a guildmate's relayed profession stored", "Sync", "^data from .*: [1-9]%d* recipes: %a+" },
    { "sync:names", "a relayed recipe named by the client (its spell)", "Spells", "^[1-9]%d* recipes named now" },
    { "members:rows", "open the Guild tab's Members view: the server lists members' professions and skills",
        "Skills", ": [1-9]%d* professions, [1-9]%d* member rows" },
    { "skills:own", "your own professions' levels read (secondaries too)", "Skills", "^own levels: %d+ " },
    { "sync:skills", "a guildmate's skill levels stored", "Sync", "^skills from .*: .*, %a+" },
    { "ui:tooltip", "hover a recipe in the Guild tab: its spell tooltip", "Page", "^tooltip: the spell's" },
    { "members:club", "open the Members view: every member's professions from the guild club, offline too", "Skills",
        "^club: [1-9]%d* members" },
    { "detail:icons", "click a member in the guild window: their profession icons on the detail panel", "Detail",
        "^shown: .*, [1-9]%d* professions" },
    { "detail:tooltip", "hover one of those icons", "Detail", "^tooltip: " },
}
Verify.BY = {}
for _, item in ipairs(Verify.ITEMS) do
    assert(not Verify.BY[item[1]], "Verify: two items " .. item[1])
    Verify.BY[item[1]] = item
end

local function Ticks()
    ProffDebugDB.verify = type(ProffDebugDB.verify) == "table" and ProffDebugDB.verify or {}
    return ProffDebugDB.verify
end

function Verify:Tick(id, detail)
    local ticks = Ticks()
    if ticks[id] then return false end
    ticks[id] = { at = ns.Now(), detail = detail }
    ns.Log("Verify", "ticked %s: %s", id, tostring(detail))
    ns.Print(("|cff7fd47fverified|r %s (%s)"):format(id, self.BY[id] and self.BY[id][2] or "?"))
    return true
end

local function Tap(module, msg)
    for _, item in ipairs(Verify.ITEMS) do
        if item[3] == module and not Ticks()[item[1]] then
            local test = item[4]
            local hit
            if type(test) == "function" then hit = test(msg) else hit = msg:find(test) ~= nil end
            if hit then Verify:Tick(item[1], msg:sub(1, 120)) end
        end
    end
end

function Verify:SetOn(on)
    ProffDebugDB.verifyOn = on or nil
    ns.Debug.tap = on and Tap or nil
    if on and not ns.Debug.enabled then ns.Debug:SetEnabled(true, ns.Debug.echo) end
end

function Verify:Status()
    local ticks, open = Ticks(), {}
    for _, item in ipairs(self.ITEMS) do
        if not ticks[item[1]] then open[#open + 1] = item end
    end
    return open, #self.ITEMS - #open
end

function Verify:Command(arg)
    local word, rest = (arg or ""):match("^(%S*)%s*(.-)$")
    if word == "off" then
        self:SetOn(false)
        return ns.Print("Verify off.")
    elseif word == "reset" then
        ProffDebugDB.verify = {}
        return ns.Print("Verify: every item open again.")
    elseif word == "ok" then
        if not self.BY[rest] then return ns.Print("Verify: no item \"" .. rest .. "\".") end
        self:Tick(rest, "by hand")
        return
    end
    self:SetOn(true)
    local open, done = self:Status()
    ns.Print(("Verify on: %d of %d confirmed. Still open:"):format(done, #self.ITEMS))
    for _, item in ipairs(open) do ns.Print(("  %s: %s"):format(item[1], item[2])) end
end

ns.Start("loaded", function() if ProffDebugDB.verifyOn then Verify:SetOn(true) end end)
