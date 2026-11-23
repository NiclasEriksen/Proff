-- The profession window's API (C_TradeSkillUI, retail-style as on Forever), answering from c.window:
--   { owner = a world player, line = base skill line, kind = "own" | "linked" | "npc" | "guild", changing }
-- While the data source changes, the list is empty and IsDataSourceChanging says so. The child line says 0/0
-- (Forever, AuctionDetonator's note); the base one has the level. Quirks: w.quirks.linkedName = false
-- (IsTradeSkillLinked: true but no name), noIsLinked (no such function).
local H, P = ...

return function(c, env)
    local w = c.world
    local function Win()
        local win = c.window
        if win and not win.changing then return win end
    end
    local function Prof(win) return H.PROFESSIONS[win.line] end
    local T = {}
    T.IsTradeSkillLinked = function()
        local win = c.window
        if not win or win.kind ~= "linked" then return false, nil end
        return true, w.quirks.linkedName ~= false and win.owner.name or nil
    end
    T.IsTradeSkillGuild = function() return c.window ~= nil and c.window.kind == "guild" end
    T.IsTradeSkillGuildMember = function() return false end
    T.IsNPCCrafting = function() return c.window ~= nil and c.window.kind == "npc" end
    T.IsDataSourceChanging = function() return c.window ~= nil and c.window.changing == true end
    T.IsTradeSkillReady = function() return Win() ~= nil end
    T.GetBaseProfessionInfo = function()
        local win = Win()
        if not win then return { professionID = 0, skillLevel = 0, maxSkillLevel = 0 } end
        local p = Prof(win)
        return { professionID = win.line, professionName = p.name, skillLevel = win.owner.rank,
            maxSkillLevel = win.owner.max, expansionName = "Classic" }
    end
    T.GetChildProfessionInfo = function()
        local win = Win()
        if not win then return { professionID = 0, skillLevel = 0, maxSkillLevel = 0 } end
        local p = Prof(win)
        return { professionID = p.child, professionName = "Classic " .. p.name, skillLevel = 0, maxSkillLevel = 0,
            parentProfessionID = win.line, parentProfessionName = p.name }
    end
    T.GetProfessionInfoBySkillLineID = function(line)
        local p = H.PROFESSIONS[line]
        return p and { professionID = line, professionName = p.name } or { professionID = 0 }
    end
    T.GetAllRecipeIDs = function()
        local win = Win()
        if not win then return {} end
        local ids = {}
        for id in pairs(Prof(win).recipes) do ids[#ids + 1] = id end
        table.sort(ids)
        return ids
    end
    T.GetRecipeInfo = function(id)
        local win = Win()
        local name = win and Prof(win).recipes[id]
        if not name then return nil end
        local learned = (win.owner.profs[win.line] or {})[id] == true
        return { recipeID = id, name = win.secretNames and H.SECRET or name, icon = 134000 + id % 1000,
            learned = learned, categoryID = win.line * 10, craftable = learned, disabled = false, favorite = false }
    end
    T.GetRecipeLink = function(id) return ("|cffffd000|Henchant:%d|h[%s]|h|r"):format(id, "Recipe") end
    T.GetProfessionInfoByRecipeID = function(id)
        for line, p in pairs(H.PROFESSIONS) do
            if p.recipes[id] then return { professionID = p.child, parentProfessionID = line } end
        end
    end
    T.GetTradeSkillTexture = function(line) return H.PROFESSIONS[line] and 136240 + line % 100 or nil end
    T.IsGuildTradeSkillsEnabled = function() return w.quirks.guildRecipes ~= false end
    T.GetRecipeOutputItemData = function(id) return { itemID = id + 100000 } end
    -- Static data, whoever's window: retail's CraftingRecipeSchematic, one item per slot as in Classic recipes.
    T.GetRecipeSchematic = function(id, isRecraft)
        c.schematics = (c.schematics or 0) + 1
        local slots = {}
        local list = {}
        for item in pairs(H.REAGENTS[id] or {}) do list[#list + 1] = item end
        table.sort(list)
        for _, item in ipairs(list) do
            slots[#slots + 1] = { reagents = { { itemID = item } }, quantityRequired = H.REAGENTS[id][item],
                reagentType = 1, required = true, dataSlotIndex = #slots + 1 }
        end
        return { recipeID = id, isRecraft = isRecraft, reagentSlotSchematics = slots, quantityMin = 1, quantityMax = 1 }
    end
    if w.quirks.noIsLinked then T.IsTradeSkillLinked = nil end
    -- The player's own professions (Forever: slots primary, primary, archaeology, fishing, cooking; nil for an
    -- empty one; Dyreparken's probe, 2026-11-13). A profession's level: player.skills[line] or player.rank.
    -- w.quirks.noProfessions: the functions missing.
    local function Own()
        local p = c.player
        local prim, sec = {}, {}
        for line in pairs(p and p.profs or {}) do
            local list = H.PROFESSIONS[line].secondary and sec or prim
            list[#list + 1] = line
        end
        table.sort(prim); table.sort(sec)
        return p, prim, sec
    end
    env.GetProfessions = function()
        local _, prim, sec = Own()
        local cooking
        for i, line in ipairs(sec) do if line == 185 then cooking = 2 + i end end
        return prim[1] and 1 or nil, prim[2] and 2 or nil, nil, nil, cooking
    end
    env.GetProfessionInfo = function(index)
        local p, prim, sec = Own()
        local line = index <= 2 and prim[index] or sec[index - 2]
        if not line then return nil end
        local rank = p.skills and p.skills[line] or p.rank
        return H.PROFESSIONS[line].name, 136240 + line % 100, rank, p.max, 0, 0, line, 0, 0, 0
    end
    if w.quirks.noProfessions then env.GetProfessions, env.GetProfessionInfo = nil, nil end
    env.C_TradeSkillUI = T
end
