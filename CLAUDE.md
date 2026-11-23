# Proff

A guild addon for **World of Warcraft: Forever** (interface 16001, client 1.60.1, Mainline engine, **Lua 5.1**): a
database of the guild's recipes, filled passively. When the profession window shows a guild member's profession
(their link, clicked in chat) or your own, its learned recipes are stored; a search tells who knows what. Only guild
members' recipes are kept. Its tooling and conventions follow Dyreparken (`../Dyreparken`, CLAUDE.md there).

**Before writing WoW API code, read `docs/FOREVER_API.md`** (and through it Dyreparken's, the client's reference):
names with surnames, secret values, missing APIs, what's known and still assumed about the profession window. When
you learn something new about the client, add it there with the date and build.

## Status

- Round one (2026-11-23): reading and storing recipes, the search index, `/proff search|who|stats|forget`, probes,
  tests, CI. Nothing in the profession window yet.
- Round two (2026-11-23): the profession window's "Guild" tab (UI/): a search box (recipe, crafter or
  ingredient), a profession filter, a help icon, a dense list with icons and the recipe's spell tooltip.
  Reagents are stored per recipe (schema 2) and their names learned (Core/Items.lua) for ingredient search.
  Not seen in game yet: `/proff probe verify`'s `ui:*` items and `probe window`'s `frame` say how it sits.

## Working rules

- **Ask before guessing** on anything vague or open to interpretation; don't silently pick.
- **Performance first.** Dormant day to day: no OnUpdate, no polling. Only `TRADE_SKILL_SHOW` is always registered;
  the window's other events while it's open, `GUILD_ROSTER_UPDATE` only while a roster is asked for,
  `ITEM_DATA_LOAD_RESULT` only while reagent names are on their way, `CHAT_MSG_ADDON` only while in a guild
  (every addon's traffic: our prefix is checked first), `PLAYER_GUILD_UPDATE` always (rare). The search index is built on demand, the
  first search after a change; the Guild tab is built the first time it opens, refreshed only while shown, and
  its list is virtual (rows for what's in view).
- Never call protected functions in combat. Hook Blizzard UI, never replace it. Never change the profession
  window's filters (`C_TradeSkillUI.Set*`): Capture reads what's there. The Guild tab never calls a profession
  tab's OnClick or adds to its list, and never hides the window's pages: our page covers them (UI/GuildTab.lua).
- **Sync is silent** (the user, 2026-11-23: "lightweight, unintrusive and cheap", "no chat output"): no chat posts,
  nothing printed, the debug log only. Addon messages on GUILD only, from roster members only, paced far under the
  server's throttle (Core/Comm.lua's header); every incoming field is untrusted (Pack's readers return nil).
  A wire change bumps `Sync.PROTOCOL`; a peer's newer hello is read as far as ours goes.
- Only a guild member's recipes are stored, and membership is the roster's: a non-member's capture is dropped, one
  whose membership isn't known yet is held for the roster (`Capture.held`), and a complete roster prunes who left.
  An incomplete or stale roster never deletes anyone.
- Saved data changes go through `MIGRATIONS` in `Core/DB.lua` (schema 3 now); data newer than ours is left alone.
- Comments explain *why* (game quirks, decisions), not what. Player text lives in `Locale/enUS.lua` (`ns.L`,
  `ns.T`); developer output (Dev/, the log) is English and inline.

## Verify

- `tools/check.sh` runs the TOC↔file check, a Lua 5.1 syntax check (luajit), a scan for 5.2+ syntax, luacheck (its
  config from the harness's stubs, `tools/lint_config.lua`: a client API must be stubbed before lint takes it; a
  probe's maybe-missing field goes in its OPTIONAL lists), the Lua language server headless (fields and arguments:
  `ns.Indx`, `ns.Index:Serch()`; `tools/types.lua` writes `tools/types/ns.lua`), and the tests with coverage floors
  (**Core ≥ 95%, UI ≥ 95%, Main ≥ 95%, Dev ≥ 80%**). `tools/check.sh --quick` skips coverage.
- The game can't run from here. For in-game checks, ask the user to `/reload`, `/proff debug on`, and
  `/proff probe verify` (the checklist, Dev/Verify.lua) or `/proff probe [api|roster|window|link]` (Dev/Probe.lua).
  Then read `../../../WTF/Account/*/SavedVariables/Proff.lua` (account folder: `NIKKERN`) with
  **`luajit tools/log.lua`** (`-h`; `-m Capture,Guild`, `--dump probe.window`, `--errors`) and the stored recipes with
  **`luajit tools/db.lua`** (`search <words>`, `who <name>`, `check`). docs/FOREVER_API.md, "How to probe".
- The log: `ProffDebugDB.lines`, tab-separated `serverTime  GetTime  module  message`, a ring of
  `Config.DEBUG_RING_SIZE`; a `Session` line at each login; repeats folded " (xN)"; only a git checkout logs.
  Our own Lua errors go into it with their stack (Dev/Errors.lua, through BugGrabber).

## Testing

**Run the tests whenever you implement or change something**, and add or update tests in the same change:
`luajit tools/test/run.lua <filter>` while working, `tools/check.sh` before committing. A `pre-push` hook (`.githooks/`,
enabled per clone with `git config core.hooksPath .githooks`) runs `tools/check.sh --quick` on each pushed branch's
newest commit (the full check for a tag) in a temporary worktree. CI (`.github/workflows/check.yml`) runs the full
check on every push.

- `tools/test/harness.lua` simulates a world (read its header first): a clock (`w:Run(s)`, `w:Settle()`), the guild's
  roster, other players with professions (`w:AddPlayer(name, { profs, guild })`, `p:Learn`, `w:Leave`), and clients
  (`w:AddClient(name, opts)`), each running its own copy of the addon in its own global environment, logging in and
  out with SavedVariables kept (`c:Reload()`). Its parts live in `tools/test/harness/` (base, frames, world, client,
  ui, assert; the stub client API in `env/*.lua`). `frames.lua` has the widget types' methods (an EditBox's,
  a ScrollFrame's: one a type lacks throws) and regions; `blizzard.lua` the templates (P.TEMPLATES: a missing
  one throws, as the client does), Forever's `ProfessionsFrame` (profession side tabs, no tab bar), and `H.Menu(dropdown)`.
- A player's actions: `c:ClickLink(name, line)`, `c:OpenProfession(line)`, `c:OpenNPC(line)`, `c:CloseProfession()`,
  `c:Slash("search potion")`; the Guild tab: `c:OpenGuildTab()`, `c:Type("potion")`, a frame's `f:Press()`
  (a mouse press: OnMouseDown, then the click), `f:Run("OnEnter")` (a hover). Read results as a player would:
  `c:Mark()` then `c:Said()`, `c:Holders(recipeName)`, `c:Shown()` (the list's rows in view),
  `GameTooltip:Said()`, `c:Logged(module, text)`, `c:Listening(event)`.
- How the client might differ from retail is a `w.quirks` flag (`linkedName`, `noIsLinked`, `rosterGuid`,
  `guidName`, `rosterIgnored`, `rosterPartial`, `linkSync`, `itemsCached`, `itemsLost`, `spellTooltip`,
  `noSideTabs`, `missingTemplates`, `guildRecipes`; a client's `trial`). Addon messages: `w.wire`, `w:Sent(kind,
  from, since)`, `w:Mark()`, `w:Inject(sender, text)` (an outsider or a forger), `w.throttled`: test both ways for every assumption in docs/FOREVER_API.md's table.
- Specs: `tools/test/spec/NN_area.lua`, each `return function(test, H) ... end`. The runner fails a test whose
  clients hit a Lua error (`c:TakeErrors()` for one caused on purpose), wrote a stray global or printed an unfilled
  `{placeholder}` (`H.Invariants`).
- Stubs must behave like the real client. Unknown frame methods and unknown events throw on purpose; reads of
  globals the stubs lack are recorded and 01_core allows only the optional ones. When the addon starts using a new
  API, stub it realistically in the right `tools/test/harness/env/*.lua`.
- Before relying on a new test, make sure it can fail: break the code it covers once and watch it go red.

## Releasing (as Dyreparken, 2026-11-23, the user: "do it the same way Dyreparken does it")

- **Commit subjects are the changelog**: one line a player could read (what changed for them, not how), or starting
  with `Tests:`, `Tidy-up:`, `Notes:`, `Docs:` or `Developer probe` for what players don't see (left out).
  `tools/changelog.sh` prints what players will read since the newest tag; `tools/changelog.sh --draft vX.Y.Z`
  writes `COMMIT.md` to edit (reword, merge, drop), and when committed it is that tag's changelog word for word.
- Push a tag `vX.Y.Z` (release), `vX.Y.Z-betaN` or `vX.Y.Z-alphaN` on main. `.github/workflows/release.yml` runs the
  checks, refuses a tag not on main or not newer than the last, then BigWigsMods/packager@v2 uploads to CurseForge
  (WoW Forever, 1.60.1, from Interface 16001) and makes a GitHub release.
- Repository secrets: `CF_API_KEY` (a CurseForge API token) and `CF_PROJECT_ID` (passed as `-p`, kept out of the TOC).
- The TOC's Version is `dev` for a checkout (`#@debug@`) and the tag for a package (`#@non-debug@`).
- `.pkgmeta` leaves the dev files out of the zip: tools, docs, CLAUDE.md, README.md, COMMIT.md, .claude, .luarc.json,
  .github, .githooks, Dev (its TOC lines are in a `#@do-not-package@` block).
- A wire change bumps `Sync.PROTOCOL`; a saved data change adds a migration (Working rules).

## Layout

```
Proff.toc           load order (each file only uses files above it); Dev/ in a #@do-not-package@ block
Core/Init.lua       ns, Config tunables, client-value guards (Plain, Read, Yes), names (PlayerKey, NormalizeName,
                    GuildKey), Fold (lowercase with Latin-1), Print, ns.L/ns.T, start-up phases, Debounce, Bus
Locale/enUS.lua     every text players read, keyed
Core/Debug.lua      the debug log (ProffDebugDB), Debug.tap for Verify
Core/Events.lua     one frame for game events, registered only while someone listens
Core/DB.lua         ProffDB's shape (its header), Init, cleaning, MIGRATIONS
Core/Items.lua      reagents' names: C_Item, ITEM_DATA_LOAD_RESULT while some are on their way
Core/Pack.lua       compact text: numbers, recipe sets (first id + gaps), a set's checksum (pure)
Core/Guild.lua      the roster on demand: members, GUIDs, first names, complete; Resolve (whose is a link)
Core/Comm.lua       addon messages: kind + tab fields, S/F/M/L chunks, a paced outbox, members only, silent
Core/Recipes.lua    the store: Store (a profession whole), Forget, Prune (a complete roster)
Core/Skills.lua     the server's guild profession roster (expanded and collapsed back); skill sheets (ours, relayed);
                    Table, Sort
Core/Index.lua      search: Search, Holders, Member, Professions, Stats (pure over DB: tools/db.lua uses it)
Core/Capture.lua    the link click (SetItemRef hook), the window's events, reading it, Admit/Hold
Core/Spells.lua     names, icons, reagents of relayed recipes, from their spells (SPELL_DATA_LOAD_RESULT while asked)
Core/Sync.lua       relay sync: hello (digest), index (pages), request, data; read its header first
Core/Commands.lua   /proff
UI/GuildPage.lua    the Guild tab's page: search, profession filter, help, the virtual list, tooltips
UI/GuildMembers.lua the Members view: a slim column per profession (icon head), skills, sort by a column
UI/GuildTab.lua     the side tab under the profession tabs, the page covering the window, its views (Recipes,
                    Members: tabs under the window), leaving it (hooks only)
Dev/                Errors, Probe (/proff probe), Verify (/proff probe verify), Commands (/proff debug, probe)
Main.lua            ADDON_LOADED / PLAYER_LOGIN / settled phases
tools/              check.sh, lint_config.lua, types.lua, log.lua, db.lua, test/
```

## Decisions (2026-11-23)

- Account-wide storage (`ProffDB`), per guild, so every character of the account sees what any of them stored.
- A profession is stored whole each time it's seen, never merged: a recipe no longer shown is gone.
- Your own professions are stored too when you open them (you're a guild member; the user, 2026-11-23).
- **Sync relays** (the user, 2026-11-23: "Yes, relay"): every Proff user passes on every member's profession it
  holds, so one user opening a non-user's link is enough for the guild. Newest `at` wins, from any guild member;
  data about non-members is dropped. The server doesn't answer recipe queries (`/proff probe guild`), so this is
  the only way recipes travel. A profession's `at` moves only when its recipes change (`seen` is when it was read).
- Player text stays English (the user, 2026-11-23).
- The Guild tab's filter starts at "All professions" (not the open window's) and the search box empty: the
  list shows every recipe, by name. A recipe's reagents are read once (they don't change) and kept per recipe.
- Recipe names are kept once per recipe id (`ProffDB.recipes`), shared by guilds; in the client's language at the
  time (a language switch shows old names until each profession is seen again).
- The Members view's columns: primary professions by name, then Cooking, First Aid, Fishing at the right (the
  user, 2026-11-23: "they're not important").
- **Skill sheets** (the user, 2026-11-23: "a combination of A and B; skill level being stale is better than no
  skill level"): each Proff user's own levels (`GetProfessions`, secondaries too) are read at login and when their
  own profession is stored, kept as `members[who].skills`, and relayed by everyone like a profession (sync's `K`,
  key line 0). The Members view takes the highest of the server's, a link's and a sheet's. Whether
  `GetProfessions` lists First Aid on Forever is unprobed (`skills:own` logs what it reads).
- Whose a linked window is: the link's GUID on the roster, then the window's name, then `GetPlayerInfoByGUID`'s, then
  a first name only one member has. A first name two members share is "couldn't tell", not a guess.

## Open questions (ask the user before deciding)

- Relay sync is untested between two real clients.
