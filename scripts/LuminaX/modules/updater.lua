-- ============================================================================
-- LuminaX Module: Updater
-- In-player GitHub release detection, manifest checking & detached self-update
-- ============================================================================

local mp_utils = require('mp.utils')
local version  = require('version')

local M = {}

local user_opts   = {}
local state       = {}
local huds        = nil
local request_tick= function() end
local request_init= function() end
local is_checking = false
local is_updating = false

local function notify_hud(key, val, icon, val_color, dur)
    if huds and huds.show_pill then
        huds.show_pill({
            icon      = icon or '✨',
            key       = key,
            val       = val,
            val_color = val_color or '60E0FF',
        })
    else
        mp.osd_message(string.format('%s %s: %s', icon or '', key, val), dur or 4)
    end
end

local function get_cache_check_file()
    local p = mp.command_native({'expand-path', '~~cache/'})
    if not p or p == '' or p == '~~cache/' then
        p = os.getenv('TMPDIR') or os.getenv('TEMP') or '/tmp'
    end
    return p:gsub('[/\\]+$', '') .. '/luminax_update_check.json'
end

local function safe_async_cmd(cmd_tbl, callback)
    if not (mp and mp.command_native_async) then
        if callback then callback(false, nil) end
        return nil
    end
    if cmd_tbl.playback_only == nil then
        cmd_tbl.playback_only = false
    end
    return mp.command_native_async(cmd_tbl, function(ok, res, err)
        if callback then callback(ok, res, err) end
    end)
end

function M.init(ctx)
    user_opts    = ctx.user_opts or {}
    state        = ctx.state or {}
    huds         = ctx.huds or nil
    request_tick = ctx.request_tick or function() end
    request_init = ctx.request_init or function() end

    -- Register script bindings
    local function handle_user_update_trigger()
        if state.update_available then
            M.perform_update()
        else
            M.check_for_updates(function(avail, new_ver)
                if avail then
                    notify_hud('LUMINA UPDATE', 'v' .. new_ver .. ' Available (Click bar icon or press U)', '✨', '60E0FF', 5)
                else
                    notify_hud('LUMINA UPDATE', 'Up to date (v' .. version.VERSION .. ')', '✓', '72D572', 3)
                end
            end, true)
        end
    end

    mp.add_key_binding('U', 'check-update', handle_user_update_trigger)
    mp.add_key_binding(nil, 'perform-update', function()
        M.perform_update()
    end)

    -- Background throttled check on player startup (after 15 seconds)
    -- SILENT when player is already up-to-date; only notifies when an update is available!
    if user_opts.check_updates ~= false and mp.add_timeout then
        mp.add_timeout(15, function()
            M.check_for_updates(function(avail, new_ver)
                if avail then
                    notify_hud('LUMINA UPDATE', 'v' .. new_ver .. ' Available (Click bar icon or press U)', '✨', '60E0FF', 5)
                end
                -- When avail is false: stay completely silent in background check
            end, false)
        end)
    end
end

function M.get_update_status()
    return state.update_available
end

function M.check_for_updates(callback, force)
    if is_checking then
        if callback then callback(state.update_available ~= nil, state.update_available and state.update_available.version) end
        return
    end

    local check_file = get_cache_check_file()
    local now = os.time()

    if not force then
        local f = io.open(check_file, 'r')
        if f then
            local c = f:read('*a')
            f:close()
            local d = mp_utils.parse_json(c)
            -- Check once every 3 days (259200 seconds) by default
            local interval_days = tonumber(user_opts.check_update_interval_days) or 3
            local interval_sec  = interval_days * 86400
            if d and d.last_checked and (now - d.last_checked < interval_sec) then
                if d.update_available then
                    state.update_available = d.update_available
                    if request_init then request_init() end
                    request_tick()
                end
                if callback then
                    callback(d.update_available ~= nil, d.update_available and d.update_available.version)
                end
                return
            end
        end
    end

    is_checking = true
    safe_async_cmd({
        name = 'subprocess',
        args = {
            'curl', '-s', '-4', '--connect-timeout', '4', '--max-time', '8',
            '-H', 'User-Agent: LuminaX-InPlayer-Checker',
            version.GITHUB_API_URL
        },
        capture_stdout = true,
    }, function(ok, res)
        is_checking = false
        if not ok or not res or not res.stdout or res.stdout == '' then
            if callback then callback(false, nil) end
            return
        end

        local data = mp_utils.parse_json(res.stdout)
        if not data or not data.tag_name then
            if callback then callback(false, nil) end
            return
        end

        local latest_tag = data.tag_name:gsub('^[vV]', '')
        local is_newer = (version.compare(latest_tag, version.VERSION) > 0)

        local update_info = nil
        if is_newer then
            update_info = {
                version = latest_tag,
                url     = data.html_url or '',
                name    = data.name or ('Release v' .. latest_tag),
            }
            state.update_available = update_info
            if request_init then request_init() end
            request_tick()
        else
            if state.update_available ~= nil then
                state.update_available = nil
                if request_init then request_init() end
                request_tick()
            end
        end

        -- Persist check state
        pcall(function()
            local out_f = io.open(check_file, 'w')
            if out_f then
                out_f:write(mp_utils.format_json({
                    last_checked     = now,
                    latest_tag       = latest_tag,
                    update_available = update_info,
                }))
                out_f:close()
            end
        end)

        if callback then callback(is_newer, latest_tag, update_info) end
    end)
end

function M.perform_update()
    if is_updating then
        notify_hud('LUMINA UPDATE', 'Update already in progress...', '⏳', 'FFA0DC', 3)
        return
    end

    is_updating = true
    notify_hud('UPDATING LUMINA', 'Downloading & applying update in background...', '🚀', 'FFD070', 6)

    local is_win = (package.config:sub(1, 1) == '\\')
    local config_dir = mp.command_native({'expand-path', '~~/'})

    local updater_cmd = nil
    if is_win then
        local ps_script = config_dir:gsub('[/\\]+$', '') .. '\\tools\\update.ps1'
        updater_cmd = {
            name = 'subprocess',
            playback_only = false,
            args = {
                'powershell.exe', '-NoProfile', '-ExecutionPolicy', 'Bypass',
                '-File', ps_script,
                '-TargetDir', config_dir,
                '-NonInteractive'
            },
        }
    else
        local sh_script = config_dir:gsub('[/\\]+$', '') .. '/tools/update.sh'
        updater_cmd = {
            name = 'subprocess',
            playback_only = false,
            args = {'bash', sh_script, config_dir, '--non-interactive'},
        }
    end

    safe_async_cmd(updater_cmd, function(ok, res)
        is_updating = false
        if ok and res and (res.status == 0 or res.error_string == nil) then
            state.update_available = nil
            if request_init then request_init() end
            request_tick()
            notify_hud('UPDATE COMPLETE', 'LuminaX updated! Restart mpv to apply.', '🎉', '72D572', 7)
        else
            notify_hud('UPDATE ISSUE', 'Run update.sh or update.bat manually', '⚠️', '6B6BFF', 6)
        end
    end)
end

return M
