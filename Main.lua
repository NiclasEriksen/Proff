local addonName = ...
---@class Proff
local ns = select(2, ...)

-- Bootstrap: runs the start-up phases (ns.Start in each module, Core/Init.lua). SavedVariables exist from
-- ADDON_LOADED on; the guild is only reliable some seconds after login.
local Main = {}
Main.SETTLE = 5 -- s after PLAYER_LOGIN

ns.Events:On("ADDON_LOADED", Main, function(_, _, name)
    if name ~= addonName then return end
    ns.Events:Off("ADDON_LOADED", Main) -- (every addon after us would be heard)
    ns.RunPhase("loaded")
    ns.Log("Main", "loaded %s", ns.VERSION)
end)

ns.Events:On("PLAYER_LOGIN", Main, function()
    ns.Events:Off("PLAYER_LOGIN", Main)
    ns.RunPhase("login")
    C_Timer.After(Main.SETTLE, function()
        ns.RunPhase("settled")
        ns.Log("Main", "settled: guild %s", tostring(ns.GuildKey()))
    end)
end)
