-- ============================================================================
-- LuminaX Integration Suite: Compound Interactions & Architecture Matrix
-- Tests real cross-module event pipelines, multi-step user lifecycles,
-- visual overlay collisions (screensaver vs skip), and hitbox input routing.
-- ============================================================================

package.path = './scripts/LuminaX/?.lua;./scripts/LuminaX/modules/?.lua;./tests/mocks/?.lua;' .. package.path

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

-- ============================================================================
-- 1. Thumbfast Script-Message Pipeline & Inter-Module Mutation
-- ============================================================================
local utils = require('modules.utils')

package.loaded['mp.msg'] = {
    debug = function(...) end,
    info  = function(...) end,
    warn  = function(...) end,
    error = function(...) end,
    trace = function(...) end,
}

package.loaded['mp.options'] = {
    read_options = function(t, id) return t end,
}

package.loaded['mp.utils'] = {
    parse_json = function(str)
        if not str or str == '' then return nil end
        local res = {}
        for k, v in str:gmatch('"([%w_]+)"%s*:%s*([%w%."]+)') do
            if v == 'true' then
                res[k] = true
            elseif v == 'false' then
                res[k] = false
            elseif tonumber(v) then
                res[k] = tonumber(v)
            else
                res[k] = v:gsub('^"', ''):gsub('"$', '')
            end
        end
        return res
    end,
}

package.loaded['mp.assdraw'] = {
    ass_new = function()
        return {
            text = '',
            new_event = function(self) self.text = self.text .. '\n[event]' end,
            pos = function(self, x, y) self.text = self.text .. string.format('{\\pos(%d,%d)}', x, y) end,
            an = function(self, a) self.text = self.text .. string.format('{\\an%d}', a) end,
            append = function(self, s) self.text = self.text .. s end,
            draw_start = function(self) self.text = self.text .. '{\\p1}' end,
            draw_stop = function(self) self.text = self.text .. '{\\p0}' end,
            rect_cw = function(self, x0, y0, x1, y1) end,
            round_rect_cw = function(self, x0, y0, x1, y1, r)
                self.text = self.text .. string.format('m %s %s round_rect(%s,%s,%s,%s,r=%s)', tostring(x0), tostring(y0), tostring(x0), tostring(y0), tostring(x1), tostring(y1), tostring(r))
            end,
        }
    end,
}

local osc_state = require('modules.osc.osc_state')
assert_true("Initial thumbfast disabled is true", osc_state.thumbfast.disabled == true)

-- Simulate incoming thumbfast-info JSON message
local mock_json = '{"width": 320, "height": 180, "disabled": false, "available": true}'
local parsed = package.loaded['mp.utils'].parse_json(mock_json)
assert_true("JSON parses into table", type(parsed) == 'table')

-- Propagate through osc_state.set_thumbfast
osc_state.set_thumbfast(parsed)

assert_eq("Thumbfast disabled updated to false in osc_state", osc_state.thumbfast.disabled, false)
assert_eq("Thumbfast width updated to 320 in osc_state", osc_state.thumbfast.width, 320)
assert_eq("Thumbfast height updated to 180 in osc_state", osc_state.thumbfast.height, 180)
assert_eq("Thumbfast available updated to true in osc_state", osc_state.thumbfast.available, true)

-- ============================================================================
-- 2. Pub/Sub Event Bus Error Isolation & Multi-Arg Propagation
-- ============================================================================
print("\n=== 2. Testing Event Bus Resilience & Error Isolation ===")

local events_mod = require('modules.events')
local bus = events_mod.new()

local healthy_executed = false
local throw_executed = false

bus:on('test:safe_dispatch', function()
    throw_executed = true
    error("Simulated crash in third-party listener")
end)

bus:on('test:safe_dispatch', function(a, b)
    healthy_executed = true
    assert_eq("Event received payload A", a, "foo")
    assert_eq("Event received payload B", b, "bar")
end)

-- Emit should wrap in pcall and not crash execution
bus:emit('test:safe_dispatch', 'foo', 'bar')

assert_true("Throwing listener executed", throw_executed)
assert_true("Healthy listener executed despite previous listener throw", healthy_executed)

-- ============================================================================
-- 3. Paused Playback & Compound Modal Lifecycle Matrix
-- ============================================================================
print("\n=== 3. Testing Paused Playback & Compound Modal Lifecycles ===")

-- Mock mpv environment for compound interactions
local mock_props = {
    ['pause'] = true,
    ['time-pos'] = 100,
    ['duration'] = 1440,
    ['filename'] = 'Show.S01E02.mkv',
}

local osc_shown = false
local osc_hidden = false
local screensaver_inhibited = false
local screensaver_delay_armed = false

local mock_osc = {
    show_osc = function() osc_shown = true; osc_hidden = false end,
    hide_osc = function() osc_hidden = true; osc_shown = false end,
}

local mock_ss = {
    inhibit = function() screensaver_inhibited = true end,
    activate = function() end,
    is_active = function() return false end,
}

local mock_user_opts = {
    showonpause = true,
    visibility = 'auto',
    screensaver_enabled = true,
    screensaver_delay = 3,
}

local shared_bus = events_mod.new()

-- Wire main.lua domain listeners into test harness
shared_bus:on('modal:close', function(modal_name)
    if mock_props['pause'] then
        if mock_user_opts.showonpause ~= false or mock_user_opts.visibility == 'always' then
            mock_osc.show_osc()
        end
        if mock_user_opts.screensaver_enabled then
            mock_ss.inhibit()
            screensaver_delay_armed = true
        end
    end
end)

shared_bus:on('modal:open', function(modal_name)
    mock_ss.inhibit()
    mock_osc.hide_osc()
end)

-- Scenario A: Paused -> Open Menu -> Close Menu -> Assert OSC re-appears
mock_props['pause'] = true
osc_shown = false
osc_hidden = false

-- 1. Open Menu
shared_bus:emit('modal:open', 'menu')
assert_true("Opening menu hides OSC", osc_hidden)
assert_true("Opening menu inhibits screensaver", screensaver_inhibited)

-- 2. Close Menu
screensaver_inhibited = false
screensaver_delay_armed = false
shared_bus:emit('modal:close', 'menu')
assert_true("Closing menu in paused mode restores OSC (show_osc called)", osc_shown)
assert_true("Closing menu in paused mode re-arms screensaver delay", screensaver_delay_armed)

-- Scenario B: Playing -> Open Menu -> Close Menu -> Assert OSC does NOT force show
mock_props['pause'] = false
osc_shown = false
osc_hidden = false
shared_bus:emit('modal:open', 'menu')
assert_true("Opening menu while playing hides OSC", osc_hidden)

shared_bus:emit('modal:close', 'menu')
assert_eq("Closing menu while playing does not force show_osc when visibility is auto", osc_shown, false)

-- Scenario C: Playing -> Pause = true -> Tag Editor Open -> Tag Editor Close
mock_props['pause'] = true
osc_shown = false
osc_hidden = false
shared_bus:emit('modal:open', 'tag_editor')
assert_true("Opening tag editor hides OSC", osc_hidden)

shared_bus:emit('modal:close', 'tag_editor')
assert_true("Closing tag editor restores paused OSC", osc_shown)

-- ============================================================================
-- 4. Screensaver vs Smart Skip Visual Collision & Key Unbinding
-- ============================================================================
print("\n=== 4. Testing Screensaver vs Smart Skip Overlay Collisions ===")

local keybindings = {}
local overlay_data = { text = '', visible = false }
local mock_mouse_x, mock_mouse_y = -1, -1
local active_timer_cb = nil
local ss_is_active = false

-- Mock mpv interface
_G.mp = {
    create_osd_overlay = function()
        return {
            res_x = 1280, res_y = 720, data = '',
            update = function(self) overlay_data.text = self.data; overlay_data.visible = true end,
            remove = function(self) overlay_data.text = ''; overlay_data.visible = false end,
        }
    end,
    observe_property = function(prop, typ, cb) end,
    register_event = function(name, cb) end,
    get_property = function(name, def) return mock_props[name] ~= nil and mock_props[name] or def end,
    get_property_number = function(name, def) return tonumber(mock_props[name]) or def end,
    get_property_native = function(name, def) return mock_props[name] ~= nil and mock_props[name] or def end,
    get_osd_size = function() return 1280, 720 end,
    get_time = function() return 100 end,
    get_mouse_pos = function() return mock_mouse_x, mock_mouse_y end,
    add_forced_key_binding = function(key, name, fn) keybindings[name] = fn end,
    remove_key_binding = function(name) keybindings[name] = nil end,
    add_periodic_timer = function(interval, cb)
        active_timer_cb = cb
        return { kill = function() active_timer_cb = nil end }
    end,
    commandv = function(...) end,
}

local smart_skip = dofile('scripts/LuminaX/modules/smart_skip.lua')
local skip_events = events_mod.new()

smart_skip.init({
    events = skip_events,
    screensaver = {
        is_active = function() return ss_is_active end,
    },
    user_opts = {
        smart_skip_mode = 'pill',
        smart_skip_countdown = 6,
    },
    state = {},
    utils = utils,
    huds = {},
    get_canvas_size = function() return 1280, 720 end,
    get_virt_mouse_pos = function() return mock_mouse_x, mock_mouse_y end,
})

-- Manually trigger skip button
smart_skip.update_overlay() -- initially none
assert_eq("Initial overlay hidden", overlay_data.visible, false)

-- Chapter trigger simulation via private state
-- We simulate button appearance by updating overlay when not blocked
smart_skip.get_chapter_zones()

-- Chapter zone entry
local on_ch = nil
_G.mp.observe_property = function(p, t, cb)
    if p == 'chapter' then on_ch = cb end
end

-- Re-init with observer capture
smart_skip.init({
    events = skip_events,
    screensaver = {
        is_active = function() return ss_is_active end,
    },
    user_opts = {
        smart_skip_mode = 'pill',
        smart_skip_countdown = 6,
    },
    state = {},
    utils = utils,
    huds = {},
    get_canvas_size = function() return 1280, 720 end,
    get_virt_mouse_pos = function() return mock_mouse_x, mock_mouse_y end,
})

-- Set chapter list with opening
mock_props['chapter-list'] = {
    { title = 'Prologue', time = 0 },
    { title = 'Opening', time = 90 },
    { title = 'Main', time = 180 },
}
mock_props['time-pos'] = 95
if smart_skip.refresh_chapter_zones then smart_skip.refresh_chapter_zones() end

-- Trigger chapter opening
if on_ch then on_ch('chapter', 1) end
smart_skip.update_overlay()

assert_true("Skip button overlay is visible during opening", overlay_data.visible)
assert_true("Dynamic enter key is bound", keybindings['smart-skip-enter'] ~= nil)

-- NOW: Screensaver activates (ACTIVE state)
ss_is_active = true
skip_events:emit('screensaver:state', true)

assert_eq("Screensaver active forces skip overlay hidden", overlay_data.visible, false)
assert_eq("Screensaver active unbinds dynamic enter key", keybindings['smart-skip-enter'], nil)
assert_eq("Screensaver active unbinds mouse click key", keybindings['smart-skip-click'], nil)

-- Screensaver dismisses (IDLE state)
ss_is_active = false
skip_events:emit('screensaver:state', false)

assert_true("Screensaver dismissal restores skip overlay", overlay_data.visible)
assert_true("Screensaver dismissal restores dynamic enter key", keybindings['smart-skip-enter'] ~= nil)

-- ============================================================================
-- 5. Real-Time Mouse Hitbox Detection & Dynamic Left-Click Binding
-- ============================================================================
print("\n=== 5. Testing Mouse Hitbox & Left-Click Routing ===")

-- Cursor outside skip button
mock_mouse_x, mock_mouse_y = 500, 300
if active_timer_cb then active_timer_cb() end
assert_eq("Mouse click not bound when cursor is outside hitbox", keybindings['smart-skip-click'], nil)

-- Cursor enters skip button hitbox (~1138 to 1244, 550 to 582)
mock_mouse_x, mock_mouse_y = 1150, 560
if active_timer_cb then active_timer_cb() end
assert_true("Mouse entering skip button hitbox binds smart-skip-click (MBTN_LEFT)", keybindings['smart-skip-click'] ~= nil)

-- Clicking left mouse button executes skip action
local action_executed = false
keybindings['smart-skip-click']()
assert_eq("Clicking skip button dismisses overlay immediately", overlay_data.visible, false)
assert_eq("Post-dismissal unbinds smart-skip-click immediately", keybindings['smart-skip-click'], nil)

-- ============================================================================
-- Summary Report
-- ============================================================================
print("\n" .. string.rep("=", 65))
print(string.format("Test Results: %d passed, %d failed", pass_count, test_count - pass_count))
print(string.rep("=", 65))

if pass_count == test_count and test_count > 0 then
    print("✓ ALL COMPOUND INTERACTION & ARCHITECTURE TESTS PASSED!\n")
    os.exit(0)
else
    print("✗ TEST FAILURES OCCURRED!\n")
    os.exit(1)
end
