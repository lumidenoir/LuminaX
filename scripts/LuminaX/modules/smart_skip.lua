-- ============================================================================
-- LuminaX Module: Smart Skip & Next Episode Binge System
-- Netflix-Style Progress Button: Option B Embedded Floor Rail, Hotkey Keycap,
-- Integrated Micro-Pill Context Chip, and 120ms/150ms Kinetic Micro-Motion
-- ============================================================================

local assdraw = require('mp.assdraw')

local M = {}

local ctx_ref = {}
local user_opts = {}
local state = {}
local utils_mod = nil
local huds_mod = nil
local request_tick = function() end

local overlay = mp.create_osd_overlay('ass-events')
overlay.z = 2000

-- Single unified active button to strictly prevent overlays or stacking
-- {
--   kind = 'skip' | 'next_ep',
--   type = 'intro' | 'outro' | 'recap',
--   target_time = num,
--   valid_start = num,
--   valid_end = num,
--   label = str,
--   sub_label = str,
--   total_sec = num,
--   elapsed = num,
--   is_active = bool,
--   is_hover = bool,
--   timer = obj,
--   last_tick = num,
--   hitbox = { x1, y1, x2, y2 },
--   anim_state = 'enter' | 'active' | 'exit',
--   enter_start = num,
--   exit_start = num,
--   anim_alpha = num,
--   y_offset = num,
--   manual_dismiss = bool,
-- }
local active_btn = nil
local chapter_zones = {}
local dynamic_keys_bound = false
local manual_dismiss_until = nil

local function is_series_context()
    if not utils_mod then return false end
    local fn = mp.get_property('filename')
    local mt = mp.get_property('media-title')
    local fp = mp.get_property('path')
    local label = utils_mod.resolve_episode_label(mt, fn, fp)
    if label and label ~= '' then return true end

    -- Check TMDB context
    if ctx_ref.get_tmdb_current then
        local tmdb = ctx_ref.get_tmdb_current()
        if tmdb and (tmdb.is_series or (tmdb.genres and tmdb.genres:lower():find('animation'))) then
            return true
        end
    end
    return false
end

local function is_any_menu_active()
    if ctx_ref and ctx_ref.is_menu_active and ctx_ref.is_menu_active() then
        return true
    end
    if state and (state.menu_active ~= nil or state.tag_editor_active) then
        return true
    end
    return false
end

local function unbind_dynamic_keys()
    if dynamic_keys_bound then
        pcall(mp.remove_key_binding, 'smart-skip-enter')
        pcall(mp.remove_key_binding, 'smart-skip-kp-enter')
        pcall(mp.remove_key_binding, 'smart-skip-esc')
        dynamic_keys_bound = false
    end
end

local function dismiss_immediate(manual)
    if active_btn then
        if active_btn.timer then
            active_btn.timer:kill()
            active_btn.timer = nil
        end
        if manual then
            manual_dismiss_until = active_btn.valid_end or (mp.get_property_number('time-pos', 0) + 10)
        end
        active_btn = nil
    end

    unbind_dynamic_keys()
    overlay:remove()
    request_tick()
end

local function dismiss_all(manual, immediate)
    if not active_btn then return end

    if immediate or not active_btn.timer then
        dismiss_immediate(manual)
        return
    end

    -- 150ms kinetic dismissal glide (+6px downward drift and linear fade-out)
    if active_btn.anim_state ~= 'exit' then
        active_btn.anim_state = 'exit'
        active_btn.exit_start = mp.get_time()
        active_btn.manual_dismiss = manual
        unbind_dynamic_keys()
    end
end

local function execute_action()
    if not active_btn then return end
    local btn = active_btn
    local target = tonumber(btn.target_time)
    local ptype = btn.type
    local kind = btn.kind

    -- Dismiss immediately on activation
    dismiss_all(false, true)

    if kind == 'skip' then
        if target and target > 0 then
            mp.commandv('seek', target, 'absolute+exact')
        end
        if huds_mod and huds_mod.show_pill then
            local hud_label = (ptype == 'intro') and 'Skipped Opening'
                              or ((ptype == 'recap') and 'Skipped Recap' or 'Skipped Ending')
            huds_mod.show_pill('\238\129\150', hud_label)
        end
    elseif kind == 'next_ep' then
        mp.commandv('playlist-next')
    end
end

local function handle_esc()
    if not active_btn then return end
    if active_btn.is_active then
        -- User pressed Esc while countdown is active:
        -- Stop countdown, leaving the button in a clean static state without auto-skipping
        active_btn.is_active = false
        active_btn.elapsed = 0
        if M.update_overlay then
            M.update_overlay()
        end
    else
        -- User pressed Esc while already static: initiate smooth dismissal
        dismiss_all(true, false)
    end
end

local function bind_dynamic_keys()
    if not dynamic_keys_bound then
        mp.add_forced_key_binding('ENTER', 'smart-skip-enter', execute_action)
        mp.add_forced_key_binding('KP_ENTER', 'smart-skip-kp-enter', execute_action)
        mp.add_forced_key_binding('ESC', 'smart-skip-esc', handle_esc)
        dynamic_keys_bound = true
    end
end

local function get_dimensions()
    if ctx_ref.get_canvas_size then
        local w, h = ctx_ref.get_canvas_size()
        if w and w > 0 and h and h > 0 then
            return w, h
        end
    end
    local d_w, d_h = mp.get_osd_size()
    return d_w or 1280, d_h or 720
end

local function get_mouse_coords()
    if ctx_ref.get_virt_mouse_pos then
        local mx, my = ctx_ref.get_virt_mouse_pos()
        if mx and my and mx >= 0 and my >= 0 then
            return mx, my
        end
    end
    local mx, my = mp.get_mouse_pos()
    if not mx or not my then return -1, -1 end
    local cw, ch = get_dimensions()
    local ow, oh = mp.get_osd_size()
    if ow and ow > 0 and oh and oh > 0 then
        return mx * (cw / ow), my * (ch / oh)
    end
    return mx, my
end

-- Converts base opacity hex to dynamic alpha taking kinetic transitions into account
local function to_hex_alpha(base_dec, anim_alpha)
    local opacity = (1.0 - (base_dec / 255.0)) * (anim_alpha or 1.0)
    local final_dec = math.floor((1.0 - opacity) * 255.0 + 0.5)
    final_dec = math.max(0, math.min(255, final_dec))
    return string.format('%02X', final_dec)
end

-- Character and text width estimation for pixel-precise content-hugged layouts
local function estimate_char_width(b, fs, is_bold)
    local base = (b == 73 or b == 74) and 0.30  -- Uppercase I, J (narrow)
        or (b == 87 or b == 77) and 0.80        -- Uppercase W, M (wide)
        or (b >= 65 and b <= 90) and 0.58       -- Other Uppercase
        or (b == 105 or b == 108) and 0.28      -- Lowercase i, l
        or (b == 119 or b == 109) and 0.75      -- Lowercase w, m
        or (b >= 97 and b <= 122) and 0.48      -- Other Lowercase
        or (b >= 48 and b <= 57) and 0.52       -- Digits
        or (b == 32) and 0.28                   -- Space
        or (b == 58 or b == 46 or b == 44) and 0.25 -- Colon, dot, comma
        or (b == 40 or b == 41) and 0.32        -- Parentheses
        or (b == 45 or b == 95) and 0.32        -- Dash, underscore
        or (b == 183) and 0.32                  -- Middle dot
        or 0.50                                  -- Fallback
    if is_bold then base = base * 1.05 end
    return base * fs
end

local function estimate_text_width(str, fs, is_bold)
    if not str or str == '' then return 0 end
    local w = 0
    local i = 1
    local len = #str
    while i <= len do
        local b = string.byte(str, i)
        local step = 1
        if b >= 0xF0 then step = 4
        elseif b >= 0xE0 then step = 3
        elseif b >= 0xC0 then step = 2
        end
        w = w + estimate_char_width(b, fs, is_bold)
        i = i + step
    end
    return math.ceil(w)
end

-- ============================================================================
-- LuminaX Simple Rounded Rectangle: Option B Floor Rail & Inline Return
-- ============================================================================
local function draw_netflix_progress_button(ass, cfg)
    local x = cfg.x
    local y = cfg.y + (cfg.y_offset or 0)
    local w = cfg.width or 115
    local h = cfg.height or 32
    local r = cfg.radius or 8
    local anim_alpha = cfg.anim_alpha or 1.0
    local is_hover = cfg.is_hover
    local progress = math.max(0, math.min(1, cfg.progress or 0))
    local main_label = cfg.main_label or 'SKIP'
    local countdown_sec = cfg.countdown_sec
    local font_name = cfg.font_name or 'Inter'
    local fs = cfg.font_size or 12

    -- ------------------------------------------------------------------------
    -- LAYER 1: Ambient Drop Shadow for Floating Elevation
    -- ------------------------------------------------------------------------
    ass:new_event()
    ass:pos(0, 0)
    ass:an(7)
    ass:append(string.format('{\\bord0\\shad0\\1c&H000000&\\1a&H%s&}',
        to_hex_alpha(0xB0, anim_alpha)))
    ass:draw_start()
    ass:round_rect_cw(x - 2, y - 1, x + w + 2, y + h + 3, r + 2)
    ass:draw_stop()

    -- ------------------------------------------------------------------------
    -- LAYER 2: Base Container (Frosted Obsidian Glass Rounded Rectangle)
    -- ------------------------------------------------------------------------
    local rim_a = is_hover and 0x90 or 0xD0
    local bg_a = is_hover and 0x08 or 0x18
    ass:new_event()
    ass:pos(0, 0)
    ass:an(7)
    ass:append(string.format('{\\bord1.2\\blur0.4\\3c&HFFFFFF&\\3a&H%s&\\shad0\\1c&H121210&\\1a&H%s&}',
        to_hex_alpha(rim_a, anim_alpha), to_hex_alpha(bg_a, anim_alpha)))
    ass:draw_start()
    ass:round_rect_cw(x, y, x + w, y + h, r)
    ass:draw_stop()

    -- Soft translucent luminous wash on hover (matches menu.lua line 1898)
    if is_hover then
        ass:new_event()
        ass:pos(0, 0)
        ass:an(7)
        ass:append(string.format('{\\bord0\\blur0\\1c&HFFFFFF&\\1a&H%s&}',
            to_hex_alpha(0xE0, anim_alpha)))
        ass:draw_start()
        ass:round_rect_cw(x, y, x + w, y + h, r)
        ass:draw_stop()
    end

    -- ------------------------------------------------------------------------
    -- LAYER 3: Option B - Embedded Bottom Floor Rail
    -- ------------------------------------------------------------------------
    local rh = 2
    local ry = math.floor(y + h - 3)
    local rx1 = math.floor(x + r + 2)
    local rx2 = math.floor(x + w - r - 2)
    local rw = rx2 - rx1

    -- Inactive floor groove
    local groove_alpha = is_hover and 0xD8 or 0xE8
    ass:new_event()
    ass:pos(0, 0)
    ass:an(7)
    ass:append(string.format('{\\bord0\\shad0\\1c&HFFFFFF&\\1a&H%s&}',
        to_hex_alpha(groove_alpha, anim_alpha)))
    ass:draw_start()
    ass:round_rect_cw(rx1, ry, rx2, ry + rh, 1)
    ass:draw_stop()

    -- Active progress fill: Apple System Blue &H0A84FF& for Intro/OP, Theme Orange &HFF9500& for Outro/ED
    if progress > 0 then
        local is_outro = (cfg.ptype == 'outro') or (cfg.kind == 'next_ep')
        local rail_col = is_outro and 'FF9500' or '0A84FF'
        local fill_right = math.floor(rx1 + (rw * progress))
        ass:new_event()
        ass:pos(0, 0)
        ass:an(7)
        ass:append(string.format('{\\clip(%d,%d,%d,%d)\\bord0\\shad0\\1c&H%s&\\1a&H%s&}',
            rx1, ry - 1, fill_right, ry + rh + 1,
            rail_col,
            to_hex_alpha(0x00, anim_alpha)))
        ass:draw_start()
        ass:round_rect_cw(rx1, ry, rx2, ry + rh, 1)
        ass:draw_stop()
    end

    -- ------------------------------------------------------------------------
    -- LAYER 4: Two-Tier Typographic Hierarchy with Seamless Inline Return
    -- ------------------------------------------------------------------------
    local main_col = "FFFFFF"
    local sub_col = is_hover and "E5E5EA" or "8E8E93"
    local enter_col = is_hover and "FFFFFF" or "8E8E93"

    ass:new_event()
    ass:pos(x + math.floor(w / 2), y + math.floor(h / 2) - 1)
    ass:an(5) -- Middle-center alignment

    if countdown_sec then
        ass:append(string.format(
            '{\\q2\\fn%s\\b700\\fs%d\\fsp1\\1c&H%s&\\1a&H%s&\\bord0\\shad0}%s  ' ..
            '{\\q2\\fn%s\\b500\\fs11\\fsp0.5\\1c&H%s&\\1a&H%s&\\bord0\\shad0}(%ds)  ' ..
            '{\\q2\\fn%s\\b600\\fs10\\fsp1\\1c&H%s&\\1a&H%s&\\bord0\\shad0}⏎',
            font_name, fs, main_col, to_hex_alpha(0x00, anim_alpha), main_label:upper(),
            font_name, sub_col, to_hex_alpha(0x00, anim_alpha), countdown_sec,
            font_name, enter_col, to_hex_alpha(0x00, anim_alpha)))
    else
        ass:append(string.format(
            '{\\q2\\fn%s\\b700\\fs%d\\fsp1\\1c&H%s&\\1a&H%s&\\bord0\\shad0}%s  ' ..
            '{\\q2\\fn%s\\b600\\fs10\\fsp1\\1c&H%s&\\1a&H%s&\\bord0\\shad0}⏎',
            font_name, fs, main_col, to_hex_alpha(0x00, anim_alpha), main_label:upper(),
            font_name, enter_col, to_hex_alpha(0x00, anim_alpha)))
    end
end

function M.update_overlay()
    if not active_btn then
        unbind_dynamic_keys()
        overlay:remove()
        return
    end

    -- Strictly hide skip button & unbind hotkeys while any menu is open
    if is_any_menu_active() then
        unbind_dynamic_keys()
        overlay:remove()
        return
    end

    if active_btn.is_active and not dynamic_keys_bound then
        bind_dynamic_keys()
    end

    local d_w, d_h = get_dimensions()
    if not d_w or d_w <= 0 or not d_h or d_h <= 0 then return end

    overlay.res_x = d_w
    overlay.res_y = d_h
    overlay.z = 2000

    local ass = assdraw.ass_new()
    local font_name = (user_opts and user_opts.font) or 'Inter'

    -- Calculate current progress and countdown
    local progress = 0
    local rem_sec = nil
    if active_btn.is_active then
        rem_sec = math.max(0, math.ceil(active_btn.total_sec - (active_btn.elapsed or 0)))
        progress = math.max(0, math.min(1, (active_btn.elapsed or 0) / active_btn.total_sec))
    else
        progress = 0
        rem_sec = nil
    end

    local main_label = active_btn.label or 'Skip'
    local main_w = estimate_text_width(main_label:upper(), 12, true)
    local cd_w = rem_sec and (estimate_text_width(string.format(' (%ds)', rem_sec), 11, false) + 4) or 0
    local enter_w = 16

    local content_w = main_w + cd_w + enter_w
    local b_w = math.max(104, content_w + 32)
    local b_h = 32
    local b_r = 8
    local b_x = d_w - b_w - 36
    -- Constant height elevated comfortably above the bottom OSC controls, seekbar, and scrim:
    local bottom_margin = tonumber(user_opts and user_opts.smart_skip_bottom_margin) or 170
    local b_y = d_h - bottom_margin

    -- Hitbox strictly bounds the unified rounded rectangle
    active_btn.hitbox = { x1 = b_x, y1 = b_y, x2 = b_x + b_w, y2 = b_y + b_h }

    draw_netflix_progress_button(ass, {
        x             = b_x,
        y             = b_y,
        y_offset      = active_btn.y_offset or 0,
        anim_alpha    = active_btn.anim_alpha or 1.0,
        width         = b_w,
        height        = b_h,
        radius        = b_r,
        progress      = progress,
        is_hover      = active_btn.is_hover,
        main_label    = main_label,
        countdown_sec = rem_sec,
        font_name     = font_name,
        font_size     = 12,
        ptype         = active_btn.type,
        kind          = active_btn.kind,
    })

    overlay.data = ass.text
    overlay:update()
end

local function start_button_loop()
    if not active_btn then return end
    if active_btn.timer then
        active_btn.timer:kill()
        active_btn.timer = nil
    end

    active_btn.last_tick = mp.get_time()

    -- 30 FPS animation loop for buttery smooth kinetic entry/exit and rail progress
    active_btn.timer = mp.add_periodic_timer(0.033, function()
        if not active_btn then return end

        -- Freeze countdown and hide overlay while any menu is open
        if is_any_menu_active() then
            M.update_overlay()
            return
        end

        local now = mp.get_time()
        local dt = now - (active_btn.last_tick or now)
        active_btn.last_tick = now

        -- 1. Animation transition processing (Entry / Exit)
        if active_btn.anim_state == 'enter' then
            local t = (now - (active_btn.enter_start or now)) / 0.12
            if t >= 1.0 then
                active_btn.anim_state = 'active'
                active_btn.anim_alpha = 1.0
                active_btn.y_offset = 0
                local inv = 1.0 - t
                local ease = 1.0 - (inv * inv * inv)
                active_btn.anim_alpha = ease
                active_btn.y_offset = math.floor((1.0 - ease) * 10)
            end
        elseif active_btn.anim_state == 'exit' then
            local t = (now - (active_btn.exit_start or now)) / 0.15
            if t >= 1.0 then
                dismiss_immediate(active_btn.manual_dismiss)
                return
            else
                active_btn.anim_alpha = math.max(0, 1.0 - t)
                active_btn.y_offset = math.floor(t * 6)
            end
            M.update_overlay()
            return
        end

        -- 2. Mouse hover detection
        local mx, my = get_mouse_coords()
        local is_hover = false
        if active_btn.hitbox and mx >= active_btn.hitbox.x1 and mx <= active_btn.hitbox.x2
           and my >= active_btn.hitbox.y1 and my <= active_btn.hitbox.y2 then
            is_hover = true
        end

        local hover_changed = (active_btn.is_hover ~= is_hover)
        active_btn.is_hover = is_hover

        -- 3. Countdown progression
        if active_btn.is_active then
            -- Micro-UX: Hover freezes timer and pauses progress rail
            if not is_hover then
                active_btn.elapsed = (active_btn.elapsed or 0) + dt
                local progress = active_btn.elapsed / active_btn.total_sec
                if progress >= 1.0 then
                    -- 100% reached -> fire skip or next episode
                    execute_action()
                    return
                end
            end
            M.update_overlay()
        elseif hover_changed or active_btn.anim_state == 'enter' then
            M.update_overlay()
        end
    end)
end

-- ============================================================================
-- Button Trigger Methods (Strict Mutual Exclusion: Always dismiss first)
-- ============================================================================
local function trigger_skip_pill(stype, start_time, end_time, title)
    -- Dismiss any active button immediately first to prevent button overlaying
    dismiss_all(false, true)

    local cd = tonumber(user_opts.smart_skip_countdown) or 6.0
    local now = mp.get_time()
    active_btn = {
        kind           = 'skip',
        type           = stype,
        target_time    = end_time,
        valid_start    = start_time or 0,
        valid_end      = end_time or 999999,
        label          = 'Skip',
        sub_label      = nil,
        total_sec      = cd,
        elapsed        = 0,
        is_active      = true,
        is_hover       = false,
        anim_state     = 'enter',
        enter_start    = now,
        anim_alpha     = 0.0,
        y_offset       = 10,
        manual_dismiss = false,
    }

    bind_dynamic_keys()
    M.update_overlay()
    start_button_loop()
end

local function trigger_next_episode_card(start_time, end_time)
    -- Dismiss any active button immediately first to prevent button overlaying
    dismiss_all(false, true)

    local pl = mp.get_property_native('playlist', {})
    local cur_idx = mp.get_property_number('playlist-pos', -1) + 1
    if cur_idx <= 0 or cur_idx >= #pl then return end

    local next_item = pl[cur_idx + 1]
    if not next_item or not next_item.filename then return end

    local cd = tonumber(user_opts.next_episode_countdown) or 10.0
    local now = mp.get_time()
    active_btn = {
        kind           = 'next_ep',
        type           = 'outro',
        target_time    = nil,
        valid_start    = start_time or 0,
        valid_end      = end_time or 999999,
        label          = 'Next',
        sub_label      = nil,
        total_sec      = cd,
        elapsed        = 0,
        is_active      = true,
        is_hover       = false,
        anim_state     = 'enter',
        enter_start    = now,
        anim_alpha     = 0.0,
        y_offset       = 10,
        manual_dismiss = false,
    }

    bind_dynamic_keys()
    M.update_overlay()
    start_button_loop()
end

-- ============================================================================
-- Position Validation: Stale Button Dismissal When Moving Outside Zone
-- ============================================================================
local function validate_active_button_position()
    if not active_btn then return end
    local pos = mp.get_property_number('time-pos', 0) or 0

    -- If playback position is outside the active button's valid time range,
    -- the button is useless and must be dismissed immediately.
    if pos < (active_btn.valid_start - 0.5) or pos >= active_btn.valid_end then
        dismiss_all(false, true)
    end
end

-- Scan chapters and update cached zones for seekbar
local function refresh_chapter_zones()
    chapter_zones = {}
    local chapters = mp.get_property_native('chapter-list', {})
    local dur = mp.get_property_number('duration', 0) or 0
    if not chapters or #chapters == 0 or dur <= 0 then return end

    for i, ch in ipairs(chapters) do
        local title = ch.title or ''
        local stype = utils_mod and utils_mod.match_chapter_type(title)
        if stype then
            local start_t = ch.time or 0
            local end_t = dur
            if chapters[i + 1] and chapters[i + 1].time then
                end_t = chapters[i + 1].time
            end
            table.insert(chapter_zones, {
                type      = stype,
                start_sec = start_t,
                end_sec   = end_t,
                title     = title,
                index     = i - 1,
            })
        end
    end
end

local function on_chapter_changed(ch_idx)
    -- Whenever chapter changes, dismiss existing button immediately to avoid any stacking
    dismiss_all(false, true)

    if ch_idx == nil or ch_idx < 0 then return end

    local mode = user_opts.smart_skip_mode or 'pill'
    if mode == 'no' then return end

    local series_only = (user_opts.smart_skip_series_only ~= false)
    local is_series = is_series_context()

    local chapters = mp.get_property_native('chapter-list', {})
    local dur = mp.get_property_number('duration', 0) or 0
    local cur_ch = chapters and chapters[ch_idx + 1]
    if not cur_ch then return end

    local title = cur_ch.title or ''
    local stype = utils_mod and utils_mod.match_chapter_type(title)
    if not stype then return end

    -- Guard: series-only check for credits / outro
    if series_only and not is_series and (stype == 'outro') then
        return
    end

    local start_t = cur_ch.time or 0
    local end_t = dur
    if chapters[ch_idx + 2] and chapters[ch_idx + 2].time then
        end_t = chapters[ch_idx + 2].time
    end

    if mode == 'auto' then
        mp.commandv('seek', end_t, 'absolute+exact')
        if huds_mod and huds_mod.show_pill then
            local hud_label = (stype == 'intro') and 'Skipped Opening'
                              or ((stype == 'recap') and 'Skipped Recap' or 'Skipped Ending')
            huds_mod.show_pill('\238\129\150', hud_label)
        end
    elseif mode == 'pill' then
        if stype == 'outro' and (user_opts.next_episode_card ~= false) and is_series then
            trigger_next_episode_card(start_t, end_t)
        else
            trigger_skip_pill(stype, start_t, end_t, title)
        end
    end
end

local function on_time_tick()
    -- 1. Validate active button position and dismiss if scrubbed/seeked away
    if active_btn then
        validate_active_button_position()
        return
    end

    -- 2. Check for late-episode Next Episode Card trigger (if outro was unchaptered)
    if user_opts.next_episode_card == false then return end

    local dur = mp.get_property_number('duration', 0) or 0
    local pos = mp.get_property_number('time-pos', 0) or 0
    if dur <= 60 or pos <= 0 then return end

    if manual_dismiss_until and pos < manual_dismiss_until then
        return
    end

    local rem = dur - pos
    local thresh = tonumber(user_opts.next_episode_threshold) or 25
    if rem <= thresh and rem > 2 and is_series_context() then
        trigger_next_episode_card(dur - thresh, dur)
    end
end

function M.handle_mouse_click(vx, vy)
    if is_any_menu_active() then return false end
    if not active_btn or not active_btn.hitbox then return false end

    if not vx or not vy or vx < 0 or vy < 0 then
        vx, vy = get_mouse_coords()
    end

    local hb = active_btn.hitbox
    if vx >= hb.x1 and vx <= hb.x2 and vy >= hb.y1 and vy <= hb.y2 then
        execute_action()
        return true
    end

    return false
end

function M.get_chapter_zones()
    return chapter_zones
end

function M.init(ctx)
    ctx_ref      = ctx
    user_opts    = ctx.user_opts or {}
    state        = ctx.state or {}
    utils_mod    = ctx.utils
    huds_mod     = ctx.huds
    request_tick = ctx.request_tick or function() end

    mp.observe_property('chapter', 'number', function(_, ch)
        pcall(on_chapter_changed, ch)
    end)

    mp.observe_property('chapter-list', nil, function()
        refresh_chapter_zones()
    end)

    mp.observe_property('time-pos', 'number', function()
        on_time_tick()
    end)

    mp.observe_property('seeking', 'bool', function()
        validate_active_button_position()
    end)

    mp.register_event('start-file', function()
        manual_dismiss_until = nil
        dismiss_all(false, true)
        chapter_zones = {}
    end)

    mp.register_event('file-loaded', function()
        refresh_chapter_zones()
    end)
end

return M
