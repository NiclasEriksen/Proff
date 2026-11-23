-- Assertions for the specs: H.eq, H.ok, H.no, H.match (with H.Show for values).
local H, P = ...

local function Show(v)
    if type(v) == "string" then return string.format("%q", v) end
    if type(v) ~= "table" then return tostring(v) end
    local parts = {}
    for k, x in pairs(v) do parts[#parts + 1] = tostring(k) .. "=" .. Show(x) end
    table.sort(parts)
    return "{" .. table.concat(parts, ", ") .. "}"
end
H.Show = Show

function H.eq(actual, expected, msg)
    if actual ~= expected then
        error(("%sexpected %s, got %s"):format(msg and (msg .. ": ") or "", Show(expected), Show(actual)), 2)
    end
end

function H.ok(v, msg)
    if not v then error(msg or "expected a true value", 2) end
    return v
end

function H.no(v, msg)
    if v then error((msg or "expected a false value") .. " (got " .. Show(v) .. ")", 2) end
end

function H.match(s, pattern, msg)
    if type(s) ~= "string" or not s:find(pattern) then
        error(("%sexpected %s to match %q"):format(msg and (msg .. ": ") or "", Show(s), pattern), 2)
    end
end

-- A list's items joined with " | " (printed lines, holders): for one H.eq.
function H.lines(list) return table.concat(list, " | ") end
