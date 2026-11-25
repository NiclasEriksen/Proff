# World of Warcraft: Forever, addon API notes (Proff)

**The client's reference is Dyreparken's `../Dyreparken/docs/FOREVER_API.md`.** Read it before writing WoW API code:
it's the probed record of secret values, missing APIs, chat links, combat lockdown and SavedVariables. This file
keeps only what Proff relies on, the profession-window findings, and what's still to be probed. Add findings here
with the date and build; one that matters to every addon goes in Dyreparken's doc too.

## From Dyreparken's notes, the parts Proff leans on

- **Client**: product `wowf`, client 1.60.1 (builds 70790 to 71037 seen), `## Interface: 16001`. The modern Mainline
  engine with Classic-like content: retail-style API (`C_TradeSkillUI`, `ProfessionsFrame`), Classic globals mostly
  missing. Detect by probing for the API, not by version numbers.
- **Lua 5.1**: no `goto`, `//`, bitwise operators, `require`/`io`/`os` (but `date`, `time`). 200 locals per function.
  `tools/check.sh` greps for 5.2+ syntax.
- **Names**: characters have **surnames**. `UnitName("player")` gives `"First", "Surname"` (the second value is the
  surname, not a realm). Roster and chat names are `"First Surname"`. Full names are unique across rulesets.
  **Realms are ignored**: a `-Realm` suffix is stripped (`ns.NormalizeName`, kept for hyphenated surnames). The
  guild key is the guild's name (two same-named guilds on two rulesets would share an entry: accepted).
- **Secret values**: some values throw on comparison, arithmetic, indexing or printing. Guard every value read from
  the client (`ns.Plain`, `ns.Read`, `ns.Yes`); a secret becomes nil. A secret table: `type()` says "table".
- **Registering an unknown event throws** and aborts the file: `ns.Events:On` pcalls it and logs.
- **Templates** (Dyreparken's probe, 2026-11-11): `SearchBoxTemplate`, `WowStyle1DropdownTemplate` (a
  `DropdownButton`), `UIPanelScrollFrameTemplate`, `InsetFrameTemplate`, `PanelTabButtonTemplate`,
  `TabSystemTemplate`, `UIPanelButtonTemplate` exist; `CharacterFrameTabButtonTemplate`, `ItemButtonTemplate`
  don't. `C_XMLUtil.GetTemplateInfo` tells (UI/GuildTab.lua's `Template`). `C_Item.GetItemNameByID`,
  `GetRecipeSchematic`, `Menu`/`MenuUtil` exist.
- **Missing**: `GetSpellInfo`, `GetItemInfo`, `GetNumSkillLines`/`GetSkillLineInfo`, the Classic trade skill and craft
  APIs (`GetTradeSkillLine`, `GetNumTradeSkills`, `GetTradeSkillInfo`, `GetCraftInfo`). The harness's `H.MISSING`
  (tools/test/harness/base.lua) lists them; 01_core checks the stub client lacks them too.
- **Addon links in chat work**, and a click reaches `hooksecurefunc("SetItemRef")` (2026-11-22, Dyreparken's probe).
- **SavedVariables** are written on /reload and logout, not on a crash. Create defaults at `ADDON_LOADED`.
- **Combat**: never call protected functions in combat; hook Blizzard UI (`hooksecurefunc`, `HookScript`), never
  replace it. Opening or switching a Blizzard window from addon code can taint it (Dyreparken, the Collections
  window): the Guild tab never calls the profession window's `SetTab` or adds to its tab list (UI/GuildTab.lua).
- **Guild chat posts** only from a keypress or click (a timer's is blocked). Proff posts nothing.

## Professions: what's known (Dyreparken's API dump, `/dp probe api`, 2026-11-11, build 70888)

- `C_TradeSkillUI` is retail's, nearly whole. It has everything Capture uses: `IsTradeSkillLinked`,
  `IsTradeSkillGuild`, `IsTradeSkillGuildMember`, `IsNPCCrafting`, `IsDataSourceChanging`, `IsTradeSkillReady`,
  `GetAllRecipeIDs`, `GetFilteredRecipeIDs`, `GetRecipeInfo`, `GetBaseProfessionInfo`, `GetChildProfessionInfo(s)`,
  `GetProfessionInfoBySkillLineID`, `GetProfessionInfoByRecipeID`, `GetRecipeLink`, `GetRecipeOutputItemData`,
  `GetCategories`/`GetCategoryInfo`, `GetTradeSkillDisplayName`, `GetTradeSkillListLink`, `CanTradeSkillListLink`,
  `IsGuildTradeSkillsEnabled`, `OpenTradeSkill`, `CloseTradeSkill`. **Not there**: `GetTradeSkillLine`.
- The globals `GetGuildRosterInfo`, `GetGuildRosterLastOnline`, `GetPlayerInfoByGUID`, `SetItemRef` and
  `ProfessionsFrame_LoadUI` exist. `TRADE_SKILL_SHOW`, `SKILL_LINES_CHANGED`, `GUILD_ROSTER_UPDATE` register.
- `GetProfessions()` / `GetProfessionInfo(i)` work (name, icon, rank, maxRank, ..., skillLine; Herbalism 224/225,
  Enchanting 186/225; Dyreparken 2026-11-13). maxRank is the trainer's current cap, not 300.
- The open window's **child** profession says 0/0 while the **base** one has the real level (AuctionDetonator's
  note, `Crafting.OpenProfession`): Capture reads the level from whichever has a cap.
- `ProfessionsFrame` is the profession window (Mastercraft and AuctionDetonator build on it; no addon here adds
  a tab to it, so Proff's Guild tab follows Dyreparken's SidePage instead, on the Collections window).
- Other addons here treat only a real `true` (or nonzero) from `IsTradeSkillLinked` / `IsTradeSkillGuild` /
  `IsNPCCrafting` as a yes: a 0, a secret or an error is a no (Mastercraft, its patch-331). `ns.Yes` does the same.

## Professions: confirmed in game (Proff's verify, 2026-11-23, build 71037)

- **The link** is retail's: `trade:<GUID>:<spell>:<skill line>`, e.g. `trade:Player-6841-0129B6A9:13920:333`
  (Enchanting: base skill line 333, `GetBaseProfessionInfo().professionID` 333 too). A click reaches
  `hooksecurefunc("SetItemRef")`.
- **The window opens inside the click**: `TRADE_SKILL_SHOW` comes during Blizzard's `SetItemRef`, before our
  post-hook sees the link (the harness's `linkSync`). Capture reads 0.3 s later, so the link is known by then.
- `IsTradeSkillLinked()` gives `true, "First Surname"` for someone's link (your own link clicked too: true,
  your name), `false, nil` for your own window. `GetRecipeInfo(id).learned` is the **linked player's** (56
  learned in theirs, 104 in ours, same profession).
- `GetGuildRosterInfo`'s 17th value is the member's GUID: a link was placed by it (`capture:byguid`).
- A non-member's link opens their window as well; Capture drops it ("isn't in your guild").
- **The profession window isn't retail's** (screenshot and `/proff probe window`, 2026-11-23, build 71037):
  `ProfessionsFrame`, 673x594, frame level 1 (MEDIUM), title "Professions", background atlas
  `Profession-Background-Overview`. **No tab bar** (no `TabSystem`, no `recipesTabID`); down the right edge:
  - `ProfessionsOverviewTab` (the overview page, `BookPage`, with every profession's rank bar), then
    `Professions1Tab` .. `Professions7Tab`, also in `ProfessionsFrame.rightProfessionTabs` (ForeverRecipes uses it):
    the character's professions shown (`.skillLine`: 182, 333, 356, 185), the rest hidden. They're **Frames**
    (not Buttons), 55x55, 57 px from top to top (2 px apart), level 2, with an `OnClick` method.
  - Each has six textures: `common-sidetab`, the icon (no atlas), `common-sidetab-mask`, two
    `common-sidetab-selected` (the **first shown only on the open profession's tab**; the second on every tab),
    `common-sidetab-hover`: the Collections window's side tab art (Dyreparken).
  - Other children: `NineSlice` (500), `PortraitContainer` (400), `TitleContainer` and `CloseButton` (510),
    `CraftingPage` (100; its parts reach 608), `BookPage`, `FrameGlow`, `TabIndicators`, jump hints. The overview's
    rank bars are drawn above a page at the window's level + 500, so the Guild tab's page goes above the highest
    shown part each time it opens.
- **The window opens on its overview** (2026-11-23): `ProfessionsFrame` shows with `BookPage` (every
  profession's rank bar), **no profession open** (`GetAllRecipeIDs` empty, base `professionID` 0) and **no
  `TRADE_SKILL_SHOW`**; that event comes only when a profession's tab is clicked. So anything that should be on
  the window from the start attaches when the window exists (`ADDON_LOADED` of whichever addon, then
  `rawget(_G, "ProfessionsFrame")`; or at login if it's already there), not on `TRADE_SKILL_SHOW`
  (UI/GuildTab.lua; the Guild tab was missing until a profession was picked, before).
- **The recipe tooltip**: `GameTooltip:SetSpellByID(recipeID)` shows the recipe ("Enchanting: Arcane Salvager",
  Tools, Reagents, the item, "Requires Enchanting (140)"). Recipe ids can be Forever's own (1263056).
- `GetRecipeSchematic(id, false).reagentSlotSchematics[i]` is retail's (`reagents = { { itemID } }`,
  `quantityRequired`, `reagentType` 1). `GetTradeSkillListLink()` gives your profession's link and spell
  (`trade:<GUID>:13920:333`, 13920). `GetChildProfessionInfo` is empty (`professionID` 0) in your own window;
  `GetAllRecipeIDs()` lists the whole profession (262 ids, 104 learned: all of Enchanting, one skill line).
- **The chat link bug** (2026-11-23, the user: profession links in whispers and guild chat can't be opened
  for most people): the click still reaches `SetItemRef` (a `Player-6939-...` Tailoring link, clicked about 40
  times), but no window ever opens. Nothing an addon can do about it: Proff just never sees a window.

## Guild sync: what the client offers (2026-11-23)

- **A profession link can't be read silently.** No `C_TradeSkillUI` function takes a link (or a GUID) and gives
  recipes (Dyreparken's dump, every function listed); the server sends someone's recipes only by opening their
  profession in the window, as a click on their link does (`TRADE_SKILL_SHOW`, the window shows). A shared link
  could open a member's real profession on demand (a click), not feed a background sync. Forever's links carry no
  recipe data (`trade:<GUID>:<spell>:<line>`, unlike Classic's encoded bitmask).
- **The server's own guild profession system is in the client** (Cataclysm's): `QueryGuildRecipes`,
  `GetNumGuildTradeSkill`, `GetGuildTradeSkillInfo` (the guild's professions and who has them), and
  `C_GuildInfo.QueryGuildMembersForRecipe(line, recipe)` answered by `GUILD_RECIPE_KNOWN_BY_MEMBERS`,
  `GetGuildRecipeInfoPostQuery()` and `GetGuildRecipeMember(i)` (who knows one recipe), `CanViewGuildRecipes`,
  `C_TradeSkillUI.IsGuildTradeSkillsEnabled`. **Probed 2026-11-23 (build 71037, `/proff probe guild`): the recipe
  half is off.** `IsGuildTradeSkillsEnabled()` false, `CanViewGuildRecipes(182)` false, and
  `QueryGuildMembersForRecipe(182, 1229705)` is never answered (no `GUILD_RECIPE_KNOWN_BY_MEMBERS`;
  `GetGuildRecipeInfoPostQuery` gives 0, 0, 0). **The profession roster works**: `QueryGuildRecipes()` is answered by
  `GUILD_TRADESKILL_UPDATE` at once (+0.03 s), and `GetGuildTradeSkillInfo(i)` lists a header per profession
  (skillID, collapsed = true, icon, name, numOnline, numVisible, numPlayers: Alchemy 11, Enchanting 18, Mining 32,
  ... and a "Test Profession [DNT]" 2933 with 0). Collapsed, so no member rows: those would need
  `ExpandGuildTradeSkillHeader(skillID)` (the guild window's shared collapse state: untried). So the server can say
  who has a profession (and their skill, once expanded), never which recipes.
  **Expanded, it lists the members** (screenshot, 2026-11-23: 23 members, class colors right): name, online,
  class file, skill. **The skill is always 1** (ours too: Enchanting 281, Herbalism 300 said 1), and **only primary
  professions are listed**: no Cooking, Fishing or First Aid header at all (the 287 and 294 seen for ours were
  Proff's own stored ranks). So a 1 means "has it": Core/Skills.lua reads it so, and a rank Proff stored (own
  window, a link, sync) fills it in; secondary professions come only from Proff's own data. `/proff debug` logs one raw member row a
  query ("Skills: a member row"), in case the real skill is in another field.
  **`ExpandGuildTradeSkillHeader` and `CollapseGuildTradeSkillHeader` fire `GUILD_TRADESKILL_UPDATE` inside the
  call, before they return** (the log, 2026-11-24, build 71037: one read finished ten times in the same frame, a
  handler re-entered per header). Core/Skills.lua ignores the updates its own expanding causes and reads once after.
  `GetProfessions()` lists every profession with its base skill line: Herbalism 182, Cooking 185, Enchanting 333,
  Fishing 356, and **First Aid 129** (a guildmate's skill sheet, 2026-11-24: First Aid 225/225, Skinning 393).
- **Relay sync works between two real clients** (2026-11-24, build 71037, our log): our hello, their index, our
  request for 6 entries, 5 professions and a skill sheet back within 7 s; ours they lacked pushed (4 D, 1 K, the
  biggest 192 bytes in one part). Relayed recipes were all in the client's spell cache: named at once (155 of 155).
- **The guild profession roster lists online members only** (2026-11-25, build 71037: 44 member rows with 22 of
  109 online, about two professions each; the rows changed with who was online, 25 to 51 over two days).
- **The guild window is retail's `CommunitiesFrame`** (`/proff probe communities`, 2026-11-25): 814x426; the member
  list's columns Lvl, Class, Name, Zone, Rank, Note; each row has `memberInfo`, retail's ClubMemberInfo, **with
  `profession1ID/Name/Rank` and `profession2...`** (rank 1, as the roster's), and the methods `Init`, `SetMember`.
  `GuildMemberDetailFrame` (212x260, shown to the window's right when a name is clicked) has `DisplayMember`:
  Name at TOPLEFT 17,-18, Level under it, the close button at TOPRIGHT, the zone, rank, last online and the notes
  below, Remove and Group Invite at the bottom. Guild Roster Manager (also for Forever, Interface 16001) uses the
  same frames, takes every member's professions from `C_Club.GetMemberInfo` (offline members too: its saved data,
  77 offline members with professions), replaces the panel's OnShow/OnHide/OnKeyDown with `SetScript`, and adds
  a line above the panel, a button below it and its own panel to the right (UI/MemberDetail.lua's header).
- Addon messages: Dyreparken's "Addon messages" section (255 bytes, 10 per prefix +1/s, Trial accounts can't send,
  "First Surname" senders, GUILD only). Proff's Core/Comm.lua follows it.

## Professions: assumed from retail, to probe (`/proff probe verify` ticks each)

Each is an item in Dev/Verify.lua; the harness stubs the retail behaviour, and a `w.quirks` flag for the other
way (tools/test/harness.lua's header), so both are tested.

| Assumption | If not | Verify item / probe |
| --- | --- | --- |
| `GetPlayerInfoByGUID(guid)`'s 6th value is the full name | a first name alone, matched when one member has it (`guidName`) | `capture:byname` |
| Addon messages on GUILD reach guildmates with our prefix registered | no sync at all (a Trial account: never sends) | `sync:sent`, `sync:heard` |
| `C_Spell.GetSpellName(recipeID)` names a recipe (perhaps "Enchanting: <name>": the prefix is dropped), `RequestLoadSpellData` answers with `SPELL_DATA_LOAD_RESULT`; `GetRecipeSchematic` works for a recipe whose profession isn't open | relayed recipes show as "#id" (Core/Spells.lua) | `sync:names` |
| `GetProfessions()` / `GetProfessionInfo(i)` give every profession's level and its base skill line (Cooking 185, Fishing 356, First Aid 129 if listed: Forever's slots may leave First Aid out) | no own skill sheet, nothing else changes (`noProfessions`); secondary columns sort among the primaries if their lines differ | `skills:own` |
| `C_Club.GetGuildClubId` / `GetClubMembers` / `GetMemberInfo` list every guild member, offline too, with their two primaries (`profession1ID`..), without the guild window open | offline members only with what Proff stored (`noClub`) | `members:club` |
| `GuildMemberDetailFrame:DisplayMember(clubId, memberInfo)` runs for each member shown (hooked) | no icons on the panel | `detail:icons` |
| `C_Item.RequestLoadItemDataByID` answers with `ITEM_DATA_LOAD_RESULT` (id, success) | names only for cached items (`itemsLost`: given up after `ITEM_WAIT`, asked again when the tab opens) | `capture:itemnames` |

## How to probe

1. `/reload`, `/proff debug on`, `/proff probe verify` (stays on across logins until `/proff probe verify off`).
2. Open your own profession; click a guildmate's profession link in chat; click a non-member's. Click the
   Guild tab, hover a recipe, then click a profession tab.
3. `/proff probe` with the window open (api, roster, window), and `/proff probe link` before clicking a link to
   record each event of the window with what the API said at each.
4. `/reload`, then from the addon folder: `luajit tools/log.lua` (the session), `luajit tools/log.lua -m Capture,Guild`,
   `luajit tools/log.lua --dump probe.window` (or `.api`, `.roster`, `.link`), `luajit tools/db.lua` (what's stored).
5. Write what was learned above, with date and build, and move a confirmed row out of the table.

## Sources

- Dyreparken (`../Dyreparken/docs/FOREVER_API.md`) and its API dump (`WTF/Account/*/SavedVariables/Dyreparken.lua`,
  `DyreparkenDebugDB.api`).
- Mastercraft (`../Mastercraft/Crafters.lua`), AuctionDetonator (`../AuctionDetonator/Crafting/Crafting.lua`),
  ForeverArtisan_Core (`UI.lua`): how other Forever addons read the profession window.
