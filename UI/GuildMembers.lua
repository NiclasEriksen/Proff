---@class Proff
local ns = select(2, ...)

-- The Guild tab's Members view (UI/GuildTab.lua switches to it): who has which profession, at what skill. One
-- slim column per profession, only its icon on top (its name on hover), a cell holding the member's skill or
-- nothing; a member's name first. Clicking a column sorts by it: who has it first, highest skill first, then by
-- first name; the name column sorts by name. A thin first column holds a green dot for who's online (sorts them
-- first, the view's sort when it opens); offline names are grey (the user, 2026-11-25). Data: ns.Skills (the server's guild profession roster and
-- the guild's club, merged with the ranks Proff stored with recipes), asked for when the view shows.
--
-- A virtual list like the Recipes view's: rows for what's in view, moved along as it scrolls.
---@class Proff.GuildMembers
-- (sorted by who's online at first: the user, 2026-11-25)
local Members = { sort = "online", rows = {}, data = {}, columns = {}, heads = {}, bands = {} }
ns.GuildMembers = Members

local ROW = ns.Config.ROW_HEIGHT
local TOP = 40           -- px from the view's top to the list (clear of the window's portrait)
local HEAD = 24          -- the column heads (icons)
local DOT_W = 16         -- the online column
local NAME_W = 170
local COL_W = 34
local LEFT = DOT_W + NAME_W   -- where the profession columns start
local DOT = "Interface\\FriendsFrame\\StatusIcon-Online"

local frame, inset, scroll, child, empty, count, nameHead, dotHead

local function Template(name) return ns.GuildTab.Template(name) end

-- A member's name in their class color, grey while offline.
local function NameText(r)
    local colors = rawget(_G, "RAID_CLASS_COLORS")
    local c = type(r.class) == "string" and colors and colors[r.class]
    if r.online == false then return "|cff808080" .. r.who .. "|r" end
    if c and c.colorStr then return "|c" .. c.colorStr .. r.who .. "|r" end
    return r.who
end
Members.NameText = NameText

-- A skill's color (the user, 2026-11-23): 300 (the cap) light blue, 225 and up orange, 150 yellow, 75 green, below
-- that grey.
function Members.SkillColor(s)
    if s >= 300 then return "66ccff" end
    if s >= 225 then return "ff8040" end
    if s >= 150 then return "ffff00" end
    if s >= 75 then return "40c040" end
    return "808080"
end

-- A cell: the skill in its color; "?" when they have it but the skill's unknown; nothing without it.
local function Cell(r, line)
    local s = r.skills[line]
    if s then return "|cff" .. Members.SkillColor(s) .. s .. "|r" end
    if r.recipes[line] or r.has[line] then return "|cff808080?|r" end
    return ""
end
Members.Cell = Cell

------------------------------------------------------------------------------
-- Rows
------------------------------------------------------------------------------
local function RowTooltip(row)
    local r = row.data
    if not r then return end
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    GameTooltip:SetText(r.who, 1, 1, 1)
    for _, c in ipairs(Members.columns) do
        local s, n = r.skills[c.line], r.recipes[c.line]
        if s or n or r.has[c.line] then
            local text = ns.T("members.tip.skill", { prof = c.name,
                skill = s and ("|cff" .. Members.SkillColor(s) .. s .. "|r") or "?" })
            if n then text = text .. ns.T("members.tip.recipes", { n = n }) end
            GameTooltip:AddLine(text, 1, 0.82, 0)
        end
    end
    if r.online == false then GameTooltip:AddLine(ns.L["members.offline"], 0.5, 0.5, 0.5) end
    GameTooltip:Show()
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
    row.dot = row:CreateTexture(nil, "ARTWORK")
    row.dot:SetSize(10, 10)
    row.dot:SetPoint("LEFT", row, "LEFT", (DOT_W - 10) / 2, 0)
    row.dot:SetTexture(DOT)
    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.name:SetPoint("LEFT", row, "LEFT", DOT_W + 4, 1)
    row.name:SetWidth(NAME_W - 8)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)
    row.cells, row.fills = {}, {}
    row:SetScript("OnEnter", RowTooltip)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    Members.rows[i] = row
    return row
end

-- A cell's fill (the grid: who has a profession shows as a box, the user 2026-11-23): its skill's band color,
-- faint; grey for "has it, skill unknown"; none without it. r, g, b, a or nil.
function Members.Fill(r, line)
    local s = r.skills[line]
    if s then
        local hex = Members.SkillColor(s)
        return tonumber(hex:sub(1, 2), 16) / 255, tonumber(hex:sub(3, 4), 16) / 255, tonumber(hex:sub(5, 6), 16) / 255, 0.22
    end
    if r.recipes[line] or r.has[line] then return 0.6, 0.6, 0.6, 0.16 end
end

local function Bind(row, r, index)
    row.data = r
    row.name:SetText(NameText(r))
    row.dot:SetShown(r.online == true)
    for i, c in ipairs(Members.columns) do
        local fs = row.cells[i]
        if not fs then
            -- The whole cell but the column's line (its first pixel: Members' grid lines, DrawHeads).
            local x = LEFT + (i - 1) * COL_W
            row.fills[i] = row:CreateTexture(nil, "BORDER")
            row.fills[i]:SetPoint("TOPLEFT", row, "TOPLEFT", x + 1, 0)
            row.fills[i]:SetSize(COL_W - 1, ROW)
            -- (centered in the cell both ways; the small font sits a pixel low in its box: lifted by one)
            fs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            fs:SetPoint("TOPLEFT", row, "TOPLEFT", x + 1, 1)
            fs:SetSize(COL_W - 1, ROW)
            fs:SetJustifyH("CENTER")
            fs:SetJustifyV("MIDDLE")
            row.cells[i] = fs
        end
        fs:SetText(Cell(r, c.line))
        fs:Show()
        local fr, fg, fb, fa = Members.Fill(r, c.line)
        if fr then row.fills[i]:SetColorTexture(fr, fg, fb, fa) end
        row.fills[i]:SetShown(fr ~= nil)
    end
    for i = #Members.columns + 1, #row.cells do row.cells[i]:Hide(); row.fills[i]:Hide() end
    row.stripe:SetShown(index % 2 == 0)
end

local function Fit()
    local h = scroll:GetHeight()
    if not h or h <= 0 then return 24 end
    return math.ceil(h / ROW) + 1
end

function Members:Draw()
    if not frame then return end
    local first = math.floor((scroll:GetVerticalScroll() or 0) / ROW)
    local n = Fit()
    for i = 1, n do
        local index = first + i
        local r = self.data[index]
        local row = self.rows[i] or (r and NewRow(i))
        if row then
            if r then
                row:ClearAllPoints()
                row:SetPoint("TOPLEFT", child, "TOPLEFT", 0, -(index - 1) * ROW)
                row:SetPoint("RIGHT", child, "RIGHT", 0, 0)
                Bind(row, r, index)
                row:Show()
                if GameTooltip:IsOwned(row) then RowTooltip(row) end
            else
                row.data = nil
                row:Hide()
            end
        end
    end
    for i = n + 1, #self.rows do self.rows[i].data = nil; self.rows[i]:Hide() end
end

------------------------------------------------------------------------------
-- Column heads
------------------------------------------------------------------------------
local function HeadTooltip(head)
    local c = head.column
    if not c then return end
    GameTooltip:SetOwner(head, "ANCHOR_TOP")
    GameTooltip:SetText(c.name or ("#" .. c.line), 1, 1, 1)
    GameTooltip:AddLine(ns.T("members.tip.have", { n = head.holders or 0 }), 1, 0.82, 0)
    GameTooltip:AddLine(ns.L["members.tip.sort"], 0.7, 0.7, 0.7)
    GameTooltip:Show()
end

local function Head(i)
    local h = Members.heads[i]
    if h then return h end
    h = CreateFrame("Button", nil, inset)
    h:SetSize(COL_W, HEAD)
    h:SetPoint("TOPLEFT", inset, "TOPLEFT", 4 + LEFT + (i - 1) * COL_W, -3)
    h.sorted = h:CreateTexture(nil, "BACKGROUND")
    h.sorted:SetAllPoints()
    h.sorted:SetColorTexture(1, 0.82, 0, 0.18)
    h.icon = h:CreateTexture(nil, "ARTWORK")
    h.icon:SetSize(HEAD - 6, HEAD - 6)
    h.icon:SetPoint("CENTER")
    h.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    h.hl = h:CreateTexture(nil, "HIGHLIGHT")
    h.hl:SetAllPoints()
    h.hl:SetColorTexture(1, 1, 1, 0.12)
    h:SetScript("OnClick", function(self) Members:SetSort(self.column and self.column.line) end)
    h:SetScript("OnEnter", HeadTooltip)
    h:SetScript("OnLeave", function() GameTooltip:Hide() end)
    Members.heads[i] = h
    return h
end

function Members:Line(i)
    local line = self.bands[i]
    if not line then
        local x = 4 + LEFT + (i - 1) * COL_W
        line = inset:CreateTexture(nil, "ARTWORK")
        line:SetPoint("TOPLEFT", inset, "TOPLEFT", x, -3)
        line:SetPoint("BOTTOMLEFT", inset, "BOTTOMLEFT", x, 4)
        line:SetWidth(1)
        line:SetColorTexture(1, 1, 1, 0.08)
        self.bands[i] = line
    end
    line:Show()
end

local function DrawHeads()
    for i, c in ipairs(Members.columns) do
        local h = Head(i)
        h.column = c
        h.icon:SetTexture(c.icon or 134400)
        local n = 0
        for _, r in ipairs(Members.data) do if r.skills[c.line] or r.recipes[c.line] or r.has[c.line] then n = n + 1 end end
        h.holders = n
        h.sorted:SetShown(Members.sort == c.line)
        h:Show()
        -- The grid: a one-pixel line on each column's left edge, the list's height (and one after the last).
        Members:Line(i)
    end
    Members:Line(#Members.columns + 1)
    for i = #Members.columns + 1, #Members.heads do Members.heads[i].column = nil; Members.heads[i]:Hide() end
    for i = #Members.columns + 2, #Members.bands do Members.bands[i]:Hide() end
    nameHead.sorted:SetShown(Members.sort == nil)
    dotHead.sorted:SetShown(Members.sort == "online")
end

------------------------------------------------------------------------------
-- What's shown
------------------------------------------------------------------------------
function Members:Refresh()
    if not frame then return end
    local guild = ns.GuildKey()
    local cols, rows = {}, {}
    if guild then cols, rows = ns.Skills:Table(guild) end
    -- (a sort by a profession nobody shows any more: the default, online)
    local still = self.sort == nil or self.sort == "online"
    for _, c in ipairs(cols) do if c.line == self.sort then still = true end end
    if not still then self.sort = "online" end
    self.columns, self.data = cols, ns.Skills.Sort(rows, self.sort)
    child:SetHeight(math.max(1, #rows * ROW))
    count:SetText(ns.T("members.count", { n = #rows }))
    if not guild then
        empty:SetText(ns.L["tab.noguild"])
    elseif #rows == 0 then
        empty:SetText(ns.Skills.busy and ns.L["members.asking"] or ns.L["members.empty"])
    end
    empty:SetShown(#rows == 0)
    DrawHeads()
    self:Draw()
    ns.Log("Page", "members: %d shown, %d professions, sorted by %s", #rows, #cols, tostring(self.sort or "name"))
end

-- Sort by a profession's skill line, by "online", or by name (nil).
function Members:SetSort(line)
    self.sort = line
    scroll:SetVerticalScroll(0)
    self:Refresh()
end

local RefreshSoon = ns.Debounce(0.2, function()
    if frame and frame:IsVisible() then Members:Refresh() end
end)
for _, event in ipairs({ "SKILLS", "STORED", "PRUNED", "ROSTER" }) do ns.Bus:On(event, Members, function() RefreshSoon() end) end

------------------------------------------------------------------------------
-- Building
------------------------------------------------------------------------------
function Members:Build(f)
    frame = f
    local hint = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("TOPLEFT", f, "TOPLEFT", 70, -14)
    hint:SetText(ns.L["members.hint"])
    count = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    count:SetPoint("TOPRIGHT", f, "TOPRIGHT", -14, -14)
    inset = CreateFrame("Frame", nil, f, Template("InsetFrameTemplate"))
    inset:SetPoint("TOPLEFT", f, "TOPLEFT", 4, -TOP)
    inset:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -6, 4)
    dotHead = CreateFrame("Button", nil, inset)
    dotHead:SetSize(DOT_W, HEAD)
    dotHead:SetPoint("TOPLEFT", inset, "TOPLEFT", 4, -3)
    dotHead.sorted = dotHead:CreateTexture(nil, "BACKGROUND")
    dotHead.sorted:SetAllPoints()
    dotHead.sorted:SetColorTexture(1, 0.82, 0, 0.18)
    dotHead.icon = dotHead:CreateTexture(nil, "ARTWORK")
    dotHead.icon:SetSize(10, 10)
    dotHead.icon:SetPoint("CENTER")
    dotHead.icon:SetTexture(DOT)
    dotHead:SetScript("OnClick", function() Members:SetSort("online") end)
    dotHead:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(ns.L["members.col.online"], 1, 1, 1)
        GameTooltip:AddLine(ns.L["members.tip.sort"], 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)
    dotHead:SetScript("OnLeave", function() GameTooltip:Hide() end)
    nameHead = CreateFrame("Button", nil, inset)
    nameHead:SetSize(NAME_W, HEAD)
    nameHead:SetPoint("TOPLEFT", inset, "TOPLEFT", 4 + DOT_W, -3)
    nameHead.sorted = nameHead:CreateTexture(nil, "BACKGROUND")
    nameHead.sorted:SetAllPoints()
    nameHead.sorted:SetColorTexture(1, 0.82, 0, 0.18)
    nameHead.label = nameHead:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    nameHead.label:SetPoint("LEFT", nameHead, "LEFT", 4, 0)
    nameHead.label:SetText(ns.L["members.col.name"])
    nameHead:SetScript("OnClick", function() Members:SetSort(nil) end)
    scroll = CreateFrame("ScrollFrame", nil, inset, Template("UIPanelScrollFrameTemplate"))
    scroll.scrollBarHideable = true
    scroll:SetPoint("TOPLEFT", inset, "TOPLEFT", 4, -(4 + HEAD))
    scroll:SetPoint("BOTTOMRIGHT", inset, "BOTTOMRIGHT", -26, 4)
    child = CreateFrame("Frame", nil, scroll)
    child:SetSize(1, 1)
    scroll:SetScrollChild(child)
    scroll:HookScript("OnVerticalScroll", function() Members:Draw() end)
    scroll:HookScript("OnSizeChanged", function(self, w)
        child:SetWidth(w or self:GetWidth() or 1)
        Members:Draw()
    end)
    empty = inset:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    empty:SetPoint("TOPLEFT", inset, "TOPLEFT", 20, -60)
    empty:SetPoint("TOPRIGHT", inset, "TOPRIGHT", -20, -60)
    empty:SetJustifyH("CENTER")
    f:HookScript("OnShow", function()
        child:SetWidth(scroll:GetWidth() or 1)
        ns.Guild:Refresh()
        ns.Skills:Refresh()
        Members:Refresh()
    end)
    self.scroll, self.empty, self.count, self.nameHead, self.dotHead = scroll, empty, count, nameHead, dotHead
end
