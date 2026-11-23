-- Test harness: a simulated world with WoW clients, each running its own copy of the addon (Dyreparken's
-- tools/test/harness, smaller: Proff sends nothing, so there's no network).
--
--   local w = H.World()                       -- clock, timers, guild roster, other players
--   w:AddPlayer("Kari Berg", { profs = { [171] = { 2330, 2331 } } })        -- a guild member (not a client)
--   w:AddPlayer("Per Fremmed", { guild = false, profs = { [164] = { 2662 } } })  -- someone outside the guild
--   local ola = w:AddClient("Ola Nord", { profs = { [197] = { 2538 } } })   -- logs in
--   w:Settle()                                -- past the login's settled phase and its roster read
--   ola:ClickLink("Kari Berg", 171)           -- a profession link in chat, clicked: the linked window opens
--   ola:OpenProfession(197)                   -- your own profession window
--   ola:CloseProfession()
--   ola:Slash("search healing")               -- a slash command, as typed
--   H.eq(ola:Holders("Minor Healing Potion"), "Kari Berg")
--   ola:Reload()                              -- logout and login, SavedVariables kept
--
-- How the client answers (each a field of w.quirks, to test what Forever might do; docs/FOREVER_API.md):
--   linkedName = false     IsTradeSkillLinked() gives true but no name
--   noIsLinked = true      C_TradeSkillUI has no IsTradeSkillLinked
--   rosterGuid = false     GetGuildRosterInfo has no GUID (its 17th value)
--   guidName = "first"     GetPlayerInfoByGUID gives the first name only (false: nothing)
--   rosterIgnored = true   the server doesn't answer C_GuildInfo.GuildRoster (the timeout reads the cache)
--   rosterPartial = n      the cached roster has only its first n rows (GetNumGuildMembers still says all)
--   itemsCached = true     every item's name is known at once (else: after a load, ITEM_DATA_LOAD_RESULT)
--   itemsLost = true       an item load never answers
--   spellTooltip = false   GameTooltip:SetSpellByID shows nothing ("error": it throws)
--   noSkillRows = true     the guild profession roster's headers expand to no members
--   guildRecipes = false   the server's guild recipe system answers nothing (QueryGuildRecipes and friends)
--   trial = true           (a client's own: c.trial) can't send addon messages
--   noSideTabs = true      the profession window has no profession tabs (rightProfessionTabs)
--   missingTemplates = { name = true }   templates the client lacks (C_XMLUtil says so, CreateFrame throws)
--
-- Each client has its own global environment (setfenv): its files, SavedVariables and frames are separate.
-- `c.ns` is the addon namespace, `c.env` its globals. Stubs follow the real client: an unknown event or frame
-- method throws, reads of globals the stubs lack are recorded (c.missingGlobals; 01_core checks), and the
-- runner fails a test whose clients hit a Lua error or broke H.Invariants (a stray global, a {placeholder}).
--
-- Parts in tools/test/harness/, loaded in this order (each `local H, P = ...`):
--   base.lua      the TOC, Load (compiled once), NewEnv, known events, H.MISSING, the professions' data
--   frames.lua    frame and region stubs (CreateFrame), by widget type; templates throw when missing
--   blizzard.lua  Blizzard's templates, the profession window (Forever's ProfessionsFrame, its side tabs), H.Menu (a dropdown's)
--   world.lua     World: clock, timers, players and roster (H.World, H.Setup)
--   client.lua    Client: login, reload, SavedVariables, invariants; BuildEnv runs env/*.lua
--   ui.lua        the profession window, links, slash commands, what was printed
--   assert.lua    H.eq, H.ok, H.no, H.match
local H, P = {}, {}
P.dir = (debug.getinfo(1, "S").source:match("^@(.-)[^/]*$") or "") .. "harness/"
for _, part in ipairs({ "base", "frames", "blizzard", "world", "client", "ui", "assert" }) do
    assert(loadfile(P.dir .. part .. ".lua"))(H, P)
end
return H
