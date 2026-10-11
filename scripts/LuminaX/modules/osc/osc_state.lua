-- ============================================================================
-- LuminaX Sub-module: OSC State & Coordinate Primitives
-- Manages shared OSC runtime state, user options, icons, styles and geometry helpers.
-- ============================================================================

local msg = require('mp.msg')
local opt = require('mp.options')

local M = {}

-- default user option values (may be customized in osc.conf or luminax.conf)
local user_opts = {
    showwindowed = true,        -- show OSC when windowed?
    showfullscreen = true,      -- show OSC when fullscreen?
    idlescreen = true,          -- draw logo and text when idle
    scalewindowed = 1.0,        -- scaling of the controller when windowed
    scalefullscreen = 1.0,      -- scaling of the controller when fullscreen
    scaleforcedwindow = 2.0,    -- scaling when rendered on a forced window
    vidscale = true,            -- scale the controller with the video?
    hidetimeout = 1500,         -- duration in ms until the OSC hides if no mouse movement
    fadeduration = 250,         -- duration of fade out in ms, 0 = no fade
    minmousemove = 1,           -- minimum amount of pixels the mouse has to move
    iamaprogrammer = false,     -- use native mpv values and disable OSC track list management
    font = 'Inter',             -- default osc font
    seekbarhandlesize = 0.6,    -- size ratio of the slider handle, range 0 ~ 1
    seekrange = true,           -- show seekrange overlay
    seekrangealpha = 64,        -- transparency of seekranges
    seekbarkeyframes = true,    -- use keyframes when dragging the seekbar
    showjump = true,            -- show "jump forward/backward 5 seconds" buttons
    jumpamount = 5,             -- change the jump amount (in seconds by default)
    jumpiconnumber = true,      -- show different icon when jumpamount is 5, 10, or 30
    jumpmode = 'exact',         -- seek mode for jump buttons
    title = '${filename/no-ext}',-- string compatible with property-expansion for title
    showtitle = true,           -- show title in OSC
    showonpause = true,         -- whether to disable the hide timeout on pause
    timetotal = true,           -- display total time instead of remaining time?
    timems = false,             -- display time down to milliseconds by default
    visibility = 'auto',        -- only used at init to set visibility_mode(...)
    windowcontrols = 'auto',    -- whether to show window controls
    greenandgrumpy = false,     -- disable santa hat
    language = 'eng',           -- eng=English, chs=Chinese, pl=Polish
    volumecontrol = true,       -- whether to show mute button and volume slider
    volume_slider_mode = 'hover', -- volume slider appearance: 'hover', 'always', 'never'
    keyboardnavigation = false, -- enable directional keyboard navigation
    chapter_fmt = '%s',         -- format for chapter name display on seekbar
    min_scale = 0.70,           -- minimum adaptive scale factor
    max_scale = 1.05,           -- maximum adaptive scale factor
    tmdb_api_key = '',          -- TMDB v3 API key
    screensaver_enabled = true, -- dim overlay + metadata card on pause
    screensaver_delay = 3,      -- seconds of pause before screensaver activates
    screensaver_align = 'center',-- screensaver alignment: 'center', 'split'
    logo_engine = 'auto',       -- logo processing engine: 'auto', 'ffmpeg', 'text'
    screensaver_film_font = 'NewYork', -- font face for title when no logo is used
    tmdb_cache_lookup = true,   -- whether to use disk/memory cache for tmdb data
    tmdb_cache_max_mb = 250,    -- maximum cache storage size in MB
    screensaver_anti_burnin = false, -- anti-burn-in micro-drift on pause
    check_updates = true,       -- auto check for updates in background
    check_update_interval_days = 3, -- check frequency in days
    sub_auto_anime_preset = true, -- switch to Anime Fansub subtitle preset when Animation
    smart_skip_mode = 'pill',   -- 'pill', 'auto', 'no'
    smart_skip_series_only = true, -- only skip intros/outros for series/anime
    chapter_zone_tinting = true,-- subtle seekbar range shading for intro and outro
    smart_skip_countdown = 6,   -- countdown in seconds for intro/outro skip button
    smart_skip_bottom_margin = 170, -- constant vertical distance from bottom
    next_episode_card = true,   -- show Next Episode binge card on outro/ending
    next_episode_countdown = 10,-- countdown in seconds before auto-playing next episode
    next_episode_threshold = 25,-- remaining playtime threshold in seconds
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
    update = '\238\164\163',       -- Material Icons Round: update
    pip = '\238\164\145',          -- picture_in_picture_alt
}

-- Localization
local language = {
    ['eng'] = {
        welcome = '{\\fs24\\1c&H0&\\1c&HFFFFFF&}Drop files or URLs to play here.',
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
        welcome = '{\\1c&H00\\bord0\\fs30\\fn微软雅黑 light\\fscx125}MPV{\\fscx100} 播放器',
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
        welcome = '{\\fs24\\1c&H0&\\1c&HFFFFFF&}Upuść plik lub łącze URL do odtworzenia.',
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

local function validate_user_opts()
    if user_opts.windowcontrols ~= 'auto' and
       user_opts.windowcontrols ~= 'yes' and
       user_opts.windowcontrols ~= 'no' then
        if msg and msg.warn then
            msg.warn('windowcontrols cannot be \'' .. user_opts.windowcontrols .. '\'. Ignoring.')
        end
        user_opts.windowcontrols = 'auto'
    end
end

-- Read options from config files
opt.read_options(user_opts, 'osc')
opt.read_options(user_opts, 'luminax')
validate_user_opts()

local texts = language[user_opts.language] or language['eng']

local osc_param = {
    playresy = 0,
    playresx = 0,
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
    Ctrl1 = '{\\blur0\\bord0\\1c&HFFFFFF&\\3c&H161618&\\fs44\\fnMaterial Icons Round}',
    Ctrl2 = '{\\blur0\\bord0\\1c&HFFFFFF&\\3c&H161618&\\fs26\\fnMaterial Icons Round}',
    Ctrl2Flip = '{\\blur0\\bord0\\1c&HFFFFFF&\\3c&HFFFFFF&\\fs22\\fnMaterial Icons Round\\fry180}',
    Ctrl3 = '{\\blur0\\bord0\\1c&HC7C7CC&\\3c&H161618&\\fs22\\fnMaterial Icons Round}',
    Time = '{\\blur0\\bord0\\1c&HFFFFFF&\\3c&H000000&\\fs12\\b400\\fsp0.8\\fn' .. user_opts.font .. '}',
    Tooltip = '{\\blur0\\bord0.8\\1c&HFFFFFF&\\3c&H101014&\\fs12\\b700\\fn' .. user_opts.font .. '}',
    Title = '{\\blur0\\bord0.5\\1c&HFFFFFF&\\3c&H101014&\\fs19\\b600\\fsp0.1\\q2\\fn' .. user_opts.font .. '}',
    WinCtrl = '{\\blur1\\bord0.5\\1c&HFFFFFF&\\3c&H0\\fs16\\fnmpv-osd-symbols}',
    ThumbnailBorder = '{\\blur0\\bord0\\1c&H000000&}',
    elementDown = '{\\1c&H8E8E93&}',
    elementHighlight = '{\\blur2\\bord0\\1c&HFFFFFF&}',
}

local elements = {}

local state = {
    showtime = nil,
    osc_visible = false,
    anistart = nil,
    anitype = nil,
    animation = nil,
    mouse_down_counter = 0,
    active_element = nil,
    active_event_source = nil,
    rightTC_trem = not user_opts.timetotal,
    mp_screen_sizeX = nil,
    mp_screen_sizeY = nil,
    initREQ = false,
    last_mouseX = nil,
    last_mouseY = nil,
    mouse_in_window = false,
    seekbar_anim = 0.0,
    seekbar_last_t = nil,
    vol_anim = 0.0,
    vol_last_t = nil,
    message_text = nil,
    message_hide_timer = nil,
    fullscreen = false,
    tick_timer = nil,
    tick_last_time = 0,
    hide_timer = nil,
    cache_state = nil,
    idle = false,
    enabled = true,
    input_enabled = true,
    showhide_enabled = false,
    dmx_cache = 0,
    border = true,
    maximized = false,
    osd = (mp and mp.create_osd_overlay) and mp.create_osd_overlay('ass-events') or nil,
    mute = false,
    lastvisibility = user_opts.visibility,
    fulltime = user_opts.timems,
    highlight_element = 'cy_audio',
    chapter_list = {},
    menu_active = nil,
    menu_selected = 1,
    menu_scroll = 0,
}

local thumbfast = {
    width = 0,
    height = 0,
    disabled = true,
    available = false,
}

local function set_thumbfast(data)
    if type(data) ~= 'table' then return end
    for k in pairs(thumbfast) do
        thumbfast[k] = nil
    end
    for k, v in pairs(data) do
        thumbfast[k] = v
    end
end

-- ── Coordinates & Hit Testing Helpers ──────────────────────────────────────────

local function get_virt_scale_factor()
    if not (mp and mp.get_osd_size) then return 1, 1 end
    local w, h = mp.get_osd_size()
    if not w or not h or w <= 0 or h <= 0 then
        return 0, 0
    end
    return osc_param.playresx / w, osc_param.playresy / h
end

local function get_virt_mouse_pos()
    if not (mp and mp.get_mouse_pos) then return -1, -1 end
    local x, y = mp.get_mouse_pos()
    if state.mouse_in_window or (x and y and (x > 0 or y > 0)) then
        local sx, sy = get_virt_scale_factor()
        return x * sx, y * sy
    else
        return -1, -1
    end
end

local function set_virt_mouse_area(x0, y0, x1, y1, name)
    if not (mp and mp.set_mouse_area) then return end
    local sx, sy = get_virt_scale_factor()
    if sx > 0 and sy > 0 then
        mp.set_mouse_area(x0 / sx, y0 / sy, x1 / sx, y1 / sy, name)
    end
end

local function scale_value(x0, x1, y0, y1, val)
    if x1 == x0 then return y0 end
    local m = (y1 - y0) / (x1 - x0)
    local b = y0 - (m * x0)
    return (m * val) + b
end

local function limit_range(min_val, max_val, val)
    if val > max_val then
        return max_val
    elseif val < min_val then
        return min_val
    end
    return val
end

local function countone(val)
    if not user_opts.iamaprogrammer then
        val = val + 1
    end
    return val
end

local function mult_alpha(alphaA, alphaB)
    return 255 - (((1 - (alphaA / 255)) * (1 - (alphaB / 255))) * 255)
end

local function add_area(name, x1, y1, x2, y2)
    if osc_param.areas[name] == nil then
        osc_param.areas[name] = {}
    end
    table.insert(osc_param.areas[name], {x1 = x1, y1 = y1, x2 = x2, y2 = y2})
end

local function get_hitbox_coords(x, y, an, w, h)
    local alignments = {
        [1] = function() return x, y - h, x + w, y end,
        [2] = function() return x - (w / 2), y - h, x + (w / 2), y end,
        [3] = function() return x - w, y - h, x, y end,
        [4] = function() return x, y - (h / 2), x + w, y + (h / 2) end,
        [5] = function() return x - (w / 2), y - (h / 2), x + (w / 2), y + (h / 2) end,
        [6] = function() return x - w, y - (h / 2), x, y + (h / 2) end,
        [7] = function() return x, y, x + w, y + h end,
        [8] = function() return x - (w / 2), y, x + (w / 2), y + h end,
        [9] = function() return x - w, y, x, y + h end,
    }
    local fn = alignments[an]
    if fn then return fn() end
    return x, y, x + w, y + h
end

local function get_hitbox_coords_geo(geometry)
    return get_hitbox_coords(geometry.x, geometry.y, geometry.an, geometry.w, geometry.h)
end

local function get_element_hitbox(element)
    return element.hitbox.x1, element.hitbox.y1, element.hitbox.x2, element.hitbox.y2
end

local function mouse_hit_coords(bX1, bY1, bX2, bY2)
    local mX, mY = get_virt_mouse_pos()
    return (mX >= bX1 and mX <= bX2 and mY >= bY1 and mY <= bY2)
end

local function mouse_hit(element)
    if not element or not element.hitbox then return false end
    if element.name == 'volumebar' or element.name == 'volumebarbg' then
        local vmode = user_opts.volume_slider_mode or 'hover'
        if vmode == 'never' then return false end
        local active_elem = (state.active_element and elements and elements[state.active_element]) or nil
        if vmode == 'hover' and (state.vol_anim or 0) < 0.35 and (active_elem ~= element) then
            return false
        end
    end
    return mouse_hit_coords(get_element_hitbox(element))
end

local function ass_append_alpha(ass, alpha, modifier)
    local ar = {}
    for ai, av in pairs(alpha) do
        av = mult_alpha(av, modifier)
        if state.animation then
            av = mult_alpha(av, state.animation)
        end
        ar[ai] = av
    end
    ass:append(string.format('{\\1a&H%X&\\2a&H%X&\\3a&H%X&\\4a&H%X&}',
               ar[1] or 0, ar[2] or 255, ar[3] or 255, ar[4] or 255))
end

local function ass_draw_cir_cw(ass, x, y, r)
    ass:round_rect_cw(x - r, y - r, x + r, y + r, r)
end

local function ass_draw_rr_h_cw(ass, x0, y0, x1, y1, r1, hexagon, r2)
    if hexagon and ass.hexagon_cw then
        ass:hexagon_cw(x0, y0, x1, y1, r1, r2)
    else
        ass:round_rect_cw(x0, y0, x1, y1, r1, r2)
    end
end

local function ass_draw_rr_h_ccw(ass, x0, y0, x1, y1, r1, hexagon, r2)
    if hexagon and ass.hexagon_ccw then
        ass:hexagon_ccw(x0, y0, x1, y1, r1, r2)
    else
        ass:round_rect_ccw(x0, y0, x1, y1, r1, r2)
    end
end

local function new_element(name, type)
    elements[name] = {}
    elements[name].type = type
    elements[name].name = name
    elements[name].eventresponder = {}
    elements[name].visible = true
    elements[name].enabled = true
    elements[name].softrepeat = false
    elements[name].styledown = (type == 'button')
    elements[name].state = {}

    if type == 'slider' then
        elements[name].slider = {min = {value = 0}, max = {value = 100}}
    end

    return elements[name]
end

local function clear_elements()
    for k in pairs(elements) do
        elements[k] = nil
    end
    for i = #elements, 1, -1 do
        elements[i] = nil
    end
end

-- Export table
M.user_opts             = user_opts
M.state                 = state
M.osc_param             = osc_param
M.osc_styles            = osc_styles
M.icons                 = icons
M.jumpicons             = jumpicons
M.language              = language
M.texts                 = texts
M.elements              = elements
M.thumbfast             = thumbfast
M.set_thumbfast         = set_thumbfast

M.clear_elements        = clear_elements
M.validate_user_opts    = validate_user_opts
M.get_virt_scale_factor = get_virt_scale_factor
M.get_virt_mouse_pos    = get_virt_mouse_pos
M.set_virt_mouse_area   = set_virt_mouse_area
M.scale_value           = scale_value
M.limit_range           = limit_range
M.countone              = countone
M.mult_alpha            = mult_alpha
M.add_area              = add_area
M.get_hitbox_coords     = get_hitbox_coords
M.get_hitbox_coords_geo = get_hitbox_coords_geo
M.get_element_hitbox    = get_element_hitbox
M.mouse_hit_coords      = mouse_hit_coords
M.mouse_hit             = mouse_hit
M.ass_append_alpha      = ass_append_alpha
M.ass_draw_cir_cw       = ass_draw_cir_cw
M.ass_draw_rr_h_cw      = ass_draw_rr_h_cw
M.ass_draw_rr_h_ccw     = ass_draw_rr_h_ccw
M.new_element           = new_element

return M
