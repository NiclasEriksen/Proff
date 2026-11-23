---@class Proff
local ns = select(2, ...)

-- The profession window's "Guild" tab: a side tab under the window's profession tabs that shows our page
-- (UI/GuildPage.lua) over the window's content.
--
-- Forever's profession window isn't retail's (seen 2026-11-23): no tab bar at the bottom, but one icon tab per
-- profession down the RIGHT edge, `ProfessionsFrame.rightProfessionTabs` (ForeverRecipes uses it: buttons
-- with .skillLine and an OnClick that switches profession), drawn like the Collections window's side tabs
-- (Dyreparken's docs/FOREVER_API.md: atlases common-sidetab, -mask, -selected, -hover). How many there are
-- depends on the character, so ours goes under the last one shown, the same size and spacing, and moves
-- whenever one of theirs shows or hides.
--
-- TAINT AND COMBAT (Dyreparken's SidePage, on the Collections window): we never touch Blizzard's tab list,
-- call a tab's OnClick or hide its pages. Our page COVERS the content below the title bar, above whatever
-- shows: its frame level is set above the highest of the window's parts each time it opens (the overview's
-- rank bars sit high: they showed through, 2026-11-23). While it's up, the selected profession tab's
-- highlight is hidden (textures only) and the window's border, portrait, title and close button are lifted
-- above the page (frame levels only). We leave when:
--   * one of the profession tabs is pressed (OnMouseDown, hooked) or its OnClick runs (hooksecurefunc),
--   * our tab is pressed again,
--   * the window hides.
-- Attached when the window first exists (Blizzard's profession UI loads on demand: see the end of this file).
---@class Proff.GuildTab
local GuildTab = {}
ns.GuildTab = GuildTab

local TITLE_H = 21
local ICON = "Interface\\Icons\\INV_Shirt_GuildTabard_01"
-- Parts of the window drawn over its edges: above our page while it's up.
local LIFT = { "NineSlice", "PortraitContainer", "TitleContainer", "CloseButton" }
local STRATA = { BACKGROUND = 1, LOW = 2, MEDIUM = 3, HIGH = 4, DIALOG = 5, FULLSCREEN = 6, FULLSCREEN_DIALOG = 7,
    TOOLTIP = 8 }

local host, tab, cover
local lifted = {}         -- frame -> its level before we lifted it
local hidden = {}         -- the selected highlights of their tabs we hid
local hooked = setmetatable({}, { __mode = "k" })

-- A template the client has (C_XMLUtil.GetTemplateInfo), or nil.
function GuildTab.Template(name)
    local X = C_XMLUtil
    if type(X) == "table" and ns.Read(X.GetTemplateInfo, name) then return name end
    return nil
end

-- A mixin's method or parentKey of a Blizzard frame: a plain field, so rawget (no error if it isn't there).
local function Field(f, k) return type(f) == "table" and rawget(f, k) or nil end

function GuildTab:Host() return host end
function GuildTab:Tab() return tab end
function GuildTab:IsOpen() return cover ~= nil and cover:IsVisible() end

------------------------------------------------------------------------------
-- Their tabs
------------------------------------------------------------------------------
-- The profession tabs shown, top to bottom (by position once laid out, else in the list's order).
function GuildTab:ProfessionTabs()
    local out = {}
    for i, t in ipairs(Field(host, "rightProfessionTabs") or {}) do
        if t ~= tab and t.IsShown and t:IsShown() then out[#out + 1] = { t, t:GetTop(), i } end
    end
    table.sort(out, function(a, b)
        if a[2] and b[2] and a[2] ~= b[2] then return a[2] > b[2] end
        return a[3] < b[3]
    end)
    for i, e in ipairs(out) do out[i] = e[1] end
    return out
end

-- A tab's "selected" highlight: its FIRST texture with "selected" in its atlas. Forever's profession tabs have
-- two common-sidetab-selected textures; the second is shown on every tab (part of the look), the first only on
-- the open profession's (/proff probe window, 2026-11-23).
local function Highlight(f)
    for _, r in ipairs({ f:GetRegions() }) do
        local atlas = r.GetAtlas and r:GetAtlas()
        if type(atlas) == "string" and atlas:find("selected", 1, true) then return r end
    end
end

-- Their other tabs that leave our page when pressed: the overview's (Professions, its rank bars), not a
-- profession tab.
local OTHER_TABS = { "ProfessionsOverviewTab" }

------------------------------------------------------------------------------
-- Layout
------------------------------------------------------------------------------
-- The highest frame level and strata among the window's parts (ours and the lifted ones aside), a few levels
-- down: what our page must be above.
local function Highest()
    local level, strata = host:GetFrameLevel(), host:GetFrameStrata()
    local skip = {}
    if cover then skip[cover] = true end
    if tab then skip[tab] = true end
    for _, key in ipairs(LIFT) do local f = Field(host, key); if f then skip[f] = true end end
    local function Walk(f, depth)
        for _, ch in ipairs({ f:GetChildren() }) do
            if not skip[ch] and ch:IsShown() then
                level = math.max(level, ch:GetFrameLevel() or 0)
                local s = ch:GetFrameStrata()
                if (STRATA[s] or 0) > (STRATA[strata] or 0) then strata = s end
                if depth < 6 then Walk(ch, depth + 1) end
            end
        end
    end
    Walk(host, 1)
    return level, strata
end

local LayoutSoon -- (below)

-- Under the last profession tab, as far from it as they are from each other (2 px, Dyreparken's), its size.
-- Without any (a linked or NPC window may show none): at the window's right edge, under the title bar.
function GuildTab:Layout()
    if not tab then return end
    local tabs = self:ProfessionTabs()
    for _, t in ipairs(tabs) do self:Hook(t) end
    for _, key in ipairs(OTHER_TABS) do
        local t = Field(host, key)
        if t and t.HookScript then self:Hook(t) end
    end
    local last = tabs[#tabs]
    -- A size from anchors is 0 until the client lays the frame out: not shown until theirs have one (each of theirs
    -- says when, OnSizeChanged). (In game they had theirs at once, 2026-11-23; this is in case.)
    local w, h = 55, 55
    if last then
        w, h = last:GetSize()
        if not (w and w > 0 and h and h > 0) then
            tab:Hide()
            return ns.Log("Tab", "layout: their tabs have no size yet")
        end
    end
    if not tab.art then self:Paint(tabs) end
    tab:ClearAllPoints()
    if last then
        local gap = 2
        local a, b = #tabs >= 2 and tabs[#tabs - 1]:GetBottom(), last:GetTop()
        if a and b then gap = math.max(0, a - b) end
        tab:SetPoint("TOPLEFT", last, "BOTTOMLEFT", 0, -gap)
    else
        tab:SetPoint("TOPLEFT", host, "TOPRIGHT", 0, -(TITLE_H + 40))
    end
    tab:SetSize(w, h)
    if last then tab:SetFrameLevel(last:GetFrameLevel()) end
    tab:Show()
    ns.Log("Tab", "layout: %d profession tabs, ours %s, %dx%d", #tabs, last and "under the last" or "at the window's edge",
        w, h)
end

-- One of their tabs: leaving our page when it's pressed or clicked, laying out again when it shows or hides.
function GuildTab:Hook(t)
    if hooked[t] then return end
    hooked[t] = true
    t:HookScript("OnMouseDown", function() GuildTab:Close() end)
    if type(Field(t, "OnClick")) == "function" then hooksecurefunc(t, "OnClick", function() GuildTab:Close() end) end
    t:HookScript("OnShow", function() LayoutSoon() end)
    t:HookScript("OnHide", function() LayoutSoon() end)
    t:HookScript("OnSizeChanged", function() LayoutSoon() end)
end

LayoutSoon = ns.Debounce(0, function() if host and host:IsShown() then GuildTab:Layout() end end)

------------------------------------------------------------------------------
-- Showing and leaving
------------------------------------------------------------------------------
local function BuildCover()
    local f = CreateFrame("Frame", nil, host)
    f:SetPoint("TOPLEFT", host, "TOPLEFT", 0, -TITLE_H)
    f:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", 0, 0)
    f:EnableMouse(true)
    -- The window's own background (its Bg: a texture or a frame of them), so the page looks part of it.
    f.bg = f:CreateTexture(nil, "BACKGROUND")
    f.bg:SetAllPoints()
    local src = Field(host, "Bg")
    if src and src.GetObjectType and src:GetObjectType() ~= "Texture" then src = (src:GetRegions()) end
    local atlas = src and src.GetAtlas and src:GetAtlas()
    if atlas then
        f.bg:SetAtlas(atlas)
    else
        f.bg:SetColorTexture(0.06, 0.06, 0.07, 1)
    end
    ns.Log("Tab", "page background: %s", atlas and ("atlas " .. atlas) or "plain")
    f:Hide()
    -- Two views, Recipes (each time the page opens) and Members, with their tabs under the window's bottom edge
    -- (the classic look; Forever's window has none of its own there). Ours, children of the page: gone with it.
    f.views, f.tabs = {}, {}
    local prev
    for i, v in ipairs(GuildTab.VIEWS) do
        local view = CreateFrame("Frame", nil, f)
        view:SetAllPoints()
        view:Hide()
        v.module():Build(view)
        f.views[v.id] = view
        local t = CreateFrame("Button", nil, f, GuildTab.Template("PanelTabButtonTemplate"))
        local text = Field(t, "Text") or t:GetFontString()
        if not text then
            text = t:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            text:SetPoint("CENTER")
        end
        text:SetText(ns.L[v.label])
        local resize = rawget(_G, "PanelTemplates_TabResize")
        if not (type(resize) == "function" and pcall(resize, t, 0)) then t:SetSize((text:GetStringWidth() or 40) + 40, 32) end
        -- (retail's tab art doesn't overlap like the classic one did: 3 px apart, as Blizzard's own windows)
        if prev then t:SetPoint("LEFT", prev, "RIGHT", 3, 0) else t:SetPoint("TOPLEFT", host, "BOTTOMLEFT", 12, 2) end
        t:SetScript("OnClick", function() GuildTab:ShowView(v.id) end)
        t.view = v.id
        f.tabs[i] = t
        prev = t
    end
    return f
end

-- The page's views, in tab order.
GuildTab.VIEWS = {
    { id = "recipes", label = "tab.view.recipes", module = function() return ns.GuildPage end },
    { id = "members", label = "tab.view.members", module = function() return ns.GuildMembers end },
}

function GuildTab:View()
    for id, v in pairs(cover and cover.views or {}) do if v:IsShown() then return id end end
end

function GuildTab:ShowView(id)
    if not cover then return end
    for vid, v in pairs(cover.views) do if vid ~= id then v:Hide() end end
    cover.views[id]:Show()
    local sel, desel = rawget(_G, "PanelTemplates_SelectTab"), rawget(_G, "PanelTemplates_DeselectTab")
    for _, t in ipairs(cover.tabs) do
        local fn = t.view == id and sel or desel
        if type(fn) == "function" then pcall(fn, t) end
    end
    ns.Log("Tab", "view %s", id)
end

function GuildTab:Cover() return cover end

function GuildTab:Open()
    if not host then return end
    cover = cover or BuildCover()
    if cover:IsShown() then return end
    local level, strata = Highest()
    cover:SetFrameStrata(strata)
    cover:SetFrameLevel(math.min(level + 10, 9000))
    for _, t in ipairs(self:ProfessionTabs()) do
        local r = Highlight(t)
        if r and r:IsShown() then r:Hide(); hidden[#hidden + 1] = r end
    end
    if tab.selected then tab.selected:Show() end
    -- (all by the same amount, so their own order stays: Dyreparken lifted only the border once, and the
    -- title went under it)
    local low
    for _, key in ipairs(LIFT) do
        local f = Field(host, key)
        if f and f.SetFrameLevel then
            lifted[f] = f:GetFrameLevel()
            low = math.min(low or lifted[f], lifted[f])
        end
    end
    for f, l in pairs(lifted) do
        f:SetFrameStrata(strata)
        f:SetFrameLevel(cover:GetFrameLevel() + 10 + l - low)
    end
    self:ShowView("recipes")
    cover:Show()
    ns.Log("Tab", "opened above level %d (%s)", level, tostring(strata))
end

function GuildTab:Close()
    if not (cover and cover:IsShown()) then return end
    cover:Hide()
    if tab.selected then tab.selected:Hide() end
    -- Their highlight back, unless they've selected a tab since (their own update drew the right one).
    local any = false
    for _, t in ipairs(self:ProfessionTabs()) do
        local r = Highlight(t)
        any = any or (r ~= nil and r:IsShown())
    end
    if not any then for _, r in ipairs(hidden) do r:Show() end end
    hidden = {}
    local strata = host:GetFrameStrata()
    for f, l in pairs(lifted) do
        f:SetFrameStrata(strata)
        f:SetFrameLevel(l)
    end
    lifted = {}
    ns.Log("Tab", "closed")
end

function GuildTab:Toggle()
    if self:IsOpen() then self:Close() else self:Open() end
end

------------------------------------------------------------------------------
-- Attaching to the window
------------------------------------------------------------------------------
-- Our tab's art: a copy of one of their UNSELECTED tabs, every texture as it is there: atlas, layer and
-- sublevel, size, place, shown, alpha, blend mode, color, texture coordinates (a texture can be shown and still
-- not seen: their second common-sidetab-selected is shown on every tab, and copying only "shown" drew ours
-- gold, 2026-11-23). The one without an atlas is the icon (ours instead); the first "selected" is the
-- highlight, hidden until our page is up. Without one of theirs: Forever's side tab as Dyreparken probed it on
-- the Collections window. Painted once, at the first layout where theirs have a size.
local DEFAULT_ART = {
    { "Texture", "BACKGROUND", "common-sidetab", w = 55, h = 60 }, { "Texture", "ARTWORK", w = 50, h = 50 },
    { "MaskTexture", "ARTWORK", "common-sidetab-mask", w = 55, h = 60 },
    { "Texture", "OVERLAY", "common-sidetab-selected", w = 55, h = 60 },
    { "Texture", "HIGHLIGHT", "common-sidetab-hover", w = 55, h = 60 },
}

-- A region's value, or nil when the client lacks the method.
local function Get(r, method)
    local found, fn = pcall(function() return r[method] end)
    if not found or type(fn) ~= "function" then return nil end
    local v = { pcall(fn, r) }
    if not v[1] then return nil end
    table.remove(v, 1)
    return v
end

local function ArtOf(ref)
    local art = {}
    for _, r in ipairs(ref and { ref:GetRegions() } or {}) do
        local size = Get(r, "GetSize") or {}
        local point = Get(r, "GetPoint") or {}
        local layer = Get(r, "GetDrawLayer") or {}
        art[#art + 1] = { r:GetObjectType(), layer[1], (Get(r, "GetAtlas") or {})[1], sub = layer[2],
            w = size[1], h = size[2], shown = r:IsShown(), alpha = (Get(r, "GetAlpha") or {})[1],
            blend = (Get(r, "GetBlendMode") or {})[1], color = Get(r, "GetVertexColor"), coords = Get(r, "GetTexCoord"),
            point = point[2] == ref and point or nil }
    end
    if #art == 0 then return DEFAULT_ART, "default" end
    return art, "copied"
end

-- The tab to copy: a shown one whose highlight is hidden (not the open profession's).
local function Reference(tabs)
    for _, t in ipairs(tabs) do
        local r = Highlight(t)
        if not (r and r:IsShown()) then return t end
    end
    return tabs[1]
end

function GuildTab:Paint(tabs)
    local b = tab
    local ref = Reference(tabs)
    local art, how = ArtOf(ref)
    local masks, icon = {}, nil
    for _, a in ipairs(art) do
        local kind, layer, atlas = a[1], a[2], a[3]
        local t = kind == "MaskTexture" and b:CreateMaskTexture(nil, layer) or b:CreateTexture(nil, layer, nil, a.sub)
        if atlas then t:SetAtlas(atlas) elseif kind == "Texture" and not icon then icon = t; t:SetTexture(ICON) end
        local dw, dh = 55, 60
        if t == icon then dw, dh = 50, 50 end
        t:SetSize((a.w or 0) > 0 and a.w or dw, (a.h or 0) > 0 and a.h or dh)
        if a.point then t:SetPoint(a.point[1], b, a.point[3], a.point[4], a.point[5]) else t:SetPoint("CENTER") end
        if kind == "Texture" then
            if a.alpha then t:SetAlpha(a.alpha) end
            if a.blend then t:SetBlendMode(a.blend) end
            if a.color and t ~= icon then t:SetVertexColor(unpack(a.color)) end
            if a.coords and t ~= icon and #a.coords == 8 then t:SetTexCoord(unpack(a.coords)) end
        else
            masks[#masks + 1] = t
        end
        if kind == "Texture" and type(atlas) == "string" and atlas:find("selected", 1, true) and not b.selected then
            b.selected = t
            t:Hide()
        elseif a.shown == false then
            t:Hide()
        end
    end
    b.icon = icon
    if icon then for _, m in ipairs(masks) do icon:AddMaskTexture(m) end end
    -- (no highlight among theirs: ours must still show selected)
    if not b.selected then
        b.selected = b:CreateTexture(nil, "OVERLAY")
        b.selected:SetAtlas("common-sidetab-selected")
        b.selected:SetSize(55, 60)
        b.selected:SetPoint("CENTER")
        b.selected:Hide()
    end
    b.selected:SetShown(self:IsOpen())
    b.art = how
    ns.Log("Tab", "art %s: %d textures, from line %s", how, #art, tostring(ref and Field(ref, "skillLine")))
end

local function BuildTab()
    local b = CreateFrame("Button", "ProffGuildTab", host)
    b:SetSize(55, 55)
    b:SetScript("OnClick", function() GuildTab:Toggle() end)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(ns.L["tab.title"], 1, 1, 1)
        GameTooltip:AddLine(ns.L["tab.tip"], 1, 0.82, 0, true)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    b:Hide()
    return b
end

function GuildTab:Attach(frame)
    if host then return end
    host = frame
    tab = BuildTab()
    host:HookScript("OnHide", function() GuildTab:Close() end)
    host:HookScript("OnShow", function() LayoutSoon() end)
    ns.Log("Tab", "attached: %d profession tabs", #(Field(host, "rightProfessionTabs") or {}))
    LayoutSoon()
end

-- The window exists once Blizzard's profession UI has loaded (on demand). Forever's window opens on its
-- overview of every profession, with no profession open and no TRADE_SKILL_SHOW (probed 2026-11-23: attached on
-- that event, the tab was missing until a profession was picked). So: attached as soon as the window exists,
-- heard as ADDON_LOADED (whichever addon brought it: no name assumed), or at login if it's already there;
-- TRADE_SKILL_SHOW as well, in case. Then our hooks on the window do the rest, and the events are let go.
local function Try()
    local pf = rawget(_G, "ProfessionsFrame")
    if not pf then return end
    ns.Events:Off("ADDON_LOADED", GuildTab)
    ns.Events:Off("TRADE_SKILL_SHOW", GuildTab)
    GuildTab:Attach(pf)
    -- (already open: its OnShow has passed)
    if pf:IsShown() then LayoutSoon() end
end

ns.Start("login", function()
    if not C_TradeSkillUI then return end
    ns.Events:On("ADDON_LOADED", GuildTab, Try)
    ns.Events:On("TRADE_SKILL_SHOW", GuildTab, Try)
    Try()
end)
