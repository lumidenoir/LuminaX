-- ============================================================================
-- ModernH Module: OSC
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

local assdraw = require 'mp.assdraw'
local msg = require 'mp.msg'
local opt = require 'mp.options'
local utils = require 'mp.utils'

--
-- Parameters
--
-- default user option values
-- may change them in osc.conf
local user_opts = {
    showwindowed = true,        -- show OSC when windowed?
    showfullscreen = true,      -- show OSC when fullscreen?
    idlescreen = true,          -- draw logo and text when idle
    scalewindowed = 1.0,        -- scaling of the controller when windowed
    scalefullscreen = 1.0,      -- scaling of the controller when fullscreen
    scaleforcedwindow = 2.0,    -- scaling when rendered on a forced window
    vidscale = true,            -- scale the controller with the video?
    hidetimeout = 1500,         -- duration in ms until the OSC hides if no
                                -- mouse movement. enforced non-negative for the
                                -- user, but internally negative is 'always-on'.
    fadeduration = 250,         -- duration of fade out in ms, 0 = no fade
    minmousemove = 1,           -- minimum amount of pixels the mouse has to
                                -- move between ticks to make the OSC show up
    iamaprogrammer = false,     -- use native mpv values and disable OSC
                                -- internal track list management (and some
                                -- functions that depend on it)
    font = 'Inter',	-- default osc font
    seekbarhandlesize = 0.6,	-- size ratio of the slider handle, range 0 ~ 1
    seekrange = true,		-- show seekrange overlay
    seekrangealpha = 64,      	-- transparency of seekranges
    seekbarkeyframes = true,    -- use keyframes when dragging the seekbar
    showjump = true,            -- show "jump forward/backward 5 seconds" buttons 
                                -- shift+left-click to step 1 frame and 
                                -- right-click to jump 1 minute
    jumpamount = 5,             -- change the jump amount (in seconds by default)
    jumpiconnumber = true,      -- show different icon when jumpamount is 5, 10, or 30
    jumpmode = 'exact',         -- seek mode for jump buttons. e.g.
                                -- 'exact', 'relative+keyframes', etc.
  title = '${filename/no-ext}',   -- string compatible with property-expansion
                                -- to be shown as OSC title
    showtitle = true,		-- show title in OSC
    showonpause = true,         -- whether to disable the hide timeout on pause
    timetotal = true,          	-- display total time instead of remaining time?
    timems = false,             -- Display time down to millliseconds by default
    visibility = 'auto',        -- only used at init to set visibility_mode(...)
    windowcontrols = 'auto',    -- whether to show window controls
    greenandgrumpy = false,     -- disable santa hat
    language = 'eng',		-- eng=English, chs=Chinese
    volumecontrol = true,       -- whether to show mute button and volume slider
    volume_slider_mode = 'hover', -- volume slider appearance: 'hover' (default), 'always', 'never'
    keyboardnavigation = false, -- enable directional keyboard navigation
    chapter_fmt = 'Chapter: %s',-- format for chapter name display on seekbar
    -- Adaptive Scaling Bounds
    min_scale = 0.70,           -- minimum adaptive scale factor (default 0.70)
    max_scale = 1.05,           -- maximum adaptive scale factor (default 1.05)
    -- TMDB Pause Screensaver
    tmdb_api_key = '',          -- TMDB v3 API key (free at themoviedb.org)
    screensaver_enabled = true, -- dim overlay + metadata card on pause
    screensaver_delay = 3,      -- seconds of pause before screensaver activates
    screensaver_align = 'center', -- screensaver alignment: 'center' (Apple TV cinema centered), 'split' (symmetrical 2-column)
    logo_engine = 'auto',       -- logo processing engine: 'auto' (native ffmpeg with fallback), 'ffmpeg' (pure native ffmpeg), 'text' (bypass logo engine, show title text)
    screensaver_film_font = 'NewYork', -- font face for title when no logo is used (or logo_engine=text)
    tmdb_cache_lookup = true,   -- whether to use disk/memory cache for tmdb data and logos
    tmdb_cache_max_mb = 250,    -- maximum cache storage size in MB
    screensaver_anti_burnin = false, -- anti-burn-in micro-drift on pause
    check_updates = true,       -- auto check for LuminaX updates in background
    check_update_interval_days = 3, -- check frequency in days
    sub_auto_anime_preset = true, -- automatically switch to Anime Fansub subtitle preset when TMDB genre is Animation
}

-- Icons for jump button depending on jumpamount (Material Icons Round)
local jumpicons = { 
    [5] = {'\238\129\155', '\238\129\152'}, -- replay_5, forward_5
    [10] = {'\238\129\153', '\238\129\150'}, -- replay_10, forward_10
    [30] = {'\238\129\154', '\238\129\151'}, -- replay_30, forward_30
    default = {'\238\129\130', '\238\129\130'}, -- replay
} 

local icons = {
  previous = '\238\129\133',     -- skip_previous
  next = '\238\129\132',         -- skip_next
  play = '\238\128\183',         -- play_arrow
  pause = '\238\128\180',        -- pause
  backward = '\238\128\160',     -- fast_rewind
  forward = '\238\128\159',      -- fast_forward
  audio = '\238\142\161',        -- audiotrack
  volume = '\238\129\144',       -- volume_up
  volume_mute = '\238\129\143',  -- volume_off
  sub = '\238\129\136',          -- subtitles
  video = '\238\136\168',        -- tune (video picture tuning)
  minimize = '\238\151\145',     -- fullscreen_exit
  fullscreen = '\238\151\144',   -- fullscreen
  info = '\238\162\142',         -- info
  playlist = '\238\129\159',     -- playlist_play
  chapters = '\238\137\130',     -- format_list_bulleted
  tags = '\238\149\142',         -- local_offer / tag
  update = '\238\164\163',       -- Material Icons Round: update (0xE923: circular arrow with clock hands)
  pip = '\238\164\145',          -- picture_in_picture_alt
}

-- Localization
local language = {
	['eng'] = {
	    welcome = '{\\fs24\\1c&H0&\\1c&HFFFFFF&}Drop files or URLs to play here.',  -- this text appears when mpv starts
		off = 'OFF',
		na = 'n/a',
		none = 'none',
		video = 'Video',
		audio = 'Audio',
		subtitle = 'Subtitle',
		available = 'Available ',
		track = ' Tracks:',
		playlist = 'Playlist',
		nolist = 'Empty playlist.',
		chapter = 'Chapter',
		nochapter = 'No chapters.',
	},
	['chs'] = {
		welcome = '{\\1c&H00\\bord0\\fs30\\fn微软雅黑 light\\fscx125}MPV{\\fscx100} 播放器',  -- this text appears when mpv starts
		off = '关闭',
		na = 'n/a',
		none = '无',
		video = '视频',
		audio = '音频',
		subtitle = '字幕',
		available = '可选',
		track = '：',
		playlist = '播放列表',
		nolist = '无列表信息',
		chapter = '章节',
		nochapter = '无章节信息',
	},
	['pl'] = {
	    welcome = '{\\fs24\\1c&H0&\\1c&HFFFFFF&}Upuść plik lub łącze URL do odtworzenia.',  -- this text appears when mpv starts
		off = 'WYŁ.',
		na = 'n/a',
		none = 'nic',
		video = 'Wideo',
		audio = 'Ścieżka audio',
		subtitle = 'Napisy',
		available = 'Dostępne ',
		track = ' Ścieżki:',
		playlist = 'Lista odtwarzania',
		nolist = 'Lista odtwarzania pusta.',
		chapter = 'Rozdział',
		nochapter = 'Brak rozdziałów.',
	}
}
-- read options from config and command-line (supports both osc.conf and luminax.conf)
opt.read_options(user_opts, 'osc', function(list) update_options(list) end)
opt.read_options(user_opts, 'luminax', function(list) update_options(list) end)
-- apply lang opts
local texts = language[user_opts.language]
local osc_param = { -- calculated by osc_init()
    playresy = 0,                           -- canvas size Y
    playresx = 0,                           -- canvas size X
    display_aspect = 1,
    unscaled_y = 0,
    areas = {},
}

local osc_styles = {
    TransBg = '{\\blur70\\bord90\\1c&H161618&\\3c&H161618&}',
    SeekbarBg = '{\\blur0\\bord0\\1c&H3A3A3C&}',
    SeekbarFg = '{\\blur0\\bord0\\1c&HFFFFFF&}',
    VolumebarBg = '{\\blur0\\bord0\\1c&H3A3A3C&}',
    VolumebarFg = '{\\blur0\\bord0\\1c&HFFFFFF&}',
    -- Hero play/pause: large, pure white (Material Icons Round)
    Ctrl1 = '{\\blur0\\bord0\\1c&HFFFFFF&\\3c&H161618&\\fs44\\fnMaterial Icons Round}',
    -- Secondary skip/prev/next icons: slightly smaller, slightly dimmed
    Ctrl2 = '{\\blur0\\bord0\\1c&HFFFFFF&\\3c&H161618&\\fs26\\fnMaterial Icons Round}',
    Ctrl2Flip = '{\\blur0\\bord0\\1c&HFFFFFF&\\3c&HFFFFFF&\\fs22\\fnMaterial Icons Round\\fry180}',
    -- Tertiary utility icons: visually quieter iOS-gray-3
    Ctrl3 = '{\\blur0\\bord0\\1c&HC7C7CC&\\3c&H161618&\\fs22\\fnMaterial Icons Round}',
    -- Time: clean white, medium weight, generous tracking
    Time = '{\\blur0\\bord0\\1c&HFFFFFF&\\3c&H000000&\\fs12\\b400\\fsp0.8\\fn' .. user_opts.font .. '}',
    -- Tooltip: bold white with subtle dark halo for legibility
    Tooltip = '{\\blur0\\bord0.8\\1c&HFFFFFF&\\3c&H101014&\\fs12\\b700\\fn' .. user_opts.font .. '}',
    -- Title: semi-bold, slightly smaller — let the video breathe
    Title = '{\\blur0\\bord0.5\\1c&HFFFFFF&\\3c&H101014&\\fs19\\b600\\fsp0.1\\q2\\fn' .. user_opts.font .. '}',
    WinCtrl = '{\\blur1\\bord0.5\\1c&HFFFFFF&\\3c&H0\\fs16\\fnmpv-osd-symbols}',
    ThumbnailBorder = '{\\blur0\\bord0\\1c&H000000&}',
    elementDown = '{\\1c&H8E8E93&}',
    elementHighlight = '{\\blur2\\bord0\\1c&HFFFFFF&}',
}

-- Element list (file-scoped forward declaration so mouse_hit and all handlers can access it)
local elements = {}

-- internal states, do not touch
local state = {
    showtime,                               -- time of last invocation (last mouse move)
    osc_visible = false,
    anistart,                               -- time when the animation started
    anitype,                                -- current type of animation
    animation,                              -- current animation alpha
    mouse_down_counter = 0,                 -- used for softrepeat
    active_element = nil,                   -- nil = none, 0 = background, 1+ = see elements[]
    active_event_source = nil,              -- the 'button' that issued the current event
    rightTC_trem = not user_opts.timetotal, -- if the right timecode should display total or remaining time
    mp_screen_sizeX, mp_screen_sizeY,       -- last screen-resolution, to detect resolution changes to issue reINITs
    initREQ = false,                        -- is a re-init request pending?
    last_mouseX, last_mouseY,               -- last mouse position, to detect significant mouse movement
    mouse_in_window = false,
    seekbar_anim = 0.0,
    seekbar_last_t = nil,
    vol_anim = 0.0,
    vol_last_t = nil,
    message_text,
    message_hide_timer,
    fullscreen = false,
    tick_timer = nil,
    tick_last_time = 0,                     -- when the last tick() was run
    hide_timer = nil,
    cache_state = nil,
    idle = false,
    enabled = true,
    input_enabled = true,
    showhide_enabled = false,
    dmx_cache = 0,
    border = true,
    maximized = false,
    osd = mp.create_osd_overlay('ass-events'),
    mute = false,
    lastvisibility = user_opts.visibility,	-- save last visibility on pause if showonpause
    fulltime = user_opts.timems,
    highlight_element = 'cy_audio',
    chapter_list = {},                      -- sorted by time
    -- overlay menu state
    menu_active = nil,      -- 'playlist', 'audio', 'sub', or nil
    menu_selected = 1,      -- currently highlighted item index
    menu_scroll = 0,        -- scroll offset
}

local activate_screensaver -- forward declaration
local ss_delay_timer      -- forward declaration

local thumbfast = {
    width = 0,
    height = 0,
    disabled = true,
    available = false
}

-- Menu fade animation
local menu_alpha   = 0     -- 0=invisible, 255=fully visible
local menu_closing = false -- true while fading out
local menu_bar_anim_y  = nil
local menu_bar_last_t  = nil

-- Menu focus bar animation state
local menu_bar_anim_y = nil   -- current animated y position (nil = not initialised)
local menu_bar_last_t = nil   -- last tick time for lerp

local window_control_box_width = 138
local tick_delay = 0.03

local is_december = os.date("*t").month == 12

--- Automatically disable OSC
local builtin_osc_enabled = mp.get_property_native('osc')
if builtin_osc_enabled then
    mp.set_property_native('osc', false)
end

--


-- WindowControl helpers
function window_controls_enabled()
    local val = user_opts.windowcontrols
    if val == 'no' then
        return false
    elseif val == 'auto' then
        -- Never show top window controls in fullscreen mode
        if state.fullscreen then
            return false
        end
        return not state.border
    else
        return val == 'yes'
    end
end



function build_keyboard_controls()

    -- prepare the main button row
    local bottom_button_line = {}
    table.insert(bottom_button_line, 'cy_audio')
    table.insert(bottom_button_line, 'cy_sub')
    table.insert(bottom_button_line, 'tog_video')
    table.insert(bottom_button_line, 'pl_prev')
    table.insert(bottom_button_line, 'skipback')
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

    -- build up the main mapping object
    local mapping = {}
    if window_controls_enabled() then
        table.insert(mapping, {
            'minimize',
            'maximize',
            'close'
        })
    end
    table.insert(mapping, {
        'seekbar'
    })
    table.insert(mapping, bottom_button_line)

    return mapping
end


--
-- Helperfunctions
--

function set_osd(res_x, res_y, text)
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

-- scale factor for translating between real and virtual ASS coordinates
function get_virt_scale_factor()
    local w, h = mp.get_osd_size()
    if w <= 0 or h <= 0 then
        return 0, 0
    end
    return osc_param.playresx / w, osc_param.playresy / h
end

-- return mouse position in virtual ASS coordinates (playresx/y)
function get_virt_mouse_pos()
    local x, y = mp.get_mouse_pos()
    if state.mouse_in_window or (x and y and (x > 0 or y > 0)) then
        local sx, sy = get_virt_scale_factor()
        return x * sx, y * sy
    else
        return -1, -1
    end
end

function set_virt_mouse_area(x0, y0, x1, y1, name)
    local sx, sy = get_virt_scale_factor()
    mp.set_mouse_area(x0 / sx, y0 / sy, x1 / sx, y1 / sy, name)
end

function scale_value(x0, x1, y0, y1, val)
    local m = (y1 - y0) / (x1 - x0)
    local b = y0 - (m * x0)
    return (m * val) + b
end

-- returns hitbox spanning coordinates (top left, bottom right corner)
-- according to alignment
function get_hitbox_coords(x, y, an, w, h)

    local alignments = {
      [1] = function () return x, y-h, x+w, y end,
      [2] = function () return x-(w/2), y-h, x+(w/2), y end,
      [3] = function () return x-w, y-h, x, y end,

      [4] = function () return x, y-(h/2), x+w, y+(h/2) end,
      [5] = function () return x-(w/2), y-(h/2), x+(w/2), y+(h/2) end,
      [6] = function () return x-w, y-(h/2), x, y+(h/2) end,

      [7] = function () return x, y, x+w, y+h end,
      [8] = function () return x-(w/2), y, x+(w/2), y+h end,
      [9] = function () return x-w, y, x, y+h end,
    }

    return alignments[an]()
end

function get_hitbox_coords_geo(geometry)
    return get_hitbox_coords(geometry.x, geometry.y, geometry.an,
        geometry.w, geometry.h)
end

function get_element_hitbox(element)
    return element.hitbox.x1, element.hitbox.y1,
        element.hitbox.x2, element.hitbox.y2
end

function mouse_hit(element)
    if not element then return false end
    if (element.name == 'volumebar' or element.name == 'volumebarbg') then
        local vmode = user_opts.volume_slider_mode or 'hover'
        if vmode == 'never' then return false end
        local active_elem = (state.active_element and elements and elements[state.active_element]) or nil
        if vmode == 'hover' and (state.vol_anim or 0) < 0.35 and (active_elem ~= element) then
            return false
        end
    end
    return mouse_hit_coords(get_element_hitbox(element))
end

function mouse_hit_coords(bX1, bY1, bX2, bY2)
    local mX, mY = get_virt_mouse_pos()
    return (mX >= bX1 and mX <= bX2 and mY >= bY1 and mY <= bY2)
end

function limit_range(min, max, val)
    if val > max then
        val = max
    elseif val < min then
        val = min
    end
    return val
end

-- translate value into element coordinates
function get_slider_ele_pos_for(element, val)

    local ele_pos = scale_value(
        element.slider.min.value, element.slider.max.value,
        element.slider.min.ele_pos, element.slider.max.ele_pos,
        val)

    return limit_range(
        element.slider.min.ele_pos, element.slider.max.ele_pos,
        ele_pos)
end

-- translates global (mouse) coordinates to value
function get_slider_value_at(element, glob_pos)

    local val = scale_value(
        element.slider.min.glob_pos, element.slider.max.glob_pos,
        element.slider.min.value, element.slider.max.value,
        glob_pos)

    return limit_range(
        element.slider.min.value, element.slider.max.value,
        val)
end

-- get value at current mouse position
function get_slider_value(element)
    return get_slider_value_at(element, get_virt_mouse_pos())
end

function countone(val)
    if not (user_opts.iamaprogrammer) then
        val = val + 1
    end
    return val
end

-- multiplies two alpha values, formular can probably be improved
function mult_alpha(alphaA, alphaB)
    return 255 - (((1-(alphaA/255)) * (1-(alphaB/255))) * 255)
end

function add_area(name, x1, y1, x2, y2)
    -- create area if needed
    if (osc_param.areas[name] == nil) then
        osc_param.areas[name] = {}
    end
    table.insert(osc_param.areas[name], {x1=x1, y1=y1, x2=x2, y2=y2})
end

function ass_append_alpha(ass, alpha, modifier)
    local ar = {}

    for ai, av in pairs(alpha) do
        av = mult_alpha(av, modifier)
        if state.animation then
            av = mult_alpha(av, state.animation)
        end
        ar[ai] = av
    end

    ass:append(string.format('{\\1a&H%X&\\2a&H%X&\\3a&H%X&\\4a&H%X&}',
               ar[1], ar[2], ar[3], ar[4]))
end

function ass_draw_cir_cw(ass, x, y, r)
	ass:round_rect_cw(x-r, y-r, x+r, y+r, r)
end

function ass_draw_rr_h_cw(ass, x0, y0, x1, y1, r1, hexagon, r2)
    if hexagon then
        ass:hexagon_cw(x0, y0, x1, y1, r1, r2)
    else
        ass:round_rect_cw(x0, y0, x1, y1, r1, r2)
    end
end

function ass_draw_rr_h_ccw(ass, x0, y0, x1, y1, r1, hexagon, r2)
    if hexagon then
        ass:hexagon_ccw(x0, y0, x1, y1, r1, r2)
    else
        ass:round_rect_ccw(x0, y0, x1, y1, r1, r2)
    end
end


--
-- Tracklist Management
--

local nicetypes = {video = texts.video, audio = texts.audio, sub = texts.subtitle}

-- updates the OSC internal playlists, should be run each time the track-layout changes
function update_tracklist()
    local tracktable = mp.get_property_native('track-list', {})

    -- by osc_id
    tracks_osc = {}
    tracks_osc.video, tracks_osc.audio, tracks_osc.sub = {}, {}, {}
    -- by mpv_id
    tracks_mpv = {}
    tracks_mpv.video, tracks_mpv.audio, tracks_mpv.sub = {}, {}, {}
    for n = 1, #tracktable do
        if not (tracktable[n].type == 'unknown') then
            local type = tracktable[n].type
            local mpv_id = tonumber(tracktable[n].id)

            -- by osc_id
            table.insert(tracks_osc[type], tracktable[n])

            -- by mpv_id
            tracks_mpv[type][mpv_id] = tracktable[n]
            tracks_mpv[type][mpv_id].osc_id = #tracks_osc[type]
        end
    end
end

-- return a nice list of tracks of the given type (video, audio, sub)
function get_tracklist(type)
    local msg = texts.available .. nicetypes[type] .. texts.track
    if #tracks_osc[type] == 0 then
        msg = msg .. texts.none
    else
        for n = 1, #tracks_osc[type] do
            local track = tracks_osc[type][n]
            local lang, title, selected = 'unknown', '', '○'
            if not(track.lang == nil) then lang = track.lang end
            if not(track.title == nil) then title = track.title end
            if (track.id == tonumber(mp.get_property(type))) then
                selected = '●'
            end
            msg = msg..'\n'..selected..' '..n..': ['..lang..'] '..title
        end
    end
    return msg
end

-- relatively change the track of given <type> by <next> tracks
    --(+1 -> next, -1 -> previous)
function set_track(type, next)
    local current_track_mpv, current_track_osc
    if (mp.get_property(type) == 'no') then
        current_track_osc = 0
    else
        current_track_mpv = tonumber(mp.get_property(type))
        current_track_osc = tracks_mpv[type][current_track_mpv].osc_id
    end
    local new_track_osc = (current_track_osc + next) % (#tracks_osc[type] + 1)
    local new_track_mpv
    if new_track_osc == 0 then
        new_track_mpv = 'no'
    else
        new_track_mpv = tracks_osc[type][new_track_osc].id
    end

    mp.commandv('set', type, new_track_mpv)

--	if (new_track_osc == 0) then
--        show_message(nicetypes[type] .. ' Track: none')
--    else
--        show_message(nicetypes[type]  .. ' Track: '
--            .. new_track_osc .. '/' .. #tracks_osc[type]
--            .. ' ['.. (tracks_osc[type][new_track_osc].lang or 'unknown') ..'] '
--            .. (tracks_osc[type][new_track_osc].title or ''))
--    end
end

-- get the currently selected track of <type>, OSC-style counted
function get_track(type)
    local track = mp.get_property(type)
    if track ~= 'no' and track ~= nil then
        local tr = tracks_mpv[type][tonumber(track)]
        if tr then
            return tr.osc_id
        end
    end
    return 0
end

--
-- Media Badges Renderer (Delegated to unified modules.utils)
--
local function render_media_badges(elem_ass, elem_geo, alpha)
    local u = ctx_ref and ctx_ref.utils
    if not u or not u.collect_media_badges or not u.draw_badges_ltr then return end
    local badges = u.collect_media_badges(state)
    if #badges == 0 then return end
    local badge_h = 16
    local cy      = elem_geo.y + badge_h / 2  -- vertically centred on this row
    u.draw_badges_ltr(elem_ass, badges, elem_geo.x, cy, badge_h, alpha, state.animation)
end

--
-- Element Management
--

elements = {}

function prepare_elements()

    -- remove elements without layout or invisble
    local elements2 = {}
    for n, element in pairs(elements) do
        if not (element.layout == nil) and (element.visible) then
            table.insert(elements2, element)
        end
    end
    elements = elements2

    function elem_compare (a, b)
        return a.layout.layer < b.layout.layer
    end

    table.sort(elements, elem_compare)


    for _,element in pairs(elements) do
        if element.name then
            elements[element.name] = element
        end

        local elem_geo = element.layout.geometry

        -- Calculate the hitbox
        local bX1, bY1, bX2, bY2 = get_hitbox_coords_geo(elem_geo)
        element.hitbox = {x1 = bX1, y1 = bY1, x2 = bX2, y2 = bY2}

        local style_ass = assdraw.ass_new()

        -- prepare static elements
        style_ass:append('{}') -- hack to troll new_event into inserting a \n
        style_ass:new_event()
        style_ass:pos(elem_geo.x, elem_geo.y)
        style_ass:an(elem_geo.an)
        style_ass:append(element.layout.style or '')

        element.style_ass = style_ass

        local static_ass = assdraw.ass_new()


        if (element.type == 'box') then
            --draw box
            static_ass:draw_start()
            ass_draw_rr_h_cw(static_ass, 0, 0, elem_geo.w, elem_geo.h,
                             element.layout.box.radius, element.layout.box.hexagon)
            static_ass:draw_stop()

        elseif (element.type == 'slider') then
            --draw static slider parts
            local slider_lo = element.layout.slider
            -- calculate positions of min and max points
			element.slider.min.ele_pos = user_opts.seekbarhandlesize * elem_geo.h / 2
			element.slider.max.ele_pos = elem_geo.w - element.slider.min.ele_pos
            element.slider.min.glob_pos = element.hitbox.x1 + element.slider.min.ele_pos
            element.slider.max.glob_pos = element.hitbox.x1 + element.slider.max.ele_pos

            static_ass:draw_start()
			-- a hack which prepares the whole slider area to allow center placements such like an=5
			static_ass:rect_cw(0, 0, elem_geo.w, elem_geo.h)
			static_ass:rect_ccw(0, 0, elem_geo.w, elem_geo.h)
            -- marker nibbles (clean YouTube-style circular chapter dots)
            if not (element.slider.markerF == nil) then
                local markers = element.slider.markerF()
                for _,marker in pairs(markers) do
                    if (marker >= element.slider.min.value) and (marker <= element.slider.max.value) then
                        local s = get_slider_ele_pos_for(element, marker)
                        ass_draw_cir_cw(static_ass, s, elem_geo.h / 2, 2.5)
                    end
                end
            end
        end

        element.static_ass = static_ass

        -- if the element is supposed to be disabled,
        -- style it accordingly and kill the eventresponders (except dynamic playlist buttons)
        if not (element.enabled) then
            element.layout.alpha[1] = 136
            if name ~= 'pl_prev' and name ~= 'pl_next' then
                element.eventresponder = nil
            end
        end
        -- gray out the element if it is toggled off
        if (element.off) then
            element.layout.alpha[1] = 136
        end

    end
end

--
-- Element Rendering
--

-- returns nil or a chapter element from the native property chapter-list
function get_chapter(possec)
    if not possec then return nil end
    local cl = state.chapter_list or {}

    for n=#cl,1,-1 do
        if cl[n] and cl[n].time and possec >= cl[n].time then
            return cl[n]
        end
    end
end

function render_elements(master_ass)
    -- when the slider is dragged or hovered and we have a target chapter name
    -- then we use it instead of the normal title. we calculate it before the
    -- render iterations because the title may be rendered before the slider.
    state.forced_title = nil
    if thumbfast.disabled then
        local se, ae = state.slider_element, elements[state.active_element]
        if user_opts.chapter_fmt ~= "no" and se and (ae == se or (not ae and mouse_hit(se))) then
            local dur = mp.get_property_number("duration", 0)
            if dur and dur > 0 then
                local possec = get_slider_value(se) * dur / 100 -- of mouse pos
                local ch = get_chapter(possec)
                if ch and ch.title and ch.title ~= "" then
                    pcall(function()
                        state.forced_title = string.format(user_opts.chapter_fmt or 'Chapter: %s', ch.title)
                    end)
                end
            end
        end
    end

    local loop_seekbar_data = nil
    for n=1, #elements do
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
                ass_append_alpha(style_ass, element.layout.alpha, extra_a)
            else
                ass_append_alpha(style_ass, element.layout.alpha, 0)
            end

            if element.eventresponder and (state.active_element == n) then
                -- run render event functions
                if not (element.eventresponder.render == nil) then
                    element.eventresponder.render(element)
                end
                if mouse_hit(element) then
                    -- mouse down styling
                    if (element.styledown) then
                        style_ass:append(osc_styles.elementDown)
                    end
                    if (element.softrepeat) and (state.mouse_down_counter >= 15
                        and state.mouse_down_counter % 5 == 0) then

                        element.eventresponder[state.active_event_source..'_down'](element)
                    end
                    state.mouse_down_counter = state.mouse_down_counter + 1
                end
            end

            if user_opts.keyboardnavigation and state.highlight_element == element.name then
                style_ass:append(osc_styles.elementHighlight)
            end
            
            local elem_geo = element.layout.geometry
            local elem_ass = assdraw.ass_new()
            elem_ass:merge(style_ass)
            
            if (element.name == 'seekbarbg') then
                local anim = state.seekbar_anim or 0.0
                local bar_h = 3.0 + 4.0 * anim
                -- Centre the bar vertically inside the hitbox (same maths as the FG fill)
                local bg_gap = (elem_geo.h - bar_h) / 2
                elem_ass:draw_start()
                -- Anchor bounding box to [0, 0, w, h] so libass \an5 centers at elem_geo.y (same hack as slider)
                elem_ass:rect_cw(0, 0, elem_geo.w, elem_geo.h)
                elem_ass:rect_ccw(0, 0, elem_geo.w, elem_geo.h)
                elem_ass:round_rect_cw(0, bg_gap, elem_geo.w, elem_geo.h - bg_gap, bar_h / 2)
                elem_ass:draw_stop()
            elseif (element.name == 'volumebarbg') then
                local anim_w = (vmode == 'hover') and math.floor(elem_geo.w * (state.vol_anim or 1.0) + 0.5) or elem_geo.w
                elem_ass:draw_start()
                elem_ass:round_rect_cw(0, 0, anim_w, elem_geo.h, elem_geo.h / 2)
                elem_ass:draw_stop()
            elseif not (element.type == 'button') then
                elem_ass:merge(element.static_ass)
            end

            if (element.type == 'slider') then

                local slider_lo = element.layout.slider
                local elem_geo = element.layout.geometry
                local s_min = element.slider.min.value
                local s_max = element.slider.max.value
                local pos = element.slider.posF()

                if element.name == 'seekbar' then
                    local anim = state.seekbar_anim or 0.0
                    local bar_h = 3.0 + 4.0 * anim
                    local gap = (elem_geo.h - bar_h) / 2
                    local rh = (user_opts.seekbarhandlesize * elem_geo.h / 2) * (0.35 + 0.65 * anim)
                    local xp = pos and get_slider_ele_pos_for(element, pos) or nil

                    local loop_a = mp.get_property_number('ab-loop-a')
                    local loop_b = mp.get_property_number('ab-loop-b')
                    local dur = mp.get_property_number('duration', 0)
                    local has_loop = loop_a and dur and dur > 0 and loop_a >= 0

                    if not has_loop then
                        if xp then
                            ass_draw_cir_cw(elem_ass, xp, elem_geo.h / 2, rh)
                            elem_ass:round_rect_cw(0, gap, xp, elem_geo.h - gap, bar_h / 2)
                        end
                    else
                        local ax = get_slider_ele_pos_for(element, math.min(100, math.max(0, (loop_a / dur) * 100)))
                        local bx = (loop_b and loop_b > 0) and get_slider_ele_pos_for(element, math.min(100, math.max(0, (loop_b / dur) * 100))) or nil

                        -- White played progress stops cleanly at Point A
                        if xp and xp > 0 then
                            local white_end = math.min(xp, ax)
                            if white_end > 0 then
                                elem_ass:round_rect_cw(0, gap, white_end, elem_geo.h - gap, bar_h / 2)
                            end
                        end
                        -- White handle circle if playhead is before Point A
                        if xp and xp <= ax then
                            ass_draw_cir_cw(elem_ass, xp, elem_geo.h / 2, rh)
                        end

                        loop_seekbar_data = {
                            element = element,
                            bar_h = bar_h,
                            rh = rh,
                            ax = ax,
                            bx = bx,
                            xp = xp,
                        }
                    end
                else
                    local rh = user_opts.seekbarhandlesize * elem_geo.h / 2
                    local xp
                    if pos then
                        xp = get_slider_ele_pos_for(element, pos)
                        if (element.name == 'volumebar' and vmode == 'hover') then
                            xp = math.floor(xp * (state.vol_anim or 1.0) + 0.5)
                        end
                        ass_draw_cir_cw(elem_ass, xp, elem_geo.h/2, rh)
                        elem_ass:rect_cw(0, slider_lo.gap, xp, elem_geo.h - slider_lo.gap)
                    end
                end

                elem_ass:draw_stop()
            
            -- add tooltip
            if not (element.slider.tooltipF == nil) then
                if mouse_hit(element) then
                    local sliderpos = get_slider_value(element)
                    local tooltiplabel = element.slider.tooltipF(sliderpos)
                    local an = slider_lo.tooltip_an
                    local ty
                    if (an == 2) then
                        ty = element.hitbox.y1
                    else
                        ty = element.hitbox.y1 + elem_geo.h/2
                    end

                    local tx = get_virt_mouse_pos()
                    if (slider_lo.adjust_tooltip) then
                        if (an == 2) then
                            if (sliderpos < (s_min + 3)) then
                                an = an - 1
                            elseif (sliderpos > (s_max - 3)) then
                                an = an + 1
                            end
                        elseif (sliderpos > (s_max-s_min)/2) then
                            an = an + 1
                            tx = tx - 5
                        else
                            an = an - 1
                            tx = tx + 10
                        end
                    end

                    -- tooltip label
                    elem_ass:new_event()
                    elem_ass:pos(tx, ty)
                    elem_ass:an(an)
                    elem_ass:append(slider_lo.tooltip_style)
                    ass_append_alpha(elem_ass, slider_lo.alpha, 0)
                    elem_ass:append(tooltiplabel)
                    
                    -- thumbnail (ONLY for seekbar, never for volumebar)
                    if (element.name == 'seekbar') and (not thumbfast.disabled) then
                        local osd_w = mp.get_property_number("osd-width")
                        if osd_w then
                            local r_w, r_h = get_virt_scale_factor()

                            local tooltip_font_size = 18
                            local thumbPad = 1
                            local thumbMarginX = 18 / r_w
                            local thumbMarginY = tooltip_font_size + thumbPad + 2 / r_h
                            local tooltipBgColor = "000000"
                            local tooltipBgAlpha = 100
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

                            mp.commandv("script-message-to", "thumbfast", "thumb",
                                mp.get_property_number("duration", 0) * (sliderpos / 100),
                                thumbX,
                                thumbY
                            )

                            local se, ae = state.slider_element, elements[state.active_element]
                            if user_opts.chapter_fmt ~= "no" and se and (ae == se or (not ae and mouse_hit(se))) then
                                local dur = mp.get_property_number("duration", 0)
                                if dur and dur > 0 then
                                    local possec = get_slider_value(se) * dur / 100 -- of mouse pos
                                    local ch = get_chapter(possec)
                                    if ch and ch.title and ch.title ~= "" then
                                        elem_ass:new_event()
                                        elem_ass:pos((thumbX + thumbfast.width / 2) * r_w, thumbY * r_h - tooltip_font_size)
                                        elem_ass:an(an)
                                        elem_ass:append(slider_lo.tooltip_style)
                                        ass_append_alpha(elem_ass, slider_lo.alpha, 0)
                                        local ok_fmt, formatted = pcall(string.format, user_opts.chapter_fmt or 'Chapter: %s', ch.title)
                                        if ok_fmt and formatted then
                                            elem_ass:append(formatted)
                                        end
                                    end
                                end
                            end
                        end
                    end
                else
                    if (element.name == 'seekbar') and thumbfast.available then
                        mp.commandv("script-message-to", "thumbfast", "clear")
                    end
                end
            end

        elseif (element.type == 'button') then

            if element.name == 'media_badges' then
                render_media_badges(elem_ass, element.layout.geometry, element.layout.alpha)
            else
                local buttontext
                if type(element.content) == 'function' then
                    buttontext = element.content() -- function objects
                elseif not (element.content == nil) then
                    buttontext = element.content -- text objects
                end

                if buttontext == nil then buttontext = '' end
                buttontext = buttontext:gsub(':%((.?.?.?)%) unknown ', ':%(%1%)')  --gsub('%) unknown %(\'', '')

                local maxchars = element.layout.button.maxchars
                -- skip ALL charcount processing when content has ASS override tags
                if not (maxchars == nil) and not (buttontext:sub(1,1) == '{') then
                    -- 认为1个中文字符约等于1.5个英文字符
                    local charcount = (buttontext:len() + select(2, buttontext:gsub('[^\128-\193]', ''))*2) / 3
                    if (charcount > maxchars) then
                        local limit = math.max(0, maxchars - 3)
                        if (charcount > limit) then
                            while (charcount > limit) do
                                buttontext = buttontext:gsub('.[\128-\191]*$', '')
                                charcount = (buttontext:len() + select(2, buttontext:gsub('[^\128-\193]', ''))*2) / 3
                            end
                            buttontext = buttontext .. '...'
                        end
                    end
                end

                elem_ass:append(buttontext)
            end
            
            -- add tooltip
			if not (element.tooltipF == nil) and element.enabled then
                if mouse_hit(element) then
                    local tooltiplabel = element.tooltipF
                    local an = 1
                    local ty = element.hitbox.y1
                    local tx = get_virt_mouse_pos()
                    
                    if ty < osc_param.playresy / 2 then
						ty = element.hitbox.y2
						an = 7
					end

                    -- tooltip label
                    if type(element.tooltipF) == 'function' then
						tooltiplabel = element.tooltipF()
					else
						tooltiplabel = element.tooltipF
					end
                    elem_ass:new_event()
                    elem_ass:pos(tx, ty)
                    elem_ass:an(an)
                    elem_ass:append(element.tooltip_style)
                    elem_ass:append(tooltiplabel)
                end
			end
        end

        master_ass:merge(elem_ass)

        if loop_seekbar_data and element.name == 'seekbar' then
            local ld = loop_seekbar_data
            local sb_x0 = ld.element.hitbox.x1
            local center_y = ld.element.layout.geometry.y
            local y1 = center_y - ld.bar_h / 2
            local y2 = center_y + ld.bar_h / 2
            local ax_s = sb_x0 + ld.ax
            local bx_s = ld.bx and (sb_x0 + ld.bx) or nil
            local cur_x_s = ld.xp and (sb_x0 + ld.xp) or nil

            local ab_ass = assdraw.ass_new()

            -- 1. Translucent amber loop track across entire [A, B] window
            if bx_s and (bx_s - ax_s) > 0.5 then
                ab_ass:new_event()
                ab_ass:pos(0, 0)
                ab_ass:an(7)
                ab_ass:append('{\\blur0\\bord0\\1c&H00A5FF&\\1a&H90&}')
                ab_ass:draw_start()
                ab_ass:round_rect_cw(ax_s, y1, bx_s, y2, ld.bar_h / 2)
                ab_ass:draw_stop()
            end

            -- 2. Solid vibrant amber fill for played portion inside loop
            if cur_x_s and cur_x_s > ax_s then
                local played_end = bx_s and math.min(bx_s, cur_x_s) or cur_x_s
                if (played_end - ax_s) > 0.5 then
                    ab_ass:new_event()
                    ab_ass:pos(0, 0)
                    ab_ass:an(7)
                    ab_ass:append('{\\blur0\\bord0\\1c&H00A5FF&\\1a&H00&}')
                    ab_ass:draw_start()
                    ab_ass:round_rect_cw(ax_s, y1, played_end, y2, ld.bar_h / 2)
                    ab_ass:draw_stop()
                end
            end

            -- 3. Gold loop node cap markers (Point A and Point B)
            local node_r = (ld.bar_h / 2) + 2.0
            ab_ass:new_event()
            ab_ass:pos(0, 0)
            ab_ass:an(7)
            ab_ass:append('{\\blur0\\bord0.5\\1c&H00D7FF&\\3c&H004488&\\1a&H00&\\3a&H20&}')
            ab_ass:draw_start()
            ass_draw_cir_cw(ab_ass, ax_s, center_y, node_r)
            if bx_s then
                ass_draw_cir_cw(ab_ass, bx_s, center_y, node_r)
            end
            ab_ass:draw_stop()

            -- 3b. "A" / "B" micro-labels above each node marker
            local lbl_style = '{\\blur0\\bord0.4\\1c&H00D7FF&\\3c&H003366&\\fs7\\b700\\fn' .. user_opts.font .. '}'
            local lbl_y = y1 - 2  -- just above the bar
            ab_ass:new_event()
            ab_ass:pos(ax_s, lbl_y)
            ab_ass:an(2)
            ab_ass:append(lbl_style .. 'A')
            if bx_s then
                ab_ass:new_event()
                ab_ass:pos(bx_s, lbl_y)
                ab_ass:an(2)
                ab_ass:append(lbl_style .. 'B')
            end

            -- 4. White playhead handle circle if inside or past loop Point A
            if cur_x_s and cur_x_s > ax_s then
                ab_ass:new_event()
                ab_ass:pos(0, 0)
                ab_ass:an(7)
                ab_ass:append('{\\blur0\\bord0\\1c&HFFFFFF&\\1a&H00&}')
                ab_ass:draw_start()
                ass_draw_cir_cw(ab_ass, cur_x_s, center_y, ld.rh)
                ab_ass:draw_stop()
            end

            master_ass:merge(ab_ass)
            loop_seekbar_data = nil
        end


        end
    end
end

--
-- Message display
--

-- pos is 1 based
function limited_list(prop, pos)
    local proplist = mp.get_property_native(prop, {})
    local count = #proplist
    if count == 0 then
        return count, proplist
    end

    local fs = tonumber(mp.get_property('options/osd-font-size'))
    local max = math.ceil(osc_param.unscaled_y*0.75 / fs)
    if max % 2 == 0 then
        max = max - 1
    end
    local delta = math.ceil(max / 2) - 1
    local begi = math.max(math.min(pos - delta, count - max + 1), 1)
    local endi = math.min(begi + max - 1, count)

    local reslist = {}
    for i=begi, endi do
        local item = proplist[i]
        if item then
            local item_copy = {}
            for k, val in pairs(item) do item_copy[k] = val end
            item_copy.current = (i == pos) and true or nil
            table.insert(reslist, item_copy)
        end
    end
    return count, reslist
end

function get_playlist()
    local pos = mp.get_property_number('playlist-pos', 0) + 1
    local count, limlist = limited_list('playlist', pos)
    if not count or count == 0 then
        return texts.nolist or 'No playlist.'
    end

    local message = string.format((texts.playlist or 'Playlist') .. ' [%d/%d]:\n', pos or 1, count)
    for i, v in ipairs(limlist or {}) do
        if v then
            local title = v.title
            local _, filename = utils.split_path(v.filename or '')
            if title == nil then
                title = filename or ''
            end
            message = string.format('%s %s %s\n', message,
                (v.current and '●' or '○'), title)
        end
    end
    return message
end

function get_chapterlist()
    local pos = mp.get_property_number('chapter', 0) + 1
    local count, limlist = limited_list('chapter-list', pos)
    if not count or count == 0 then
        return texts.nochapter or 'No chapters.'
    end

    local u = ctx_ref.utils
    local message = string.format((texts.chapter or 'Chapter') .. ' [%d/%d]:\n', pos or 1, count)
    for i, v in ipairs(limlist or {}) do
        if v then
            local time = (u and u.format_time) and u.format_time(v.time) or '00:00'
            local title = v.title
            if title == nil then
                title = string.format((texts.chapter or 'Chapter') .. ' %02d', i)
            end
            if i == pos then
                message = message .. string.format('(%s) %s\n', time, title)
            else
                message = message .. string.format(' %s %s\n', time, title)
            end
        end
    end
    return message
end

function show_message(text, duration)

    --print('text: '..text..'   duration: ' .. duration)
    if duration == nil then
        duration = tonumber(mp.get_property('options/osd-duration')) / 1000
    elseif not type(duration) == 'number' then
        print('duration: ' .. duration)
    end

    -- cut the text short, otherwise the following functions
    -- may slow down massively on huge input
    text = string.sub(text, 0, 4000)

    -- replace actual linebreaks with ASS linebreaks
    text = string.gsub(text, '\n', '\\N')

    state.message_text = text

    if not state.message_hide_timer then
        state.message_hide_timer = mp.add_timeout(0, request_tick)
    end
    state.message_hide_timer:kill()
    state.message_hide_timer.timeout = duration
    state.message_hide_timer:resume()
    request_tick()
end

function render_message(ass)
    if state.message_hide_timer and state.message_hide_timer:is_enabled() and
       state.message_text
    then
        local _, lines = string.gsub(state.message_text, '\\N', '')

        local fontsize = tonumber(mp.get_property('options/osd-font-size'))
        local outline = tonumber(mp.get_property('options/osd-border-size'))
        local maxlines = math.ceil(osc_param.unscaled_y*0.75 / fontsize)
        local counterscale = osc_param.playresy / osc_param.unscaled_y

        fontsize = fontsize * counterscale / math.max(0.65 + math.min(lines/maxlines, 1), 1)
        outline = outline * counterscale / math.max(0.75 + math.min(lines/maxlines, 1)/2, 1)

        local style = '{\\bord' .. outline .. '\\fs' .. fontsize .. '}'


        ass:new_event()
        ass:append(style .. state.message_text)
    else
        state.message_text = nil
    end
end

--
-- Initialisation and Layout
--

function new_element(name, type)
    elements[name] = {}
    elements[name].type = type
    elements[name].name = name

    -- add default stuff
    elements[name].eventresponder = {}
    elements[name].visible = true
    elements[name].enabled = true
    elements[name].softrepeat = false
    elements[name].styledown = (type == 'button')
    elements[name].state = {}

    if (type == 'slider') then
        elements[name].slider = {min = {value = 0}, max = {value = 100}}
    end


    return elements[name]
end

function add_layout(name)
    if not (elements[name] == nil) then
        -- new layout
        elements[name].layout = {}

        -- set layout defaults
        elements[name].layout.layer = 50
        elements[name].layout.alpha = {[1] = 0, [2] = 255, [3] = 255, [4] = 255}

        if (elements[name].type == 'button') then
            elements[name].layout.button = {
                maxchars = nil,
            }
        elseif (elements[name].type == 'slider') then
            -- slider defaults
            elements[name].layout.slider = {
                border = 1,
                gap = 1,
                nibbles_top = true,
                nibbles_bottom = true,
                adjust_tooltip = true,
                tooltip_style = '',
                tooltip_an = 2,
                alpha = {[1] = 0, [2] = 255, [3] = 88, [4] = 255},
            }
        elseif (elements[name].type == 'box') then
            elements[name].layout.box = {radius = 0, hexagon = false}
        end

        return elements[name].layout
    else
        msg.error('Can\'t add_layout to element \''..name..'\', doesn\'t exist.')
    end
end

-- Window Controls
function window_controls()
    local wc_geo = {
        x = 0,
        y = 32,
        an = 1,
        w = osc_param.playresx,
        h = 32,
    }

    local controlbox_w = window_control_box_width
    local titlebox_w = wc_geo.w - controlbox_w

    -- Default alignment is 'right'
    local controlbox_left = wc_geo.w - controlbox_w
    local titlebox_left = wc_geo.x
    local titlebox_right = wc_geo.w - controlbox_w

    add_area('window-controls',
             get_hitbox_coords(controlbox_left, wc_geo.y, wc_geo.an,
                               controlbox_w, wc_geo.h))

    local lo

    local button_y = wc_geo.y - (wc_geo.h / 2)
    local first_geo =
        {x = controlbox_left + 27, y = button_y, an = 5, w = 40, h = wc_geo.h}
    local second_geo =
        {x = controlbox_left + 69, y = button_y, an = 5, w = 40, h = wc_geo.h}
    local third_geo =
        {x = controlbox_left + 115, y = button_y, an = 5, w = 40, h = wc_geo.h}

    -- Window control buttons use symbols in the custom mpv osd font
    -- because the official unicode codepoints are sufficiently
    -- exotic that a system might lack an installed font with them,
    -- and libass will complain that they are not present in the
    -- default font, even if another font with them is available.

    -- Close: ??
    ne = new_element('close', 'button')
    ne.content = '\238\132\149'
    ne.eventresponder['mbtn_left_up'] =
        function () mp.commandv('quit') end
    lo = add_layout('close')
    lo.geometry = third_geo
    lo.style = osc_styles.WinCtrl
    lo.alpha[3] = 0

    -- Minimize: ??
    ne = new_element('minimize', 'button')
    ne.content = '\\n\238\132\146'
    ne.eventresponder['mbtn_left_up'] =
        function () mp.commandv('cycle', 'window-minimized') end
    lo = add_layout('minimize')
    lo.geometry = first_geo
    lo.style = osc_styles.WinCtrl
    lo.alpha[3] = 0
    
    -- Maximize: ?? /??
    ne = new_element('maximize', 'button')
    if state.maximized or state.fullscreen then
        ne.content = '\238\132\148'
    else
        ne.content = '\238\132\147'
    end
    ne.eventresponder['mbtn_left_up'] =
        function ()
            if state.fullscreen then
                mp.commandv('cycle', 'fullscreen')
            else
                mp.commandv('cycle', 'window-maximized')
            end
        end
    lo = add_layout('maximize')
    lo.geometry = second_geo
    lo.style = osc_styles.WinCtrl
    lo.alpha[3] = 0
end

--
-- Layouts
--

local layouts = {}

-- Default layout
layouts = function ()
local UI_OFFSET_Y = 0
    local osc_geo = {w, h}

	osc_geo.w = osc_param.playresx
	osc_geo.h = 180

    -- origin of the controllers, left/bottom corner
    local posX = 0
    local posY = osc_param.playresy

    osc_param.areas = {} -- delete areas

    -- area for active mouse input
    add_area('input', get_hitbox_coords(posX, posY + UI_OFFSET_Y, 1, osc_geo.w, 110))

    -- area for show/hide
    add_area('showhide', 0, 0, osc_param.playresx, osc_param.playresy)

    -- fetch values
    local osc_w, osc_h=
        osc_geo.w, osc_geo.h

	--
    -- Controller Background — Upward-Fading Gradient Scrim (Infuse / Apple TV)
    --
	local lo
	local scrim_layers = {
		{h = 55,  alpha = 75,  blur = 22},
		{h = 100, alpha = 115, blur = 28},
		{h = 150, alpha = 160, blur = 34},
		{h = 195, alpha = 200, blur = 40},
		{h = 240, alpha = 235, blur = 46},
	}
	for i, sc in ipairs(scrim_layers) do
		local name = 'scrim_' .. i
		new_element(name, 'box')
		lo = add_layout(name)
		lo.geometry = {x = posX, y = posY - sc.h, an = 7, w = osc_w, h = sc.h}
		lo.style = string.format('{\\blur%d\\bord0\\1c&H0A0A0D&\\3c&H0A0A0D&}', sc.blur)
		lo.layer = 10
		lo.alpha[1] = sc.alpha
		lo.alpha[3] = 255
	end

    --
    -- Alignment
    --
	local refX = osc_w / 2
	local refY = posY
	local geo
	
    --
    -- Seekbar
    --
    new_element('seekbarbg', 'box')
    lo = add_layout('seekbarbg')
    -- h must match the seekbar slider h so both have the same center point;
    -- the actual bar thickness is painted dynamically in render_elements.
    lo.geometry = {x = refX , y = refY - 96 + UI_OFFSET_Y , an = 5, w = osc_geo.w - 50, h = 19}
    lo.layer = 13
    lo.style = osc_styles.SeekbarBg
    lo.alpha[1] = 128
    lo.alpha[3] = 128

    lo = add_layout('seekbar')
    lo.geometry = {x = refX, y = refY - 96 + UI_OFFSET_Y , an = 5, w = osc_geo.w - 50, h = 19}
	lo.style = osc_styles.SeekbarFg
    lo.slider.gap = 6
    lo.slider.tooltip_style = osc_styles.Tooltip
    lo.slider.tooltip_an = 2

    local showjump = user_opts.showjump
    local offset = showjump and 60 or 0
    
    --
    -- Adaptive Sizing & Metrics (Window-size proportional, strictly capped by min_scale / max_scale)
    --
    local min_scale = tonumber(user_opts.min_scale) or 0.70
    local max_scale = tonumber(user_opts.max_scale) or 1.05
    local raw_scale = osc_param.playresx / 1280
    local scale = math.max(min_scale, math.min(max_scale, raw_scale))

    local is_compact = (osc_param.playresx < 1050)
    local is_tiled   = (osc_param.playresx < 850)

    -- Rounded font sizes for crisp glyph rendering
    local fs_ctrl1      = math.floor(44 * scale + 0.5)
    local fs_ctrl2      = math.floor(26 * scale + 0.5)
    local fs_ctrl2_flip = math.floor(22 * scale + 0.5)
    local fs_ctrl3      = math.floor(22 * scale + 0.5)

    local style_ctrl1      = string.format('{\\blur0\\bord0\\1c&HFFFFFF&\\3c&H161618&\\fs%d\\fnMaterial Icons Round}', fs_ctrl1)
    local style_ctrl2      = string.format('{\\blur0\\bord0\\1c&HFFFFFF&\\3c&H161618&\\fs%d\\fnMaterial Icons Round}', fs_ctrl2)
    local style_ctrl2_flip = string.format('{\\blur0\\bord0\\1c&HFFFFFF&\\3c&HFFFFFF&\\fs%d\\fnMaterial Icons Round\\fry180}', fs_ctrl2_flip)
    local style_ctrl3      = string.format('{\\blur0\\bord0\\1c&HC7C7CC&\\3c&H161618&\\fs%d\\fnMaterial Icons Round}', fs_ctrl3)

    -- Button hitboxes
    local ctrl1_w = math.floor(45 * scale + 0.5)
    local ctrl1_h = math.floor(45 * scale + 0.5)
    local ctrl2_w = math.floor(32 * scale + 0.5)
    local ctrl2_h = math.floor(24 * scale + 0.5)
    local ctrl3_w = math.floor(26 * scale + 0.5)
    local ctrl3_h = math.floor(24 * scale + 0.5)

    -- Left controls placement
    local left_pad     = math.floor(36 * scale + 0.5)
    local left_spacing = math.floor(46 * scale + 0.5)

    lo = add_layout('cy_audio')
    lo.geometry = {x = left_pad, y = refY - 40 + UI_OFFSET_Y, an = 5, w = ctrl3_w, h = ctrl3_h}
    lo.style = style_ctrl3
    elements['cy_audio'].visible = (osc_param.playresx >= 480)
	
    lo = add_layout('cy_sub')
    lo.geometry = {x = left_pad + left_spacing, y = refY - 40 + UI_OFFSET_Y, an = 5, w = ctrl3_w, h = ctrl3_h}
    lo.style = style_ctrl3
    elements['cy_sub'].visible = (osc_param.playresx >= 540)

    lo = add_layout('tog_video')
    lo.geometry = {x = left_pad + left_spacing * 2, y = refY - 40 + UI_OFFSET_Y, an = 5, w = ctrl3_w, h = ctrl3_h}
    lo.style = style_ctrl3
    elements['tog_video'].visible = (osc_param.playresx >= 580)

    local vol_x = left_pad + left_spacing * 3
    lo = add_layout('vol_ctrl')
    lo.geometry = {x = vol_x, y = refY - 40 + UI_OFFSET_Y, an = 5, w = ctrl3_w, h = ctrl3_h}
    lo.style = style_ctrl3
    elements['vol_ctrl'].visible = (osc_param.playresx >= 650) and user_opts.volumecontrol

    local vbar_x = vol_x + math.floor(18 * scale + 0.5)
    local vbar_w = math.floor((is_compact and 55 or 70) * scale + 0.5)

    local vmode = user_opts.volume_slider_mode or 'hover'
    local show_vbar = (osc_param.playresx >= 780) and user_opts.volumecontrol and (vmode ~= 'never')

    lo = new_element('volumebarbg', 'box')
    lo.visible = show_vbar
    lo = add_layout('volumebarbg')
    lo.geometry = {x = vbar_x, y = refY - 40 + UI_OFFSET_Y, an = 4, w = vbar_w, h = 2}
    lo.layer = 13
    lo.style = osc_styles.VolumebarBg
    elements['volumebarbg'].visible = show_vbar

    lo = add_layout('volumebar')
    lo.geometry = {x = vbar_x, y = refY - 40 + UI_OFFSET_Y, an = 4, w = vbar_w, h = 10}
    lo.style = osc_styles.VolumebarFg
    lo.slider.gap = 4
    lo.slider.tooltip_style = osc_styles.Tooltip
    lo.slider.tooltip_an = 2
    elements['volumebar'].visible = show_vbar

    -- Right controls placement (symmetric from right edge: FS, Info, Tags, Speed, Chapters, Playlist)
    local right_pad     = osc_geo.w - math.floor(36 * scale + 0.5)
    local right_spacing = math.floor(44 * scale + 0.5)
    local fs_speed      = math.floor(13 * scale + 0.5)
    local style_speed   = string.format('{\\blur0\\bord0\\1c&HC7C7CC&\\3c&H161618&\\fs%d\\fn%s\\b700}', fs_speed, user_opts.font)

    local btn_idx = 0
    lo = add_layout('tog_fs')
    lo.geometry = {x = right_pad - right_spacing * btn_idx, y = refY - 40 + UI_OFFSET_Y, an = 5, w = ctrl3_w, h = ctrl3_h}
    lo.style = style_ctrl3
    elements['tog_fs'].visible = (osc_param.playresx >= 500)
    btn_idx = btn_idx + 1

    lo = add_layout('tog_info')
    lo.geometry = {x = right_pad - right_spacing * btn_idx, y = refY - 40 + UI_OFFSET_Y, an = 5, w = ctrl3_w, h = ctrl3_h}
    lo.style = style_ctrl3
    elements['tog_info'].visible = (osc_param.playresx >= 540)
    btn_idx = btn_idx + 1

    local show_update_btn = (state.update_available ~= nil)
    lo = add_layout('tog_update')
    if show_update_btn then
        lo.geometry = {x = right_pad - right_spacing * btn_idx, y = refY - 40 + UI_OFFSET_Y, an = 5, w = ctrl3_w, h = ctrl3_h}
        lo.style = style_ctrl3
        elements['tog_update'].visible = true
        btn_idx = btn_idx + 1
    else
        lo.geometry = {x = 0, y = 0, an = 5, w = 0, h = 0}
        lo.style = style_ctrl3
        elements['tog_update'].visible = false
    end

    lo = add_layout('tog_tags')
    lo.geometry = {x = right_pad - right_spacing * btn_idx, y = refY - 40 + UI_OFFSET_Y, an = 5, w = ctrl3_w, h = ctrl3_h}
    lo.style = style_ctrl3
    elements['tog_tags'].visible = (osc_param.playresx >= 660)
    btn_idx = btn_idx + 1

    lo = add_layout('tog_speed')
    lo.geometry = {x = right_pad - right_spacing * btn_idx, y = refY - 40 + UI_OFFSET_Y, an = 5, w = math.floor(34 * scale + 0.5), h = ctrl3_h}
    lo.style = style_speed
    elements['tog_speed'].visible = (osc_param.playresx >= 720)
    btn_idx = btn_idx + 1

    lo = add_layout('tog_chapters')
    lo.geometry = {x = right_pad - right_spacing * btn_idx, y = refY - 40 + UI_OFFSET_Y, an = 5, w = ctrl3_w, h = ctrl3_h}
    lo.style = style_ctrl3
    elements['tog_chapters'].visible = (osc_param.playresx >= 580)
    btn_idx = btn_idx + 1

    lo = add_layout('tog_playlist')
    lo.geometry = {x = right_pad - right_spacing * btn_idx, y = refY - 40 + UI_OFFSET_Y, an = 5, w = ctrl3_w, h = ctrl3_h}
    lo.style = style_ctrl3
    elements['tog_playlist'].visible = (osc_param.playresx >= 620)

    -- Center playback cluster
    local have_ch = (mp.get_property_number('chapters', 0) > 0)
    local have_pl = (mp.get_property_number('playlist-count', 0) > 1)
    local center_spacing = math.floor(62 * scale + 0.5)

    local show_jump    = (user_opts.showjump == true)
    local show_chapter = false -- User requested: no fast forward or chapter skip buttons on OSC bar
    local show_pl      = have_pl

    -- Assign unique non-overlapping slots from inside out
    local cur_step = 0
    local jump_step = 0
    if show_jump then
        cur_step = cur_step + 1
        jump_step = cur_step
    end

    local ch_step = 0
    if show_chapter then
        cur_step = cur_step + 1
        ch_step = cur_step
    end

    local pl_step = 0
    if show_pl then
        cur_step = cur_step + 1
        pl_step = cur_step
    end

    -- Primary Center: Play/Pause
    lo = add_layout('playpause')
    lo.geometry = {x = refX, y = refY - 40 + UI_OFFSET_Y, an = 5, w = ctrl1_w, h = ctrl1_h}
    lo.style = style_ctrl1
    elements['playpause'].visible = true

    -- 10s Jump Buttons
    if show_jump then
        lo = add_layout('jumpback')
        lo.geometry = {x = refX - (center_spacing * jump_step), y = refY - 40 + UI_OFFSET_Y, an = 5, w = ctrl2_w, h = ctrl2_h}
        lo.style = style_ctrl2
        elements['jumpback'].visible = true

        lo = add_layout('jumpfrwd')
        lo.geometry = {x = refX + (center_spacing * jump_step), y = refY - 40 + UI_OFFSET_Y, an = 5, w = ctrl2_w, h = ctrl2_h}
        lo.style = (user_opts.jumpiconnumber and jumpicons[user_opts.jumpamount] ~= nil) and style_ctrl2 or style_ctrl2_flip
        elements['jumpfrwd'].visible = true
    else
        if elements['jumpback'] then elements['jumpback'].visible = false; elements['jumpback'].layout = nil end
        if elements['jumpfrwd'] then elements['jumpfrwd'].visible = false; elements['jumpfrwd'].layout = nil end
    end

    -- Chapter Skip Buttons
    if show_chapter then
        lo = add_layout('skipback')
        lo.geometry = {x = refX - (center_spacing * ch_step), y = refY - 40 + UI_OFFSET_Y, an = 5, w = ctrl2_w, h = ctrl2_h}
        lo.style = style_ctrl2
        elements['skipback'].visible = true

        lo = add_layout('skipfrwd')
        lo.geometry = {x = refX + (center_spacing * ch_step), y = refY - 40 + UI_OFFSET_Y, an = 5, w = ctrl2_w, h = ctrl2_h}
        lo.style = style_ctrl2
        elements['skipfrwd'].visible = true
    else
        if elements['skipback'] then elements['skipback'].visible = false; elements['skipback'].layout = nil end
        if elements['skipfrwd'] then elements['skipfrwd'].visible = false; elements['skipfrwd'].layout = nil end
    end

    -- Playlist Buttons
    if show_pl then
        lo = add_layout('pl_prev')
        lo.geometry = {x = refX - (center_spacing * pl_step), y = refY - 40 + UI_OFFSET_Y, an = 5, w = ctrl2_w, h = ctrl2_h}
        lo.style = style_ctrl2
        elements['pl_prev'].visible = true

        lo = add_layout('pl_next')
        lo.geometry = {x = refX + (center_spacing * pl_step), y = refY - 40 + UI_OFFSET_Y, an = 5, w = ctrl2_w, h = ctrl2_h}
        lo.style = style_ctrl2
        elements['pl_next'].visible = true
    else
        if elements['pl_prev'] then elements['pl_prev'].visible = false; elements['pl_prev'].layout = nil end
        if elements['pl_next'] then elements['pl_next'].visible = false; elements['pl_next'].layout = nil end
    end

    -- Time displays
    local tc_pad = math.max(20, math.floor(25 * scale + 0.5))
    lo = add_layout('tc_left')
    lo.geometry = {x = tc_pad, y = refY - 84 + UI_OFFSET_Y, an = 7, w = 64, h = 20}
    lo.style = osc_styles.Time	

    lo = add_layout('tc_right')
    lo.geometry = {x = osc_geo.w - tc_pad, y = refY - 84 + UI_OFFSET_Y, an = 9, w = 64, h = 20}
    lo.style = osc_styles.Time

    -- Badge row sits ABOVE title (Infuse / Option B style)
    -- anchor: an=1 (top-left), so y is the TOP edge of the badge row
    new_element('media_badges', 'button')
    lo = add_layout('media_badges')
    lo.geometry = { x = 25, y = refY - 180 + UI_OFFSET_Y, an = 1, w = osc_geo.w - 50, h = 18 }
    lo.style = ''
    lo.layer = 50
    lo.visible = (osc_param.playresx >= 540)

    -- Title sits below the badge row
    geo = { x = 25, y = refY - 136 + UI_OFFSET_Y, an = 1, w = osc_geo.w - 50, h = 36 }
    lo = add_layout('title')
    lo.geometry = geo
    if osc_param.playresx < 700 then
        lo.style = string.format('{\\blur0\\bord0.5\\1c&HFFFFFF&\\3c&H101014&\\fs15\\b600\\fsp0.1\\q2\\fn%s}', user_opts.font)
    else
        lo.style = osc_styles.Title
    end
	lo.alpha[3] = 0
    lo.button.maxchars = math.max(22, math.floor((osc_geo.w - 60) / 9.5))
end

-- Validate string type user options
function validate_user_opts()
    if user_opts.windowcontrols ~= 'auto' and
       user_opts.windowcontrols ~= 'yes' and
       user_opts.windowcontrols ~= 'no' then
        msg.warn('windowcontrols cannot be \'' ..
                user_opts.windowcontrols .. '\'. Ignoring.')
        user_opts.windowcontrols = 'auto'
    end
end

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

    -- set canvas resolution according to display aspect and scaling setting
    local baseResY = 720
    local display_w, display_h, display_aspect = mp.get_osd_size()
    local scale = 1

    if (mp.get_property('video') == 'no') then -- dummy/forced window
        scale = user_opts.scaleforcedwindow
    elseif state.fullscreen then
        scale = user_opts.scalefullscreen
    else
        scale = user_opts.scalewindowed
    end

    if user_opts.vidscale then
        osc_param.unscaled_y = baseResY
    else
        osc_param.unscaled_y = display_h
    end
    osc_param.playresy = osc_param.unscaled_y / scale
    if (display_aspect > 0) then
        osc_param.display_aspect = display_aspect
    end
    osc_param.playresx = osc_param.playresy * osc_param.display_aspect

    -- stop seeking with the slider to prevent skipping files
    state.active_element = nil

    elements = {}

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
                    tonumber(user_opts.screensaver_delay) or 3,
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
        thumbfast = data
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
