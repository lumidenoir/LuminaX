        -- ============================================================================
-- ModernH Module: Menu
-- Popup Track / Chapter / Playlist / Tag Menus with animated focus bar
-- ============================================================================

local mp_utils = require('mp.utils')

local M = {}

local menu_key_bindings = {}
local menu_alpha        = 0
local menu_closing      = false
local menu_bar_anim_y   = nil
local menu_bar_last_t   = nil
local tmdb_matches_list = {}
local tmdb_searching    = false
local tmdb_query_str    = ''
local tag_inspector_boxes = {}

local ctx_ref = {}

local function rgb_to_ass(hex_str)
    if not hex_str or type(hex_str) ~= 'string' then return '&HFFFFFF&' end
    local h = hex_str:gsub('#', ''):upper()
    if #h == 6 then
        local r, g, b = h:sub(1, 2), h:sub(3, 4), h:sub(5, 6)
        return '&H' .. b .. g .. r .. '&'
    end
    return '&HFFFFFF&'
end

function M.init(ctx)
    ctx_ref = ctx
    mp.observe_property('track-list', nil, function()
        M.invalidate_items()
        if M.is_active() and ctx_ref.request_tick then ctx_ref.request_tick() end
    end)
    mp.observe_property('aid', nil, function()
        M.invalidate_items()
        if M.is_active() and ctx_ref.request_tick then ctx_ref.request_tick() end
    end)
    mp.observe_property('sid', nil, function()
        M.invalidate_items()
        if M.is_active() and ctx_ref.request_tick then ctx_ref.request_tick() end
    end)
    mp.observe_property('playlist-pos', nil, function()
        M.invalidate_items()
        if M.is_active() and ctx_ref.request_tick then ctx_ref.request_tick() end
    end)
    mp.observe_property('chapter', nil, function()
        M.invalidate_items()
        if M.is_active() and ctx_ref.request_tick then ctx_ref.request_tick() end
    end)
    mp.observe_property('media-title', nil, function()
        M.invalidate_items()
        if M.is_active() and ctx_ref.request_tick then ctx_ref.request_tick() end
    end)
    mp.observe_property('filename', nil, function()
        M.invalidate_items()
        if M.is_active() and ctx_ref.request_tick then ctx_ref.request_tick() end
    end)
    mp.observe_property('path', nil, function()
        M.invalidate_items()
        if M.is_active() and ctx_ref.request_tick then ctx_ref.request_tick() end
    end)
    mp.register_event('start-file', function()
        M.invalidate_items()
        if M.is_active() and ctx_ref.request_tick then ctx_ref.request_tick() end
    end)
    mp.register_event('file-loaded', function()
        M.invalidate_items()
        if M.is_active() and ctx_ref.request_tick then ctx_ref.request_tick() end
    end)
end

local function menu_add_binding(key, name, fn, flags)
    menu_key_bindings[#menu_key_bindings + 1] = name
    mp.add_forced_key_binding(key, name, fn, flags)
end

function M.is_active()
    return ctx_ref.state.menu_active ~= nil or menu_closing
end

function M.menu_close()
    if ctx_ref.subtitle and ctx_ref.subtitle.set_live_preview then
        ctx_ref.subtitle.set_live_preview(false)
    end
    for _, name in ipairs(menu_key_bindings) do
        mp.remove_key_binding(name)
    end
    menu_key_bindings = {}
    menu_search_query = ''
    menu_closing = true
    M.invalidate_items()
    if ctx_ref.request_tick then ctx_ref.request_tick() end
end

local cached_items = nil
local cached_menu_type = nil

function M.invalidate_items()
    cached_items = nil
    cached_menu_type = nil
end

local menu_search_query = ''

local function is_night_mode_active()
    local af = mp.get_property_native('af', {})
    if type(af) ~= 'table' then return false end
    for _, filter in ipairs(af) do
        if filter.label == 'nightmode' or (filter.name and filter.name:find('nightmode')) then
            return true
        end
    end
    return false
end

local function toggle_night_mode()
    local active = is_night_mode_active()
    if active then
        mp.commandv("af", "remove", "@nightmode")
        mp.osd_message("Night Mode: Off", 2)
    else
        local filter_str = "dynaudnorm=f=150:g=15:m=10:p=0.9"
        mp.commandv("af", "add", "@nightmode:lavfi=[" .. filter_str .. "]")
        mp.osd_message("Night Mode: On (Dialogue Clarity)", 2)
    end
end

local function step_audio_delay(delta)
    local cur = mp.get_property_number("audio-delay", 0.0) or 0.0
    local next_val = math.floor((cur + delta) * 1000 + 0.5) / 1000
    mp.set_property_number("audio-delay", next_val)
end

local function reset_audio_delay()
    mp.set_property_number("audio-delay", 0.0)
    mp.osd_message("Audio Delay: Reset (0 ms)", 2)
end

local function step_video_prop(prop, delta, min_val, max_val)
    local cur = mp.get_property_number(prop, 0) or 0
    local nxt = math.max(min_val, math.min(max_val, cur + delta))
    mp.set_property_number(prop, nxt)
end

local function cycle_aspect_ratio()
    local cur_num = mp.get_property_number('video-aspect-override', -1)
    local cur = '-1'
    if cur_num and cur_num > 0 then
        if math.abs(cur_num - 16/9) < 0.05 then cur = '16:9'
        elseif math.abs(cur_num - 21/9) < 0.08 or math.abs(cur_num - 2.35) < 0.08 then cur = '21:9'
        elseif math.abs(cur_num - 4/3) < 0.05 then cur = '4:3'
        end
    end
    local order = {'-1', '16:9', '21:9', '4:3'}
    local next_val = '-1'
    for idx, v in ipairs(order) do
        if v == cur then
            next_val = order[(idx % #order) + 1]
            break
        end
    end
    mp.set_property('video-aspect-override', next_val)
    local names = {['-1'] = 'Auto (16:9)', ['16:9'] = '16:9', ['21:9'] = '21:9 (Ultrawide)', ['4:3'] = '4:3'}
    mp.osd_message('Aspect Ratio: ' .. (names[next_val] or next_val), 2)
end

local function cycle_rotate(dir)
    local cur = mp.get_property_number('video-rotate', 0) or 0
    local next_val = (cur + (dir > 0 and 90 or 270)) % 360
    mp.set_property_number('video-rotate', next_val)
    mp.osd_message(string.format('Rotate: %d°', next_val), 2)
end

local function cycle_deinterlace()
    local cur = mp.get_property('deinterlace', 'no') or 'no'
    local next_val = (cur == 'no') and 'yes' or ((cur == 'yes') and 'auto' or 'no')
    mp.set_property('deinterlace', next_val)
    mp.osd_message('Deinterlace: ' .. next_val:upper(), 2)
end

local function reset_video_settings()
    mp.set_property_number('contrast', 0)
    mp.set_property_number('brightness', 0)
    mp.set_property_number('saturation', 0)
    mp.set_property_number('gamma', 0)
    mp.set_property('video-aspect-override', '-1')
    mp.set_property_number('panscan', 0.0)
    mp.set_property_number('video-rotate', 0)
    mp.set_property('deinterlace', 'no')
    mp.osd_message('✓ Video settings reset to default', 2)
end

local function get_tracks_by_type(target_type)
    local tracktable = mp.get_property_native('track-list', {})
    local res = {}
    for _, t in ipairs(tracktable) do
        if t.type == target_type then
            res[#res + 1] = t
        end
    end
    return res
end

function M.menu_get_items()
    local state = ctx_ref.state
    if not state.menu_active then return {} end
    if cached_items and cached_menu_type == state.menu_active then
        return cached_items
    end
    local items = {}

    if state.menu_active == 'playlist' then
        local utils = ctx_ref.utils
        local playlist = mp.get_property_native('playlist', {})
        local cur_pos = mp.get_property_number('playlist-pos', 0) + 1

        -- Identify active series context
        local cur_title = mp.get_property('media-title')
        local cur_fn = mp.get_property('filename')
        local active_show, active_s, active_e, _ = nil, nil, nil, nil
        if utils and utils.parse_clean_title then
            active_show, active_s, active_e, _ = utils.parse_clean_title(cur_title, cur_fn)
        end
        local is_series = (active_show ~= nil and active_show ~= '' and (active_s ~= nil or active_e ~= nil))
        state.playlist_is_series = is_series
        state.playlist_cur_show = active_show
        state.playlist_cur_season = active_s or 1

        -- Default filter: if series, show series only unless user toggled to all
        if state.playlist_filter_series == nil then
            state.playlist_filter_series = is_series
        end

        local show_only_series = is_series and state.playlist_filter_series
        local filter_pat = (menu_search_query ~= '') and menu_search_query:lower() or nil

        for i, v in ipairs(playlist) do
            local raw_t = v.title
            local _, fname = mp_utils.split_path(v.filename or '')
            local clean_show, season, episode, year = nil, nil, nil, nil
            if utils and utils.parse_clean_title then
                clean_show, season, episode, year = utils.parse_clean_title(raw_t, fname)
            end

            local is_curr = (i == cur_pos)
            local matches_series = false
            if is_series and clean_show and active_show then
                if clean_show:lower() == active_show:lower() then
                    matches_series = true
                end
            end

            if not show_only_series or matches_series then
                local line1, line2
                if clean_show and season and episode then
                    line1 = string.format('%s  •  S%02dE%02d', clean_show, tonumber(season), tonumber(episode))
                    local ep_title = (raw_t and raw_t ~= '' and not raw_t:find('^%s*$')) and raw_t or fname
                    line2 = (fname ~= '' and fname ~= line1) and fname or string.format('Episode %02d', tonumber(episode))
                elseif clean_show and year then
                    line1 = string.format('%s (%s)', clean_show, year)
                    line2 = (fname ~= '' and fname ~= clean_show) and fname or ''
                else
                    local disp = (clean_show and clean_show ~= '') and clean_show or (fname ~= '' and fname or ('Item ' .. i))
                    line1 = disp
                    line2 = (fname ~= '' and fname ~= disp) and fname or ''
                end

                local matches_search = true
                if filter_pat then
                    local haystack = (line1 .. ' ' .. line2 .. ' ' .. (v.filename or '')):lower()
                    matches_search = (haystack:find(filter_pat, 1, true) ~= nil)
                end

                if matches_search then
                    items[#items + 1] = {
                        label = line1,
                        sublabel = line2,
                        current = is_curr,
                        index = i
                    }
                end
            end
        end

        if #items == 0 and filter_pat then
            items[1] = {
                label = 'No matching playlist items',
                sublabel = string.format('Query: "%s"  (Press Backspace to edit or Esc to clear)', menu_search_query),
                action = 'none',
                current = false,
                index = 0
            }
        end
    elseif state.menu_active == 'audio' then
        local audio_tracks = get_tracks_by_type('audio')

        -- 1. Enhancements: Night Mode (Dialogue Clarity)
        items[#items + 1] = {
            type = 'header',
            label = 'ENHANCEMENTS',
            index = #items + 1
        }
        local night_active = is_night_mode_active()
        items[#items + 1] = {
            label = 'Night Mode (Dialogue Clarity)',
            sublabel = 'Normalizes loud SFX & lifts vocals',
            type = 'stepper',
            value = night_active and 'On' or 'Off',
            current = night_active,
            action = 'toggle_night_mode',
            on_prev = toggle_night_mode,
            on_next = toggle_night_mode,
            index = #items + 1
        }

        -- 2. Audio Track List
        items[#items + 1] = {
            type = 'header',
            label = string.format('TRACKS (%d)', #audio_tracks),
            index = #items + 1
        }
        if #audio_tracks == 0 then
            items[#items + 1] = {label = '(No audio tracks)', sublabel = '', current = false, index = #items + 1}
        else
            local cur_aid = tonumber(mp.get_property('aid', '0'))
            for i, track in ipairs(audio_tracks) do
                local lang = track.lang or 'und'
                local title = track.title or ''
                local label
                local sublabel = ''
                local is_junk = (title ~= '' and utils and utils.is_junk_title and utils.is_junk_title(title))
                if title ~= '' and not is_junk then
                    local name_part, codec_part = title:match('^(.-)%s*%(([^%)]+)%)%s*$')
                    if name_part and codec_part and name_part ~= '' then
                        label = string.format('[%s]  %s', lang, name_part)
                        sublabel = codec_part:gsub('~', ''):gsub('%s*/+%s*', ' • ')
                    else
                        local clean_title = title:gsub('~', ''):gsub('%s*/+%s*', ' • ')
                        label = string.format('[%s]  %s', lang, clean_title)
                        local codec = track.codec or ''
                        local ch    = track['demux-channel-count']
                        local rate  = track['demux-samplerate']
                        local extra = ''
                        if codec ~= '' then extra = codec end
                        if ch then extra = (extra ~= '' and (extra .. ' • ') or '') .. ch .. 'ch' end
                        if rate then extra = (extra ~= '' and (extra .. ' • ') or '') .. math.floor(rate/1000) .. ' kHz' end
                        sublabel = extra
                    end
                else
                    local lang_map = {
                        eng = 'English', tam = 'Tamil', tel = 'Telugu', hin = 'Hindi',
                        mal = 'Malayalam', kan = 'Kannada', jpn = 'Japanese', kor = 'Korean',
                        zho = 'Chinese', chi = 'Chinese', fre = 'French', fra = 'French',
                        ger = 'German', deu = 'German', spa = 'Spanish', ita = 'Italian',
                        rus = 'Russian', por = 'Portuguese'
                    }
                    local lang_name = lang_map[lang] or (lang ~= 'und' and lang:upper()) or ('Track ' .. i)
                    local codec = track.codec or ''
                    local ch    = track['demux-channel-count']
                    local rate  = track['demux-samplerate']
                    local extra = ''
                    if codec ~= '' then extra = codec:upper() end
                    if ch then
                        local ch_str = (ch == 6 and '5.1') or (ch == 8 and '7.1') or (ch == 2 and 'Stereo') or (ch .. 'ch')
                        extra = (extra ~= '' and (extra .. ' • ') or '') .. ch_str
                    end
                    if rate then extra = (extra ~= '' and (extra .. ' • ') or '') .. math.floor(rate/1000) .. ' kHz' end
                    label = string.format('[%s]  %s', lang, lang_name)
                    sublabel = extra
                end
                local is_cur = track.selected or (cur_aid ~= nil and track.id == cur_aid)
                items[#items + 1] = {
                    label = label,
                    sublabel = sublabel,
                    current = is_cur,
                    index = #items + 1,
                    track_id = track.id,
                    action = 'select_track'
                }
            end
        end

        -- 3. Sync & Delay
        items[#items + 1] = {
            type = 'header',
            label = 'SYNC & DELAY',
            index = #items + 1
        }
        local cur_a_delay = mp.get_property_number('audio-delay', 0.0) or 0.0
        local a_delay_str = 'Synced (0 ms)'
        if math.abs(cur_a_delay) >= 0.005 then
            a_delay_str = string.format('%+.1f s (%+d ms)', cur_a_delay, math.floor(cur_a_delay * 1000 + 0.5))
        end
        items[#items + 1] = {
            label = 'Audio Delay',
            sublabel = 'Adjust lip-sync timing (click to reset)',
            value = a_delay_str,
            type = 'stepper',
            on_prev = function() step_audio_delay(-0.1) end,
            on_next = function() step_audio_delay(0.1) end,
            action = 'reset_audio_delay',
            index = #items + 1
        }
    elseif state.menu_active == 'sub' then
        local sid_val = mp.get_property('sid')
        local sub_off = (sid_val == 'no' or sid_val == nil)
        items[1] = {label = 'Off', current = sub_off, index = 0, track_id = 'no'}
        local sub_tracks = get_tracks_by_type('sub')
        if #sub_tracks == 0 then
            items[2] = {label = '(No subtitle tracks)', current = false, index = 0}
        else
            local cur_sid = tonumber(sid_val)
            for i, track in ipairs(sub_tracks) do
                local lang = track.lang or 'und'
                local title = track.title or ''
                local is_junk = (title ~= '' and utils and utils.is_junk_title and utils.is_junk_title(title))
                local lang_map = {
                    eng = 'English', tam = 'Tamil', tel = 'Telugu', hin = 'Hindi',
                    mal = 'Malayalam', kan = 'Kannada', jpn = 'Japanese', kor = 'Korean',
                    zho = 'Chinese', chi = 'Chinese', fre = 'French', fra = 'French',
                    ger = 'German', deu = 'German', spa = 'Spanish', ita = 'Italian',
                    rus = 'Russian', por = 'Portuguese'
                }
                local clean_lang_name = lang_map[lang] or (lang ~= 'und' and lang:upper()) or ('Track ' .. i)
                local raw_sub_title = (title ~= '' and not is_junk) and title or clean_lang_name
                local clean_sub_title = raw_sub_title:gsub('~', ''):gsub('%s*/+%s*', ' • ')
                local label = string.format('[%s]  %s', lang, clean_sub_title)
                local sublabel = ''
                local codec = track.codec or ''
                local flags = {}
                if track.forced then table.insert(flags, 'Forced') end
                if track['default'] then table.insert(flags, 'Default') end
                if track.external then table.insert(flags, 'External') end
                if codec ~= '' then table.insert(flags, codec:upper()) end
                if #flags > 0 then
                    sublabel = table.concat(flags, ' • ')
                end
                local is_cur = (not sub_off) and (track.selected or (cur_sid ~= nil and track.id == cur_sid))
                items[i+1] = {label = label, sublabel = sublabel, current = is_cur, index = i, track_id = track.id}
            end
        end
        items[#items + 1] = {
            label = 'Subtitle Styling & Presets...',
            sublabel = 'Presets, typography, box style & live timing',
            action = 'open_sub_config',
            current = false,
            index = #items + 1
        }
    elseif state.menu_active and state.menu_active:find('^sub_') then
        if ctx_ref.subtitle and ctx_ref.subtitle.get_menu_items then
            items = ctx_ref.subtitle.get_menu_items(state.menu_active)
        end
    elseif state.menu_active == 'video' then
        local contrast = mp.get_property_number('contrast', 0) or 0
        local brightness = mp.get_property_number('brightness', 0) or 0
        local saturation = mp.get_property_number('saturation', 0) or 0
        local gamma = mp.get_property_number('gamma', 0) or 0
        local aspect_num = mp.get_property_number('video-aspect-override', -1)
        local aspect_display = 'Auto (16:9)'
        if aspect_num and aspect_num > 0 then
            if math.abs(aspect_num - 16/9) < 0.05 then
                aspect_display = '16:9'
            elseif math.abs(aspect_num - 21/9) < 0.08 or math.abs(aspect_num - 2.35) < 0.08 then
                aspect_display = '21:9 (Ultrawide)'
            elseif math.abs(aspect_num - 4/3) < 0.05 then
                aspect_display = '4:3'
            else
                aspect_display = string.format('%.2f', aspect_num)
            end
        end
        local panscan = mp.get_property_number('panscan', 0.0) or 0.0
        local rotate = mp.get_property_number('video-rotate', 0) or 0
        local deint = mp.get_property('deinterlace', 'no') or 'no'
        local deint_names = {['no'] = 'Off', ['yes'] = 'Yes (yadif)', ['auto'] = 'Auto'}

        items[#items + 1] = {
            type = 'header',
            label = 'PICTURE TUNING',
            index = #items + 1
        }
        items[#items + 1] = {
            label = 'Contrast',
            value = string.format('%+d', contrast),
            type = 'stepper',
            on_prev = function() step_video_prop('contrast', -2, -100, 100) end,
            on_next = function() step_video_prop('contrast', 2, -100, 100) end,
            action = 'reset_contrast',
            index = #items + 1
        }
        items[#items + 1] = {
            label = 'Brightness',
            value = string.format('%+d', brightness),
            type = 'stepper',
            on_prev = function() step_video_prop('brightness', -2, -100, 100) end,
            on_next = function() step_video_prop('brightness', 2, -100, 100) end,
            action = 'reset_brightness',
            index = #items + 1
        }
        items[#items + 1] = {
            label = 'Saturation',
            value = string.format('%+d', saturation),
            type = 'stepper',
            on_prev = function() step_video_prop('saturation', -2, -100, 100) end,
            on_next = function() step_video_prop('saturation', 2, -100, 100) end,
            action = 'reset_saturation',
            index = #items + 1
        }
        items[#items + 1] = {
            label = 'Gamma',
            value = string.format('%+d', gamma),
            type = 'stepper',
            on_prev = function() step_video_prop('gamma', -2, -100, 100) end,
            on_next = function() step_video_prop('gamma', 2, -100, 100) end,
            action = 'reset_gamma',
            index = #items + 1
        }

        items[#items + 1] = {
            type = 'header',
            label = 'FRAMING & ASPECT',
            index = #items + 1
        }
        items[#items + 1] = {
            label = 'Aspect Ratio',
            value = aspect_display,
            type = 'stepper',
            on_prev = cycle_aspect_ratio,
            on_next = cycle_aspect_ratio,
            action = 'cycle_aspect',
            index = #items + 1
        }
        items[#items + 1] = {
            label = 'Pan & Scan',
            value = (panscan <= 0.001) and 'Fit (0.0)' or string.format('%.2f', panscan),
            type = 'stepper',
            on_prev = function() step_video_prop('panscan', -0.05, 0.0, 1.0) end,
            on_next = function() step_video_prop('panscan', 0.05, 0.0, 1.0) end,
            action = 'reset_panscan',
            index = #items + 1
        }
        items[#items + 1] = {
            label = 'Rotate',
            value = string.format('%d°', rotate),
            type = 'stepper',
            on_prev = function() cycle_rotate(-1) end,
            on_next = function() cycle_rotate(1) end,
            action = 'cycle_rotate',
            index = #items + 1
        }

        items[#items + 1] = {
            type = 'header',
            label = 'PROCESSING',
            index = #items + 1
        }
        items[#items + 1] = {
            label = 'Deinterlace',
            value = deint_names[deint] or deint:upper(),
            type = 'stepper',
            on_prev = cycle_deinterlace,
            on_next = cycle_deinterlace,
            action = 'cycle_deint',
            index = #items + 1
        }
        items[#items + 1] = {
            label = 'Reset All Picture Settings',
            action = 'reset_all_video',
            index = #items + 1
        }
    elseif state.menu_active == 'chapters' then
        local chapters = mp.get_property_native('chapter-list', {})
        local cur_ch = mp.get_property_number('chapter', -1)
        if not chapters or #chapters == 0 then
            items[1] = {label = '(No chapters in current media)', sublabel = 'Seekbar timeline and jump shortcuts are available', current = false, index = 0}
        else
            local utils = ctx_ref.utils
            local filter_pat = (menu_search_query ~= '') and menu_search_query:lower() or nil
            for i, ch in ipairs(chapters) do
                local title = (ch and ch.title and ch.title ~= '') and ch.title or ('Chapter ' .. i)
                local time_sec = ch and ch.time
                local time = (utils and utils.format_time) and utils.format_time(time_sec) or '00:00'
                local label = title
                if not label:lower():find('^chapter') then
                    label = string.format('Chapter %02d: %s', i, title)
                end
                local sublabel = string.format('Timestamp: %s', time)

                local matches_search = true
                if filter_pat then
                    local haystack = (label .. ' ' .. sublabel):lower()
                    matches_search = (haystack:find(filter_pat, 1, true) ~= nil)
                end

                if matches_search then
                    items[#items + 1] = {
                        label = label,
                        sublabel = sublabel,
                        time_str = time,
                        current = (i - 1 == cur_ch),
                        index = i - 1
                    }
                end
            end

            if #items == 0 and filter_pat then
                items[1] = {
                    label = 'No matching chapters found',
                    sublabel = string.format('Query: "%s"  (Press Backspace to edit or Esc to clear)', menu_search_query),
                    action = 'none',
                    current = false,
                    index = -1
                }
            end
        end
    elseif state.menu_active == 'tags' then
        local utils = ctx_ref.utils
        local path = mp.get_property('path', '')
        if utils and utils.is_url and utils.is_url(path) then
            items[1] = {
                label = '(Online Stream - Read-Only)',
                sublabel = 'Metadata tag editing is disabled for streaming URLs',
                action = 'none',
                index = 1
            }
            return items
        end

        local cur_title = mp.get_property('media-title') or mp.get_property('filename') or ''
        cur_title = cur_title:gsub('%.%w+$', '')

        local fn = mp.get_property('filename') or ''
        local show, s_num, e_num, year = utils.parse_clean_title(nil, fn)
        local derived_fn = (show and show ~= '') and (
            (s_num and e_num) and string.format('%s - S%02dE%02d', show, s_num, e_num)
            or (year and (show .. ' (' .. year .. ')') or show)
        ) or fn
        derived_fn = derived_fn:gsub('%.%w+$', '')

        local tmdb_curr = ctx_ref.get_tmdb_current and ctx_ref.get_tmdb_current()
        local tmdb_title = (tmdb_curr and tmdb_curr.show_name and tmdb_curr.show_name ~= '') and
            ((tmdb_curr.year and tmdb_curr.year ~= '') and (tmdb_curr.show_name .. ' (' .. tmdb_curr.year .. ')') or tmdb_curr.show_name) or nil

        -- Count files in current folder
        local filepath = mp.get_property('path', '')
        local dir = filepath:match('^(.*)/[^/]+$') or '.'
        local mkv_count = 0
        local utils_pkg = require and require('mp.utils') or nil
        local readdir = (utils_pkg and utils_pkg.readdir) or (mp.utils and mp.utils.readdir)
        local files = readdir and readdir(dir, 'files')
        if files then
            for _, f in ipairs(files) do
                if f:lower():match('%.mkv$') or f:lower():match('%.webm$') then
                    mkv_count = mkv_count + 1
                end
            end
        end

        if state.tag_inspector_confirm then
            items[1] = {
                label = 'Confirm & Apply',
                sublabel = state.tag_inspector_confirm_msg or 'Are you sure?',
                action = 'confirm_batch_yes',
                index = 1
            }
            items[2] = {
                label = 'Cancel',
                sublabel = 'Return to Inspector without modifying other files',
                action = 'confirm_batch_no',
                index = 2
            }
            return items
        end

        -- Section 2: Smart Quick-Fix Cards
        items[1] = {
            label = 'Clean Watermarks & Ads',
            sublabel = 'Strips URLs, encoders & track promo labels',
            action = 'clean_all',
            index = 1,
            role = 'smart_card'
        }
        items[2] = {
            label = 'Match Nearest Title (TMDB)',
            sublabel = tmdb_title and ('Search TMDB (Cached: "' .. tmdb_title:sub(1, 18) .. '")') or 'Fetch official title & metadata',
            action = 'search_tmdb_picker',
            index = 2,
            role = 'smart_card'
        }
        items[3] = {
            label = 'Use Clean Filename',
            sublabel = '"' .. derived_fn:sub(1, 26) .. '"',
            action = 'set_filename',
            index = 3,
            role = 'smart_card'
        }

        -- Section 3: Inline Manual Editor
        items[4] = {
            label = 'Manual Title Input',
            sublabel = state.tag_inspector_input or cur_title,
            action = 'edit_manual_inline',
            index = 4,
            role = 'manual_input'
        }
        items[5] = {
            label = 'Save & Apply',
            sublabel = 'Save title to file header',
            action = 'save_manual_inline',
            index = 5,
            role = 'manual_save'
        }

        -- Section 4: Advanced Tools
        items[6] = {
            label = state.tag_inspector_expanded and 'Advanced & Folder Tools [Collapse ▴]' or 'Advanced & Folder Tools [Expand Tools ▾]',
            sublabel = 'Batch operations & multi-file header tools',
            action = 'toggle_advanced',
            index = 6,
            role = 'advanced_toggle'
        }

        if state.tag_inspector_expanded then
            items[7] = {
                label = string.format('Batch Apply Title to Season Folder (%d files)', mkv_count),
                sublabel = 'Update header title for all MKV episodes in season directory',
                action = 'prompt_batch_apply',
                index = 7,
                role = 'batch_tool'
            }
            items[8] = {
                label = 'Strip All Header Titles in Directory [⚠ Danger Zone]',
                sublabel = 'Remove title tags from all video files in directory',
                action = 'prompt_batch_strip',
                index = 8,
                role = 'batch_tool'
            }
            items[9] = {
                label = 'Auto-reload playback after saving disk changes',
                sublabel = 'Seamlessly reload file at current second to update mpv track list',
                action = 'toggle_autoreload',
                index = 9,
                role = 'auto_reload'
            }
        else
            items[7] = {
                label = 'Auto-reload playback after saving disk changes',
                sublabel = 'Seamlessly reload file at current second to update mpv track list',
                action = 'toggle_autoreload',
                index = 7,
                role = 'auto_reload'
            }
        end
    elseif state.menu_active == 'tmdb_matches' then
        if tmdb_searching then
            items[1] = {
                label = 'Searching TheMovieDB for "' .. (tmdb_query_str or '') .. '"...',
                sublabel = 'Connecting to TMDB API to find exact movie / series matches...',
                action = 'none',
                index = 1
            }
        elseif not tmdb_matches_list or #tmdb_matches_list == 0 then
            items[1] = {
                label = '(No matching TMDB titles found)',
                sublabel = 'Press ENTER or ESC to return to Tags Inspector',
                action = 'back_to_tags',
                index = 1
            }
        else
            for i, cand in ipairs(tmdb_matches_list) do
                local type_str = (cand.media_type == 'tv' and 'TV Series') or 'Movie'
                local yr_str = (cand.year and cand.year ~= '') and (' (' .. cand.year .. ')') or ''
                local rat_str = (cand.rating and cand.rating ~= '') and ('  ·  ' .. cand.rating .. '/10') or ''
                local ov_str = (cand.overview and cand.overview ~= '') and ('  ·  ' .. cand.overview:sub(1, 45) .. '...') or ''
                items[i] = {
                    label = cand.title .. yr_str,
                    sublabel = type_str .. yr_str .. rat_str .. ov_str,
                    candidate_title = cand.title,
                    candidate_year = cand.year,
                    candidate_type = cand.media_type,
                    action = 'select_tmdb_match',
                    index = i
                }
            end
        end
    end
    cached_items = items
    cached_menu_type = state.menu_active
    return items
end

function M.menu_navigate(dir)
    local state = ctx_ref.state
    if state.menu_active == 'tags' then
        local items = M.menu_get_items()
        local count = #items
        if count == 0 then return end
        if state.tag_inspector_confirm then
            state.menu_selected = (state.menu_selected == 1) and 2 or 1
            if ctx_ref.request_tick then ctx_ref.request_tick() end
            return
        end
        local sel = state.menu_selected
        local expanded = state.tag_inspector_expanded == true
        if dir > 0 then
            if sel >= 1 and sel <= 3 then
                sel = 4
            elseif sel == 4 or sel == 5 then
                sel = 6
            elseif sel == 6 then
                sel = 7
            elseif sel == 7 then
                sel = expanded and 8 or 1
            elseif sel == 8 then
                sel = expanded and 9 or 1
            elseif sel >= 9 then
                sel = 1
            else
                sel = 1
            end
        else
            if sel >= 1 and sel <= 3 then
                sel = expanded and 9 or 7
            elseif sel == 4 or sel == 5 then
                sel = 1
            elseif sel == 6 then
                sel = 4
            elseif sel == 7 then
                sel = 6
            elseif sel == 8 then
                sel = 7
            elseif sel >= 9 then
                sel = 8
            else
                sel = 1
            end
        end
        state.menu_selected = math.max(1, math.min(count, sel))
        if ctx_ref.request_tick then ctx_ref.request_tick() end
        return
    end

    local items = M.menu_get_items()
    local count = #items
    if count == 0 then return end
    local sel = state.menu_selected
    for _ = 1, count do
        sel = sel + dir
        if sel < 1 then sel = count end
        if sel > count then sel = 1 end
        if not (items[sel] and items[sel].type == 'header') then
            state.menu_selected = sel
            break
        end
    end
    if ctx_ref.request_tick then ctx_ref.request_tick() end
end

function M.menu_confirm()
    local state = ctx_ref.state
    local items = M.menu_get_items()
    local item = items[state.menu_selected]
    if not item or item.type == 'header' then return end

    if state.menu_active == 'playlist' then
        mp.commandv('playlist-play-index', item.index - 1)
    elseif state.menu_active == 'chapters' then
        mp.commandv('set', 'chapter', tostring(item.index))
    elseif state.menu_active == 'audio' then
        if item.action == 'toggle_night_mode' then
            toggle_night_mode()
            M.invalidate_items()
            if ctx_ref.request_tick then ctx_ref.request_tick() end
            return
        elseif item.action == 'reset_audio_delay' then
            reset_audio_delay()
            M.invalidate_items()
            if ctx_ref.request_tick then ctx_ref.request_tick() end
            return
        elseif item.type == 'stepper' and item.on_next then
            item.on_next()
            M.invalidate_items()
            if ctx_ref.request_tick then ctx_ref.request_tick() end
            return
        elseif item.track_id then
            mp.commandv('set', 'aid', tostring(item.track_id))
        end
    elseif state.menu_active == 'video' then
        if item.action == 'reset_all_video' then
            reset_video_settings()
            M.invalidate_items()
            if ctx_ref.request_tick then ctx_ref.request_tick() end
            return
        elseif item.type == 'stepper' and item.on_next then
            item.on_next()
            M.invalidate_items()
            if ctx_ref.request_tick then ctx_ref.request_tick() end
            return
        end
    elseif state.menu_active == 'sub' then
        if item.action == 'open_sub_config' then
            state.menu_active = 'sub_config'
            state.menu_selected = 1
            state.menu_scroll = 0
            M.invalidate_items()
            if ctx_ref.subtitle then ctx_ref.subtitle.set_live_preview(true) end
            if ctx_ref.request_tick then ctx_ref.request_tick() end
            return
        elseif item.track_id then
            mp.commandv('set', 'sid', tostring(item.track_id))
        end
    elseif state.menu_active and state.menu_active:find('^sub_') then
        if item.action == 'nav_menu' and item.target then
            state.menu_active = item.target
            state.menu_selected = 1
            state.menu_scroll = 0
            M.invalidate_items()
            if state.menu_active == 'sub' then
                if ctx_ref.subtitle then ctx_ref.subtitle.set_live_preview(false) end
            else
                if ctx_ref.subtitle then ctx_ref.subtitle.set_live_preview(true) end
            end
            if ctx_ref.request_tick then ctx_ref.request_tick() end
            return
        elseif item.type == 'stepper' and item.on_next then
            item.on_next()
            M.invalidate_items()
            if ctx_ref.request_tick then ctx_ref.request_tick() end
            return
        elseif ctx_ref.subtitle and ctx_ref.subtitle.handle_action then
            ctx_ref.subtitle.handle_action(item)
            M.invalidate_items()
            if ctx_ref.request_tick then ctx_ref.request_tick() end
            return
        end
    elseif state.menu_active == 'tags' then
        local tag_editor = ctx_ref.tag_editor
        local utils = ctx_ref.utils
        if item.action == 'search_tmdb_picker' then
            local fn = mp.get_property('filename') or ''
            local filepath = mp.get_property('path', '')
            local parent_dir_title = nil
            if filepath ~= '' then
                local parent = filepath:match('([^/]+)/[^/]+$')
                if parent then
                    parent_dir_title = parent:gsub('%s[Ss]%d+.*$', ''):gsub('%b[]', ''):gsub('%([Ss]eason%s*%d+%)', ''):gsub('`', "'"):gsub('%s+', ' '):gsub('^%s+', ''):gsub('%s+$', '')
                end
            end
            local show, _, _, _ = utils.parse_clean_title(mp.get_property('media-title'), fn, filepath)
            local tmdb_curr = ctx_ref.get_tmdb_current and ctx_ref.get_tmdb_current()
            local default_query = (tmdb_curr and tmdb_curr.show_name and tmdb_curr.show_name ~= '') and tmdb_curr.show_name
                or ((show and show ~= '' and #show > 3) and show or (parent_dir_title or fn:gsub('%.%w+$', '')))
            if default_query then
                default_query = default_query:gsub('%s*%(%d%d%d%d%)', ''):gsub('^%s+', ''):gsub('%s+$', '')
            end

            M.menu_close()
            tag_editor.input_box_open('SEARCH TMDB MATCHES', default_query, function(query_text)
                if query_text and query_text ~= '' then
                    tmdb_searching = true
                    tmdb_query_str = query_text
                    tmdb_matches_list = {}
                    M.menu_open('tmdb_matches')

                    local ss = ctx_ref.screensaver
                    if ss and ss.fetch_candidates then
                        ss.fetch_candidates(query_text, function(results)
                            tmdb_searching = false
                            if state.menu_active == 'tmdb_matches' then
                                tmdb_matches_list = results or {}
                                state.menu_selected = 1
                                state.menu_scroll = 0
                                M.invalidate_items()
                                if ctx_ref.request_tick then ctx_ref.request_tick() end
                            end
                        end)
                    else
                        tmdb_searching = false
                        tmdb_matches_list = {}
                        M.invalidate_items()
                        if ctx_ref.request_tick then ctx_ref.request_tick() end
                    end
                else
                    M.menu_open('tags')
                    state.menu_selected = 2
                end
            end, function()
                M.menu_open('tags')
                state.menu_selected = 2
            end)
        elseif item.action == 'clean_all' then
            tag_editor.clean_all_mkv_watermarks(function()
                M.invalidate_items()
                if ctx_ref.on_tag_updated then ctx_ref.on_tag_updated(true) end
                if ctx_ref.request_tick then ctx_ref.request_tick() end
            end)
        elseif item.action == 'apply_tmdb' then
            local tmdb_curr = ctx_ref.get_tmdb_current and ctx_ref.get_tmdb_current()
            local tmdb_title = (tmdb_curr and tmdb_curr.show_name and tmdb_curr.show_name ~= '') and
                ((tmdb_curr.year and tmdb_curr.year ~= '') and (tmdb_curr.show_name .. ' (' .. tmdb_curr.year .. ')') or tmdb_curr.show_name) or nil
            if tmdb_title then
                tag_editor.apply_mkv_title(tmdb_title, function()
                    M.invalidate_items()
                    if ctx_ref.on_tag_updated then ctx_ref.on_tag_updated(true) end
                    if ctx_ref.request_tick then ctx_ref.request_tick() end
                end)
            end
        elseif item.action == 'set_filename' then
            local fn = mp.get_property('filename') or ''
            local show, s_num, e_num, year = utils.parse_clean_title(nil, fn)
            local derived = (show and show ~= '') and (
                (s_num and e_num) and string.format('%s - S%02dE%02d', show, s_num, e_num)
                or (year and (show .. ' (' .. year .. ')') or show)
            ) or fn
            derived = derived:gsub('%.%w+$', '')
            tag_editor.apply_mkv_title(derived, function()
                M.invalidate_items()
                if ctx_ref.on_tag_updated then ctx_ref.on_tag_updated(true) end
                if ctx_ref.request_tick then ctx_ref.request_tick() end
            end)
        elseif item.action == 'edit_manual_inline' then
            local cur = state.tag_inspector_input or mp.get_property('media-title') or mp.get_property('filename') or ''
            cur = cur:gsub('%.%w+$', '')
            M.menu_close()
            tag_editor.input_box_open('EDIT MOVIE / SERIES TITLE', cur, function(new_val)
                if new_val and new_val ~= '' then
                    state.tag_inspector_input = new_val
                end
                M.menu_open('tags')
                state.menu_selected = 5
            end, function()
                M.menu_open('tags')
                state.menu_selected = 4
            end)
        elseif item.action == 'save_manual_inline' then
            local cur = state.tag_inspector_input or mp.get_property('media-title') or mp.get_property('filename') or ''
            cur = cur:gsub('%.%w+$', '')
            if cur ~= '' then
                tag_editor.apply_mkv_title(cur, function()
                    state.tag_inspector_input = nil
                    M.invalidate_items()
                    if ctx_ref.on_tag_updated then ctx_ref.on_tag_updated(true) end
                    if ctx_ref.request_tick then ctx_ref.request_tick() end
                end)
            end
        elseif item.action == 'toggle_advanced' then
            state.tag_inspector_expanded = not (state.tag_inspector_expanded == true)
            M.invalidate_items()
            if ctx_ref.request_tick then ctx_ref.request_tick() end
        elseif item.action == 'prompt_batch_apply' then
            local fn = mp.get_property('filename') or ''
            local show, s_num, e_num, year = utils.parse_clean_title(nil, fn)
            local derived = (show and show ~= '') and (
                (s_num and e_num) and string.format('%s - S%02dE%02d', show, s_num, e_num)
                or (year and (show .. ' (' .. year .. ')') or show)
            ) or fn
            local target_title = state.tag_inspector_input or derived:gsub('%.%w+$', '')
            state.tag_inspector_confirm = 'batch_apply'
            state.tag_inspector_confirm_msg = string.format('Apply title "%s" across all MKV files in folder?', target_title)
            state.menu_selected = 1
            M.invalidate_items()
            if ctx_ref.request_tick then ctx_ref.request_tick() end
        elseif item.action == 'prompt_batch_strip' then
            state.tag_inspector_confirm = 'batch_strip'
            state.tag_inspector_confirm_msg = 'Strip all container title tags across all MKV files in folder?'
            state.menu_selected = 1
            M.invalidate_items()
            if ctx_ref.request_tick then ctx_ref.request_tick() end
        elseif item.action == 'confirm_batch_yes' then
            if state.tag_inspector_confirm == 'batch_apply' then
                local fn = mp.get_property('filename') or ''
                local show, s_num, e_num, year = utils.parse_clean_title(nil, fn)
                local derived = (show and show ~= '') and (
                    (s_num and e_num) and string.format('%s - S%02dE%02d', show, s_num, e_num)
                    or (year and (show .. ' (' .. year .. ')') or show)
                ) or fn
                local target_title = state.tag_inspector_input or derived:gsub('%.%w+$', '')
                tag_editor.apply_mkv_title_folder(target_title, function()
                    state.tag_inspector_confirm = nil
                    M.invalidate_items()
                    if ctx_ref.on_tag_updated then ctx_ref.on_tag_updated(true) end
                    if ctx_ref.request_tick then ctx_ref.request_tick() end
                end)
            elseif state.tag_inspector_confirm == 'batch_strip' then
                tag_editor.delete_mkv_title_folder(function()
                    state.tag_inspector_confirm = nil
                    M.invalidate_items()
                    if ctx_ref.on_tag_updated then ctx_ref.on_tag_updated(true) end
                    if ctx_ref.request_tick then ctx_ref.request_tick() end
                end)
            end
        elseif item.action == 'confirm_batch_no' then
            state.tag_inspector_confirm = nil
            state.menu_selected = 6
            M.invalidate_items()
            if ctx_ref.request_tick then ctx_ref.request_tick() end
        elseif item.action == 'toggle_autoreload' then
            local cur = tag_editor.get_auto_reload and tag_editor.get_auto_reload() or false
            if tag_editor.set_auto_reload then
                tag_editor.set_auto_reload(not cur)
            end
            M.invalidate_items()
            if ctx_ref.request_tick then ctx_ref.request_tick() end
        end
        return
    elseif state.menu_active == 'tmdb_matches' then
        local tag_editor = ctx_ref.tag_editor
        local utils = ctx_ref.utils
        if item.action == 'select_tmdb_match' and item.candidate_title then
            local cand_title = item.candidate_title
            local fn = mp.get_property('filename') or ''
            local show, s_num, e_num, year = utils and utils.parse_clean_title(nil, fn) or nil
            local final_title = cand_title
            if s_num and e_num then
                final_title = string.format('%s - S%02dE%02d', cand_title, s_num, e_num)
            elseif item.candidate_year and item.candidate_year ~= '' and not cand_title:find('%(' .. item.candidate_year .. '%)') then
                final_title = string.format('%s (%s)', cand_title, item.candidate_year)
            end
            tag_editor.apply_mkv_title(final_title, function()
                if ctx_ref.on_tag_updated then
                    ctx_ref.on_tag_updated(true)
                end
                mp.osd_message('✓ TMDB Match Applied: ' .. final_title, 3)
                M.menu_open('tags')
                state.menu_selected = 2
            end)
        elseif item.action == 'back_to_tags' then
            M.menu_open('tags')
            state.menu_selected = 2
        end
        return
    end
    M.menu_close()
end

function M.menu_handle_click()
    local state = ctx_ref.state
    if not state.menu_active then return end
    local mx, my = ctx_ref.get_virt_mouse_pos()

    if state.menu_active == 'tags' then
        if tag_inspector_boxes['close'] then
            local b = tag_inspector_boxes['close']
            if mx >= b.x1 and mx <= b.x2 and my >= b.y1 and my <= b.y2 then
                M.menu_close()
                return
            end
        end
        for idx, b in pairs(tag_inspector_boxes) do
            if type(idx) == 'number' and mx >= b.x1 and mx <= b.x2 and my >= b.y1 and my <= b.y2 then
                state.menu_selected = idx
                M.menu_confirm()
                return
            end
        end
        return
    end

    local items  = M.menu_get_items()
    local is_pl  = (state.menu_active == 'playlist')
    local osc_param = ctx_ref.osc_param
    local is_sub_menu = state.menu_active and (
        state.menu_active:find('^sub_') ~= nil or
        state.menu_active == 'sub'
    )
    local is_drawer = state.menu_active and (
        is_sub_menu or
        state.menu_active == 'audio' or
        state.menu_active == 'video'
    )

    local menu_w, row_h, header_h, footer_h, pad_bot, x0, y0, visible_max, scroll, vis, menu_h
    local is_searchable = not is_drawer and (state.menu_active == 'playlist' or state.menu_active == 'chapters') and (state.menu_searchable == true or (state.menu_searchable == nil and #items > 5))
    local search_h = is_searchable and 42 or 0

    if is_drawer then
        menu_w    = math.max(360, math.min(420, math.floor(osc_param.playresx * 0.30)))
        local has_any_sublabel = false
        for _, item in ipairs(items) do
            if item.sublabel and item.sublabel ~= '' then
                has_any_sublabel = true
                break
            end
        end
        local is_video_menu = (state.menu_active == 'video')
        row_h     = is_video_menu and 34 or (has_any_sublabel and 52 or 40)
        header_h  = 48
        footer_h  = 34
        pad_bot   = 0
        local cx  = math.floor(osc_param.playresx / 2)
        local cy  = math.floor(osc_param.playresy / 2)
        local y_safe_top = is_sub_menu and 22 or 24
        local y_safe_bot = is_sub_menu and math.floor(osc_param.playresy * 0.78) or (osc_param.playresy - 24)
        visible_max = math.max(1, math.floor((y_safe_bot - y_safe_top - header_h - footer_h) / row_h))
        scroll    = state.menu_scroll or 0
        vis       = math.min(#items - scroll, visible_max)
        menu_h    = header_h + vis * row_h + footer_h
        if is_sub_menu then
            x0    = math.max(20, math.floor(osc_param.playresx * 0.02))
            y0    = y_safe_top
        else
            x0    = math.floor(cx - menu_w / 2)
            y0    = math.max(y_safe_top, math.floor(cy - menu_h / 2))
        end
    else
        local is_wide = is_pl or (state.menu_active == 'chapters') or (state.menu_active == 'tags') or (state.menu_active == 'tmdb_matches')
        menu_w = is_wide and math.min(920, math.floor(osc_param.playresx * 0.90)) or math.min(740, math.floor(osc_param.playresx * 0.88))
        local has_any_sublabel = false
        for _, item in ipairs(items) do
            if item.sublabel and item.sublabel ~= '' then
                has_any_sublabel = true
                break
            end
        end
        row_h    = (is_pl or state.menu_active == 'tags' or has_any_sublabel) and 60 or 46
        header_h = 56
        footer_h = 36
        pad_bot  = 0
        local y_safe_top = 24
        local y_safe_bot = osc_param.playresy - 24
        visible_max = math.max(1, math.min(
            (is_pl or state.menu_active == 'chapters') and 8 or 7,
            math.floor((y_safe_bot - y_safe_top - header_h - search_h - footer_h) / row_h)
        ))
        scroll = state.menu_scroll or 0
        vis    = math.min(#items - scroll, visible_max)
        local card_vis = is_searchable and math.max(vis, math.min(6, visible_max)) or vis
        menu_h = header_h + search_h + card_vis * row_h + footer_h
        local cx = math.floor(osc_param.playresx / 2)
        local cy = math.floor(osc_param.playresy / 2)
        x0 = math.floor(cx - menu_w / 2)
        y0 = math.max(y_safe_top, math.floor(cy - menu_h / 2))
    end

    if mx < x0 or mx > x0 + menu_w or my < y0 or my > y0 + menu_h then
        M.menu_close()
        return
    end

    -- Header click
    if my >= y0 and my < y0 + header_h then
        if is_drawer then
            if mx < x0 + 64 then
                -- Clicked ESC / back
                if state.menu_active and state.menu_active:find('^sub_') and state.menu_active ~= 'sub_config' then
                    state.menu_active = 'sub_config'
                    state.menu_selected = 1
                    state.menu_scroll = 0
                    M.invalidate_items()
                elseif state.menu_active == 'sub_config' then
                    state.menu_active = 'sub'
                    state.menu_selected = 1
                    state.menu_scroll = 0
                    M.invalidate_items()
                    if ctx_ref.subtitle and ctx_ref.subtitle.set_live_preview then
                        ctx_ref.subtitle.set_live_preview(false)
                    end
                else
                    M.menu_close()
                end
                if ctx_ref.request_tick then ctx_ref.request_tick() end
                return
            elseif mx >= x0 + menu_w - 70 then
                if state.menu_active == 'sub' then
                    state.menu_active = 'sub_config'
                    state.menu_selected = 1
                    state.menu_scroll = 0
                    M.invalidate_items()
                    if ctx_ref.subtitle and ctx_ref.subtitle.set_live_preview then
                        ctx_ref.subtitle.set_live_preview(true)
                    end
                    if ctx_ref.request_tick then ctx_ref.request_tick() end
                    return
                elseif state.menu_active == 'sub_config' then
                    state.menu_active = 'sub'
                    state.menu_selected = 1
                    state.menu_scroll = 0
                    M.invalidate_items()
                    if ctx_ref.subtitle and ctx_ref.subtitle.set_live_preview then
                        ctx_ref.subtitle.set_live_preview(false)
                    end
                    if ctx_ref.request_tick then ctx_ref.request_tick() end
                    return
                else
                    M.menu_close()
                    return
                end
            end
            return
        else
            -- Clicked 'X' close button on top-right of centered modal card
            if mx >= x0 + menu_w - 56 then
                M.menu_close()
                return
            end
            if state.menu_active == 'playlist' and state.playlist_is_series then
                state.playlist_filter_series = not state.playlist_filter_series
                M.invalidate_items()
                local new_items = M.menu_get_items()
                local cur_i = 1
                for i, it in ipairs(new_items) do
                    if it.current then cur_i = i; break end
                end
                state.menu_selected = cur_i
                state.menu_scroll = math.max(0, cur_i - 5)
                if ctx_ref.request_tick then ctx_ref.request_tick() end
                return
            end
            return
        end
    end

    -- Search bar clear click
    if is_searchable and my >= y0 + header_h and my < y0 + header_h + search_h then
        if mx >= x0 + menu_w - 90 and menu_search_query ~= '' then
            menu_search_query = ''
            state.menu_selected = 1
            state.menu_scroll = 0
            M.invalidate_items()
            if ctx_ref.request_tick then ctx_ref.request_tick() end
        end
        return
    end

    -- Row click
    for i = 1, vis do
        local ry = y0 + header_h + (is_searchable and search_h or 0) + (i - 1) * row_h
        local ai = i + scroll
        if my >= ry and my < ry + row_h and ai <= #items then
            local item = items[ai]
            if item.type == 'header' then return end
            state.menu_selected = ai
            if is_drawer and (item.type == 'stepper' or item.on_prev or item.on_next) then
                local rel_x = mx - x0
                if rel_x >= menu_w * 0.45 then
                    if rel_x < menu_w * 0.72 then
                        if item.on_prev then item.on_prev() end
                    else
                        if item.on_next then item.on_next() end
                    end
                    M.invalidate_items()
                    if ctx_ref.request_tick then ctx_ref.request_tick() end
                    return
                end
            end
            M.menu_confirm()
            return
        end
    end
end

function M.menu_open(menu_type)
    pcall(mp.commandv, 'overlay-remove', 1)
    if ctx_ref.inhibit_screensaver then ctx_ref.inhibit_screensaver() end
    M.invalidate_items()
    if ctx_ref.on_open then ctx_ref.on_open() end

    local state = ctx_ref.state
    state.menu_active = menu_type
    state.menu_selected = 1
    state.menu_scroll = 0
    menu_alpha   = 0
    menu_closing = false
    menu_bar_anim_y = nil
    menu_bar_last_t = nil

    if menu_type and menu_type:find('^sub_') then
        if ctx_ref.subtitle and ctx_ref.subtitle.set_live_preview then
            ctx_ref.subtitle.set_live_preview(true)
        end
    end

    menu_search_query = ''
    local items = M.menu_get_items()
    local matched_idx = nil
    for i, it in ipairs(items) do
        if it.current and it.type ~= 'header' then
            matched_idx = i
            break
        end
    end
    if matched_idx then
        state.menu_selected = matched_idx
    else
        state.menu_selected = 1
        if items[1] and items[1].type == 'header' then
            for i, it in ipairs(items) do
                if it.type ~= 'header' then
                    state.menu_selected = i
                    break
                end
            end
        end
    end

    menu_key_bindings = {}
    local function bind_keys(k1, k2, name, fn, flags)
        menu_add_binding(k1, name, fn, flags)
        if k2 and k2 ~= k1 then
            menu_add_binding(k2, name .. '_alt', fn, flags)
        end
    end

    local is_searchable_candidate = (menu_type == 'playlist' or menu_type == 'chapters')
    local is_searchable_open = is_searchable_candidate and (#items > 5)
    state.menu_searchable = is_searchable_open

    if state.menu_searchable then
        local function handle_char_input(c)
            if ctx_ref.inhibit_screensaver then ctx_ref.inhibit_screensaver() end
            menu_search_query = menu_search_query .. c
            state.menu_selected = 1
            state.menu_scroll = 0
            M.invalidate_items()
            if ctx_ref.request_tick then ctx_ref.request_tick() end
        end
        local function handle_backspace()
            if ctx_ref.inhibit_screensaver then ctx_ref.inhibit_screensaver() end
            if #menu_search_query > 0 then
                menu_search_query = menu_search_query:sub(1, -2)
                state.menu_selected = 1
                state.menu_scroll = 0
                M.invalidate_items()
                if ctx_ref.request_tick then ctx_ref.request_tick() end
            end
        end

        bind_keys('BS', 'backspace', 'menu-bs', handle_backspace, 'repeatable')
        bind_keys('DEL', 'del', 'menu-del', handle_backspace, 'repeatable')
        menu_add_binding('SPACE', 'menu-char-space', function() handle_char_input(' ') end)

        local chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_.,'\"/()[]{}:;+*!@#$%&="
        for i = 1, #chars do
            local c = chars:sub(i, i)
            menu_add_binding(c, 'menu-char-' .. i, function() handle_char_input(c) end)
        end
    end

    bind_keys('UP', 'up', 'menu-up', function()
        if ctx_ref.inhibit_screensaver then ctx_ref.inhibit_screensaver() end
        M.menu_navigate(-1)
    end, 'repeatable')
    bind_keys('DOWN', 'down', 'menu-down', function()
        if ctx_ref.inhibit_screensaver then ctx_ref.inhibit_screensaver() end
        M.menu_navigate(1)
    end, 'repeatable')
    bind_keys('WHEEL_UP', 'wheel_up', 'menu-wheel-up', function()
        if ctx_ref.inhibit_screensaver then ctx_ref.inhibit_screensaver() end
        M.menu_navigate(-1)
    end)
    bind_keys('WHEEL_DOWN', 'wheel_down', 'menu-wheel-down', function()
        if ctx_ref.inhibit_screensaver then ctx_ref.inhibit_screensaver() end
        M.menu_navigate(1)
    end)
    bind_keys('LEFT', 'left', 'menu-left', function()
        if ctx_ref.inhibit_screensaver then ctx_ref.inhibit_screensaver() end
        if state.menu_active == 'tags' then
            if state.tag_inspector_confirm then
                state.menu_selected = (state.menu_selected == 1) and 2 or 1
                if ctx_ref.request_tick then ctx_ref.request_tick() end
                return
            end
            local sel = state.menu_selected
            if sel == 2 then state.menu_selected = 1
            elseif sel == 3 then state.menu_selected = 2
            elseif sel == 1 then state.menu_selected = 3
            elseif sel == 5 then state.menu_selected = 4
            elseif sel == 4 then state.menu_selected = 5
            end
            if ctx_ref.request_tick then ctx_ref.request_tick() end
            return
        end
        local items = M.menu_get_items()
        local item = items[state.menu_selected]
        if item and item.on_prev then
            item.on_prev()
            M.invalidate_items()
            if ctx_ref.request_tick then ctx_ref.request_tick() end
            return
        end
    end)
    bind_keys('RIGHT', 'right', 'menu-right', function()
        if ctx_ref.inhibit_screensaver then ctx_ref.inhibit_screensaver() end
        if state.menu_active == 'tags' then
            if state.tag_inspector_confirm then
                state.menu_selected = (state.menu_selected == 1) and 2 or 1
                if ctx_ref.request_tick then ctx_ref.request_tick() end
                return
            end
            local sel = state.menu_selected
            if sel == 1 then state.menu_selected = 2
            elseif sel == 2 then state.menu_selected = 3
            elseif sel == 3 then state.menu_selected = 1
            elseif sel == 4 then state.menu_selected = 5
            elseif sel == 5 then state.menu_selected = 4
            end
            if ctx_ref.request_tick then ctx_ref.request_tick() end
            return
        end
        local items = M.menu_get_items()
        local item = items[state.menu_selected]
        if item and item.on_next then
            item.on_next()
            M.invalidate_items()
            if ctx_ref.request_tick then ctx_ref.request_tick() end
            return
        end
    end)
    bind_keys('ENTER', 'enter', 'menu-enter', function() M.menu_confirm() end)
    bind_keys('ESC', 'esc', 'menu-esc', function()
        if state.menu_active == 'tags' and state.tag_inspector_confirm then
            state.tag_inspector_confirm = nil
            state.menu_selected = 6
            M.invalidate_items()
            if ctx_ref.request_tick then ctx_ref.request_tick() end
            return
        end
        if state.menu_searchable and menu_search_query ~= '' then
            menu_search_query = ''
            state.menu_selected = 1
            state.menu_scroll = 0
            M.invalidate_items()
            if ctx_ref.request_tick then ctx_ref.request_tick() end
            return
        end
        if state.menu_active and state.menu_active:find('^sub_') and state.menu_active ~= 'sub_config' then
            state.menu_active = 'sub_config'
            state.menu_selected = 1
            state.menu_scroll = 0
            M.invalidate_items()
            if ctx_ref.request_tick then ctx_ref.request_tick() end
        elseif state.menu_active == 'sub_config' then
            state.menu_active = 'sub'
            state.menu_selected = 1
            state.menu_scroll = 0
            M.invalidate_items()
            if ctx_ref.subtitle and ctx_ref.subtitle.set_live_preview then
                ctx_ref.subtitle.set_live_preview(false)
            end
            if ctx_ref.request_tick then ctx_ref.request_tick() end
        elseif state.menu_active == 'tmdb_matches' then
            M.menu_open('tags')
            state.menu_selected = 2
            return
        else
            M.menu_close()
        end
    end)
    bind_keys('TAB', 'tab', 'menu-tab', function()
        if state.menu_active == 'playlist' and state.playlist_is_series then
            state.playlist_filter_series = not state.playlist_filter_series
            M.invalidate_items()
            local new_items = M.menu_get_items()
            local cur_i = 1
            for i, it in ipairs(new_items) do
                if it.current then cur_i = i; break end
            end
            state.menu_selected = cur_i
            state.menu_scroll = math.max(0, cur_i - 5)
            if ctx_ref.request_tick then ctx_ref.request_tick() end
        elseif state.menu_active == 'sub' then
            state.menu_active = 'sub_config'
            state.menu_selected = 1
            state.menu_scroll = 0
            M.invalidate_items()
            if ctx_ref.subtitle and ctx_ref.subtitle.set_live_preview then
                ctx_ref.subtitle.set_live_preview(true)
            end
            if ctx_ref.request_tick then ctx_ref.request_tick() end
        elseif state.menu_active and state.menu_active:find('^sub_') then
            state.menu_active = 'sub'
            state.menu_selected = 1
            state.menu_scroll = 0
            M.invalidate_items()
            if ctx_ref.subtitle and ctx_ref.subtitle.set_live_preview then
                ctx_ref.subtitle.set_live_preview(false)
            end
            if ctx_ref.request_tick then ctx_ref.request_tick() end
        end
    end)
    bind_keys('MBTN_LEFT', 'mbtn_left', 'menu-click', function()
        if ctx_ref.inhibit_screensaver then ctx_ref.inhibit_screensaver() end
        M.menu_handle_click()
    end)
    if ctx_ref.request_tick then ctx_ref.request_tick() end
end

-- Inspector-Style Centered Modal for Tag Editor
local function render_tag_inspector(ass, osc_param, font, eff_alpha, items)
    tag_inspector_boxes = {}
    local state = ctx_ref.state
    local utils = ctx_ref.utils
    local tag_editor = ctx_ref.tag_editor
    local auto_reload = tag_editor and tag_editor.get_auto_reload and tag_editor.get_auto_reload() or false

    local menu_w = math.min(860, math.floor(osc_param.playresx * 0.92))
    local expanded = (state.tag_inspector_expanded == true)
    local is_confirm = (state.tag_inspector_confirm ~= nil)

    local header_h = 46
    local health_h = 92
    local smart_h  = 102
    local manual_h = 66
    local adv_h    = expanded and 112 or 36
    local auto_h   = 36
    local pad_bot  = 14
    local menu_h   = header_h + health_h + smart_h + manual_h + adv_h + auto_h + pad_bot
    if is_confirm then
        menu_h = 240
    end

    local x0 = math.floor((osc_param.playresx - menu_w) / 2)
    local y0 = math.max(16, math.floor((osc_param.playresy - menu_h) / 2))

    local dim_a = string.format('%02X', math.floor(255 - (110 * eff_alpha / 255)))
    local pan_a = string.format('%02X', math.floor(255 - (230 * eff_alpha / 255)))

    -- Dimmer
    ass:new_event()
    ass:pos(0, 0)
    ass:an(7)
    ass:append('{\\bord0\\blur0\\1c&H000000&\\1a&H' .. dim_a .. '&}')
    ass:draw_start()
    ass:rect_cw(0, 0, osc_param.playresx, osc_param.playresy)
    ass:draw_stop()

    -- Modal panel
    ass:new_event()
    ass:pos(x0, y0)
    ass:an(7)
    ass:append('{\\bord1.2\\blur0.5\\1c&H161614&\\3c&HFFFFFF&\\3a&HD0&\\1a&H' .. pan_a .. '&}')
    ass:draw_start()
    ass:round_rect_cw(0, 0, menu_w, menu_h, 16)
    ass:draw_stop()

    if is_confirm then
        ass:new_event()
        ass:pos(x0 + menu_w / 2, y0 + 36)
        ass:an(5)
        ass:append(string.format('{\\bord0\\blur0\\1c&H0095FF&\\fs14\\fn%s\\b700\\fsp1}⚠ CONFIRM BATCH OPERATION', font))

        local msg = state.tag_inspector_confirm_msg or 'Are you sure you want to perform this batch operation?'
        ass:new_event()
        ass:pos(x0 + menu_w / 2, y0 + 80)
        ass:an(5)
        ass:append(string.format('{\\bord0\\blur0\\1c&HE0E0E0&\\fs12\\fn%s\\b500}%s', font, utils and utils.ass_escape(msg) or msg))

        ass:new_event()
        ass:pos(x0 + menu_w / 2, y0 + 110)
        ass:an(5)
        ass:append(string.format('{\\bord0\\blur0\\1c&H8E8E93&\\fs10\\fn%s}This will write directly to Matroska file headers on disk.', font))

        local btn_w = 190
        local btn_h = 38
        local btn_y = y0 + 150
        local b1_x = x0 + menu_w / 2 - btn_w - 16
        local b2_x = x0 + menu_w / 2 + 16

        local sel1 = (state.menu_selected == 1)
        tag_inspector_boxes[1] = { x1 = b1_x, y1 = btn_y, x2 = b1_x + btn_w, y2 = btn_y + btn_h }
        ass:new_event()
        ass:pos(b1_x, btn_y)
        ass:an(7)
        local b1_fill = sel1 and '&H1818E0&' or '&H1818A0&'
        local b1_bord = sel1 and '&H7080FF&' or '&H3030D0&'
        ass:append('{\\bord' .. (sel1 and '2.0' or '1.0') .. '\\1c' .. b1_fill .. '\\3c' .. b1_bord .. '\\1a&H00&}')
        ass:draw_start()
        ass:round_rect_cw(0, 0, btn_w, btn_h, 8)
        ass:draw_stop()
        ass:new_event()
        ass:pos(b1_x + btn_w / 2, btn_y + btn_h / 2)
        ass:an(5)
        ass:append(string.format('{\\bord0\\1c&HFFFFFF&\\fs12\\fn%s\\b800}Confirm & Apply', font))

        local sel2 = (state.menu_selected == 2)
        tag_inspector_boxes[2] = { x1 = b2_x, y1 = btn_y, x2 = b2_x + btn_w, y2 = btn_y + btn_h }
        ass:new_event()
        ass:pos(b2_x, btn_y)
        ass:an(7)
        local b2_fill = sel2 and '&H555550&' or '&H222220&'
        local b2_bord = sel2 and '&HFFFFFF&' or '&H333330&'
        ass:append('{\\bord' .. (sel2 and '2.0' or '1.0') .. '\\1c' .. b2_fill .. '\\3c' .. b2_bord .. '\\1a&H00&}')
        ass:draw_start()
        ass:round_rect_cw(0, 0, btn_w, btn_h, 8)
        ass:draw_stop()
        ass:new_event()
        ass:pos(b2_x + btn_w / 2, btn_y + btn_h / 2)
        ass:an(5)
        ass:append(string.format('{\\bord0\\1c&HFFFFFF&\\fs12\\fn%s\\b700}Cancel', font))

        return
    end

    -- Header Bar
    ass:new_event()
    ass:pos(x0 + 24, y0 + 24)
    ass:an(4)
    ass:append(string.format('{\\bord0\\blur0\\1c&HFFFFFF&\\fs12\\fn%s\\b700\\fsp2}METADATA & TAG INSPECTOR', font))

    -- [Esc] ✕ Button
    local esc_w, esc_h = 58, 24
    local esc_x = x0 + menu_w - esc_w - 20
    local esc_y = y0 + 12
    tag_inspector_boxes['close'] = { x1 = esc_x, y1 = esc_y, x2 = esc_x + esc_w, y2 = esc_y + esc_h }
    ass:new_event()
    ass:pos(esc_x, esc_y)
    ass:an(7)
    ass:append('{\\bord1\\1c&H20201E&\\3c&H3A3A38&\\1a&H30&}')
    ass:draw_start()
    ass:round_rect_cw(0, 0, esc_w, esc_h, 6)
    ass:draw_stop()
    ass:new_event()
    ass:pos(esc_x + esc_w / 2, esc_y + esc_h / 2)
    ass:an(5)
    ass:append(string.format('{\\bord0\\1c&H8E8E93&\\fs10\\fn%s\\b600}[Esc] ✕', font))

    -- Divider
    ass:new_event()
    ass:pos(0, 0)
    ass:an(7)
    ass:append('{\\bord0\\1c&H282826&\\1a&H20&}')
    ass:draw_start()
    ass:rect_cw(x0 + 20, y0 + 44, x0 + menu_w - 20, y0 + 45)
    ass:draw_stop()

    -- Section 1: The Status & Health Card
    local cx = x0 + 20
    local cy = y0 + 54
    local cw = menu_w - 40
    local ch = 88

    ass:new_event()
    ass:pos(cx, cy)
    ass:an(7)
    ass:append('{\\bord1\\blur0.3\\1c&H1A1A18&\\3c&H2C2C2A&\\1a&H10&}')
    ass:draw_start()
    ass:round_rect_cw(0, 0, cw, ch, 10)
    ass:draw_stop()

    local raw_fn = mp.get_property('filename') or ''
    local raw_title = mp.get_property('media-title') or ''
    local tracks = mp.get_property_native('track-list', {})
    local v_cnt, a_cnt, s_cnt = 0, 0, 0
    local a_ads, s_ads = 0, 0
    for _, t in ipairs(tracks) do
        local is_j = t.title and utils and (utils.is_junk_title(t.title) or t.title:lower():find('1tamilmv') or t.title:lower():find('tamilblasters') or t.title:lower():find('as%-encodes'))
        if t.type == 'video' then
            v_cnt = v_cnt + 1
        elseif t.type == 'audio' then
            a_cnt = a_cnt + 1
            if is_j then a_ads = a_ads + 1 end
        elseif t.type == 'sub' then
            s_cnt = s_cnt + 1
            if is_j then s_ads = s_ads + 1 end
        end
    end
    local title_is_junk = (raw_title ~= '' and raw_title ~= raw_fn and utils and utils.is_junk_title(raw_title))
    local is_watermarked = title_is_junk or (a_ads > 0) or (s_ads > 0)

    -- Badge on Right
    if is_watermarked then
        local bw = 210
        local bh = 24
        local bx = cx + cw - bw - 14
        local by = cy + 12
        ass:new_event()
        ass:pos(bx, by)
        ass:an(7)
        ass:append('{\\bord1\\1c&H1C142A&\\3c&H3040E0&\\1a&H10&}')
        ass:draw_start()
        ass:round_rect_cw(0, 0, bw, bh, 6)
        ass:draw_stop()
        ass:new_event()
        ass:pos(bx + bw / 2, by + bh / 2)
        ass:an(5)
        ass:append(string.format('{\\bord0\\1c&H5060FF&\\fs10\\fn%s\\b700}⚠ Promo Watermarks Detected', font))
    else
        local bw = 84
        local bh = 24
        local bx = cx + cw - bw - 14
        local by = cy + 12
        ass:new_event()
        ass:pos(bx, by)
        ass:an(7)
        ass:append('{\\bord1\\1c&H142618&\\3c&H2ECC71&\\1a&H10&}')
        ass:draw_start()
        ass:round_rect_cw(0, 0, bw, bh, 6)
        ass:draw_stop()
        ass:new_event()
        ass:pos(bx + bw / 2, by + bh / 2)
        ass:an(5)
        ass:append(string.format('{\\bord0\\1c&H71CC2E&\\fs10\\fn%s\\b700}✓ Clean', font))
    end

    local disp_fn = raw_fn
    if #disp_fn > 68 then disp_fn = disp_fn:sub(1, 65) .. '...' end
    local disp_title = (raw_title ~= '' and raw_title ~= raw_fn) and ('"' .. raw_title .. '"') or '(No Title Tag Set)'
    if #disp_title > 68 then disp_title = disp_title:sub(1, 65) .. '..."' end

    ass:new_event()
    ass:pos(cx + 14, cy + 18)
    ass:an(4)
    ass:append(string.format('{\\bord0\\1c&H8E8E93&\\fs10.5\\fn%s\\b700}File:  {\\1c&HE0E0E0&\\b400}%s', font, utils and utils.ass_escape(disp_fn) or disp_fn))

    ass:new_event()
    ass:pos(cx + 14, cy + 42)
    ass:an(4)
    local title_c = title_is_junk and '&H5060FF&' or '&HFFFFFF&'
    ass:append(string.format('{\\bord0\\1c&H8E8E93&\\fs10.5\\fn%s\\b700}Title:  {\\1c%s\\b700}%s', font, title_c, utils and utils.ass_escape(disp_title) or disp_title))

    local trk_info = string.format('%d Video  •  %d Audio%s  •  %d Subtitles%s',
        v_cnt,
        a_cnt, (a_ads > 0 and (' {\\1c&H5060FF&}[' .. a_ads .. ' Tagged Ads]{\\1c&H8E8E93&}') or ''),
        s_cnt, (s_ads > 0 and (' {\\1c&H5060FF&}[' .. s_ads .. ' Tagged Ads]{\\1c&H8E8E93&}') or '')
    )
    if a_ads == 0 and s_ads == 0 then
        trk_info = trk_info .. '  {\\1c&H71CC2E&}[All Clean]{\\1c&H8E8E93&}'
    end
    ass:new_event()
    ass:pos(cx + 14, cy + 66)
    ass:an(4)
    ass:append(string.format('{\\bord0\\1c&H8E8E93&\\fs10.5\\fn%s\\b700}Tracks:  {\\b500}%s', font, trk_info))

    -- Section 2: Smart Actions
    local s2_y = cy + ch + 12
    ass:new_event()
    ass:pos(x0 + 24, s2_y + 8)
    ass:an(4)
    ass:append(string.format('{\\bord0\\1c&H7A7A80&\\fs9\\fn%s\\b700\\fsp2}SMART ACTIONS (ONE-CLICK)', font))

    local cards_y = s2_y + 20
    local card_gap = 12
    local card_w = math.floor((cw - 2 * card_gap) / 3)
    local card_h = 74

    for i = 1, 3 do
        local it = items[i]
        if it then
            local card_x = cx + (i - 1) * (card_w + card_gap)
            local is_sel = (state.menu_selected == i)
            tag_inspector_boxes[i] = { x1 = card_x, y1 = cards_y, x2 = card_x + card_w, y2 = cards_y + card_h }

            ass:new_event()
            ass:pos(card_x, cards_y)
            ass:an(7)
            local c_fill = is_sel and '&H8A551E&' or '&H1D1D1B&'
            local c_bord = is_sel and '&HFFE860&' or '&H30302E&'
            if i == 1 then
                c_fill = is_sel and '&H9E6422&' or '&H221F1C&'
                c_bord = is_sel and '&HFFFFFF&' or '&H4A3A2C&'
            end
            ass:append('{\\bord' .. (is_sel and '2.0' or '1.0') .. '\\1c' .. c_fill .. '\\3c' .. c_bord .. '\\1a&H00&}')
            ass:draw_start()
            ass:round_rect_cw(0, 0, card_w, card_h, 8)
            ass:draw_stop()

            ass:new_event()
            ass:pos(card_x + 14, cards_y + 24)
            ass:an(4)
            local t_color = is_sel and '&HFFFFFF&' or (i == 1 and '&H64D2FF&' or '&HEAEAEA&')
            local t_weight = is_sel and '\\b800' or '\\b700'
            ass:append(string.format('{\\bord0\\1c%s\\fs11.5\\fn%s%s}%s', t_color, font, t_weight, utils and utils.ass_escape(it.label) or it.label))

            ass:new_event()
            ass:pos(card_x + 14, cards_y + 48)
            ass:an(4)
            local sub_txt = it.sublabel or ''
            if #sub_txt > 36 then sub_txt = sub_txt:sub(1, 33) .. '...' end
            local s_color = is_sel and '&HE8E8F0&' or '&H8E8E93&'
            local s_weight = is_sel and '\\b500' or '\\b400'
            ass:append(string.format('{\\bord0\\1c%s\\fs9.5\\fn%s%s}%s', s_color, font, s_weight, utils and utils.ass_escape(sub_txt) or sub_txt))
        end
    end

    -- Section 3: Inline Manual Editor
    local s3_y = cards_y + card_h + 12
    ass:new_event()
    ass:pos(x0 + 24, s3_y + 8)
    ass:an(4)
    ass:append(string.format('{\\bord0\\1c&H7A7A80&\\fs9\\fn%s\\b700\\fsp2}MANUAL EDIT', font))

    local edit_y = s3_y + 20
    local save_btn_w = 138
    local input_box_w = cw - save_btn_w - 12
    local edit_h = 38

    local is_input_sel = (state.menu_selected == 4)
    tag_inspector_boxes[4] = { x1 = cx, y1 = edit_y, x2 = cx + input_box_w, y2 = edit_y + edit_h }
    ass:new_event()
    ass:pos(cx, edit_y)
    ass:an(7)
    local inp_fill = is_input_sel and '&H5A3E26&' or '&H141412&'
    local inp_bord = is_input_sel and '&HFFE860&' or '&H333330&'
    ass:append('{\\bord' .. (is_input_sel and '2.0' or '1.0') .. '\\1c' .. inp_fill .. '\\3c' .. inp_bord .. '\\1a&H00&}')
    ass:draw_start()
    ass:round_rect_cw(0, 0, input_box_w, edit_h, 8)
    ass:draw_stop()

    local manual_val = state.tag_inspector_input or (raw_title ~= '' and raw_title or raw_fn:gsub('%.%w+$', ''))
    if #manual_val > 72 then manual_val = manual_val:sub(1, 69) .. '...' end
    ass:new_event()
    ass:pos(cx + 14, edit_y + edit_h / 2)
    ass:an(4)
    local title_pfx_col = is_input_sel and '&HFFE860&' or '&H8E8E93&'
    ass:append(string.format('{\\bord0\\1c%s\\fs10.5\\fn%s\\b700}Title:  {\\1c&HFFFFFF&\\fs11\\b%s}%s', title_pfx_col, font, is_input_sel and '700' or '500', utils and utils.ass_escape(manual_val) or manual_val))

    local save_x = cx + input_box_w + 12
    local is_save_sel = (state.menu_selected == 5)
    tag_inspector_boxes[5] = { x1 = save_x, y1 = edit_y, x2 = save_x + save_btn_w, y2 = edit_y + edit_h }
    ass:new_event()
    ass:pos(save_x, edit_y)
    ass:an(7)
    local s_fill = is_save_sel and '&HFF8C14&' or '&H2A2A26&'
    local s_bord = is_save_sel and '&HFFFFFF&' or '&H444440&'
    ass:append('{\\bord' .. (is_save_sel and '2.0' or '1.0') .. '\\1c' .. s_fill .. '\\3c' .. s_bord .. '\\1a&H00&}')
    ass:draw_start()
    ass:round_rect_cw(0, 0, save_btn_w, edit_h, 8)
    ass:draw_stop()
    ass:new_event()
    ass:pos(save_x + save_btn_w / 2, edit_y + edit_h / 2)
    ass:an(5)
    ass:append(string.format('{\\bord0\\1c&HFFFFFF&\\fs11.5\\fn%s\\b%s}Save & Apply', font, is_save_sel and '800' or '600'))

    -- Section 4: Advanced Tools Toggle
    local adv_y = edit_y + edit_h + 12
    local is_adv_sel = (state.menu_selected == 6)
    tag_inspector_boxes[6] = { x1 = cx, y1 = adv_y, x2 = cx + cw, y2 = adv_y + 32 }
    ass:new_event()
    ass:pos(cx, adv_y)
    ass:an(7)
    local adv_fill = is_adv_sel and '&H7A4C24&' or '&H181816&'
    local adv_bord = is_adv_sel and '&HFFE860&' or '&H2C2C28&'
    ass:append('{\\bord' .. (is_adv_sel and '2.0' or '1.0') .. '\\1c' .. adv_fill .. '\\3c' .. adv_bord .. '\\1a&H00&}')
    ass:draw_start()
    ass:round_rect_cw(0, 0, cw, 32, 6)
    ass:draw_stop()

    ass:new_event()
    ass:pos(cx + 14, adv_y + 16)
    ass:an(4)
    ass:append(string.format('{\\bord0\\1c%s\\fs10\\fn%s\\b700\\fsp1}ADVANCED & FOLDER TOOLS', is_adv_sel and '&HFFFFFF&' or '&H8E8E93&', font))

    local exp_text = expanded and '[ Collapse Tools ▴ ]' or '[ Expand Tools ▾ ]'
    ass:new_event()
    ass:pos(cx + cw - 14, adv_y + 16)
    ass:an(6)
    ass:append(string.format('{\\bord0\\1c%s\\fs10\\fn%s\\b%s}%s', is_adv_sel and '&HFFFFFF&' or '&H64D2FF&', font, is_adv_sel and '800' or '700', exp_text))

    local next_y = adv_y + 36
    if expanded then
        local is_b7_sel = (state.menu_selected == 7)
        tag_inspector_boxes[7] = { x1 = cx + 10, y1 = next_y, x2 = cx + cw - 10, y2 = next_y + 32 }
        ass:new_event()
        ass:pos(cx + 10, next_y)
        ass:an(7)
        local b7_fill = is_b7_sel and '&H7A4C24&' or '&H161614&'
        local b7_bord = is_b7_sel and '&HFFE860&' or '&H2A2A28&'
        ass:append('{\\bord' .. (is_b7_sel and '2.0' or '1.0') .. '\\1c' .. b7_fill .. '\\3c' .. b7_bord .. '\\1a&H00&}')
        ass:draw_start()
        ass:round_rect_cw(0, 0, cw - 20, 32, 6)
        ass:draw_stop()
        ass:new_event()
        ass:pos(cx + 24, next_y + 16)
        ass:an(4)
        local b7_label = (items[7] and items[7].label) or '• Batch Apply Title to Season Folder'
        ass:append(string.format('{\\bord0\\1c%s\\fs10.5\\fn%s\\b%s}%s', is_b7_sel and '&HFFFFFF&' or '&HE0E0E0&', font, is_b7_sel and '700' or '600', utils and utils.ass_escape(b7_label) or b7_label))

        local b8_y = next_y + 38
        local is_b8_sel = (state.menu_selected == 8)
        tag_inspector_boxes[8] = { x1 = cx + 10, y1 = b8_y, x2 = cx + cw - 10, y2 = b8_y + 32 }
        ass:new_event()
        ass:pos(cx + 10, b8_y)
        ass:an(7)
        local b8_fill = is_b8_sel and '&H251890&' or '&H181414&'
        local b8_bord = is_b8_sel and '&H5070FF&' or '&H3A2222&'
        ass:append('{\\bord' .. (is_b8_sel and '2.0' or '1.0') .. '\\1c' .. b8_fill .. '\\3c' .. b8_bord .. '\\1a&H00&}')
        ass:draw_start()
        ass:round_rect_cw(0, 0, cw - 20, 32, 6)
        ass:draw_stop()
        ass:new_event()
        ass:pos(cx + 24, b8_y + 16)
        ass:an(4)
        local b8_warn_col = is_b8_sel and '&H80A0FF&' or '&H4040E0&'
        ass:append(string.format('{\\bord0\\1c%s\\fs10.5\\fn%s\\b%s}• Strip All Header Titles in Directory  {\\1c%s\\b800}[⚠ Danger Zone]', is_b8_sel and '&HFFFFFF&' or '&HE0A0A0&', font, is_b8_sel and '700' or '600', b8_warn_col))

        next_y = b8_y + 38
    end

    -- Section 5: Auto-Reload
    local auto_idx = expanded and 9 or 7
    local is_auto_sel = (state.menu_selected == auto_idx)
    tag_inspector_boxes[auto_idx] = { x1 = cx, y1 = next_y, x2 = cx + cw, y2 = next_y + 26 }

    if is_auto_sel then
        ass:new_event()
        ass:pos(cx, next_y)
        ass:an(7)
        ass:append('{\\bord1.5\\1c&H6A4422&\\3c&HFFE860&\\1a&H00&}')
        ass:draw_start()
        ass:round_rect_cw(0, 0, cw, 26, 6)
        ass:draw_stop()
    end

    local cb_x = cx + 8
    local cb_y = next_y + 5
    local cb_sz = 16
    ass:new_event()
    ass:pos(cb_x, cb_y)
    ass:an(7)
    local cb_bord = is_auto_sel and '&HFFFFFF&' or '&H50504C&'
    local cb_fill = is_auto_sel and '&H3A2616&' or '&H1C1C1A&'
    ass:append('{\\bord' .. (is_auto_sel and '1.5' or '1.0') .. '\\1c' .. cb_fill .. '\\3c' .. cb_bord .. '\\1a&H00&}')
    ass:draw_start()
    ass:round_rect_cw(0, 0, cb_sz, cb_sz, 3)
    ass:draw_stop()

    if auto_reload then
        ass:new_event()
        ass:pos(cb_x + cb_sz / 2, cb_y + cb_sz / 2)
        ass:an(5)
        ass:append(string.format('{\\bord0\\1c&H2ECC71&\\fs11\\fn%s\\b800}✓', font))
    end

    ass:new_event()
    ass:pos(cb_x + cb_sz + 10, cb_y + cb_sz / 2)
    ass:an(4)
    local ar_color = is_auto_sel and '&HFFFFFF&' or '&H8E8E93&'
    local ar_weight = is_auto_sel and '\\b700' or '\\b500'
    ass:append(string.format('{\\bord0\\1c%s\\fs10.5\\fn%s%s}Auto-reload playback after saving disk changes', ar_color, font, ar_weight))
end

function M.render(ass)
    local state = ctx_ref.state
    local user_opts = ctx_ref.user_opts or {}
    local osc_param = ctx_ref.osc_param or {playresx = 1280, playresy = 720}

    if menu_closing then
        local speed = 1800
        local dt = 1/30
        menu_alpha = math.max(0, menu_alpha - speed * dt)
        if menu_alpha <= 0 then
            state.menu_active = nil
            menu_closing = false
            menu_bar_anim_y = nil
            if ctx_ref.on_close then ctx_ref.on_close() end
            return
        end
        if ctx_ref.request_tick then ctx_ref.request_tick() end
    elseif state.menu_active then
        local speed = 2200
        local dt = 1/30
        menu_alpha = math.min(255, menu_alpha + speed * dt)
        if menu_alpha < 255 and ctx_ref.request_tick then ctx_ref.request_tick() end
    end
    if not state.menu_active and not menu_closing then return end

    local items = M.menu_get_items()
    if #items == 0 then return end

    local font  = user_opts.font or 'Inter'
    if state.menu_active == 'tags' then
        render_tag_inspector(ass, osc_param, font, menu_alpha, items)
        return
    end
    local is_pl = (state.menu_active == 'playlist')
    local is_sub_menu = state.menu_active and (
        state.menu_active:find('^sub_') ~= nil or
        state.menu_active == 'sub'
    )
    local is_drawer = state.menu_active and (
        is_sub_menu or
        state.menu_active == 'audio' or
        state.menu_active == 'video'
    )

    local menu_w, row_h, header_h, footer_h, pad_bot, x0, y0, visible_max, scroll, vis, menu_h
    local num_x, text_x
    local is_searchable = not is_drawer and (state.menu_active == 'playlist' or state.menu_active == 'chapters') and (state.menu_searchable == true or (state.menu_searchable == nil and #items > 5))
    local search_h = is_searchable and 42 or 0

    if is_drawer then
        menu_w    = math.max(360, math.min(420, math.floor(osc_param.playresx * 0.30)))
        local has_any_sublabel = false
        for _, item in ipairs(items) do
            if item.sublabel and item.sublabel ~= '' then
                has_any_sublabel = true
                break
            end
        end
        local is_video_menu = (state.menu_active == 'video')
        row_h     = is_video_menu and 34 or (has_any_sublabel and 52 or 40)
        header_h  = 48
        footer_h  = 34
        pad_bot   = 0
        local cx  = math.floor(osc_param.playresx / 2)
        local cy  = math.floor(osc_param.playresy / 2)
        local y_safe_top = is_sub_menu and 22 or 24
        local y_safe_bot = is_sub_menu and math.floor(osc_param.playresy * 0.78) or (osc_param.playresy - 24)
        visible_max = math.max(1, math.floor((y_safe_bot - y_safe_top - header_h - footer_h) / row_h))

        scroll = state.menu_scroll or 0
        if scroll < 0 then scroll = 0 end
        if state.menu_selected - scroll > visible_max then
            scroll = state.menu_selected - visible_max
        elseif state.menu_selected - scroll < 1 then
            scroll = state.menu_selected - 1
        end
        if scroll < 0 then scroll = 0 end
        state.menu_scroll = scroll

        local total = #items
        vis    = math.min(total - scroll, visible_max)
        menu_h = header_h + vis * row_h + footer_h
        if is_sub_menu then
            x0 = math.max(20, math.floor(osc_param.playresx * 0.02))
            y0 = y_safe_top
        else
            x0 = math.floor(cx - menu_w / 2)
            y0 = math.max(y_safe_top, math.floor(cy - menu_h / 2))
        end
    else
        local is_wide = is_pl or (state.menu_active == 'chapters') or (state.menu_active == 'tags') or (state.menu_active == 'tmdb_matches')
        menu_w    = is_wide and math.min(920, math.floor(osc_param.playresx * 0.90)) or math.min(740, math.floor(osc_param.playresx * 0.88))
        local pad_left  = 20
        local has_any_sublabel = false
        for _, item in ipairs(items) do
            if item.sublabel and item.sublabel ~= '' then
                has_any_sublabel = true
                break
            end
        end
        row_h     = (is_pl or state.menu_active == 'tags' or has_any_sublabel) and 60 or 46
        header_h  = 56
        footer_h  = 36
        pad_bot   = 0
        num_x     = 32
        text_x    = pad_left + 46

        local y_safe_top = 24
        local y_safe_bot = osc_param.playresy - 24
        visible_max = math.max(1, math.min(
            (is_pl or state.menu_active == 'chapters') and 8 or 7,
            math.floor((y_safe_bot - y_safe_top - header_h - search_h - footer_h) / row_h)
        ))

        scroll = state.menu_scroll or 0
        if scroll < 0 then scroll = 0 end
        if state.menu_selected - scroll > visible_max then
            scroll = state.menu_selected - visible_max
        elseif state.menu_selected - scroll < 1 then
            scroll = state.menu_selected - 1
        end
        if scroll < 0 then scroll = 0 end
        state.menu_scroll = scroll

        local total  = #items
        vis    = math.min(total - scroll, visible_max)
        local card_vis = is_searchable and math.max(vis, math.min(6, visible_max)) or vis
        menu_h = header_h + search_h + card_vis * row_h + footer_h

        local cx = math.floor(osc_param.playresx / 2)
        local cy = math.floor(osc_param.playresy / 2)
        x0 = math.floor(cx - menu_w / 2)
        y0 = math.max(y_safe_top, math.floor(cy - menu_h / 2))
    end

    local total = #items
    local eff_alpha = math.max(0, math.min(255, menu_alpha))
    local dim_a = string.format('%02X', math.floor(255 - (110 * eff_alpha / 255)))
    local pan_a = string.format('%02X', math.floor(255 - (is_drawer and (235 * eff_alpha / 255) or (200 * eff_alpha / 255))))
    local txt_a = string.format('%02X', math.floor(255 - eff_alpha))

    if not is_drawer then
        ass:new_event()
        ass:pos(0,0)
        ass:an(7)
        ass:append('{\\bord0\\blur0\\1c&H000000&\\1a&H'..dim_a..'&}')
        ass:draw_start()
        ass:rect_cw(0, 0, osc_param.playresx, osc_param.playresy)
        ass:draw_stop()
    end

    ass:new_event()
    ass:pos(x0, y0)
    ass:an(7)
    ass:append('{\\bord1.2\\blur0.5\\1c&H161614&\\3c&HFFFFFF&\\3a&HD0&\\1a&H'..pan_a..'&}')
    ass:draw_start()
    ass:round_rect_cw(0, 0, menu_w, menu_h, 16)
    ass:draw_stop()

    local titles = {
        playlist      = 'PLAYLIST',
        audio         = 'AUDIO SETTINGS',
        sub           = 'SUBTITLES',
        sub_config    = 'SUBTITLE STYLING',
        sub_customize = 'ADVANCED TUNING',
        sub_advanced  = 'ADVANCED TUNING',
        sub_presets   = 'STYLE PRESETS',
        chapters      = 'CHAPTERS',
        video         = 'VIDEO ADJUSTMENTS',
        tags          = 'METADATA & TAG EDITOR',
        tmdb_matches  = 'TMDB MATCHES'
    }
    ass:new_event()
    ass:pos(x0 + 18, y0 + header_h / 2)
    ass:an(4)
    ass:append(string.format('{\\bord0\\blur0\\1c&H8E8E93&\\1a&H00&\\fs10\\fn%s\\b600\\fsp1\\q2}', font))
    ass:append('ESC')

    if state.menu_active == 'playlist' and state.playlist_is_series then
        ass:new_event()
        ass:pos(x0 + menu_w / 2, y0 + header_h / 2)
        ass:an(5)
        ass:append(string.format('{\\bord0\\blur0\\1c&HFFFFFF&\\1a&H00&\\fs13\\fn%s\\b700\\fsp2\\q2}', font))
        if state.playlist_filter_series then
            local s_str = state.playlist_cur_season and string.format(' • S%02d', tonumber(state.playlist_cur_season)) or ''
            ass:append(string.format('%s%s', (state.playlist_cur_show or 'SERIES'):upper(), s_str))
        else
            ass:append('PLAYLIST  (ALL FILES)')
        end

        local total_pl = #mp.get_property_native('playlist', {})
        ass:new_event()
        ass:pos(x0 + menu_w - 38, y0 + header_h / 2)
        ass:an(6)
        ass:append(string.format('{\\bord0\\blur0\\1c&HFF9500&\\1a&H00&\\fs11\\fn%s\\b600\\q2}', font))
        if state.playlist_filter_series then
            ass:append(string.format('%d eps  •  TAB: All (%d)', total, total_pl))
        else
            ass:append(string.format('%d items  •  TAB: Series', total))
        end
    else
        ass:new_event()
        ass:pos(x0 + menu_w / 2, y0 + header_h / 2)
        ass:an(5)
        ass:append(string.format('{\\bord0\\blur0\\1c&HFFFFFF&\\1a&H00&\\fs13\\fn%s\\b700\\fsp2\\q2}', font))
        local dyn_sub_title = (ctx_ref.subtitle and ctx_ref.subtitle.get_menu_title) and ctx_ref.subtitle.get_menu_title(state.menu_active)
        ass:append(dyn_sub_title or titles[state.menu_active] or '')

        ass:new_event()
        ass:pos(x0 + menu_w - (is_drawer and 20 or 38), y0 + header_h / 2)
        ass:an(6)
        if state.menu_active == 'sub' then
            ass:append(string.format('{\\bord0\\blur0\\1c&HFF9500&\\1a&H00&\\fs11\\fn%s\\b600\\q2}', font))
            ass:append('TAB: Styling')
        elseif state.menu_active == 'sub_config' then
            ass:append(string.format('{\\bord0\\blur0\\1c&H0A84FF&\\1a&H00&\\fs11\\fn%s\\b600\\q2}', font))
            ass:append('TAB: Tracks')
        elseif state.menu_active and state.menu_active:find('^sub_') then
            ass:append(string.format('{\\bord0\\blur0\\1c&H8E8E93&\\1a&H00&\\fs11\\fn%s\\b600\\q2}', font))
            ass:append('ESC: Styling')
        elseif state.menu_active == 'video' then
            ass:append(string.format('{\\bord0\\blur0\\1c&H8E8E93&\\1a&H00&\\fs11\\fn%s\\b500\\q2}', font))
            ass:append('Tuning')
        elseif state.menu_active == 'audio' then
            ass:append(string.format('{\\bord0\\blur0\\1c&H8E8E93&\\1a&H00&\\fs11\\fn%s\\b500\\q2}', font))
            ass:append('DSP & Tracks')
        elseif is_drawer then
            ass:append(string.format('{\\bord0\\blur0\\1c&H8E8E93&\\1a&H00&\\fs11\\fn%s\\b500\\q2}', font))
            ass:append(string.format('%d tracks', total))
        else
            ass:append(string.format('{\\bord0\\blur0\\1c&H8E8E93&\\1a&H00&\\fs12\\fn%s\\b300\\q2}', font))
            ass:append(string.format('%d items', total))
        end
    end

    if not is_drawer then
        ass:new_event()
        ass:pos(x0 + menu_w - 18, y0 + header_h / 2)
        ass:an(6)
        ass:append(string.format('{\\bord0\\blur0\\1c&H8E8E93&\\1a&H00&\\fs14\\fn%s\\b600\\q2}✕', font))
    end

    ass:new_event()
    ass:pos(x0, y0 + header_h)
    ass:an(7)
    ass:append('{\\bord0\\blur0\\1c&H2C2C2E&\\1a&H40&}')
    ass:draw_start()
    ass:rect_cw(0, 0, menu_w, 1)
    ass:draw_stop()

    if is_searchable then
        local sb_x = x0 + 16
        local sb_y = y0 + header_h + 5
        local sb_w = menu_w - 32
        local sb_h = 32

        ass:new_event()
        ass:pos(sb_x, sb_y)
        ass:an(7)
        ass:append('{\\bord1\\blur0.5\\1c&H202023&\\3c&H3A3A3C&\\3a&H60&\\1a&H20&}')
        ass:draw_start()
        ass:round_rect_cw(0, 0, sb_w, sb_h, 8)
        ass:draw_stop()

        ass:new_event()
        ass:pos(sb_x + 14, sb_y + sb_h / 2)
        ass:an(4)
        ass:append(string.format('{\\bord0\\blur0\\1c&H8E8E93&\\1a&H00&\\fs11\\fn%s\\b700\\q2}🔍', font))

        ass:new_event()
        ass:pos(sb_x + 36, sb_y + sb_h / 2)
        ass:an(4)
        if menu_search_query ~= '' then
            ass:append(string.format('{\\bord0\\blur0\\1c&HFFFFFF&\\1a&H00&\\fs12\\fn%s\\b600\\q2}%s{\\1c&H0A84FF&}▎', font, menu_search_query))
        else
            ass:append(string.format('{\\bord0\\blur0\\1c&H636366&\\1a&H00&\\fs12\\fn%s\\b400\\q2}Search by name... (Type to filter)', font))
        end

        ass:new_event()
        ass:pos(sb_x + sb_w - 14, sb_y + sb_h / 2)
        ass:an(6)
        if menu_search_query ~= '' then
            ass:append(string.format('{\\bord0\\blur0\\1c&H0A84FF&\\1a&H00&\\fs11\\fn%s\\b600\\q2}%d match%s  {\\1c&H8E8E93&}|  {\\1c&HFF453A&\\b700}✕ Clear',
                font, total, total == 1 and '' or 'es'))
        else
            ass:append(string.format('{\\bord0\\blur0\\1c&H636366&\\1a&H00&\\fs11\\fn%s\\b400\\q2}%d items', font, total))
        end

        ass:new_event()
        ass:pos(x0, y0 + header_h + search_h)
        ass:an(7)
        ass:append('{\\bord0\\blur0\\1c&H2C2C2E&\\1a&H50&}')
        ass:draw_start()
        ass:rect_cw(0, 0, menu_w, 1)
        ass:draw_stop()
    end

    if not is_drawer then
        local sel_i   = state.menu_selected - scroll
        local bar_vis = (sel_i >= 1 and sel_i <= vis)
        local tgt_y   = y0 + header_h + (is_searchable and search_h or 0) + (sel_i - 1) * row_h + 5
        local now     = mp.get_time()
        if bar_vis then
            if menu_bar_anim_y == nil then
                menu_bar_anim_y = tgt_y
            else
                local dt = menu_bar_last_t and math.min(now - menu_bar_last_t, 0.05) or 0
                menu_bar_anim_y = menu_bar_anim_y + (tgt_y - menu_bar_anim_y) * math.min(1, 20 * dt)
                if math.abs(menu_bar_anim_y - tgt_y) > 0.5 and ctx_ref.request_tick then ctx_ref.request_tick() end
            end
            menu_bar_last_t = now
            ass:new_event()
            ass:pos(x0 + 8, menu_bar_anim_y)
            ass:an(7)
            ass:append('{\\bord0\\blur0\\1c&HFFFFFF&\\1a&H00&}')
            ass:draw_start()
            ass:round_rect_cw(0, 0, 4, row_h - 10, 2)
            ass:draw_stop()
        else
            menu_bar_anim_y = nil
        end
    end

    for i = 1, vis do
        local ai   = i + scroll
        local item = items[ai]
        if not item then break end

        local ry     = y0 + header_h + (is_searchable and search_h or 0) + (i - 1) * row_h
        local is_sel = (ai == state.menu_selected)
        local is_cur = item.current

        if item.type == 'header' then
            ass:new_event()
            ass:pos(x0 + 16, ry + row_h / 2)
            ass:an(4)
            ass:append(string.format('{\\bord0\\blur0\\1c&H8E8E93&\\1a&H%s&\\fs10\\fn%s\\b700\\fsp1\\q2}', txt_a, font))
            ass:append(item.label)

            if i < vis then
                ass:new_event()
                ass:pos(x0 + 16, ry + row_h - 2)
                ass:an(7)
                ass:append('{\\bord0\\blur0\\1c&H2C2C2E&\\1a&H50&}')
                ass:draw_start()
                ass:rect_cw(0, 0, menu_w - 32, 1)
                ass:draw_stop()
            end
        elseif is_drawer then
            -- Soft luminous capsule on selected row
            if is_sel then
                ass:new_event()
                ass:pos(x0 + 8, ry + 3)
                ass:an(7)
                ass:append('{\\bord0\\blur0\\1c&HFFFFFF&\\1a&HE0&}')
                ass:draw_start()
                ass:round_rect_cw(0, 0, menu_w - 16, row_h - 6, 8)
                ass:draw_stop()
            end

            local has_sub = item.sublabel and item.sublabel ~= ''
            local lbl_col = is_sel and '&HFFFFFF&' or (is_cur and '&H0A84FF&' or '&HFFFFFF&')
            local lbl_b   = (is_sel or is_cur) and '\\b700' or '\\b500'
            local main_y  = has_sub and (ry + 16) or (ry + row_h / 2)

            ass:new_event()
            ass:pos(x0 + 16, main_y)
            ass:an(4)
            ass:append(string.format('{\\bord0\\blur0\\1c%s\\1a&H%s&\\fs12\\fn%s%s\\q2}',
                lbl_col, txt_a, font, lbl_b))
            ass:append(item.label or item.title or '')

            if has_sub then
                ass:new_event()
                ass:pos(x0 + 16, ry + 34)
                ass:an(4)
                local sub_col = is_sel and '&HE5E5EA&' or '&H8E8E93&'
                ass:append(string.format('{\\bord0\\blur0\\1c%s\\1a&H%s&\\fs10\\fn%s\\b400\\q2}',
                    sub_col, txt_a, font))
                ass:append(item.sublabel)
            end

            -- Row value / stepper (right side)
            ass:new_event()
            ass:pos(x0 + menu_w - 16, ry + row_h / 2)
            ass:an(6)

            if item.type == 'stepper' or item.on_prev or item.on_next then
                local val_text = item.value or ''
                if item.color_hex then
                    local bgr = rgb_to_ass(item.color_hex)
                    val_text = string.format('{\\1c%s}●{\\1c&HFFFFFF&} %s', bgr, item.value or '')
                end
                if is_sel then
                    ass:append(string.format('{\\bord0\\blur0\\1c&HFFFFFF&\\1a&H%s&\\fs12\\fn%s\\b700\\q2}', txt_a, font))
                    ass:append('◀  ' .. val_text .. '  ▶')
                else
                    ass:append(string.format('{\\bord0\\blur0\\1c&H8E8E93&\\1a&H%s&\\fs12\\fn%s\\b500\\q2}', txt_a, font))
                    ass:append('‹  {\\1c&HE5E5EA&}' .. val_text .. '{\\1c&H8E8E93&}  ›')
                end
            elseif item.action == 'nav_menu' or item.action == 'open_sub_config' then
                local val_text = (item.value and item.value ~= '') and (item.value .. '  ›') or '›'
                local nav_col = is_sel and '&HFFFFFF&' or '&H8E8E93&'
                ass:append(string.format('{\\bord0\\blur0\\1c%s\\1a&H%s&\\fs12\\fn%s\\b600\\q2}', nav_col, txt_a, font))
                ass:append(val_text)
            elseif is_cur then
                local cur_col = is_sel and '&HFFFFFF&' or '&H0A84FF&'
                ass:append(string.format('{\\bord0\\blur0\\1c%s\\1a&H%s&\\fs14\\b700\\q2}', cur_col, txt_a))
                ass:append('✓')
            elseif item.value and item.value ~= '' then
                local val_col = is_sel and '&HFFFFFF&' or '&H8E8E93&'
                ass:append(string.format('{\\bord0\\blur0\\1c%s\\1a&H%s&\\fs12\\fn%s\\b500\\q2}', val_col, txt_a, font))
                ass:append(item.value)
            end

            -- Divider between unselected rows
            if not is_sel and i < vis then
                ass:new_event()
                ass:pos(x0 + 16, ry + row_h)
                ass:an(7)
                ass:append('{\\bord0\\blur0\\1c&H2C2C2E&\\1a&H60&}')
                ass:draw_start()
                ass:rect_cw(0, 0, menu_w - 32, 1)
                ass:draw_stop()
            end
        else
            -- Existing centered modal row rendering
            if is_sel then
                ass:new_event()
                ass:pos(x0 + 6, ry + 4)
                ass:an(7)
                ass:append('{\\bord0\\blur0\\1c&HFFFFFF&\\1a&HE0&}')
                ass:draw_start()
                ass:round_rect_cw(0, 0, menu_w - 12, row_h - 8, 8)
                ass:draw_stop()
            end

            local num_col = is_sel and '&HFFFFFF&' or (is_cur and '&H0A84FF&' or '&H8E8E93&')
            ass:new_event()
            ass:pos(x0 + num_x, ry + row_h / 2)
            ass:an(5)
            ass:append(string.format('{\\bord0\\blur0\\1c%s\\1a&H%s&\\fs12\\fn%s\\b600\\q2}',
                num_col, txt_a, font))
            ass:append(tostring(ai))

            local lbl_col = is_cur and '&H0A84FF&' or '&HFFFFFF&'
            local lbl_b   = (is_sel or is_cur) and '\\b700' or '\\b400'
            local has_sub = item.sublabel and item.sublabel ~= ''

            ass:new_event()
            ass:pos(x0 + text_x, has_sub and (ry + 20) or (ry + row_h / 2))
            ass:an(4)
            ass:append(string.format('{\\bord0\\blur0\\1c%s\\1a&H%s&\\fs14\\fn%s%s\\q2}',
                lbl_col, txt_a, font, lbl_b))
            ass:append(item.label)

            if has_sub then
                ass:new_event()
                ass:pos(x0 + text_x, ry + 42)
                ass:an(4)
                ass:append(string.format('{\\bord0\\blur0\\1c&H8E8E93&\\1a&H%s&\\fs12\\fn%s\\b300\\q2}',
                    txt_a, font))
                ass:append(item.sublabel)
            end

            if is_cur then
                ass:new_event()
                ass:pos(x0 + menu_w - (is_drawer and 24 or 36), ry + row_h / 2)
                ass:an(6)
                local cur_tag = is_pl and '✓ Now Playing' or '✓ Active'
                local tag_fs = is_pl and '12' or '13'
                ass:append(string.format('{\\bord0\\blur0\\1c&H0A84FF&\\1a&H%s&\\fs%s\\fn%s\\b700\\q2}%s', txt_a, tag_fs, font, cur_tag))
            end

            if i < vis then
                ass:new_event()
                ass:pos(x0 + text_x, ry + row_h)
                ass:an(7)
                ass:append('{\\bord0\\blur0\\1c&H2C2C2E&\\1a&H40&}')
                ass:draw_start()
                ass:rect_cw(0, 0, menu_w - text_x - 18, 1)
                ass:draw_stop()
            end
        end
    end

    -- Top divider of persistent footer
    ass:new_event()
    ass:pos(x0, y0 + menu_h - footer_h)
    ass:an(7)
    ass:append('{\\bord0\\blur0\\1c&H2C2C2E&\\1a&H40&}')
    ass:draw_start()
    ass:rect_cw(0, 0, menu_w, 1)
    ass:draw_stop()

    -- Persistent navigation hint
    ass:new_event()
    ass:pos(x0 + menu_w / 2, y0 + menu_h - footer_h / 2)
    ass:an(5)
    ass:append(string.format('{\\bord0\\blur0\\1c&H8E8E93&\\1a&H00&\\fs10\\fn%s\\b500\\q2}', font))
    if is_searchable then
        ass:append('[↑/↓] Navigate  •  [Enter] Play  •  [Backspace] Clear  •  [Esc] Exit')
    elseif is_drawer then
        if state.menu_active:find('^sub_') then
            ass:append('[↑/↓] Navigate  •  [←/→] Adjust  •  [Esc] Back')
        else
            ass:append('[↑/↓] Navigate  •  [Enter / Click] Select  •  [Esc] Close')
        end
    else
        ass:append('[↑/↓] Navigate  •  [Enter / Click] Select  •  [Esc] Close')
    end

    if scroll > 0 then
        ass:new_event()
        ass:pos(x0 + menu_w / 2, y0 + header_h + (is_searchable and search_h or 0) + 10)
        ass:an(8)
        ass:append(string.format('{\\bord0\\blur0\\1c&H8E8E93&\\1a&H00&\\fs11\\fn%s\\b300\\q2}', font))
        ass:append('\xe2\x96\xb2  more above')
    end

    if scroll + vis < total then
        ass:new_event()
        ass:pos(x0 + menu_w / 2, y0 + menu_h - footer_h - 4)
        ass:an(2)
        ass:append(string.format('{\\bord0\\blur0\\1c&H8E8E93&\\1a&H00&\\fs11\\fn%s\\b300\\q2}', font))
        ass:append('\xe2\x96\xbc  more below')
    end
end

if mp.register_script_message then
    mp.register_script_message('menu-select', function(idx_str)
        local idx = tonumber(idx_str)
        if idx and ctx_ref.state then
            ctx_ref.state.menu_selected = idx
            M.invalidate_items()
            if ctx_ref.request_tick then ctx_ref.request_tick() end
        end
    end)

    mp.register_script_message('menu-confirm', function()
        M.menu_confirm()
    end)

    mp.register_script_message('tmdb-set-matches', function(json_str)
        local mp_utils = require and require('mp.utils') or mp.utils
        if mp_utils and mp_utils.parse_json then
            local ok, data = pcall(mp_utils.parse_json, json_str)
            if ok and data then
                tmdb_matches_list = data
                M.invalidate_items()
                if ctx_ref.request_tick then ctx_ref.request_tick() end
            end
        end
    end)
end

return M
