---@class Proff
local ns = select(2, ...)

-- Every text players read, keyed, with named {placeholders}. Code holds no player text: add a key here and
-- use ns.L[key] / ns.T(key, vars). Developer output (Dev/, the debug log) stays English and inline.
local L = ns.L

L["stored.linked"] = "Stored {n} {prof} recipes from {who}."
L["stored.own"] = "Stored your {n} {prof} recipes."
L["stored.same"] = "{who}'s {prof} is up to date ({n} recipes)."
L["skip.notmember"] = "{who} isn't in your guild: their recipes weren't stored."
L["skip.unknown"] = "Couldn't tell whose profession this is: nothing stored."
L["skip.noguild"] = "You're not in a guild: nothing stored."
L["held"] = "Waiting for the guild roster before storing {who}'s {prof}."

L["search.usage"] = "/proff search <words>: who in the guild knows a recipe."
L["search.none"] = "No recipe matches \"{q}\"."
L["search.head"] = "{n} recipes match \"{q}\":"
L["search.row"] = "{name} ({prof}): {who}"
L["search.more"] = "... and {n} more."
L["who.none"] = "No recipes stored for {who}."
L["who.row"] = "{prof}: {n} recipes, {rank}seen {ago}"
L["stats"] = "{guild}: {members} members, {profs} professions, {recipes} different recipes."
L["stats.noguild"] = "You're not in a guild."
L["forget.done"] = "Forgot {who}'s recipes."
L["forget.none"] = "Nothing stored for {who}."
L["help"] = "/proff search <words> | who <name> | stats | forget <name>"

L["ago.now"] = "just now"
L["ago.min"] = "{n} min ago"
L["ago.hour"] = "{n} h ago"
L["ago.day"] = "{n} days ago"

-- The profession window's Guild tab (UI/)
L["tab.title"] = "Guild"
L["tab.tip"] = "Every recipe your guild knows: search by recipe, crafter or ingredient."
L["tab.search"] = "Recipe, crafter or ingredient"
L["tab.all"] = "All professions"
L["tab.prof"] = "{name} ({n})"
L["tab.count"] = "{n} recipes"
L["tab.you"] = "You"
L["tab.col.recipe"] = "Recipe"
L["tab.col.prof"] = "Profession"
L["tab.col.who"] = "Known by"
L["tab.empty"] = "No guild recipes known yet.\n\nThey're stored when you open a guildmate's profession link in chat, and when you open your own professions."
L["tab.nomatch"] = "Nothing matches \"{q}\"."
L["tab.noguild"] = "You're not in a guild."
L["tip.known"] = "Known by ({prof}):"
L["tip.reagents"] = "Reagents:"
L["tip.reagent"] = "{n} x {name}"
L["help.title"] = "Searching the guild's recipes"
L["help.search"] = "Search by recipe name, crafter name or ingredient. Words can be in any order: \"kari potion\", \"peacebloom\", \"bracer strength\"."
L["help.filter"] = "The list beside the search shows one profession only."
L["help.where"] = "Proff remembers recipes when you open a guild member's profession link in chat, and your own professions when you open them. Hover a recipe to see it."

-- The Guild tab's views (bottom tabs) and its Members view
L["tab.view.recipes"] = "Recipes"
L["tab.view.members"] = "Members"
L["members.count"] = "{n} members"
L["members.hint"] = "Click a profession to sort by it"
L["members.col.name"] = "Member"
L["members.empty"] = "No profession data for the guild yet."
L["members.asking"] = "Asking the server..."
L["members.offline"] = "Offline"
L["members.tip.skill"] = "{prof} {skill}"
L["members.tip.recipes"] = " ({n} recipes known)"
L["members.tip.have"] = "{n} members"
L["members.tip.sort"] = "Click: sort by it"
