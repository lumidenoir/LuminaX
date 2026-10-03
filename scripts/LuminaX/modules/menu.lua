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
    mp.observe_property('playlist-count', nil, function()
        M.invalidate_items()
        if M.is_active() and ctx_ref.request_tick then ctx_ref.request_tick() end
    end)
    mp.observe_property('playlist', nil, function()
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

local AUDIO_PROFILES = {
    {
        id = 'off',
        label = 'Pure Studio (Off)',
        value = 'Off',
        sublabel = 'Direct bit-perfect passthrough',
        filter = nil,
    },
    {
        id = 'night',
        label = 'Night Mode',
        value = 'Night Mode',
        sublabel = 'Normalizes loud SFX & lifts soft whispers',
        filter = 'dynaudnorm=f=150:g=15:m=10:p=0.9',
    },
    {
        id = 'dialogue',
        label = 'Voice Boost',
        value = 'Voice Boost',
        sublabel = 'Intelligibility boost & 300Hz mud scoop',
        filter = 'volume=-3.5dB,highpass=f=85,equalizer=f=300:t=q:w=1.2:g=-2.5,equalizer=f=3200:t=q:w=1.2:g=4.0',
    },
    {
        id = 'bass',
        label = 'Cinema Bass',
        value = 'Cinema Bass',
        sublabel = 'Deep low-end rumble with true-peak limiter',
        filter = 'volume=-4.5dB,bass=g=5.0:f=105:w=0.6,alimiter=limit=-0.2dB',
    },
    {
        id = 'crossfeed',
        label = 'Spatial Headphone',
        value = 'Spatial Headphone',
        sublabel = 'Bauer binaural crossfeed (reduces fatigue)',
        filter = 'bs2b=profile=default',
    },
}

local current_audio_profile_idx = 1

local function detect_current_audio_profile_idx()
    local af = mp.get_property_native('af', {})
    if type(af) ~= 'table' or #af == 0 then return 1 end
    for _, filter in ipairs(af) do
        local label = filter.label or ''
        local name = filter.name or ''
        if label == 'nightmode' or name:find('nightmode') then
            return 2 -- Night Mode legacy tag
        end
        if label == 'enhancement' or name:find('enhancement') then
            return current_audio_profile_idx or 1
        end
    end
    return 1 -- Off
end

local function set_audio_profile(idx)
    if idx < 1 then idx = #AUDIO_PROFILES end
    if idx > #AUDIO_PROFILES then idx = 1 end
    current_audio_profile_idx = idx
    local profile = AUDIO_PROFILES[idx]

    -- Remove both current @enhancement and legacy @nightmode cleanly
    pcall(mp.commandv, "af", "remove", "@enhancement")
    pcall(mp.commandv, "af", "remove", "@nightmode")

    if profile.filter and profile.filter ~= '' then
        pcall(mp.commandv, "af", "add", "@enhancement:lavfi=[" .. profile.filter .. "]")
    end

    if ctx_ref.huds and ctx_ref.huds.show_pill then
        ctx_ref.huds.show_pill('\238\142\161', 'Audio Profile: ' .. (profile.value or profile.label))
    else
        mp.osd_message('Audio Profile: ' .. (profile.value or profile.label), 2)
    end
end

local function step_audio_profile(delta)
    local cur_idx = detect_current_audio_profile_idx()
    set_audio_profile(cur_idx + delta)
end

local function is_night_mode_active()
    return detect_current_audio_profile_idx() > 1
end

local function toggle_night_mode()
    local cur = detect_current_audio_profile_idx()
    if cur > 1 then
        set_audio_profile(1) -- Off
    else
        set_audio_profile(2) -- Night Mode
    end
end

local function step_audio_delay(delta)
    local cur = mp.get_property_number("audio-delay", 0.0) or 0.0
    local next_val = math.floor((cur + delta) * 1000 + 0.5) / 1000
    mp.set_property_number("audio-delay", next_val)
end

local function reset_audio_delay()
    mp.set_property_number("audio-delay", 0.0)
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
    local lbl = 'Aspect: ' .. (names[next_val] or next_val)
    if ctx_ref.huds and ctx_ref.huds.show_pill then
        ctx_ref.huds.show_pill('\238\136\168', lbl)
    else
        mp.osd_message(lbl, 2)
    end
end

local function cycle_rotate(dir)
    local cur = mp.get_property_number('video-rotate', 0) or 0
    local next_val = (cur + (dir > 0 and 90 or 270)) % 360
    mp.set_property_number('video-rotate', next_val)
    local lbl = string.format('Rotate: %d°', next_val)
    if ctx_ref.huds and ctx_ref.huds.show_pill then
        ctx_ref.huds.show_pill('\238\136\168', lbl)
    else
        mp.osd_message(lbl, 2)
    end
end

local function cycle_deinterlace()
    local cur = mp.get_property('deinterlace', 'no') or 'no'
    local next_val = (cur == 'no') and 'yes' or ((cur == 'yes') and 'auto' or 'no')
    mp.set_property('deinterlace', next_val)
    local lbl = 'Deinterlace: ' .. next_val:upper()
    if ctx_ref.huds and ctx_ref.huds.show_pill then
        ctx_ref.huds.show_pill('\238\136\168', lbl)
    else
        mp.osd_message(lbl, 2)
    end
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
    if ctx_ref.huds and ctx_ref.huds.show_pill then
        ctx_ref.huds.show_pill('\238\136\168', 'Video Settings Reset')
    else
        mp.osd_message('✓ Video settings reset to default', 2)
    end
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

        -- 1. Enhancements: Audio Profile Suite
        items[#items + 1] = {
            type = 'header',
            label = 'ENHANCEMENTS',
            index = #items + 1
        }
        local cur_idx = detect_current_audio_profile_idx()
        local cur_prof = AUDIO_PROFILES[cur_idx] or AUDIO_PROFILES[1]
        items[#items + 1] = {
            label = 'Audio Profile',
            sublabel = cur_prof.sublabel,
            type = 'stepper',
            value = cur_prof.value,
            current = (cur_idx > 1),
            action = 'cycle_audio_profile',
            on_prev = function() step_audio_profile(-1) end,
            on_next = function() step_audio_profile(1) end,
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
        local tag_editor = ctx_ref.tag_editor
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

        local auto_reload = tag_editor and tag_editor.get_auto_reload and tag_editor.get_auto_reload() or false
        local auto_fn = function()
            if tag_editor and tag_editor.set_auto_reload then
                tag_editor.set_auto_reload(not auto_reload)
                M.invalidate_items()
                if ctx_ref.request_tick then ctx_ref.request_tick() end
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
                sublabel = 'Return to Tag Editor without modifying other files',
                action = 'confirm_batch_no',
                index = 2
            }
            return items
        end

        -- Section 1: Smart Quick-Fix Actions
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

        -- Section 2: Inline Manual Editor
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

        -- Section 3: Folder & Directory Operations (Always Shown)
        items[6] = {
            label = string.format('Batch Apply Title to Season Folder (%d files)', mkv_count),
            sublabel = 'Update header title for all MKV episodes in season directory',
            action = 'prompt_batch_apply',
            index = 6,
            role = 'batch_tool'
        }
        items[7] = {
            label = 'Strip All Header Titles in Directory [⚠ Danger Zone]',
            sublabel = 'Remove title tags from all video files in directory',
            action = 'prompt_batch_strip',
            index = 7,
            role = 'batch_tool'
        }

        -- Section 4: Configuration & Automation (Always Shown)
        items[8] = {
            label = 'Auto-reload playback after saving disk changes',
            sublabel = 'Seamlessly reload file at current second to update mpv track list',
            type = 'stepper',
            value = auto_reload and 'On' or 'Off',
            current = auto_reload,
            action = 'toggle_autoreload',
            on_prev = auto_fn,
            on_next = auto_fn,
            index = 8,
            role = 'auto_reload'
        }
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
    if state.menu_active == 'tags' and state.tag_inspector_confirm then
        state.menu_selected = (state.menu_selected == 1) and 2 or 1
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
        if item.action == 'toggle_night_mode' or item.action == 'cycle_audio_profile' then
            if item.on_next then
                item.on_next()
            else
                step_audio_profile(1)
            end
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
        elseif item.action == 'toggle_autoreload' or item.role == 'auto_reload' then
            local te = ctx_ref.tag_editor or tag_editor
            local cur
            if te and te.get_auto_reload then
                cur = te.get_auto_reload()
            elseif state.tag_editor_auto_reload ~= nil then
                cur = state.tag_editor_auto_reload
            else
                cur = true
            end
            local next_val = not cur
            if te and te.set_auto_reload then
                te.set_auto_reload(next_val)
            end
            state.tag_editor_auto_reload = next_val
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

local function calculate_menu_layout(state, items, osc_param)
    local is_pl = (state.menu_active == 'playlist')
    local is_sub_menu = state.menu_active and (
        state.menu_active:find('^sub_') ~= nil or
        state.menu_active == 'sub'
    )
    local is_drawer = state.menu_active and (
        is_sub_menu or
        state.menu_active == 'audio' or
        state.menu_active == 'video' or
        state.menu_active == 'chapters' or
        state.menu_active == 'tags'
    )

    local is_searchable = not is_drawer and is_pl and (state.menu_searchable == true or (state.menu_searchable == nil and #items > 5))
    local search_h = is_searchable and 42 or 0

    local has_any_sublabel = false
    if state.menu_active ~= 'chapters' then
        for _, item in ipairs(items) do
            if item.sublabel and item.sublabel ~= '' then
                has_any_sublabel = true
                break
            end
        end
    end

    local menu_w, row_h, header_h, footer_h, visible_max, scroll, vis, menu_h, x0, y0
    local num_x, text_x

    if is_drawer then
        menu_w = math.max(380, math.min(440, math.floor(osc_param.playresx * 0.28)))
        local is_video_menu = (state.menu_active == 'video')
        row_h = is_video_menu and 40 or (has_any_sublabel and 52 or 42)
        header_h = 50
        footer_h = 36
        num_x = 24
        text_x = 20

        local y_safe_top = 24
        local y_safe_bot = osc_param.playresy - 24
        local max_h = y_safe_bot - y_safe_top
        visible_max = math.max(1, math.floor((max_h - header_h - footer_h) / row_h))

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
        vis = math.min(total - scroll, visible_max)
        menu_h = header_h + vis * row_h + footer_h

        -- Right-docked side drawer (Style A)
        x0 = osc_param.playresx - menu_w - 24
        y0 = math.max(y_safe_top, math.floor((osc_param.playresy - menu_h) / 2))
    else
        local is_wide = is_pl or (state.menu_active == 'tmdb_matches')
        menu_w = is_wide and math.min(740, math.floor(osc_param.playresx * 0.76)) or math.min(700, math.floor(osc_param.playresx * 0.80))
        local pad_left = 20
        row_h = (is_pl or has_any_sublabel) and 58 or 46
        header_h = 50
        footer_h = 36
        num_x = 32
        text_x = pad_left + 46

        local y_safe_top = 24
        local y_safe_bot = osc_param.playresy - 24
        visible_max = math.max(1, math.min(
            is_pl and 8 or 7,
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

        local total = #items
        vis = math.min(total - scroll, visible_max)
        local card_vis = is_searchable and math.max(vis, math.min(6, visible_max)) or vis
        menu_h = header_h + search_h + card_vis * row_h + footer_h

        local cx = math.floor(osc_param.playresx / 2)
        local cy = math.floor(osc_param.playresy / 2)
        x0 = math.floor(cx - menu_w / 2)
        y0 = math.max(y_safe_top, math.floor(cy - menu_h / 2))
    end

    return {
        is_drawer = is_drawer,
        is_searchable = is_searchable,
        is_pl = is_pl,
        is_sub_menu = is_sub_menu,
        menu_w = menu_w,
        menu_h = menu_h,
        row_h = row_h,
        header_h = header_h,
        footer_h = footer_h,
        search_h = search_h,
        visible_max = visible_max,
        scroll = scroll,
        vis = vis,
        x0 = x0,
        y0 = y0,
        num_x = num_x,
        text_x = text_x,
        total = #items,
    }
end

function M.menu_handle_click()
    local state = ctx_ref.state
    if not state.menu_active then return end
    local mx, my = ctx_ref.get_virt_mouse_pos()



    local items  = M.menu_get_items()
    local osc_param = ctx_ref.osc_param or {playresx = 1280, playresy = 720}
    local l = calculate_menu_layout(state, items, osc_param)

    local is_drawer = l.is_drawer
    local is_searchable = l.is_searchable
    local menu_w = l.menu_w
    local menu_h = l.menu_h
    local row_h = l.row_h
    local header_h = l.header_h
    local search_h = l.search_h
    local x0 = l.x0
    local y0 = l.y0
    local scroll = l.scroll
    local vis = l.vis

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
        if state.menu_active == 'tags' and state.tag_inspector_confirm then
            state.menu_selected = (state.menu_selected == 1) and 2 or 1
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
        if state.menu_active == 'tags' and state.tag_inspector_confirm then
            state.menu_selected = (state.menu_selected == 1) and 2 or 1
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
    local l = calculate_menu_layout(state, items, osc_param)
    local total = l.total
    local eff_alpha = math.max(0, math.min(255, menu_alpha))
    local progress = eff_alpha / 255
    local ease = 1 - (1 - progress) * (1 - progress)

    -- Obsidian Glass Tokens (Style A)
    local pan_a = string.format('%02X', math.floor(255 - (238 * eff_alpha / 255)))
    local txt_a = string.format('%02X', math.floor(255 - eff_alpha))

    -- Horizontal Slide Animation for Side Drawer
    local slide_offset = l.is_drawer and math.floor((1 - ease) * 32) or 0
    local x0 = l.x0 + slide_offset
    local y0 = l.y0
    local menu_w = l.menu_w
    local menu_h = l.menu_h
    local row_h = l.row_h
    local header_h = l.header_h
    local footer_h = l.footer_h
    local is_drawer = l.is_drawer
    local is_searchable = l.is_searchable
    local search_h = l.search_h
    local scroll = l.scroll
    local vis = l.vis
    local text_x = l.text_x
    local num_x = l.num_x

    -- Dimmer Backdrop
    if not is_drawer then
        -- 42% Dark Scrim for Center Modals
        local dim_a = string.format('%02X', math.floor(255 - (108 * eff_alpha / 255)))
        ass:new_event()
        ass:pos(0, 0)
        ass:an(7)
        ass:append('{\\bord0\\blur0\\1c&H000000&\\1a&H' .. dim_a .. '&}')
        ass:draw_start()
        ass:rect_cw(0, 0, osc_param.playresx, osc_param.playresy)
        ass:draw_stop()
    else
        -- Subtle 18% Ambient Scrim for Side Drawers
        local dim_a = string.format('%02X', math.floor(255 - (45 * eff_alpha / 255)))
        ass:new_event()
        ass:pos(0, 0)
        ass:an(7)
        ass:append('{\\bord0\\blur0\\1c&H000000&\\1a&H' .. dim_a .. '&}')
        ass:draw_start()
        ass:rect_cw(0, 0, osc_param.playresx, osc_param.playresy)
        ass:draw_stop()
    end

    -- Card Background Panel (93.3% opaque obsidian + 1.2px specular rim light)
    ass:new_event()
    ass:pos(x0, y0)
    ass:an(7)
    ass:append('{\\bord1.2\\blur0.4\\1c&H121210&\\3c&HFFFFFF&\\3a&HE0&\\1a&H' .. pan_a .. '&}')
    ass:draw_start()
    ass:round_rect_cw(0, 0, menu_w, menu_h, 14)
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
    local esc_lbl = (is_drawer and state.menu_active and state.menu_active:find('^sub_') and state.menu_active ~= 'sub_config') and '‹ BACK' or 'ESC'
    ass:append(string.format('{\\bord0\\blur0\\1c&H8E8E93&\\1a&H00&\\fs10\\fn%s\\b600\\fsp1\\q2}%s', font, esc_lbl))

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
        elseif state.menu_active == 'chapters' then
            ass:append(string.format('{\\bord0\\blur0\\1c&H8E8E93&\\1a&H00&\\fs11\\fn%s\\b500\\q2}', font))
            ass:append(string.format('%d chapters', total))
        elseif state.menu_active == 'video' then
            ass:append(string.format('{\\bord0\\blur0\\1c&H8E8E93&\\1a&H00&\\fs11\\fn%s\\b500\\q2}', font))
            ass:append('Tuning')
        elseif state.menu_active == 'audio' then
            ass:append(string.format('{\\bord0\\blur0\\1c&H8E8E93&\\1a&H00&\\fs11\\fn%s\\b500\\q2}', font))
            ass:append('DSP & Tracks')
        elseif state.menu_active == 'tags' then
            ass:append(string.format('{\\bord0\\blur0\\1c&H8E8E93&\\1a&H00&\\fs11\\fn%s\\b500\\q2}', font))
            ass:append('Matroska Tags')
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
    ass:append('{\\bord0\\blur0\\1c&HFFFFFF&\\1a&HE8&}')
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
            elseif item.action == 'nav_menu' or item.action == 'open_sub_config' or item.action == 'search_tmdb_picker' or item.action == 'edit_manual_inline' then
                local val_text = (item.value and item.value ~= '') and (item.value .. '  ›') or '›'
                local nav_col = is_sel and '&HFFFFFF&' or '&H8E8E93&'
                ass:append(string.format('{\\bord0\\blur0\\1c%s\\1a&H%s&\\fs12\\fn%s\\b600\\q2}', nav_col, txt_a, font))
                ass:append(val_text)
            elseif is_cur then
                local cur_col = is_sel and '&HFFFFFF&' or '&H0A84FF&'
                if item.time_str and item.time_str ~= '' then
                    ass:append(string.format('{\\bord0\\blur0\\1c%s\\1a&H%s&\\fs11\\fn%s\\b500\\q2}%s  {\\fs14\\b700}✓', cur_col, txt_a, font, item.time_str))
                else
                    ass:append(string.format('{\\bord0\\blur0\\1c%s\\1a&H%s&\\fs14\\b700\\q2}', cur_col, txt_a))
                    ass:append('✓')
                end
            elseif item.time_str and item.time_str ~= '' then
                local time_col = is_sel and '&HFFFFFF&' or '&H8E8E93&'
                ass:append(string.format('{\\bord0\\blur0\\1c%s\\1a&H%s&\\fs11\\fn%s\\b500\\q2}', time_col, txt_a, font))
                ass:append(item.time_str)
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
                ass:append('{\\bord0\\blur0\\1c&HFFFFFF&\\1a&HF0&}')
                ass:draw_start()
                ass:rect_cw(0, 0, menu_w - 32, 1)
                ass:draw_stop()
            end
        else
            -- Centered modal row rendering
            if is_sel then
                ass:new_event()
                ass:pos(x0 + 6, ry + 4)
                ass:an(7)
                ass:append('{\\bord0\\blur0\\1c&HFFFFFF&\\1a&HE4&}')
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
                ass:append('{\\bord0\\blur0\\1c&HFFFFFF&\\1a&HF0&}')
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
    ass:append('{\\bord0\\blur0\\1c&HFFFFFF&\\1a&HE8&}')
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
