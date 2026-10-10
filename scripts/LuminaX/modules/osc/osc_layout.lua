-- ============================================================================
-- LuminaX Sub-module: OSC Layout Engine & Window Controls
-- Handles canvas aspect/scaling math, 3-tier layout metrics, and window controls.
-- ============================================================================

local osc_state    = require('modules.osc.osc_state')
local osc_controls = require('modules.osc.osc_controls')

local M = {}

local user_opts   = osc_state.user_opts
local state       = osc_state.state
local osc_param   = osc_state.osc_param
local osc_styles  = osc_state.osc_styles
local elements    = osc_state.elements
local jumpicons   = osc_state.jumpicons

local window_control_box_width = 138

function M.window_controls_enabled()
    local val = user_opts.windowcontrols
    if val == 'no' then
        return false
    elseif val == 'auto' then
        if state.fullscreen then
            return false
        end
        return not state.border
    else
        return val == 'yes'
    end
end

function M.build_keyboard_controls()
    local bottom_button_line = {
        'cy_audio',
        'cy_sub',
        'tog_video',
        'pl_prev',
        'skipback',
    }
    if user_opts.showjump then
        table.insert(bottom_button_line, 'jumpback')
    end
    table.insert(bottom_button_line, 'playpause')
    if user_opts.showjump then
        table.insert(bottom_button_line, 'jumpfrwd')
    end
    table.insert(bottom_button_line, 'skipfrwd')
    table.insert(bottom_button_line, 'pl_next')
    table.insert(bottom_button_line, 'tog_playlist')
    table.insert(bottom_button_line, 'tog_chapters')
    table.insert(bottom_button_line, 'tog_speed')
    table.insert(bottom_button_line, 'tog_tags')
    table.insert(bottom_button_line, 'tog_update')
    table.insert(bottom_button_line, 'tog_info')
    table.insert(bottom_button_line, 'tog_fs')

    local mapping = {}
    if M.window_controls_enabled() then
        table.insert(mapping, { 'minimize', 'maximize', 'close' })
    end
    table.insert(mapping, { 'seekbar' })
    table.insert(mapping, bottom_button_line)

    return mapping
end

function M.window_controls()
    local wc_geo = {
        x = 0,
        y = 32,
        an = 1,
        w = osc_param.playresx,
        h = 32,
    }

    local controlbox_w = window_control_box_width
    local controlbox_left = wc_geo.w - controlbox_w

    osc_state.add_area('window-controls',
        osc_state.get_hitbox_coords(controlbox_left, wc_geo.y, wc_geo.an,
                                    controlbox_w, wc_geo.h))

    local button_y = wc_geo.y - (wc_geo.h / 2)
    local first_geo  = { x = controlbox_left + 27, y = button_y, an = 5, w = 40, h = wc_geo.h }
    local second_geo = { x = controlbox_left + 69, y = button_y, an = 5, w = 40, h = wc_geo.h }
    local third_geo  = { x = controlbox_left + 115, y = button_y, an = 5, w = 40, h = wc_geo.h }

    local ne, lo

    -- Close button
    ne = osc_state.new_element('close', 'button')
    ne.content = '\238\132\149'
    ne.eventresponder['mbtn_left_up'] = function() mp.commandv('quit') end
    lo = osc_controls.add_layout('close')
    lo.geometry = third_geo
    lo.style = osc_styles.WinCtrl
    lo.alpha[3] = 0

    -- Minimize button
    ne = osc_state.new_element('minimize', 'button')
    ne.content = '\\n\238\132\146'
    ne.eventresponder['mbtn_left_up'] = function() mp.commandv('cycle', 'window-minimized') end
    lo = osc_controls.add_layout('minimize')
    lo.geometry = first_geo
    lo.style = osc_styles.WinCtrl
    lo.alpha[3] = 0

    -- Maximize button
    ne = osc_state.new_element('maximize', 'button')
    if state.maximized or state.fullscreen then
        ne.content = '\238\132\148'
    else
        ne.content = '\238\132\147'
    end
    ne.eventresponder['mbtn_left_up'] = function()
        if state.fullscreen then
            mp.commandv('cycle', 'fullscreen')
        else
            mp.commandv('cycle', 'window-maximized')
        end
    end
    lo = osc_controls.add_layout('maximize')
    lo.geometry = second_geo
    lo.style = osc_styles.WinCtrl
    lo.alpha[3] = 0
end

-- Calculates canvas resolution
function M.calc_canvas_resolution()
    local baseResY = 720
    local display_w, display_h, display_aspect
    if mp and mp.get_osd_size then
        display_w, display_h, display_aspect = mp.get_osd_size()
    end
    display_w = (display_w and display_w > 0) and display_w or 1280
    display_h = (display_h and display_h > 0) and display_h or 720
    display_aspect = (display_aspect and display_aspect > 0) and display_aspect or (display_w / display_h)

    local scale = 1
    if mp and mp.get_property and mp.get_property('video') == 'no' then
        scale = user_opts.scaleforcedwindow or 2.0
    elseif state.fullscreen then
        scale = user_opts.scalefullscreen or 1.0
    else
        scale = user_opts.scalewindowed or 1.0
    end

    if user_opts.vidscale then
        osc_param.unscaled_y = baseResY
    else
        osc_param.unscaled_y = display_h
    end
    osc_param.playresy = osc_param.unscaled_y / scale
    if display_aspect > 0 then
        osc_param.display_aspect = display_aspect
    end
    osc_param.playresx = osc_param.playresy * osc_param.display_aspect
end

-- Default Layout Builder
function M.layouts()
    local UI_OFFSET_Y = 0
    local osc_geo = { w = osc_param.playresx, h = 180 }

    local posX = 0
    local posY = osc_param.playresy

    osc_param.areas = {}

    osc_state.add_area('input', osc_state.get_hitbox_coords(posX, posY + UI_OFFSET_Y, 1, osc_geo.w, 110))
    osc_state.add_area('showhide', 0, 0, osc_param.playresx, osc_param.playresy)

    local osc_w, osc_h = osc_geo.w, osc_geo.h
    local lo

    -- Upward-Fading Gradient Scrim Layers
    local scrim_layers = {
        { h = 55,  alpha = 75,  blur = 22 },
        { h = 100, alpha = 115, blur = 28 },
        { h = 150, alpha = 160, blur = 34 },
        { h = 195, alpha = 200, blur = 40 },
        { h = 240, alpha = 235, blur = 46 },
    }
    for i, sc in ipairs(scrim_layers) do
        local name = 'scrim_' .. i
        osc_state.new_element(name, 'box')
        lo = osc_controls.add_layout(name)
        lo.geometry = { x = posX, y = posY - sc.h, an = 7, w = osc_w, h = sc.h }
        lo.style = string.format('{\\blur%d\\bord0\\1c&H0A0A0D&\\3c&H0A0A0D&}', sc.blur)
        lo.layer = 10
        lo.alpha[1] = sc.alpha
        lo.alpha[3] = 255
    end

    local refX = osc_w / 2
    local refY = posY

    -- Seekbar background and slider
    osc_state.new_element('seekbarbg', 'box')
    lo = osc_controls.add_layout('seekbarbg')
    lo.geometry = { x = refX, y = refY - 96 + UI_OFFSET_Y, an = 5, w = osc_geo.w - 50, h = 19 }
    lo.layer = 13
    lo.style = osc_styles.SeekbarBg
    lo.alpha[1] = 128
    lo.alpha[3] = 128

    lo = osc_controls.add_layout('seekbar')
    lo.geometry = { x = refX, y = refY - 96 + UI_OFFSET_Y, an = 5, w = osc_geo.w - 50, h = 19 }
    lo.style = osc_styles.SeekbarFg
    lo.slider.gap = 6
    lo.slider.tooltip_style = osc_styles.Tooltip
    lo.slider.tooltip_an = 2

    -- Adaptive Sizing & Metrics
    local min_scale = tonumber(user_opts.min_scale) or 0.70
    local max_scale = tonumber(user_opts.max_scale) or 1.05
    local raw_scale = osc_param.playresx / 1280
    local scale = math.max(min_scale, math.min(max_scale, raw_scale))

    local is_compact = (osc_param.playresx < 1050)

    local fs_ctrl1      = math.floor(44 * scale + 0.5)
    local fs_ctrl2      = math.floor(26 * scale + 0.5)
    local fs_ctrl2_flip = math.floor(22 * scale + 0.5)
    local fs_ctrl3      = math.floor(22 * scale + 0.5)

    local style_ctrl1      = string.format('{\\blur0\\bord0\\1c&HFFFFFF&\\3c&H161618&\\fs%d\\fnMaterial Icons Round}', fs_ctrl1)
    local style_ctrl2      = string.format('{\\blur0\\bord0\\1c&HFFFFFF&\\3c&H161618&\\fs%d\\fnMaterial Icons Round}', fs_ctrl2)
    local style_ctrl2_flip = string.format('{\\blur0\\bord0\\1c&HFFFFFF&\\3c&HFFFFFF&\\fs%d\\fnMaterial Icons Round\\fry180}', fs_ctrl2_flip)
    local style_ctrl3      = string.format('{\\blur0\\bord0\\1c&HC7C7CC&\\3c&H161618&\\fs%d\\fnMaterial Icons Round}', fs_ctrl3)

    local ctrl1_w = math.floor(45 * scale + 0.5)
    local ctrl1_h = math.floor(45 * scale + 0.5)
    local ctrl2_w = math.floor(32 * scale + 0.5)
    local ctrl2_h = math.floor(24 * scale + 0.5)
    local ctrl3_w = math.floor(26 * scale + 0.5)
    local ctrl3_h = math.floor(24 * scale + 0.5)

    local left_pad     = math.floor(36 * scale + 0.5)
    local left_spacing = math.floor(46 * scale + 0.5)

    -- Left controls
    lo = osc_controls.add_layout('cy_audio')
    lo.geometry = { x = left_pad, y = refY - 40 + UI_OFFSET_Y, an = 5, w = ctrl3_w, h = ctrl3_h }
    lo.style = style_ctrl3
    elements['cy_audio'].visible = (osc_param.playresx >= 480)

    lo = osc_controls.add_layout('cy_sub')
    lo.geometry = { x = left_pad + left_spacing, y = refY - 40 + UI_OFFSET_Y, an = 5, w = ctrl3_w, h = ctrl3_h }
    lo.style = style_ctrl3
    elements['cy_sub'].visible = (osc_param.playresx >= 540)

    lo = osc_controls.add_layout('tog_video')
    lo.geometry = { x = left_pad + left_spacing * 2, y = refY - 40 + UI_OFFSET_Y, an = 5, w = ctrl3_w, h = ctrl3_h }
    lo.style = style_ctrl3
    elements['tog_video'].visible = (osc_param.playresx >= 580)

    local vol_x = left_pad + left_spacing * 3
    lo = osc_controls.add_layout('vol_ctrl')
    lo.geometry = { x = vol_x, y = refY - 40 + UI_OFFSET_Y, an = 5, w = ctrl3_w, h = ctrl3_h }
    lo.style = style_ctrl3
    elements['vol_ctrl'].visible = (osc_param.playresx >= 650) and user_opts.volumecontrol

    local vbar_x = vol_x + math.floor(18 * scale + 0.5)
    local vbar_w = math.floor((is_compact and 55 or 70) * scale + 0.5)
    local vmode = user_opts.volume_slider_mode or 'hover'
    local show_vbar = (osc_param.playresx >= 780) and user_opts.volumecontrol and (vmode ~= 'never')

    lo = osc_state.new_element('volumebarbg', 'box')
    lo.visible = show_vbar
    lo = osc_controls.add_layout('volumebarbg')
    lo.geometry = { x = vbar_x, y = refY - 40 + UI_OFFSET_Y, an = 4, w = vbar_w, h = 2 }
    lo.layer = 13
    lo.style = osc_styles.VolumebarBg
    elements['volumebarbg'].visible = show_vbar

    lo = osc_controls.add_layout('volumebar')
    lo.geometry = { x = vbar_x, y = refY - 40 + UI_OFFSET_Y, an = 4, w = vbar_w, h = 10 }
    lo.style = osc_styles.VolumebarFg
    lo.slider.gap = 4
    lo.slider.tooltip_style = osc_styles.Tooltip
    lo.slider.tooltip_an = 2
    elements['volumebar'].visible = show_vbar

    -- Right controls
    local right_pad     = osc_geo.w - math.floor(36 * scale + 0.5)
    local right_spacing = math.floor(44 * scale + 0.5)
    local fs_speed      = math.floor(13 * scale + 0.5)
    local style_speed   = string.format('{\\blur0\\bord0\\1c&HC7C7CC&\\3c&H161618&\\fs%d\\fn%s\\b700}', fs_speed, user_opts.font)

    local btn_idx = 0
    lo = osc_controls.add_layout('tog_fs')
    lo.geometry = { x = right_pad - right_spacing * btn_idx, y = refY - 40 + UI_OFFSET_Y, an = 5, w = ctrl3_w, h = ctrl3_h }
    lo.style = style_ctrl3
    elements['tog_fs'].visible = (osc_param.playresx >= 500)
    btn_idx = btn_idx + 1

    lo = osc_controls.add_layout('tog_info')
    lo.geometry = { x = right_pad - right_spacing * btn_idx, y = refY - 40 + UI_OFFSET_Y, an = 5, w = ctrl3_w, h = ctrl3_h }
    lo.style = style_ctrl3
    elements['tog_info'].visible = (osc_param.playresx >= 540)
    btn_idx = btn_idx + 1

    local show_update_btn = (state.update_available ~= nil)
    lo = osc_controls.add_layout('tog_update')
    if show_update_btn then
        lo.geometry = { x = right_pad - right_spacing * btn_idx, y = refY - 40 + UI_OFFSET_Y, an = 5, w = ctrl3_w, h = ctrl3_h }
        lo.style = style_ctrl3
        elements['tog_update'].visible = true
        btn_idx = btn_idx + 1
    else
        lo.geometry = { x = 0, y = 0, an = 5, w = 0, h = 0 }
        lo.style = style_ctrl3
        elements['tog_update'].visible = false
    end

    lo = osc_controls.add_layout('tog_tags')
    lo.geometry = { x = right_pad - right_spacing * btn_idx, y = refY - 40 + UI_OFFSET_Y, an = 5, w = ctrl3_w, h = ctrl3_h }
    lo.style = style_ctrl3
    elements['tog_tags'].visible = (osc_param.playresx >= 660)
    btn_idx = btn_idx + 1

    lo = osc_controls.add_layout('tog_speed')
    lo.geometry = { x = right_pad - right_spacing * btn_idx, y = refY - 40 + UI_OFFSET_Y, an = 5, w = math.floor(34 * scale + 0.5), h = ctrl3_h }
    lo.style = style_speed
    elements['tog_speed'].visible = (osc_param.playresx >= 720)
    btn_idx = btn_idx + 1

    lo = osc_controls.add_layout('tog_chapters')
    lo.geometry = { x = right_pad - right_spacing * btn_idx, y = refY - 40 + UI_OFFSET_Y, an = 5, w = ctrl3_w, h = ctrl3_h }
    lo.style = style_ctrl3
    elements['tog_chapters'].visible = (osc_param.playresx >= 580)
    btn_idx = btn_idx + 1

    lo = osc_controls.add_layout('tog_playlist')
    lo.geometry = { x = right_pad - right_spacing * btn_idx, y = refY - 40 + UI_OFFSET_Y, an = 5, w = ctrl3_w, h = ctrl3_h }
    lo.style = style_ctrl3
    elements['tog_playlist'].visible = (osc_param.playresx >= 620)

    -- Center playback controls
    local have_pl = (mp and mp.get_property_number) and (mp.get_property_number('playlist-count', 0) > 1) or false
    local center_spacing = math.floor(62 * scale + 0.5)

    local show_jump = (user_opts.showjump == true)
    local cur_step = 0
    local jump_step = 0
    if show_jump then
        cur_step = cur_step + 1
        jump_step = cur_step
    end
    local pl_step = 0
    if have_pl then
        cur_step = cur_step + 1
        pl_step = cur_step
    end

    -- Play/Pause
    lo = osc_controls.add_layout('playpause')
    lo.geometry = { x = refX, y = refY - 40 + UI_OFFSET_Y, an = 5, w = ctrl1_w, h = ctrl1_h }
    lo.style = style_ctrl1
    elements['playpause'].visible = true

    -- Jump buttons
    if show_jump then
        lo = osc_controls.add_layout('jumpback')
        lo.geometry = { x = refX - (center_spacing * jump_step), y = refY - 40 + UI_OFFSET_Y, an = 5, w = ctrl2_w, h = ctrl2_h }
        lo.style = style_ctrl2
        elements['jumpback'].visible = true

        lo = osc_controls.add_layout('jumpfrwd')
        lo.geometry = { x = refX + (center_spacing * jump_step), y = refY - 40 + UI_OFFSET_Y, an = 5, w = ctrl2_w, h = ctrl2_h }
        lo.style = (user_opts.jumpiconnumber and jumpicons[user_opts.jumpamount] ~= nil) and style_ctrl2 or style_ctrl2_flip
        elements['jumpfrwd'].visible = true
    else
        if elements['jumpback'] then elements['jumpback'].visible = false; elements['jumpback'].layout = nil end
        if elements['jumpfrwd'] then elements['jumpfrwd'].visible = false; elements['jumpfrwd'].layout = nil end
    end

    -- Playlist Buttons
    if have_pl then
        lo = osc_controls.add_layout('pl_prev')
        lo.geometry = { x = refX - (center_spacing * pl_step), y = refY - 40 + UI_OFFSET_Y, an = 5, w = ctrl2_w, h = ctrl2_h }
        lo.style = style_ctrl2
        elements['pl_prev'].visible = true

        lo = osc_controls.add_layout('pl_next')
        lo.geometry = { x = refX + (center_spacing * pl_step), y = refY - 40 + UI_OFFSET_Y, an = 5, w = ctrl2_w, h = ctrl2_h }
        lo.style = style_ctrl2
        elements['pl_next'].visible = true
    else
        if elements['pl_prev'] then elements['pl_prev'].visible = false; elements['pl_prev'].layout = nil end
        if elements['pl_next'] then elements['pl_next'].visible = false; elements['pl_next'].layout = nil end
    end

    -- Time displays
    local tc_pad = math.max(20, math.floor(25 * scale + 0.5))
    lo = osc_controls.add_layout('tc_left')
    lo.geometry = { x = tc_pad, y = refY - 84 + UI_OFFSET_Y, an = 7, w = 64, h = 20 }
    lo.style = osc_styles.Time

    lo = osc_controls.add_layout('tc_right')
    lo.geometry = { x = osc_geo.w - tc_pad, y = refY - 84 + UI_OFFSET_Y, an = 9, w = 64, h = 20 }
    lo.style = osc_styles.Time

    -- Badges row
    osc_state.new_element('media_badges', 'button')
    lo = osc_controls.add_layout('media_badges')
    lo.geometry = { x = 25, y = refY - 180 + UI_OFFSET_Y, an = 1, w = osc_geo.w - 50, h = 18 }
    lo.style = ''
    lo.layer = 50
    lo.visible = (osc_param.playresx >= 540)

    -- Title row
    local geo = { x = 25, y = refY - 136 + UI_OFFSET_Y, an = 1, w = osc_geo.w - 50, h = 36 }
    lo = osc_controls.add_layout('title')
    lo.geometry = geo
    if osc_param.playresx < 700 then
        lo.style = string.format('{\\blur0\\bord0.5\\1c&HFFFFFF&\\3c&H101014&\\fs15\\b600\\fsp0.1\\q2\\fn%s}', user_opts.font)
    else
        lo.style = osc_styles.Title
    end
    lo.alpha[3] = 0
    lo.button.maxchars = math.max(22, math.floor((osc_geo.w - 60) / 9.5))
end

return M
