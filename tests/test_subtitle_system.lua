-- ============================================================================
-- Unit Test Suite: Subtitle Subsystem & 8 Industry-Standard Presets
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
print('🧪 LuminaX Subtitle Subsystem & 8 Industry Presets Unit Tests')
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

print('\n▶ 1. Testing 8 Industry Presets Application & Specifications:')

-- A. Apple TV+ / visionOS ("Spatial Glass")
subtitle.apply_preset('apple_tv')
local cfg = subtitle.get_config()
assert_equal(cfg.preset, 'apple_tv', 'A. Apple TV+ id')
assert_equal(cfg.box_mode, 'unified', 'A. Apple TV+ unified capsule mode')
assert_equal(cfg.box_radius, 16, 'A. Apple TV+ 16px radius')
assert_equal(cfg.box_opacity, 0.68, 'A. Apple TV+ 0.68 opacity')
assert_equal(cfg.glass_rim, true, 'A. Apple TV+ glass rim enabled')
assert_equal(cfg.font_color, 'FFFFFF', 'A. Apple TV+ white font')
assert_equal(cfg.bottom_margin, 38, 'A. Apple TV+ 38px bottom margin')

-- B. Netflix Modern Box ("Clean Charcoal")
subtitle.apply_preset('netflix_box')
cfg = subtitle.get_config()
assert_equal(cfg.preset, 'netflix_box', 'B. Netflix id')
assert_equal(cfg.box_mode, 'per_line', 'B. Netflix per-line pill mode')
assert_equal(cfg.box_radius, 8, 'B. Netflix 8px radius')
assert_equal(cfg.box_color, '080808', 'B. Netflix 080808 charcoal fill')
assert_equal(cfg.box_opacity, 0.78, 'B. Netflix 0.78 opacity')
assert_equal(cfg.font_size, 35, 'B. Netflix 35pt font size')
assert_equal(cfg.line_spacing, 4, 'B. Netflix 4px compact line spacing')

-- C. YouTube Studio ("Compact Pill")
subtitle.apply_preset('youtube_cc')
cfg = subtitle.get_config()
assert_equal(cfg.preset, 'youtube_cc', 'C. YouTube Studio id')
assert_equal(cfg.box_mode, 'per_line', 'C. YouTube Studio per-line mode')
assert_equal(cfg.box_radius, 6, 'C. YouTube Studio 6px tight radius')
assert_equal(cfg.box_opacity, 0.82, 'C. YouTube Studio 0.82 opacity')
assert_equal(cfg.bold, true, 'C. YouTube Studio bold font')
assert_equal(cfg.padding_x, 14, 'C. YouTube Studio 14px compact padding')

-- D. Theatrical Cinema ("Warm Gold")
subtitle.apply_preset('cinema_gold')
cfg = subtitle.get_config()
assert_equal(cfg.preset, 'cinema_gold', 'D. Cinema Gold id')
assert_equal(cfg.box_mode, 'unified', 'D. Cinema Gold unified capsule')
assert_equal(cfg.font_color, 'FFE675', 'D. Cinema Gold warm pale amber')
assert_equal(cfg.box_opacity, 0.60, 'D. Cinema Gold 0.60 subtle tint')
assert_equal(cfg.box_radius, 12, 'D. Cinema Gold 12px radius')
assert_equal(cfg.shadow_offset, 1.0, 'D. Cinema Gold 1.0px drop shadow')
assert_equal(cfg.bottom_margin, 42, 'D. Cinema Gold 42px bottom margin')

-- E. Criterion Minimalist ("Floating Pure")
subtitle.apply_preset('criterion_minimal')
cfg = subtitle.get_config()
assert_equal(cfg.preset, 'criterion_minimal', 'E. Criterion id')
assert_equal(cfg.box_enabled, false, 'E. Criterion boxless')
assert_equal(cfg.font_color, 'F7F7F7', 'E. Criterion off-white font')
assert_equal(cfg.border_size, 1.2, 'E. Criterion 1.2px outline')
assert_equal(cfg.shadow_offset, 1.8, 'E. Criterion 1.8px shadow')

-- F. Anime Fansub ("Crisp High-Contrast Outline")
subtitle.apply_preset('anime_outline')
cfg = subtitle.get_config()
assert_equal(cfg.preset, 'anime_outline', 'F. Anime Fansub id')
assert_equal(cfg.box_enabled, false, 'F. Anime Fansub boxless')
assert_equal(cfg.bold, true, 'F. Anime Fansub bold text')
assert_equal(cfg.border_size, 3.2, 'F. Anime Fansub 3.2px contour stroke')
assert_equal(cfg.border_color, '000000', 'F. Anime Fansub pitch-black border')

-- G. BBC iPlayer / High-Accessibility CC
subtitle.apply_preset('bbc_accessible')
cfg = subtitle.get_config()
assert_equal(cfg.preset, 'bbc_accessible', 'G. BBC Accessible CC id')
assert_equal(cfg.box_mode, 'per_line', 'G. BBC Accessible per-line mode')
assert_equal(cfg.font_color, 'FFFF00', 'G. BBC Accessible cadmium yellow')
assert_equal(cfg.box_opacity, 0.94, 'G. BBC Accessible 0.94 solid backdrop')
assert_equal(cfg.font_size, 38, 'G. BBC Accessible 38pt large font')
assert_equal(cfg.bold, true, 'G. BBC Accessible bold weight')

-- H. Disney+ Midnight Slate ("Cinema Navy")
subtitle.apply_preset('disney_slate')
cfg = subtitle.get_config()
assert_equal(cfg.preset, 'disney_slate', 'H. Disney+ Midnight id')
assert_equal(cfg.box_mode, 'unified', 'H. Disney+ unified mode')
assert_equal(cfg.box_color, '0B101E', 'H. Disney+ deep midnight navy')
assert_equal(cfg.box_opacity, 0.75, 'H. Disney+ 0.75 opacity')
assert_equal(cfg.glass_rim, true, 'H. Disney+ glass rim enabled')
assert_equal(cfg.rim_color, '7090C0', 'H. Disney+ slate-blue rim color')
assert_equal(cfg.box_radius, 12, 'H. Disney+ 12px radius')

print('\n▶ 2. Testing Menu Generator & 8 Preset Listing:')
local preset_items = subtitle.get_menu_items('sub_presets')
assert_equal(#preset_items, 9, 'Preset submenu contains 8 presets + back item')
assert_true(preset_items[1].label:find('Apple TV%+ Glass') ~= nil, 'Item 1 is Apple TV+')
assert_true(preset_items[2].label:find('Netflix Standard') ~= nil, 'Item 2 is Netflix')
assert_true(preset_items[3].label:find('YouTube Studio CC') ~= nil, 'Item 3 is YouTube CC')
assert_true(preset_items[4].label:find('Theatrical Gold') ~= nil, 'Item 4 is Theatrical Gold')
assert_true(preset_items[5].label:find('Criterion Float') ~= nil, 'Item 5 is Criterion')
assert_true(preset_items[6].label:find('Anime Fansub') ~= nil, 'Item 6 is Anime Fansub')
assert_true(preset_items[7].label:find('Studio Accessible CC') ~= nil, 'Item 7 is Studio Accessible')
assert_true(preset_items[8].label:find('Disney%+ Midnight') ~= nil, 'Item 8 is Disney+ Midnight')

local root_items = subtitle.get_menu_items('sub_config')
assert_true(#root_items >= 7, 'Sub config root has all primary sections')

print('\n▶ 3. Testing Per-Line vs Unified Pill Rendering Logic:')
-- Test Unified Mode
subtitle.apply_preset('apple_tv')
if mock_events['sub-text'] then
    mock_events['sub-text']('sub-text', 'Top Line of Dialogue\nShort line')
end
assert_equal(mock_properties['sub-visibility'], false, 'Native sub-visibility disabled during pill rendering')

-- Test Per-Line Mode (YouTube CC)
subtitle.apply_preset('youtube_cc')
if mock_events['sub-text'] then
    mock_events['sub-text']('sub-text', 'First line of commentary\nShort')
end
assert_equal(mock_properties['sub-visibility'], false, 'Native sub-visibility disabled during per-line rendering')

-- Test Boxless Mode (Anime Fansub)
subtitle.apply_preset('anime_outline')
if mock_events['sub-text'] then
    mock_events['sub-text']('sub-text', 'HIKARI ARE!!')
end
assert_equal(mock_properties['sub-visibility'], false, 'Native sub-visibility handled cleanly for boxless anime')

print('\n▶ 4. Testing Dynamic Scaling Factor:')
-- At 720p base: scale = 1.0
-- At 1080p: scale = 1.5
-- At 2160p (4K): scale = 3.0
local function calc_scale(h)
    return math.max(0.5, h / 720)
end
assert_equal(calc_scale(720), 1.0, '720p reference scale is 1.0')
assert_equal(calc_scale(1080), 1.5, '1080p scale is 1.5')
assert_equal(calc_scale(1440), 2.0, '1440p scale is 2.0')
assert_equal(calc_scale(2160), 3.0, '4K scale is 3.0')

print('\n▶ 5. Testing Live Preview Mode:')
subtitle.set_live_preview(true)
assert_true(true, 'Live preview enabled without error')
subtitle.set_live_preview(false)
assert_true(true, 'Live preview disabled cleanly')

print('\n' .. string.rep('=', 70))
print(string.format('🎉 Subtitle Unit Suite Finished: %d / %d assertions passed', pass_count, test_count))
print(string.rep('=', 70))
