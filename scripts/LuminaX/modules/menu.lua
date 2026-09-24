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

local ctx_ref = {}

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
    for _, name in ipairs(menu_key_bindings) do
        mp.remove_key_binding(name)
    end
    menu_key_bindings = {}
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
                if clean_show and season and episode then
                    local line1 = string.format('%s • S%02dE%02d', clean_show, tonumber(season), tonumber(episode))
                    local line2 = string.format('Episode %02d', tonumber(episode))
                    items[#items + 1] = {label = line1, sublabel = line2,
                        current = is_curr, index = i}
                elseif clean_show and year then
                    items[#items + 1] = {label = string.format('%s (%s)', clean_show, year), sublabel = '',
                        current = is_curr, index = i}
                else
                    local disp = (clean_show and clean_show ~= '') and clean_show or (fname ~= '' and fname or ('Item ' .. i))
                    items[#items + 1] = {label = disp, sublabel = '',
                        current = is_curr, index = i}
                end
            end
        end
    elseif state.menu_active == 'audio' then
        local audio_tracks = get_tracks_by_type('audio')
        if #audio_tracks == 0 then
            items[1] = {label = '(No audio tracks)', current = false, index = 0}
        else
            local cur_aid = tonumber(mp.get_property('aid', '0'))
            for i, track in ipairs(audio_tracks) do
                local lang = track.lang or 'und'
                local title = track.title or ''
                local label
                local sublabel = ''
                if title ~= '' then
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
                    local codec = track.codec or ''
                    local ch    = track['demux-channel-count']
                    local rate  = track['demux-samplerate']
                    local extra = ''
                    if ch   then extra = extra .. '  ' .. ch .. 'ch' end
                    if rate then extra = extra .. '  ' .. math.floor(rate/1000) .. ' kHz' end
                    label = string.format('[%s]  %s%s', lang, codec ~= '' and codec or ('Track '..i), extra)
                end
                local is_cur = track.selected or (cur_aid ~= nil and track.id == cur_aid)
                items[i] = {label = label, sublabel = sublabel, current = is_cur, index = i, track_id = track.id}
            end
        end
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
                local raw_sub_title = title ~= '' and title or 'Track ' .. i
                local clean_sub_title = raw_sub_title:gsub('~', ''):gsub('%s*/+%s*', ' • ')
                local label = string.format('[%s]  %s', lang, clean_sub_title)
                local sublabel = ''
                local codec = track.codec or ''
                local flags = {}
                if track.forced then table.insert(flags, 'Forced') end
                if track['default'] then table.insert(flags, 'Default') end
                if track.external then table.insert(flags, 'External') end
                if codec ~= '' then table.insert(flags, codec) end
                if #flags > 0 then
                    sublabel = table.concat(flags, ' • ')
                end
                local is_cur = (not sub_off) and (track.selected or (cur_sid ~= nil and track.id == cur_sid))
                items[i+1] = {label = label, sublabel = sublabel, current = is_cur, index = i, track_id = track.id}
            end
        end
    elseif state.menu_active == 'chapters' then
        local chapters = mp.get_property_native('chapter-list', {})
        local cur_ch = mp.get_property_number('chapter', -1)
        if not chapters or #chapters == 0 then
            items[1] = {label = '(No chapters)', current = false, index = 0}
        else
            local utils = ctx_ref.utils
            for i, ch in ipairs(chapters) do
                local title = (ch and ch.title and ch.title ~= '') and ch.title or ('Chapter ' .. i)
                local time_sec = ch and ch.time
                local time = (utils and utils.format_time) and utils.format_time(time_sec) or '00:00'
                local label = string.format('[%s]  %s', time, title)
                items[i] = {label = label, current = (i - 1 == cur_ch), index = i - 1}
            end
        end
    elseif state.menu_active == 'tags' then
        local utils = ctx_ref.utils
        local path = mp.get_property('path', '')
        if utils and utils.is_url and utils.is_url(path) then
            items[1] = {
                label = '(Online Stream - Tags Read-Only)',
                sublabel = 'Metadata editing is disabled for streaming URLs',
                action = 'none',
                index = 1
            }
            return items
        end

        local cur_title = mp.get_property('media-title') or mp.get_property('filename') or ''
        cur_title = cur_title:gsub('%.%w+$', '')

        local fn = mp.get_property('filename') or ''
        local show, _, _, year = utils.parse_clean_title(nil, fn)
        local derived_fn = (show and show ~= '') and (year and (show .. ' (' .. year .. ')') or show) or fn
        derived_fn = derived_fn:gsub('%.%w+$', '')

        local tmdb_curr = ctx_ref.get_tmdb_current and ctx_ref.get_tmdb_current()
        local tmdb_title = (tmdb_curr and tmdb_curr.show_name and tmdb_curr.show_name ~= '') and
            ((tmdb_curr.year and tmdb_curr.year ~= '') and (tmdb_curr.show_name .. ' (' .. tmdb_curr.year .. ')') or tmdb_curr.show_name) or nil

        local filepath = mp.get_property('path', '')
        local parent_dir_title = nil
        if filepath ~= '' then
            local parent = filepath:match('([^/]+)/[^/]+$')
            if parent then
                parent_dir_title = parent:gsub('%s[Ss]%d+.*$', ''):gsub('%b[]', ''):gsub('%([Ss]eason%s*%d+%)', ''):gsub('`', "'"):gsub('%s+', ' '):gsub('^%s+', ''):gsub('%s+$', '')
            end
        end

        items[1] = {
            label = 'Search & Pick Nearest TMDB Match...',
            sublabel = 'Query TMDB API & select exact show/movie match from list',
            action = 'search_tmdb_picker',
            index = 1
        }
        items[2] = {
            label = 'Edit Title Manually (Current File)',
            sublabel = 'Type with OSD keyboard: "' .. cur_title:sub(1, 40) .. '"',
            action = 'edit_manual',
            index = 2
        }
        items[3] = {
            label = 'Apply Show Title to All Episodes in Folder',
            sublabel = 'Batch update header title across all .mkv files in current directory',
            action = 'edit_folder_manual',
            index = 3
        }
        items[4] = {
            label = 'Set Title from Parent Folder Name',
            sublabel = parent_dir_title and ('Apply clean series folder title: "' .. parent_dir_title:sub(1, 40) .. '"') or 'Parent folder name not available',
            action = 'set_parent_folder',
            index = 4
        }
        items[5] = {
            label = 'Set Title from Filename',
            sublabel = 'Apply clean derived filename title: "' .. derived_fn:sub(1, 40) .. '"',
            action = 'set_filename',
            index = 5
        }
        items[6] = {
            label = 'Set Title from TMDB',
            sublabel = tmdb_title and ('Apply verified TMDB name: "' .. tmdb_title:sub(1, 40) .. '"') or 'TMDB metadata not loaded yet',
            action = 'set_tmdb',
            index = 6
        }
        items[7] = {
            label = 'Clean All Watermarks (1-Click)',
            sublabel = 'Auto-strip promotional URLs & rip tags from title and audio/subtitle tracks',
            action = 'clean_all',
            index = 7
        }
        items[8] = {
            label = 'Delete Title Tag (Current File)',
            sublabel = 'Removes title tag from MKV (player falls back to filename)',
            action = 'delete_tag',
            index = 8
        }
        items[9] = {
            label = 'Batch Delete Title Tags (All Files in Folder)',
            sublabel = 'Removes title tags from all .mkv files in directory',
            action = 'delete_folder_tags',
            index = 9
        }
        items[10] = {
            label = 'Force Refresh TMDB Metadata & Clear Cache',
            sublabel = 'Purge cached TMDB lookup and re-fetch poster/backdrop metadata',
            action = 'refresh_tmdb',
            index = 10
        }
    elseif state.menu_active == 'tmdb_matches' then
        if not tmdb_matches_list or #tmdb_matches_list == 0 then
            items[1] = {
                label = '(No matching TMDB titles found)',
                sublabel = 'Press ESC to return to Tags menu and try a different query',
                action = 'none',
                index = 1
            }
        else
            for i, cand in ipairs(tmdb_matches_list) do
                local type_str = (cand.media_type == 'tv' and 'TV Series') or 'Movie'
                local yr_str = (cand.year and cand.year ~= '') and (' (' .. cand.year .. ')') or ''
                local rat_str = (cand.rating and cand.rating ~= '') and ('  ·  ★ ' .. cand.rating) or ''
                local ov_str = (cand.overview and cand.overview ~= '') and ('  ·  ' .. cand.overview:sub(1, 45) .. '...') or ''
                items[i] = {
                    label = cand.title,
                    sublabel = type_str .. yr_str .. rat_str .. ov_str,
                    candidate_title = cand.title,
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
    local items = M.menu_get_items()
    local count = #items
    if count == 0 then return end
    state.menu_selected = state.menu_selected + dir
    if state.menu_selected < 1 then state.menu_selected = count end
    if state.menu_selected > count then state.menu_selected = 1 end
    if ctx_ref.request_tick then ctx_ref.request_tick() end
end

function M.menu_confirm()
    local state = ctx_ref.state
    local items = M.menu_get_items()
    local item = items[state.menu_selected]
    if not item then return end

    if state.menu_active == 'playlist' then
        mp.commandv('playlist-play-index', item.index - 1)
    elseif state.menu_active == 'chapters' then
        mp.commandv('set', 'chapter', tostring(item.index))
    elseif state.menu_active == 'audio' then
        if item.track_id then
            mp.commandv('set', 'aid', tostring(item.track_id))
        end
    elseif state.menu_active == 'sub' then
        if item.track_id then
            mp.commandv('set', 'sid', tostring(item.track_id))
        end
    elseif state.menu_active == 'tags' then
        M.menu_close()
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
            local default_query = (show and show ~= '' and #show > 3) and show or (parent_dir_title or fn:gsub('%.%w+$', ''))

            tag_editor.input_box_open('SEARCH TMDB MATCHES', default_query, function(query_text)
                if query_text and query_text ~= '' then
                    mp.osd_message('Searching TMDB for: ' .. query_text .. '...', 3)
                    local ss = ctx_ref.screensaver
                    if ss and ss.fetch_candidates then
                        ss.fetch_candidates(query_text, function(results)
                            tmdb_matches_list = results or {}
                            state.menu_active = 'tmdb_matches'
                            state.menu_selected = 1
                            state.menu_scroll = 0
                            M.invalidate_items()
                            if ctx_ref.request_tick then ctx_ref.request_tick() end
                            if ctx_ref.on_open then ctx_ref.on_open() end
                        end)
                    else
                        mp.osd_message('TMDB search not available', 3)
                    end
                end
            end)
        elseif item.action == 'clean_all' then
            tag_editor.clean_all_mkv_watermarks(function()
                if ctx_ref.on_tag_updated then ctx_ref.on_tag_updated() end
            end)
        elseif item.action == 'edit_manual' then
            local cur = mp.get_property('media-title') or mp.get_property('filename') or ''
            cur = cur:gsub('%.%w+$', '')
            tag_editor.input_box_open('EDIT MOVIE / SERIES TITLE', cur, function(new_val)
                if new_val and new_val ~= '' then
                    tag_editor.apply_mkv_title(new_val, function()
                        if ctx_ref.on_tag_updated then ctx_ref.on_tag_updated() end
                    end)
                end
            end)
        elseif item.action == 'edit_folder_manual' then
            local cur = mp.get_property('media-title') or mp.get_property('filename') or ''
            cur = cur:gsub('%.%w+$', '')
            tag_editor.input_box_open('BATCH EDIT FOLDER SHOW TITLE', cur, function(new_val)
                if new_val and new_val ~= '' then
                    tag_editor.apply_mkv_title_folder(new_val, function()
                        if ctx_ref.on_tag_updated then ctx_ref.on_tag_updated() end
                    end)
                end
            end)
        elseif item.action == 'set_parent_folder' then
            local filepath = mp.get_property('path', '')
            if filepath ~= '' then
                local parent = filepath:match('([^/]+)/[^/]+$')
                if parent then
                    local clean_parent = parent:gsub('%s[Ss]%d+.*$', ''):gsub('%b[]', ''):gsub('%([Ss]eason%s*%d+%)', ''):gsub('`', "'"):gsub('%s+', ' '):gsub('^%s+', ''):gsub('%s+$', '')
                    tag_editor.apply_mkv_title(clean_parent, function()
                        if ctx_ref.on_tag_updated then ctx_ref.on_tag_updated() end
                    end)
                end
            end
        elseif item.action == 'set_filename' then
            local fn = mp.get_property('filename') or ''
            local show, _, _, year = utils.parse_clean_title(nil, fn)
            local derived = (show and show ~= '') and (year and (show .. ' (' .. year .. ')') or show) or fn
            derived = derived:gsub('%.%w+$', '')
            tag_editor.apply_mkv_title(derived, function()
                if ctx_ref.on_tag_updated then ctx_ref.on_tag_updated() end
            end)
        elseif item.action == 'set_tmdb' then
            local tmdb_curr = ctx_ref.get_tmdb_current and ctx_ref.get_tmdb_current()
            local tmdb_title = (tmdb_curr and tmdb_curr.show_name and tmdb_curr.show_name ~= '') and
                ((tmdb_curr.year and tmdb_curr.year ~= '') and (tmdb_curr.show_name .. ' (' .. tmdb_curr.year .. ')') or tmdb_curr.show_name) or nil
            if tmdb_title then
                tag_editor.apply_mkv_title(tmdb_title, function()
                    if ctx_ref.on_tag_updated then ctx_ref.on_tag_updated() end
                end)
            else
                mp.osd_message('TMDB title not loaded yet', 3)
            end
        elseif item.action == 'delete_tag' then
            tag_editor.delete_mkv_title(function()
                if ctx_ref.on_tag_updated then ctx_ref.on_tag_updated() end
            end)
        elseif item.action == 'delete_folder_tags' then
            tag_editor.delete_mkv_title_folder(function()
                if ctx_ref.on_tag_updated then ctx_ref.on_tag_updated() end
            end)
        elseif item.action == 'refresh_tmdb' then
            if ctx_ref.on_tag_updated then
                ctx_ref.on_tag_updated(true)
                mp.osd_message('✓ Refreshed TMDB metadata & cache', 3)
            end
        end
        return
    elseif state.menu_active == 'tmdb_matches' then
        M.menu_close()
        local tag_editor = ctx_ref.tag_editor
        if item.action == 'select_tmdb_match' and item.candidate_title then
            local cand_title = item.candidate_title
            tag_editor.apply_mkv_title_folder(cand_title, function()
                if ctx_ref.on_tag_updated then
                    ctx_ref.on_tag_updated(true)
                end
                mp.osd_message('✓ TMDB Match Applied: ' .. cand_title, 4)
            end)
        end
        return
    end
    M.menu_close()
end

function M.menu_handle_click()
    local state = ctx_ref.state
    if not state.menu_active then return end
    local mx, my = ctx_ref.get_virt_mouse_pos()
    local items  = M.menu_get_items()
    local is_pl  = (state.menu_active == 'playlist')
    local osc_param = ctx_ref.osc_param
    local menu_w = 740
    local has_any_sublabel = false
    for _, item in ipairs(items) do
        if item.sublabel and item.sublabel ~= '' then
            has_any_sublabel = true
            break
        end
    end
    local row_h  = (is_pl or state.menu_active == 'tags' or has_any_sublabel) and 62 or 46
    local header_h = 56
    local pad_bot  = 18
    local y_safe_top = 8
    local y_safe_bot = osc_param.playresy - 195
    local visible_max = math.max(1, math.min(
        is_pl and 6 or 7,
        math.floor((y_safe_bot - y_safe_top - header_h - pad_bot) / row_h)
    ))
    local scroll = state.menu_scroll or 0
    local vis    = math.min(#items - scroll, visible_max)
    local menu_h = header_h + vis * row_h + pad_bot
    local cx = osc_param.playresx / 2
    local x0 = cx - menu_w / 2
    local y0 = math.max(y_safe_top, math.min(y_safe_bot - menu_h,
               (y_safe_top + y_safe_bot) / 2 - menu_h / 2))

    if mx < x0 or mx > x0 + menu_w or my < y0 or my > y0 + menu_h then
        M.menu_close()
        return
    end

    -- Header click: toggle series filter
    if my >= y0 and my < y0 + header_h then
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
        end
        return
    end

    for i = 1, vis do
        local ry = y0 + header_h + (i - 1) * row_h
        local ai = i + scroll
        if my >= ry and my < ry + row_h and ai <= #items then
            state.menu_selected = ai
            M.menu_confirm()
            return
        end
    end
end

function M.menu_open(menu_type)
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

    local items = M.menu_get_items()
    local matched_idx = nil
    for i, it in ipairs(items) do
        if it.current then
            matched_idx = i
            break
        end
    end
    if matched_idx then
        state.menu_selected = matched_idx
    else
        state.menu_selected = 1
    end

    menu_key_bindings = {}
    local function bind_keys(k1, k2, name, fn, flags)
        menu_add_binding(k1, name, fn, flags)
        if k2 and k2 ~= k1 then
            menu_add_binding(k2, name .. '_alt', fn, flags)
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
    bind_keys('ENTER', 'enter', 'menu-enter', function() M.menu_confirm() end)
    bind_keys('ESC', 'esc', 'menu-esc', function() M.menu_close() end)
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
    local is_pl = (state.menu_active == 'playlist')

    local menu_w    = math.min(740, math.floor(osc_param.playresx * 0.88))
    local pad_left  = 20
    local has_any_sublabel = false
    for _, item in ipairs(items) do
        if item.sublabel and item.sublabel ~= '' then
            has_any_sublabel = true
            break
        end
    end
    local row_h     = (is_pl or state.menu_active == 'tags' or has_any_sublabel) and 62 or 46
    local header_h  = 56
    local pad_bot   = 18
    local num_x     = 28
    local text_x    = pad_left + 50

    local y_safe_top = 8
    local y_safe_bot = osc_param.playresy - 195
    local visible_max = math.max(1, math.min(
        is_pl and 6 or 7,
        math.floor((y_safe_bot - y_safe_top - header_h - pad_bot) / row_h)
    ))

    local scroll = state.menu_scroll or 0
    if scroll < 0 then scroll = 0 end
    if state.menu_selected - scroll > visible_max then
        scroll = state.menu_selected - visible_max
    elseif state.menu_selected - scroll < 1 then
        scroll = state.menu_selected - 1
    end
    if scroll < 0 then scroll = 0 end
    state.menu_scroll = scroll

    local total  = #items
    local vis    = math.min(total - scroll, visible_max)
    local menu_h = header_h + vis * row_h + pad_bot

    local cx = osc_param.playresx / 2
    local x0 = cx - menu_w / 2
    local y0 = math.max(y_safe_top, math.min(y_safe_bot - menu_h,
               (y_safe_top + y_safe_bot) / 2 - menu_h / 2))

    local eff_alpha = math.max(0, math.min(255, menu_alpha))
    local dim_a = string.format('%02X', math.floor(255 - (110 * eff_alpha / 255)))
    local pan_a = string.format('%02X', math.floor(255 - (200 * eff_alpha / 255)))
    local txt_a = string.format('%02X', math.floor(255 - eff_alpha))

    ass:new_event()
    ass:pos(0,0)
    ass:an(7)
    ass:append('{\\bord0\\blur0\\1c&H000000&\\1a&H'..dim_a..'&}')
    ass:draw_start()
    ass:rect_cw(0, 0, osc_param.playresx, osc_param.playresy)
    ass:draw_stop()

    ass:new_event()
    ass:pos(x0, y0)
    ass:an(7)
    ass:append('{\\bord1.2\\blur0.5\\1c&H161618&\\3c&HFFFFFF&\\3a&HD8&\\1a&H'..pan_a..'&}')
    ass:draw_start()
    ass:round_rect_cw(0, 0, menu_w, menu_h, 16)
    ass:draw_stop()

    local titles = {playlist='PLAYLIST', audio='AUDIO TRACKS', sub='SUBTITLES', chapters='CHAPTERS', tags='METADATA & TAGS', tmdb_matches='TMDB MATCHES'}
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
        ass:pos(x0 + menu_w - 18, y0 + header_h / 2)
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
        ass:append(string.format('{\\bord0\\blur0\\1c&HFFFFFF&\\1a&H00&\\fs13\\fn%s\\b700\\fsp2.5\\q2}', font))
        ass:append(titles[state.menu_active] or '')

        ass:new_event()
        ass:pos(x0 + menu_w - 18, y0 + header_h / 2)
        ass:an(6)
        ass:append(string.format('{\\bord0\\blur0\\1c&H8E8E93&\\1a&H00&\\fs12\\fn%s\\b300\\q2}', font))
        ass:append(string.format('%d items', total))
    end

    ass:new_event()
    ass:pos(x0, y0 + header_h)
    ass:an(7)
    ass:append('{\\bord0\\blur0\\1c&H3A3A3C&\\1a&H00&}')
    ass:draw_start()
    ass:rect_cw(0, 0, menu_w, 1)
    ass:draw_stop()

    do
        local sel_i   = state.menu_selected - scroll
        local bar_vis = (sel_i >= 1 and sel_i <= vis)
        local tgt_y   = y0 + header_h + (sel_i - 1) * row_h + 5
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

        local ry     = y0 + header_h + (i - 1) * row_h
        local is_sel = (ai == state.menu_selected)
        local is_cur = item.current

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
            ass:pos(x0 + menu_w - 24, ry + row_h / 2)
            ass:an(6)
            ass:append(string.format('{\\bord0\\blur0\\1c&H0A84FF&\\1a&H%s&\\fs15\\b700\\q2}', txt_a))
            ass:append('\xe2\x9c\x93')
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

    if scroll > 0 then
        ass:new_event()
        ass:pos(x0 + menu_w / 2, y0 + header_h + 10)
        ass:an(8)
        ass:append(string.format('{\\bord0\\blur0\\1c&H8E8E93&\\1a&H00&\\fs12\\fn%s\\b300\\q2}', font))
        ass:append('\xe2\x96\xb2  more above')
    end

    if scroll + vis < total then
        ass:new_event()
        ass:pos(x0 + menu_w / 2, y0 + menu_h - 8)
        ass:an(2)
        ass:append(string.format('{\\bord0\\blur0\\1c&H8E8E93&\\1a&H00&\\fs12\\fn%s\\b300\\q2}', font))
        ass:append('\xe2\x96\xbc  more below')
    end
end

return M
