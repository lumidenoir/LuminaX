-- ============================================================================
-- ModernH Module: HUDs
-- Floating HUD overlays (Play/Pause Center Pulse, Speed, Volume, Dynamic Toasts)
-- Frosted Obsidian Glass Design System (32px capsule height, key/value hierarchy)
-- ============================================================================

local assdraw = require('mp.assdraw')

local M = {}

function M.init(ctx)
    local icons           = ctx.icons or {}
    local get_canvas_size = ctx.get_canvas_size
    local raw_on_interaction = ctx.on_interaction or function() end

    -- ────────────────────────────────────────────────────────────────────────
    -- File-Load HUD Gate: Suppress startup/track-probing notifications
    -- ────────────────────────────────────────────────────────────────────────
    local file_loading = true
    local file_load_timer = nil

    local function cancel_file_load_timer()
        if file_load_timer then
            file_load_timer:kill()
            file_load_timer = nil
        end
    end

    local function mark_file_loaded()
        cancel_file_load_timer()
        file_load_timer = mp.add_timeout(1.2, function()
            file_loading = false
            file_load_timer = nil
        end)
    end

    local function mark_user_activity()
        file_loading = false
        cancel_file_load_timer()
    end

    local function on_interaction()
        mark_user_activity()
        raw_on_interaction()
    end

    local function ass_draw_cir_cw(ass, x, y, r)
        ass:round_rect_cw(x - r, y - r, x + r, y + r, r)
    end

    -- ────────────────────────────────────────────────────────────────────────
    -- Text Metric Width Estimator (Inter / Variable Width Proportional Metrics)
    -- ────────────────────────────────────────────────────────────────────────
    local function estimate_char_width(byte, fs, is_bold)
        local bold_factor = is_bold and 1.05 or 1.0
        if byte >= 0xC0 then
            return fs * 0.95 * bold_factor
        end
        local ch = string.char(byte)
        if ch:match('[WwMm@]') then
            return fs * 0.72 * bold_factor
        elseif ch:match('[A-Z]') then
            return fs * 0.58 * bold_factor
        elseif ch:match('[a-z0-9]') then
            if ch:match('[iljtfr]') then
                return fs * 0.30 * bold_factor
            end
            return fs * 0.48 * bold_factor
        elseif ch:match('[%s]') then
            return fs * 0.28
        elseif ch:match('[,%.!;:|\'"%-_]') then
            return fs * 0.25
        else
            return fs * 0.44 * bold_factor
        end
    end

    local function estimate_text_width(text, fs, is_bold)
        if not text or text == '' then return 0 end
        local clean = text:gsub('{[^}]-}', '')
        local w = 0
        local len = #clean
        local i = 1
        while i <= len do
            local b = clean:byte(i)
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

    -- ────────────────────────────────────────────────────────────────────────
    -- Unified Two-Tier Pill Renderer (Frosted Obsidian Glass, 32px height)
    -- ────────────────────────────────────────────────────────────────────────
    local HUD_PILL_Y    = 42
    local HUD_PILL_H    = 32
    local HUD_PILL_R    = 16
    local HUD_PAD_X     = 16
    local HUD_MIN_W     = 90
    local HUD_SHOW_DUR  = 1.50
    local HUD_FADE_DUR  = 0.30

    local function render_two_tier_frame(overlay, hud_data, fade_t)
        local w, h = get_canvas_size()
        local cx   = math.floor(w / 2)
        local cy   = HUD_PILL_Y

        local key        = hud_data.key or ''
        local val        = hud_data.val or ''
        local val_col    = hud_data.val_color or 'FFFFFF'
        local icon_str   = hud_data.icon or ''
        local is_muted   = (hud_data.is_muted == true)
        local micro_bar  = hud_data.micro_bar -- optional { val = 0..130 }

        -- Alpha calculations
        local bg_a  = math.min(255, math.floor(0x18 + fade_t * (255 - 0x18)))
        local rim_a = math.min(255, math.floor(0xD8 + (bg_a / 255) * (255 - 0xD8)))
        local val_a = math.min(255, math.floor(fade_t * 255))
        -- Dimmed key alpha (~55% visible when fade_t = 0)
        local key_a = 255 - math.floor((255 - 0x70) * (255 - val_a) / 255)

        local bg_h  = string.format('%02X', bg_a)
        local rim_h = string.format('%02X', rim_a)
        local val_h = string.format('%02X', val_a)
        local key_h = string.format('%02X', key_a)

        -- Specular rim tint: Soft red (BGR 6B6BFF) if muted, else specular white
        local rim_col = is_muted and '6B6BFF' or 'FFFFFF'

        -- Content width measurement
        local kw = (key ~= '') and estimate_text_width(key, 12, true) or 0
        local vw = (val ~= '') and estimate_text_width(val, 13, false) or 0
        local gap_w = (key ~= '' and val ~= '') and 10 or 0
        local icon_w = (icon_str ~= '') and 20 or 0
        local bar_w = micro_bar and 44 or 0
        local bar_gap = micro_bar and 10 or 0

        local content_w = icon_w + kw + gap_w + vw + (bar_w > 0 and (bar_gap + bar_w) or 0)
        local pill_w = math.max(HUD_MIN_W, content_w + HUD_PAD_X * 2)

        local ass = assdraw.ass_new()

        -- 1. Frosted Obsidian Glass Pill + Specular Rim
        ass:new_event()
        ass:pos(0, 0)
        ass:an(7)
        ass:append(string.format(
            '{\\bord1.2\\blur0.4\\1c&H121210&\\1a&H%s&\\3c&H%s&\\3a&H%s&}',
            bg_h, rim_col, rim_h))
        ass:draw_start()
        ass:round_rect_cw(cx - pill_w / 2, cy - HUD_PILL_R, cx + pill_w / 2, cy + HUD_PILL_R, HUD_PILL_R)
        ass:draw_stop()

        -- 2. Layout Elements Side-by-Side (Vertically centered at cy)
        local cur_x = cx - content_w / 2

        -- Icon (if present)
        if icon_str ~= '' then
            ass:new_event()
            ass:pos(cur_x, cy)
            ass:an(4) -- middle-left
            ass:append(string.format(
                '{\\fnMaterial Icons Round\\fs16\\1c&H%s&\\1a&H%s&\\bord0\\shad0}',
                is_muted and '6B6BFF' or 'FFFFFF', val_h))
            ass:append(icon_str)
            cur_x = cur_x + icon_w
        end

        -- Dimmed Key (55% opacity, uppercase, tracking spaced)
        if key ~= '' then
            ass:new_event()
            ass:pos(cur_x, cy)
            ass:an(4)
            ass:append(string.format(
                '{\\fnInter\\b700\\fs12\\fsp0.6\\1c&HFFFFFF&\\1a&H%s&\\bord0\\shad0}',
                key_h))
            ass:append(key)
            cur_x = cur_x + kw + gap_w
        end

        -- Crisp Value (100% opacity bold/prominent)
        if val ~= '' then
            ass:new_event()
            ass:pos(cur_x, cy)
            ass:an(4)
            ass:append(string.format(
                '{\\fnInter\\b600\\fs13\\fsp0.2\\1c&H%s&\\1a&H%s&\\bord0\\shad0}',
                val_col, val_h))
            ass:append(val)
            cur_x = cur_x + vw
        end

        -- Micro-Bar Gauge (Volume)
        if micro_bar then
            local bx = cur_x + bar_gap
            local by = cy
            local bw = 44
            local v_level = micro_bar.val or 100
            local fill_pct = math.max(0, math.min(1.0, v_level / 100))
            local fw = math.floor(bw * fill_pct + 0.5)
            local is_boost = (v_level > 100)
            local fill_col = is_boost and '00A5FF' or 'FFFFFF'

            -- Track (Etched Translucent White)
            ass:new_event()
            ass:pos(0, 0)
            ass:an(7)
            ass:append('{\\blur0\\bord0\\1c&HFFFFFF&\\1a&HB0&}')
            ass:draw_start()
            ass:round_rect_cw(bx, by - 1.5, bx + bw, by + 1.5, 1.5)
            ass:draw_stop()

            -- Fill + Thumb Pin
            if fw > 0 then
                ass:new_event()
                ass:pos(0, 0)
                ass:an(7)
                ass:append(string.format('{\\blur0\\bord0\\1c&H%s&\\1a&H%s&}', fill_col, val_h))
                ass:draw_start()
                ass:round_rect_cw(bx, by - 1.5, bx + fw, by + 1.5, 1.5)
                ass_draw_cir_cw(ass, bx + fw, by, 3)
                ass:draw_stop()
            end
        end

        overlay.res_x = w
        overlay.res_y = h
        overlay.data  = ass.text
        overlay:update()
    end

    -- ────────────────────────────────────────────────────────────────────────
    -- 1. Center Play/Pause Overlay Pulse (Netflix / Apple TV style)
    -- ────────────────────────────────────────────────────────────────────────
    local pulse_overlay   = mp.create_osd_overlay('ass-events')
    local pulse_timer     = nil
    local pulse_start_t   = nil
    local PULSE_DURATION  = 0.55
    local pulse_icon      = ''
    local pulse_first_run = true

    local function draw_pulse(t)
        local w, h = get_canvas_size()
        local cx   = math.floor(w / 2)
        local cy   = math.floor(h / 2)
        local R    = 44

        local circ_a = math.min(255, math.floor(0x18 + t * (255 - 0x18)))
        local rim_a  = math.min(255, math.floor(0xD0 + t * (255 - 0xD0)))
        local icon_a = math.min(255, math.floor(t * 255))
        local circ_h = string.format('%02X', circ_a)
        local rim_h  = string.format('%02X', rim_a)
        local icon_h = string.format('%02X', icon_a)

        local ass = assdraw.ass_new()
        ass:new_event()
        ass:pos(0, 0)
        ass:an(7)
        ass:append(string.format('{\\bord1.2\\blur0.4\\1c&H121210&\\1a&H%s&\\3c&HFFFFFF&\\3a&H%s&}', circ_h, rim_h))
        ass:draw_start()
        ass_draw_cir_cw(ass, cx, cy, R)
        ass:draw_stop()

        local ix = cx + (pulse_icon == icons.play and 2 or 0)
        ass:new_event()
        ass:pos(ix, cy)
        ass:an(5)
        ass:append(string.format(
            '{\\fnMaterial Icons Round\\fs40\\1c&HFFFFFF&\\1a&H%s&\\bord0\\shad0}',
            icon_h))
        ass:append(pulse_icon)

        pulse_overlay.res_x = w
        pulse_overlay.res_y = h
        pulse_overlay.data  = ass.text
        pulse_overlay:update()
    end

    local function update_pulse_animation()
        if not pulse_start_t then return end
        local t = (mp.get_time() - pulse_start_t) / PULSE_DURATION
        if t >= 1.0 then
            pulse_overlay:remove()
            pulse_start_t = nil
            if pulse_timer then pulse_timer:kill(); pulse_timer = nil end
            return
        end
        draw_pulse(t)
    end

    local function trigger_play_pause_pulse(paused)
        if file_loading then return end
        pulse_icon  = paused and icons.pause or icons.play
        pulse_start_t = mp.get_time()
        draw_pulse(0)
        if pulse_timer then pulse_timer:kill() end
        pulse_timer = mp.add_periodic_timer(0.033, update_pulse_animation)
    end

    mp.observe_property('pause', 'bool', function(_, paused)
        if pulse_first_run then pulse_first_run = false; return end
        if paused == nil then return end
        trigger_play_pause_pulse(paused)
    end)

    -- ────────────────────────────────────────────────────────────────────────
    -- 2. Playback Speed Indicator Pill
    -- ────────────────────────────────────────────────────────────────────────
    local speed_overlay    = mp.create_osd_overlay('ass-events')
    local speed_hide_timer = nil
    local speed_fade_timer = nil
    local speed_fade_start = 0
    local speed_cur_data   = nil
    local speed_first_run  = true

    local function update_speed_fade()
        local t = (mp.get_time() - speed_fade_start) / HUD_FADE_DUR
        if t >= 1.0 then
            speed_overlay:remove()
            if speed_fade_timer then speed_fade_timer:kill(); speed_fade_timer = nil end
            return
        end
        if speed_cur_data then
            render_two_tier_frame(speed_overlay, speed_cur_data, t)
        end
    end

    local function show_speed_pill(spd)
        if not spd or file_loading then return end
        local formatted_spd = string.format('%.2f×', spd):gsub('0×$', '×')
        speed_cur_data = {
            key  = 'SPEED',
            val  = formatted_spd,
            icon = '\238\167\164', -- speedometer (0xE9E4 in uosc_icons.otf)
        }
        if speed_hide_timer then speed_hide_timer:kill(); speed_hide_timer = nil end
        if speed_fade_timer then speed_fade_timer:kill(); speed_fade_timer = nil end
        render_two_tier_frame(speed_overlay, speed_cur_data, 0)
        speed_hide_timer = mp.add_timeout(HUD_SHOW_DUR, function()
            speed_fade_start = mp.get_time()
            speed_fade_timer = mp.add_periodic_timer(0.033, update_speed_fade)
        end)
    end

    mp.observe_property('speed', 'number', function(_, spd)
        if speed_first_run then speed_first_run = false; return end
        show_speed_pill(spd)
    end)

    -- ────────────────────────────────────────────────────────────────────────
    -- 3. Volume HUD Pill with Embedded Micro-Bar
    -- ────────────────────────────────────────────────────────────────────────
    local vol_overlay    = mp.create_osd_overlay('ass-events')
    local vol_hide_timer = nil
    local vol_fade_timer = nil
    local vol_fade_start = 0
    local vol_cur_data   = nil
    local vol_first_run  = true
    local mute_first_run = true

    local function update_vol_fade()
        local t = (mp.get_time() - vol_fade_start) / HUD_FADE_DUR
        if t >= 1.0 then
            vol_overlay:remove()
            if vol_fade_timer then vol_fade_timer:kill(); vol_fade_timer = nil end
            return
        end
        if vol_cur_data then
            render_two_tier_frame(vol_overlay, vol_cur_data, t)
        end
    end

    local function show_vol_pill()
        if file_loading then return end
        local vol   = mp.get_property_number('volume', 100) or 100
        local muted = mp.get_property_bool('mute', false)
        if muted then
            vol_cur_data = {
                key       = 'AUDIO',
                val       = 'MUTED',
                val_color = '6B6BFF', -- Soft Red
                icon      = '\238\129\143', -- volume_off
                is_muted  = true,
            }
        else
            vol_cur_data = {
                key       = 'VOL',
                val       = string.format('%d%%', math.floor(vol + 0.5)),
                icon      = (vol <= 35 and '\238\129\141' or '\238\129\144'),
                micro_bar = { val = vol },
            }
        end

        if vol_hide_timer then vol_hide_timer:kill(); vol_hide_timer = nil end
        if vol_fade_timer then vol_fade_timer:kill(); vol_fade_timer = nil end
        render_two_tier_frame(vol_overlay, vol_cur_data, 0)
        vol_hide_timer = mp.add_timeout(HUD_SHOW_DUR, function()
            vol_fade_start = mp.get_time()
            vol_fade_timer = mp.add_periodic_timer(0.033, update_vol_fade)
        end)
    end

    mp.observe_property('volume', 'number', function(_, v)
        if vol_first_run then vol_first_run = false; return end
        if v == nil then return end
        on_interaction()
        show_vol_pill()
    end)
    mp.observe_property('mute', 'bool', function(_, m)
        if mute_first_run then mute_first_run = false; return end
        on_interaction()
        show_vol_pill()
    end)

    -- ────────────────────────────────────────────────────────────────────────
    -- 4. Shared Interactive Two-Tier Toast Pill
    -- ────────────────────────────────────────────────────────────────────────
    local toast_overlay    = mp.create_osd_overlay('ass-events')
    local toast_hide_timer = nil
    local toast_fade_timer = nil
    local toast_fade_start = 0
    local toast_cur_data   = nil

    local function update_toast_fade()
        local t = (mp.get_time() - toast_fade_start) / HUD_FADE_DUR
        if t >= 1.0 then
            toast_overlay:remove()
            if toast_fade_timer then toast_fade_timer:kill(); toast_fade_timer = nil end
            return
        end
        if toast_cur_data then
            render_two_tier_frame(toast_overlay, toast_cur_data, t)
        end
    end

    local function show_toast_hud(hud_data)
        if not hud_data or file_loading then return end
        toast_cur_data = hud_data
        if toast_hide_timer then toast_hide_timer:kill(); toast_hide_timer = nil end
        if toast_fade_timer then toast_fade_timer:kill(); toast_fade_timer = nil end
        render_two_tier_frame(toast_overlay, toast_cur_data, 0)
        toast_hide_timer = mp.add_timeout(HUD_SHOW_DUR, function()
            toast_fade_start = mp.get_time()
            toast_fade_timer = mp.add_periodic_timer(0.033, update_toast_fade)
        end)
    end

    -- Backwards-compatible public interface
    function M.show_pill(icon_or_opts, maybe_label)
        mark_user_activity()
        if type(icon_or_opts) == 'table' then
            show_toast_hud(icon_or_opts)
        elseif type(maybe_label) == 'string' then
            local k, v = maybe_label:match('^(.-)%s%s+(.+)$')
            if not k then
                k, v = maybe_label:match('^(.-):%s*(.+)$')
            end
            if k and v then
                show_toast_hud({ key = k, val = v, icon = icon_or_opts })
            else
                show_toast_hud({ key = '', val = maybe_label, icon = icon_or_opts })
            end
        end
    end

    -- ────────────────────────────────────────────────────────────────────────
    -- Observers: Sync Delays, Subtitle State, Track Switching
    -- ────────────────────────────────────────────────────────────────────────

    -- Subtitle Delay
    local sub_delay_first_run = true
    mp.observe_property('sub-delay', 'number', function(_, d)
        if sub_delay_first_run then sub_delay_first_run = false; return end
        if d == nil then return end
        local ms = math.floor(d * 1000 + 0.5)
        local val_str = (ms == 0) and '0 ms (Reset)' or string.format('%+d ms', ms)
        show_toast_hud({
            key  = 'SUB SYNC',
            val  = val_str,
            icon = '\238\129\136', -- subtitles
        })
    end)

    -- Audio Delay
    local audio_delay_first_run = true
    mp.observe_property('audio-delay', 'number', function(_, d)
        if audio_delay_first_run then audio_delay_first_run = false; return end
        if d == nil then return end
        local ms = math.floor(d * 1000 + 0.5)
        local val_str = (ms == 0) and '0 ms (Reset)' or string.format('%+d ms', ms)
        show_toast_hud({
            key  = 'AUDIO SYNC',
            val  = val_str,
            icon = '\238\142\161', -- audiotrack
        })
    end)

    -- Subtitle Visibility
    local sub_vis_first_run = true
    mp.observe_property('sub-visibility', 'bool', function(_, v)
        if sub_vis_first_run then sub_vis_first_run = false; return end
        if v == nil then return end
        show_toast_hud({
            key       = 'SUBTITLES',
            val       = v and 'On' or 'Off',
            val_color = v and '72D572' or 'A0A0A0',
            icon      = v and '\238\163\180' or '\238\163\181', -- visibility / visibility_off
        })
    end)

    -- Subtitle Font Scale
    local sub_scale_first_run = true
    mp.observe_property('sub-scale', 'number', function(_, sc)
        if sub_scale_first_run then sub_scale_first_run = false; return end
        if sc == nil then return end
        local pct = math.floor(sc * 100 + 0.5)
        show_toast_hud({
            key  = 'SUB SIZE',
            val  = string.format('%d%%', pct),
            icon = '\238\137\133', -- format_size
        })
    end)

    -- ────────────────────────────────────────────────────────────────────────
    -- Observers: A-B Loop & Repeat Modes
    -- ────────────────────────────────────────────────────────────────────────
    local loop_a_first = true
    local last_loop_a = nil
    mp.observe_property('ab-loop-a', 'string', function(_, val)
        if loop_a_first then loop_a_first = false; last_loop_a = val; return end
        if val == last_loop_a then return end
        last_loop_a = val
        if val and val ~= 'no' and tonumber(val) then
            local sec = tonumber(val)
            local u = ctx.utils
            local t_str = (u and u.format_time) and u.format_time(sec) or string.format('%.1fs', sec)
            show_toast_hud({
                key  = 'LOOP',
                val  = 'A: ' .. t_str,
                icon = '\238\129\128', -- repeat
            })
        elseif val == 'no' then
            local b = mp.get_property('ab-loop-b', 'no')
            if b == 'no' then
                show_toast_hud({
                    key  = 'LOOP',
                    val  = 'Cleared',
                    icon = '\238\129\128',
                })
            end
        end
    end)

    local loop_b_first = true
    local last_loop_b = nil
    mp.observe_property('ab-loop-b', 'string', function(_, val)
        if loop_b_first then loop_b_first = false; last_loop_b = val; return end
        if val == last_loop_b then return end
        last_loop_b = val
        if val and val ~= 'no' and tonumber(val) then
            local sec_b = tonumber(val)
            local sec_a = tonumber(mp.get_property('ab-loop-a')) or 0
            local u = ctx.utils
            local ta = (u and u.format_time) and u.format_time(sec_a) or string.format('%.1fs', sec_a)
            local tb = (u and u.format_time) and u.format_time(sec_b) or string.format('%.1fs', sec_b)
            show_toast_hud({
                key  = 'LOOP',
                val  = string.format('%s → %s', ta, tb),
                icon = '\238\129\128',
            })
        end
    end)

    local loop_file_first = true
    mp.observe_property('loop-file', 'string', function(_, val)
        if loop_file_first then loop_file_first = false; return end
        if val == nil then return end
        local is_looping = (val == 'inf' or val == 'yes')
        show_toast_hud({
            key  = 'REPEAT',
            val  = is_looping and 'File' or 'Off',
            icon = is_looping and '\238\129\129' or '\238\129\128', -- repeat_one / repeat
        })
    end)

    -- ────────────────────────────────────────────────────────────────────────
    -- Observers: Audio & Subtitle Track Switching
    -- ────────────────────────────────────────────────────────────────────────
    local aid_first = true
    local last_aid = nil
    mp.observe_property('aid', 'string', function(_, aid)
        if aid_first then aid_first = false; last_aid = aid; return end
        if file_loading then last_aid = aid; return end
        if aid == last_aid then return end
        last_aid = aid
        if not aid or aid == 'no' then
            show_toast_hud({
                key  = 'AUDIO',
                val  = 'Muted / None',
                icon = '\238\142\161',
            })
            return
        end
        local tracks = mp.get_property_native('track-list', {})
        for _, tr in ipairs(tracks) do
            if tr.type == 'audio' and tr.id == tonumber(aid) then
                local lang = tr.lang or tr.title or ('Track ' .. aid)
                local codec = tr.codec and (' · ' .. tr.codec:upper()) or ''
                show_toast_hud({
                    key  = 'AUDIO',
                    val  = lang .. codec,
                    icon = '\238\142\161',
                })
                break
            end
        end
    end)

    local sid_first = true
    local last_sid = nil
    mp.observe_property('sid', 'string', function(_, sid)
        if sid_first then sid_first = false; last_sid = sid; return end
        if file_loading then last_sid = sid; return end
        if sid == last_sid then return end
        last_sid = sid
        if not sid or sid == 'no' then
            show_toast_hud({
                key  = 'SUBTITLES',
                val  = 'Off',
                icon = '\238\129\136',
            })
            return
        end
        local tracks = mp.get_property_native('track-list', {})
        for _, tr in ipairs(tracks) do
            if tr.type == 'sub' and tr.id == tonumber(sid) then
                local lang = tr.lang or tr.title or ('Track ' .. sid)
                show_toast_hud({
                    key  = 'SUBTITLES',
                    val  = lang,
                    icon = '\238\129\136',
                })
                break
            end
        end
    end)

    -- ────────────────────────────────────────────────────────────────────────
    -- 5. Seek Scrub Accumulator (Delta + Destination Timestamp)
    -- ────────────────────────────────────────────────────────────────────────
    local seek_accum = 0
    local seek_reset_timer = nil

    local function handle_seek_hud(amt_str)
        mark_user_activity()
        local amt = tonumber(amt_str) or 0
        if amt == 0 then return end

        if (seek_accum > 0 and amt < 0) or (seek_accum < 0 and amt > 0) then
            seek_accum = amt
        else
            seek_accum = seek_accum + amt
        end

        if seek_reset_timer then seek_reset_timer:kill() end
        seek_reset_timer = mp.add_timeout(1.0, function()
            seek_accum = 0
        end)

        local is_fwd = seek_accum > 0
        local abs_s = math.abs(seek_accum)
        local cur_pos = mp.get_property_number('time-pos', 0) or 0
        local dur = mp.get_property_number('duration', 0) or 0
        local dest_pos = math.max(0, math.min(dur > 0 and dur or 86400, cur_pos + seek_accum))
        local u = ctx.utils
        local dest_str = (u and u.format_time) and u.format_time(dest_pos) or string.format('%d:%02d', math.floor(dest_pos / 60), math.floor(dest_pos % 60))

        local key_str = is_fwd and string.format('+%ds', abs_s) or string.format('-%ds', abs_s)
        local val_str = is_fwd and string.format('▶▶  %s', dest_str) or string.format('◀◀  %s', dest_str)
        local icn = is_fwd and (icons.forward or '\238\128\159') or (icons.backward or '\238\128\160')

        show_toast_hud({
            key  = key_str,
            val  = val_str,
            icon = icn,
        })
    end

    mp.register_script_message('seek-hud', handle_seek_hud)

    -- Screenshot Toast
    mp.register_script_message('screenshot-hud', function()
        mark_user_activity()
        show_toast_hud({
            key  = 'SCREENSHOT',
            val  = 'Saved',
            icon = '\238\142\176', -- camera_alt
        })
    end)

    -- ────────────────────────────────────────────────────────────────────────
    -- 6. Missing Trigger Suite: Night Mode, Aspect, Chapter, HW Dec
    -- ────────────────────────────────────────────────────────────────────────

    -- 6.1 Night Mode (Dialogue Clarity)
    local night_first = true
    local last_night = nil
    mp.observe_property('af', 'native', function(_, filters)
        local active = false
        if type(filters) == 'table' then
            for _, f in ipairs(filters) do
                if f.label == 'nightmode' or (f.name and f.name:find('nightmode')) then
                    active = true
                    break
                end
            end
        end
        if night_first then
            night_first = false
            last_night = active
            return
        end
        if file_loading then last_night = active; return end
        if active == last_night then return end
        last_night = active
        show_toast_hud({
            key       = 'NIGHT MODE',
            val       = active and 'On' or 'Off',
            val_color = active and '72D572' or 'A0A0A0',
            icon      = '\238\136\168', -- tune
        })
    end)

    -- 6.2 Aspect Ratio Override
    local aspect_first = true
    local last_aspect = nil
    mp.observe_property('video-aspect-override', 'number', function(_, asp)
        if aspect_first then aspect_first = false; last_aspect = asp; return end
        if file_loading then last_aspect = asp; return end
        if asp == last_aspect then return end
        last_aspect = asp
        if asp == nil then return end
        local asp_str
        if asp <= 0 or asp == -1 then
            asp_str = 'Auto'
        elseif math.abs(asp - 16/9) < 0.03 then
            asp_str = '16:9'
        elseif math.abs(asp - 2.35) < 0.05 or math.abs(asp - 21/9) < 0.05 or math.abs(asp - 2.40) < 0.05 then
            asp_str = '21:9'
        elseif math.abs(asp - 4/3) < 0.03 then
            asp_str = '4:3'
        else
            asp_str = string.format('%.2f:1', asp)
        end
        show_toast_hud({
            key  = 'ASPECT',
            val  = asp_str,
            icon = '\238\151\144', -- fullscreen
        })
    end)

    -- 6.3 Chapter Jump
    local chapter_first = true
    local last_chapter = nil
    mp.observe_property('chapter', 'number', function(_, ch_idx)
        if chapter_first then chapter_first = false; last_chapter = ch_idx; return end
        if file_loading then last_chapter = ch_idx; return end
        if ch_idx == last_chapter then return end
        last_chapter = ch_idx
        if ch_idx == nil or ch_idx < 0 then return end
        local ch_list = mp.get_property_native('chapter-list', {})
        local ch = ch_list[ch_idx + 1]
        local ch_num = string.format('%02d', ch_idx + 1)
        local title = (ch and ch.title and ch.title ~= '') and ch.title or nil
        local u = ctx.utils
        local time_s = (ch and ch.time and u and u.format_time) and u.format_time(ch.time) or nil

        local val_str
        if title and time_s then
            val_str = string.format('%s (%s)', title, time_s)
        elseif title then
            val_str = title
        elseif time_s then
            val_str = time_s
        else
            val_str = 'Jump'
        end

        show_toast_hud({
            key  = 'CHAPTER ' .. ch_num,
            val  = val_str,
            icon = '\238\137\130', -- format_list_bulleted
        })
    end)

    -- 6.4 Hardware Decoding Fallback Warning
    local hwdec_first = true
    local last_hwdec = nil
    mp.observe_property('hwdec-current', 'string', function(_, hw)
        if hwdec_first then hwdec_first = false; last_hwdec = hw; return end
        if file_loading then last_hwdec = hw; return end
        if hw == last_hwdec then return end
        last_hwdec = hw
        if not hw then return end
        local is_sw = (hw == 'no' or hw == '')
        show_toast_hud({
            key       = 'HW DEC',
            val       = is_sw and 'Software (CPU)' or string.format('%s (GPU)', hw:upper()),
            val_color = is_sw and 'FFB060' or '72D572',
            icon      = '\238\162\142', -- info
        })
    end)

    -- ────────────────────────────────────────────────────────────────────────
    -- 7. Smooth Cinematic Fade-In on File Open
    -- ────────────────────────────────────────────────────────────────────────
    local fadein_timer = nil
    local fadein_start = 0
    local fadein_duration = 0.30

    local function cancel_fadein()
        if fadein_timer then
            fadein_timer:kill()
            fadein_timer = nil
        end
        mp.set_property_number('brightness', 0)
    end

    local function step_fadein()
        local now = mp.get_time()
        local progress = (now - fadein_start) / fadein_duration
        if progress >= 1.0 then
            cancel_fadein()
            return
        end
        local ease = 1 - (1 - progress) * (1 - progress)
        local b = -100 * (1 - ease)
        mp.set_property_number('brightness', math.floor(b + 0.5))
    end

    mp.register_event('start-file', function()
        file_loading = true
        cancel_file_load_timer()
        toast_overlay:remove()
        speed_overlay:remove()
        vol_overlay:remove()
        if toast_hide_timer then toast_hide_timer:kill(); toast_hide_timer = nil end
        if toast_fade_timer then toast_fade_timer:kill(); toast_fade_timer = nil end
    end)

    mp.register_event('file-loaded', function()
        mark_file_loaded()
        last_aid = mp.get_property('aid')
        last_sid = mp.get_property('sid')
        last_hwdec = mp.get_property('hwdec-current')
        last_chapter = mp.get_property_number('chapter', -1)
        last_aspect = mp.get_property_number('video-aspect-override')
        if fadein_timer then fadein_timer:kill() end
        mp.set_property_number('brightness', -100)
        fadein_start = mp.get_time()
        fadein_timer = mp.add_periodic_timer(0.025, step_fadein)
    end)

    mp.register_event('end-file', function()
        cancel_fadein()
        file_loading = true
        cancel_file_load_timer()
        toast_overlay:remove()
        speed_overlay:remove()
        vol_overlay:remove()
        if toast_hide_timer then toast_hide_timer:kill(); toast_hide_timer = nil end
        if toast_fade_timer then toast_fade_timer:kill(); toast_fade_timer = nil end
    end)
end

return M
