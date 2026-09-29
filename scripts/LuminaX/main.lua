-- ============================================================================
-- LuminaX: Apple visionOS OSC & TMDB Pause Screensaver
-- Main Entry Point & Subsystem Coordinator
-- ============================================================================

local script_dir = mp.get_script_directory()
if not script_dir or script_dir == '' then
    local src = debug.getinfo(1).source
    local script_path = src:match('^@?(.*)$')
    script_dir = script_path:match('^(.*)[/\\][^/\\]+$') or '.'
end

package.path = script_dir .. '/?.lua;' .. script_dir .. '/modules/?.lua;' .. package.path

-- Load Subsystems
local utils       = require('modules.utils')
local osc         = require('modules.osc')
local huds        = require('modules.huds')
local tag_editor  = require('modules.tag_editor')
local menu        = require('modules.menu')
local screensaver = require('modules.screensaver')
local subtitle    = require('modules.subtitle')

-- Cross-Module Wireup
local user_opts   = osc.get_user_opts()
local state       = osc.get_state()
local osc_param   = osc.get_osc_param()
local icons       = osc.get_icons()

-- 1. Initialize Tag Editor
tag_editor.init({
    utils             = utils,
    user_opts         = user_opts,
    osc_param         = osc_param,
    get_virt_mouse_pos= osc.get_virt_mouse_pos,
    request_tick      = osc.request_tick,
    on_open           = function()
        if menu.is_active() then menu.menu_close() end
        screensaver.inhibit()
    end,
    on_close          = function()
        if mp.get_property_native('pause') and user_opts.screensaver_enabled then
            screensaver.inhibit()
            mp.add_timeout(tonumber(user_opts.screensaver_delay) or 3, function()
                if not menu.is_active() and not tag_editor.is_active() then
                    screensaver.activate()
                end
            end)
        end
    end,
})

-- 2. Initialize Screensaver
screensaver.init({
    user_opts    = user_opts,
    state        = state,
    hide_osc     = osc.hide_osc,
    show_osc     = osc.show_osc,
    request_tick = osc.request_tick,
    utils        = utils,
})

-- 3. Initialize Subtitle Subsystem
subtitle.init({
    utils        = utils,
    user_opts    = user_opts,
    osc_param    = osc_param,
    request_tick = osc.request_tick,
})

-- 4. Initialize Menu
menu.init({
    subtitle          = subtitle,
    state             = state,
    user_opts         = user_opts,
    osc_param         = osc_param,
    get_track         = osc.get_track,
    get_virt_mouse_pos= osc.get_virt_mouse_pos,
    request_tick      = osc.request_tick,
    tag_editor        = tag_editor,
    utils             = utils,
    get_tmdb_current  = screensaver.get_current,
    inhibit_screensaver = screensaver.inhibit,
    on_open           = function()
        screensaver.inhibit()
    end,
    on_close          = function()
        if mp.get_property_native('pause') and user_opts.screensaver_enabled then
            screensaver.inhibit()
            mp.add_timeout(tonumber(user_opts.screensaver_delay) or 3, function()
                if not menu.is_active() and not tag_editor.is_active() then
                    screensaver.activate()
                end
            end)
        end
    end,
    on_tag_updated    = function()
        screensaver.fetch_data(true)
    end,
})

-- 5. Initialize OSC
osc.init({
    menu        = menu,
    tag_editor  = tag_editor,
    screensaver = screensaver,
    subtitle    = subtitle,
    utils       = utils,
})

-- 6. Initialize HUDs
huds.init({
    icons           = icons,
    get_canvas_size = function() return utils.get_canvas_size(osc_param) end,
    make_pill_ass   = utils.make_pill_ass,
    on_interaction  = function()
        screensaver.hide()
    end,
})

-- 6. Register Script Keybindings & Bindings
mp.add_key_binding(nil, 'menu-playlist', function()
    if menu.is_active() and state.menu_active == 'playlist' then
        menu.menu_close()
    else
        menu.menu_open('playlist')
    end
end)

mp.add_key_binding(nil, 'menu-chapters', function()
    if menu.is_active() and state.menu_active == 'chapters' then
        menu.menu_close()
    else
        menu.menu_open('chapters')
    end
end)

mp.add_key_binding(nil, 'menu-audio', function()
    if menu.is_active() and state.menu_active == 'audio' then
        menu.menu_close()
    else
        menu.menu_open('audio')
    end
end)

mp.add_key_binding(nil, 'menu-sub', function()
    if menu.is_active() and state.menu_active == 'sub' then
        menu.menu_close()
    else
        menu.menu_open('sub')
    end
end)

mp.add_key_binding(nil, 'menu-sub-config', function()
    if menu.is_active() and state.menu_active == 'sub_config' then
        menu.menu_close()
    else
        menu.menu_open('sub_config')
    end
end)

mp.add_key_binding(nil, 'sub-scale-up', function()
    if subtitle and subtitle.add_sub_scale then subtitle.add_sub_scale(0.05) end
end)

mp.add_key_binding(nil, 'sub-scale-down', function()
    if subtitle and subtitle.add_sub_scale then subtitle.add_sub_scale(-0.05) end
end)

mp.add_key_binding(nil, 'sub-scale-reset', function()
    if subtitle and subtitle.reset_sub_scale then subtitle.reset_sub_scale() end
end)

mp.add_key_binding(nil, 'menu-tags', function()
    if menu.is_active() and state.menu_active == 'tags' then
        menu.menu_close()
    else
        menu.menu_open('tags')
    end
end)

mp.add_key_binding('T', 'toggle-tags-menu', function()
    if menu.is_active() and state.menu_active == 'tags' then
        menu.menu_close()
    else
        menu.menu_open('tags')
    end
end)

mp.add_key_binding('Ctrl+t', 'toggle-tags-menu-ctrl', function()
    if menu.is_active() and state.menu_active == 'tags' then
        menu.menu_close()
    else
        menu.menu_open('tags')
    end
end)
