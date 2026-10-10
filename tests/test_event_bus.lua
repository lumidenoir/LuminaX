-- ============================================================================
-- Test Suite: Pub/Sub Event Bus Verification
-- Tests: subscription, unsubscription, once, argument passing, error isolation,
-- listener counts, and lifecycle decoupling.
-- ============================================================================

package.path = './scripts/LuminaX/?.lua;' .. package.path
local events_mod = require('modules.events')

local test_count = 0
local pass_count = 0

local function assert_eq(desc, actual, expected)
    test_count = test_count + 1
    if actual == expected then
        pass_count = pass_count + 1
        print(string.format("  ✓ PASS: %s", desc))
    else
        print(string.format("  ✗ FAIL: %s | Expected: %s, Got: %s", desc, tostring(expected), tostring(actual)))
    end
end

local function assert_true(desc, val)
    assert_eq(desc, not not val, true)
end

print("=== 1. Testing Event Bus Instance Creation & Shared Singleton ===")
local bus = events_mod.new()
assert_true("EventBus.new creates an instance", bus ~= nil)
assert_true("Shared instance exists", events_mod.shared ~= nil)
assert_eq("Initial listener count is 0", bus:listener_count('test:event'), 0)

print("\n=== 2. Testing Basic Subscription and Event Emission ===")
local received_val = nil
local unsub = bus:on('item:selected', function(val)
    received_val = val
end)
assert_eq("Listener registered", bus:listener_count('item:selected'), 1)

bus:emit('item:selected', 42)
assert_eq("Event received payload argument", received_val, 42)

-- Multiple arguments
local a_val, b_val = nil, nil
bus:on('multi:args', function(a, b)
    a_val, b_val = a, b
end)
bus:emit('multi:args', 'hello', 'world')
assert_eq("Arg 1 received", a_val, 'hello')
assert_eq("Arg 2 received", b_val, 'world')

print("\n=== 3. Testing Unsubscription (Function & off) ===")
unsub()
assert_eq("Listener unregistered via returned unbind function", bus:listener_count('item:selected'), 0)
received_val = nil
bus:emit('item:selected', 99)
assert_eq("Unsubscribed listener does not receive event", received_val, nil)

-- Test off() directly
local manual_count = 0
local function manual_handler()
    manual_count = manual_count + 1
end
bus:on('manual:ev', manual_handler)
bus:emit('manual:ev')
assert_eq("Handler executed on emit", manual_count, 1)

bus:off('manual:ev', manual_handler)
assert_eq("Listener removed with off()", bus:listener_count('manual:ev'), 0)
bus:emit('manual:ev')
assert_eq("Handler not executed after off()", manual_count, 1)

print("\n=== 4. Testing 'once' Subscription ===")
local once_count = 0
bus:once('file:loaded', function(fn)
    once_count = once_count + 1
end)
assert_eq("Once listener registered", bus:listener_count('file:loaded'), 1)

bus:emit('file:loaded', 'movie.mkv')
assert_eq("Once listener fired on first emit", once_count, 1)
assert_eq("Once listener automatically removed", bus:listener_count('file:loaded'), 0)

bus:emit('file:loaded', 'movie.mkv')
assert_eq("Once listener did not fire on second emit", once_count, 1)

print("\n=== 5. Testing Error Isolation (No Crash On Throwing Listener) ===")
local post_error_received = false
bus:on('faulty:event', function()
    error("Simulated catastrophic listener failure!")
end)
bus:on('faulty:event', function()
    post_error_received = true
end)

local ok, _ = pcall(function()
    bus:emit('faulty:event')
end)
assert_true("Emit did not crash when one listener threw error", ok)
assert_true("Subsequent listeners ran despite previous listener error", post_error_received)

print("\n=== 6. Testing Unsubscribe Inside Listener During Emit ===")
local order = {}
local unsub_self
unsub_self = bus:on('mutation:event', function()
    table.insert(order, 1)
    unsub_self()
end)
bus:on('mutation:event', function()
    table.insert(order, 2)
end)

bus:emit('mutation:event')
assert_eq("Both listeners ran on first emit", #order, 2)
assert_eq("Self-unsubscribed listener count reduced to 1", bus:listener_count('mutation:event'), 1)

order = {}
bus:emit('mutation:event')
assert_eq("Only second listener ran on second emit", #order, 1)
assert_eq("Second listener value matches", order[1], 2)

print("\n=== 7. Testing clear() Method ===")
bus:on('clear:a', function() end)
bus:on('clear:b', function() end)
bus:clear('clear:a')
assert_eq("clear(event) cleared specific event", bus:listener_count('clear:a'), 0)
assert_eq("clear(event) preserved other event", bus:listener_count('clear:b'), 1)

bus:clear()
assert_eq("clear() without args cleared all events", bus:listener_count('clear:b'), 0)

print(string.format("\n========================================================"))
print(string.format("Event Bus Test Suite: %d / %d Passed (%.1f%%)", pass_count, test_count, (pass_count/test_count)*100))
print(string.format("========================================================"))

if pass_count ~= test_count then
    os.exit(1)
end
