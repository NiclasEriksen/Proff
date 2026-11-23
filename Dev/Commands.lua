---@class Proff
local ns = select(2, ...)

-- Developer commands, English: only in a git checkout (ns.DEV). The file isn't packaged (#@do-not-package@
-- in the TOC), and a checkout given a release's version (the tests do) has none either.
if not ns.DEV then return end
local Add = ns.Commands.Add

Add("probe", "probe [api|roster|window|link [off]|verify [ok <id>|off|reset]|clear]", function(arg)
    local word, rest = (arg or ""):match("^(%S*)%s*(.-)$")
    if word == "verify" then return ns.Verify:Command(rest) end
    ns.Probe:Run(arg)
end)

Add("debug", "debug [on|off|echo|clear|mute <module>|unmute <module>]", function(arg)
    local D = ns.Debug
    local word, module = (arg or ""):match("^(%S*)%s*(%S*)")
    word = word:lower()
    if word == "mute" or word == "unmute" then
        local list = D:Mute(module ~= "" and module or nil, word == "mute")
        return ns.Print("Muted in the log: " .. (#list > 0 and table.concat(list, ", ") or "none") .. ".")
    elseif word == "clear" then
        D:Clear()
        return ns.Print("Debug log cleared.")
    elseif word == "echo" then
        D:SetEnabled(true, not D.echo)
    elseif word == "on" or word == "off" then
        D:SetEnabled(word == "on", D.echo)
    else
        D:SetEnabled(not D.enabled, D.echo)
    end
    ns.Print(("Debug %s%s."):format(D.enabled and "on" or "off", D.echo and " (echo to chat)" or ""))
end)
