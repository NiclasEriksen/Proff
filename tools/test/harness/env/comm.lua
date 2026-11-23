-- Addon messages (Dyreparken's stub): the server's throttle (10 per prefix, +1 a second: over it, refused with
-- code 3 and counted in w.throttled), a Trial account refused (c.trial: code 7, as Dyreparken's stub has it), and
-- delivery a moment later to every online client in the guild with the prefix registered, the sender too (GUILD
-- comes back to its sender). Every message sent is kept in w.wire: { from, prefix, text, chan, at }.
local H, P = ...

return function(c, env)
    local w = c.world
    c.prefixes = {}
    env.C_ChatInfo = {
        RegisterAddonMessagePrefix = function(p)
            assert(#p <= 16, "prefix too long")
            c.prefixes[p] = true
            return 0
        end,
        IsAddonMessagePrefixRegistered = function(p) return c.prefixes[p] == true end,
        SendAddonMessage = function(prefix, text, chan, target)
            assert(type(text) == "string" and #text <= 255, "addon message over 255 bytes")
            assert(not text:find("%z"), "addon message with \\0")
            if c.trial then return 7 end
            if chan == "GUILD" and not c.player.guild then return 10 end
            c.throttle = c.throttle or {}
            local b = c.throttle[prefix] or { tokens = 10, at = w.t }
            c.throttle[prefix] = b
            b.tokens, b.at = math.min(10, b.tokens + (w.t - b.at)), w.t
            if b.tokens < 1 then
                w.throttled = (w.throttled or 0) + 1
                return 3
            end
            b.tokens = b.tokens - 1
            w.wire[#w.wire + 1] = { from = c.name, prefix = prefix, text = text, chan = chan, at = w.t }
            w:After(0.1, function()
                for _, r in ipairs(w.clients) do
                    if r.online and r.player.guild and chan == "GUILD" and r.prefixes[prefix] and not (w.drop and w.drop(text, r)) then
                        r:Fire("CHAT_MSG_ADDON", prefix, text, chan, c.name, r.name, 0, 0, "", 0)
                    end
                end
            end)
            return 0
        end,
    }
    env.Enum = { SendAddonMessageResult = { Success = 0, InvalidPrefix = 1, InvalidMessage = 2, AddonMessageThrottle = 3,
        InvalidChatType = 4, NotInGroup = 5, TargetRequired = 6, InvalidChannel = 7, ChannelThrottle = 8,
        GeneralError = 9, NotInGuild = 10, AddOnMessageLockdown = 11, TargetOffline = 12 } }
end
