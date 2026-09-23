-- ============================================================================
-- ModernH Module: HUDs
-- Floating HUD overlays (Play/Pause Center Pulse, Speed Pill, Volume Pill, File Fade-in)
-- ============================================================================

local assdraw = require('mp.assdraw')

local M = {}

function M.init(ctx)
    local icons           = ctx.icons
    local get_canvas_size = ctx.get_canvas_size
    local make_pill_ass   = ctx.make_pill_ass
    local on_interaction  = ctx.on_interaction or function() end

    local function ass_draw_cir_cw(ass, x, y, r)
        ass:round_rect_cw(x - r, y - r, x + r, y + r, r)
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

        local circ_a = math.min(255, math.floor(0x4A + t * (255 - 0x4A)))
        local icon_a = math.min(255, math.floor(t * 255))
        local circ_h = string.format('%02X', circ_a)
        local icon_h = string.format('%02X', icon_a)

        local ass = assdraw.ass_new()
        ass:new_event()
        ass:pos(0, 0)
        ass:an(7)
        ass:append(string.format('{\\blur0\\bord0\\1c&H000000&\\1a&H%s&}', circ_h))
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
    -- 2. Playback Speed Indicator Pill (YouTube style)
    -- ────────────────────────────────────────────────────────────────────────
    local speed_overlay    = mp.create_osd_overlay('ass-events')
    local speed_hide_timer = nil
    local speed_fade_timer = nil
    local speed_fade_start = 0
    local SPEED_FADE_DUR   = 0.30
    local SPEED_SHOW_DUR   = 1.50
    local speed_val_str    = ''
    local speed_first_run  = true
    local SPEED_PILL_Y     = 40

    local function render_speed_pill_frame(fade_t)
        local w, h = get_canvas_size()
        local cx   = math.floor(w / 2)
        local bg_a   = math.min(255, math.floor(0x20 + fade_t * 255))
        local text_a = math.min(255, math.floor(fade_t * 255))
        local bg_h   = string.format('%02X', bg_a)
        local txt_h  = string.format('%02X', text_a)
        local pw, ph = 78, 28
        local ass = make_pill_ass(cx, SPEED_PILL_Y, pw, ph, speed_val_str,
                                  'Inter', 14, bg_h, txt_h)
        speed_overlay.res_x = w
        speed_overlay.res_y = h
        speed_overlay.data  = ass.text
        speed_overlay:update()
    end

    local function update_speed_fade()
        local t = (mp.get_time() - speed_fade_start) / SPEED_FADE_DUR
        if t >= 1.0 then
            speed_overlay:remove()
            if speed_fade_timer then speed_fade_timer:kill(); speed_fade_timer = nil end
            return
        end
        render_speed_pill_frame(t)
    end

    local function show_speed_pill(spd)
        if not spd then return end
        speed_val_str = string.format('%.2f', spd):gsub('%.?0+$', '') .. '×'
        if speed_hide_timer then speed_hide_timer:kill(); speed_hide_timer = nil end
        if speed_fade_timer then speed_fade_timer:kill(); speed_fade_timer = nil end
        render_speed_pill_frame(0)
        speed_hide_timer = mp.add_timeout(SPEED_SHOW_DUR, function()
            speed_fade_start = mp.get_time()
            speed_fade_timer = mp.add_periodic_timer(0.033, update_speed_fade)
        end)
    end

    mp.observe_property('speed', 'number', function(_, spd)
        if speed_first_run then speed_first_run = false; return end
        show_speed_pill(spd)
    end)

    -- ────────────────────────────────────────────────────────────────────────
    -- 3. Volume OSD Pill (iOS / Apple TV style)
    -- ────────────────────────────────────────────────────────────────────────
    local vol_overlay    = mp.create_osd_overlay('ass-events')
    local vol_hide_timer = nil
    local vol_fade_timer = nil
    local vol_fade_start = 0
    local VOL_FADE_DUR   = 0.30
    local VOL_SHOW_DUR   = 1.50
    local VOL_PILL_Y     = SPEED_PILL_Y
    local vol_first_run  = true
    local mute_first_run = true

    local function render_vol_pill_frame(fade_t)
        local vol    = mp.get_property_number('volume', 100)
        local muted  = mp.get_property_bool('mute', false)
        local w, h   = get_canvas_size()
        local cx     = math.floor(w / 2)
        local bg_a   = math.min(255, math.floor(0x20 + fade_t * 255))
        local text_a = math.min(255, math.floor(fade_t * 255))
        local bg_h   = string.format('%02X', bg_a)
        local txt_h  = string.format('%02X', text_a)
        local ph = 28
        local pw = 92
        local r  = ph / 2
        local bx = cx - pw/2
        local by = VOL_PILL_Y

        local icon_str  = muted and icons.volume_mute or icons.volume
        local label_str = muted and 'Muted' or string.format('%d%%', math.floor(vol + 0.5))

        local ass = assdraw.ass_new()
        ass:new_event()
        ass:pos(0, 0)
        ass:an(7)
        ass:append(string.format('{\\blur0\\bord0.5\\1c&H0A0A0A&\\1a&H%s&\\3c&HFFFFFF&\\3a&HC0&}', bg_h))
        ass:draw_start()
        ass:round_rect_cw(bx, by - r, bx + pw, by + r, r)
        ass:draw_stop()

        ass:new_event()
        ass:pos(bx + 14, by)
        ass:an(4)
        ass:append(string.format('{\\fnMaterial Icons Round\\fs16\\1c&HFFFFFF&\\1a&H%s&\\bord0\\shad0}', txt_h))
        ass:append(icon_str)

        ass:new_event()
        ass:pos(bx + pw - 10, by)
        ass:an(6)
        ass:append(string.format('{\\fnInter\\b700\\fs13\\1c&HFFFFFF&\\1a&H%s&\\bord0\\shad0}', txt_h))
        ass:append(label_str)

        vol_overlay.res_x = w
        vol_overlay.res_y = h
        vol_overlay.data  = ass.text
        vol_overlay:update()
    end

    local function update_vol_fade()
        local t = (mp.get_time() - vol_fade_start) / VOL_FADE_DUR
        if t >= 1.0 then
            vol_overlay:remove()
            if vol_fade_timer then vol_fade_timer:kill(); vol_fade_timer = nil end
            return
        end
        render_vol_pill_frame(t)
    end

    local function show_vol_pill()
        if vol_hide_timer then vol_hide_timer:kill(); vol_hide_timer = nil end
        if vol_fade_timer then vol_fade_timer:kill(); vol_fade_timer = nil end
        render_vol_pill_frame(0)
        vol_hide_timer = mp.add_timeout(VOL_SHOW_DUR, function()
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
    -- 4. Smooth Cinematic Fade-In on File Open (Infuse style)
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

    mp.register_event('file-loaded', function()
        if fadein_timer then fadein_timer:kill() end
        mp.set_property_number('brightness', -100)
        fadein_start = mp.get_time()
        fadein_timer = mp.add_periodic_timer(0.025, step_fadein)
    end)

    mp.register_event('end-file', function()
        cancel_fadein()
    end)
end

return M
