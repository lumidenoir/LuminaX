-- ============================================================================
-- LuminaX Test Suite: Playlist Identification & Smart Skip Edge Cases
-- Validates episode detection, series context, chapter classification & false positives
-- ============================================================================

local utils = dofile('scripts/LuminaX/modules/utils.lua')

local passed = 0
local failed = 0

local function assert_eq(actual, expected, test_name)
    if actual == expected then
        passed = passed + 1
    else
        failed = failed + 1
        print(string.format('  ✗ FAIL: %s\n    Expected: %s\n    Actual:   %s', test_name, tostring(expected), tostring(actual)))
    end
end

local function assert_true(cond, test_name)
    if cond then
        passed = passed + 1
    else
        failed = failed + 1
        print(string.format('  ✗ FAIL: %s (expected true, got false/nil)', test_name))
    end
end

print('======================================================================')
print('▶ Testing Playlist Episode Identification & Edge Cases')
print('======================================================================')

-- 1. Standard Scene SxxExx
local l1, s1 = utils.resolve_episode_label(nil, 'Breaking.Bad.S01E02.1080p.BluRay.x264.mkv')
assert_eq(l1, 'S01E02', 'Standard Scene S01E02')
assert_eq(s1, 'Breaking Bad', 'Show name Breaking Bad')

local l2, s2 = utils.resolve_episode_label(nil, 'Game.of.Thrones.S08E06.2160p.UHD.HDR.mkv')
assert_eq(l2, 'S08E06', 'High-res Scene S08E06')

-- 2. Compact and Lowercase Formats
local l3 = utils.resolve_episode_label(nil, 'stranger.things.s1e5.webrip.mkv')
assert_eq(l3, 'S01E05', 'Compact s1e5')

local l4 = utils.resolve_episode_label(nil, 'The.Sopranos.1x05.HDTV.mkv')
assert_eq(l4, 'S01E05', 'Classic 1x05 notation')

local l5 = utils.resolve_episode_label(nil, 'The.Wire.02x10.mkv')
assert_eq(l5, 'S02E10', 'Two-digit season 02x10 notation')

-- 3. Standalone EP and E formats
local l6 = utils.resolve_episode_label(nil, 'Show.Name.EP05.mkv')
assert_eq(l6, 'Episode 05', 'Standalone EP05')

local l7 = utils.resolve_episode_label(nil, 'Show_Name_E12_1080p.mkv')
assert_eq(l7, 'Episode 12', 'Standalone E12')

-- 4. Anime Formats
local l8, s8 = utils.resolve_episode_label(nil, '[SubsPlease] Sousou no Frieren - 04 (1080p) [ABCD1234].mkv')
assert_eq(l8, 'Episode 04', 'Anime hyphen single episode')
assert_eq(s8, 'Sousou no Frieren', 'Anime title extraction')

local l9, s9 = utils.resolve_episode_label(nil, '[Erai-raws] Jujutsu Kaisen 2nd Season - 14 [1080p].mkv')
assert_eq(l9, 'S02E14', 'Anime explicit 2nd Season')

local l10 = utils.resolve_episode_label(nil, 'Bleach - 366 (720p).mkv')
assert_eq(l10, 'Episode 366', '3-digit anime episode 366')

local l11 = utils.resolve_episode_label(nil, 'One Piece - 1072.mkv')
assert_eq(l11, 'Episode 1072', '4-digit anime episode 1072 (not a release year)')

-- 5. Shows with Numbers in Title (Edge Cases)
local l12, s12 = utils.resolve_episode_label(nil, 'Mob Psycho 100 - 05.mkv')
assert_eq(l12, 'Episode 05', 'Mob Psycho 100 episode 5')
assert_eq(s12, 'Mob Psycho 100', 'Mob Psycho 100 title preserved')

local l13, s13 = utils.resolve_episode_label(nil, 'Cyberpunk 2077 - 01.mkv')
assert_eq(l13, 'Episode 01', 'Cyberpunk 2077 episode 1')
assert_eq(s13, 'Cyberpunk 2077', 'Cyberpunk 2077 title preserved')

local l14, s14 = utils.resolve_episode_label(nil, 'Studio 54 - S01E02.mkv')
assert_eq(l14, 'S01E02', 'Studio 54 S01E02')
assert_eq(s14, 'Studio 54', 'Studio 54 title preserved')

local l15, s15 = utils.resolve_episode_label(nil, '24 - S01E01.mkv')
assert_eq(l15, 'S01E01', 'Show 24 S01E01')
assert_eq(s15, '24', 'Show 24 title preserved')

local l16, s16 = utils.resolve_episode_label(nil, '1923 - S01E03.mkv')
assert_eq(l16, 'S01E03', 'Show 1923 S01E03')
assert_eq(s16, '1923', 'Show 1923 title preserved')

local l17, s17 = utils.resolve_episode_label(nil, '1923 - 04.mkv')
assert_eq(l17, 'Episode 04', 'Show 1923 single ep 04')
assert_eq(s17, '1923', 'Show 1923 title preserved')

-- 6. Non-Episodic Movies (Must NOT be detected as episodes! Must return nil label)
local movies = {
    'Inception (2010).1080p.BluRay.x264.mkv',
    '1917 (2019).2160p.UHD.mkv',
    'Blade.Runner.2049.2017.mkv',
    '2001 A Space Odyssey (1968).mkv',
    'The 40 Year Old Virgin (2005).mkv',
    'District 9 (2009).mkv',
    'Apollo 13 (1995).mkv',
    'Se7en (1995).mkv',
    'Oceans Eleven (2001).mkv',
    'Super 8 (2011).mkv',
}

for _, m in ipairs(movies) do
    local lbl = utils.resolve_episode_label(nil, m)
    assert_eq(lbl, nil, 'Movie not misidentified as episode: ' .. m)
end

print('\n======================================================================')
print('▶ Testing Chapter Type Classification & False Positive Guards')
print('======================================================================')

-- 1. Intro Matches
local intro_samples = {
    'OP', 'op', '[OP]', 'OP 1', 'OP2', 'Opening', 'Intro', 'Theme Song',
    'Episode 01 - OP', '[01:30] OP: Gurenge'
}
for _, sample in ipairs(intro_samples) do
    assert_eq(utils.match_chapter_type(sample), 'intro', 'Classified as intro: ' .. sample)
end

-- 2. Outro Matches
local outro_samples = {
    'ED', 'ed', '[ED]', 'ED 1', 'ED2', 'Ending', 'Outro', 'Credits', 'End Credits',
    'Preview', 'Next Episode Preview', 'Episode 01 - ED'
}
for _, sample in ipairs(outro_samples) do
    assert_eq(utils.match_chapter_type(sample), 'outro', 'Classified as outro: ' .. sample)
end

-- 3. Recap Matches
local recap_samples = {
    'Recap', 'recap', 'Previously', 'Previously on Lost', 'Episode Recap'
}
for _, sample in ipairs(recap_samples) do
    assert_eq(utils.match_chapter_type(sample), 'recap', 'Classified as recap: ' .. sample)
end

-- 4. False-Positive & Story Content Guards (Must return nil)
local strict_non_matches = {
    'Stop', 'Crop', 'Drop the Gun', 'Operation Overlord', 'Opening Scene',
    'Red Alert', 'Speed', 'Wedding', 'Bed of Roses', 'End of the Line',
    'End of Days', 'Chapter 01: The Beginning', 'Fight at the Warehouse', 'Main Feature',
    'Prologue', 'prologue', 'Prologue to War', 'Episode 01 - Prologue',
    'Epilogue', 'epilogue', 'Epilogue: A New Dawn', 'Final Epilogue'
}

for _, sample in ipairs(strict_non_matches) do
    assert_eq(utils.match_chapter_type(sample), nil, 'Guarded against false match: ' .. sample)
end

print('\n======================================================================')
print('▶ Testing Smart Skip Netflix Button, \\clip, Hover Freeze & Dismissal')
print('======================================================================')

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
                self.text = self.text .. string.format('m %s %s round_rect(%s,%s,%s,%s,r=%s)', tostring(x0), tostring(y0), tostring(x0), tostring(y0), tostring(x1), tostring(y1), tostring(r))
            end,
        }
        return obj
    end
}

local observers = {}
local keybindings = {}
local overlay_data = { text = '', visible = false }
local active_timer_cb = nil
local mock_now = 1000.0
local mock_mouse_x, mock_mouse_y = -1, -1
local mock_props = {
    ['filename'] = 'Sousou.no.Frieren.S01E02.mkv',
    ['media-title'] = 'Sousou no Frieren',
    ['time-pos'] = 90,
    ['duration'] = 1440,
    ['chapter'] = 0,
    ['seeking'] = false,
    ['chapter-list'] = {
        { title = 'Prologue', time = 0 },
        { title = 'Opening: Yuusha', time = 90 },
        { title = 'Episode 2', time = 180 },
        { title = 'Ending: Anytime Anywhere', time = 1320 },
        { title = 'Epilogue', time = 1410 },
    },
    ['playlist'] = {
        { filename = 'Sousou.no.Frieren.S01E02.mkv', title = 'Episode 2' },
        { filename = 'Sousou.no.Frieren.S01E03.mkv', title = 'Episode 3' },
    },
    ['playlist-pos'] = 0,
}

_G.mp = {
    create_osd_overlay = function()
        return {
            res_x = 1280, res_y = 720, data = '',
            update = function(self) overlay_data.text = self.data; overlay_data.visible = true end,
            remove = function(self) overlay_data.text = ''; overlay_data.visible = false end,
        }
    end,
    observe_property = function(prop, typ, cb) observers[prop] = cb end,
    register_event = function() end,
    get_property = function(name, def) return mock_props[name] ~= nil and mock_props[name] or def end,
    get_property_number = function(name, def) return tonumber(mock_props[name]) or def end,
    get_property_native = function(name, def) return mock_props[name] ~= nil and mock_props[name] or def end,
    get_osd_size = function() return 1280, 720 end,
    get_time = function() return mock_now end,
    get_mouse_pos = function() return mock_mouse_x, mock_mouse_y end,
    add_forced_key_binding = function(key, name, fn) keybindings[name] = fn end,
    remove_key_binding = function(name) keybindings[name] = nil end,
    add_periodic_timer = function(interval, cb)
        active_timer_cb = cb
        return { kill = function() active_timer_cb = nil end, cb = cb }
    end,
    commandv = function(...) end,
}

local mock_state = { osc_visible = false }
local smart_skip = dofile('scripts/LuminaX/modules/smart_skip.lua')
smart_skip.init({
    user_opts = {
        smart_skip_mode = 'pill',
        smart_skip_series_only = true,
        next_episode_card = true,
        smart_skip_countdown = 6,
        next_episode_countdown = 10,
    },
    state = mock_state,
    utils = utils,
    huds = {},
    request_tick = function() end,
    get_canvas_size = function() return 1280, 720 end,
    get_virt_mouse_pos = function() return mock_mouse_x, mock_mouse_y end,
})

-- 1. Prologue never triggers skip button
observers['chapter']('chapter', 0)
assert_eq(overlay_data.visible, false, 'Prologue chapter does not trigger skip button')

-- 2. Opening triggers Netflix \clip skip button
mock_now = mock_now + 0.15
observers['chapter']('chapter', 1)
assert_eq(overlay_data.visible, true, 'Opening chapter triggers skip button')
if active_timer_cb then
    mock_now = mock_now + 1.0
    active_timer_cb()
end
assert_true(overlay_data.text:find('\\clip') ~= nil, 'Opening skip button uses \\clip rectangular progress fill')
assert_true(overlay_data.text:find('0A84FF', 1, true) ~= nil, 'Progress uses Apple System Blue 0A84FF')
assert_true(overlay_data.text:find('SKIP') ~= nil, 'Opening button displays SKIP label')

-- 3. Stale button dismissal when seeking outside opening
mock_props['time-pos'] = 500
observers['time-pos']('time-pos', 500)
assert_eq(overlay_data.visible, false, 'Seeking outside opening immediately dismisses stale button')

-- 4. Clean transition between Opening and Ending (Mutual exclusion / zero stacking)
mock_props['time-pos'] = 95
observers['chapter']('chapter', 1)
assert_eq(overlay_data.visible, true, 'Opening active before transition')

mock_props['time-pos'] = 1330
mock_now = mock_now + 0.15
observers['chapter']('chapter', 3)
assert_eq(overlay_data.visible, true, 'Ending active after transition')
if active_timer_cb then
    mock_now = mock_now + 1.0
    active_timer_cb()
end
assert_true(overlay_data.text:find('NEXT') ~= nil, 'Transitions cleanly to NEXT without stacking')
assert_true(overlay_data.text:find('FF9500', 1, true) ~= nil, 'Ending progress uses Theme Orange FF9500')

-- 5. Epilogue never triggers button
observers['chapter']('chapter', 4)
assert_eq(overlay_data.visible, false, 'Epilogue chapter does not trigger button')

-- 6. Hover freeze & inverted styling
mock_props['time-pos'] = 95
mock_now = mock_now + 0.15
observers['chapter']('chapter', 1)
mock_mouse_x, mock_mouse_y = 1180, 560
if active_timer_cb then
    mock_now = mock_now + 0.15
    active_timer_cb()
end
assert_true(overlay_data.text:find('1a&HE0&', 1, true) ~= nil, 'Hovering draws menu translucent glass wash')
assert_true(overlay_data.text:find('SKIP') ~= nil, 'SKIP label remains visible on hover')

-- 7. Esc cancels wipe on first press and dismisses on second
if keybindings['smart-skip-esc'] then
    keybindings['smart-skip-esc']()
    assert_eq(overlay_data.visible, true, 'First Esc leaves button in static state')
    assert_true(overlay_data.text:find('SKIP') ~= nil, 'First Esc shows static label without countdown')

    keybindings['smart-skip-esc']()
    if active_timer_cb then
        mock_now = mock_now + 0.20
        active_timer_cb()
    end
    assert_eq(overlay_data.visible, false, 'Second Esc dismisses button completely')
end

-- 8. Any menu active state (Audio, Video, Sub, Chapters, Customization) hides skip button and unbinds keys
mock_props['time-pos'] = 95
mock_now = mock_now + 0.15
observers['chapter']('chapter', 1)
assert_eq(overlay_data.visible, true, 'Skip button active before menu opens')
assert_true(keybindings['smart-skip-enter'] ~= nil, 'Skip enter key bound before menu opens')

-- User opens audio menu
mock_state.menu_active = 'audio'
smart_skip.update_overlay()
assert_eq(overlay_data.visible, false, 'Opening audio menu hides skip button')
assert_eq(keybindings['smart-skip-enter'], nil, 'Opening menu unbinds skip enter key')

-- User switches to other menus
for _, m in ipairs({ 'chapters', 'video', 'sub', 'sub_config', 'playlist', 'tags' }) do
    mock_state.menu_active = m
    smart_skip.update_overlay()
    assert_eq(overlay_data.visible, false, 'Menu ' .. m .. ' keeps skip button hidden')
    assert_eq(keybindings['smart-skip-enter'], nil, 'Menu ' .. m .. ' keeps skip keys unbound')
end

-- User closes menu
mock_state.menu_active = nil
smart_skip.update_overlay()
assert_eq(overlay_data.visible, true, 'Closing menu restores skip button')
assert_true(keybindings['smart-skip-enter'] ~= nil, 'Closing menu rebinds skip enter key')

print('\n----------------------------------------------------------------------')
print(string.format('Test Results: %d passed, %d failed', passed, failed))
print('----------------------------------------------------------------------')

if failed > 0 then
    os.exit(1)
else
    print('✓ All playlist identification & smart skip edge case tests passed!\n')
    os.exit(0)
end
