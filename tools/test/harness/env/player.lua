-- The player: names ("First", "Surname": the second value is the surname on Forever), GUIDs, realms.
local H, P = ...

return function(c, env)
    local w = c.world
    env.UnitName = function(unit)
        if unit == "player" then return c.first, c.surname end
        return nil
    end
    env.UnitGUID = function(unit) if unit == "player" then return c.player.guid end end
    env.GetNormalizedRealmName = function() return "CAMWOWEU4Realm1PvE" end
    env.GetRealmName = function() return "CAMWOW EU4 Realm 1 PvE" end
    env.GetAutoCompleteRealms = function() return { "CAMWOWEU4Realm1PvE", "CAMWOWEU4Realm5PvE" } end
    -- localizedClass, englishClass, localizedRace, englishRace, sex, name, realmName
    env.GetPlayerInfoByGUID = function(guid)
        for _, p in pairs(w.players) do
            if p.guid == guid then
                local q = w.quirks.guidName
                local name = q == "first" and p.name:match("^(%S+)") or (q ~= false and p.name or nil)
                return "Warrior", "WARRIOR", "Human", "Human", 2, name, ""
            end
        end
    end
end
