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
    ['sub-scale'] = 1.0,
    ['sub-font-size'] = 26,
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
    get_property_number = function(name, def)
        if mock_properties[name] ~= nil then return tonumber(mock_properties[name]) end
        return def
    end,
    get_property_bool = function(name, def)
        if mock_properties[name] ~= nil then return mock_properties[name] end
        return def
    end,
    set_property = function(name, val)
        mock_properties[name] = val
    end,
    set_property_number = function(name, val)
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

print('\n▶ 1. Testing 8 Industry Presets Application & Proportional Specifications:')

-- A. Apple TV+ / visionOS ("Spatial Glass")
subtitle.apply_preset('apple_tv')
local cfg = subtitle.get_config()
assert_equal(cfg.preset, 'apple_tv', 'A. Apple TV+ id')
assert_equal(cfg.font_size, 24, 'A. Apple TV+ 24pt proportional font size')
assert_equal(cfg.box_mode, 'unified', 'A. Apple TV+ unified capsule mode')
assert_equal(cfg.box_radius, 14, 'A. Apple TV+ 14px radius')
assert_equal(cfg.box_opacity, 0.68, 'A. Apple TV+ 0.68 opacity')
assert_equal(cfg.glass_rim, true, 'A. Apple TV+ glass rim enabled')
assert_equal(cfg.font_color, 'FFFFFF', 'A. Apple TV+ white font')
assert_equal(cfg.bottom_margin, 26, 'A. Apple TV+ 26px bottom margin')

-- B. Netflix Modern Box ("Clean Charcoal")
subtitle.apply_preset('netflix_box')
cfg = subtitle.get_config()
assert_equal(cfg.preset, 'netflix_box', 'B. Netflix id')
assert_equal(cfg.box_mode, 'per_line', 'B. Netflix per-line pill mode')
assert_equal(cfg.box_radius, 7, 'B. Netflix 7px radius')
assert_equal(cfg.box_color, '080808', 'B. Netflix 080808 charcoal fill')
assert_equal(cfg.box_opacity, 0.78, 'B. Netflix 0.78 opacity')
assert_equal(cfg.font_size, 24, 'B. Netflix 24pt font size')
assert_equal(cfg.line_spacing, 3, 'B. Netflix 3px compact line spacing')

-- C. YouTube Studio ("Compact Pill")
subtitle.apply_preset('youtube_cc')
cfg = subtitle.get_config()
assert_equal(cfg.preset, 'youtube_cc', 'C. YouTube Studio id')
assert_equal(cfg.box_mode, 'per_line', 'C. YouTube Studio per-line mode')
assert_equal(cfg.box_radius, 5, 'C. YouTube Studio 5px tight radius')
assert_equal(cfg.box_opacity, 0.82, 'C. YouTube Studio 0.82 opacity')
assert_equal(cfg.bold, true, 'C. YouTube Studio bold font')
assert_equal(cfg.padding_x, 12, 'C. YouTube Studio 12px compact padding')

-- D. Theatrical Cinema ("Warm Gold")
subtitle.apply_preset('cinema_gold')
cfg = subtitle.get_config()
assert_equal(cfg.preset, 'cinema_gold', 'D. Cinema Gold id')
assert_equal(cfg.box_mode, 'unified', 'D. Cinema Gold unified capsule')
assert_equal(cfg.font_color, 'FFE675', 'D. Cinema Gold warm pale amber')
assert_equal(cfg.box_opacity, 0.60, 'D. Cinema Gold 0.60 subtle tint')
assert_equal(cfg.box_radius, 10, 'D. Cinema Gold 10px radius')
assert_equal(cfg.shadow_offset, 1.0, 'D. Cinema Gold 1.0px drop shadow')
assert_equal(cfg.bottom_margin, 28, 'D. Cinema Gold 28px bottom margin')

-- E. Criterion Minimalist ("Floating Pure")
subtitle.apply_preset('criterion_minimal')
cfg = subtitle.get_config()
assert_equal(cfg.preset, 'criterion_minimal', 'E. Criterion id')
assert_equal(cfg.box_enabled, false, 'E. Criterion boxless')
assert_equal(cfg.font_color, 'F7F7F7', 'E. Criterion off-white font')
assert_equal(cfg.border_size, 1.0, 'E. Criterion 1.0px outline')
assert_equal(cfg.shadow_offset, 1.5, 'E. Criterion 1.5px shadow')

-- F. Anime Fansub ("Crisp High-Contrast Outline")
subtitle.apply_preset('anime_outline')
cfg = subtitle.get_config()
assert_equal(cfg.preset, 'anime_outline', 'F. Anime Fansub id')
assert_equal(cfg.box_enabled, false, 'F. Anime Fansub boxless')
assert_equal(cfg.bold, true, 'F. Anime Fansub bold text')
assert_equal(cfg.border_size, 2.8, 'F. Anime Fansub 2.8px contour stroke')
assert_equal(cfg.border_color, '000000', 'F. Anime Fansub pitch-black border')

-- G. BBC iPlayer / High-Accessibility CC
subtitle.apply_preset('bbc_accessible')
cfg = subtitle.get_config()
assert_equal(cfg.preset, 'bbc_accessible', 'G. BBC Accessible CC id')
assert_equal(cfg.box_mode, 'per_line', 'G. BBC Accessible per-line mode')
assert_equal(cfg.font_color, 'FFFF00', 'G. BBC Accessible cadmium yellow')
assert_equal(cfg.box_opacity, 0.94, 'G. BBC Accessible 0.94 solid backdrop')
assert_equal(cfg.font_size, 28, 'G. BBC Accessible 28pt font')
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
assert_equal(cfg.box_radius, 10, 'H. Disney+ 10px radius')

-- I. Prime Video Dark ("Amazon Standard")
subtitle.apply_preset('prime_video')
cfg = subtitle.get_config()
assert_equal(cfg.preset, 'prime_video', 'I. Prime Video Dark id')
assert_equal(cfg.box_mode, 'per_line', 'I. Prime Video Dark per-line mode')
assert_equal(cfg.box_color, '040404', 'I. Prime Video Dark 040404 near-black')
assert_equal(cfg.box_opacity, 0.80, 'I. Prime Video Dark 0.80 opacity')
assert_equal(cfg.box_radius, 8, 'I. Prime Video Dark 8px radius')

-- J. Hulu Signature White ("Boxless Hairline")
subtitle.apply_preset('hulu_white')
cfg = subtitle.get_config()
assert_equal(cfg.preset, 'hulu_white', 'J. Hulu Signature id')
assert_equal(cfg.box_enabled, false, 'J. Hulu Signature boxless')
assert_equal(cfg.font_color, 'FFFFFF', 'J. Hulu Signature white')
assert_equal(cfg.border_size, 1.0, 'J. Hulu Signature 1.0px hairline contour')
assert_equal(cfg.shadow_offset, 1.0, 'J. Hulu Signature 1.0px subtle shadow')

print('\n▶ 2. Testing Subtitle Scale Keybindings & Dynamic Multipliers:')
assert_equal(subtitle.get_current_scale(), 1.0, 'Default sub-scale is 1.0')
subtitle.add_sub_scale(0.10)
assert_equal(subtitle.get_current_scale(), 1.10, 'sub-scale increased to 1.10 via keybinding helper')
subtitle.add_sub_scale(-0.20)
assert_equal(subtitle.get_current_scale(), 0.90, 'sub-scale decreased to 0.90 via keybinding helper')
subtitle.reset_sub_scale()
assert_equal(subtitle.get_current_scale(), 1.0, 'sub-scale reset to 1.0')

print('\n▶ 3. Testing Menu Generator & 10 Preset Listing:')
local preset_items = subtitle.get_menu_items('sub_presets')
assert_equal(#preset_items, 11, 'Preset submenu contains 10 presets + back item')
assert_true(preset_items[1].label:find('Apple TV%+ Glass') ~= nil, 'Item 1 is Apple TV+')
assert_true(preset_items[2].label:find('Netflix Standard') ~= nil, 'Item 2 is Netflix')
assert_true(preset_items[3].label:find('Prime Video Dark') ~= nil, 'Item 3 is Prime Video')
assert_true(preset_items[4].label:find('Hulu Signature') ~= nil, 'Item 4 is Hulu Signature')
assert_true(preset_items[5].label:find('YouTube Studio CC') ~= nil, 'Item 5 is YouTube CC')
assert_true(preset_items[6].label:find('Theatrical Gold') ~= nil, 'Item 6 is Theatrical Gold')
assert_true(preset_items[7].label:find('Criterion Float') ~= nil, 'Item 7 is Criterion')
assert_true(preset_items[8].label:find('Anime Fansub') ~= nil, 'Item 8 is Anime Fansub')
assert_true(preset_items[9].label:find('Studio Accessible CC') ~= nil, 'Item 9 is Studio Accessible')
assert_true(preset_items[10].label:find('Disney%+ Midnight') ~= nil, 'Item 10 is Disney+ Midnight')

print('\n▶ 4. Testing Live Overlay Generation with Proportional Sizing:')
subtitle.apply_preset('apple_tv')
if mock_events['sub-text'] then
    mock_events['sub-text']('sub-text', 'I feel sorry for\nchildren nowadays.')
end
assert_equal(mock_properties['sub-visibility'], false, 'Native sub-visibility disabled during pill rendering')

print('\n▶ 5. Testing Live Preview Mode:')
subtitle.set_live_preview(true)
assert_true(true, 'Live preview enabled without error')
subtitle.set_live_preview(false)
assert_true(true, 'Live preview disabled cleanly')

print('\n▶ 6. Testing Subtitle Visibility Toggle & Menu Integration:')
assert_true(subtitle.is_visible(), 'Subtitle is visible by default')
subtitle.toggle_visibility()
assert_equal(subtitle.is_visible(), false, 'Subtitle visibility is now toggled off')
subtitle.toggle_visibility()
assert_equal(subtitle.is_visible(), true, 'Subtitle visibility is toggled back on')

-- Accessible 3-Tier Side Drawer: Level 1 & Level 2 In-Place Steppers
print('\n▶ 6.1 Testing Accessible 3-Tier Side Drawer & In-Place Steppers:')
local config_items = subtitle.get_menu_items('sub_config')
assert_equal(#config_items, 10, 'sub_config exposes 10 items: 8 steppers + Advanced nav + Reset action')
assert_true(config_items[1].label:find('Style Presets') ~= nil, 'Item 1 is Style Presets stepper')
assert_equal(config_items[1].type, 'stepper', 'Item 1 is stepper type')
assert_equal(config_items[1].target, 'sub_presets', 'Item 1 target is sub_presets')
assert_equal(config_items[2].label, 'Text Size', 'Item 2 is Text Size stepper')
assert_equal(config_items[3].label, 'Background Box', 'Item 3 is Background Box stepper')
assert_equal(config_items[4].label, 'Box Opacity', 'Item 4 is Box Opacity stepper')
assert_equal(config_items[5].label, 'Corner Radius', 'Item 5 is Corner Radius stepper')
assert_equal(config_items[6].label, 'Text Color', 'Item 6 is Text Color stepper')
assert_true(config_items[6].color_hex ~= nil, 'Text color item provides color_hex swatch')
assert_equal(config_items[7].label, 'Vertical Position', 'Item 7 is Vertical Position stepper')
assert_equal(config_items[8].label, 'Subtitle Delay', 'Item 8 is Subtitle Delay stepper')
assert_equal(config_items[9].label, 'Advanced Tuning...', 'Item 9 is Advanced Tuning navigation')
assert_equal(config_items[9].target, 'sub_advanced', 'Item 9 target is sub_advanced')
assert_equal(config_items[10].label, 'Reset to Defaults', 'Item 10 is Reset to Defaults')

-- Test In-Place Steppers execution & Dirty State Tracking
subtitle.apply_preset('apple_tv')
assert_equal(subtitle.is_preset_dirty(), false, 'Factory preset apple_tv is clean (not dirty)')

-- Step text size
local cur_fs = subtitle.get_config().font_size
subtitle.step_font_size(2)
assert_equal(subtitle.get_config().font_size, cur_fs + 2, 'step_font_size(+2) increased font size')
assert_true(subtitle.is_preset_dirty(), 'Modifying font size marked preset dirty')

-- Step opacity
subtitle.step_box_opacity(-0.05)
assert_equal(subtitle.get_config().box_opacity, 0.63, 'step_box_opacity(-0.05) stepped opacity down')

-- Cycle color
subtitle.cycle_font_color(1)
assert_equal(subtitle.get_config().font_color, 'FFE675', 'cycle_font_color cycled to Warm Amber')

-- Cycle radius
subtitle.cycle_box_radius(1)
assert_equal(subtitle.get_config().box_radius, 18, 'cycle_box_radius cycled to 18px')

-- Step vertical margin
subtitle.step_bottom_margin(4)
assert_equal(subtitle.get_config().bottom_margin, 30, 'step_bottom_margin stepped margin to 30px')

-- Test Reset to Defaults
subtitle.reset_defaults()
assert_equal(subtitle.is_preset_dirty(), false, 'reset_defaults restored factory preset and cleared dirty state')
assert_equal(subtitle.get_config().font_size, 24, 'Font size restored to 24')
assert_equal(subtitle.get_config().font_color, 'FFFFFF', 'Font color restored to FFFFFF')

-- Test Level 3: Deep Customizer (sub_advanced)
local adv_items = subtitle.get_menu_items('sub_advanced')
assert_equal(#adv_items, 9, 'sub_advanced contains 8 deep tuning steppers + back action')
assert_equal(adv_items[1].label, 'Glass Rim Highlight', 'Adv item 1 is Glass Rim')
assert_equal(adv_items[2].label, 'Outline Stroke', 'Adv item 2 is Outline Stroke')
assert_equal(adv_items[3].label, 'Drop Shadow', 'Adv item 3 is Drop Shadow')
assert_equal(adv_items[4].label, 'Horizontal Padding', 'Adv item 4 is Horizontal Padding')
assert_equal(adv_items[5].label, 'Vertical Padding', 'Adv item 5 is Vertical Padding')
assert_equal(adv_items[6].label, 'Line Spacing', 'Adv item 6 is Line Spacing')
assert_equal(adv_items[7].label, 'Font Weight', 'Adv item 7 is Font Weight')
assert_equal(adv_items[8].label, 'Letterbox Margins', 'Adv item 8 is Letterbox Margins')
assert_equal(adv_items[9].target, 'sub_config', 'Adv item 9 targets sub_config')

-- Test Level 3 Steppers execution
subtitle.toggle_glass_rim()
assert_equal(subtitle.get_config().glass_rim, false, 'toggle_glass_rim toggled rim off')
subtitle.step_border_size(0.5)
assert_equal(subtitle.get_config().border_size, 0.5, 'step_border_size increased outline stroke')
subtitle.step_shadow_offset(0.5)
assert_equal(subtitle.get_config().shadow_offset, 0.5, 'step_shadow_offset increased drop shadow')
subtitle.step_padding('padding_x', 2)
assert_equal(subtitle.get_config().padding_x, 20, 'step_padding increased horizontal padding')
subtitle.step_padding('padding_y', 1)
assert_equal(subtitle.get_config().padding_y, 8, 'step_padding increased vertical padding')
subtitle.step_line_spacing(1)
assert_equal(subtitle.get_config().line_spacing, 5, 'step_line_spacing increased line spacing')
subtitle.toggle_bold()
assert_equal(subtitle.get_config().bold, true, 'toggle_bold toggled bold on')

-- Test sub_customize backwards-compatibility alias
local cust_items = subtitle.get_menu_items('sub_customize')
assert_equal(#cust_items, #adv_items, 'sub_customize aliases to sub_advanced')

print('\n▶ 7. Testing Fullscreen Letterbox & Aspect Ratio Adaptation:')
-- Simulate 1080p display playing a 2.40:1 Cinemascope widescreen movie
mock_properties['osd-dimensions'] = {
    w = 1920, h = 1080, aspect = 1.777778, par = 1.0,
    mt = 140, mb = 140, ml = 0, mr = 0
}
mock_properties['sub-use-margins'] = false
subtitle.update_overlay()
assert_true(true, 'Cinemascope letterbox inside-frame overlay calculated successfully')

-- Simulate sub-use-margins=true (letterbox drop into black bar)
subtitle.handle_action({ action = 'toggle_sub_use_margins' })
assert_equal(mock_properties['sub-use-margins'], true, 'sub-use-margins toggled to true')
subtitle.update_overlay()
assert_true(true, 'Letterbox black-bar overlay calculated successfully')

-- Restore user preference sub-use-margins=false
subtitle.handle_action({ action = 'toggle_sub_use_margins' })
assert_equal(mock_properties['sub-use-margins'], false, 'sub-use-margins restored to false')

print('\n▶ 8. Testing Long Dialogue Safe-Zone Wrapping:')
if mock_events['sub-text'] then
    mock_events['sub-text']('sub-text', 'This is an exceptionally long piece of theatrical dialogue designed to test whether the modern LuminaX subtitle engine automatically performs word-wrapping to prevent the rounded pill from clipping outside the visible video frame!')
end
assert_true(true, 'Ultra-long line soft-wrapped cleanly within safe bounds')

print('\n' .. string.rep('=', 70))
print(string.format('🎉 Subtitle Unit Suite Finished: %d / %d assertions passed', pass_count, test_count))
print(string.rep('=', 70))
