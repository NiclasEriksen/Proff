-- C_Item, as retail's: an item's name only once the client has it cached (c.itemCache); a load request
-- answers ITEM_DATA_LOAD_RESULT a moment later. Quirks: w.quirks.itemsCached (all known at once),
-- itemsLost (a request never answers).
local H, P = ...

return function(c, env)
    local w = c.world
    c.itemCache = c.itemCache or {}
    c.itemRequests = 0
    local function Cached(id) return w.quirks.itemsCached or c.itemCache[id] end
    -- Spells (a recipe id is its spell's): the name "<Profession>: <recipe>", once cached (c.spellCache, or
    -- w.quirks.spellsCached); RequestLoadSpellData answers SPELL_DATA_LOAD_RESULT a moment later.
    c.spellCache = c.spellCache or {}
    local function Recipe(id)
        for _, p in pairs(H.PROFESSIONS) do if p.recipes[id] then return p.name .. ": " .. p.recipes[id] end end
    end
    env.C_Spell = {
        GetSpellName = function(id) return (w.quirks.spellsCached or c.spellCache[id]) and Recipe(id) or nil end,
        GetSpellTexture = function(id) return Recipe(id) and 135000 + id % 1000 or nil end,
        RequestLoadSpellData = function(id)
            c.spellRequests = (c.spellRequests or 0) + 1
            w:After(0.1, function()
                if Recipe(id) then c.spellCache[id] = true end
                c:Fire("SPELL_DATA_LOAD_RESULT", id, Recipe(id) ~= nil)
            end, c)
        end,
    }
    env.C_Item = {
        GetItemNameByID = function(id) return Cached(id) and H.ITEMS[id] or nil end,
        GetItemIconByID = function(id) return H.ITEMS[id] and 130000 + id % 1000 or nil end,
        RequestLoadItemDataByID = function(id)
            c.itemRequests = c.itemRequests + 1
            if w.quirks.itemsLost then return end
            w:After(0.1, function()
                if H.ITEMS[id] then c.itemCache[id] = true end
                c:Fire("ITEM_DATA_LOAD_RESULT", id, H.ITEMS[id] ~= nil)
            end, c)
        end,
    }
end
