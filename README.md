# Proff

Your guild's recipes, for World of Warcraft: Forever. Proff fills itself as you play: whenever you open a guild
member's profession link in chat (or your own profession window), it remembers the recipes they know. Then ask it
who can craft something:

```
/proff search major healing     who in the guild knows a recipe
/proff who Kari                 one member's professions
/proff stats                    how much is known
/proff forget <name>            drop a member's recipes
```

Or open any profession and click the **Guild** tab under the profession tabs on the window's right: every recipe the guild knows, searchable by
recipe, crafter or ingredient, with a profession filter. Hover a recipe for its tooltip and who knows it.

The **Members** tab lists every guild member's professions and skill levels, offline members too (greyed), sortable by
profession or by who's online.

In Blizzard's guild window, clicking a member shows small icons of their professions on the detail panel; hover one
for their skill and how many of their recipes Proff knows.

Guildmates running Proff share what they know quietly in the background: one person opening a link is enough for
everyone, and each Proff user's own skill levels reach the rest of the guild. Nothing is posted in chat. Only guild
members' recipes are kept, and members who leave the guild are dropped.

Development: `tools/check.sh` (lint, types, tests); see CLAUDE.md.
