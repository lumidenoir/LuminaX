-- ============================================================================
-- LuminaX Module: OSC
-- Core On-Screen Controller: timeline, seekbar, hover volume slider, controls & layout
-- ============================================================================

local assdraw = require('mp.assdraw')
local msg     = require('mp.msg')
local opt     = require('mp.options')
local utils   = require('mp.utils')

local M = {}

local ctx_ref = {}

local function menu_open(mtype)
    if ctx_ref.menu then ctx_ref.menu.menu_open(mtype) end
end

local function menu_close()
    if ctx_ref.menu then ctx_ref.menu.menu_close() end
end

local function render_overlay_menu(ass)
    if ctx_ref.menu then ctx_ref.menu.render(ass) end
end

local function render_input_box(ass)
    if ctx_ref.tag_editor then ctx_ref.tag_editor.render(ass) end
end

local function is_input_active()
    return ctx_ref.tag_editor and ctx_ref.tag_editor.is_active()
end

local function is_ss_active()
    return ctx_ref.screensaver and ctx_ref.screensaver.is_active()
end

local function ss_hide(imm)
    if ctx_ref.screensaver then ctx_ref.screensaver.hide(imm) end
end

local activate_screensaver = function()
    if ctx_ref.screensaver and ctx_ref.screensaver.activate then
        ctx_ref.screensaver.activate()
    end
end
local ss_delay_timer = nil
local tick_delay = 0.03
local is_december = os.date("*t").month == 12

-- ============================================================================
-- Sub-module Integration (Decomposed Architecture R14)
-- ============================================================================
local osc_state    = require('modules.osc.osc_state')
local osc_layout   = require('modules.osc.osc_layout')
local osc_seekbar  = require('modules.osc.osc_seekbar')
local osc_controls = require('modules.osc.osc_controls')
local osc_render   = require('modules.osc.osc_render')

-- Aliases to sub-module state tables
local user_opts   = osc_state.user_opts
local state       = osc_state.state
local osc_param   = osc_state.osc_param
local osc_styles  = osc_state.osc_styles
local icons       = osc_state.icons
local jumpicons   = osc_state.jumpicons
local texts       = osc_state.texts
local elements    = osc_state.elements
local thumbfast   = osc_state.thumbfast
local nicetypes   = osc_controls.nicetypes
local tracks_osc  = osc_controls.tracks_osc

-- Delegated coordinate & hitbox primitives
local get_virt_scale_factor  = osc_state.get_virt_scale_factor
local get_virt_mouse_pos     = osc_state.get_virt_mouse_pos
local set_virt_mouse_area    = osc_state.set_virt_mouse_area
local scale_value            = osc_state.scale_value
local limit_range            = osc_state.limit_range
local get_hitbox_coords      = osc_state.get_hitbox_coords
local get_hitbox_coords_geo  = osc_state.get_hitbox_coords_geo
local get_element_hitbox     = osc_state.get_element_hitbox
local mouse_hit              = osc_state.mouse_hit
local mouse_hit_coords       = osc_state.mouse_hit_coords
local countone               = osc_state.countone
local mult_alpha             = osc_state.mult_alpha
local add_area               = osc_state.add_area
local ass_append_alpha       = osc_state.ass_append_alpha
local ass_draw_cir_cw        = osc_state.ass_draw_cir_cw
local ass_draw_rr_h_cw       = osc_state.ass_draw_rr_h_cw
local ass_draw_rr_h_ccw      = osc_state.ass_draw_rr_h_ccw
local new_element            = osc_state.new_element
local validate_user_opts     = osc_state.validate_user_opts

-- Delegated layout primitives
local window_controls_enabled= osc_layout.window_controls_enabled
local build_keyboard_controls= osc_layout.build_keyboard_controls
local window_controls        = osc_layout.window_controls
local layouts                = osc_layout.layouts

-- Delegated seekbar & chapter primitives
local get_slider_ele_pos_for = osc_seekbar.get_slider_ele_pos_for
local get_slider_value_at    = osc_seekbar.get_slider_value_at
local get_slider_value       = osc_seekbar.get_slider_value
local get_chapter            = osc_seekbar.get_chapter
local limited_list           = osc_seekbar.limited_list
local function get_chapterlist() return osc_seekbar.get_chapterlist(ctx_ref) end

-- Delegated controls & tracklist primitives
local update_tracklist       = osc_controls.update_tracklist
local get_tracklist          = osc_controls.get_tracklist
local set_track              = osc_controls.set_track
local get_track              = osc_controls.get_track
local get_playlist           = osc_controls.get_playlist
local add_layout             = osc_controls.add_layout
local render_message         = osc_controls.render_message
local function show_message(text, dur) osc_controls.show_message(text, dur, request_tick) end

-- Delegated render primitives
local set_osd                = osc_render.set_osd
local prepare_elements       = osc_render.prepare_elements
local function render_elements(master_ass) osc_render.render_elements(master_ass, ctx_ref) end

function update_options(list)
    validate_user_opts()
    request_tick()
    visibility_mode(user_opts.visibility, true)
    update_duration_watch()
    request_init()
end

-- OSC INIT
function osc_init()
    msg.debug('osc_init')

    osc_layout.calc_canvas_resolution()

    -- stop seeking with the slider to prevent skipping files
    state.active_element = nil

    osc_state.clear_elements()

    -- some often needed stuff
    local pl_count = mp.get_property_number('playlist-count', 0)
    local have_pl = (pl_count > 1)
    local pl_pos = mp.get_property_number('playlist-pos', 0) + 1
    local have_ch = (mp.get_property_number('chapters', 0) > 0)
    local loop = mp.get_property('loop-playlist', 'no')

    local ne

    -- playlist buttons
    -- prev
    ne = new_element('pl_prev', 'button')

    ne.content = icons.previous
    ne.enabled = (pl_pos > 1) or (loop ~= 'no')
    ne.eventresponder['mbtn_left_up'] =
        function ()
            local cur_pos = mp.get_property_number('playlist-pos', 0) + 1
            local cur_loop = mp.get_property('loop-playlist', 'no')
            if cur_pos > 1 or (cur_loop ~= 'no') then
                mp.commandv('playlist-prev', 'weak')
            end
        end
    ne.eventresponder['mbtn_right_up'] =
        function () show_message(get_playlist()) end

    --next
    ne = new_element('pl_next', 'button')

    ne.content = icons.next
    ne.enabled = (have_pl and (pl_pos < pl_count)) or (loop ~= 'no')
    ne.eventresponder['mbtn_left_up'] =
        function ()
            local cur_cnt = mp.get_property_number('playlist-count', 0)
            local cur_pos = mp.get_property_number('playlist-pos', 0) + 1
            local cur_loop = mp.get_property('loop-playlist', 'no')
            if (cur_cnt > 1 and cur_pos < cur_cnt) or (cur_loop ~= 'no') then
                mp.commandv('playlist-next', 'weak')
            end
        end
    ne.eventresponder['mbtn_right_up'] =
        function () show_message(get_playlist()) end


    --play control buttons
    --playpause
    ne = new_element('playpause', 'button')

    ne.content = function ()
        if mp.get_property('pause') == 'yes' then
            return (icons.play)
        else
            return (icons.pause)
        end
    end
    ne.eventresponder['mbtn_left_up'] =
        function () mp.commandv('cycle', 'pause') end
    --ne.eventresponder['mbtn_right_up'] =
    --    function () mp.commandv('script-binding', 'open-file-dialog') end

    if user_opts.showjump then
        local jumpamount = user_opts.jumpamount
        local jumpmode = user_opts.jumpmode
        local icons = jumpicons.default
        if user_opts.jumpiconnumber then
            icons = jumpicons[jumpamount] or jumpicons.default
        end

        --jumpback
        ne = new_element('jumpback', 'button')

        ne.softrepeat = true
        ne.content = icons[1]
        ne.eventresponder['mbtn_left_down'] =
            --function () mp.command('seek -5') end
            function () mp.commandv('seek', -jumpamount, jumpmode) end
        ne.eventresponder['shift+mbtn_left_down'] =
            function () mp.commandv('frame-back-step') end
        ne.eventresponder['mbtn_right_down'] =
            --function () mp.command('seek -60') end
            function () mp.commandv('seek', -60, jumpmode) end
        ne.eventresponder['enter'] =
            --function () mp.command('seek -5') end
            function () mp.commandv('seek', -jumpamount, jumpmode) end


        --jumpfrwd
        ne = new_element('jumpfrwd', 'button')

        ne.softrepeat = true
        ne.content = icons[2]
        ne.eventresponder['mbtn_left_down'] =
            --function () mp.command('seek +5') end
            function () mp.commandv('seek', jumpamount, jumpmode) end
        ne.eventresponder['shift+mbtn_left_down'] =
            function () mp.commandv('frame-step') end
        ne.eventresponder['mbtn_right_down'] =
            --function () mp.command('seek +60') end
            function () mp.commandv('seek', 60, jumpmode) end
        ne.eventresponder['enter'] =
            --function () mp.command('seek +5') end
            function () mp.commandv('seek', jumpamount, jumpmode) end
    end
    

    --skipback
    ne = new_element('skipback', 'button')

    ne.softrepeat = true
    ne.content = icons.backward
    ne.enabled = (have_ch) -- disables button when no chapters available.
    ne.eventresponder['mbtn_left_down'] =
        --function () mp.command('seek -5') end
        --function () mp.commandv('seek', -5, 'relative', 'keyframes') end
        function () mp.commandv("add", "chapter", -1) end
    --ne.eventresponder['shift+mbtn_left_down'] =
        --function () mp.commandv('frame-back-step') end
    ne.eventresponder['mbtn_right_down'] =
        function () show_message(get_chapterlist()) end
        --function () mp.command('seek -60') end
        --function () mp.commandv('seek', -60, 'relative', 'keyframes') end
    ne.eventresponder['enter'] =
        --function () mp.command('seek -5') end
        --function () mp.commandv('seek', -5, 'relative', 'keyframes') end
        function () mp.commandv("add", "chapter", -1) end

    --skipfrwd
    ne = new_element('skipfrwd', 'button')

    ne.softrepeat = true
    ne.content = icons.forward
    ne.enabled = (have_ch) -- disables button when no chapters available.
    ne.eventresponder['mbtn_left_down'] =
        --function () mp.command('seek +5') end
        --function () mp.commandv('seek', 5, 'relative', 'keyframes') end
        function () mp.commandv("add", "chapter", 1) end
    --ne.eventresponder['shift+mbtn_left_down'] =
        --function () mp.commandv('frame-step') end
    ne.eventresponder['mbtn_right_down'] =
        function () show_message(get_chapterlist()) end
        --function () mp.command('seek +60') end
        --function () mp.commandv('seek', 60, 'relative', 'keyframes') end
    ne.eventresponder['enter'] =
        --function () mp.command('seek +5') end
        --function () mp.commandv('seek', 5, 'relative', 'keyframes') end
        function () mp.commandv("add", "chapter", 1) end

    --
    update_tracklist()
    
    --cy_audio
    ne = new_element('cy_audio', 'button')
    ne.enabled = (#tracks_osc.audio > 0)
    ne.off = (get_track('audio') == 0)
    ne.visible = (osc_param.playresx >= 540)
    ne.content = icons.audio
    ne.tooltip_style = osc_styles.Tooltip
    ne.tooltipF = function ()
		local msg = texts.off
        if not (get_track('audio') == 0) then
            msg = (texts.audio .. ' [' .. get_track('audio') .. ' ∕ ' .. #tracks_osc.audio .. '] ')
            local prop = mp.get_property('current-tracks/audio/title') --('current-tracks/audio/lang')
            if not prop then
				prop = texts.na
			end
			msg = msg .. '[' .. prop .. ']'
			prop = mp.get_property('current-tracks/audio/lang') --('current-tracks/audio/title')
			if prop then
				msg = msg .. ' ' .. prop
			end
			return msg
        end
        return msg
    end
    ne.eventresponder['mbtn_left_up'] =
        function ()
            if state.menu_active == 'audio' then
                menu_close()
            else
                menu_open('audio')
            end
        end
    ne.eventresponder['mbtn_right_up'] =
        function ()
            if state.menu_active == 'audio' then
                menu_close()
            else
                menu_open('audio')
            end
        end
    ne.eventresponder['shift+mbtn_left_down'] =
        function ()
            if state.menu_active == 'audio' then
                menu_close()
            else
                menu_open('audio')
            end
        end
    ne.eventresponder['enter'] =
        function ()
            if state.menu_active == 'audio' then
                menu_close()
            else
                menu_open('audio')
            end
        end
                
    --cy_sub
    ne = new_element('cy_sub', 'button')
    ne.enabled = (#tracks_osc.sub > 0)
    ne.off = (get_track('sub') == 0)
    ne.visible = (osc_param.playresx >= 600)
    ne.content = icons.sub
    ne.tooltip_style = osc_styles.Tooltip
    ne.tooltipF = function ()
		local msg = texts.off
        if not (get_track('sub') == 0) then
            msg = (texts.subtitle .. ' [' .. get_track('sub') .. ' ∕ ' .. #tracks_osc.sub .. '] ')
            local prop = mp.get_property('current-tracks/sub/lang')
            if not prop then
				prop = texts.na
			end
			msg = msg .. '[' .. prop .. ']'
			prop = mp.get_property('current-tracks/sub/title')
			if prop then
				msg = msg .. ' ' .. prop
			end
			return msg
        end
        return msg
    end
    ne.eventresponder['mbtn_left_up'] =
        function ()
            if state.menu_active == 'sub' then
                menu_close()
            else
                menu_open('sub')
            end
        end
    ne.eventresponder['mbtn_right_up'] =
        function ()
            if state.menu_active == 'sub_config' then
                menu_close()
            else
                menu_open('sub_config')
            end
        end
    ne.eventresponder['shift+mbtn_left_down'] =
        function ()
            if state.menu_active == 'sub' then
                menu_close()
            else
                menu_open('sub')
            end
        end

    -- tog_video
    ne = new_element('tog_video', 'button')
    ne.content = icons.video
    ne.tooltip_style = osc_styles.Tooltip
    ne.tooltip_an = 2
    ne.tooltip_text = 'Video Adjustments (V)'
    ne.eventresponder['mbtn_left_up'] =
        function ()
            if state.menu_active == 'video' then
                menu_close()
            else
                menu_open('video')
            end
        end

    -- vol_ctrl
    ne = new_element('vol_ctrl', 'button')
    ne.enabled = (get_track('audio')>0)
    ne.visible = (osc_param.playresx >= 650) and user_opts.volumecontrol
    ne.content = function ()
        local vol = mp.get_property_number('volume', 100)
        if (state.mute or (vol ~= nil and vol <= 0)) then
            return (icons.volume_mute)
        else
            return (icons.volume)
        end
    end
    ne.eventresponder['mbtn_left_up'] =
        function () mp.commandv('cycle', 'mute') end
    ne.eventresponder["wheel_up_press"] =
        function () mp.commandv("osd-auto", "add", "volume", 5) end
    ne.eventresponder["wheel_down_press"] =
        function () mp.commandv("osd-auto", "add", "volume", -5) end
    
    -- tog_fs
    ne = new_element('tog_fs', 'button')
    ne.content = function ()
        if (state.fullscreen) then
            return (icons.minimize)
        else
            return (icons.fullscreen)
        end
    end
    ne.visible = (osc_param.playresx >= 500)
    ne.tooltip_style = osc_styles.Tooltip
    ne.tooltipF = 'Fullscreen (F)'
    ne.eventresponder['mbtn_left_up'] =
        function () mp.commandv('cycle', 'fullscreen') end

    -- tog_info
    ne = new_element('tog_info', 'button')
    ne.content = icons.info
    ne.visible = (osc_param.playresx >= 540)
    ne.tooltip_style = osc_styles.Tooltip
    ne.tooltipF = 'Media Information & Stats (I)'
    ne.eventresponder['mbtn_left_up'] =
        function () mp.commandv('script-binding', 'stats/display-stats-toggle') end

    -- tog_update (Only visible & active when an update is available)
    ne = new_element('tog_update', 'button')
    ne.content = function ()
        if state.update_available then
            return '{\\1c&H60E0FF&}' .. (icons.update or '\238\164\163') .. '{\\r}'
        else
            return ''
        end
    end
    ne.visible = (state.update_available ~= nil)
    ne.tooltip_style = osc_styles.Tooltip
    ne.tooltipF = function ()
        if state.update_available then
            return string.format('✨ LuminaX Update: v%s (Click to install now)', state.update_available.version or '')
        else
            return ''
        end
    end
    ne.eventresponder['mbtn_left_up'] = function ()
        if state.update_available then
            mp.commandv('script-message', 'update-run')
        end
    end
    ne.eventresponder['mbtn_right_up'] = function ()
        if state.update_available then
            mp.commandv('script-message', 'update-run')
        end
    end

    -- tog_tags
    ne = new_element('tog_tags', 'button')
    ne.content = icons.tags or '\238\149\142'
    ne.visible = (osc_param.playresx >= 660)
    ne.tooltip_style = osc_styles.Tooltip
    ne.tooltipF = 'Metadata & Tag Editor (T)'
    ne.eventresponder['mbtn_left_up'] =
        function ()
            if state.menu_active == 'tags' then
                menu_close()
            else
                menu_open('tags')
            end
        end

    -- tog_speed
    ne = new_element('tog_speed', 'button')
    ne.visible = (osc_param.playresx >= 720)
    ne.tooltip_style = osc_styles.Tooltip
    ne.tooltipF = 'Playback Speed (Click: Cycle, Right: Reset 1.0×, Scroll: ±0.1×)'
    ne.content = function ()
        local spd = mp.get_property_number('speed', 1.0) or 1.0
        if math.abs(spd - 1.0) < 0.01 then
            return '1.0×'
        else
            return string.format('%.2f×', spd):gsub('0×$', '×')
        end
    end
    ne.eventresponder['mbtn_left_up'] = function ()
        local spd = mp.get_property_number('speed', 1.0) or 1.0
        local speeds = {1.0, 1.25, 1.5, 2.0, 0.75}
        local next_spd = 1.25
        for i, s in ipairs(speeds) do
            if math.abs(spd - s) < 0.05 then
                next_spd = speeds[(i % #speeds) + 1]
                break
            end
        end
        mp.set_property_number('speed', next_spd)
    end
    ne.eventresponder['mbtn_right_up'] = function ()
        mp.set_property_number('speed', 1.0)
    end
    ne.eventresponder['wheel_up_press'] = function ()
        local spd = mp.get_property_number('speed', 1.0) or 1.0
        local next_spd = math.min(4.0, math.floor((spd + 0.1) * 10 + 0.5) / 10)
        mp.set_property_number('speed', next_spd)
    end
    ne.eventresponder['wheel_down_press'] = function ()
        local spd = mp.get_property_number('speed', 1.0) or 1.0
        local next_spd = math.max(0.2, math.floor((spd - 0.1) * 10 + 0.5) / 10)
        mp.set_property_number('speed', next_spd)
    end

    -- tog_chapters
    ne = new_element('tog_chapters', 'button')
    ne.content = icons.chapters or '\238\137\130'
    ne.visible = (osc_param.playresx >= 580)
    ne.tooltip_style = osc_styles.Tooltip
    ne.tooltipF = 'Chapters (C)'
    ne.eventresponder['mbtn_left_up'] =
        function ()
            if state.menu_active == 'chapters' then
                menu_close()
            else
                menu_open('chapters')
            end
        end

    -- tog_playlist
    ne = new_element('tog_playlist', 'button')
    ne.content = icons.playlist
    ne.visible = (osc_param.playresx >= 620)
    ne.tooltip_style = osc_styles.Tooltip
    ne.tooltipF = 'Playlist (P)'
    ne.eventresponder['mbtn_left_up'] =
        function ()
            if state.menu_active == 'playlist' then
                menu_close()
            else
                menu_open('playlist')
            end
        end


    -- title (display only)
    ne = new_element('title', 'button')
    ne.content = function ()
        -- 1. If official TMDB metadata is active, prioritize broadcast-quality title
        local tmdb_curr = ctx_ref.screensaver and ctx_ref.screensaver.get_current and ctx_ref.screensaver.get_current()
        if tmdb_curr and tmdb_curr.show_name and tmdb_curr.show_name ~= '' then
            local s_ep = (tmdb_curr.season_ep or ''):gsub('%s+', '')
            if tmdb_curr.ep_title and tmdb_curr.ep_title ~= '' then
                if s_ep ~= '' then
                    return string.format(
                        '%s \xc2\xb7 %s \xc2\xb7 %s',
                        tmdb_curr.show_name, s_ep, tmdb_curr.ep_title
                    )
                else
                    return string.format('%s \xc2\xb7 %s', tmdb_curr.show_name, tmdb_curr.ep_title)
                end
            elseif s_ep ~= '' then
                return string.format('%s \xc2\xb7 %s', tmdb_curr.show_name, s_ep)
            else
                if tmdb_curr.year and tmdb_curr.year ~= '' then
                    return string.format('%s (%s)', tmdb_curr.show_name, tmdb_curr.year)
                else
                    return tmdb_curr.show_name
                end
            end
        end

        -- 2. High-precision clean parser via utils (handles anime ordinal seasons, SxxExx, movies)
        local u = ctx_ref.utils
        if u and u.parse_clean_title then
            local cur_media_title = mp.get_property('media-title')
            local cur_filename = mp.get_property('filename')
            local clean_show, clean_s, clean_e, clean_y = u.parse_clean_title(cur_media_title, cur_filename)
            if clean_show and clean_s and clean_e then
                return string.format('%s \xc2\xb7 S%02dE%02d', clean_show, tonumber(clean_s), tonumber(clean_e))
            elseif clean_show and clean_y then
                return string.format('%s (%s)', clean_show, clean_y)
            elseif clean_show and clean_show ~= '' then
                return clean_show
            end
        end

        local raw = mp.command_native({"expand-text", user_opts.title})

        -- clean filename separators first
        raw = raw
            :gsub('%.[Ss](%d+)[Ee](%d+)%.', ' S%1E%2 ')  -- preserve SxxExx before dot-cleaning
            :gsub('%.', ' ')
            :gsub('_', ' ')
            :gsub('%b[]', '')
            :gsub('%s+', ' ')
            :gsub('^%s+', '')

        -- detect series + episode: ShowName S01E05 EpisodeName
        local show, season, episode, epname =
            raw:match("^(.-)%s*[Ss](%d+)[Ee](%d+)%s*(.-)$")

        if show and season and episode then
            -- clean show name: strip trailing year / junk
            show = show
                :gsub('%s*%(%d%d%d%d%)%s*$', '')  -- trailing (2024)
                :gsub('%s+%d%d%d%d%s*$', '')       -- trailing 2024
                :gsub('[%s%-]+$', '')

            epname = (epname or '')
                -- strip encode/release garbage
                :gsub('2160[pP].*',  '')
                :gsub('1080[pP].*',  '')
                :gsub('[72]20[pP].*', '')
                :gsub('4[Kk].*',     '')
                :gsub('[Uu][Hh][Dd].*', '')
                :gsub('[Aa][Mm][Zz][Nn].*', '')
                :gsub('[Nn][Ff]%f[%A].*', '')
                :gsub('[Aa][Tt][Vv][Pp].*', '')
                :gsub('[Dd][Ss][Nn][Pp].*', '')
                :gsub('[Hh][Uu][Ll][Uu].*', '')
                :gsub('[Bb]lu[Rr]ay.*', '')
                :gsub('[Ww][Ee][Bb]%-[Dd][Ll].*', '')
                :gsub('[Ww][Ee][Bb][Rr]ip.*', '')
                :gsub('[Hh][Ee][Vv][Cc].*', '')
                :gsub('[Hh]%.?26[45].*', '')
                :gsub('[Xx]26[45].*',    '')
                :gsub('[Dd][Tt][Ss].*',  '')
                :gsub('[Dd][Dd][Pp].*',  '')
                :gsub('[Aa][Aa][Cc].*',  '')
                -- strip language tags (Hindi/Telugu/Tamil/…)
                :gsub('%s*[Hh]indi.*',   '')
                :gsub('%s*[Ee]nglish.*', '')
                :gsub('%s*[Tt]elugu.*',  '')
                :gsub('%s*[Tt]amil.*',   '')
                :gsub('%s*[Jj]apanese.*','  ')
                -- strip trailing punctuation / hyphens / ellipsis
                :gsub('[%s%.%-]+$', '')
                :gsub('%.%.%.?$',   '')
                :gsub('%s+$',       '')

            if epname ~= '' then
                return string.format(
                    '%s \xc2\xb7 S%02dE%02d \xc2\xb7 %s',
                    show, tonumber(season), tonumber(episode), epname
                )
            else
                return string.format(
                    '%s \xc2\xb7 S%02dE%02d',
                    show, tonumber(season), tonumber(episode)
                )
            end
        end

        -- detect movie + year: "Movie Name 2024 ..."
        local title, year = raw:match('^(.-)%s+(%d%d%d%d)%s')
        if title and year then
            title = title:gsub('[%s%-]+$', '')
            return string.format('%s (%s)', title, year)
        end

        -- final fallback: strip codec/release junk
        raw = raw
            :gsub('2160[pP].*', ''):gsub('1080[pP].*', '')
            :gsub('[72]20[pP].*', ''):gsub('4[Kk].*', '')
            :gsub('[Uu][Hh][Dd].*', ''):gsub('[Aa][Mm][Zz][Nn].*', '')
            :gsub('[Bb]lu[Rr]ay.*', ''):gsub('[Ww][Ee][Bb]%-[Dd][Ll].*', '')
            :gsub('[Hh][Ee][Vv][Cc].*', ''):gsub('[Xx]26[45].*', '')
            :gsub('[Dd][Tt][Ss].*', ''):gsub('[%s%-]+$', '')
        return raw
    end
    ne.visible = osc_param.playresy >= 320 and user_opts.showtitle

    -- media_badges (above title — collected in layout; rendered by render_media_badges)
    ne = new_element('media_badges', 'button')
    ne.visible = osc_param.playresy >= 320 and (osc_param.playresx >= 540)
    
    --seekbar
    ne = new_element('seekbar', 'slider')

    ne.enabled = not (mp.get_property('percent-pos') == nil)
    state.slider_element = ne.enabled and ne or nil  -- used for forced_title
    ne.slider.markerF = function ()
        local duration = mp.get_property_number('duration', nil)
        if duration and duration > 0 then
            local chapters = mp.get_property_native('chapter-list', {})
            local markers = {}
            for n = 1, #(chapters or {}) do
                if chapters[n] and chapters[n].time then
                    table.insert(markers, (chapters[n].time / duration * 100))
                end
            end
            return markers
        else
            return {}
        end
    end
    ne.slider.posF =
        function () return mp.get_property_number('percent-pos', nil) end
    ne.slider.tooltipF = function (pos)
        local duration = mp.get_property_number('duration', nil)
        if duration and pos then
            local possec = duration * (pos / 100)
            local u = ctx_ref.utils
            return (u and u.format_time) and u.format_time(possec) or '00:00'
        else
            return ''
        end
    end
    ne.slider.seekRangesF = function()
        if not user_opts.seekrange then
            return nil
        end
        local cache_state = state.cache_state
        if not cache_state then
            return nil
        end
        local duration = mp.get_property_number('duration', nil)
        if (duration == nil) or duration <= 0 then
            return nil
        end
        local ranges = cache_state['seekable-ranges']
        if #ranges == 0 then
            return nil
        end
        local nranges = {}
        for _, range in pairs(ranges) do
            nranges[#nranges + 1] = {
                ['start'] = 100 * range['start'] / duration,
                ['end'] = 100 * range['end'] / duration,
            }
        end
        return nranges
    end
    ne.eventresponder['mouse_move'] = --keyframe seeking when mouse is dragged
        function (element)
			if not element.state.mbtnleft then return end -- allow drag for mbtnleft only!
            -- mouse move events may pile up during seeking and may still get
            -- sent when the user is done seeking, so we need to throw away
            -- identical seeks
            local seekto = get_slider_value(element)
            if (element.state.lastseek == nil) or
                (not (element.state.lastseek == seekto)) then
                    local flags = 'absolute-percent'
                    if not user_opts.seekbarkeyframes then
                        flags = flags .. '+exact'
                    end
                    mp.commandv('seek', seekto, flags)
                    element.state.lastseek = seekto
            end

        end
    ne.eventresponder['mbtn_left_down'] = --exact seeks on single clicks
        function (element)
			mp.commandv('seek', get_slider_value(element), 'absolute-percent', 'exact')
			element.state.mbtnleft = true
		end
	ne.eventresponder['mbtn_left_up'] =
		function (element) element.state.mbtnleft = false end
    ne.eventresponder['mbtn_right_down'] = --seeks to chapter start
        function (element)
			local duration = mp.get_property_number('duration', nil)
			if not (duration == nil) then
				local chapters = mp.get_property_native('chapter-list', {})
				if #chapters > 0 then
					local pos = get_slider_value(element)
					local ch = #chapters
					for n = 1, ch do
						if chapters[n].time / duration * 100 >= pos then
							ch = n - 1
							break
						end
					end
					mp.commandv('set', 'chapter', ch - 1)
					--if chapters[ch].title then show_message(chapters[ch].time) end
				end
			end
		end
    ne.eventresponder['reset'] =
        function (element) element.state.lastseek = nil end

    --volumebar
    ne = new_element('volumebar', 'slider')
    ne.visible = (osc_param.playresx >= 700) and user_opts.volumecontrol
    ne.enabled = (get_track('audio')>0)
    ne.slider.markerF = function ()
        return {}
    end
    ne.slider.seekRangesF = function()
      return nil
    end
    ne.slider.posF =
        function ()
            local val = mp.get_property_number('volume', 0)
            if not val then return 0 end
            return math.min(100, math.max(0, val))
        end
    ne.slider.tooltipF = function (val)
        return string.format('%d%%', math.floor(val + 0.5))
    end
    ne.eventresponder['mouse_move'] =
        function (element)
            if not element.state.mbtnleft then return end -- allow drag for mbtnleft only!
            local seekto = get_slider_value(element)
            if (element.state.lastseek == nil) or
                (not (element.state.lastseek == seekto)) then
                    local target_vol = math.min(100, math.max(0, seekto))
                    mp.commandv('set', 'volume', target_vol)
                    element.state.lastseek = seekto
            end
        end
    ne.eventresponder['mbtn_left_down'] = --exact seeks on single clicks
        function (element)
            local seekto = get_slider_value(element)
            local target_vol = math.min(100, math.max(0, seekto))
            mp.commandv('set', 'volume', target_vol)
            element.state.mbtnleft = true
        end
    ne.eventresponder['mbtn_left_up'] =
        function (element) element.state.mbtnleft = false end
    ne.eventresponder['reset'] =
        function (element) element.state.lastseek = nil end
    ne.eventresponder["wheel_up_press"] =
        function () mp.commandv("osd-auto", "add", "volume", 5) end
    ne.eventresponder["wheel_down_press"] =
        function () mp.commandv("osd-auto", "add", "volume", -5) end
    
    -- tc_left (current pos)
    ne = new_element('tc_left', 'button')
    ne.content = function ()
	if (state.fulltime) then
		return (mp.get_property_osd('playback-time/full'))
	else
		return (mp.get_property_osd('playback-time'))
	end
    end
    ne.eventresponder["mbtn_left_up"] = function ()
        state.fulltime = not state.fulltime
        request_init()
    end
    -- tc_right (total/remaining time)
    ne = new_element('tc_right', 'button')
    ne.content = function ()
        if (mp.get_property_number('duration', 0) <= 0) then return '--:--:--' end
        if (state.rightTC_trem) then
		if (state.fulltime) then
			return ('-'..mp.get_property_osd('playtime-remaining/full'))
		else
			return ('-'..mp.get_property_osd('playtime-remaining'))
		end
        else
		if (state.fulltime) then
			return (mp.get_property_osd('duration/full'))
		else
			return (mp.get_property_osd('duration'))
		end
			
        end
    end
    ne.eventresponder['mbtn_left_up'] =
        function () state.rightTC_trem = not state.rightTC_trem end

    -- load layout
    layouts()

    -- load window controls
    if window_controls_enabled() then
        window_controls()
    end

    --do something with the elements
    prepare_elements()
end

function shutdown()
    
end

--
-- Other important stuff
--


function show_osc()
    -- show when disabled can happen (e.g. mouse_move) due to async/delayed unbinding
    if not state.enabled then return end

    if is_ss_active() then ss_hide()
        if mp.get_property_native('pause') and user_opts.screensaver_enabled then
            if ss_delay_timer then ss_delay_timer:kill() end
            if activate_screensaver then
                ss_delay_timer = mp.add_timeout(
                    math.max(1, tonumber(user_opts.screensaver_delay) or 3),
                    activate_screensaver
                )
            end
        end
    end

    msg.trace('show_osc')
    --remember last time of invocation (mouse move)
    state.showtime = mp.get_time()

    osc_visible(true)
    
    if user_opts.keyboardnavigation == true then
        osc_enable_key_bindings()
    end

    if (user_opts.fadeduration > 0) then
        state.anitype = nil
    end
end

function hide_osc()
    msg.trace('hide_osc')
    -- Close any open overlay menu
    if state.menu_active then menu_close() end
    if not state.enabled then
        -- typically hide happens at render() from tick(), but now tick() is
        -- no-op and won't render again to remove the osc, so do that manually.
        state.osc_visible = false
        render_wipe()
        if user_opts.keyboardnavigation == true then
            osc_disable_key_bindings()
        end
    elseif (user_opts.fadeduration > 0) then
        if not(state.osc_visible == false) then
            state.anitype = 'out'
            request_tick()
        end
    else
        osc_visible(false)
    end
end

function osc_visible(visible)
    if state.osc_visible ~= visible then
        state.osc_visible = visible
        if ctx_ref and ctx_ref.subtitle and ctx_ref.subtitle.update_overlay then
            ctx_ref.subtitle.update_overlay()
        end
    end
    request_tick()
end

function pause_state(name, enabled)
    state.paused = enabled
    mp.add_timeout(0.1, function() state.osd:update() end) 
    if user_opts.showonpause then
		if enabled then
			state.lastvisibility = user_opts.visibility
			visibility_mode("always", true)
			show_osc()
		else
			visibility_mode(state.lastvisibility, true)
		end
	end
    request_tick()
end

function cache_state(name, st)
    state.cache_state = st
    request_tick()
end

-- Request that tick() is called (which typically re-renders the OSC).
-- The tick is then either executed immediately, or rate-limited if it was
-- called a small time ago.
function request_tick()
    if state.tick_timer == nil then
        state.tick_timer = mp.add_timeout(0, tick)
    end

    if not state.tick_timer:is_enabled() then
        local now = mp.get_time()
        local timeout = tick_delay - (now - state.tick_last_time)
        if timeout < 0 then
            timeout = 0
        end
        state.tick_timer.timeout = timeout
        state.tick_timer:resume()
    end
end

function mouse_leave()
    if get_hidetimeout() >= 0 then
        hide_osc()
    end
    -- reset mouse position
    state.last_mouseX, state.last_mouseY = nil, nil
    state.mouse_in_window = false
end

function request_init()
    state.initREQ = true
    request_tick()
end

-- Like request_init(), but also request an immediate update
function request_init_resize()
    request_init()
    -- ensure immediate update
    state.tick_timer:kill()
    state.tick_timer.timeout = 0
    state.tick_timer:resume()
end

function render_wipe()
    msg.trace('render_wipe()')
    state.osd:remove()
end

function render()
    msg.trace('rendering')
    local current_screen_sizeX, current_screen_sizeY, aspect = mp.get_osd_size()
    local mouseX, mouseY = get_virt_mouse_pos()
    local now = mp.get_time()

    -- check if display changed, if so request reinit
    if not (state.mp_screen_sizeX == current_screen_sizeX
        and state.mp_screen_sizeY == current_screen_sizeY) then

        request_init_resize()

        state.mp_screen_sizeX = current_screen_sizeX
        state.mp_screen_sizeY = current_screen_sizeY
    end

    -- auto-reinit layout when update state changes (e.g. update becomes available or completes)
    local has_update = (state.update_available ~= nil)
    if state.last_update_state ~= has_update then
        state.last_update_state = has_update
        request_init_resize()
    end

    -- init management
    if state.active_element then
        -- mouse is held down on some element - keep ticking and igore initReq
        -- till it's released, or else the mouse-up (click) will misbehave or
        -- get ignored. that's because osc_init() recreates the osc elements,
        -- but mouse handling depends on the elements staying unmodified
        -- between mouse-down and mouse-up (using the index active_element).
        request_tick()
    elseif state.initREQ then
        osc_init()
        state.initREQ = false

        -- store initial mouse position
        if (state.last_mouseX == nil or state.last_mouseY == nil)
            and not (mouseX == nil or mouseY == nil) then

            state.last_mouseX, state.last_mouseY = mouseX, mouseY
        end
    end


    -- fade animation
    if not(state.anitype == nil) then

        if (state.anistart == nil) then
            state.anistart = now
        end

        if (now < state.anistart + (user_opts.fadeduration/1000)) then

            if (state.anitype == 'in') then --fade in
                osc_visible(true)
                state.animation = scale_value(state.anistart,
                    (state.anistart + (user_opts.fadeduration/1000)),
                    255, 0, now)
            elseif (state.anitype == 'out') then --fade out
                state.animation = scale_value(state.anistart,
                    (state.anistart + (user_opts.fadeduration/1000)),
                    0, 255, now)
            end

        else
            if (state.anitype == 'out') then
                osc_visible(false)
            end
            state.anistart = nil
            state.animation = nil
            state.anitype =  nil
        end
    else
        state.anistart = nil
        state.animation = nil
        state.anitype =  nil
    end

    -- seekbar hover expand animation lerp
    local sb = elements['seekbar']
    local is_sb_hover = (sb and mouse_hit(sb) and state.osc_visible)
    local sb_target = is_sb_hover and 1.0 or 0.0
    if state.seekbar_anim == nil then state.seekbar_anim = 0.0 end
    if state.seekbar_last_t == nil then state.seekbar_last_t = now end
    local dt = math.min(0.05, math.max(0.001, now - state.seekbar_last_t))
    state.seekbar_last_t = now

    if math.abs(state.seekbar_anim - sb_target) > 0.001 then
        state.seekbar_anim = state.seekbar_anim + (sb_target - state.seekbar_anim) * math.min(1.0, dt * 18)
        if math.abs(state.seekbar_anim - sb_target) < 0.008 then
            state.seekbar_anim = sb_target
        else
            request_tick()
        end
    end

    -- volume slider hover expand animation lerp
    local is_vol_hover = false
    local vmode = user_opts.volume_slider_mode or 'hover'
    if vmode == 'always' then
        is_vol_hover = true
    elseif vmode == 'hover' then
        local active_elem = state.active_element and elements[state.active_element]
        if active_elem and (active_elem.name == 'volumebar' or active_elem.name == 'vol_ctrl') then
            is_vol_hover = true
        elseif state.osc_visible then
            local mouseX, mouseY = get_virt_mouse_pos()
            local vc = elements['vol_ctrl']
            local vb = elements['volumebar']
            if mouseX and mouseY and vc and vc.layout and vb and vb.layout then
                local g_vc = vc.layout.geometry
                local g_vb = vb.layout.geometry
                local zx1 = g_vc.x - g_vc.w/2 - 10
                local zx2 = g_vb.x + g_vb.w + 14
                local zy1 = g_vc.y - g_vc.h/2 - 14
                local zy2 = g_vc.y + g_vc.h/2 + 14
                if mouseX >= zx1 and mouseX <= zx2 and mouseY >= zy1 and mouseY <= zy2 then
                    is_vol_hover = true
                end
            end
        end
    end

    local vol_target = is_vol_hover and 1.0 or 0.0
    if state.vol_anim == nil then state.vol_anim = (vmode == 'always') and 1.0 or 0.0 end
    if state.vol_last_t == nil then state.vol_last_t = now end
    local dt_vol = math.min(0.05, math.max(0.001, now - state.vol_last_t))
    state.vol_last_t = now

    if math.abs(state.vol_anim - vol_target) > 0.001 then
        state.vol_anim = state.vol_anim + (vol_target - state.vol_anim) * math.min(1.0, dt_vol * 18)
        if math.abs(state.vol_anim - vol_target) < 0.008 then
            state.vol_anim = vol_target
        else
            request_tick()
        end
    end

    --mouse show/hide area
    for k,cords in pairs(osc_param.areas['showhide']) do
        set_virt_mouse_area(cords.x1, cords.y1, cords.x2, cords.y2, 'showhide')
    end
    if osc_param.areas['showhide_wc'] then
        for k,cords in pairs(osc_param.areas['showhide_wc']) do
            set_virt_mouse_area(cords.x1, cords.y1, cords.x2, cords.y2, 'showhide_wc')
        end
    else
        set_virt_mouse_area(0, 0, 0, 0, 'showhide_wc')
    end
    do_enable_keybindings()

    --mouse input area
    local mouse_over_osc = false

    for _,cords in ipairs(osc_param.areas['input']) do
        if state.osc_visible then -- activate only when OSC is actually visible
            set_virt_mouse_area(cords.x1, cords.y1, cords.x2, cords.y2, 'input')
        end
        if state.osc_visible ~= state.input_enabled then
            if state.osc_visible then
                mp.enable_key_bindings('input')
            else
                mp.disable_key_bindings('input')
            end
            state.input_enabled = state.osc_visible
        end

        if (mouse_hit_coords(cords.x1, cords.y1, cords.x2, cords.y2)) then
            mouse_over_osc = true
        end
    end

    if osc_param.areas['window-controls'] then
        for _,cords in ipairs(osc_param.areas['window-controls']) do
            if state.osc_visible then -- activate only when OSC is actually visible
                set_virt_mouse_area(cords.x1, cords.y1, cords.x2, cords.y2, 'window-controls')
                mp.enable_key_bindings('window-controls')
            else
                mp.disable_key_bindings('window-controls')
            end

            if (mouse_hit_coords(cords.x1, cords.y1, cords.x2, cords.y2)) then
                mouse_over_osc = true
            end
        end
    end

    if osc_param.areas['window-controls-title'] then
        for _,cords in ipairs(osc_param.areas['window-controls-title']) do
            if (mouse_hit_coords(cords.x1, cords.y1, cords.x2, cords.y2)) then
                mouse_over_osc = true
            end
        end
    end

    -- autohide
    if not (state.showtime == nil) and (get_hidetimeout() >= 0) then
        local timeout = state.showtime + (get_hidetimeout()/1000) - now
        if timeout <= 0 then
            if (state.active_element == nil) and not (mouse_over_osc) and not state.menu_active then
                hide_osc()
            end
        else
            -- the timer is only used to recheck the state and to possibly run
            -- the code above again
            if not state.hide_timer then
                state.hide_timer = mp.add_timeout(0, tick)
            end
            state.hide_timer.timeout = timeout
            -- re-arm
            state.hide_timer:kill()
            state.hide_timer:resume()
        end
    end


    -- actual rendering
    local ass = assdraw.ass_new()

    -- Messages
    render_message(ass)

    -- Overlay menus (playlist / audio / sub / tags)
    render_overlay_menu(ass)

    -- In-player OSD text input modal
    render_input_box(ass)

    -- actual OSC
    local input_active = is_input_active and is_input_active()
    local is_any_menu_active = (state and state.menu_active ~= nil) or (ctx_ref.menu and ctx_ref.menu.is_active and ctx_ref.menu.is_active())
    if state.osc_visible and not is_ss_active() and not is_any_menu_active and not input_active then
        render_elements(ass)
    end

    -- submit
    set_osd(osc_param.playresy * osc_param.display_aspect,
            osc_param.playresy, ass.text)
end

--
-- Eventhandling
--

local function element_has_action(element, action)
    return element and element.eventresponder and
        element.eventresponder[action]
end

function process_event(source, what)
    if is_input_active() then return end
    if is_ss_active() then
        if what == 'up' or what == 'press' then
            ss_hide()
        end
        return
    end

    if (what == 'up' or what == 'press') and ctx_ref.smart_skip and ctx_ref.smart_skip.handle_mouse_click then
        local vx, vy = get_virt_mouse_pos()
        if ctx_ref.smart_skip.handle_mouse_click(vx, vy) then
            return
        end
    end

    local action = string.format('%s%s', source,
        what and ('_' .. what) or '')

    if what == 'down' or what == 'press' then

        for n = 1, #elements do

            if mouse_hit(elements[n]) and
                elements[n].eventresponder and
                (elements[n].eventresponder[source .. '_up'] or
                    elements[n].eventresponder[action]) then

                if what == 'down' then
                    state.active_element = n
                    state.active_event_source = source
                end
                -- fire the down or press event if the element has one
                if element_has_action(elements[n], action) then
                    elements[n].eventresponder[action](elements[n])
                end

            end
        end

    elseif what == 'up' then

        if elements[state.active_element] then
            local n = state.active_element

            if n == 0 then
                --click on background (does not work)
            elseif element_has_action(elements[n], action) and
                mouse_hit(elements[n]) then

                elements[n].eventresponder[action](elements[n])
            end

            --reset active element
            if element_has_action(elements[n], 'reset') then
                elements[n].eventresponder['reset'](elements[n])
            end

        end
        state.active_element = nil
        state.mouse_down_counter = 0

    elseif source == 'mouse_move' then

        state.mouse_in_window = true

        local mouseX, mouseY = get_virt_mouse_pos()
        if (user_opts.minmousemove == 0) or
            (not ((state.last_mouseX == nil) or (state.last_mouseY == nil)) and
                ((math.abs(mouseX - state.last_mouseX) >= user_opts.minmousemove)
                    or (math.abs(mouseY - state.last_mouseY) >= user_opts.minmousemove)
                )
            ) then
            show_osc()
        end
        state.last_mouseX, state.last_mouseY = mouseX, mouseY

        local n = state.active_element
        if element_has_action(elements[n], action) then
            elements[n].eventresponder[action](elements[n])
        end
    end

    -- ensure rendering after any (mouse) event - icons could change etc
    request_tick()
end

local logo_lines = {
    -- White border
    "{\\c&HE5E5E5&\\p6}m 895 10 b 401 10 0 410 0 905 0 1399 401 1800 895 1800 1390 1800 1790 1399 1790 905 1790 410 1390 10 895 10 {\\p0}",
    -- Purple fill
    "{\\c&H682167&\\p6}m 925 42 b 463 42 87 418 87 880 87 1343 463 1718 925 1718 1388 1718 1763 1343 1763 880 1763 418 1388 42 925 42{\\p0}",
    -- Darker fill
    "{\\c&H430142&\\p6}m 1605 828 b 1605 1175 1324 1456 977 1456 631 1456 349 1175 349 828 349 482 631 200 977 200 1324 200 1605 482 1605 828{\\p0}",
    -- White fill
    "{\\c&HDDDBDD&\\p6}m 1296 910 b 1296 1131 1117 1310 897 1310 676 1310 497 1131 497 910 497 689 676 511 897 511 1117 511 1296 689 1296 910{\\p0}",
    -- Triangle
    "{\\c&H691F69&\\p6}m 762 1113 l 762 708 b 881 776 1000 843 1119 911 1000 978 881 1046 762 1113{\\p0}",
}

local santa_hat_lines = {
    -- Pompoms
    "{\\c&HC0C0C0&\\p6}m 500 -323 b 491 -322 481 -318 475 -311 465 -312 456 -319 446 -318 434 -314 427 -304 417 -297 410 -290 404 -282 395 -278 390 -274 387 -267 381 -265 377 -261 379 -254 384 -253 397 -244 409 -232 425 -228 437 -228 446 -218 457 -217 462 -216 466 -213 468 -209 471 -205 477 -203 482 -206 491 -211 499 -217 508 -222 532 -235 556 -249 576 -267 584 -272 584 -284 578 -290 569 -305 550 -312 533 -309 523 -310 515 -316 507 -321 505 -323 503 -323 500 -323{\\p0}",
    "{\\c&HE0E0E0&\\p6}m 315 -260 b 286 -258 259 -240 246 -215 235 -210 222 -215 211 -211 204 -188 177 -176 172 -151 170 -139 163 -128 154 -121 143 -103 141 -81 143 -60 139 -46 125 -34 129 -17 132 -1 134 16 142 30 145 56 161 80 181 96 196 114 210 133 231 144 266 153 303 138 328 115 373 79 401 28 423 -24 446 -73 465 -123 483 -174 487 -199 467 -225 442 -227 421 -232 402 -242 384 -254 364 -259 342 -250 322 -260 320 -260 317 -261 315 -260{\\p0}",
    -- Main cap
    "{\\c&H0000F0&\\p6}m 1151 -523 b 1016 -516 891 -458 769 -406 693 -369 624 -319 561 -262 526 -252 465 -235 479 -187 502 -147 551 -135 588 -111 1115 165 1379 232 1909 761 1926 800 1952 834 1987 858 2020 883 2053 912 2065 952 2088 1000 2146 962 2139 919 2162 836 2156 747 2143 662 2131 615 2116 567 2122 517 2120 410 2090 306 2089 199 2092 147 2071 99 2034 64 1987 5 1928 -41 1869 -86 1777 -157 1712 -256 1629 -337 1578 -389 1521 -436 1461 -476 1407 -509 1343 -507 1284 -515 1240 -519 1195 -521 1151 -523{\\p0}",
    -- Cap shadow
    "{\\c&H0000AA&\\p6}m 1657 248 b 1658 254 1659 261 1660 267 1669 276 1680 284 1689 293 1695 302 1700 311 1707 320 1716 325 1726 330 1735 335 1744 347 1752 360 1761 371 1753 352 1754 331 1753 311 1751 237 1751 163 1751 90 1752 64 1752 37 1767 14 1778 -3 1785 -24 1786 -45 1786 -60 1786 -77 1774 -87 1760 -96 1750 -78 1751 -65 1748 -37 1750 -8 1750 20 1734 78 1715 134 1699 192 1694 211 1689 231 1676 246 1671 251 1661 255 1657 248 m 1909 541 b 1914 542 1922 549 1917 539 1919 520 1921 502 1919 483 1918 458 1917 433 1915 407 1930 373 1942 338 1947 301 1952 270 1954 238 1951 207 1946 214 1947 229 1945 239 1939 278 1936 318 1924 356 1923 362 1913 382 1912 364 1906 301 1904 237 1891 175 1887 150 1892 126 1892 101 1892 68 1893 35 1888 2 1884 -9 1871 -20 1859 -14 1851 -6 1854 9 1854 20 1855 58 1864 95 1873 132 1883 179 1894 225 1899 273 1908 362 1910 451 1909 541{\\p0}",
    -- Brim and tip pompom
    "{\\c&HF8F8F8&\\p6}m 626 -191 b 565 -155 486 -196 428 -151 387 -115 327 -101 304 -47 273 2 267 59 249 113 219 157 217 213 215 265 217 309 260 302 285 283 373 264 465 264 555 257 608 252 655 292 709 287 759 294 816 276 863 298 903 340 972 324 1012 367 1061 394 1125 382 1167 424 1213 462 1268 482 1322 506 1385 546 1427 610 1479 662 1510 690 1534 725 1566 752 1611 796 1664 830 1703 880 1740 918 1747 986 1805 1005 1863 991 1897 932 1916 880 1914 823 1945 777 1961 725 1979 673 1957 622 1938 575 1912 534 1862 515 1836 473 1790 417 1755 351 1697 305 1658 266 1633 216 1593 176 1574 138 1539 116 1497 110 1448 101 1402 77 1371 37 1346 -16 1295 15 1254 6 1211 -27 1170 -62 1121 -86 1072 -104 1027 -128 976 -133 914 -130 851 -137 794 -162 740 -181 679 -168 626 -191 m 2051 917 b 1971 932 1929 1017 1919 1091 1912 1149 1923 1214 1970 1254 2000 1279 2027 1314 2066 1325 2139 1338 2212 1295 2254 1238 2281 1203 2287 1158 2282 1116 2292 1061 2273 1006 2229 970 2206 941 2167 938 2138 918{\\p0}",
}

-- called by mpv on every frame
function tick()
    if (not state.enabled) then return end

    if (state.idle) then
	   
        -- render idle message
        msg.trace('idle message')
        local _, _, display_aspect = mp.get_osd_size()
        local display_h = 360
        local display_w = display_h * display_aspect
        -- logo is rendered at 2^(6-1) = 32 times resolution with size 1800x1800
        local icon_x, icon_y = (display_w - 1800 / 32) / 2, 140
        local line_prefix = ('{\\rDefault\\an7\\1a&H00&\\bord0\\shad0\\pos(%f,%f)}'):format(icon_x, icon_y)

        local ass = assdraw.ass_new()
        -- mpv logo
        if user_opts.idlescreen then
            for i, line in ipairs(logo_lines) do
                ass:new_event()
                ass:append(line_prefix .. line)
            end
        end

        -- Santa hat
        if is_december and user_opts.idlescreen and not user_opts.greenandgrumpy then
            for i, line in ipairs(santa_hat_lines) do
                ass:new_event()
                ass:append(line_prefix .. line)
            end
        end
   
        if user_opts.idlescreen then
            ass:new_event()
            ass:pos(display_w / 2, icon_y + 65)
            ass:an(8)
            ass:append(texts.welcome)
        end
        set_osd(display_w, display_h, ass.text)

        if state.showhide_enabled then
            mp.disable_key_bindings('showhide')
            mp.disable_key_bindings('showhide_wc')
            state.showhide_enabled = false
        end


    elseif (state.fullscreen and user_opts.showfullscreen)
        or (not state.fullscreen and user_opts.showwindowed) then

        -- render the OSC
        render()
    else
        -- Flush OSD
        set_osd(osc_param.playresy, osc_param.playresy, '')
    end

    state.tick_last_time = mp.get_time()

    if state.anitype ~= nil then
        -- state.anistart can be nil - animation should now start, or it can
        -- be a timestamp when it started. state.idle has no animation.
        if not state.idle and
           (not state.anistart or
            mp.get_time() < 1 + state.anistart + user_opts.fadeduration/1000)
        then
            -- animating or starting, or still within 1s past the deadline
            request_tick()
        else
            state.anitype = nil
            state.anistart = nil
            state.animation = nil
        end
    end
end

function do_enable_keybindings()
    if state.enabled then
        if not state.showhide_enabled then
            mp.enable_key_bindings('showhide', 'allow-vo-dragging+allow-hide-cursor')
            mp.enable_key_bindings('showhide_wc', 'allow-vo-dragging+allow-hide-cursor')
        end
        state.showhide_enabled = true
    end
end

function enable_osc(enable)
    state.enabled = enable
    if enable then
        do_enable_keybindings()
    else
        hide_osc() -- acts immediately when state.enabled == false
        if state.showhide_enabled then
            mp.disable_key_bindings('showhide')
            mp.disable_key_bindings('showhide_wc')
        end
        state.showhide_enabled = false
    end
end

-- duration is observed for the sole purpose of updating chapter markers
-- positions. live streams with chapters are very rare, and the update is also
-- expensive (with request_init), so it's only observed when we have chapters
-- and the user didn't disable the livemarkers option (update_duration_watch).
function on_duration() request_init() end

local duration_watched = false
function update_duration_watch()
    local want_watch = user_opts.livemarkers and
                       (mp.get_property_number("chapters", 0) or 0) > 0 and
                       true or false  -- ensure it's a boolean

    if (want_watch ~= duration_watched) then
        if want_watch then
            mp.observe_property("duration", nil, on_duration)
        else
            mp.unobserve_property(on_duration)
        end
        duration_watched = want_watch
    end
end

validate_user_opts()
update_duration_watch()

mp.register_event('shutdown', shutdown)
mp.register_event('start-file', request_init)
mp.observe_property('track-list', nil, request_init)
mp.observe_property('playlist', nil, request_init)
mp.observe_property('playlist-count', nil, request_init)
mp.observe_property('playlist-pos', nil, request_init)
mp.observe_property("chapter-list", "native", function(_, list)
    list = list or {}  -- safety, shouldn't return nil
    pcall(function()
        table.sort(list, function(a, b)
            local ta = (a and type(a) == 'table' and a.time) or 0
            local tb = (b and type(b) == 'table' and b.time) or 0
            return ta < tb
        end)
    end)
    state.chapter_list = list
    update_duration_watch()
    request_init()
end)

mp.register_script_message('osc-message', show_message)
mp.register_script_message('osc-chapterlist', function(dur)
    show_message(get_chapterlist(), dur)
end)
mp.register_script_message('osc-playlist', function(dur)
    show_message(get_playlist(), dur)
end)
mp.register_script_message('osc-tracklist', function(dur)
    local msg = {}
    for k,v in pairs(nicetypes) do
        table.insert(msg, get_tracklist(k))
    end
    show_message(table.concat(msg, '\n\n'), dur)
end)

mp.register_script_message('show_osc', show_osc)
mp.register_script_message('hide_osc', hide_osc)

mp.observe_property('fullscreen', 'bool',
    function(name, val)
        state.fullscreen = val
        request_init_resize()
    end
)
mp.observe_property('mute', 'bool',
    function(name, val)
        state.mute = val
    end
)
mp.observe_property('border', 'bool',
    function(name, val)
        state.border = val
        request_init_resize()
    end
)
mp.observe_property('window-maximized', 'bool',
    function(name, val)
        state.maximized = val
        request_init_resize()
    end
)
mp.observe_property('idle-active', 'bool',
    function(name, val)
        state.idle = val
        request_tick()
    end
)
mp.observe_property('pause', 'bool', pause_state)
mp.observe_property('demuxer-cache-state', 'native', cache_state)
mp.observe_property('vo-configured', 'bool', function(name, val)
    request_tick()
end)
local last_playback_t = nil
mp.observe_property('playback-time', 'number', function(name, val)
    if val and last_playback_t then
        local delta = math.abs(val - last_playback_t)
        -- Normal playback progress delta is ~0.02-0.25s. A seek jump is > 0.8s
        if delta > 0.8 then
            show_osc()
        end
    end
    last_playback_t = val
    request_tick()
end)

mp.observe_property('seeking', 'bool', function(_, seeking)
    if seeking then
        show_osc()
    end
end)
mp.observe_property('osd-dimensions', 'native', function(name, val)
    -- (we could use the value instead of re-querying it all the time, but then
    --  we might have to worry about property update ordering)
    request_init_resize()
end)

-- mouse show/hide bindings
mp.set_key_bindings({
    {'mouse_move',              function(e) process_event('mouse_move', nil) end},
    {'mouse_leave',             mouse_leave},
}, 'showhide', 'force')
mp.set_key_bindings({
    {'mouse_move',              function(e) process_event('mouse_move', nil) end},
    {'mouse_leave',             mouse_leave},
}, 'showhide_wc', 'force')
do_enable_keybindings()

--mouse input bindings
mp.set_key_bindings({
    {"mbtn_left",           function(e) process_event("mbtn_left", "up") end,
                            function(e) process_event("mbtn_left", "down")  end},
    {"shift+mbtn_left",     function(e) process_event("shift+mbtn_left", "up") end,
                            function(e) process_event("shift+mbtn_left", "down")  end},
    {"mbtn_right",          function(e) process_event("mbtn_right", "up") end,
                            function(e) process_event("mbtn_right", "down")  end},
    -- alias to shift_mbtn_left for single-handed mouse use
    {"mbtn_mid",            function(e) process_event("shift+mbtn_left", "up") end,
                            function(e) process_event("shift+mbtn_left", "down")  end},
    {"wheel_up",            function(e) process_event("wheel_up", "press") end},
    {"wheel_down",          function(e) process_event("wheel_down", "press") end},
    {"mbtn_left_dbl",       "ignore"},
    {"shift+mbtn_left_dbl", "ignore"},
    {"mbtn_right_dbl",      "ignore"},
}, "input", "force")
mp.enable_key_bindings('input')

mp.set_key_bindings({
    {'mbtn_left',           function(e) process_event('mbtn_left', 'up') end,
                            function(e) process_event('mbtn_left', 'down')  end},
}, 'window-controls', 'force')
mp.enable_key_bindings('window-controls')

function get_hidetimeout()
    if user_opts.visibility == 'always' then
        return -1 -- disable autohide
    end
    return user_opts.hidetimeout
end

function always_on(val)
    if state.enabled then
        if val then
            show_osc()
        else
            hide_osc()
        end
    end
end

-- mode can be auto/always/never/cycle
-- the modes only affect internal variables and not stored on its own.
function visibility_mode(mode, no_osd)
    if mode == "cycle" then
        if not state.enabled then
            mode = "auto"
        elseif user_opts.visibility ~= "always" then
            mode = "always"
        else
            mode = "never"
        end
    end

    if mode == 'auto' then
        always_on(false)
        enable_osc(true)
    elseif mode == 'always' then
        enable_osc(true)
        always_on(true)
    elseif mode == 'never' then
        enable_osc(false)
    else
        msg.warn('Ignoring unknown visibility mode \"' .. mode .. '\"')
        return
    end

    user_opts.visibility = mode
    mp.set_property_native("user-data/osc/visibility", user_opts.visibility)

    if not no_osd and tonumber(mp.get_property('osd-level')) >= 1 then
        mp.osd_message('OSC visibility: ' .. mode)
    end

    -- Reset the input state on a mode change. The input state will be
    -- recalcuated on the next render cycle, except in 'never' mode where it
    -- will just stay disabled.
    mp.disable_key_bindings('input')
    mp.disable_key_bindings('window-controls')
    state.input_enabled = false
    request_tick()
end


-- KeyboardControl
--

local osc_key_bindings = {}

function osc_kb_control_up()
    visibility_mode('always', true)
    local keyboard_controls = build_keyboard_controls()
    local rows = {}
    local active_row_index = 0
    local active_row_name = nil

    local row_index = -1
    for row_name, row_controls in pairs(keyboard_controls) do
        row_index = row_index + 1
        rows[row_index] = row_name
        for i, control in pairs(row_controls) do
            if control == state.highlight_element then
                active_row_index = row_index
                active_row_name = row_name
            end
        end
    end

    if active_row_index - 1 < 0 then
        return
    end

    local next_row_index = active_row_index - 1

    local new_active_row_name = rows[next_row_index]
    local new_active_row = keyboard_controls[new_active_row_name]

    for i, control in pairs(new_active_row) do
        state.highlight_element = control
        return
    end
end

function osc_kb_control_down()
    visibility_mode('always', true)
    local keyboard_controls = build_keyboard_controls()
    local rows = {}
    local active_row_index = 0
    local active_row_name = nil

    local row_index = -1
    for row_name, row_controls in pairs(keyboard_controls) do
        row_index = row_index + 1
        rows[row_index] = row_name
        for i, control in pairs(row_controls) do
            if control == state.highlight_element then
                active_row_index = row_index
                active_row_name = row_name
            end
        end
    end

    if active_row_index + 1 > #rows then
        return
    end

    local next_row_index = active_row_index + 1

    local new_active_row_name = rows[next_row_index]
    local new_active_row = keyboard_controls[new_active_row_name]

    for i, control in pairs(new_active_row) do
        state.highlight_element = control
        return
    end

end

function osc_kb_control_left()
    visibility_mode('always', true)
    local keyboard_controls = build_keyboard_controls()
    
    local active_control_name = nil
    for row_name, row_controls in pairs(keyboard_controls) do
        local controls = {}
        local controls_index = -1
        for i, control in pairs(row_controls) do
            controls_index = controls_index + 1
            controls[controls_index] = control
            if control == state.highlight_element then
                active_control_index = controls_index
                active_control_name = control
            end
        end

        if active_control_name == 'seekbar' then
            mp.commandv('seek', -5, 'exact', 'keyframes')
            return
        end

        if active_control_name then
            if active_control_index - 1 < 0 then
                return
            end
        
            local next_control_index = active_control_index - 1
            state.highlight_element = controls[next_control_index]
            return
        end
    end

end

function osc_kb_control_right()
    visibility_mode('always', true)
    local keyboard_controls = build_keyboard_controls()
    
    local active_control_name = nil
    for row_name, row_controls in pairs(keyboard_controls) do
        local controls = {}
        local controls_index = -1
        for i, control in pairs(row_controls) do
            controls_index = controls_index + 1
            controls[controls_index] = control
            if control == state.highlight_element then
                active_control_index = controls_index
                active_control_name = control
            end
        end

        if active_control_name == 'seekbar' then
            mp.commandv('seek', 5, 'exact', 'keyframes')
            return
        end

        if active_control_name then
            if active_control_index + 1 > #controls then
                return
            end
        
            local next_control_index = active_control_index + 1
            state.highlight_element = controls[next_control_index]
            return
        end
    end

end

function osc_kb_control_back()
    visibility_mode('auto', true)
end

function osc_kb_control_enter()
    visibility_mode('always', true)
    for n = 1, #elements do
        if elements[n].name == state.highlight_element then
            
            local action = 'enter'
            if element_has_action(elements[n], action) then
                elements[n].eventresponder[action](elements[n])
                return
            end

            local action = 'mbtn_left_up'
            if element_has_action(elements[n], action) then
                elements[n].eventresponder[action](elements[n])
                return
            end
        end
    end

end

function osc_add_key_binding(key, name, fn, flags)
	osc_key_bindings[#osc_key_bindings + 1] = name
	mp.add_forced_key_binding(key, name, fn, flags)
end

-- This is based on code from https://github.com/darsain/uosc
function osc_enable_key_bindings()
	osc_key_bindings = {}
	-- The `mp.set_key_bindings()` method would be easier here, but that
	-- doesn't support 'repeatable' flag, so we are stuck with this monster.
	osc_add_key_binding('up',              'osc-kb-control-prev1',        osc_kb_control_up, 'repeatable')
	osc_add_key_binding('down',            'osc-kb-control-next1',        osc_kb_control_down, 'repeatable')
	osc_add_key_binding('left',            'osc-kb-control-left1',        osc_kb_control_left, 'repeatable')
	osc_add_key_binding('right',           'osc-kb-control-right1',      osc_kb_control_right, 'repeatable')
	osc_add_key_binding('enter',      'osc-kb-control-select-alt3', osc_kb_control_enter, 'repeatable')
	osc_add_key_binding('esc',        'osc-kb-control-close',       osc_kb_control_back, 'repeatable')
end

function osc_disable_key_bindings()
	for _, name in ipairs(osc_key_bindings) do mp.remove_key_binding(name) end
	osc_key_bindings = {}
end



visibility_mode(user_opts.visibility, true)
mp.register_script_message('osc-visibility', visibility_mode)
mp.add_key_binding(nil, 'visibility', function() visibility_mode('cycle') end)

mp.register_script_message("thumbfast-info", function(json)
    local data = utils.parse_json(json)
    if type(data) ~= "table" or not data.width or not data.height then
        msg.error("thumbfast-info: received json didn't produce a table with thumbnail information")
    else
        osc_state.set_thumbfast(data)
    end
end)

set_virt_mouse_area(0, 0, 0, 0, 'input')
set_virt_mouse_area(0, 0, 0, 0, 'window-controls')

-- Script messages & bindings for menus
mp.register_script_message('menu-open', function(mtype)
    if state.menu_active == mtype then
        menu_close()
    else
        menu_open(mtype)
    end
end)
mp.add_key_binding(nil, 'menu-playlist', function()
    if state.menu_active == 'playlist' then menu_close() else menu_open('playlist') end
end)
mp.add_key_binding(nil, 'menu-chapters', function()
    if state.menu_active == 'chapters' then menu_close() else menu_open('chapters') end
end)
mp.add_key_binding(nil, 'menu-audio', function()
    if state.menu_active == 'audio' then menu_close() else menu_open('audio') end
end)
mp.add_key_binding(nil, 'menu-sub', function()
    if state.menu_active == 'sub' then menu_close() else menu_open('sub') end
end)
mp.add_key_binding(nil, 'menu-video', function()
    if state.menu_active == 'video' then menu_close() else menu_open('video') end
end)
mp.add_key_binding(nil, 'menu-tags', function()
    if state.menu_active == 'tags' then menu_close() else menu_open('tags') end
end)
mp.add_key_binding('T', 'toggle-tags-menu', function()
    if state.menu_active == 'tags' then menu_close() else menu_open('tags') end
end)
mp.add_key_binding('Ctrl+t', 'toggle-tags-menu-ctrl', function()
    if state.menu_active == 'tags' then menu_close() else menu_open('tags') end
end)


function M.init(ctx)
    ctx_ref = ctx
end

function M.get_user_opts()
    return user_opts
end

function M.get_state()
    return state
end

function M.get_osc_param()
    return osc_param
end

function M.get_tracks_osc()
    return tracks_osc
end

function M.get_icons()
    return icons
end

function M.get_track(type)
    return get_track(type)
end

function M.get_virt_mouse_pos()
    return get_virt_mouse_pos()
end

function M.hide_osc()
    hide_osc()
end

function M.show_osc()
    show_osc()
end

function M.request_tick()
    request_tick()
end

function M.request_init()
    request_init_resize()
end

return M
