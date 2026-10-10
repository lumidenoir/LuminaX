-- ============================================================================
-- LuminaX Module: Events
-- High-performance, zero-dependency Pub/Sub Event Bus for decoupled subsystems
-- ============================================================================

local M = {}

local EventBus = {}
EventBus.__index = EventBus

function EventBus.new()
    local self = setmetatable({}, EventBus)
    self.listeners = {}

    -- Support both colon (bus:emit(...)) and dot (bus.emit(...)) syntax seamlessly
    self.on = function(a, b, c)
        if a == self then return EventBus.on(self, b, c) end
        return EventBus.on(self, a, b)
    end
    self.once = function(a, b, c)
        if a == self then return EventBus.once(self, b, c) end
        return EventBus.once(self, a, b)
    end
    self.off = function(a, b, c)
        if a == self then return EventBus.off(self, b, c) end
        return EventBus.off(self, a, b)
    end
    self.emit = function(a, ...)
        if a == self then return EventBus.emit(self, ...) end
        return EventBus.emit(self, a, ...)
    end
    self.clear = function(a, b)
        if a == self then return EventBus.clear(self, b) end
        return EventBus.clear(self, a)
    end
    self.listener_count = function(a, b)
        if a == self then return EventBus.listener_count(self, b) end
        return EventBus.listener_count(self, a)
    end

    return self
end

-- Subscribe a handler to a specific event. Returns an unbind function.
function EventBus:on(event, handler)
    if not event or type(handler) ~= 'function' then
        return function() end
    end
    if not self.listeners[event] then
        self.listeners[event] = {}
    end
    table.insert(self.listeners[event], handler)

    local unsubscribed = false
    return function()
        if not unsubscribed then
            unsubscribed = true
            self:off(event, handler)
        end
    end
end

-- Subscribe a handler that automatically unbinds after its first execution.
function EventBus:once(event, handler)
    if not event or type(handler) ~= 'function' then
        return function() end
    end
    local unbind
    local wrapper = function(...)
        if unbind then unbind() end
        handler(...)
    end
    unbind = self:on(event, wrapper)
    return unbind
end

-- Unsubscribe a specific handler from an event.
function EventBus:off(event, handler)
    local list = self.listeners[event]
    if not list then return end
    for i = #list, 1, -1 do
        if list[i] == handler then
            table.remove(list, i)
            break
        end
    end
    if #list == 0 then
        self.listeners[event] = nil
    end
end

-- Emit an event with optional arguments to all subscribed listeners.
-- Listeners are wrapped in pcall so one throwing handler never breaks others.
function EventBus:emit(event, ...)
    local list = self.listeners[event]
    if not list or #list == 0 then return end

    -- Clone listener slice to prevent issues if a listener unsubscribes during emit
    local copy = {}
    for i = 1, #list do
        copy[i] = list[i]
    end

    for i = 1, #copy do
        local ok, err = pcall(copy[i], ...)
        if not ok then
            local warn_msg = string.format('[LuminaX EventBus] Error in listener for "%s": %s', tostring(event), tostring(err))
            if mp and mp.msg and mp.msg.warn then
                mp.msg.warn(warn_msg)
            else
                print(warn_msg)
            end
        end
    end
end

-- Clear all listeners for a given event, or all listeners entirely if event is nil.
function EventBus:clear(event)
    if event then
        self.listeners[event] = nil
    else
        self.listeners = {}
    end
end

-- Return the number of active listeners for an event.
function EventBus:listener_count(event)
    local list = self.listeners[event]
    return list and #list or 0
end

M.EventBus = EventBus
M.new = EventBus.new

-- Global shared singleton instance for LuminaX
M.shared = EventBus.new()

return M
