-- ============================================================================
-- ModernH Module: Screensaver
-- Infuse / Apple TV style TMDB rich metadata pause screensaver with 3-tier cinema layout
-- ============================================================================

local assdraw = require('mp.assdraw')
local utils   = require('mp.utils')

local M = {}

local user_opts    = {}
local state        = {}
local hide_osc     = function() end
local show_osc     = function() end
local request_tick = function() end
local utils_mod    = nil

local function tmdb_parse_title()
    if utils_mod and utils_mod.parse_clean_title then
        local fn = mp.get_property('filename')
        local mt = mp.get_property('media-title')
        local fp = mp.get_property('path')

        -- 1. Try clean filename-derived title first (avoids leftover/junk metadata tags)
        local fn_show, fn_s, fn_e, fn_yr = utils_mod.parse_clean_title(nil, fn, fp)
        if fn_show and fn_show ~= '' and (fn_yr or (fn_s and fn_e)) then
            return fn_show, fn_s, fn_e, fn_yr
        end

        -- 2. If filename has no year/season, check if media-title provides a clean title
        if mt and mt ~= '' and mt ~= fn and not (utils_mod.is_junk_title and utils_mod.is_junk_title(mt)) then
            local mt_show, mt_s, mt_e, mt_yr = utils_mod.parse_clean_title(mt, fn, fp)
            if mt_show and mt_show ~= '' then
                return mt_show, mt_s, mt_e, mt_yr
            end
        end

        -- 3. Fallback to clean filename title even without year, or media-title
        if fn_show and fn_show ~= '' then
            return fn_show, fn_s, fn_e, fn_yr
        end
        return utils_mod.parse_clean_title(mt, fn, fp)
    end
    return mp.get_property('filename') or '', nil, nil, nil
end

local function collect_media_badges()
    if utils_mod and utils_mod.collect_media_badges then
        return utils_mod.collect_media_badges()
    end
    return {}
end

local function calc_badges_width(badges, badge_h)
    if utils_mod and utils_mod.calc_badges_width then
        return utils_mod.calc_badges_width(badges, badge_h)
    end
    return 0
end

local function draw_badges_ltr(ass, badges, start_x, cy, badge_h, alpha)
    if utils_mod and utils_mod.draw_badges_ltr then
        return utils_mod.draw_badges_ltr(ass, badges, start_x, cy, badge_h, alpha)
    end
    return start_x
end

local ss_overlay        = mp.create_osd_overlay('ass-events')
local ss_delay_timer    = nil    -- fires after SCREENSAVER_DELAY to start fade-in
local ss_fade_timer     = nil    -- drives fade-in animation
local ss_fade_out_timer = nil    -- drives smooth fade-out animation
local ss_clock_timer    = nil    -- periodic timer to keep "Ends" time live in real-time
local ss_last_ends_t    = nil    -- tracks current formatted ends time to avoid redundant redraws
local ss_fade_start     = 0
local SS_FADE_DUR       = 0.40   -- fade-in duration
local SS_OUT_DUR        = 0.16   -- smooth fade-out duration (160ms)
local ss_alpha          = 255    -- current overlay alpha (255=invisible, 0=opaque)
local ss_overlay_logo   = false  -- whether hardware overlay 1 is currently active
local ss_hiding         = false

-- TMDB metadata cache (keyed by media-title)
local tmdb_cache = {}
local tmdb_current = nil   -- cached result for current file
local tmdb_fetching = false
local tmdb_debounce_timer = nil

-- Subprocess lifecycle tracking & cancellation
local active_subprocesses = {}

local function abort_all_subprocesses()
    for handle, _ in pairs(active_subprocesses) do
        pcall(mp.abort_async_command, handle)
    end
    active_subprocesses = {}
    tmdb_fetching = false
end

local function safe_async_cmd(cmd_tbl, callback)
    if not (mp and mp.command_native_async) then return nil end
    if cmd_tbl.playback_only == nil then
        cmd_tbl.playback_only = false
    end
    local handle
    local finished = false
    handle = mp.command_native_async(cmd_tbl, function(ok, res, err)
        finished = true
        if handle then
            active_subprocesses[handle] = nil
        end
        if callback then
            callback(ok, res, err)
        end
    end)
    if handle and not finished then
        active_subprocesses[handle] = handle
    end
    return handle
end

-- ── helpers ──────────────────────────────────────────────────────────────────

local function ss_remove_logo()
    pcall(mp.commandv, 'overlay-remove', 1)
    ss_overlay_logo = false
end

local function estimate_meta_width(meta_str, fs)
    fs = fs or 16
    local scale = fs / 16.0
    local w = 0
    local in_tag = false
    local i = 1
    while i <= #meta_str do
        local b = meta_str:byte(i)
        if b == 123 then
            in_tag = true
        elseif b == 125 then
            in_tag = false
        elseif not in_tag then
            if b < 128 then
                local c = meta_str:sub(i, i)
                if c:find('[ijl|1:.,! ]') then
                    w = w + 4.8
                elseif c:find('[frt%-%s]') then
                    w = w + 6.2
                elseif c:find('[mwMW]') then
                    w = w + 13.0
                elseif c:find('[%u%d]') then
                    w = w + 9.8
                else
                    w = w + 8.4
                end
            elseif b == 0xC2 and meta_str:byte(i+1) == 0xB7 then
                w = w + 8.0
                i = i + 1
            elseif b == 0xE2 and meta_str:byte(i+1) == 0x98 and meta_str:byte(i+2) == 0x85 then
                w = w + 16.5
                i = i + 2
            else
                w = w + 9.0
            end
        end
        i = i + 1
    end
    return math.floor(w * scale)
end

local function format_currency(n)
    if not n or n <= 0 then return nil end
    local s = tostring(math.floor(n))
    local formatted = s:reverse():gsub('(%d%d%d)', '%1,'):reverse():gsub('^,', '')
    return '$' .. formatted
end

local function format_date(d_str)
    if not d_str or d_str == '' then return nil end
    local y, m, d = d_str:match('(%d%d%d%d)%-(%d%d)%-(%d%d)')
    if not y or not m or not d then return d_str end
    local months = {'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'}
    local m_idx = tonumber(m)
    local m_name = months[m_idx] or m
    return string.format('%s %d, %s', m_name, tonumber(d), y)
end

local function format_ends_time(duration_min)
    local rem = mp.get_property_number('playtime-remaining')
    if not rem or rem <= 0 or rem ~= rem then
        rem = (duration_min and duration_min > 0 and duration_min == duration_min) and (duration_min * 60) or 0
    end
    if rem > 0 and rem < 8640000 then
        local ok, res = pcall(function()
            local end_t = os.time() + math.floor(rem)
            local h = tonumber(os.date('%H', end_t))
            local m = os.date('%M', end_t)
            local ampm = (h and h >= 12) and 'PM' or 'AM'
            local h12 = (h and h % 12) or 12
            if h12 == 0 then h12 = 12 end
            return string.format('%d:%s %s', h12, m, ampm)
        end)
        if ok and res then return res end
    end
    return nil
end

local function render_screensaver(alpha)
    -- alpha: 0=fully opaque, 255=fully transparent (ASS convention)
    if alpha >= 255 or (state and state.menu_active) then
        ss_overlay:remove()
        ss_remove_logo()
        return
    end

    local osd_w, osd_h = mp.get_osd_size()
    osd_w = (osd_w and osd_w > 0) and osd_w or 1920
    osd_h = (osd_h and osd_h > 0) and osd_h or 1080

    local aspect = osd_w / osd_h
    local VIRTUAL_H = 1080
    local VIRTUAL_W = math.max(640, math.floor(VIRTUAL_H * aspect))
    local scale_x = osd_w / VIRTUAL_W
    local scale_y = osd_h / VIRTUAL_H

    -- 3-Tier Responsive Architecture
    local tier = 2
    if osd_w < 1150 or aspect < 1.25 then
        tier = 1 -- Compact / Tiled Mode
    elseif osd_w >= 1800 and aspect >= 1.25 then
        tier = 3 -- Cinematic Large (Fullscreen, Pic 2)
    else
        tier = 2 -- Normal Windowed Mode
    end

    local align_mode = user_opts.screensaver_align or 'center'
    local is_center = (align_mode == 'center')
    local is_split  = (align_mode == 'split')

    local margin_x, cur_y, badge_h
    local show_fs, ep_fs, tag_fs, meta_fs, gen_fs, ov_fs, ov_lh, ov_max_chars, dir_fs

    if tier == 1 then
        margin_x     = 50
        cur_y        = 190
        show_fs      = 28
        ep_fs        = 20
        tag_fs       = 14
        meta_fs      = 13
        badge_h      = 18
        gen_fs       = 11
        ov_fs        = 13
        ov_lh        = 18
        ov_max_chars = 44
        dir_fs       = 11
    elseif tier == 3 then
        margin_x     = 120
        cur_y        = 280
        show_fs      = 46
        ep_fs        = 30
        tag_fs       = 18
        meta_fs      = 19
        badge_h      = 26
        gen_fs       = 15
        ov_fs        = 16
        ov_lh        = 24
        ov_max_chars = 76
        dir_fs       = 14
    else -- tier == 2
        margin_x     = 90
        cur_y        = 260
        show_fs      = 36
        ep_fs        = 24
        tag_fs       = 16
        meta_fs      = 16
        badge_h      = 22
        gen_fs       = 13
        ov_fs        = 15
        ov_lh        = 22
        ov_max_chars = 64
        dir_fs       = 13
    end

    local a_hex = string.format('%02X', alpha)
    local ass = assdraw.ass_new()

    -- 1. Full-screen cinematic dark wash scrim (~92% opaque black, pristine obsidian backdrop)
    local scrim_alpha = math.floor(255 - (255 - 0x14) * (1 - alpha / 255))
    local scrim_hex = string.format('%02X', scrim_alpha)
    ass:new_event()
    ass:pos(0, 0)
    ass:an(7)
    ass:append(string.format('{\\blur0\\bord0\\shad0\\1c&H000000&\\1a&H%s&}', scrim_hex))
    ass:draw_start()
    ass:rect_cw(0, 0, VIRTUAL_W, VIRTUAL_H)
    ass:draw_stop()

    -- 2. Data extraction
    local td = tmdb_current
    local show_name = td and td.show_name or (function()
        local raw = (mp.get_property('media-title') or mp.get_property('filename') or '')
            :gsub('%.', ' '):gsub('_', ' '):gsub('%b[]', '')
        local sn = raw:match('^(.-)[%s]-[Ss]%d+[Ee]%d+') or raw:match('^(.-[%a]) %d%d%d%d') or raw
        return sn:gsub('[%s%-]+$', ''):sub(1, 45)
    end)()
    local ep_title     = td and td.ep_title     or ''
    local tagline      = td and td.tagline      or ''
    local genres       = td and td.genres       or ''
    local director     = td and td.director     or ''
    local year_str     = td and td.year         or ''
    local duration_str = td and td.duration     or ''
    local rating_str   = td and td.rating       or ''
    local cert_str     = td and td.cert         or ''
    local season_ep    = td and td.season_ep    or (function()
        local s, e = (mp.get_property('media-title') or ''):match('[Ss](%d+)[Ee](%d+)')
        return (s and e) and string.format('S%02d E%02d', tonumber(s), tonumber(e)) or ''
    end)()
    local overview     = td and td.overview     or ''

    -- 3. Logo or Fallback Text Title
    local logo_info = nil
    if td then
        if td.logos and td.logos[tier] then
            logo_info = td.logos[tier]
        elseif td.bgra_path and utils.file_info(td.bgra_path) then
            logo_info = {path = td.bgra_path, w = td.logo_w or 520, h = td.logo_h or 134, is_backdrop = td.is_backdrop}
        end
    end

    -- Overview text wrapping pre-calculation
    local words = {}
    if overview ~= '' then
        for word in overview:gmatch('%S+') do table.insert(words, word) end
    end
    local lines = {}
    local cur_l = ''
    local max_lines = (tier == 1) and 2 or 3
    local effective_max_chars = is_center and (tier == 1 and 48 or (tier == 3 and 78 or 64)) or ov_max_chars
    for _, word in ipairs(words) do
        if #lines < (max_lines - 1) then
            if cur_l == '' then
                cur_l = word
            elseif #cur_l + 1 + #word <= effective_max_chars then
                cur_l = cur_l .. ' ' .. word
            else
                table.insert(lines, cur_l)
                cur_l = word
            end
        else
            if #cur_l + 1 + #word <= effective_max_chars + 10 then
                cur_l = cur_l .. ' ' .. word
            else
                if not cur_l:match('%.%.%.$') then cur_l = cur_l .. '...' end
                break
            end
        end
    end
    if cur_l ~= '' and #lines < max_lines then
        table.insert(lines, cur_l)
    end
    local ov_wrapped = table.concat(lines, '\\N')

    -- Info Card Rows pre-calculation
    local rows = {}
    if VIRTUAL_W >= 850 then
        if td then
            local dur = (duration_str ~= '' and duration_str) or (td.runtime_min and (td.runtime_min .. 'm')) or ''
            local ends_t = format_ends_time(td.runtime_min)
            local rt_val = dur
            if ends_t then
                ss_last_ends_t = ends_t
                rt_val = (dur ~= '' and (dur .. ' • ') or '') .. 'Ends ' .. ends_t
            end
            if rt_val ~= '' then
                table.insert(rows, {label = 'Runtime', val = rt_val})
            end

            local lang_code = (td.language or 'en'):upper()
            table.insert(rows, {label = 'Language', val = lang_code})

            local rel_d = format_date(td.release_date)
            if rel_d then
                table.insert(rows, {label = 'Release Date', val = rel_d})
            end

            if tier >= 2 then
                local b_str = format_currency(td.budget)
                if b_str then
                    table.insert(rows, {label = 'Budget', val = b_str})
                end
                local r_str = format_currency(td.revenue)
                if r_str then
                    table.insert(rows, {label = 'Revenue', val = r_str})
                end

                if #rows < 4 and td.seasons_count then
                    local s_txt = td.seasons_count .. (td.seasons_count == 1 and ' Season' or ' Seasons')
                    if td.episodes_count then s_txt = s_txt .. ' (' .. td.episodes_count .. ' Ep)' end
                    table.insert(rows, {label = 'Seasons', val = s_txt})
                end
                if #rows < 5 and td.status and td.status ~= '' then
                    table.insert(rows, {label = 'Status', val = td.status})
                end
                if #rows < 5 and td.network and td.network ~= '' then
                    table.insert(rows, {label = 'Network', val = td.network})
                end
            end
        else
            -- Offline / No-TMDB Ambient Info Card
            local curr_path = mp.get_property('path', '')
            local is_stream = (utils_mod and utils_mod.is_url and utils_mod.is_url(curr_path))
                or (curr_path:find('^%a[%w+.-]*://') ~= nil)
                or (curr_path:find('^ytdl://') ~= nil)
                or (curr_path:find('^magnet:') ~= nil)
            if is_stream then
                local domain = curr_path:match('^%a[%w+.-]*://([^/]+)') or 'Stream'
                table.insert(rows, {label = 'Source', val = domain:gsub('^www%.', '')})
            end
            local d = mp.get_property_number('duration', 0)
            local ends_t = format_ends_time(d > 0 and math.floor(d / 60) or nil)
            local dur_str = (d > 0) and (mp.format_time(d) or (utils.format_time and utils.format_time(d)) or '') or ''
            if ends_t then
                ss_last_ends_t = ends_t
                table.insert(rows, {label = 'Runtime', val = (dur_str ~= '' and (dur_str .. ' • ') or '') .. 'Ends ' .. ends_t})
            elseif dur_str ~= '' then
                table.insert(rows, {label = 'Duration', val = dur_str})
            elseif is_stream then
                table.insert(rows, {label = 'Stream', val = 'Live Stream'})
            end

            local ac = mp.get_property('audio-codec-name')
            local ch = mp.get_property('audio-params/channel-count') or mp.get_property('audio-params/channels')
            if ac then
                local a_info = ac:upper() .. (ch and (' ' .. ch .. 'ch') or '')
                table.insert(rows, {label = 'Audio', val = a_info})
            end

            local w = mp.get_property_number('width')
            local h = mp.get_property_number('height')
            if w and h and w > 0 and h > 0 then
                local res_label = (w >= 3800 or h >= 2100) and '4K UHD' or ((w >= 1900 or h >= 1000) and '1080p FHD' or (h .. 'p'))
                table.insert(rows, {label = 'Quality', val = res_label})
            end
        end
    end

    -- Symmetrical Vertical & Horizontal Positioning
    if is_center then
        local est_h = 0
        if logo_info and logo_info.path and utils.file_info(logo_info.path) then
            est_h = est_h + math.floor(logo_info.h / scale_y) + (tier == 1 and 14 or 20)
            if logo_info.is_backdrop then
                est_h = est_h + math.floor(show_fs * 1.35) + 6
            end
        else
            est_h = est_h + math.floor(show_fs * 1.35) + 6
        end
        if ep_title ~= '' then
            est_h = est_h + math.floor(ep_fs * 1.35) + 8
        elseif tagline ~= '' then
            est_h = est_h + math.floor(tag_fs * 1.4) + 8
        end
        est_h = est_h + math.max(badge_h + 8, math.floor(meta_fs * 1.5) + 6)
        if genres ~= '' then
            est_h = est_h + math.floor(gen_fs * 1.4) + 6
        end
        if #lines > 0 then
            est_h = est_h + (#lines * ov_lh) + 12
        end
        if director ~= '' then
            est_h = est_h + math.floor(dir_fs * 1.4) + 14
        end
        if #rows > 0 then
            local row_h = (tier == 3) and 42 or ((tier == 2) and 36 or 30)
            local card_h = (#rows * row_h) + 16
            est_h = est_h + card_h + 16
        end
        cur_y = math.max(40, math.floor((VIRTUAL_H - est_h) / 2))
    elseif is_split then
        local max_container_w = (tier == 3) and 1320 or 1080
        local container_w = math.min(VIRTUAL_W - 80, max_container_w)
        margin_x = math.floor((VIRTUAL_W - container_w) / 2)
    end
    local start_cur_y = cur_y

    -- Render Logo or Title
    if logo_info and logo_info.path and utils.file_info(logo_info.path) then
        if alpha < 120 then
            local actual_w = logo_info.w
            local actual_h = logo_info.h
            local actual_x
            if is_center then
                actual_x = math.floor((osd_w - actual_w) / 2)
            else
                actual_x = math.floor(margin_x * scale_x)
            end
            local actual_y = math.floor(cur_y * scale_y)
            pcall(mp.commandv, 'overlay-add', 1, actual_x, actual_y, logo_info.path, 0, 'bgra', actual_w, actual_h, actual_w * 4)
            ss_overlay_logo = true
        else
            ss_remove_logo()
        end
        cur_y = cur_y + math.floor(logo_info.h / scale_y) + (tier == 1 and 14 or 20)

        if logo_info.is_backdrop then
            ass:new_event()
            if is_center then
                ass:pos(VIRTUAL_W / 2, cur_y)
                ass:an(8)
            else
                ass:pos(margin_x, cur_y)
                ass:an(7)
            end
            ass:append(string.format(
                '{\\fnInter\\b700\\fs%d\\1c&HFFFFFF&\\1a&H%s&\\bord0\\shad1\\4c&H000000&\\4a&H80&\\q2}',
                show_fs, a_hex))
            ass:append(show_name)
            cur_y = cur_y + math.floor(show_fs * 1.35) + 6
        end
    else
        ss_remove_logo()
        ass:new_event()
        if is_center then
            ass:pos(VIRTUAL_W / 2, cur_y)
            ass:an(8)
        else
            ass:pos(margin_x, cur_y)
            ass:an(7)
        end
        ass:append(string.format(
            '{\\fnInter\\b700\\fs%d\\1c&HFFFFFF&\\1a&H%s&\\bord0\\shad1\\4c&H000000&\\4a&H80&\\q2}',
            show_fs, a_hex))
        ass:append(show_name)
        cur_y = cur_y + math.floor(show_fs * 1.35) + 6
    end

    -- 4. Episode Title (TV) or Tagline (Movie)
    if ep_title ~= '' then
        ass:new_event()
        if is_center then
            ass:pos(VIRTUAL_W / 2, cur_y)
            ass:an(8)
        else
            ass:pos(margin_x, cur_y)
            ass:an(7)
        end
        ass:append(string.format(
            '{\\fnInter\\b700\\fs%d\\1c&HFFFFFF&\\1a&H%s&\\bord0\\shad0\\q2}', ep_fs, a_hex))
        ass:append(ep_title)
        cur_y = cur_y + math.floor(ep_fs * 1.35) + 8
    elseif tagline ~= '' then
        ass:new_event()
        if is_center then
            ass:pos(VIRTUAL_W / 2, cur_y)
            ass:an(8)
        else
            ass:pos(margin_x, cur_y)
            ass:an(7)
        end
        ass:append(string.format(
            '{\\fnInter\\b400\\i1\\fs%d\\1c&H9E9EA8&\\1a&H%s&\\bord0\\shad0\\q2}', tag_fs, a_hex))
        ass:append('“' .. tagline .. '”')
        cur_y = cur_y + math.floor(tag_fs * 1.4) + 8
    end

    -- 5. Metadata Row: 2026 · 1h 48m · ★ 6.7   [PG-13] [1080P] [5.1]
    local meta_text_parts = {}
    if year_str ~= '' then table.insert(meta_text_parts, year_str) end
    if duration_str ~= '' then table.insert(meta_text_parts, duration_str) end
    if rating_str ~= '' then
        table.insert(meta_text_parts, string.format('{\\1c&H30D5FF&}★{\\1c&HE5E5EA&} %s', rating_str))
    end
    if season_ep ~= '' then table.insert(meta_text_parts, season_ep) end

    local meta_line = table.concat(meta_text_parts, '  ·  ')

    -- Badges: Certification pill + Media codec badges (inline with tight gap)
    local inline_badges = {}
    if cert_str ~= '' then
        table.insert(inline_badges, {text = cert_str, fg = 'D8D8E0', bg = '242220', bord = '554E48', w = #cert_str * 8})
    end
    local media_badges = collect_media_badges()
    for _, mb in ipairs(media_badges) do
        table.insert(inline_badges, mb)
    end

    local meta_w = (meta_line ~= '') and estimate_meta_width(meta_line, meta_fs) or 0
    local badges_w = calc_badges_width(inline_badges, badge_h)
    local row_gap = (meta_w > 0 and badges_w > 0) and (tier == 1 and 12 or 16) or 0
    local total_row_w = meta_w + row_gap + badges_w

    local meta_start_x
    local badges_start_x
    if is_center then
        meta_start_x = math.floor((VIRTUAL_W - total_row_w) / 2)
        badges_start_x = meta_start_x + meta_w + row_gap
    else
        meta_start_x = margin_x
        badges_start_x = margin_x + meta_w + row_gap
    end

    if meta_line ~= '' then
        ass:new_event()
        ass:pos(meta_start_x, cur_y)
        ass:an(7)
        ass:append(string.format(
            '{\\fnInter\\b600\\fs%d\\1c&HDADADA&\\1a&H%s&\\bord0\\shad0}', meta_fs, a_hex))
        ass:append(meta_line)
    end

    if #inline_badges > 0 then
        local cy_badge = cur_y + math.floor(meta_fs * 0.62)
        draw_badges_ltr(ass, inline_badges, badges_start_x, cy_badge, badge_h, a_hex)
    end
    cur_y = cur_y + math.max(badge_h + 8, math.floor(meta_fs * 1.5) + 6)

    -- 6. Genres (if available from TMDB)
    if genres ~= '' then
        ass:new_event()
        if is_center then
            ass:pos(VIRTUAL_W / 2, cur_y)
            ass:an(8)
        else
            ass:pos(margin_x, cur_y)
            ass:an(7)
        end
        ass:append(string.format(
            '{\\fnInter\\b500\\fs%d\\1c&H787882&\\1a&H%s&\\bord0\\shad0\\fsp0.5}', gen_fs, a_hex))
        ass:append(genres)
        cur_y = cur_y + math.floor(gen_fs * 1.4) + 6
    end

    -- 7. Synopsis / Overview
    if #lines > 0 then
        ass:new_event()
        if is_center then
            ass:pos(VIRTUAL_W / 2, cur_y)
            ass:an(8)
        else
            ass:pos(margin_x, cur_y)
            ass:an(7)
        end
        ass:append(string.format(
            '{\\fnInter\\b400\\fs%d\\1c&HC8C4C0&\\1a&H%s&\\bord0\\shad0\\lh%d\\q2}',
            ov_fs, a_hex, ov_lh))
        ass:append(ov_wrapped)
        cur_y = cur_y + (#lines * ov_lh) + 12
    end

    -- 8. Director / Creator (Elevated contrast: refined slate gray)
    if director ~= '' then
        ass:new_event()
        if is_center then
            ass:pos(VIRTUAL_W / 2, cur_y)
            ass:an(8)
        else
            ass:pos(margin_x, cur_y)
            ass:an(7)
        end
        ass:append(string.format(
            '{\\fnInter\\b500\\fs%d\\1c&HA5958E&\\1a&H%s&\\bord0\\shad0}', dir_fs, a_hex))
        ass:append('Directed by ' .. director)
        cur_y = cur_y + math.floor(dir_fs * 1.4) + 14
    end

    -- 9. Info Card (Runtime, Language, Release Date, Seasons, Status)
    if #rows > 0 then
        local card_w
        local card_x
        local card_y
        local row_h = (tier == 3) and 42 or ((tier == 2) and 36 or 30)
        local card_h = (#rows * row_h) + 16
        local r = 14
        local f_size = (tier == 3) and 14 or ((tier == 2) and 12 or 11)

        if is_center then
            card_w = (tier == 3) and 420 or ((tier == 2) and 360 or 280)
            card_x = math.floor((VIRTUAL_W - card_w) / 2)
            card_y = cur_y + 4
        elseif is_split then
            local max_container_w = (tier == 3) and 1320 or 1080
            local container_w = math.min(VIRTUAL_W - 80, max_container_w)
            card_w = (tier == 3) and 380 or ((tier == 2) and 320 or 250)
            card_x = margin_x + container_w - card_w
            card_y = start_cur_y
        else
            card_w = (tier == 3) and 380 or ((tier == 2) and 320 or 250)
            local max_container_w = (tier == 3) and 1320 or 1080
            card_x = math.min(VIRTUAL_W - margin_x - card_w, margin_x + max_container_w - card_w)
            card_y = start_cur_y
        end

        -- Card background pill (frosted obsidian with subtle specular border)
        ass:new_event()
        ass:pos(0, 0)
        ass:an(7)
        ass:append(string.format(
            '{\\blur0\\bord1\\1c&H121216&\\1a&H38&\\3c&H404048&\\3a&H60&}', a_hex))
        ass:draw_start()
        ass:round_rect_cw(card_x, card_y, card_x + card_w, card_y + card_h, r)
        ass:draw_stop()

        -- Hairline dividers between rows
        for i = 1, #rows - 1 do
            local dy = card_y + 8 + (i * row_h)
            ass:new_event()
            ass:pos(0, 0)
            ass:an(7)
            ass:append(string.format('{\\blur0\\bord0\\1c&H2E2E36&\\1a&H40&}', a_hex))
            ass:draw_start()
            ass:rect_cw(card_x + 14, dy, card_x + card_w - 14, dy + 1)
            ass:draw_stop()
        end

        -- Row labels & values
        local pad_x = (tier == 1) and 14 or 20
        for i, row in ipairs(rows) do
            local cy_row = card_y + 8 + ((i - 0.5) * row_h)

            -- Label (middle-left)
            ass:new_event()
            ass:pos(card_x + pad_x, cy_row)
            ass:an(4)
            ass:append(string.format(
                '{\\fnInter\\b500\\fs%d\\1c&H8E8E98&\\1a&H%s&\\bord0\\shad0}', f_size, a_hex))
            ass:append(row.label)

            -- Value (middle-right)
            ass:new_event()
            ass:pos(card_x + card_w - pad_x, cy_row)
            ass:an(6)
            ass:append(string.format(
                '{\\fnInter\\b600\\fs%d\\1c&HE5E5EA&\\1a&H%s&\\bord0\\shad0}', f_size, a_hex))
            ass:append(row.val)
        end
    end

    ss_overlay.res_x = VIRTUAL_W
    ss_overlay.res_y = VIRTUAL_H
    ss_overlay.data  = ass.text
    ss_overlay:update()
end

local function ss_schedule_next_minute()
    if not ss_active or ss_hiding then return end
    local now = os.time()
    -- Calculate seconds remaining until the exact top of the next minute (:00)
    local sec_to_next = 60 - (now % 60) + 0.2
    if sec_to_next < 1 then sec_to_next = 60.2 end
    if ss_clock_timer then ss_clock_timer:kill(); ss_clock_timer = nil end
    ss_clock_timer = mp.add_timeout(sec_to_next, function()
        if not ss_active or ss_hiding then return end
        local td = tmdb_current
        local ends_t = format_ends_time(td and td.runtime_min)
        if ends_t and ends_t ~= ss_last_ends_t then
            ss_last_ends_t = ends_t
            render_screensaver(ss_alpha)
        end
        ss_schedule_next_minute()
    end)
end

local function ss_fade_step()
    local t = (mp.get_time() - ss_fade_start) / SS_FADE_DUR
    if t >= 1.0 then
        ss_alpha = 0
        render_screensaver(0)
        if ss_fade_timer then ss_fade_timer:kill(); ss_fade_timer = nil end
        ss_schedule_next_minute()
        return
    end
    local ease = t * t
    ss_alpha = math.floor(255 * (1 - ease))
    render_screensaver(ss_alpha)
end

local function ss_fade_out_step()
    local t = (mp.get_time() - ss_fade_start) / SS_OUT_DUR
    if t >= 1.0 then
        if ss_clock_timer then ss_clock_timer:kill(); ss_clock_timer = nil end
        ss_last_ends_t = nil
        ss_active = false
        ss_hiding = false
        ss_overlay:remove()
        ss_remove_logo()
        pcall(mp.remove_key_binding, 'ss_esc_dismiss')
        if ss_fade_out_timer then ss_fade_out_timer:kill(); ss_fade_out_timer = nil end
        if user_opts.showonpause and mp.get_property_native('pause') then
            show_osc()
        end
        request_tick()
        return
    end
    local ease = t * t
    ss_alpha = math.floor(255 * ease)
    render_screensaver(ss_alpha)
end

ss_hide = function(immediate)
    if immediate then
        ss_remove_logo()
    end
    if not ss_active and not ss_delay_timer and not ss_hiding then return end
    if ss_delay_timer then ss_delay_timer:kill(); ss_delay_timer = nil end
    if ss_fade_timer  then ss_fade_timer:kill();  ss_fade_timer  = nil end
    if ss_clock_timer then ss_clock_timer:kill(); ss_clock_timer = nil end
    ss_last_ends_t = nil

    if immediate or not ss_active or not mp.get_property_native('pause') then
        if ss_fade_out_timer then ss_fade_out_timer:kill(); ss_fade_out_timer = nil end
        ss_active = false
        ss_hiding = false
        ss_overlay:remove()
        ss_remove_logo()
        pcall(mp.remove_key_binding, 'ss_esc_dismiss')
        if user_opts.showonpause and mp.get_property_native('pause') then
            show_osc()
        end
        request_tick()
        return
    end

    -- Smooth 160ms fade out when dismissed while remaining paused
    if not ss_hiding then
        ss_hiding = true
        ss_fade_start = mp.get_time()
        if ss_fade_out_timer then ss_fade_out_timer:kill() end
        ss_fade_out_timer = mp.add_periodic_timer(0.025, ss_fade_out_step)
    end
end

local is_menu_active_fn = nil

activate_screensaver = function()
    if not user_opts.screensaver_enabled then return end
    if ss_active and not ss_hiding then return end
    if not mp.get_property_native('pause') then return end
    if state.menu_active or menu_closing then return end
    if is_menu_active_fn and is_menu_active_fn() then return end
    hide_osc()
    if ss_clock_timer then ss_clock_timer:kill(); ss_clock_timer = nil end
    ss_last_ends_t = nil
    ss_active      = true
    ss_hiding      = false
    ss_fade_start  = mp.get_time()
    ss_alpha       = 255
    if ss_fade_timer then ss_fade_timer:kill() end
    if ss_fade_out_timer then ss_fade_out_timer:kill(); ss_fade_out_timer = nil end
    ss_fade_timer  = mp.add_periodic_timer(0.033, ss_fade_step)
    -- Intercept ESC to dismiss screensaver cleanly without exiting fullscreen
    pcall(mp.add_forced_key_binding, 'ESC', 'ss_esc_dismiss', function() ss_hide() end)
    request_tick()
end

-- ── TMDB fetch & logo processing ──────────────────────────────────────────────

local function tmdb_url_encode(s)
    if not s then return '' end
    return s:gsub('([^%w%-_%.])', function(c)
        return string.format('%%%02X', string.byte(c))
    end)
end

local function make_dir_sync(dir)
    if not dir or dir == '' then return false end
    local info = utils.file_info(dir)
    if info and info.is_dir then return true end

    local is_win = (package.config:sub(1, 1) == '\\')
    if mp and mp.command_native then
        if is_win then
            local win_dir = dir:gsub('/', '\\'):gsub('\\+$', '')
            pcall(mp.command_native, {name = 'subprocess', playback_only = false, capture_stdout = true, args = {'cmd.exe', '/d', '/c', 'if not exist "' .. win_dir .. '" mkdir "' .. win_dir .. '"'}})
        else
            pcall(mp.command_native, {name = 'subprocess', playback_only = false, capture_stdout = true, args = {'mkdir', '-p', dir}})
        end
    end
    info = utils.file_info(dir)
    if info and info.is_dir then return true end

    if is_win then
        local win_dir = dir:gsub('/', '\\'):gsub('\\+$', '')
        pcall(os.execute, 'mkdir "' .. win_dir .. '" 2>nul')
    else
        pcall(os.execute, 'mkdir -p "' .. dir .. '" 2>/dev/null')
    end
    info = utils.file_info(dir)
    return (info and info.is_dir) == true
end

local function is_dir_usable(dir)
    if not dir or dir == '' then return false end
    if not make_dir_sync(dir) then return false end
    local test_f = string.format('%s/.test_write_%d', dir, math.random(1000, 9999))
    local f = io.open(test_f, 'w')
    if f then
        f:write('1')
        f:close()
        os.remove(test_f)
        return true
    end
    return false
end

local function resolve_cache_dir()
    local is_win = (package.config:sub(1, 1) == '\\')
    local candidates = {}

    -- 1. mpv expanded cache dir
    if mp and mp.command_native then
        local p = mp.command_native({'expand-path', '~~cache/'})
        if p and p ~= '' and p ~= '~~cache/' then
            table.insert(candidates, p:gsub('[/\\]+$', '') .. '/luminax')
        end
    end

    -- 2. XDG_CACHE_HOME / ~/.cache
    local xdg = os.getenv('XDG_CACHE_HOME')
    if xdg and xdg ~= '' then
        table.insert(candidates, xdg:gsub('[/\\]+$', '') .. '/mpv/luminax')
    end
    local home = os.getenv('HOME')
    if home and home ~= '' then
        table.insert(candidates, home:gsub('[/\\]+$', '') .. '/.cache/mpv/luminax')
    end
    if is_win then
        local appdata = os.getenv('LOCALAPPDATA')
        if appdata and appdata ~= '' then
            table.insert(candidates, appdata:gsub('[/\\]+$', '') .. '/mpv/luminax')
        end
    end

    -- 3. System TMP / TEMP fallback (/tmp/mpv_luminax or %TEMP%/mpv_luminax)
    local tmp_base = os.getenv('TMPDIR') or (is_win and (os.getenv('TEMP') or os.getenv('TMP'))) or '/tmp'
    table.insert(candidates, tmp_base:gsub('[/\\]+$', '') .. '/mpv_luminax')

    for _, dir in ipairs(candidates) do
        if is_dir_usable(dir) then
            return dir
        end
    end

    local fallback = tmp_base:gsub('[/\\]+$', '') .. '/mpv_luminax'
    make_dir_sync(fallback)
    return fallback
end

local tmdb_disk_cache_dir = resolve_cache_dir()

local function ensure_cache_dir()
    if not is_dir_usable(tmdb_disk_cache_dir) then
        tmdb_disk_cache_dir = resolve_cache_dir()
    end
    return tmdb_disk_cache_dir
end

local function safe_cache_filename(key)
    return (key:gsub('[^%w%-_]', '_'))
end

local function purge_meta_from_disk(key)
    if not key then return end
    pcall(function()
        local cdir = ensure_cache_dir()
        local path = string.format('%s/meta_%s.json', cdir, safe_cache_filename(key))
        os.remove(path)
    end)
end

local function purge_logo_from_disk(show_id)
    if not show_id then return end
    pcall(function()
        local cdir = ensure_cache_dir()
        local prefix = string.format('logo_%d', show_id)
        local files = utils.readdir(cdir, 'files')
        if files then
            for _, fn in ipairs(files) do
                if fn:sub(1, #prefix) == prefix then
                    os.remove(cdir .. '/' .. fn)
                end
            end
        end
    end)
end

local function save_meta_to_disk(key, data)
    pcall(function()
        local cdir = ensure_cache_dir()
        local path = string.format('%s/meta_%s.json', cdir, safe_cache_filename(key))
        local f = io.open(path, 'w')
        if f then
            f:write(utils.format_json(data))
            f:close()
        end
    end)
end

local function load_meta_from_disk(key)
    local ok, res = pcall(function()
        local cdir = ensure_cache_dir()
        local path = string.format('%s/meta_%s.json', cdir, safe_cache_filename(key))
        local f = io.open(path, 'r')
        if not f then return nil end
        local content = f:read('*a')
        f:close()
        if not content or content == '' then return nil end
        local data = utils.parse_json(content)
        if not data or not data.show_name then return nil end
        if data.logos and data.logos[1] and not utils.file_info(data.logos[1].path) then
            return nil
        end
        return data
    end)
    return ok and res or nil
end

local function fetch_tmdb_logo(search_type, show_id, cb)
    local key = user_opts.tmdb_api_key
    if not key or key == '' then cb(nil); return end

    local cdir = ensure_cache_dir()
    local dims_file = string.format('%s/logo_%d_dims.json', cdir, show_id)

    if user_opts.tmdb_cache_lookup ~= false then
        local f_dims = io.open(dims_file, 'r')
        if f_dims then
            local c = f_dims:read('*a')
            f_dims:close()
            local d = utils.parse_json(c)
            if d and d.t1 and d.t2 and d.t3 then
                local t1_bgra = string.format('%s/logo_%d_t1_%dx%d.bgra', cdir, show_id, d.t1[1], d.t1[2])
                local t2_bgra = string.format('%s/logo_%d_t2_%dx%d.bgra', cdir, show_id, d.t2[1], d.t2[2])
                local t3_bgra = string.format('%s/logo_%d_t3_%dx%d.bgra', cdir, show_id, d.t3[1], d.t3[2])
                local f1 = utils.file_info(t1_bgra)
                local f2 = utils.file_info(t2_bgra)
                local f3 = utils.file_info(t3_bgra)
                if f1 and f1.size == (d.t1[1] * d.t1[2] * 4) and
                   f2 and f2.size == (d.t2[1] * d.t2[2] * 4) and
                   f3 and f3.size == (d.t3[1] * d.t3[2] * 4) then
                    local is_bd = (d.is_backdrop == true)
                    cb({
                        [1] = {path = t1_bgra, w = d.t1[1], h = d.t1[2]},
                        [2] = {path = t2_bgra, w = d.t2[1], h = d.t2[2]},
                        [3] = {path = t3_bgra, w = d.t3[1], h = d.t3[2]},
                    }, is_bd)
                    return
                end
            end
        end
    end

    local images_url = string.format(
        'https://api.tmdb.org/3/%s/%d/images?api_key=%s',
        search_type, show_id, key
    )
    safe_async_cmd({
        name = 'subprocess',
        args = {'curl', '-s', '-4', '--connect-timeout', '3', '--retry', '3', '--retry-all-errors', '--max-time', '8', images_url},
        capture_stdout = true,
    }, function(ok, res)
        if not ok or not res or not res.stdout or res.stdout == '' then
            cb(nil)
            return
        end
        local img_data = utils.parse_json(res.stdout)
        if not img_data then
            cb(nil)
            return
        end

        local candidates = {}
        local is_backdrop = false

        if img_data.logos and #img_data.logos > 0 then
            for _, logo in ipairs(img_data.logos) do
                local lw = logo.width or 0
                local lh = logo.height or 0
                if lw <= 6000 and lh >= 40 then
                    table.insert(candidates, logo)
                end
            end
            if #candidates == 0 then candidates = img_data.logos end
        end

        if #candidates > 0 then
            table.sort(candidates, function(a, b)
                local a_en = (a.iso_639_1 == 'en')
                local b_en = (b.iso_639_1 == 'en')
                if a_en ~= b_en then return a_en end

                local ar_a = a.aspect_ratio or (a.width and a.height and a.height > 0 and (a.width / a.height)) or 0
                local ar_b = b.aspect_ratio or (b.width and b.height and b.height > 0 and (b.width / b.height)) or 0
                local a_wide = (ar_a >= 4.0)
                local b_wide = (ar_b >= 4.0)
                if a_wide ~= b_wide then return a_wide end

                local a_us = (a.iso_3166_1 == 'US')
                local b_us = (b.iso_3166_1 == 'US')
                if a_us ~= b_us then return a_us end

                local a_vote = a.vote_average or 0
                local b_vote = b.vote_average or 0
                if a_vote ~= b_vote then return a_vote > b_vote end

                return ar_a > ar_b
            end)
        else
            -- Rich Fallback: When movie has no transparent logo on TMDB, use high-resolution backdrop or poster!
            if img_data.backdrops and #img_data.backdrops > 0 then
                is_backdrop = true
                candidates = img_data.backdrops
            elseif img_data.posters and #img_data.posters > 0 then
                is_backdrop = true
                candidates = img_data.posters
            else
                cb(nil)
                return
            end
        end

        local chosen_path = candidates[1] and candidates[1].file_path
        if not chosen_path or chosen_path == '' then
            cb(nil)
            return
        end

        local dl_url = 'https://image.tmdb.org/t/p/w780' .. chosen_path
        local png_tmp = string.format('%s/logo_%d.png', cdir, show_id)

        safe_async_cmd({
            name = 'subprocess',
            args = {'curl', '-s', '-4', '--connect-timeout', '3', '--retry', '3', '--retry-all-errors', '--max-time', '10', dl_url, '-o', png_tmp},
        }, function(ok_dl, res_dl)
            if not ok_dl or not res_dl or (res_dl.status and res_dl.status ~= 0) then cb(nil); return end
            local finfo = utils.file_info(png_tmp)
            if not finfo or not finfo.size or finfo.size <= 0 then cb(nil); return end
        local chosen_logo = candidates[1]
        local chosen_w = (chosen_logo and chosen_logo.width and chosen_logo.width > 0) and chosen_logo.width or 600
        local chosen_h = (chosen_logo and chosen_logo.height and chosen_logo.height > 0) and chosen_logo.height or 150

        local function calc_tier(max_w, max_h, ow, oh)
            local scale = math.min(max_w / ow, max_h / oh)
            local w = math.max(2, math.floor(ow * scale + 0.5))
            local h = math.max(2, math.floor(oh * scale + 0.5))
            if w % 2 ~= 0 then w = w - 1 end
            if h % 2 ~= 0 then h = h - 1 end
            return w, h
        end

        local function process_logo_ffmpeg(img_path, ow, oh, cb_ff)
            local max_w1, max_h1 = is_backdrop and 320 or 380, is_backdrop and 180 or 98
            local max_w2, max_h2 = is_backdrop and 460 or 520, is_backdrop and 260 or 134
            local max_w3, max_h3 = is_backdrop and 580 or 680, is_backdrop and 326 or 175

            local t1_w, t1_h = calc_tier(max_w1, max_h1, ow, oh)
            local t2_w, t2_h = calc_tier(max_w2, max_h2, ow, oh)
            local t3_w, t3_h = calc_tier(max_w3, max_h3, ow, oh)

            local d = {
                is_backdrop = is_backdrop,
                t1 = {t1_w, t1_h},
                t2 = {t2_w, t2_h},
                t3 = {t3_w, t3_h}
            }
            local f_d = io.open(dims_file, 'w')
            if f_d then
                f_d:write(utils.format_json(d))
                f_d:close()
            end

            local t1_bgra = string.format('%s/logo_%d_t1_%dx%d.bgra', cdir, show_id, t1_w, t1_h)
            local t2_bgra = string.format('%s/logo_%d_t2_%dx%d.bgra', cdir, show_id, t2_w, t2_h)
            local t3_bgra = string.format('%s/logo_%d_t3_%dx%d.bgra', cdir, show_id, t3_w, t3_h)

            local function run_scale_ffmpeg(pre_filter)
                local filter_str = string.format(
                    '[0:v]%ssplit=3[v1][v2][v3]; ' ..
                    '[v1]scale=%d:%d:flags=lanczos,premultiply=inplace=1,format=bgra[o1]; ' ..
                    '[v2]scale=%d:%d:flags=lanczos,premultiply=inplace=1,format=bgra[o2]; ' ..
                    '[v3]scale=%d:%d:flags=lanczos,premultiply=inplace=1,format=bgra[o3]',
                    pre_filter or '',
                    t1_w, t1_h,
                    t2_w, t2_h,
                    t3_w, t3_h
                )
                safe_async_cmd({
                    name = 'subprocess',
                    args = {
                        'ffmpeg', '-y', '-i', img_path,
                        '-filter_complex', filter_str,
                        '-map', '[o1]', '-f', 'rawvideo', t1_bgra,
                        '-map', '[o2]', '-f', 'rawvideo', t2_bgra,
                        '-map', '[o3]', '-f', 'rawvideo', t3_bgra,
                    },
                }, function(ok_ff, _)
                    if ok_ff and utils.file_info(t1_bgra) and utils.file_info(t2_bgra) and utils.file_info(t3_bgra) then
                        cb_ff({
                            [1] = {path = t1_bgra, w = t1_w, h = t1_h},
                            [2] = {path = t2_bgra, w = t2_w, h = t2_h},
                            [3] = {path = t3_bgra, w = t3_w, h = t3_h},
                        }, is_backdrop)
                    else
                        cb_ff(nil)
                    end
                end)
            end

            if is_backdrop then
                run_scale_ffmpeg('')
            else
                -- Fast luminance & saturation probe on non-transparent logo pixels
                safe_async_cmd({
                    name = 'subprocess',
                    args = {'ffmpeg', '-v', 'error', '-i', img_path, '-vf', 'scale=16:16,format=rgba', '-f', 'rawvideo', 'pipe:1'},
                    capture_stdout = true,
                }, function(ok_p, res_p)
                    local pre_filter = ''
                    if ok_p and res_p and res_p.stdout and #res_p.stdout >= 64 then
                        local raw = res_p.stdout
                        local total_lum, total_sat, count = 0, 0, 0
                        for i = 1, #raw, 4 do
                            local a = raw:byte(i + 3)
                            if a and a > 40 then
                                local r = raw:byte(i)
                                local g = raw:byte(i + 1)
                                local b = raw:byte(i + 2)
                                local max_c = math.max(r, g, b)
                                local min_c = math.min(r, g, b)
                                total_lum = total_lum + (0.299 * r + 0.587 * g + 0.114 * b)
                                total_sat = total_sat + (max_c - min_c)
                                count = count + 1
                            end
                        end
                        if count > 0 then
                            local avg_lum = total_lum / count
                            local avg_sat = total_sat / count
                            if avg_sat <= 28.0 and avg_lum < 65.0 then
                                pre_filter = 'negate,'
                            elseif avg_lum < 75.0 then
                                pre_filter = 'eq=brightness=0.25:contrast=1.1,'
                            end
                        end
                    end
                    run_scale_ffmpeg(pre_filter)
                end)
            end
        end

        local engine = user_opts.logo_engine or 'auto'
        if engine == 'ffmpeg' or engine == 'auto' or is_backdrop then
            process_logo_ffmpeg(png_tmp, chosen_w, chosen_h, cb)
        else
            process_logo_ffmpeg(png_tmp, chosen_w, chosen_h, cb)
        end
    end)
    end)
end

local last_parsed_title = nil

local function fetch_tmdb_data(force_refresh)
    local key = user_opts.tmdb_api_key
    if not key or key == '' then return end
    if tmdb_fetching then return end

    -- URL Guard: Skip TMDB searches on network streams (YouTube, Twitch, RTMP, etc.)
    local curr_path = mp.get_property('path', '')
    local is_url = (utils_mod and utils_mod.is_url and utils_mod.is_url(curr_path))
        or (curr_path:find('^%a[%w+.-]*://') ~= nil)
        or (curr_path:find('^ytdl://') ~= nil)
        or (curr_path:find('^magnet:') ~= nil)
    if is_url then return end

    local show, season, episode, parsed_year = tmdb_parse_title()
    if not show or show == '' then return end
    local cache_key = show .. '/' .. (season or '?') .. '/' .. (episode or '?') .. '/' .. (parsed_year or '?')

    if last_parsed_title and last_parsed_title ~= show then
        force_refresh = true
    end
    last_parsed_title = show

    if force_refresh or user_opts.tmdb_cache_lookup == false then
        if tmdb_current and tmdb_current.show_id then
            purge_logo_from_disk(tmdb_current.show_id)
        end
        if tmdb_current and tmdb_current.cache_key then
            purge_meta_from_disk(tmdb_current.cache_key)
        end
        purge_meta_from_disk(cache_key)
        tmdb_cache[cache_key] = nil
        tmdb_current = nil
        if ss_active then render_screensaver(ss_alpha) end
    else
        if tmdb_cache[cache_key] then
            tmdb_current = tmdb_cache[cache_key]
            if ss_active then render_screensaver(ss_alpha) end
            return
        end

        local disk_cached = load_meta_from_disk(cache_key)
        if disk_cached then
            tmdb_cache[cache_key] = disk_cached
            tmdb_current = disk_cached
            if ss_active then render_screensaver(ss_alpha) end
            if not disk_cached.bgra_path and disk_cached.show_id and not disk_cached.logo_retry then
                disk_cached.logo_retry = true
                local is_tv = (disk_cached.season_ep and disk_cached.season_ep ~= '')
                local search_type = is_tv and 'tv' or 'movie'
                fetch_tmdb_logo(search_type, disk_cached.show_id, function(logos_tbl, is_bd)
                    if logos_tbl then
                        disk_cached.logos = logos_tbl
                        local def_logo = logos_tbl[2] or logos_tbl[1]
                        disk_cached.bgra_path = def_logo and def_logo.path
                        disk_cached.logo_w = def_logo and def_logo.w
                        disk_cached.logo_h = def_logo and def_logo.h
                        disk_cached.is_backdrop = (is_bd == true)
                        save_meta_to_disk(cache_key, disk_cached)
                        if ss_active then render_screensaver(ss_alpha) end
                    end
                end)
            end
            return
        end
    end

    tmdb_fetching = true

    local is_tv = (season ~= nil)
    local search_type = is_tv and 'tv' or 'movie'
    local search_url = string.format(
        'https://api.tmdb.org/3/search/%s?api_key=%s&query=%s%s&page=1',
        search_type,
        key,
        tmdb_url_encode(show),
        (not is_tv and parsed_year) and ('&year=' .. parsed_year) or ''
    )

    local function on_search_item(item)
        local show_id = item.id
        local year_raw = item.first_air_date or item.release_date or ''
        local year = year_raw:match('^(%d%d%d%d)') or parsed_year
        local rating = item.vote_average
        local rating_s = rating and string.format('%.1f', rating) or ''

        if not is_tv then
            -- Fetch rich movie details (runtime, certification, credits, tagline, genres, budget, revenue)
            local detail_url = string.format(
                'https://api.tmdb.org/3/movie/%d?api_key=%s&append_to_response=release_dates,credits',
                show_id, key
            )
            safe_async_cmd({
                name = 'subprocess',
                args = {'curl', '-s', '-4', '--connect-timeout', '3', '--retry', '3', '--retry-all-errors', '--max-time', '8', detail_url},
                capture_stdout = true,
            }, function(ok_det, res_det)
                local det = (ok_det and res_det and res_det.stdout) and utils.parse_json(res_det.stdout) or nil
                local dur_str = ''
                local cert = ''
                local genres_list = {}
                local director_str = ''
                if det then
                    if det.runtime and det.runtime > 0 then
                        local h_r = math.floor(det.runtime / 60)
                        local m_r = det.runtime % 60
                        dur_str = (h_r > 0 and (h_r .. 'h ') or '') .. m_r .. 'm'
                    end
                    if det.release_dates and det.release_dates.results then
                        for _, rd in ipairs(det.release_dates.results) do
                            if rd.iso_3166_1 == 'US' and rd.release_dates then
                                for _, c in ipairs(rd.release_dates) do
                                    if c.certification and c.certification ~= '' then
                                        cert = c.certification
                                        break
                                    end
                                end
                            end
                            if cert ~= '' then break end
                        end
                    end
                    if det.genres then
                        for _, g in ipairs(det.genres) do
                            if #genres_list < 3 then table.insert(genres_list, g.name) end
                        end
                    end
                    if det.credits and det.credits.crew then
                        for _, c in ipairs(det.credits.crew) do
                            if c.job == 'Director' then
                                director_str = c.name
                                break
                            end
                        end
                    end
                end

                local result = {
                    show_id      = show_id,
                    cache_key    = cache_key,
                    show_name    = (det and det.title) or item.title or show,
                    ep_title     = '',
                    tagline      = (det and det.tagline and det.tagline ~= '') and det.tagline or '',
                    genres       = table.concat(genres_list, '  ·  '),
                    director     = director_str,
                    year         = year or '',
                    duration     = dur_str,
                    rating       = rating_s,
                    cert         = cert,
                    season_ep    = '',
                    overview     = (det and det.overview or item.overview or ''):sub(1, 260),
                    bgra_path    = nil,
                    logo_w       = nil,
                    logo_h       = nil,
                    budget       = det and det.budget,
                    revenue      = det and det.revenue,
                    language     = (det and det.original_language) or item.original_language or 'en',
                    release_date = (det and det.release_date) or item.release_date or '',
                    runtime_min  = det and det.runtime,
                }
                tmdb_cache[cache_key] = result
                tmdb_current = result
                if ss_active then render_screensaver(ss_alpha) end

                fetch_tmdb_logo('movie', show_id, function(logos_tbl, is_bd)
                    tmdb_fetching = false
                    if logos_tbl then
                        result.logos = logos_tbl
                        local def_logo = logos_tbl[2] or logos_tbl[1]
                        result.bgra_path = def_logo and def_logo.path
                        result.logo_w = def_logo and def_logo.w
                        result.logo_h = def_logo and def_logo.h
                        result.is_backdrop = (is_bd == true)
                        if ss_active then render_screensaver(ss_alpha) end
                    end
                    save_meta_to_disk(cache_key, result)
                end)
            end)
            return
        end

        -- Fetch rich TV details (ratings, credits, tagline, genres) & episode details (runtime, title)
        local tv_detail_url = string.format(
            'https://api.tmdb.org/3/tv/%d?api_key=%s&append_to_response=content_ratings,credits',
            show_id, key
        )
        safe_async_cmd({
            name = 'subprocess',
            args = {'curl', '-s', '-4', '--connect-timeout', '3', '--retry', '3', '--retry-all-errors', '--max-time', '8', tv_detail_url},
            capture_stdout = true,
        }, function(ok_tv, res_tv)
            local tv_det = (ok_tv and res_tv and res_tv.stdout) and utils.parse_json(res_tv.stdout) or nil
            local cert = ''
            local genres_list = {}
            local director_str = ''
            if tv_det then
                if tv_det.content_ratings and tv_det.content_ratings.results then
                    for _, cr in ipairs(tv_det.content_ratings.results) do
                        if cr.iso_3166_1 == 'US' and cr.rating and cr.rating ~= '' then
                            cert = cr.rating
                            break
                        end
                    end
                end
                if tv_det.genres then
                    for _, g in ipairs(tv_det.genres) do
                        if #genres_list < 3 then table.insert(genres_list, g.name) end
                    end
                end
                if tv_det.created_by and #tv_det.created_by > 0 then
                    director_str = tv_det.created_by[1].name
                end
            end

            local ep_url = string.format(
                'https://api.tmdb.org/3/tv/%d/season/%d/episode/%d?api_key=%s',
                show_id, season, episode, key
            )
            safe_async_cmd({
                name = 'subprocess',
                args = {'curl', '-s', '-4', '--connect-timeout', '3', '--retry', '3', '--retry-all-errors', '--max-time', '8', ep_url},
                capture_stdout = true,
            }, function(ok2, res2)
                local ep = (ok2 and res2 and res2.stdout) and utils.parse_json(res2.stdout) or nil
                local dur_str = ''
                if ep and ep.runtime and ep.runtime > 0 then
                    dur_str = ep.runtime .. 'm'
                end

                local result = {
                    show_id        = show_id,
                    cache_key      = cache_key,
                    show_name      = (tv_det and tv_det.name) or item.name or show,
                    ep_title       = ep and (ep.name or '') or '',
                    tagline        = (tv_det and tv_det.tagline and tv_det.tagline ~= '') and tv_det.tagline or '',
                    genres         = table.concat(genres_list, '  ·  '),
                    director       = director_str,
                    year           = year or '',
                    duration       = dur_str,
                    rating         = rating_s,
                    cert           = cert,
                    season_ep      = string.format('S%02d E%02d', season, episode),
                    overview       = ep and ((ep.overview or ''):sub(1, 260)) or ((tv_det and tv_det.overview or item.overview or ''):sub(1, 260)),
                    bgra_path      = nil,
                    logo_w         = nil,
                    logo_h         = nil,
                    language       = (tv_det and tv_det.original_language) or item.original_language or 'en',
                    release_date   = (tv_det and tv_det.first_air_date) or item.first_air_date or '',
                    seasons_count  = tv_det and tv_det.number_of_seasons,
                    episodes_count = tv_det and tv_det.number_of_episodes,
                    status         = tv_det and tv_det.status,
                    network        = (tv_det and tv_det.networks and tv_det.networks[1] and tv_det.networks[1].name) or nil,
                }
                tmdb_cache[cache_key] = result
                tmdb_current = result
                if ss_active then render_screensaver(ss_alpha) end

                fetch_tmdb_logo('tv', show_id, function(logos_tbl, is_bd)
                    tmdb_fetching = false
                    if logos_tbl then
                        result.logos = logos_tbl
                        local def_logo = logos_tbl[2] or logos_tbl[1]
                        result.bgra_path = def_logo and def_logo.path
                        result.logo_w = def_logo and def_logo.w
                        result.logo_h = def_logo and def_logo.h
                        result.is_backdrop = (is_bd == true)
                        if ss_active then render_screensaver(ss_alpha) end
                    end
                    save_meta_to_disk(cache_key, result)
                end)
            end)
        end)
    end

    local function handle_search_results(data)
        if not data or not data.results or #data.results == 0 then
            -- Fallback: if search with year returned nothing, retry once without year constraint
            if not is_tv and parsed_year then
                local retry_url = string.format(
                    'https://api.tmdb.org/3/search/movie?api_key=%s&query=%s&page=1',
                    key,
                    tmdb_url_encode(show)
                )
                safe_async_cmd({
                    name = 'subprocess',
                    args = {'curl', '-s', '-4', '--connect-timeout', '3', '--retry', '3', '--retry-all-errors', '--max-time', '8', retry_url},
                    capture_stdout = true,
                }, function(ok_r, res_r)
                    local data_r = (ok_r and res_r and res_r.stdout) and utils.parse_json(res_r.stdout) or nil
                    if not data_r or not data_r.results or #data_r.results == 0 then
                        tmdb_fetching = false
                        return
                    end
                    on_search_item(data_r.results[1])
                end)
                return
            elseif is_tv then
                local stripped_show = show:gsub('%s+(%d+)%a%a%s+[Ss]eason.*$', ''):gsub('%s+[Ss]eason%s+(%d+).*$', ''):gsub('%s+[Ss]%d+.*$', '')
                if stripped_show ~= show and #stripped_show > 1 then
                    local retry_tv_url = string.format(
                        'https://api.tmdb.org/3/search/tv?api_key=%s&query=%s&page=1',
                        key,
                        tmdb_url_encode(stripped_show)
                    )
                    safe_async_cmd({
                        name = 'subprocess',
                        args = {'curl', '-s', '-4', '--connect-timeout', '3', '--retry', '3', '--retry-all-errors', '--max-time', '8', retry_tv_url},
                        capture_stdout = true,
                    }, function(ok_r, res_r)
                        local data_r = (ok_r and res_r and res_r.stdout) and utils.parse_json(res_r.stdout) or nil
                        if not data_r or not data_r.results or #data_r.results == 0 then
                            tmdb_fetching = false
                            return
                        end
                        on_search_item(data_r.results[1])
                    end)
                    return
                end
            end
            tmdb_fetching = false
            return
        end
        on_search_item(data.results[1])
    end

    safe_async_cmd({
        name = 'subprocess',
        args = {'curl', '-s', '-4', '--connect-timeout', '3', '--retry', '3', '--retry-all-errors', '--max-time', '8', search_url},
        capture_stdout = true,
    }, function(ok, res)
        if not ok or not res or not res.stdout or res.stdout == '' then
            tmdb_fetching = false
            return
        end
        local data = utils.parse_json(res.stdout)
        handle_search_results(data)
    end)
end

local function debounced_fetch_tmdb(delay, force_refresh)
    if tmdb_debounce_timer then
        tmdb_debounce_timer:kill()
        tmdb_debounce_timer = nil
    end
    tmdb_debounce_timer = mp.add_timeout(delay or 0.25, function()
        tmdb_debounce_timer = nil
        fetch_tmdb_data(force_refresh)
    end)
end

-- ── wire up pause / file-loaded events ───────────────────────────────────────

-- Reset cache & abort in-flight commands on new file
mp.register_event('start-file', function()
    abort_all_subprocesses()
    if tmdb_debounce_timer then tmdb_debounce_timer:kill(); tmdb_debounce_timer = nil end
    tmdb_current  = nil
    tmdb_fetching = false
    last_parsed_title = nil
    ss_hide(true)
end)

mp.register_event('file-loaded', function()
    tmdb_current  = nil
    tmdb_fetching = false
    last_parsed_title = nil
    ss_hide()
    if mp.get_property_native('pause') and user_opts.screensaver_enabled then
        debounced_fetch_tmdb(0.25)
        if ss_delay_timer then ss_delay_timer:kill() end
        ss_delay_timer = mp.add_timeout(
            tonumber(user_opts.screensaver_delay) or 3,
            activate_screensaver
        )
    end
end)

mp.observe_property('media-title', 'string', function(_, new_title)
    if not new_title or new_title == '' then return end
    local show, _, _, _ = tmdb_parse_title()
    if last_parsed_title and show and show ~= '' and last_parsed_title ~= show then
        debounced_fetch_tmdb(0.25, true)
    end
end)

mp.observe_property('pause', 'bool', function(_, paused)
    if paused == nil then return end
    if paused then
        if not user_opts.screensaver_enabled then return end
        if state.menu_active or (is_menu_active_fn and is_menu_active_fn()) then return end
        -- Debounce TMDB fetch to handle rapid pause/unpause toggles
        debounced_fetch_tmdb(0.25)
        -- Delay before screensaver activates
        if ss_delay_timer then ss_delay_timer:kill() end
        ss_delay_timer = mp.add_timeout(
            tonumber(user_opts.screensaver_delay) or 3,
            activate_screensaver
        )
    else
        abort_all_subprocesses()
        if tmdb_debounce_timer then tmdb_debounce_timer:kill(); tmdb_debounce_timer = nil end
        tmdb_fetching = false
        ss_hide(true) -- immediate on unpause
    end
end)

-- Mouse jitter filter: require at least 8px intentional movement to dismiss screensaver
local last_ss_mx, last_ss_my = nil, nil
mp.observe_property('mouse-pos', 'native', function(_, mpos)
    if not mp.get_property_native('pause') then return end
    if not user_opts.screensaver_enabled then return end
    if not mpos then return end
    if is_menu_active_fn and is_menu_active_fn() then
        if ss_delay_timer then ss_delay_timer:kill(); ss_delay_timer = nil end
        return
    end

    local mx, my = mpos.x, mpos.y
    if not last_ss_mx or not last_ss_my then
        last_ss_mx, last_ss_my = mx, my
        return
    end

    local dx = math.abs(mx - last_ss_mx)
    local dy = math.abs(my - last_ss_my)

    if ss_active then
        -- Require intentional mouse movement to dismiss screensaver (ignore minor table bump jitter)
        if dx >= 8 or dy >= 8 then
            last_ss_mx, last_ss_my = mx, my
            ss_hide()
        end
    else
        -- When screensaver is pending, movement resets the activation timer
        if dx >= 4 or dy >= 4 then
            last_ss_mx, last_ss_my = mx, my
            if ss_delay_timer then ss_delay_timer:kill() end
            ss_delay_timer = mp.add_timeout(
                tonumber(user_opts.screensaver_delay) or 3,
                activate_screensaver
            )
        end
    end
end)

-- Seeking observer: dismiss screensaver so user sees where they seeked
local last_seek_time = nil
mp.observe_property('time-pos', 'number', function(_, pos)
    if not pos then return end
    if not last_seek_time then
        last_seek_time = pos
        return
    end
    if math.abs(pos - last_seek_time) >= 0.8 then
        last_seek_time = pos
        if ss_active then
            ss_hide()
        end
    end
end)

function M.init(ctx)
    user_opts         = ctx.user_opts or {}
    state             = ctx.state or {}
    hide_osc          = ctx.hide_osc or function() end
    show_osc          = ctx.show_osc or function() end
    request_tick      = ctx.request_tick or function() end
    utils_mod         = ctx.utils
    is_menu_active_fn = ctx.is_menu_active
end

function M.is_active()
    return ss_active
end

function M.get_current()
    return tmdb_current
end

function M.activate()
    if activate_screensaver then activate_screensaver() end
end

function M.hide(immediate)
    if ss_hide then ss_hide(immediate) end
end

function M.inhibit()
    abort_all_subprocesses()
    if tmdb_debounce_timer then tmdb_debounce_timer:kill(); tmdb_debounce_timer = nil end
    if ss_delay_timer then ss_delay_timer:kill(); ss_delay_timer = nil end
    if ss_hide then ss_hide(true) end
    ss_remove_logo()
end

function M.render(alpha)
    render_screensaver(alpha)
end

function M.fetch_data(force_refresh)
    if fetch_tmdb_data then fetch_tmdb_data(force_refresh) end
end

function M.fetch_candidates(query, callback)
    local key = user_opts.tmdb_api_key
    if not key or key == '' or not query or query == '' then
        if callback then callback({}) end
        return
    end

    local q_enc = tmdb_url_encode(query)
    local url = string.format('https://api.tmdb.org/3/search/multi?api_key=%s&query=%s&page=1', key, q_enc)

    if not (mp and mp.command_native_async) then
        if callback then callback({}) end
        return
    end

    mp.command_native_async({
        name = 'subprocess',
        playback_only = false,
        args = {'curl', '-s', '-4', '--connect-timeout', '4', '--retry', '2', '--max-time', '8', url},
        capture_stdout = true,
    }, function(ok, res)
        local data = (ok and res and res.stdout) and utils.parse_json(res.stdout) or nil
        local candidates = {}
        if data and data.results then
            for _, item in ipairs(data.results) do
                local mtype = item.media_type or 'movie'
                if mtype == 'movie' or mtype == 'tv' then
                    local title = item.title or item.name or item.original_title or item.original_name or ''
                    if title ~= '' and #candidates < 15 then
                        local year_raw = item.release_date or item.first_air_date or ''
                        local year = year_raw:match('^(%d%d%d%d)') or ''
                        local rating = item.vote_average and string.format('%.1f', item.vote_average) or ''
                        table.insert(candidates, {
                            id = item.id,
                            title = title,
                            media_type = mtype,
                            year = year,
                            rating = rating,
                            overview = item.overview or '',
                        })
                    end
                end
            end
        end
        if callback then callback(candidates) end
    end)
end

return M
