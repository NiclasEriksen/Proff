-- Frame stubs: CreateFrame's frames record their events, scripts, anchors, sizes and children; regions
-- (textures, font strings) record what's set on them. Nothing is laid out: a size is known only when set
-- (f.size), edges never (GetLeft and friends say nil, as before the client's first layout).
--
-- Methods follow the widget type: a Button has SetText, an EditBox SetAutoFocus, a ScrollFrame SetScrollChild,
-- and a method the type doesn't have throws (a capitalized key: frame:SetBackdrop on a client without it would
-- be a Lua error there too); lowercase fields are the addon's own and free. Show/Hide cascade OnShow/OnHide;
-- SetSize fires OnSizeChanged.
--
-- Templates (P.TEMPLATES) add what Blizzard's do (a mixin's methods and parentKeys are plain fields, rawget
-- finds them); one the stub lacks, or w.quirks.missingTemplates[name], throws as the client's "Couldn't find
-- inherited node". C_XMLUtil.GetTemplateInfo answers from the same list (env/ui.lua).
local H, P = ...

local Frame, Region = {}, {}
local BY_KIND = {
    Frame = {}, Button = {}, CheckButton = {}, EditBox = {}, ScrollFrame = {}, DropdownButton = {}, GameTooltip = {},
}
local function Lookup(t, k)
    local kind = rawget(t, "kind")
    local m = (BY_KIND[kind] or {})[k] or Frame[k]
    if m ~= nil then return m end
    if type(k) == "string" and k:match("^%u") then error(("%s stub has no method %s"):format(tostring(kind), k), 2) end
    return nil
end
local FrameMeta = { __index = Lookup }
-- A Button's methods are a CheckButton's and a DropdownButton's too.
setmetatable(BY_KIND.CheckButton, { __index = BY_KIND.Button })
setmetatable(BY_KIND.DropdownButton, { __index = BY_KIND.Button })

local RegionMeta = {
    __index = function(t, k)
        local m = Region[k]
        if m ~= nil then
            if type(m) == "table" then m = m[t.ftype] end -- (a method of one region type only)
            if m ~= nil then return m end
        end
        if type(k) == "string" and k:match("^%u") then error(("%s stub has no method %s"):format(t.ftype, k), 2) end
        return nil
    end,
}

P.TEMPLATES = {}

local function Missing(c, name)
    return not P.TEMPLATES[name] or (c.world.quirks.missingTemplates or {})[name]
end
P.TemplateMissing = Missing

function P.NewFrame(c, kind, name, parent, template)
    kind = kind or "Frame"
    if not BY_KIND[kind] then error("CreateFrame: unknown frame type '" .. tostring(kind) .. "'", 2) end
    local templates = {}
    for t in (template or ""):gmatch("[^,%s]+") do
        if Missing(c, t) then error("CreateFrame(): Couldn't find inherited node '" .. t .. "'", 2) end
        templates[#templates + 1] = t
    end
    c.seq = (c.seq or 0) + 1
    local f = setmetatable({ kind = kind, name = name, parent = parent, children = {}, regions = {}, events = {},
        scripts = {}, points = {}, shown = true, seq = c.seq, client = c, level = parent and (parent.level or 1) + 1 or 1,
        templates = templates }, FrameMeta)
    if parent then parent.children[#parent.children + 1] = f end
    c.frames[#c.frames + 1] = f
    if name then rawset(c.env, name, f) end
    for _, t in ipairs(templates) do P.TEMPLATES[t](f, c) end
    return f
end

------------------------------------------------------------------------------
-- Every frame
------------------------------------------------------------------------------
function Frame:RegisterEvent(e)
    if not P.KNOWN_EVENTS[e] then error("Attempt to register unknown event \"" .. tostring(e) .. "\"", 2) end
    self.events[e] = true
end
function Frame:UnregisterEvent(e) self.events[e] = nil end
function Frame:UnregisterAllEvents() self.events = {} end
function Frame:IsEventRegistered(e) return self.events[e] == true end
function Frame:SetScript(k, fn) self.scripts[k] = fn end
function Frame:GetScript(k) return self.scripts[k] end
function Frame:HookScript(k, fn)
    local old = self.scripts[k]
    self.scripts[k] = old and function(...) old(...); fn(...) end or fn
end
-- Runs a script as the client would (a test's hover, press, a key).
function Frame:Run(script, ...)
    if self.scripts[script] then return self.scripts[script](self, ...) end
end
local function Visible(f)
    while f do
        if not f.shown then return false end
        f = f.parent
    end
    return true
end
local function Cascade(f, script)
    if f.scripts[script] then f.scripts[script](f) end
    for _, ch in ipairs(f.children) do if ch.shown then Cascade(ch, script) end end
end
function Frame:Show()
    if self.shown then return end
    self.shown = true
    if Visible(self) then Cascade(self, "OnShow") end
end
function Frame:Hide()
    if not self.shown then return end
    local was = Visible(self)
    self.shown = false
    if was then Cascade(self, "OnHide") end
end
function Frame:SetShown(on) if on then self:Show() else self:Hide() end end
function Frame:IsShown() return self.shown end
function Frame:IsVisible() return Visible(self) end
function Frame:SetSize(w, h)
    local old = self.size
    self.size = { w, h }
    if not old or old[1] ~= w or old[2] ~= h then self:Run("OnSizeChanged", w, h) end
end
function Frame:SetWidth(w) self:SetSize(w, self.size and self.size[2]) end
function Frame:SetHeight(h) self:SetSize(self.size and self.size[1], h) end
function Frame:GetSize() return (self.size or { 0, 0 })[1] or 0, (self.size or { 0, 0 })[2] or 0 end
function Frame:GetWidth() return self.size and self.size[1] end
function Frame:GetHeight() return self.size and self.size[2] end
-- (no layout: edges are unknown)
function Frame:GetLeft() return nil end
function Frame:GetRight() return nil end
function Frame:GetTop() return nil end
function Frame:GetBottom() return nil end
function Frame:SetPoint(...) self.points[#self.points + 1] = { ... } end
function Frame:ClearAllPoints() self.points = {} end
function Frame:SetAllPoints(rel) self.allPointsTo = rel or self.parent end
function Frame:GetPoint(i) local p = self.points[i or 1]; if p then return unpack(p) end end
function Frame:GetName() return self.name end
function Frame:GetObjectType() return self.kind end
function Frame:GetParent() return self.parent end
function Frame:GetChildren() return unpack(self.children) end
function Frame:GetRegions() return unpack(self.regions) end
-- (as the client: the children move by as much, so they stay above their parent)
function Frame:SetFrameLevel(n)
    local delta = n - (self.level or 0)
    self.level = n
    local function Move(f)
        for _, ch in ipairs(f.children) do ch.level = (ch.level or 0) + delta; Move(ch) end
    end
    Move(self)
end
function Frame:GetFrameLevel() return self.level end
function Frame:EnableMouse(on) self.mouse = on and true or false end
-- (a frame's strata is its parent's until set)
function Frame:SetFrameStrata(s) self.strata = s end
function Frame:GetFrameStrata() return self.strata or (self.parent and self.parent:GetFrameStrata()) or "MEDIUM" end
function Frame:SetAlpha(a) self.alpha = a end
function Frame:GetAlpha() return self.alpha or 1 end
function Frame:GetEffectiveAlpha() return (self.alpha or 1) * (self.parent and self.parent:GetEffectiveAlpha() or 1) end
local function NewRegion(f, ftype, layer, template, sub)
    local r = setmetatable({ ftype = ftype, owner = f, layer = layer, sub = sub or 0, font = template, shown = true,
        points = {} }, RegionMeta)
    f.regions[#f.regions + 1] = r
    return r
end
function Frame:CreateTexture(_, layer, template, sub) return NewRegion(self, "Texture", layer, template, sub) end
function Frame:CreateFontString(_, layer, template) return NewRegion(self, "FontString", layer, template) end
function Frame:CreateMaskTexture(_, layer) return NewRegion(self, "MaskTexture", layer) end

------------------------------------------------------------------------------
-- Buttons
------------------------------------------------------------------------------
local Button = BY_KIND.Button
function Button:SetText(t)
    if not self.fontString then self.fontString = NewRegion(self, "FontString", "OVERLAY") end
    self.fontString:SetText(t)
end
function Button:GetText() return self.fontString and self.fontString.text end
function Button:GetFontString() return self.fontString end
function Button:SetFontString(fs) self.fontString = fs end
function Button:Enable() self.disabled = false end
function Button:Disable() self.disabled = true end
function Button:IsEnabled() return not self.disabled end
function Button:RegisterForClicks(...) self.clicks = { ... } end
-- A click: OnClick as the client runs it (a disabled button takes none).
function Button:Click(button)
    if self.disabled then return end
    if self.kind == "CheckButton" then self.checked = not self.checked end
    self:Run("PreClick", button or "LeftButton", false)
    self:Run("OnClick", button or "LeftButton", false)
    self:Run("PostClick", button or "LeftButton", false)
end
-- The player pressing it with the mouse: down, up, then (a button's) the click.
function Frame:Press(button)
    self:Run("OnMouseDown", button or "LeftButton")
    self:Run("OnMouseUp", button or "LeftButton")
    if self.kind == "Button" or self.kind == "CheckButton" or self.kind == "DropdownButton" then self:Click(button) end
end
function Button:SetChecked(on) self.checked = on and true or false end
function Button:GetChecked() return self.checked end

------------------------------------------------------------------------------
-- Edit boxes
------------------------------------------------------------------------------
local EditBox = BY_KIND.EditBox
-- (OnTextChanged's userInput: true when typed, c:Type)
function EditBox:SetText(t, userInput)
    t = tostring(t or "")
    if t == self.text then return end
    self.text = t
    self:Run("OnTextChanged", userInput == true)
end
function EditBox:GetText() return self.text or "" end
function EditBox:SetAutoFocus(on) self.autoFocus = on and true or false end
function EditBox:SetMaxLetters(n) self.maxLetters = n end
function EditBox:SetFocus() self.focus = true end
function EditBox:ClearFocus() self.focus = false end
function EditBox:HasFocus() return self.focus == true end

------------------------------------------------------------------------------
-- Scroll frames: the scroll range is the child's height past the frame's own (both as set).
------------------------------------------------------------------------------
local ScrollFrame = BY_KIND.ScrollFrame
function ScrollFrame:SetScrollChild(f) self.scrollChild = f end
function ScrollFrame:GetScrollChild() return self.scrollChild end
function ScrollFrame:GetVerticalScrollRange()
    local ch = self.scrollChild and self.scrollChild:GetHeight() or 0
    return math.max(0, ch - (self:GetHeight() or 0))
end
function ScrollFrame:SetVerticalScroll(v)
    v = math.max(0, math.min(v, self:GetVerticalScrollRange()))
    if v == (self.vscroll or 0) then return end
    self.vscroll = v
    self:Run("OnVerticalScroll", v)
end
function ScrollFrame:GetVerticalScroll() return self.vscroll or 0 end

------------------------------------------------------------------------------
-- Regions
------------------------------------------------------------------------------
local function Owned(r)
    local f = r.owner
    return f
end
function Region:Show() self.shown = true end
function Region:Hide() self.shown = false end
function Region:SetShown(on) self.shown = on and true or false end
function Region:IsShown() return self.shown end
function Region:IsVisible() return self.shown and Owned(self):IsVisible() end
function Region:SetPoint(...) self.points[#self.points + 1] = { ... } end
function Region:ClearAllPoints() self.points = {} end
function Region:SetAllPoints(rel) self.allPointsTo = rel or self.owner end
function Region:SetSize(w, h) self.size = { w, h } end
function Region:GetSize() return (self.size or {})[1] or 0, (self.size or {})[2] or 0 end
function Region:GetPoint(i) local p = self.points[i or 1]; if p then return unpack(p) end end
function Region:GetDrawLayer() return self.layer, self.sub end
function Region:SetWidth(w) self.size = { w, self.size and self.size[2] } end
function Region:SetHeight(h) self.size = { self.size and self.size[1], h } end
function Region:GetObjectType() return self.ftype end
function Region:GetParent() return self.owner end
function Region:SetAlpha(a) self.alpha = a end
function Region:GetAlpha() return self.alpha or 1 end
function Region:SetDrawLayer(layer, sub) self.layer, self.sub = layer, sub or self.sub end
function Region:SetVertexColor(...) self.vertex = { ... } end
function Region:GetVertexColor() return unpack(self.vertex or { 1, 1, 1, 1 }) end
-- Textures
Region.SetTexture = { Texture = function(self, x) self.tex, self.atlas, self.color = x, nil, nil end }
Region.GetTexture = { Texture = function(self) return self.tex end }
local function SetAtlas(self, x) self.atlas, self.tex, self.color = x, x, nil end
local function GetAtlas(self) return self.atlas end
Region.SetAtlas = { Texture = SetAtlas, MaskTexture = SetAtlas }
Region.GetAtlas = { Texture = GetAtlas, MaskTexture = GetAtlas }
Region.AddMaskTexture = { Texture = function(self, m) self.mask = m end }
Region.SetColorTexture = { Texture = function(self, ...) self.color, self.tex, self.atlas = { ... }, nil, nil end }
Region.SetTexCoord = { Texture = function(self, ...) self.texCoord = { ... } end }
-- (the four corners' x, y: 8 values, as the client gives them)
Region.GetTexCoord = { Texture = function(self)
    local c = self.texCoord or { 0, 1, 0, 1 }
    if #c == 8 then return unpack(c) end
    return c[1], c[3], c[1], c[4], c[2], c[3], c[2], c[4]
end }
Region.SetBlendMode = { Texture = function(self, m) self.blend = m end }
Region.GetBlendMode = { Texture = function(self) return self.blend or "BLEND" end }
Region.SetDesaturated = { Texture = function(self, on) self.desaturated = on and true or false end }
-- Font strings: .text as set, .plain without color codes
Region.SetText = { FontString = function(self, t)
    self.text = t
    self.plain = t and P.StripColors(tostring(t))
end }
Region.GetText = { FontString = function(self) return self.text end }
Region.SetTextColor = { FontString = function(self, ...) self.textColor = { ... } end }
Region.SetJustifyH = { FontString = function(self, j) self.justifyH = j end }
Region.SetJustifyV = { FontString = function(self, j) self.justifyV = j end }
Region.SetWordWrap = { FontString = function(self, on) self.wrap = on end }
Region.SetFontObject = { FontString = function(self, f) self.font = f end }
-- About 6 px a character, as GameFontNormalSmall.
Region.GetStringWidth = { FontString = function(self) return #(self.plain or "") * 6 end }

function P.StripColors(s) return (s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end

P.Frame, P.Region, P.BY_KIND = Frame, Region, BY_KIND
