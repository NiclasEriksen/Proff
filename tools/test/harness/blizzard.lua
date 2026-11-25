-- Blizzard's UI as the addon meets it: the templates it inherits (P.TEMPLATES, retail's as Forever has them:
-- Dyreparken's template probe, 2026-11-11), the profession window (P.ProfessionsFrame: retail's ProfessionsFrame
-- with its tab system) and the menu a dropdown opens (H.Menu).
local H, P = ...
local T = P.TEMPLATES

local function Text(f, layer)
    f.Text = f:CreateFontString(nil, layer or "OVERLAY", "GameFontNormalSmall")
    f.fontString = f.Text
end

T.InsetFrameTemplate = function(f) f.Bg = f:CreateTexture(nil, "BACKGROUND") end
T.UIPanelButtonTemplate = function(f) Text(f) end
T.InputBoxTemplate = function() end
-- The instruction shows while the box is empty (the template's own OnTextChanged), a clear button empties it.
T.SearchBoxTemplate = function(f, c)
    f.Instructions = f:CreateFontString(nil, "ARTWORK", "GameFontDisable")
    f.clearButton = P.NewFrame(c, "Button", nil, f)
    f.clearButton:SetScript("OnClick", function() f:SetText(""); f:ClearFocus() end)
    f:SetScript("OnTextChanged", function(self) self.Instructions:SetShown(self:GetText() == "") end)
end
T.UIPanelScrollFrameTemplate = function(f, c)
    f.ScrollBar = P.NewFrame(c, "Frame", nil, f)
    f:SetScript("OnVerticalScroll", function(self, v) self.ScrollBar.value = v end)
end
T.PanelTabButtonTemplate = function(f) Text(f) end
-- Retail's TabSystemButtonArtMixin: the look, and SetTabSelected; TabSystemButtonMixin adds the click.
T.TabSystemButtonArtTemplate = function(f)
    Text(f)
    f.SetTabSelected = function(self, on) self.isSelected = on and true or false end
end
T.TabSystemButtonTemplate = function(f, c)
    T.TabSystemButtonArtTemplate(f, c)
    f:SetScript("OnClick", function(self) self:GetParent():SetTab(self.tabID) end)
end
T.TabSystemTemplate = function(f)
    f.tabs = {}
    f.SetTab = function(self, id) self.owner:SetTab(id) end
    f.SetTabVisuallySelected = function(self, id)
        for _, t in ipairs(self.tabs) do t:SetTabSelected(t.tabID == id) end
    end
end

-- A menu dropdown (WowStyle1DropdownTemplate): SetupMenu keeps the generator, GenerateMenu runs it and the
-- dropdown's text is the selected radio's.
T.WowStyle1DropdownTemplate = function(f)
    Text(f)
    f.SetupMenu = function(self, gen) self.generator = gen; self:GenerateMenu() end
    f.GenerateMenu = function(self)
        local entries = H.Menu(self)
        for _, e in ipairs(entries) do if e.selected then self.Text:SetText(e.text) end end
    end
end

-- The entries the dropdown's menu would show: { text, selected, Pick = choose it (and the menu closes) }.
function H.Menu(dd)
    local entries = {}
    local root = {}
    function root:CreateRadio(text, isSelected, setSelected, data)
        local e = { text = text, selected = isSelected(data) and true or false }
        e.Pick = function()
            setSelected(data)
            dd:GenerateMenu()
        end
        entries[#entries + 1] = e
        return e
    end
    function root:CreateButton(text, fn)
        local e = { text = text, Pick = function() fn(); dd:GenerateMenu() end }
        entries[#entries + 1] = e
        return e
    end
    function root:CreateTitle(text) entries[#entries + 1] = { text = text, title = true } end
    function root:CreateDivider() end
    dd.generator(dd, root)
    return entries
end

-- Forever's profession window (/proff probe window, 2026-11-23, build 71037): retail's ProfessionsFrame (673x594,
-- level 1) with no tab bar; down the right edge an overview tab (ProfessionsOverviewTab: the "Professions" page,
-- BookPage, its rank bars drawn high) and seven profession tabs (Professions1Tab..7Tab, also in
-- rightProfessionTabs), the character's shown, top to bottom, 55x55, 2 px apart. Tabs are Frames: a mouse press
-- runs their OnClick method. Each has six textures: background common-sidetab, the icon (no atlas), its mask,
-- two common-sidetab-selected (the first shown on the open profession's tab only, the second on all), and the
-- hover. CraftingPage's parts reach level 600. w.quirks.noSideTabs: a window without the tabs.
-- Their size here comes a moment after the window shows (a size from anchors is 0 before the client's layout; in
-- game they had theirs at once, 2026-11-23, but the addon mustn't count on it). The second "selected" texture is shown but not seen on an unselected
-- tab (alpha 0 and color alpha 0: probed): one copying only "shown" draws gold.
-- The window opens on the overview (BookPage) with NO profession open and no TRADE_SKILL_SHOW (c:OpenOverview);
-- a profession's tab opens it (CraftingPage). The window is made when Blizzard's profession UI loads
-- (ADDON_LOADED "Blizzard_Professions"), with whichever comes first.
local function SideTab(c, pf, line)
    local t = P.NewFrame(c, "Frame", nil, pf)
    t:SetFrameLevel(2)
    t.skillLine = line
    local function Art(layer, atlas, w, h)
        local r = atlas == "mask" and t:CreateMaskTexture(nil, layer) or t:CreateTexture(nil, layer)
        if atlas == "mask" then r:SetAtlas("common-sidetab-mask") elseif atlas then r:SetAtlas(atlas) else r:SetTexture(136240) end
        r:SetSize(w or 55, h or 60)
        r:SetPoint("CENTER", t, "CENTER", 0, 0)
        return r
    end
    Art("BACKGROUND", "common-sidetab")
    Art("ARTWORK", nil, 50, 50)
    Art("ARTWORK", "mask")
    t.highlight = Art("OVERLAY", "common-sidetab-selected")
    t.highlight:Hide()
    t.glow = Art("OVERLAY", "common-sidetab-selected")
    t.glow:SetAlpha(0)
    t.glow:SetBlendMode("ADD")
    Art("HIGHLIGHT", "common-sidetab-hover")
    t:SetScript("OnMouseUp", function(self) self:OnClick() end)
    return t
end

function P.ProfessionsFrame(c)
    local pf = P.NewFrame(c, "Frame", nil, nil, "")
    pf.name = "ProfessionsFrame"
    rawset(c.env, "ProfessionsFrame", pf)
    pf.shown = false
    pf.size = { 673, 594 }
    pf.Bg = pf:CreateTexture(nil, "BACKGROUND")
    pf.Bg:SetAtlas("Profession-Background-Overview")
    pf.NineSlice = P.NewFrame(c, "Frame", nil, pf)
    pf.NineSlice:SetFrameLevel(500)
    pf.PortraitContainer = P.NewFrame(c, "Frame", nil, pf)
    pf.PortraitContainer:SetFrameLevel(400)
    pf.TitleContainer = P.NewFrame(c, "Frame", nil, pf)
    pf.TitleContainer:SetFrameLevel(510)
    pf.CloseButton = P.NewFrame(c, "Button", nil, pf)
    pf.CloseButton:SetFrameLevel(510)
    pf.CloseButton:SetScript("OnClick", function() c:CloseProfession() end)
    pf.CraftingPage = P.NewFrame(c, "Frame", nil, pf)
    pf.CraftingPage:SetFrameLevel(100)
    pf.form = P.NewFrame(c, "Frame", nil, pf.CraftingPage)
    pf.form:SetFrameLevel(598)
    pf.BookPage = P.NewFrame(c, "Frame", nil, pf)
    pf.BookPage:SetFrameLevel(100)
    pf.BookPage.shown = false
    pf.bars = P.NewFrame(c, "Frame", nil, pf.BookPage)
    pf.bars:SetFrameLevel(700)
    -- The overview: its own tab, above the professions'.
    pf.ProfessionsOverviewTab = SideTab(c, pf, nil)
    local function Overview(on)
        pf.CraftingPage:SetShown(not on)
        pf.BookPage:SetShown(on)
    end
    pf.ProfessionsOverviewTab.OnClick = function() Overview(true) end
    pf.rightProfessionTabs = {}
    if not c.world.quirks.noSideTabs then
        for i = 1, 7 do
            local t = SideTab(c, pf, nil)
            t.OnClick = function(tab) c:OpenProfession(tab.skillLine) end
            pf["Professions" .. i .. "Tab"] = t
            pf.rightProfessionTabs[i] = t
        end
    end
    -- The character's professions on the first tabs (sorted), the rest hidden; the open one lit.
    pf.UpdateTabs = function(self, win, opening)
        local lines = {}
        for line in pairs(c.player.profs) do lines[#lines + 1] = line end
        table.sort(lines)
        for i, t in ipairs(self.rightProfessionTabs) do
            t.skillLine = lines[i]
            t:SetShown(lines[i] ~= nil)
            local on = win ~= nil and lines[i] ~= nil and lines[i] == win.line and win.kind == "own"
            t.highlight:SetShown(on)
            t.glow:SetAlpha(on and 1 or 0)
        end
        -- (laid out a moment later: then they have their size)
        c.world:After(0.05, function()
            for _, t in ipairs(self.rightProfessionTabs) do t:SetSize(55, 55) end
            self.ProfessionsOverviewTab:SetSize(55, 55)
        end, c)
        if opening ~= nil then Overview(opening) end
    end
    c:Fire("ADDON_LOADED", "Blizzard_Professions")
    return pf
end

-- The window made before the addon loads (a patch: another addon loaded Blizzard's profession UI first).
function H.MakeProfessionsFrame(c, env)
    c.env = env
    return P.ProfessionsFrame(c)
end

-- Forever's guild window (/proff probe communities, 2026-11-25): retail's CommunitiesFrame, made when Blizzard's
-- guild UI loads (ADDON_LOADED "Blizzard_Communities"). Here only its member detail panel (GuildMemberDetailFrame,
-- 212x260: Name, Level, CloseButton), filled by its DisplayMember(clubId, memberInfo) when a name is clicked.
function P.CommunitiesFrame(c)
    local cf = P.NewFrame(c, "Frame", nil, nil, "")
    cf.name = "CommunitiesFrame"
    rawset(c.env, "CommunitiesFrame", cf)
    cf.shown = false
    cf.size = { 814, 426 }
    local d = P.NewFrame(c, "Frame", nil, cf)
    d.size = { 212, 260 }
    d.shown = false
    d.Name = d:CreateFontString(nil, "ARTWORK")
    d.Name:SetPoint("TOPLEFT", d, "TOPLEFT", 17, -18)
    d.Level = d:CreateFontString(nil, "ARTWORK")
    d.CloseButton = P.NewFrame(c, "Button", nil, d)
    d.CloseButton:SetScript("OnClick", function() d:Hide() end)
    rawset(d, "DisplayMember", function(self, _, info)
        self.Name:SetText(info.name)
        self.Level:SetText("Level 60")
    end)
    cf.GuildMemberDetailFrame = d
    c:Fire("ADDON_LOADED", "Blizzard_Communities")
    return cf
end

-- The guild window made before the addon loads (another addon loaded Blizzard's guild UI first).
function H.MakeCommunitiesFrame(c, env)
    c.env = env
    return P.CommunitiesFrame(c)
end
