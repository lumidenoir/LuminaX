-- ============================================================================
-- ModernH Module: Utils
-- Shared helper utilities, title cleaning, ASS drawing, formatters & platform detection
-- ============================================================================

local ok_ass, assdraw = pcall(require, 'mp.assdraw')

local M = {}

-- Platform detection (zero subprocess spawn)
local is_windows = (package.config:sub(1, 1) == '\\')
local is_mac = false
if mp and mp.get_property_native then
    local p = mp.get_property_native('platform')
    is_windows = (p == 'windows')
    is_mac = (p == 'darwin')
elseif not is_windows then
    local ostype = os.getenv('OSTYPE') or ''
    is_mac = (ostype:lower():find('darwin') ~= nil)
end
M.is_windows = is_windows
M.is_mac     = is_mac
M.is_linux   = not is_windows and not is_mac

-- Cross-platform mkdir -p
function M.mkdir_p(dir)
    if not dir or dir == '' then return end
    if mp and mp.command_native_async then
        if is_windows then
            local win_dir = dir:gsub('/', '\\'):gsub('\\+$', '')
            mp.command_native_async({
                name = 'subprocess',
                args = {'cmd.exe', '/d', '/c', 'if not exist "' .. win_dir .. '" mkdir "' .. win_dir .. '"'},
            }, function() end)
        else
            mp.command_native_async({
                name = 'subprocess',
                args = {'mkdir', '-p', dir},
            }, function() end)
        end
    end
end

-- Return byte index of the start of the UTF-8 codepoint before byte_pos (1-indexed)
function M.utf8_prev_char(str, byte_pos)
    if not str or byte_pos <= 1 then return 1 end
    local i = byte_pos - 1
    while i > 1 and (str:byte(i) >= 0x80 and str:byte(i) < 0xC0) do
        i = i - 1
    end
    return i
end

-- Return byte index of the start of the UTF-8 codepoint after byte_pos (1-indexed)
function M.utf8_next_char(str, byte_pos)
    if not str or byte_pos > #str then return #str + 1 end
    local b = str:byte(byte_pos)
    if not b then return #str + 1 end
    local step = 1
    if b >= 0xC0 and b < 0xE0 then
        step = 2
    elseif b >= 0xE0 and b < 0xF0 then
        step = 3
    elseif b >= 0xF0 then
        step = 4
    end
    return math.min(#str + 1, byte_pos + step)
end

-- Check if a title string contains junk/web/tracker domains
function M.is_junk_title(t)
    if not t or t == '' then return true end
    local tl = t:lower()
    if tl:find('www%.') or tl:find('%.com') or tl:find('%.org') or tl:find('%.net')
       or tl:find('%.meme') or tl:find('%.vip') or tl:find('%.in') or tl:find('%.co')
       or tl:find('%.tv') or tl:find('%.cc') or tl:find('%.to') or tl:find('%.link')
       or tl:find('%.me') or tl:find('%.biz') or tl:find('%.info') or tl:find('%.ws') or tl:find('%.ph')
       or tl:find('%.mx') or tl:find('%.cx') or tl:find('%.pm') or tl:find('%.xyz') or tl:find('%.top')
       or tl:find('%.site') or tl:find('%.online') or tl:find('%.club') then
        return true
    end
    if tl:find('^downloaded') or tl:find('^torrent') or tl:find('1tamilmv') or tl:find('tamilblasters')
       or tl:find('tamilmv') or tl:find('tamilrockers') or tl:find('yts') or tl:find('yify')
       or tl:find('rarbg') or tl:find('psa') or tl:find('galaxyrg') or tl:find('qxr')
       or tl:find('tgx') or tl:find('eztv') or tl:find('ettv') or tl:find('opensubtitles')
       or tl:find('subscene') or tl:find('as%-encodes') then
        return true
    end
    -- Detect standalone scene/release junk tags left in container metadata
    local stripped = tl:gsub('[%s%-_%.%[%]%(\\%)]+', ' '):gsub('^%s+', ''):gsub('%s+$', '')
    if stripped == 'hq clean' or stripped == 'clean' or stripped == 'predvd' or stripped == 'hdts'
       or stripped == 'web dl' or stripped == 'webdl' or stripped == 'webrip' or stripped == 'bluray'
       or stripped == 'hdtv' or stripped == 'dvdrip' or stripped == 'camrip' or stripped == 'hdrip'
       or stripped == 'hq' or stripped == 'proper' or stripped == 'repack' then
        return true
    end
    return false
end

-- Check if a path is a network URL or online stream (http, https, ytdl, rtmp, etc.)
function M.is_url(path)
    if not path or path == '' then return false end
    return (path:find('^%a[%w+.-]*://') ~= nil)
        or (path:find('^ytdl://') ~= nil)
        or (path:find('^magnet:') ~= nil)
end

-- Helper to extract clean show title & season from parent folder path
local function parse_parent_folder(filepath)
    if not filepath or filepath == '' then return nil, nil end
    local parent = filepath:match('([^/]+)/[^/]+$')
    if not parent or parent == '' then return nil, nil end
    
    local s_num = parent:match('[Ss]eason%s*(%d+)') or parent:match('%b()[Ss]eason%s*(%d+)%b()') or parent:match('%b()[Ss](%d+)%b()') or parent:match('%s[Ss](%d+)%s') or parent:match('%s[Ss](%d+)$')
    local folder_season = s_num and tonumber(s_num) or nil
    
    local clean_folder = parent
    local alt = parent:match('%(([^)]+)%)')
    if alt and #alt > 3 and not alt:lower():find('1080p') and not alt:lower():find('hevc') and not alt:lower():find('season') and not alt:lower():find('bd') then
        clean_folder = alt
    end

    clean_folder = clean_folder:gsub('%s[Ss]%d+.*$', '')
    clean_folder = clean_folder:gsub('%b[]', '')
    clean_folder = clean_folder:gsub('%([Ss]eason%s*%d+%)', '')
    clean_folder = clean_folder:gsub('%(1080p[^)]*%)', '')
    clean_folder = clean_folder:gsub('%(HEVC[^)]*%)', '')
    clean_folder = clean_folder:gsub('`', "'")
    clean_folder = clean_folder:gsub('%s+', ' '):gsub('^%s+', ''):gsub('%s+$', '')

    if #clean_folder > 1 then
        return clean_folder, folder_season
    end
    return nil, nil
end

-- Parse media title / filename to extract clean title, TV season/episode, or movie release year
function M.parse_clean_title(media_title, filename, filepath)
    filepath = filepath or (mp and mp.get_property and mp.get_property('path'))
    local has_tag = media_title and media_title ~= '' and media_title ~= filename and not M.is_junk_title(media_title)
    local raw = has_tag and media_title or (filename or '')
    raw = raw:gsub('%.%w+$', '') -- remove extension

    -- Strip leading tracker/domain watermarks
    raw = raw:gsub('^%s*www%.[%w%-_]+%.%a+[%s%-_]*%-%s*', '')
    raw = raw:gsub('^%s*www%.[%w%-_]+%.%a+[%s%-_]*', '')
    raw = raw:gsub('^%s*%b[][%s%-_]*', '')

    -- 1. TV Episode patterns: S01E05, S1E1, etc.
    local s, e = raw:match('[Ss](%d+)[%s%.%-_]*[Ee](%d+)')
    if s and e then
        local show = raw:match('^(.-)[%s%.%-_]+[Ss]%d+') or ''
        show = show:gsub('%.', ' '):gsub('_', ' '):gsub('%b[]', ''):gsub('%b()', ''):gsub('[%s%-]+$', '')
        show = show:gsub('%s+', ' '):gsub('^%s+', ''):gsub('%s+$', '')
        if #show <= 3 and filepath then
            local f_title, f_season = parse_parent_folder(filepath)
            if f_title then
                show = f_title
                if f_season and not s then s = f_season end
            end
        elseif #show <= 10 and filepath then
            local f_title, f_season = parse_parent_folder(filepath)
            if f_title then show = f_title end
        end
        if #show > 0 then
            return show:sub(1, 60), tonumber(s), tonumber(e), nil
        end
    end

    -- If user set a title tag (media_title) without S02E02, check filename for S02E02!
    if has_tag and filename then
        local fn_s, fn_e = filename:match('[Ss](%d+)[%s%.%-_]*[Ee](%d+)')
        if fn_s and fn_e then
            local clean_tag = media_title:gsub('%.%w+$', ''):gsub('%b[]', ''):gsub('%b()', ''):gsub('`', "'")
            clean_tag = clean_tag:gsub('^[Ss]%d+[Ee]%d+.*$', ''):gsub('%s+', ' '):gsub('^%s+', ''):gsub('%s+$', '')
            if #clean_tag <= 3 and filepath then
                local f_title, f_season = parse_parent_folder(filepath)
                if f_title then clean_tag = f_title end
            end
            if #clean_tag > 0 then
                return clean_tag:sub(1, 60), tonumber(fn_s), tonumber(fn_e), nil
            end
        end
    end

    -- 2. Anime / Episode single-number pattern: "Title - 12 (1080p)" or "Title 2nd Season - 01"
    local anime_title, ep_num = raw:match('^(.-)%s*-%s*(%d%d?)%s*[%s%(%[]')
    if not anime_title then
        anime_title, ep_num = raw:match('^(.-)%s*-%s*(%d%d?)%s*$')
    end
    if anime_title and ep_num and not anime_title:match('[12]%d%d%d') then
        anime_title = anime_title:gsub('%.', ' '):gsub('_', ' '):gsub('%b[]', ''):gsub('%b()', ''):gsub('[%s%-]+$', '')
        anime_title = anime_title:gsub('%s+', ' '):gsub('^%s+', ''):gsub('%s+$', '')
        if #anime_title > 1 then
            -- Extract explicit season numbering if present: "Sousou no Frieren 2nd Season" -> S2, "Show Season 3" -> S3
            local base_show, s_ord = anime_title:match('^(.-)%s+(%d+)%a%a%s+[Ss]eason%s*$')
            if not base_show then
                base_show, s_ord = anime_title:match('^(.-)%s+[Ss]eason%s+(%d+)%s*$')
            end
            if not base_show then
                base_show, s_ord = anime_title:match('^(.-)%s+[Ss](%d+)%s*$')
            end
            local season = s_ord and tonumber(s_ord) or 1
            local final_show = base_show or anime_title
            final_show = final_show:gsub('[%s%-]+$', ''):gsub('%s+', ' ')
            if #final_show <= 10 and filepath then
                local f_title, f_season = parse_parent_folder(filepath)
                if f_title then
                    final_show = f_title
                    if f_season then season = f_season end
                end
            end
            return final_show:sub(1, 60), season, tonumber(ep_num), nil
        end
    end

    -- 3. Check for 4-digit year bounded by delimiters or brackets: (2026), [2026], .2026., ' 2026 '
    local pre_year = raw:match('%(([12]%d%d%d)%)') or raw:match('%[([12]%d%d%d)%]')
    if not pre_year then
        pre_year = raw:match('[%s%(%[%._]([12]%d%d%d)')
    end

    if pre_year then
        local idx = raw:find(pre_year, 1, true)
        if idx and idx > 1 then
            local prefix = raw:sub(1, idx - 1):gsub('[%s%(%[%-%.]+$', '')
            local clean_title = prefix:gsub('%.', ' '):gsub('_', ' '):gsub('%b[]', ''):gsub('%b()', ''):gsub('~.*$', '')
            clean_title = clean_title:gsub('%s+', ' '):gsub('^%s+', ''):gsub('%s+$', '')
            if #clean_title > 1 then
                return clean_title:sub(1, 60), nil, nil, pre_year
            end
        end
    end

    -- 4. Strip standard scene release tags: 1080p, 720p, 2160p, 4k, WEB-DL, BluRay, HDR, HEVC, etc.
    local clean = raw:gsub('%.', ' '):gsub('_', ' '):gsub('%b[]', ''):gsub('%b()', ''):gsub('~.*$', '')
    local scene_pattern = '%f[%a%d]([12]%d%d%d|2160p|1080p|720p|480p|4k|uhd|web%-?dl|web%-?rip|bluray|h264|h265|hevc|x264|x265|ddp?5?%.?1?|atmos|aac|dts|remux|proper|repack|tamil|telugu|hindi|english|kannada|malayalam).*$'
    local stripped = clean:gsub(scene_pattern, '')
    stripped = stripped:gsub('%s+', ' '):gsub('^%s+', ''):gsub('%s+$', '')
    if #stripped > 1 then
        return stripped:sub(1, 60), nil, nil, pre_year
    end

    clean = clean:gsub('%s+', ' '):gsub('^%s+', ''):gsub('%s+$', '')
    return clean:sub(1, 60), nil, nil, pre_year
end

-- ASS string escaping to prevent ASS markup corruption or crash
function M.ass_escape(str)
    if not str then return '' end
    str = tostring(str)
    str = str:gsub('\\', '\\\239\187\1bf')
    str = str:gsub('{', '\\{')
    str = str:gsub('}', '\\}')
    return str
end

-- Safe time formatting helper: seconds -> "HH:MM:SS" or "MM:SS"
function M.format_time(seconds)
    if not seconds or seconds ~= seconds or seconds < 0 then return '00:00' end
    if mp and mp.format_time then
        local ok, res = pcall(mp.format_time, seconds)
        if ok and res and type(res) == 'string' then return res end
    end
    local s = math.floor(seconds)
    local h = math.floor(s / 3600)
    local m = math.floor((s % 3600) / 60)
    local sec = s % 60
    if h > 0 then
        return string.format('%d:%02d:%02d', h, m, sec)
    else
        return string.format('%02d:%02d', m, sec)
    end
end

-- Format currency integer to USD string: 10585310 -> "$10,585,310"
function M.format_currency(n)
    if not n or n <= 0 then return nil end
    local s = tostring(math.floor(n))
    local formatted = s:reverse():gsub('(%d%d%d)', '%1,'):reverse():gsub('^,', '')
    return '$' .. formatted
end

-- Format date string: "2026-08-07" -> "Aug 7, 2026"
function M.format_date(d_str)
    if not d_str or d_str == '' then return nil end
    local y, m, d = d_str:match('(%d%d%d%d)%-(%d%d)%-(%d%d)')
    if not y or not m or not d then return d_str end
    local months = {'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'}
    local m_idx = tonumber(m)
    local m_name = months[m_idx] or m
    return string.format('%s %d, %s', m_name, tonumber(d), y)
end

-- Format estimated finish time based on playtime remaining: "5:52 AM"
function M.format_ends_time(duration_min)
    local rem = mp.get_property_number('playtime-remaining')
    if not rem or rem <= 0 then
        rem = (duration_min and duration_min > 0) and (duration_min * 60) or 0
    end
    if rem > 0 then
        local end_t = os.time() + math.floor(rem)
        local h = tonumber(os.date('%H', end_t))
        local m = os.date('%M', end_t)
        local ampm = (h and h >= 12) and 'PM' or 'AM'
        local h12 = (h and h % 12) or 12
        if h12 == 0 then h12 = 12 end
        return string.format('%d:%s %s', h12, m, ampm)
    end
    return nil
end

-- Get ASS canvas dimensions
function M.get_canvas_size(osc_param)
    local w = osc_param and osc_param.playresx
    local h = osc_param and osc_param.playresy
    if not w or w == 0 then
        w, h = mp.get_osd_size()
        w = w or 1280; h = h or 720
    end
    return w, h
end

-- Draw a floating pill at (cx, cy) in ASS canvas coordinates
function M.make_pill_ass(cx, cy, pill_w, pill_h, pill_text, text_font, text_size, bg_alpha_hex, text_alpha_hex)
    local ass   = assdraw.ass_new()
    local r     = pill_h / 2
    -- Background
    ass:new_event()
    ass:pos(0, 0)
    ass:an(7)
    ass:append(string.format(
        '{\\blur0\\bord0.5\\1c&H0A0A0A&\\1a&H%s&\\3c&HFFFFFF&\\3a&HC0&}',
        bg_alpha_hex))
    ass:draw_start()
    ass:round_rect_cw(cx - pill_w/2, cy - r, cx + pill_w/2, cy + r, r)
    ass:draw_stop()
    -- Text
    ass:new_event()
    ass:pos(cx, cy)
    ass:an(5)
    ass:append(string.format(
        '{\\fn%s\\b700\\fs%d\\1c&HFFFFFF&\\1a&H%s&\\bord0\\shad0}',
        text_font, text_size, text_alpha_hex))
    ass:append(pill_text)
    return ass
end

-- Multiply two alpha values (0..255)
function M.mult_alpha(a, b)
    return 255 - math.floor((255 - a) * (255 - b) / 255)
end

-- Collect badge table (shared between OSC bar and screensaver)
function M.collect_media_badges()
    local badges = {}

    -- 1. Video Resolution (Ice Blue / Steel)
    local vw = mp.get_property_number('video-params/w', 0)
    local vh = mp.get_property_number('video-params/h', 0)
    if vw >= 3800 or vh >= 2100 then
        table.insert(badges, {text = '4K',    w = 24, fg = 'D6A27E', bg = '302218', bord = '885B3B'})
    elseif vw >= 1900 or vh >= 1000 then
        table.insert(badges, {text = '1080P', w = 38, fg = 'B8A89A', bg = '282018', bord = '605040'})
    end

    -- 2. HDR / Dolby Vision (Warm Ember / Gold - ASS BGR)
    local gamma     = mp.get_property('video-params/gamma', '')
    local sig_peak  = mp.get_property_number('video-params/sig-peak', 0)
    local hdr_cll   = mp.get_property('video-params/hdr-max-cll')
    local dv        = mp.get_property('video-params/dolby-vision-profile')
                   or mp.get_property('video-params/dv-profile')
    local primaries = mp.get_property('video-params/primaries', '')

    if dv and dv ~= '' then
        table.insert(badges, {text = 'VISION', w = 46, fg = '3CA9E5', bg = '10202A', bord = '18557A'})
    elseif gamma == 'pq' or gamma == 'hlg' or sig_peak > 1
        or hdr_cll ~= nil or primaries == 'bt.2020' then
        table.insert(badges, {text = 'HDR',   w = 30, fg = '3CA9E5', bg = '10202A', bord = '18557A'})
    end

    -- 3. Audio Codec & Standards (Twilight Violet / Sky Blue / Sage)
    local audio_codec  = (mp.get_property('audio-codec-name') or ''):lower()
    local track_title  = (mp.get_property('current-tracks/audio/title') or ''):lower()
    local media_title  = (mp.get_property('media-title') or ''):lower()
    local filename_lc  = (mp.get_property('filename') or ''):lower()

    if track_title:find('atmos') or media_title:find('atmos') or filename_lc:find('atmos') then
        table.insert(badges, {text = 'ATMOS',  w = 46, fg = 'FF92B8', bg = '2E1820', bord = '8A3A5A'})
    elseif audio_codec:find('truehd') then
        table.insert(badges, {text = 'TRUEHD', w = 50, fg = 'FF92B8', bg = '2E1820', bord = '8A3A5A'})
    elseif audio_codec:find('dts') then
        table.insert(badges, {text = 'DTS',    w = 28, fg = 'F0B080', bg = '2C2218', bord = '705538'})
    elseif audio_codec:find('flac') then
        table.insert(badges, {text = 'FLAC',   w = 32, fg = '80D8A0', bg = '1C2818', bord = '3A6038'})
    end

    -- 4. Surround Channels (Neutral Studio Gray)
    local channels = mp.get_property_number('audio-params/channel-count', 0)
    if channels == 8 then
        table.insert(badges, {text = '7.1', w = 22, fg = 'ACA19B', bg = '201C1A', bord = '443C38'})
    elseif channels == 6 then
        table.insert(badges, {text = '5.1', w = 22, fg = 'ACA19B', bg = '201C1A', bord = '443C38'})
    end

    -- 5. Web / Online Stream Badge
    local path = mp.get_property('path', '')
    if M.is_url(path) then
        local d = mp.get_property_number('duration', 0)
        if d == 0 then
            table.insert(badges, {text = 'LIVE', w = 32, fg = 'FF8080', bg = '281414', bord = '683030'})
        else
            table.insert(badges, {text = 'STREAM', w = 46, fg = '70E0B0', bg = '14261E', bord = '2C6048'})
        end
    end

    return badges
end

-- Calculate total pixel width of badge pills
function M.calc_badges_width(badges, badge_h)
    if not badges or #badges == 0 then return 0 end
    local pad = math.floor(badge_h * 0.65)
    local gap = 7
    local total = 0
    for i, b in ipairs(badges) do
        local bw = (b.w or 24) + pad
        total = total + bw + (i > 1 and gap or 0)
    end
    return total
end

-- Draw badge pills LEFT-TO-RIGHT starting at (start_x, center_y)
function M.draw_badges_ltr(ass, badges, start_x, cy, badge_h, alpha)
    if not badges or #badges == 0 then return start_x end
    local cur_x = start_x
    local pad   = math.floor(badge_h * 0.65)
    local gap   = 7
    local r     = 4
    local fs    = math.max(10, math.floor(badge_h * 0.52))
    for _, b in ipairs(badges) do
        local bw = (b.w or 24) + pad
        local bx = cur_x
        local bg_col = b.bg or '1A1A1E'
        local bord_col = b.bord or '404048'

        ass:new_event()
        ass:pos(0, 0)
        ass:an(7)
        ass:append(string.format('{\\blur0\\bord1\\1c&H%s&\\3c&H%s&}', bg_col, bord_col))
        if alpha then
            if type(alpha) == 'string' then
                ass:append(string.format('{\\1a&H%s&\\3a&H%s&}', alpha, alpha))
            else
                ass:append('{\\1a&H20&\\3a&H40&}')
            end
        else
            ass:append('{\\1a&H20&\\3a&H40&}')
        end
        ass:draw_start()
        ass:round_rect_cw(bx, cy - badge_h/2, bx + bw, cy + badge_h/2, r)
        ass:draw_stop()

        ass:new_event()
        ass:pos(bx + bw/2, cy)
        ass:an(5)
        ass:append(string.format('{\\fnInter\\b700\\fs%d\\1c&H%s&\\bord0\\shad0\\fsp0.5}', fs, b.fg or 'FFFFFF'))
        if alpha and type(alpha) == 'string' then
            ass:append(string.format('{\\1a&H%s&}', alpha))
        else
            ass:append('{\\1a&H00&}')
        end
        ass:append(b.text or '')
        cur_x = bx + bw + gap
    end
    return cur_x
end

return M
