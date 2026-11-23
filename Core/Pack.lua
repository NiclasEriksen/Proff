---@class Proff
local ns = select(2, ...)

-- Compact text for the addon channel (Core/Comm.lua): numbers and sets of recipe ids, no library. Pure.
--
-- A number is written in 5-bit digits, most significant first: every digit but the last from CONT, the last from
-- STOP, so numbers need no separators. 0..31 is one character, up to 1023 two, up to ~1M four.
-- A set of ids is sorted and written as the first id and then each gap to the next: a profession's recipe ids
-- sit close together, so most gaps are one or two characters (Enchanting's 104: ~200 bytes).
-- The alphabets avoid "|" (the chat escape), "\t" and "\n" (Comm's separators) and anything unprintable.
---@class Proff.Pack
local Pack = {}
ns.Pack = Pack

local CONT = "0123456789ABCDEFGHIJKLMNOPQRSTUV"
local STOP = "WXYZabcdefghijklmnopqrstuvwxyz!#"
local DIGIT = {} -- char -> { value, last }
for i = 1, 32 do
    DIGIT[CONT:sub(i, i)] = { i - 1, false }
    DIGIT[STOP:sub(i, i)] = { i - 1, true }
end
Pack.MAX = 2 ^ 40 -- (larger numbers aren't ours: refused both ways)

-- A whole number >= 0 as text.
function Pack.Num(n)
    assert(type(n) == "number" and n >= 0 and n < Pack.MAX and n == math.floor(n), "Pack.Num: not a whole number")
    local digits = {}
    repeat
        digits[#digits + 1] = n % 32
        n = math.floor(n / 32)
    until n == 0
    local out = {}
    for i = #digits, 1, -1 do
        local d = digits[i] + 1
        out[#out + 1] = i == 1 and STOP:sub(d, d) or CONT:sub(d, d)
    end
    return table.concat(out)
end

-- Reads one number at pos: the number and the position after it, or nil for text that isn't one.
function Pack.ReadNum(s, pos)
    local n = 0
    pos = pos or 1
    while pos <= #s do
        local d = DIGIT[s:sub(pos, pos)]
        if not d then return nil end
        n = n * 32 + d[1]
        pos = pos + 1
        if n >= Pack.MAX then return nil end
        if d[2] then return n, pos end
    end
    return nil
end

-- A set { [id] = true } (or a list) of whole numbers > 0 as text.
function Pack.Set(set)
    local ids = {}
    for k, v in pairs(set) do
        local id = v == true and k or v
        if type(id) == "number" then ids[#ids + 1] = id end
    end
    table.sort(ids)
    local out, prev = {}, 0
    for _, id in ipairs(ids) do
        if id > prev then
            out[#out + 1] = Pack.Num(id - prev)
            prev = id
        end
    end
    return table.concat(out)
end

-- Text back to a set and its count; nil for text that isn't one (or holds more than max ids).
function Pack.ReadSet(s, max)
    if type(s) ~= "string" then return nil end
    local set, n, pos, id = {}, 0, 1, 0
    while pos <= #s do
        local gap
        gap, pos = Pack.ReadNum(s, pos)
        if not gap or gap == 0 then return nil end
        id = id + gap
        if id >= Pack.MAX then return nil end
        set[id] = true
        n = n + 1
        if max and n > max then return nil end
    end
    return set, n
end

-- A 20-bit hash of text (djb2): a name in a sync index is its hash (4 characters, not ~12).
function Pack.Hash(s)
    local h = 5381
    for i = 1, #s do h = (h * 33 + s:byte(i)) % 1048576 end
    return h
end

-- A short checksum of a set (4 characters): two peers can tell whether they hold the same recipes without
-- sending them. (Not a security measure: anyone can send anything.)
function Pack.Sum(set)
    local ids = {}
    for id in pairs(set) do if type(id) == "number" then ids[#ids + 1] = id end end
    table.sort(ids)
    local a, b = 1, 0
    for _, id in ipairs(ids) do
        a = (a + id % 65521) % 65521
        b = (b + a) % 65521
    end
    return Pack.Num((b * 65536 + a) % 1048576)
end
