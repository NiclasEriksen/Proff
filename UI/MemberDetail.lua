---@class Proff
local ns = select(2, ...)

-- Blizzard's guild member detail panel (CommunitiesFrame.GuildMemberDetailFrame, beside the guild window when a
-- member's name is clicked): small icons of the member's primary professions, at its top right under the close
-- button, in space the panel leaves empty (/proff probe communities, 2026-11-25: 212x260, the name and level at
-- the left, the zone line below). Hovering one says their skill and how many of their recipes Proff has.
--
-- Living beside Guild Roster Manager (the user, 2026-11-25: "make sure we don't collide with it", never use it):
-- it replaces the panel's OnShow/OnHide/OnKeyDown with SetScript (which drops a HookScript made before it), puts
-- its "Locked" text just above the panel, its join-date button just below, and its own panel to the right. So we
-- only hooksecurefunc Blizzard's DisplayMember (the panel's fill, called on each member shown), and our icons stay
-- inside the panel, its own children: nothing of Blizzard's or theirs is moved, hidden or replaced.
--
-- The professions: the member's info that DisplayMember gets (profession1ID/2ID, the server's, offline members
-- too); else the primaries Proff knows of them.
---@class Proff.MemberDetail
local Detail = { icons = {} }
ns.MemberDetail = Detail

local SIZE = 16

local function Field(t, k)
    local ok, v = pcall(function() return t[k] end)
    return ok and v or nil
end

local function Tooltip(icon)
    if not icon.who then return end
    local k = ns.Skills:Known(ns.GuildKey(), icon.who, icon.line)
    GameTooltip:SetOwner(icon, "ANCHOR_RIGHT")
    GameTooltip:SetText(ns.Skills.Name(icon.line) or ("#" .. icon.line), 1, 1, 1)
    if k.skill then
        GameTooltip:AddLine(ns.T("detail.skill", { skill = "|cff" .. ns.GuildMembers.SkillColor(k.skill) .. k.skill .. "|r",
            max = k.max and ("/" .. k.max) or "" }), 1, 0.82, 0)
    else
        GameTooltip:AddLine(ns.L["detail.noskill"], 0.6, 0.6, 0.6)
    end
    if k.n then
        GameTooltip:AddLine(ns.T("detail.recipes", { n = k.n, ago = ns.Commands.Ago(k.seen) }), 1, 0.82, 0)
    else
        GameTooltip:AddLine(ns.L["detail.norecipes"], 0.6, 0.6, 0.6)
    end
    GameTooltip:Show()
    ns.Log("Detail", "tooltip: %s %d", icon.who, icon.line)
end

local function Icon(panel, i)
    local b = Detail.icons[i]
    if b then return b end
    b = CreateFrame("Frame", nil, panel)
    b:SetSize(SIZE, SIZE)
    b:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -14 - (i - 1) * (SIZE + 3), -32)
    b.tex = b:CreateTexture(nil, "ARTWORK")
    b.tex:SetAllPoints()
    b.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    b:EnableMouse(true)
    b:SetScript("OnEnter", Tooltip)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    Detail.icons[i] = b
    return b
end

-- The panel shows a member: their icons.
function Detail:Show(panel, info)
    local who = type(info) == "table" and ns.NormalizeName(ns.Plain(info.name))
    if not who then
        local name = Field(panel, "Name")
        who = name and ns.NormalizeName(ns.Read(Field(name, "GetText"), name))
    end
    local lines, seen = {}, {}
    local function Add(line)
        if type(line) == "number" and line > 0 and not seen[line] and #lines < 2 then
            seen[line] = true
            lines[#lines + 1] = line
        end
    end
    if type(info) == "table" then
        Add(ns.Plain(info.profession1ID))
        Add(ns.Plain(info.profession2ID))
    end
    if who then for _, line in ipairs(ns.Skills:Primaries(ns.GuildKey(), who)) do Add(line) end end
    for i, line in ipairs(lines) do
        local b = Icon(panel, i)
        b.who, b.line = who, line
        b.tex:SetTexture(ns.Read(C_TradeSkillUI.GetTradeSkillTexture, line) or 134400)
        b:Show()
        if GameTooltip:IsOwned(b) then Tooltip(b) end
    end
    for i = #lines + 1, #self.icons do
        self.icons[i].who = nil
        self.icons[i]:Hide()
    end
    ns.Log("Detail", "shown: %s, %d professions", tostring(who), #lines)
end

-- The panel exists once Blizzard's guild window has loaded (on demand): heard as ADDON_LOADED (whichever addon
-- brought it), or at login if it's already there.
local function Try()
    local cf = rawget(_G, "CommunitiesFrame")
    local panel = cf and Field(cf, "GuildMemberDetailFrame")
    if not panel or type(Field(panel, "DisplayMember")) ~= "function" then return end
    ns.Events:Off("ADDON_LOADED", Detail)
    hooksecurefunc(panel, "DisplayMember", function(self, _, info) Detail:Show(self, info) end)
    Detail.panel = panel
    ns.Log("Detail", "attached")
end

ns.Start("login", function()
    ns.Events:On("ADDON_LOADED", Detail, Try)
    Try()
end)
