---@class Proff
local ns = select(2, ...)

-- Names (and icons, reagents) for recipes we got by sync: only their ids travel. A recipe id is its spell's, so
-- the client can name it: C_TradeSkillUI.GetRecipeInfo when it answers outside the window, else the spell's name
-- (C_Spell.GetSpellName; "Enchanting: " in front is dropped) and icon. A spell the client hasn't cached yet is
-- asked for (C_Spell.RequestLoadSpellData) and SPELL_DATA_LOAD_RESULT is heard while some are on their way;
-- what hasn't come after Config.ITEM_WAIT is asked for again next time. Reagents come from the recipe's schematic
-- (static data, Capture.Reagents), their names through ns.Items. Silent.
---@class Proff.Spells
local Spells = { pending = {}, waiting = 0 }
ns.Spells = Spells

local Plain = ns.Plain

-- Name and icon of recipe id in profession `prof` (its name, to drop "Prof: "), or nil while unknown.
function Spells.Look(id, prof)
    local r = ns.Read(C_TradeSkillUI.GetRecipeInfo, id)
    if type(r) == "table" and type(Plain(r.name)) == "string" and r.name ~= "" then
        return r.name, Plain(r.icon), Plain(r.categoryID)
    end
    local S = C_Spell
    if type(S) ~= "table" then return nil end
    local name = ns.Read(S.GetSpellName, id)
    if type(name) ~= "string" or name == "" then return nil end
    if prof and name:sub(1, #prof + 2) == prof .. ": " then name = name:sub(#prof + 3) end
    return name, ns.Read(S.GetSpellTexture, id)
end

local Done = ns.Debounce(0.2, function()
    ns.DB.itemsRev = ns.DB.itemsRev + 1 -- (Index rebuilds: the names it searches changed)
    ns.Bus:Fire("ITEMS")
end)

-- One recipe named (and its reagents read) now if the client can; true when it's done.
local function Fill(id, w)
    local names = ns.DB:Recipes()
    local name, icon, cat = Spells.Look(id, w.prof)
    if not name then return false end
    local reagents = ns.Capture.Reagents(id)
    names[id] = { n = name, i = icon, l = w.line, c = cat, r = reagents }
    if reagents then ns.Items:Want(reagents, true) end
    return true
end

local function Stop()
    Spells.pending, Spells.waiting = {}, 0
    ns.Events:Off("SPELL_DATA_LOAD_RESULT", Spells)
end

local function OnLoaded(_, _, id, success)
    id = Plain(id)
    local w = Spells.pending[id]
    if not w then return end
    Spells.pending[id] = nil
    Spells.waiting = Spells.waiting - 1
    if success ~= false and Fill(id, w) then Done() end
    if Spells.waiting <= 0 then
        ns.Log("Spells", "every recipe name asked for came")
        Stop()
    end
end

-- Names for these recipe ids (a set) of skill line `line`, profession name `prof`: the known kept, the cached
-- named now, the rest asked for. Returns how many are on their way.
function Spells:Want(ids, line, prof)
    if ns.DB.data.readOnly then return 0 end
    local names, named, asked = ns.DB:Recipes(), 0, {}
    for id in pairs(ids) do
        if not names[id] and not self.pending[id] then
            local w = { line = line, prof = prof }
            if Fill(id, w) then
                named = named + 1
            elseif type(C_Spell) == "table" and type(C_Spell.RequestLoadSpellData) == "function" then
                asked[#asked + 1] = { id, w }
            end
        end
    end
    if named > 0 then Done() end
    if #asked == 0 then return self.waiting end
    if self.waiting == 0 and not ns.Events:On("SPELL_DATA_LOAD_RESULT", Spells, OnLoaded) then return 0 end
    for _, a in ipairs(asked) do
        self.pending[a[1]] = a[2]
        self.waiting = self.waiting + 1
        pcall(C_Spell.RequestLoadSpellData, a[1])
    end
    local token = {}
    self.token = token
    C_Timer.After(ns.Config.ITEM_WAIT, function()
        if Spells.token ~= token or Spells.waiting == 0 then return end
        ns.Log("Spells", "%d recipe names didn't come: asked again next time", Spells.waiting)
        Stop()
    end)
    ns.Log("Spells", "%d recipes named now, %d asked for", named, #asked)
    return self.waiting
end
