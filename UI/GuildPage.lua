---@class Proff
local ns = select(2, ...)

-- The Guild tab's page (UI/GuildTab.lua shows it): a search box, a profession filter, a help icon, and the
-- guild's recipes in a dense list (icon, recipe, profession, who knows it), the recipe's spell tooltip on
-- hover. Searching is ns.Index's (a recipe's name, its profession, who knows it, its reagents).
--
-- The list is virtual: a fixed set of rows (as many as fit) in a scroll frame as tall as every result, each
-- row moved to and filled with the result at its place when the list scrolls. A few hundred results cost the
-- same as twenty.
--
-- Built the first time the tab opens; refreshed only while shown (a profession stored, members pruned, reagent
-- names arriving).
---@class Proff.GuildPage
local Page = { query = "", line = nil, results = {}, rows = {}, total = 0 }
ns.GuildPage = Page

local ROW = ns.Config.ROW_HEIGHT
local TOP = 40           -- px from the page's top to the list (clear of the window's portrait)
local HEAD = 16          -- the column headings
local PROF_W, WHO_W = 100, 210
local QUESTION = 134400  -- INV_Misc_QuestionMark: a recipe without an icon
local HELP_ICON = "Interface\\Common\\help-i"

local frame, box, filter, help, count, inset, scroll, child, empty

local function Template(name) return ns.GuildTab.Template(name) end

-- "Kari Berg, Siri Dahl": who knows it, the player first as "you".
function Page.Holders(holders)
    local me = ns.PlayerKey()
    local out, mine = {}, false
    for _, who in ipairs(holders) do
        if who == me then mine = true else out[#out + 1] = who end
    end
    if mine then table.insert(out, 1, ns.L["tab.you"]) end
    return table.concat(out, ", ")
end

------------------------------------------------------------------------------
-- Rows
------------------------------------------------------------------------------
local function Tooltip(row)
    local r = row.data
    if not r then return end
    local tip = GameTooltip
    tip:SetOwner(row, "ANCHOR_RIGHT")
    -- The recipe's spell, as the profession window shows it (a recipe id is its spell's). A client without it
    -- (or a spell it doesn't know) gets the name and the reagents we stored.
    local ok = pcall(tip.SetSpellByID, tip, r.id)
    if not ok or (tip:NumLines() or 0) == 0 then
        tip:SetText(r.name, 1, 1, 1)
        if #r.reagents > 0 then
            tip:AddLine(ns.L["tip.reagents"], 1, 0.82, 0)
            for _, re in ipairs(r.reagents) do
                tip:AddLine(ns.T("tip.reagent", { n = re.count, name = re.name or ("#" .. re.id) }), 1, 1, 1)
            end
        end
    end
    tip:AddLine(" ")
    tip:AddLine(ns.T("tip.known", { prof = r.prof }), 1, 0.82, 0)
    tip:AddLine(Page.Holders(r.holders), 1, 1, 1, true)
    tip:Show()
    ns.Log("Page", "tooltip: %s", ok and "the spell's" or "ours")
end

local function NewRow(i)
    local row = CreateFrame("Button", nil, child)
    row:SetHeight(ROW)
    row.stripe = row:CreateTexture(nil, "BACKGROUND")
    row.stripe:SetAllPoints()
    row.stripe:SetColorTexture(1, 1, 1, 0.04)
    row.hl = row:CreateTexture(nil, "HIGHLIGHT")
    row.hl:SetAllPoints()
    row.hl:SetColorTexture(1, 0.82, 0, 0.12)
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(ROW - 2, ROW - 2)
    row.icon:SetPoint("LEFT", row, "LEFT", 2, 0)
    row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    row.who = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.who:SetPoint("RIGHT", row, "RIGHT", -4, 0)
    row.who:SetWidth(WHO_W)
    row.who:SetJustifyH("LEFT")
    row.who:SetWordWrap(false)
    row.prof = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    row.prof:SetPoint("RIGHT", row.who, "LEFT", -8, 0)
    row.prof:SetWidth(PROF_W)
    row.prof:SetJustifyH("LEFT")
    row.prof:SetWordWrap(false)
    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.name:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
    row.name:SetPoint("RIGHT", row.prof, "LEFT", -8, 0)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)
    row:SetScript("OnEnter", Tooltip)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    Page.rows[i] = row
    return row
end

local function Bind(row, r, index)
    row.data = r
    row.icon:SetTexture(r.icon or QUESTION)
    row.name:SetText(r.name)
    row.prof:SetText(r.prof)
    row.who:SetText(Page.Holders(r.holders))
    row.stripe:SetShown(index % 2 == 0)
end

-- How many rows fit (one more, for the one half in view at the bottom).
local function Fit()
    local h = scroll:GetHeight()
    if not h or h <= 0 then return 24 end
    return math.ceil(h / ROW) + 1
end

-- The rows at the scroll's place.
function Page:Draw()
    if not frame then return end
    local first = math.floor((scroll:GetVerticalScroll() or 0) / ROW)
    local n = Fit()
    for i = 1, n do
        local index = first + i
        local r = self.results[index]
        local row = self.rows[i] or (r and NewRow(i))
        if row then
            if r then
                row:ClearAllPoints()
                row:SetPoint("TOPLEFT", child, "TOPLEFT", 0, -(index - 1) * ROW)
                row:SetPoint("RIGHT", child, "RIGHT", 0, 0)
                Bind(row, r, index)
                row:Show()
                -- (the mouse may rest on a row whose recipe just changed under it)
                if GameTooltip:IsOwned(row) then Tooltip(row) end
            else
                row.data = nil
                row:Hide()
            end
        end
    end
    for i = n + 1, #self.rows do self.rows[i].data = nil; self.rows[i]:Hide() end
end

------------------------------------------------------------------------------
-- What's shown
------------------------------------------------------------------------------
function Page:Refresh()
    if not frame then return end
    local guild = ns.GuildKey()
    local rows, total = {}, 0
    if guild then
        rows, total = ns.Index:Search(guild, self.query, { line = self.line, all = true, limit = math.huge })
    end
    self.results, self.total = rows, total
    child:SetHeight(math.max(1, #rows * ROW))
    count:SetText(ns.T("tab.count", { n = total }))
    if not guild then
        empty:SetText(ns.L["tab.noguild"])
    elseif ns.Index:Stats(guild).recipes == 0 then
        empty:SetText(ns.L["tab.empty"])
    elseif #rows == 0 then
        empty:SetText(ns.T("tab.nomatch", { q = self.query }))
    end
    empty:SetShown(#rows == 0)
    local regenerate = rawget(filter, "GenerateMenu")
    if regenerate then regenerate(filter) end
    self:Draw()
    ns.Log("Page", "%d shown for \"%s\"%s", total, self.query, self.line and (" in line " .. self.line) or "")
end

function Page:SetQuery(text)
    text = (text or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if text == self.query then return end
    self.query = text
    scroll:SetVerticalScroll(0)
    self:Refresh()
end

-- A profession's skill line, or nil for all of them.
function Page:SetLine(line)
    if line == self.line then return end
    self.line = line
    scroll:SetVerticalScroll(0)
    self:Refresh()
end

local RefreshSoon = ns.Debounce(0.2, function()
    if frame and frame:IsVisible() then Page:Refresh() end
end)
for _, event in ipairs({ "STORED", "PRUNED", "ITEMS" }) do ns.Bus:On(event, Page, function() RefreshSoon() end) end

------------------------------------------------------------------------------
-- Building
------------------------------------------------------------------------------
local function SearchBox()
    local b = CreateFrame("EditBox", nil, frame, Template("SearchBoxTemplate") or Template("InputBoxTemplate"))
    b:SetSize(220, 20)
    b:SetPoint("TOPLEFT", frame, "TOPLEFT", 70, -10)
    b:SetAutoFocus(false)
    b:SetMaxLetters(60)
    local hint = rawget(b, "Instructions")
    if hint then hint:SetText(ns.L["tab.search"]) end
    -- (hooked: the template's own OnTextChanged shows and hides its instruction and clear button)
    b:HookScript("OnTextChanged", function(self) Page:SetQuery(self:GetText()) end)
    b:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    b:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    return b
end

-- Every profession the guild has recipes of, and "all": a radio each.
function Page.FilterMenu(_, root)
    root:CreateRadio(ns.L["tab.all"], function() return Page.line == nil end, function() Page:SetLine(nil) end)
    local guild = ns.GuildKey()
    for _, p in ipairs(guild and ns.Index:Professions(guild) or {}) do
        root:CreateRadio(ns.T("tab.prof", { name = p.name, n = p.recipes }),
            function() return Page.line == p.line end, function() Page:SetLine(p.line) end)
    end
end

local function Filter()
    local dd
    if Template("WowStyle1DropdownTemplate") then
        dd = CreateFrame("DropdownButton", nil, frame, "WowStyle1DropdownTemplate")
        dd:SetupMenu(Page.FilterMenu)
    else
        -- (no menu dropdown on this client: a button that steps through the professions)
        dd = CreateFrame("Button", nil, frame, Template("UIPanelButtonTemplate"))
        dd:SetScript("OnClick", function(self)
            local guild = ns.GuildKey()
            local lines = { false }
            for _, p in ipairs(guild and ns.Index:Professions(guild) or {}) do lines[#lines + 1] = p.line end
            local at = 1
            for i, l in ipairs(lines) do if l == (Page.line or false) then at = i end end
            Page:SetLine(lines[at % #lines + 1] or nil)
            self:SetText(Page.line and ns.Index:Build(guild).profNames[Page.line] or ns.L["tab.all"])
        end)
        dd:SetText(ns.L["tab.all"])
    end
    dd:SetSize(170, 22)
    dd:SetPoint("LEFT", box, "RIGHT", 12, 0)
    return dd
end

local function Help()
    local b = CreateFrame("Button", nil, frame)
    b:SetSize(22, 22)
    b:SetPoint("LEFT", filter, "RIGHT", 8, 0)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetAllPoints()
    b.icon:SetTexture(HELP_ICON)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(ns.L["help.title"], 1, 1, 1)
        GameTooltip:AddLine(ns.L["help.search"], 1, 0.82, 0, true)
        GameTooltip:AddLine(ns.L["help.filter"], 1, 0.82, 0, true)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(ns.L["help.where"], 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return b
end

local function Heading(text, point, x, width)
    local fs = inset:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    fs:SetPoint(point, inset, point, x, -4)
    fs:SetJustifyH("LEFT")
    if width then fs:SetWidth(width) end
    fs:SetText(text)
    return fs
end

function Page:Build(f)
    frame = f
    box = SearchBox()
    filter = Filter()
    help = Help()
    count = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    count:SetPoint("TOPRIGHT", f, "TOPRIGHT", -14, -14)
    inset = CreateFrame("Frame", nil, f, Template("InsetFrameTemplate"))
    inset:SetPoint("TOPLEFT", f, "TOPLEFT", 4, -TOP)
    inset:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -6, 4)
    -- (the columns' right edges as the rows': the scroll bar's 26 px, then the row's own padding)
    Heading(ns.L["tab.col.recipe"], "TOPLEFT", 6 + ROW + 4)
    Heading(ns.L["tab.col.who"], "TOPRIGHT", -(26 + 4), WHO_W)
    Heading(ns.L["tab.col.prof"], "TOPRIGHT", -(26 + 4 + WHO_W + 8), PROF_W)
    scroll = CreateFrame("ScrollFrame", nil, inset, Template("UIPanelScrollFrameTemplate"))
    -- (Blizzard's template hides its bar while there's nothing to scroll, if asked: Dyreparken's lesson)
    scroll.scrollBarHideable = true
    scroll:SetPoint("TOPLEFT", inset, "TOPLEFT", 4, -(4 + HEAD))
    scroll:SetPoint("BOTTOMRIGHT", inset, "BOTTOMRIGHT", -26, 4)
    child = CreateFrame("Frame", nil, scroll)
    child:SetSize(1, 1)
    scroll:SetScrollChild(child)
    scroll:HookScript("OnVerticalScroll", function() Page:Draw() end)
    scroll:HookScript("OnSizeChanged", function(self, w)
        child:SetWidth(w or self:GetWidth() or 1)
        Page:Draw()
    end)
    empty = inset:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    empty:SetPoint("TOPLEFT", inset, "TOPLEFT", 20, -60)
    empty:SetPoint("TOPRIGHT", inset, "TOPRIGHT", -20, -60)
    empty:SetJustifyH("CENTER")
    f:HookScript("OnShow", function()
        child:SetWidth(scroll:GetWidth() or 1)
        ns.Items:WantAll()
        Page:Refresh()
    end)
    f:HookScript("OnHide", function() box:ClearFocus() end)
    self.box, self.filter, self.help, self.count, self.scroll, self.empty = box, filter, help, count, scroll, empty
    ns.Log("Page", "built: search %s, filter %s", tostring(Template("SearchBoxTemplate")),
        tostring(Template("WowStyle1DropdownTemplate")))
end
