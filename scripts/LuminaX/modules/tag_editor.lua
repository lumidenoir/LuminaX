-- ============================================================================
-- ModernH Module: Tag Editor & OSD Text Input
-- Cross-platform in-player OSD text input modal & mkvpropedit metadata writer
-- ============================================================================

local M = {}

local input_active       = false
local input_text         = ''
local input_cursor       = 1
local input_prompt       = 'EDIT MOVIE TITLE'
local input_callback     = nil
local input_on_cancel   = nil
local input_key_bindings = {}
local input_cursor_blink = true
local input_blink_timer  = nil

local ctx_ref = {}
local auto_reload_enabled = true

function M.get_auto_reload()
    return auto_reload_enabled
end

function M.set_auto_reload(val)
    auto_reload_enabled = (val == true)
end

function M.init(ctx)
    ctx_ref = ctx
    mp.register_event('start-file', function()
        pcall(mp.set_property, 'force-media-title', '')
        if input_active then
            M.input_box_close()
        end
    end)
end

function M.is_active()
    return input_active
end

local cached_mkvpropedit = nil
local mkvpropedit_checked = false

-- Find mkvpropedit binary in PATH or common directories (memoized)
function M.find_mkvpropedit()
    if mkvpropedit_checked then return cached_mkvpropedit end
    local candidates = {'mkvpropedit', 'mkvpropedit.exe'}
    local mpv_dir = mp.command_native({'expand-path', '~~/'}) or ''
    if mpv_dir ~= '' then
        table.insert(candidates, mpv_dir .. 'mkvpropedit.exe')
        table.insert(candidates, mpv_dir .. '../mkvpropedit.exe')
        table.insert(candidates, mpv_dir .. 'mkvpropedit')
    end
    table.insert(candidates, 'C:\\Program Files\\MKVToolNix\\mkvpropedit.exe')
    table.insert(candidates, 'C:\\Program Files (x86)\\MKVToolNix\\mkvpropedit.exe')

    for _, bin in ipairs(candidates) do
        local res = mp.command_native({
            name = 'subprocess',
            args = {bin, '--version'},
            capture_stdout = true,
            capture_stderr = true,
        })
        if res and res.status == 0 then
            cached_mkvpropedit = bin
            mkvpropedit_checked = true
            return bin
        end
    end
    mkvpropedit_checked = true
    return nil
end

local function is_remote_path(path)
    if not path or path == '' then return true end
    if ctx_ref.utils and ctx_ref.utils.is_url and ctx_ref.utils.is_url(path) then
        return true
    end
    return path:find('^%a[%w+.-]*://') ~= nil or path:find('^ytdl://') ~= nil or path:find('^magnet:') ~= nil
end

-- Apply new movie title tag to MKV header
function M.apply_mkv_title(new_title, on_done)
    if not new_title or new_title == '' then return end
    local path = mp.get_property('path')
    if is_remote_path(path) then
        mp.osd_message('Cannot edit remote streams', 2)
        return
    end
    if not path:lower():match('%.mkv$') and not path:lower():match('%.webm$') then
        pcall(mp.set_property, 'file-local-options/media-title', new_title)
        mp.osd_message('Session title updated: ' .. new_title, 3)
        if on_done then on_done() end
        return
    end

    local bin = M.find_mkvpropedit()
    if not bin then
        pcall(mp.set_property, 'file-local-options/media-title', new_title)
        mp.osd_message('mkvpropedit not found; updated for current session only', 4)
        if on_done then on_done() end
        return
    end

    mp.osd_message('Saving title to file...', 2)
    mp.command_native_async({
        name = 'subprocess',
        args = {bin, path, '--edit', 'info', '--set', 'title=' .. new_title},
        capture_stdout = true,
        capture_stderr = true,
    }, function(ok, res)
        if ok and res and res.status == 0 then
            pcall(mp.set_property, 'file-local-options/media-title', new_title)
            pcall(mp.set_property, 'force-media-title', new_title)
            if auto_reload_enabled then
                M.reload_current_file(on_done)
            else
                mp.osd_message('✓ Title saved: ' .. new_title, 3)
                if on_done then on_done() end
            end
        else
            local err = (res and res.stderr and res.stderr ~= '') and res.stderr or 'Failed to update title'
            mp.osd_message('Error: ' .. err:sub(1, 60), 4)
        end
    end)
end

-- Delete title tag from MKV header
function M.delete_mkv_title(on_done)
    local path = mp.get_property('path')
    if is_remote_path(path) then return end
    if not path:lower():match('%.mkv$') and not path:lower():match('%.webm$') then return end

    local bin = M.find_mkvpropedit()
    if not bin then
        mp.osd_message('mkvpropedit not found', 3)
        return
    end

    mp.osd_message('Deleting title tag...', 2)
    mp.command_native_async({
        name = 'subprocess',
        args = {bin, path, '--edit', 'info', '--delete', 'title'},
        capture_stdout = true,
        capture_stderr = true,
    }, function(ok, res)
        if ok and res and res.status == 0 then
            local fn = mp.get_property('filename') or ''
            pcall(mp.set_property, 'file-local-options/media-title', fn)
            pcall(mp.set_property, 'force-media-title', '')
            mp.osd_message('✓ Title tag deleted (using filename)', 3)
            if on_done then on_done() end
        else
            mp.osd_message('Failed to delete title tag', 3)
        end
    end)
end

-- Apply title tag to all MKV files in current directory (batch)
function M.apply_mkv_title_folder(new_title, on_done)
    if not new_title or new_title == '' then return end
    local path = mp.get_property('path')
    if is_remote_path(path) then return end
    local bin = M.find_mkvpropedit()
    if not bin then
        mp.osd_message('mkvpropedit not found (install mkvtoolnix)', 4)
        return
    end

    local dir = path:match('^(.*)/[^/]+$') or '.'
    local utils_pkg = require and require('mp.utils') or nil
    local readdir = (utils_pkg and utils_pkg.readdir) or (mp.utils and mp.utils.readdir)
    local files = readdir and readdir(dir, 'files')
    if not files then
        mp.osd_message('Failed to read directory files', 3)
        return
    end

    local mkv_count = 0
    for _, fn in ipairs(files) do
        if fn:lower():match('%.mkv$') or fn:lower():match('%.webm$') then
            mkv_count = mkv_count + 1
            local file_path = dir .. '/' .. fn
            mp.command_native_async({
                name = 'subprocess',
                args = {bin, file_path, '--edit', 'info', '--set', 'title=' .. new_title},
            }, function() end)
        end
    end

    pcall(mp.set_property, 'file-local-options/media-title', new_title)
    pcall(mp.set_property, 'force-media-title', new_title)
    mp.osd_message(string.format('✓ Title updated for %d files in folder', mkv_count), 4)
    if on_done then on_done() end
end

-- Delete title tags from all MKV files in current directory (batch)
function M.delete_mkv_title_folder(on_done)
    local path = mp.get_property('path')
    if is_remote_path(path) then return end
    local bin = M.find_mkvpropedit()
    if not bin then
        mp.osd_message('mkvpropedit not found', 3)
        return
    end

    local dir = path:match('^(.*)/[^/]+$') or '.'
    local utils_pkg = require and require('mp.utils') or nil
    local readdir = (utils_pkg and utils_pkg.readdir) or (mp.utils and mp.utils.readdir)
    local files = readdir and readdir(dir, 'files')
    if not files then return end

    local mkv_count = 0
    for _, fn in ipairs(files) do
        if fn:lower():match('%.mkv$') or fn:lower():match('%.webm$') then
            mkv_count = mkv_count + 1
            local file_path = dir .. '/' .. fn
            mp.command_native_async({
                name = 'subprocess',
                args = {bin, file_path, '--edit', 'info', '--delete', 'title'},
            }, function() end)
        end
    end

    local fn = mp.get_property('filename') or ''
    pcall(mp.set_property, 'file-local-options/media-title', fn)
    pcall(mp.set_property, 'force-media-title', '')
    mp.osd_message(string.format('✓ Tags deleted for %d files in folder', mkv_count), 4)
    if on_done then on_done() end
end

-- Clean all junk track titles and watermarks
function M.clean_all_mkv_watermarks(on_done)
    local path = mp.get_property('path')
    if is_remote_path(path) then
        mp.osd_message('Cannot edit remote streams', 2)
        return
    end
    if not path:lower():match('%.mkv$') and not path:lower():match('%.webm$') then
        mp.osd_message('Tag cleaning requires Matroska (.mkv) files', 3)
        return
    end

    local bin = M.find_mkvpropedit()
    if not bin then
        mp.osd_message('mkvpropedit not found (install mkvtoolnix)', 4)
        return
    end

    local utils = ctx_ref.utils
    local show, _, _, year = utils.parse_clean_title(mp.get_property('media-title'), mp.get_property('filename'))
    local clean_title = (show and show ~= '') and (year and (show .. ' (' .. year .. ')') or show) or (mp.get_property('filename') or '')
    clean_title = clean_title:gsub('%.%w+$', '')

    local args = {bin, path, '--edit', 'info', '--set', 'title=' .. clean_title}

    local tracks = mp.get_property_native('track-list', {})
    local v_idx, a_idx, s_idx = 0, 0, 0
    for _, t in ipairs(tracks) do
        local t_type = t.type
        local t_title = t.title or ''
        local is_junk = utils.is_junk_title(t_title) or t_title:lower():find('as%-encodes') or t_title:lower():find('1tamilmv') or t_title:lower():find('tamilblasters') or t_title:lower():find('tamilrockers')
        if t_type == 'video' then
            v_idx = v_idx + 1
            if t_title ~= '' and (is_junk or utils.is_junk_title(t_title)) then
                table.insert(args, '--edit')
                table.insert(args, 'track:v' .. v_idx)
                table.insert(args, '--delete')
                table.insert(args, 'name')
            end
        elseif t_type == 'audio' then
            a_idx = a_idx + 1
            if t_title ~= '' and is_junk then
                local lang_name = (t.lang == 'tam' and 'Tamil') or (t.lang == 'tel' and 'Telugu') or (t.lang == 'hin' and 'Hindi') or (t.lang == 'eng' and 'English') or (t.lang and t.lang:upper()) or 'Audio'
                local ch = t['demux-channel-count']
                local ch_str = (ch == 6 and '5.1') or (ch == 8 and '7.1') or (ch == 2 and '2.0') or ''
                local codec = (t.codec and t.codec:lower():find('eac3') and 'E-AC-3') or (t.codec and t.codec:lower():find('ac3') and 'AC-3') or (t.codec and t.codec:lower():find('aac') and 'AAC') or (t.codec and t.codec:upper()) or ''
                local new_name = lang_name .. (codec ~= '' and (' [' .. codec .. (ch_str ~= '' and (' ' .. ch_str) or '') .. ']') or '')
                table.insert(args, '--edit')
                table.insert(args, 'track:a' .. a_idx)
                table.insert(args, '--set')
                table.insert(args, 'name=' .. new_name)
            end
        elseif t_type == 'sub' then
            s_idx = s_idx + 1
            if t_title ~= '' and is_junk then
                local lang_name = (t.lang == 'eng' and 'English') or (t.lang == 'tam' and 'Tamil') or (t.lang == 'tel' and 'Telugu') or (t.lang == 'hin' and 'Hindi') or (t.lang and t.lang:upper()) or 'Subtitles'
                table.insert(args, '--edit')
                table.insert(args, 'track:s' .. s_idx)
                table.insert(args, '--set')
                table.insert(args, 'name=' .. lang_name)
            end
        end
    end

    mp.osd_message('Cleaning tags & watermarks...', 2)
    mp.command_native_async({
        name = 'subprocess',
        args = args,
        capture_stdout = true,
        capture_stderr = true,
    }, function(ok, res)
        if ok and res and res.status == 0 then
            pcall(mp.set_property, 'file-local-options/media-title', clean_title)
            pcall(mp.set_property, 'force-media-title', clean_title)
            if auto_reload_enabled then
                M.reload_current_file(on_done)
            else
                mp.osd_message('✓ Cleaned all tags: ' .. clean_title .. ' (Saved to disk)', 3)
                if on_done then on_done() end
            end
        else
            local err = (res and res.stderr and res.stderr ~= '') and res.stderr or 'Clean failed'
            mp.osd_message('Error: ' .. err:sub(1, 60), 4)
        end
    end)
end

-- Seamlessly reload current file at exact position to refresh demuxer track-list
function M.reload_current_file(on_done)
    local path = mp.get_property('path')
    if not path or path == '' or is_remote_path(path) then
        if on_done then on_done() end
        return
    end
    local pos = mp.get_property_number('time-pos', 0)
    local pause = mp.get_property_bool('pause', false)
    local aid = mp.get_property('aid')
    local sid = mp.get_property('sid')
    mp.commandv('loadfile', path, 'replace', 'start=' .. tostring(pos))
    pcall(mp.set_property_bool, 'pause', pause)
    if aid and aid ~= 'no' then pcall(mp.set_property, 'aid', aid) end
    if sid and sid ~= 'no' then pcall(mp.set_property, 'sid', sid) end
    mp.osd_message('✓ Headers Cleaned & Reloaded', 1.5)
    if on_done then on_done() end
end

-- Close text input modal
function M.input_box_close()
    input_active = false
    input_callback = nil
    input_on_cancel = nil
    if input_blink_timer then
        input_blink_timer:kill()
        input_blink_timer = nil
    end
    for _, name in ipairs(input_key_bindings) do
        mp.remove_key_binding(name)
    end
    input_key_bindings = {}
    if ctx_ref.request_tick then ctx_ref.request_tick() end
    if ctx_ref.on_close then ctx_ref.on_close() end
end

-- Open text input modal
function M.input_box_open(prompt, initial_text, callback, on_cancel)
    if ctx_ref.on_open then ctx_ref.on_open() end

    input_active = true
    input_prompt = prompt or 'EDIT MOVIE TITLE'
    input_text = initial_text or ''
    input_cursor = #input_text + 1
    input_callback = callback
    input_on_cancel = on_cancel
    input_cursor_blink = true

    if input_blink_timer then input_blink_timer:kill() end
    input_blink_timer = mp.add_periodic_timer(0.5, function()
        input_cursor_blink = not input_cursor_blink
        if ctx_ref.request_tick then ctx_ref.request_tick() end
    end)

    input_key_bindings = {}
    local function in_bind(key, name, fn, flags)
        mp.add_forced_key_binding(key, name, fn, flags)
        table.insert(input_key_bindings, name)
    end

    -- Bind ASCII printable characters 32 to 126
    for b = 32, 126 do
        local c = string.char(b)
        local key = (b == 32) and 'SPACE' or ((b == 35) and 'SHARP' or c)
        in_bind(key, 'in_k_' .. b, function()
            local left = input_text:sub(1, input_cursor - 1)
            local right = input_text:sub(input_cursor)
            input_text = left .. c .. right
            input_cursor = input_cursor + 1
            input_cursor_blink = true
            if ctx_ref.request_tick then ctx_ref.request_tick() end
        end, 'repeatable')
    end

    -- Backspace (UTF-8 codepoint safe)
    in_bind('BS', 'in_bs', function()
        if input_cursor > 1 then
            local u = ctx_ref.utils
            local prev_pos = u and u.utf8_prev_char and u.utf8_prev_char(input_text, input_cursor) or (input_cursor - 1)
            local left = input_text:sub(1, prev_pos - 1)
            local right = input_text:sub(input_cursor)
            input_text = left .. right
            input_cursor = prev_pos
            input_cursor_blink = true
            if ctx_ref.request_tick then ctx_ref.request_tick() end
        end
    end, 'repeatable')

    -- Delete (UTF-8 codepoint safe)
    in_bind('DEL', 'in_del', function()
        if input_cursor <= #input_text then
            local u = ctx_ref.utils
            local next_pos = u and u.utf8_next_char and u.utf8_next_char(input_text, input_cursor) or (input_cursor + 1)
            local left = input_text:sub(1, input_cursor - 1)
            local right = input_text:sub(next_pos)
            input_text = left .. right
            input_cursor_blink = true
            if ctx_ref.request_tick then ctx_ref.request_tick() end
        end
    end, 'repeatable')

    -- Navigation (UTF-8 codepoint safe)
    in_bind('LEFT', 'in_left', function()
        if input_cursor > 1 then
            local u = ctx_ref.utils
            input_cursor = u and u.utf8_prev_char and u.utf8_prev_char(input_text, input_cursor) or (input_cursor - 1)
            input_cursor_blink = true
            if ctx_ref.request_tick then ctx_ref.request_tick() end
        end
    end, 'repeatable')

    in_bind('RIGHT', 'in_right', function()
        if input_cursor <= #input_text then
            local u = ctx_ref.utils
            input_cursor = u and u.utf8_next_char and u.utf8_next_char(input_text, input_cursor) or (input_cursor + 1)
            input_cursor_blink = true
            if ctx_ref.request_tick then ctx_ref.request_tick() end
        end
    end, 'repeatable')

    in_bind('HOME', 'in_home', function()
        input_cursor = 1
        input_cursor_blink = true
        if ctx_ref.request_tick then ctx_ref.request_tick() end
    end)

    in_bind('END', 'in_end', function()
        input_cursor = #input_text + 1
        input_cursor_blink = true
        if ctx_ref.request_tick then ctx_ref.request_tick() end
    end)

    -- Clipboard Paste (Ctrl+v)
    in_bind('Ctrl+v', 'in_paste', function()
        local is_win = ctx_ref.utils and ctx_ref.utils.is_windows
        local cmd
        if is_win then
            cmd = {'powershell', '-NoProfile', '-Command', 'Get-Clipboard'}
        else
            cmd = {'sh', '-c', 'wl-paste 2>/dev/null || xclip -o -selection clipboard 2>/dev/null || pbpaste 2>/dev/null'}
        end
        mp.command_native_async({
            name = 'subprocess',
            args = cmd,
            capture_stdout = true,
        }, function(ok, res)
            if ok and res and res.stdout and res.stdout ~= '' then
                local text = res.stdout:gsub('[\r\n\t]+', ' '):gsub('[%z\1-\8\11\12\14-\31]', ''):gsub('^%s+', ''):gsub('%s+$', '')
                if text ~= '' then
                    local left = input_text:sub(1, input_cursor - 1)
                    local right = input_text:sub(input_cursor)
                    input_text = left .. text .. right
                    input_cursor = input_cursor + #text
                    input_cursor_blink = true
                    if ctx_ref.request_tick then ctx_ref.request_tick() end
                end
            end
        end)
    end)

    -- Cancel
    local function do_cancel()
        local oc = input_on_cancel
        M.input_box_close()
        if oc then oc() end
    end

    -- Click outside modal to close
    in_bind('mbtn_left', 'in_mbtn_click', function()
        local mx, my = ctx_ref.get_virt_mouse_pos()
        local osc_param = ctx_ref.osc_param
        local box_w = math.min(740, math.floor(osc_param.playresx * 0.88))
        local box_h = 162
        local cx = osc_param.playresx / 2
        local cy = osc_param.playresy / 2
        local x0 = math.floor(cx - box_w / 2)
        local y0 = math.floor(cy - box_h / 2)
        if mx < x0 or mx > x0 + box_w or my < y0 or my > y0 + box_h then
            do_cancel()
        end
    end)

    -- Confirm
    local function do_confirm()
        local cb = input_callback
        local val = input_text
        M.input_box_close()
        if cb then cb(val) end
    end
    in_bind('ENTER', 'in_enter', do_confirm)
    in_bind('KP_ENTER', 'in_kp_enter', do_confirm)

    -- Cancel on ESC
    in_bind('ESC', 'in_esc', do_cancel)

    if ctx_ref.request_tick then ctx_ref.request_tick() end
end

-- Render input box modal into ASS
function M.render(ass)
    if not input_active then return end

    local user_opts = ctx_ref.user_opts or {}
    local osc_param = ctx_ref.osc_param or {playresx = 1280, playresy = 720}
    local font = user_opts.font or 'Inter'
    local box_w = math.min(740, math.floor(osc_param.playresx * 0.88))
    local box_h = 162
    local cx = osc_param.playresx / 2
    local cy = osc_param.playresy / 2
    local x0 = math.floor(cx - box_w / 2)
    local y0 = math.floor(cy - box_h / 2)

    -- Full-screen dimmed background scrim
    ass:new_event()
    ass:pos(0, 0)
    ass:an(7)
    ass:append('{\\bord0\\blur0\\1c&H000000&\\1a&H88&}')
    ass:draw_start()
    ass:rect_cw(0, 0, osc_param.playresx, osc_param.playresy)
    ass:draw_stop()

    -- Floating rounded frosted glass modal card
    ass:new_event()
    ass:pos(x0, y0)
    ass:an(7)
    ass:append('{\\bord1.2\\blur0.5\\1c&H161618&\\3c&HFFFFFF&\\3a&HD0&\\1a&H18&}')
    ass:draw_start()
    ass:round_rect_cw(0, 0, box_w, box_h, 16)
    ass:draw_stop()

    -- Modal Header
    ass:new_event()
    ass:pos(x0 + box_w / 2, y0 + 26)
    ass:an(5)
    ass:append(string.format('{\\bord0\\blur0\\1c&HFFFFFF&\\1a&H00&\\fs13\\fn%s\\b700\\fsp2.5\\q2}', font))
    ass:append(input_prompt)

    -- Text Field Inset Box
    local fw = box_w - 44
    local fh = 46
    local fx = x0 + 22
    local fy = y0 + 50

    ass:new_event()
    ass:pos(fx, fy)
    ass:an(7)
    ass:append('{\\bord1\\blur0\\1c&H0A0A0C&\\3c&H3A3A3E&\\1a&H10&}')
    ass:draw_start()
    ass:round_rect_cw(0, 0, fw, fh, 8)
    ass:draw_stop()

    -- Text with Cursor
    local left = input_text:sub(1, input_cursor - 1)
    local right = input_text:sub(input_cursor)
    local cur_sym = input_cursor_blink and '{\\1c&H7EA2D6&\\b700}|{\\1c&HFFFFFF&\\b500}' or '{\\1a&HFF&}|{\\1a&H00&}'

    ass:new_event()
    ass:pos(fx + 14, fy + fh / 2)
    ass:an(4)
    ass:append(string.format('{\\bord0\\blur0\\1c&HFFFFFF&\\1a&H00&\\fs15\\fn%s\\b500\\q2}', font))
    ass:append(left .. cur_sym .. right)

    -- Footer / Help Hint
    ass:new_event()
    ass:pos(x0 + box_w / 2, y0 + 130)
    ass:an(5)
    ass:append(string.format('{\\bord0\\blur0\\1c&H8E8E93&\\1a&H00&\\fs11\\fn%s\\b400\\q2}', font))
    ass:append('[Enter] Save   \xc2\xb7   [Esc] Cancel   \xc2\xb7   [\xe2\x86\x90 / \xe2\x86\x92] Move   \xc2\xb7   [Backspace] Delete')
end

if mp.register_script_message then
    mp.register_script_message('input-confirm', function(val)
        if input_active then
            local cb = input_callback
            local res = (val and val ~= '') and val or input_text
            M.input_box_close()
            if cb then cb(res) end
        end
    end)

    mp.register_script_message('input-cancel', function()
        if input_active then
            local oc = input_on_cancel
            M.input_box_close()
            if oc then oc() end
        end
    end)
end

return M
