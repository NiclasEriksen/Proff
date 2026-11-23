-- What a player does: the profession window (own, a clicked link's, an NPC's), slash commands, and what
-- they're told (c.printed).
local H, P = ...
local Client = H.Client

-- The window opens (or changes source, if open): TRADE_SKILL_SHOW for a new one, the data source's change,
-- and the list's updates in a burst, as the client sends them. run: seconds to run the world after (1).
function Client:OpenWindow(win, run)
    local was = self.window
    self.window = win
    win.changing = true
    -- (Blizzard_Professions loads with the first window: UIParent's TRADE_SKILL_SHOW handler, before ours,
    -- shows it)
    local pf = rawget(self.env, "ProfessionsFrame") or P.ProfessionsFrame(self)
    -- (from the overview, or a link: the profession's page)
    pf:UpdateTabs(win, false)
    if not was then
        pf:Show()
        self:Fire("TRADE_SKILL_SHOW")
    end
    self:Fire("TRADE_SKILL_DATA_SOURCE_CHANGING")
    local w = self.world
    w:After(0.1, function()
        if self.window ~= win then return end
        win.changing = false
        self:Fire("TRADE_SKILL_DATA_SOURCE_CHANGED")
        self:Fire("TRADE_SKILL_LIST_UPDATE")
    end, self)
    for _, at in ipairs({ 0.15, 0.2, 0.6 }) do
        w:After(at, function() if self.window == win then self:Fire("TRADE_SKILL_LIST_UPDATE") end end, self)
    end
    if run ~= false then w:Run(run or 1) end
end

-- Your own profession (one you know: c.player.profs).
function Client:OpenProfession(line, run)
    assert(self.player.profs[line], self.name .. " doesn't know " .. tostring(line))
    self:OpenWindow({ owner = self.player, line = line, kind = "own" }, run)
end

-- A trainer's or an NPC's crafting window: someone else's recipes that are nobody's.
function Client:OpenNPC(line, run)
    self:OpenWindow({ owner = { name = "Trainer", profs = { [line] = {} }, rank = 0, max = 0 }, line = line, kind = "npc" }, run)
end

-- The server's answer to a clicked link (env/core.lua's SetItemRef): that player's profession.
function Client:ShowLinked(guid, line)
    for _, p in pairs(self.world.players) do
        if p.guid == guid and p.profs[line] then
            return self:OpenWindow({ owner = p, line = line, kind = "linked" }, false)
        end
    end
end

-- The link a player put in chat, as the client builds it. Retail's: trade:<GUID>:<spell>:<skill line>.
function H.TradeLink(p, line)
    return ("trade:%s:%d:%d"):format(p.guid, H.PROFESSIONS[line].spell, line), "[" .. H.PROFESSIONS[line].name .. "]"
end

-- Click name's profession link in chat. opts.button ("shift": puts it in the chat line, opens nothing),
-- opts.run (seconds to run after; 1.5).
function Client:ClickLink(name, line, opts)
    opts = opts or {}
    local p = assert(self.world.players[name], "no player " .. name)
    local link, text = H.TradeLink(p, line)
    self.env.SetItemRef(link, text, opts.button or "LeftButton", self.env.DEFAULT_CHAT_FRAME)
    if opts.run ~= false then self.world:Run(opts.run or 1.5) end
end

function Client:CloseProfession()
    local pf = rawget(self.env, "ProfessionsFrame")
    if pf then pf:Hide() end
    if not self.window then return end
    self.window = nil
    self:Fire("TRADE_SKILL_CLOSE")
end

-- The profession window as Forever opens it (its key, the spellbook's button): the overview of every
-- profession, no profession open, no TRADE_SKILL_SHOW. Then c:OpenProfession(line) is a click on its tab.
function Client:OpenOverview()
    assert(not self.window, "a profession is open")
    local pf = rawget(self.env, "ProfessionsFrame") or P.ProfessionsFrame(self)
    pf:UpdateTabs(nil, true)
    pf:Show()
    self.world:Run(0.5)
end

-- The Guild tab, as the player sees it: c:GuildTab() (the tab button), c:GuildPage() (ns.GuildPage, built
-- once opened), c:OpenGuildTab() (clicks it, and runs the world a moment), c:Type("potion") (into the
-- search box), c:Shown() (the list's rows in view: "name | prof | who" each).
function Client:GuildTab() return rawget(self.env, "ProffGuildTab") end
function Client:OpenGuildTab()
    local tab = assert(self:GuildTab(), "no Guild tab")
    assert(tab:IsVisible(), "the Guild tab isn't shown")
    tab:Press()
    self.world:Run(0.5)
end
function Client:GuildPage() return self.ns.GuildPage end
function Client:Type(text)
    self.ns.GuildPage.box:SetText(text, true)
    self.world:Run(0.1)
end
function Client:Shown()
    local out = {}
    for _, row in ipairs(self.ns.GuildPage.rows) do
        if row:IsShown() and row.data then
            out[#out + 1] = row.name.text .. " | " .. row.prof.text .. " | " .. row.who.text
        end
    end
    return out
end

-- A slash command as typed: "/proff search potion" (or without the /proff: "search potion").
function Client:Slash(text)
    if not text:find("^/") then text = "/proff " .. text end
    local cmd, rest = text:match("^(/%S+)%s*(.-)$")
    for key, fn in pairs(self.env.SlashCmdList) do
        for i = 1, 9 do
            local alias = rawget(self.env, "SLASH_" .. key .. i)
            if not alias then break end
            if alias:lower() == cmd:lower() then return fn(rest) end
        end
    end
    error("no slash command " .. cmd)
end

-- Printed lines (colors and the "Proff:" tag left out) since a mark: c:Mark() then c:Said().
function Client:Mark() self.mark = #self.printed end
local function Plain(s) return (s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("^Proff: ", "")) end
function Client:Said(text)
    local out = {}
    for i = (self.mark or 0) + 1, #self.printed do
        local line = Plain(self.printed[i])
        if not text or line:find(text, 1, true) then out[#out + 1] = line end
    end
    return out
end
function Client:CountPrinted(text) return #self:Said(text) end

-- The store, as a search answers: who knows a recipe (by name), joined with ", "; nil for nobody.
function Client:Holders(recipeName)
    local rows = self.ns.Index:Search(self.ns.GuildKey(), recipeName, { limit = 1000 })
    for _, r in ipairs(rows) do
        if r.name == recipeName then return table.concat(r.holders, ", ") end
    end
end

-- The saved bucket of this client's guild (ProffDB.guilds[name]).
function Client:Bucket() return self.ns.DB:Guild(self.world.guildName) end
