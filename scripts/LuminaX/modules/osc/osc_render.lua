-- ============================================================================
-- LuminaX Sub-module: OSC Render Engine
-- Handles ASS string compilation, element rasterization, seekbar visuals, and OSD composition.
-- ============================================================================

local assdraw     = require('mp.assdraw')
local osc_state   = require('modules.osc.osc_state')
local osc_seekbar = require('modules.osc.osc_seekbar')

local M = {}

function M.set_osd(res_x, res_y, text)
    local state = osc_state.state
    if not state.osd then return end
    if state.osd.res_x == res_x and
       state.osd.res_y == res_y and
       state.osd.data == text then
        return
    end
    state.osd.res_x = res_x
    state.osd.res_y = res_y
    state.osd.data = text
    state.osd.z = 1000
    state.osd:update()
end

function M.render_media_badges(elem_ass, elem_geo, alpha, ctx_ref)
    local u = ctx_ref and ctx_ref.utils
    if not u or not u.collect_media_badges or not u.draw_badges_ltr then return end
    local state = osc_state.state
    local badges = u.collect_media_badges(state)
    if #badges == 0 then return end
    local badge_h = 16
    local cy = elem_geo.y + badge_h / 2
    u.draw_badges_ltr(elem_ass, badges, elem_geo.x, cy, badge_h, alpha, state.animation)
end

function M.prepare_elements()
    local elements = osc_state.elements
    local user_opts = osc_state.user_opts

    local elements2 = {}
    for _, element in pairs(elements) do
        if element.layout ~= nil and element.visible then
            table.insert(elements2, element)
        end
    end

    table.sort(elements2, function(a, b)
        return a.layout.layer < b.layout.layer
    end)

    for k in pairs(elements) do
        elements[k] = nil
    end
    for i = #elements, 1, -1 do
        elements[i] = nil
    end

    for i, element in ipairs(elements2) do
        elements[i] = element
        if element.name then
            elements[element.name] = element
        end

        local elem_geo = element.layout.geometry
        local bX1, bY1, bX2, bY2 = osc_state.get_hitbox_coords_geo(elem_geo)
        element.hitbox = { x1 = bX1, y1 = bY1, x2 = bX2, y2 = bY2 }

        local style_ass = assdraw.ass_new()
        style_ass:append('{}')
        style_ass:new_event()
        style_ass:pos(elem_geo.x, elem_geo.y)
        style_ass:an(elem_geo.an)
        style_ass:append(element.layout.style or '')

        element.style_ass = style_ass

        local static_ass = assdraw.ass_new()

        if element.type == 'box' then
            static_ass:draw_start()
            osc_state.ass_draw_rr_h_cw(static_ass, 0, 0, elem_geo.w, elem_geo.h,
                             element.layout.box.radius, element.layout.box.hexagon)
            static_ass:draw_stop()
        elseif element.type == 'slider' then
            element.slider.min.ele_pos = user_opts.seekbarhandlesize * elem_geo.h / 2
            element.slider.max.ele_pos = elem_geo.w - element.slider.min.ele_pos
            element.slider.min.glob_pos = element.hitbox.x1 + element.slider.min.ele_pos
            element.slider.max.glob_pos = element.hitbox.x1 + element.slider.max.ele_pos

            static_ass:draw_start()
            static_ass:rect_cw(0, 0, elem_geo.w, elem_geo.h)
            static_ass:rect_ccw(0, 0, elem_geo.w, elem_geo.h)
            if element.slider.markerF ~= nil then
                local markers = element.slider.markerF()
                for _, marker in pairs(markers) do
                    if marker >= element.slider.min.value and marker <= element.slider.max.value then
                        local s = osc_seekbar.get_slider_ele_pos_for(element, marker)
                        osc_state.ass_draw_cir_cw(static_ass, s, elem_geo.h / 2, 2.5)
                    end
                end
            end
        end

        element.static_ass = static_ass

        if not element.enabled then
            element.layout.alpha[1] = 136
            if element.name ~= 'pl_prev' and element.name ~= 'pl_next' then
                element.eventresponder = nil
            end
        end
        if element.off then
            element.layout.alpha[1] = 136
        end
    end
end

function M.render_elements(master_ass, ctx_ref)
    local state     = osc_state.state
    local elements  = osc_state.elements
    local user_opts = osc_state.user_opts
    local osc_param = osc_state.osc_param
    local osc_styles= osc_state.osc_styles
    local thumbfast = osc_state.thumbfast

    state.forced_title = nil
    if thumbfast.disabled then
        local se, ae = state.slider_element, elements[state.active_element]
        if user_opts.chapter_fmt ~= 'no' and se and (ae == se or (not ae and osc_state.mouse_hit(se))) then
            local dur = mp.get_property_number('duration', 0)
            if dur and dur > 0 then
                local possec = osc_seekbar.get_slider_value(se) * dur / 100
                local ch = osc_seekbar.get_chapter(possec, state.chapter_list)
                if ch and ch.title and ch.title ~= '' then
                    local clean_title = ch.title:gsub('^[Cc]hapter%s*:%s*', ''):gsub('^[Cc]hapter%s+(%d+%s*:%s*)', '')
                    local fmt = user_opts.chapter_fmt or '%s'
                    if fmt == 'Chapter: %s' or fmt == 'Chapter %s' then fmt = '%s' end
                    pcall(function()
                        state.forced_title = string.format(fmt, clean_title)
                    end)
                end
            end
        end
    end

    for n = 1, #elements do
        local element = elements[n]
        local is_vbar = (element.name == 'volumebar' or element.name == 'volumebarbg')
        local vmode = user_opts.volume_slider_mode or 'hover'
        local skip_elem = false
        if is_vbar then
            if vmode == 'never' or not user_opts.volumecontrol then
                skip_elem = true
            elseif vmode == 'hover' and (state.vol_anim or 0) <= 0.005 then
                skip_elem = true
            end
        end

        if not skip_elem then
            local style_ass = assdraw.ass_new()
            style_ass:merge(element.style_ass)
            if is_vbar and vmode == 'hover' then
                local extra_a = math.floor(255 * (1.0 - (state.vol_anim or 1.0)))
                osc_state.ass_append_alpha(style_ass, element.layout.alpha, extra_a)
            else
                osc_state.ass_append_alpha(style_ass, element.layout.alpha, 0)
            end

            if element.eventresponder and (state.active_element == n) then
                if element.eventresponder.render ~= nil then
                    element.eventresponder.render(element)
                end
                if osc_state.mouse_hit(element) then
                    if element.styledown then
                        style_ass:append(osc_styles.elementDown)
                    end
                    if element.softrepeat and (state.mouse_down_counter >= 15 and state.mouse_down_counter % 5 == 0) then
                        local src = state.active_event_source or 'mbtn_left'
                        if element.eventresponder[src .. '_down'] then
                            element.eventresponder[src .. '_down'](element)
                        end
                    end
                    state.mouse_down_counter = state.mouse_down_counter + 1
                end
            end

            if user_opts.keyboardnavigation and state.highlight_element == element.name then
                style_ass:append(osc_styles.elementHighlight)
            end

            local elem_geo = element.layout.geometry
            local elem_ass = assdraw.ass_new()
            if element.name ~= 'seekbar' and element.name ~= 'seekbarbg' then
                elem_ass:merge(style_ass)
            end

            if element.name == 'seekbarbg' then
                -- Handled atomically in seekbar unified pipeline
            elseif element.name == 'volumebarbg' then
                local anim_w = (vmode == 'hover') and math.floor(elem_geo.w * (state.vol_anim or 1.0) + 0.5) or elem_geo.w
                elem_ass:draw_start()
                elem_ass:round_rect_cw(0, 0, anim_w, elem_geo.h, elem_geo.h / 2)
                elem_ass:draw_stop()
            elseif element.type ~= 'button' and element.name ~= 'seekbar' and element.name ~= 'seekbarbg' then
                elem_ass:merge(element.static_ass)
            end

            if element.type == 'slider' then
                local slider_lo = element.layout.slider
                local s_min = element.slider.min.value
                local s_max = element.slider.max.value
                local pos = element.slider.posF and element.slider.posF()

                if element.name == 'seekbar' then
                    local x0 = element.hitbox.x1
                    local w = element.hitbox.x2 - element.hitbox.x1
                    local cy = element.layout.geometry.y
                    local dur = mp.get_property_number('duration', 0)
                    local cur_pos = mp.get_property_number('time-pos', 0) or 0
                    local anim = state.seekbar_anim or 0.0

                    local base_h = 3.5
                    local hover_h = 7.0
                    local bar_h = base_h + ((hover_h - base_h) * anim)
                    local y1 = cy - (bar_h / 2)
                    local y2 = cy + (bar_h / 2)
                    local r = bar_h / 2

                    local function to_x(t)
                        local num_t = tonumber(t)
                        if not dur or dur <= 0 or not num_t then return x0 end
                        local progress = math.max(0.0, math.min(1.0, num_t / dur))
                        return x0 + (progress * w)
                    end

                    local zone_boundaries = {}
                    local zones = {}
                    if user_opts.chapter_zone_tinting ~= false and ctx_ref and ctx_ref.smart_skip and ctx_ref.smart_skip.get_chapter_zones then
                        local raw_zones = ctx_ref.smart_skip.get_chapter_zones()
                        if raw_zones and #raw_zones > 0 and dur and dur > 0 then
                            for _, z in ipairs(raw_zones) do
                                local zx1 = math.max(x0, to_x(z.start_sec))
                                local zx2 = math.min(x0 + w, to_x(z.end_sec))
                                if zx2 > zx1 + 1.0 then
                                    local z_color = (z.type == 'intro' or z.type == 'recap') and 'FFD060' or '30A0FF'
                                    table.insert(zones, { x1 = zx1, x2 = zx2, color = z_color, type = z.type })
                                    table.insert(zone_boundaries, { x = zx1, color = z_color })
                                    table.insert(zone_boundaries, { x = zx2, color = z_color })
                                end
                            end
                        end
                    end

                    table.sort(zone_boundaries, function(a, b) return a.x < b.x end)
                    local dedup_boundaries = {}
                    for _, zb in ipairs(zone_boundaries) do
                        if #dedup_boundaries == 0 or math.abs(zb.x - dedup_boundaries[#dedup_boundaries].x) > 2.0 then
                            table.insert(dedup_boundaries, zb)
                        end
                    end
                    zone_boundaries = dedup_boundaries

                    local dr = 2.8 + (1.4 * anim)
                    local gap_r = dr + 2.0

                    local raw_chapters = state.chapter_list or mp.get_property_native('chapter-list', {})
                    local valid_chapters = {}
                    if type(raw_chapters) == 'table' and dur and dur > 0 then
                        for _, ch in ipairs(raw_chapters) do
                            if type(ch) == 'table' then
                                local ct = tonumber(ch.time)
                                if ct and ct > 0.5 and ct < dur - 0.5 then
                                    table.insert(valid_chapters, { time = ct, title = ch.title })
                                end
                            end
                        end
                    end
                    local num_chapters = #valid_chapters

                    local raw_voids = {}
                    for _, zb in ipairs(zone_boundaries) do
                        table.insert(raw_voids, { x1 = math.max(x0, zb.x - gap_r), x2 = math.min(x0 + w, zb.x + gap_r) })
                    end

                    if num_chapters < 12 then
                        local ch_gap = 1.2
                        for _, ch in ipairs(valid_chapters) do
                            local cx = to_x(ch.time)
                            local near_diamond = false
                            for _, zb in ipairs(zone_boundaries) do
                                if math.abs(cx - zb.x) <= gap_r + 2.0 then
                                    near_diamond = true
                                    break
                                end
                            end
                            if not near_diamond then
                                table.insert(raw_voids, { x1 = math.max(x0, cx - ch_gap), x2 = math.min(x0 + w, cx + ch_gap) })
                            end
                        end
                    end

                    table.sort(raw_voids, function(a, b) return a.x1 < b.x1 end)
                    local voids = {}
                    for _, v in ipairs(raw_voids) do
                        if #voids > 0 and v.x1 <= voids[#voids].x2 + 0.5 then
                            voids[#voids].x2 = math.max(voids[#voids].x2, v.x2)
                        else
                            table.insert(voids, { x1 = v.x1, x2 = v.x2 })
                        end
                    end

                    local segments = {}
                    local cur_seg_x = x0
                    for _, v in ipairs(voids) do
                        if v.x1 > cur_seg_x + 1.0 then
                            local mid = (cur_seg_x + v.x1) / 2
                            local z_color = nil
                            for _, z in ipairs(zones) do
                                if mid >= z.x1 and mid <= z.x2 then
                                    z_color = z.color
                                    break
                                end
                            end
                            table.insert(segments, { x1 = cur_seg_x, x2 = v.x1, is_zone = (z_color ~= nil), color = z_color })
                        end
                        cur_seg_x = math.max(cur_seg_x, v.x2)
                    end
                    if cur_seg_x < x0 + w - 1.0 then
                        local mid = (cur_seg_x + (x0 + w)) / 2
                        local z_color = nil
                        for _, z in ipairs(zones) do
                            if mid >= z.x1 and mid <= z.x2 then
                                z_color = z.color
                                break
                            end
                        end
                        table.insert(segments, { x1 = cur_seg_x, x2 = x0 + w, is_zone = (z_color ~= nil), color = z_color })
                    end
                    if #segments == 0 then
                        table.insert(segments, { x1 = x0, x2 = x0 + w, is_zone = false })
                    end

                    -- 1. Base Groove
                    elem_ass:new_event()
                    elem_ass:pos(0, 0)
                    elem_ass:an(7)
                    elem_ass:append('{\\bord0\\shad0\\1c&H202022&\\1a&H40&}')
                    elem_ass:draw_start()
                    for _, seg in ipairs(segments) do
                        elem_ass:round_rect_cw(seg.x1, y1, seg.x2, y2, r)
                    end
                    elem_ass:draw_stop()

                    -- 2. Buffer Fill
                    local cache_end = mp.get_property_number('demuxer-cache-time')
                    if cache_end and dur and dur > 0 and cache_end > 0 then
                        local cache_x = to_x(cache_end)
                        if cache_x > x0 then
                            elem_ass:new_event()
                            elem_ass:pos(0, 0)
                            elem_ass:an(7)
                            elem_ass:append('{\\bord0\\shad0\\1c&HFFFFFF&\\1a&HD0&}')
                            elem_ass:draw_start()
                            for _, seg in ipairs(segments) do
                                if cache_x > seg.x1 then
                                    local bx2 = math.min(seg.x2, cache_x)
                                    if bx2 > seg.x1 + 0.5 then
                                        elem_ass:round_rect_cw(seg.x1, y1, bx2, y2, r)
                                    end
                                end
                            end
                            elem_ass:draw_stop()
                        end
                    end

                    -- 3. Zone Ribbon Fill
                    for _, seg in ipairs(segments) do
                        if seg.is_zone and seg.color then
                            elem_ass:new_event()
                            elem_ass:pos(0, 0)
                            elem_ass:an(7)
                            elem_ass:append(string.format('{\\bord0\\shad0\\1c&H%s&\\1a&H90&}', seg.color))
                            elem_ass:draw_start()
                            elem_ass:round_rect_cw(seg.x1, y1, seg.x2, y2, r)
                            elem_ass:draw_stop()
                        end
                    end

                    -- 4. A-B Loop Fill
                    local loop_a = mp.get_property_number('ab-loop-a')
                    local loop_b = mp.get_property_number('ab-loop-b')
                    local has_loop = loop_a and dur and dur > 0 and loop_a >= 0
                    if has_loop then
                        local ax1 = to_x(loop_a)
                        local ax2 = (loop_b and loop_b > 0) and to_x(loop_b) or to_x(cur_pos)
                        if ax2 > ax1 + 0.5 then
                            elem_ass:new_event()
                            elem_ass:pos(0, 0)
                            elem_ass:an(7)
                            elem_ass:append('{\\bord0\\shad0\\1c&HFF8844&\\1a&H80&}')
                            elem_ass:draw_start()
                            for _, seg in ipairs(segments) do
                                if ax2 > seg.x1 and ax1 < seg.x2 then
                                    local lx1 = math.max(seg.x1, ax1)
                                    local lx2 = math.min(seg.x2, ax2)
                                    if lx2 > lx1 + 0.5 then
                                        elem_ass:round_rect_cw(lx1, y1, lx2, y2, r)
                                    end
                                end
                            end
                            elem_ass:draw_stop()
                        end
                    end

                    -- 5. Playback Fill
                    local cur_x = to_x(cur_pos)
                    if cur_x > x0 then
                        local play_end = cur_x
                        if has_loop and cur_pos > loop_a then
                            play_end = math.min(cur_x, to_x(loop_a))
                        end
                        if play_end > x0 then
                            elem_ass:new_event()
                            elem_ass:pos(0, 0)
                            elem_ass:an(7)
                            elem_ass:append('{\\bord0\\shad0\\1c&HFFFFFF&\\1a&H00&}')
                            elem_ass:draw_start()
                            for _, seg in ipairs(segments) do
                                if play_end > seg.x1 then
                                    local px2 = math.min(seg.x2, play_end)
                                    if px2 > seg.x1 + 0.5 then
                                        elem_ass:round_rect_cw(seg.x1, y1, px2, y2, r)
                                    end
                                end
                            end
                            elem_ass:draw_stop()
                        end
                    end

                    -- 6. Hairline Notches (>= 12 chapters)
                    if num_chapters >= 12 then
                        for _, ch in ipairs(valid_chapters) do
                            local cx = to_x(ch.time)
                            local in_gap = false
                            for _, zb in ipairs(zone_boundaries) do
                                if math.abs(cx - zb.x) <= gap_r + 1.0 then
                                    in_gap = true
                                    break
                                end
                            end
                            if not in_gap then
                                elem_ass:new_event()
                                elem_ass:pos(0, 0)
                                elem_ass:an(7)
                                elem_ass:append('{\\bord0\\shad0\\1c&HFFFFFF&\\1a&HB8&}')
                                elem_ass:draw_start()
                                elem_ass:rect_cw(cx - 0.5, y1, cx + 0.5, y2)
                                elem_ass:draw_stop()
                            end
                        end
                    end

                    -- 7. Floating Diamond Pins
                    if #zone_boundaries > 0 then
                        for _, zb in ipairs(zone_boundaries) do
                            elem_ass:new_event()
                            elem_ass:pos(0, 0)
                            elem_ass:an(7)
                            elem_ass:append(string.format('{\\blur0\\bord0.8\\3c&H0A0A0E&\\3a&H40&\\1c&H%s&\\1a&H00&}', zb.color))
                            elem_ass:draw_start()
                            elem_ass:move_to(zb.x, cy - dr)
                            elem_ass:line_to(zb.x + dr, cy)
                            elem_ass:line_to(zb.x, cy + dr)
                            elem_ass:line_to(zb.x - dr, cy)
                            elem_ass:draw_stop()
                        end
                    end

                    -- 8. Knob
                    if cur_x and (anim > 0.05 or user_opts.seekbarhandlesize > 0) then
                        local knob_r = (user_opts.seekbarhandlesize * elem_geo.h / 2) * (0.35 + 0.65 * anim)
                        if knob_r < bar_h * 0.95 then knob_r = bar_h * 0.95 end
                        elem_ass:new_event()
                        elem_ass:pos(0, 0)
                        elem_ass:an(7)
                        elem_ass:append('{\\bord1.2\\3c&H000000&\\3a&H80&\\1c&HFFFFFF&\\1a&H00&}')
                        elem_ass:draw_start()
                        osc_state.ass_draw_cir_cw(elem_ass, cur_x, cy, knob_r)
                        elem_ass:draw_stop()
                    end
                else
                    local rh = user_opts.seekbarhandlesize * elem_geo.h / 2
                    local xp
                    if pos then
                        xp = osc_seekbar.get_slider_ele_pos_for(element, pos)
                        if element.name == 'volumebar' and vmode == 'hover' then
                            xp = math.floor(xp * (state.vol_anim or 1.0) + 0.5)
                        end
                        osc_state.ass_draw_cir_cw(elem_ass, xp, elem_geo.h / 2, rh)
                        elem_ass:rect_cw(0, slider_lo.gap, xp, elem_geo.h - slider_lo.gap)
                    end
                    elem_ass:draw_stop()
                end

                -- Slider tooltips
                if element.slider.tooltipF ~= nil and osc_state.mouse_hit(element) then
                    local sliderpos = osc_seekbar.get_slider_value(element)
                    local tooltiplabel = element.slider.tooltipF(sliderpos)
                    local an = slider_lo.tooltip_an
                    local ty = (an == 2) and element.hitbox.y1 or (element.hitbox.y1 + elem_geo.h / 2)
                    local tx = osc_state.get_virt_mouse_pos()
                    if slider_lo.adjust_tooltip then
                        if an == 2 then
                            if sliderpos < (s_min + 3) then an = an - 1
                            elseif sliderpos > (s_max - 3) then an = an + 1 end
                        elseif sliderpos > (s_max - s_min) / 2 then
                            an = an + 1
                            tx = tx - 5
                        else
                            an = an - 1
                            tx = tx + 10
                        end
                    end

                    elem_ass:new_event()
                    elem_ass:pos(tx, ty)
                    elem_ass:an(an)
                    elem_ass:append(slider_lo.tooltip_style)
                    osc_state.ass_append_alpha(elem_ass, slider_lo.alpha, 0)
                    elem_ass:append(tooltiplabel)

                    -- Thumbfast thumbnail preview
                    if element.name == 'seekbar' and not thumbfast.disabled then
                        local osd_w = mp.get_property_number('osd-width')
                        if osd_w then
                            local r_w, r_h = osc_state.get_virt_scale_factor()
                            local tooltip_font_size = 18
                            local thumbPad = 1
                            local thumbMarginX = 18 / r_w
                            local thumbMarginY = tooltip_font_size + thumbPad + 2 / r_h
                            local thumbX = math.min(osd_w - thumbfast.width - thumbMarginX, math.max(thumbMarginX, tx / r_w - thumbfast.width / 2))
                            local thumbY = (ty - thumbMarginY) / r_h - thumbfast.height

                            thumbX = math.floor(thumbX + 0.5)
                            thumbY = math.floor(thumbY + 0.5)

                            elem_ass:new_event()
                            elem_ass:pos(thumbX * r_w, ty - thumbMarginY - thumbfast.height * r_h)
                            elem_ass:an(7)
                            elem_ass:append(osc_styles.ThumbnailBorder)
                            elem_ass:draw_start()
                            elem_ass:rect_cw(-thumbPad * r_w, -thumbPad * r_h, (thumbfast.width + thumbPad) * r_w, (thumbfast.height + thumbPad) * r_h)
                            elem_ass:draw_stop()

                            mp.commandv('script-message-to', 'thumbfast', 'thumb',
                                mp.get_property_number('duration', 0) * (sliderpos / 100),
                                thumbX,
                                thumbY
                            )
                        end
                    end
                else
                    if element.name == 'seekbar' and thumbfast.available then
                        mp.commandv('script-message-to', 'thumbfast', 'clear')
                    end
                end

            elseif element.type == 'button' then
                if element.name == 'media_badges' then
                    M.render_media_badges(elem_ass, element.layout.geometry, element.layout.alpha, ctx_ref)
                else
                    local buttontext
                    if type(element.content) == 'function' then
                        buttontext = element.content()
                    elseif element.content ~= nil then
                        buttontext = element.content
                    end
                    buttontext = buttontext or ''
                    buttontext = buttontext:gsub(':%((.?.?.?)%) unknown ', ':%(%1%)')

                    local maxchars = element.layout.button.maxchars
                    if maxchars ~= nil and not (buttontext:sub(1, 1) == '{') then
                        local charcount = (buttontext:len() + select(2, buttontext:gsub('[^\128-\193]', '')) * 2) / 3
                        if charcount > maxchars then
                            local limit = math.max(0, maxchars - 3)
                            if charcount > limit then
                                while charcount > limit do
                                    buttontext = buttontext:gsub('.[\128-\191]*$', '')
                                    charcount = (buttontext:len() + select(2, buttontext:gsub('[^\128-\193]', '')) * 2) / 3
                                end
                                buttontext = buttontext .. '...'
                            end
                        end
                    end
                    elem_ass:append(buttontext)
                end

                if element.tooltipF ~= nil and element.enabled and osc_state.mouse_hit(element) then
                    local an = 1
                    local ty = element.hitbox.y1
                    local tx = osc_state.get_virt_mouse_pos()
                    if ty < osc_param.playresy / 2 then
                        ty = element.hitbox.y2
                        an = 7
                    end
                    local tooltiplabel
                    if type(element.tooltipF) == 'function' then
                        tooltiplabel = element.tooltipF()
                    else
                        tooltiplabel = element.tooltipF
                    end
                    elem_ass:new_event()
                    elem_ass:pos(tx, ty)
                    elem_ass:an(an)
                    elem_ass:append(element.tooltip_style or '')
                    elem_ass:append(tooltiplabel or '')
                end
            end

            master_ass:merge(elem_ass)
        end
    end
end

return M
