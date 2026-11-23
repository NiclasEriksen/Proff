-- Blizzard's UI globals the addon uses: GameTooltip, C_XMLUtil (which templates exist), the classic tab
-- functions. The recipe's spell tooltip has its name and reagents; w.quirks.spellTooltip = false: the client
-- shows nothing for it (an unknown spell), "error": SetSpellByID throws.
local H, P = ...

return function(c, env)
    local w = c.world
    local tip = P.NewFrame(c, "GameTooltip")
    tip.shown = false
    tip.lines = {}
    local G = P.BY_KIND.GameTooltip
    if not G.SetOwner then
        function G:SetOwner(owner, anchor) self.owner, self.anchor, self.lines = owner, anchor, {} end
        function G:IsOwned(f) return self.owner == f and self.shown end
        function G:GetOwner() return self.owner end
        function G:ClearLines() self.lines = {} end
        function G:NumLines() return #self.lines end
        function G:SetText(text) self.lines = { tostring(text) } end
        function G:AddLine(text) self.lines[#self.lines + 1] = tostring(text) end
        function G:SetSpellByID(id)
            local q = self.client.world.quirks.spellTooltip
            if q == "error" then error("SetSpellByID: bad spell", 2) end
            self.spell = id
            if q == false then return end
            for _, p in pairs(H.PROFESSIONS) do
                if p.recipes[id] then
                    self.lines = { p.recipes[id] }
                    local names = {}
                    for item in pairs(H.REAGENTS[id] or {}) do names[#names + 1] = H.ITEMS[item] end
                    table.sort(names)
                    if #names > 0 then self.lines[2] = "Reagents: " .. table.concat(names, ", ") end
                end
            end
        end
        -- What it says now, a line each, joined with " | "; nil when hidden.
        function G:Said() return self.shown and table.concat(self.lines, " | ") or nil end
    end
    env.GameTooltip = tip
    env.C_XMLUtil = { GetTemplateInfo = function(name)
        if P.TemplateMissing(c, name) then return nil end
        return { type = "Frame", width = 0, height = 0, keyValues = {} }
    end }
    env.PanelTemplates_SelectTab = function(tab) tab.selectedTab = true end
    env.PanelTemplates_DeselectTab = function(tab) tab.selectedTab = false end
    local _ = w
end
