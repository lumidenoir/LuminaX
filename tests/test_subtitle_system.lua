-- ============================================================================
-- Unit Test Suite: Subtitle Subsystem & Rounded Rectangle Architecture
-- ============================================================================

local test_count = 0
local pass_count = 0

local function assert_true(cond, msg)
    test_count = test_count + 1
    if cond then
        pass_count = pass_count + 1
        print('  ✓ PASS: ' .. (msg or 'assertion passed'))
    else
        print('  ✗ FAIL: ' .. (msg or 'assertion failed'))
        error('Assertion failed: ' .. (msg or ''))
    end
end

local function assert_equal(actual, expected, msg)
    test_count = test_count + 1
    if actual == expected then
        pass_count = pass_count + 1
        print(string.format('  ✓ PASS: %s (got %s)', msg or '', tostring(actual)))
    else
        print(string.format('  ✗ FAIL: %s (expected %s, got %s)', msg or '', tostring(expected), tostring(actual)))
        error(string.format('Expected %s, got %s', tostring(expected), tostring(actual)))
    end
end

print('======================================================================')
print('🧪 LuminaX Subtitle Subsystem & Rounded Rectangle Unit Tests')
print('======================================================================')

-- Mock MPV Environment
local mock_properties = {
    ['sub-text'] = '',
    ['sid'] = '1',
    ['sub-visibility'] = true,
}

local mock_events = {}
local mock_osd_messages = {}

_G.mp = {
    get_property = function(name, def)
        return mock_properties[name] or def
    end,
    get_property_native = function(name, def)
        return mock_properties[name] or def
    end,
    get_property_bool = function(name, def)
        if mock_properties[name] ~= nil then return mock_properties[name] end
        return def
    end,
    set_property = function(name, val)
        mock_properties[name] = val
    end,
    set_property_bool = function(name, val)
        mock_properties[name] = val
    end,
    observe_property = function(name, type_str, fn)
        mock_events[name] = fn
    end,
    get_osd_size = function()
        return 1280, 720
    end,
    osd_message = function(msg, dur)
        table.insert(mock_osd_messages, msg)
    end,
    create_osd_overlay = function(format)
        local ov = {
            res_x = 0,
            res_y = 0,
            data = '',
            visible = false,
            update = function(self) self.visible = true end,
            remove = function(self) self.visible = false; self.data = '' end,
        }
        return ov
    end,
    command_native = function() return nil end,
}

-- Mock assdraw
package.loaded['mp.assdraw'] = {
    ass_new = function()
        local obj = {
            text = '',
            new_event = function(self) self.text = self.text .. '\n[event]' end,
            pos = function(self, x, y) self.text = self.text .. string.format('{\\pos(%d,%d)}', x, y) end,
            an = function(self, a) self.text = self.text .. string.format('{\\an%d}', a) end,
            append = function(self, s) self.text = self.text .. s end,
            draw_start = function(self) self.text = self.text .. '{\\p1}' end,
            draw_stop = function(self) self.text = self.text .. '{\\p0}' end,
            round_rect_cw = function(self, x0, y0, x1, y1, r)
                self.text = self.text .. string.format('m %d %d round_rect(%d,%d,%d,%d,r=%d)', x0, y0, x0, y0, x1, y1, r)
            end,
        }
        return obj
    end
}

-- Load subtitle module
package.path = './scripts/LuminaX/?.lua;./scripts/LuminaX/modules/?.lua;' .. package.path
local subtitle = require('modules.subtitle')
local utils    = require('modules.utils')

subtitle.init({
    utils = utils,
    osc_param = {playresx = 1280, playresy = 720},
    request_tick = function() end,
})

print('\n▶ Testing Presets Application & State Validation:')
subtitle.apply_preset('visionos_pill')
local cfg = subtitle.get_config()
assert_equal(cfg.preset, 'visionos_pill', 'Preset is visionOS Pill')
assert_equal(cfg.mode, 'rounded_rect', 'Mode is rounded_rect')
assert_equal(cfg.box_enabled, true, 'Box is enabled')
assert_equal(cfg.box_radius, 14, 'Box radius is 14px')
assert_equal(cfg.text_color, '#FFFFFF', 'Text color is pure white')
assert_equal(cfg.box_rim_enabled, true, 'Glass rim is enabled')

subtitle.apply_preset('netflix_modern')
cfg = subtitle.get_config()
assert_equal(cfg.preset, 'netflix_modern', 'Preset is Netflix Modern')
assert_equal(cfg.box_radius, 8, 'Netflix box radius is 8px')
assert_equal(cfg.box_color, '#000000', 'Netflix box color is pitch black')
assert_equal(cfg.box_rim_enabled, false, 'Netflix box has no rim')

subtitle.apply_preset('cinema_yellow')
cfg = subtitle.get_config()
assert_equal(cfg.preset, 'cinema_yellow', 'Preset is Cinema Yellow')
assert_equal(cfg.text_color, '#FFE066', 'Text color is warm cinema yellow')
assert_equal(cfg.box_radius, 10, 'Cinema box radius is 10px')

subtitle.apply_preset('cyber_neon')
cfg = subtitle.get_config()
assert_equal(cfg.preset, 'cyber_neon', 'Preset is Cyberpunk Neon')
assert_equal(cfg.text_color, '#00F0FF', 'Text color is electric cyan')
assert_equal(cfg.box_rim_enabled, true, 'Cyan neon rim is enabled')

subtitle.apply_preset('anime_outline')
cfg = subtitle.get_config()
assert_equal(cfg.preset, 'anime_outline', 'Preset is Anime Outline')
assert_equal(cfg.mode, 'native', 'Mode switches to native for anime outline')
assert_equal(cfg.border_size, 3.2, 'Outline border is 3.2px')
assert_equal(cfg.box_enabled, false, 'Box is disabled for anime outline')

print('\n▶ Testing Menu Generator & Submenus:')
local root_items = subtitle.get_menu_items('sub_config')
assert_true(#root_items >= 7, 'Sub config has all primary sections')
assert_equal(root_items[1].target, 'sub_presets', 'Option 1 opens sub_presets')
assert_equal(root_items[2].target, 'sub_box', 'Option 2 opens sub_box')
assert_equal(root_items[3].target, 'sub_text', 'Option 3 opens sub_text')
assert_equal(root_items[4].target, 'sub_border', 'Option 4 opens sub_border')
assert_equal(root_items[5].target, 'sub_layout', 'Option 5 opens sub_layout')

local preset_items = subtitle.get_menu_items('sub_presets')
assert_true(#preset_items >= 7, 'Preset items contain all built-in styles')
assert_equal(subtitle.get_menu_title('sub_presets'), 'SUBTITLE STYLE PRESETS', 'Preset submenu title matches')

local box_items = subtitle.get_menu_items('sub_box')
assert_true(#box_items >= 8, 'Box styling items include radius, opacity, rim, and per-line')

print('\n▶ Testing Menu Action Handlers:')
-- Reset to visionOS pill
subtitle.handle_action({action = 'set_preset', preset_key = 'visionos_pill'})
cfg = subtitle.get_config()
assert_equal(cfg.preset, 'visionos_pill', 'Preset restored to visionos_pill')

-- Change box radius to 20
subtitle.handle_action({action = 'set_box_radius', val = 20})
cfg = subtitle.get_config()
assert_equal(cfg.box_radius, 20, 'Box radius adjusted to 20')
assert_equal(cfg.preset, 'custom', 'Preset marks as custom after fine-tuning')

-- Change font size to 44
subtitle.handle_action({action = 'set_font_size', val = 44})
cfg = subtitle.get_config()
assert_equal(cfg.font_size, 44, 'Font size adjusted to 44pt')

-- Change text color to Cinema Yellow
subtitle.handle_action({action = 'set_text_color', hex = '#FFE066'})
cfg = subtitle.get_config()
assert_equal(cfg.text_color, '#FFE066', 'Text color fine-tuned')

-- Toggle rim
subtitle.handle_action({action = 'toggle_box_rim'})
cfg = subtitle.get_config()
assert_equal(cfg.box_rim_enabled, false, 'Glass rim toggled to false')

print('\n▶ Testing Live Overlay & Rounded Rectangle Generation:')
subtitle.apply_preset('visionos_pill')
if mock_events['sub-text'] then
    mock_events['sub-text']('sub-text', 'Hello World!\nSecond Line of Dialogue')
end
assert_equal(mock_properties['sub-visibility'], false, 'Native sub-visibility disabled during pill overlay')

print('\n▶ Testing Live Preview Toggle:')
subtitle.set_live_preview(true)
assert_true(true, 'Live preview enabled without crashing')
subtitle.set_live_preview(false)
assert_true(true, 'Live preview disabled cleanly')

print('\n' .. string.rep('=', 70))
print(string.format('🎉 Subtitle Unit Suite Finished: %d / %d assertions passed', pass_count, test_count))
print(string.rep('=', 70))
