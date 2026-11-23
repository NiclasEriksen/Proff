-- The stub client's basics: the clocks, timers, the error handler, hooksecurefunc, secret values, frames,
-- the chat frame, slash commands and the addon's metadata.
local H, P = ...

return function(c, env)
    local w = c.world
    env.print = function(...) c.printed[#c.printed + 1] = table.concat({ ... }, " ") end
    env.GetTime = function() return w.t end
    env.GetServerTime = function() return w:ServerTime() end
    env.time = function(t) if t == nil then return w:ServerTime() end return os.time(t) end
    env.date = function(fmt, t) return os.date(fmt or "%c", t or w:ServerTime()) end
    env.C_Timer = { After = function(delay, fn) w:After(delay, fn, c) end }
    c.errorHandler = nil
    local record = function(e) c.errors[#c.errors + 1] = tostring(e) end
    env.geterrorhandler = function() return c.errorHandler or record end
    env.seterrorhandler = function(fn) c.errorHandler = fn end
    env.debugstack = function() return debug.traceback() end
    env.hooksecurefunc = function(a, b, fn)
        local t, name = env, a
        if type(a) == "table" then t, name = a, b else fn = b end
        local old = rawget(t, name)
        assert(type(old) == "function", "hooksecurefunc: " .. tostring(name) .. " is not a function")
        rawset(t, name, function(...)
            local r = { old(...) }
            fn(...)
            return unpack(r)
        end)
    end
    env.issecretvalue = function(v) return v == H.SECRET end
    env.issecrettable = function(v) return rawequal(v, H.SECRET) end
    env.CreateFrame = function(kind, name, parent, template) return P.NewFrame(c, kind, name, parent, template) end
    env.DEFAULT_CHAT_FRAME = { AddMessage = function(_, msg) c.printed[#c.printed + 1] = tostring(msg) end }
    env.SlashCmdList = {}
    env.GetBuildInfo = function() return "1.60.1", "71037", "Nov  3 2026", 16001 end
    env.GetLocale = function() return "enUS" end
    env.C_AddOns = { GetAddOnMetadata = function(name, field)
        if name == P.ADDON and field == "Version" then return c.version end
        return P.TOC.meta[field]
    end }
    -- Blizzard's link handler: a profession link asks the server for that player's profession, and the window
    -- opens with it a moment later (ui.lua: Client:ShowLinked). Other links do nothing here.
    env.SetItemRef = function(link, text, button)
        c.itemRefs = (c.itemRefs or 0) + 1
        local guid, spell, line = tostring(link):match("^trade:(Player%-%d+%-%x+):(%d+):(%d+)")
        if guid and button ~= "shift" then
            local delay = w.quirks.linkSync and 0 or 0.2
            local open = function() c:ShowLinked(guid, tonumber(line)) end
            if delay == 0 then open() else w:After(delay, open, c) end
        end
    end
end
