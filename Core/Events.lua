---@class Proff
local ns = select(2, ...)

-- One frame for every game event. Modules subscribe with Events:On and unsubscribe with :Off; the frame stays
-- registered only for events somebody listens to, so idle features cost nothing. Registering an event the
-- client doesn't know throws on Forever (and would abort the file), so registration is pcall'd and logged.
---@class Proff.Events
local Events = { handlers = {}, snapshots = {} }
ns.Events = Events

local frame = CreateFrame("Frame")

local function Dispatch(event, ...)
    local list = Events.handlers[event]
    if not list then return end
    -- A handler may add or remove listeners of this very event: walk a snapshot, rebuilt only when that changes.
    local snap = Events.snapshots[event]
    if not snap then
        snap = {}
        for owner, fn in pairs(list) do snap[#snap + 1] = owner; snap[#snap + 1] = fn end
        Events.snapshots[event] = snap
    end
    for i = 1, #snap, 2 do
        local owner, fn = snap[i], snap[i + 1]
        if list[owner] == fn then
            local ok, err = pcall(fn, owner, event, ...)
            if not ok then geterrorhandler()(err) end
        end
    end
end
frame:SetScript("OnEvent", function(_, event, ...) Dispatch(event, ...) end)

-- owner: any table (usually the module); fn(owner, event, ...). false when the client doesn't know the event.
function Events:On(event, owner, fn)
    local list = self.handlers[event]
    if not list then
        if not pcall(frame.RegisterEvent, frame, event) then
            ns.Log("Events", "unknown event %s", event)
            return false
        end
        list = {}
        self.handlers[event] = list
    end
    if list[owner] ~= fn then list[owner] = fn; self.snapshots[event] = nil end
    return true
end

function Events:Off(event, owner)
    local list = self.handlers[event]
    if not list or list[owner] == nil then return end
    list[owner] = nil
    self.snapshots[event] = nil
    if next(list) == nil then
        self.handlers[event] = nil
        frame:UnregisterEvent(event)
    end
end

function Events:Listening(event, owner)
    local list = self.handlers[event]
    return list ~= nil and (owner == nil or list[owner] ~= nil)
end
