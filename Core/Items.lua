---@class Proff
local ns = select(2, ...)

-- The reagents' names (ProffDB.items), so a search finds a recipe by its ingredient. The client knows an item's
-- name only once the item is cached: C_Item.GetItemNameByID answers then (Forever has it: Dyreparken's API
-- dump), else C_Item.RequestLoadItemDataByID asks the server and ITEM_DATA_LOAD_RESULT says it came. That
-- event is heard only while names are on their way; whatever hasn't come after Config.ITEM_WAIT is asked
-- for again the next time (a capture, the Guild tab), not retried on a timer.
---@class Proff.Items
local Items = { pending = {}, waiting = 0 }
ns.Items = Items

local function Learn(id, name)
    if type(name) ~= "string" or name == "" then return false end
    local items = ns.DB:Items()
    if items[id] == name then return false end
    items[id] = name
    ns.DB.itemsRev = ns.DB.itemsRev + 1
    return true
end

local function Stop()
    Items.pending, Items.waiting = {}, 0
    ns.Events:Off("ITEM_DATA_LOAD_RESULT", Items)
end

local Done = ns.Debounce(0.2, function() ns.Bus:Fire("ITEMS") end)

local function OnLoaded(_, _, id, success)
    id = ns.Plain(id)
    if not Items.pending[id] then return end
    Items.pending[id] = nil
    Items.waiting = Items.waiting - 1
    if success ~= false and Learn(id, ns.Read(C_Item.GetItemNameByID, id)) then Done() end
    if Items.waiting <= 0 then
        ns.Log("Items", "every name asked for came")
        Stop()
    end
end

-- Names for these item ids (a list, or a set's keys with set = true): the known ones are kept, the cached
-- ones learned now, the rest asked for. Returns how many are on their way.
function Items:Want(ids, set)
    if ns.DB.data.readOnly or type(C_Item) ~= "table" then return 0 end
    local known, learned, asked = ns.DB:Items(), 0, {}
    local function One(id)
        if type(id) ~= "number" or known[id] or self.pending[id] then return end
        if Learn(id, ns.Read(C_Item.GetItemNameByID, id)) then
            learned = learned + 1
        elseif type(C_Item.RequestLoadItemDataByID) == "function" then
            asked[#asked + 1] = id
        end
    end
    if set then for id in pairs(ids) do One(id) end else for _, id in ipairs(ids) do One(id) end end
    if learned > 0 then Done() end
    if #asked == 0 then return self.waiting end
    if self.waiting == 0 and not ns.Events:On("ITEM_DATA_LOAD_RESULT", Items, OnLoaded) then return 0 end
    for _, id in ipairs(asked) do
        self.pending[id] = true
        self.waiting = self.waiting + 1
        pcall(C_Item.RequestLoadItemDataByID, id)
    end
    local token = {}
    self.token = token
    C_Timer.After(ns.Config.ITEM_WAIT, function()
        if Items.token ~= token or Items.waiting == 0 then return end
        ns.Log("Items", "%d names didn't come: asked again next time", Items.waiting)
        Stop()
    end)
    ns.Log("Items", "%d names known now, %d asked for", learned, #asked)
    return self.waiting
end

-- Every reagent of the stored recipes still without a name (the Guild tab opening: what a capture missed).
function Items:WantAll()
    local need = {}
    local known = ns.DB:Items()
    for _, r in pairs(ns.DB:Recipes()) do
        for id in pairs(r.r or {}) do if not known[id] then need[id] = true end end
    end
    return self:Want(need, true)
end
