-- ============================================================================
-- LuminaX Sub-module: OSC Controls, Layout Factory & Track Management
-- Handles button layout generation, tracklist synchronization, and OSD message overlays.
-- ============================================================================

local osc_state  = require('modules.osc.osc_state')
local osc_seekbar= require('modules.osc.osc_seekbar')
local msg        = require('mp.msg')
local utils      = require('mp.utils')

local M = {}

local tracks_osc = { video = {}, audio = {}, sub = {} }
local tracks_mpv = { video = {}, audio = {}, sub = {} }

local nicetypes = {
    video = osc_state.texts.video or 'Video',
    audio = osc_state.texts.audio or 'Audio',
    sub   = osc_state.texts.subtitle or 'Subtitle',
}

M.tracks_osc = tracks_osc
M.tracks_mpv = tracks_mpv
M.nicetypes  = nicetypes

-- Add layout to an element
function M.add_layout(name)
    local elements = osc_state.elements
    if elements[name] ~= nil then
        elements[name].layout = {}
        elements[name].layout.layer = 50
        elements[name].layout.alpha = { [1] = 0, [2] = 255, [3] = 255, [4] = 255 }

        if elements[name].type == 'button' then
            elements[name].layout.button = { maxchars = nil }
        elseif elements[name].type == 'slider' then
            elements[name].layout.slider = {
                border = 1,
                gap = 1,
                nibbles_top = true,
                nibbles_bottom = true,
                adjust_tooltip = true,
                tooltip_style = '',
                tooltip_an = 2,
                alpha = { [1] = 0, [2] = 255, [3] = 88, [4] = 255 },
            }
        elseif elements[name].type == 'box' then
            elements[name].layout.box = { radius = 0, hexagon = false }
        end

        return elements[name].layout
    else
        if msg and msg.error then
            msg.error('Can\'t add_layout to element \'' .. tostring(name) .. '\', doesn\'t exist.')
        end
    end
end

-- Tracklist Management
function M.update_tracklist()
    local tracktable = (mp and mp.get_property_native) and mp.get_property_native('track-list', {}) or {}

    for k in pairs(tracks_osc) do tracks_osc[k] = {} end
    for k in pairs(tracks_mpv) do tracks_mpv[k] = {} end

    for n = 1, #tracktable do
        local tr = tracktable[n]
        if tr and tr.type and tr.type ~= 'unknown' then
            local ttype = tr.type
            local mpv_id = tonumber(tr.id)
            if tracks_osc[ttype] then
                table.insert(tracks_osc[ttype], tr)
                if mpv_id and tracks_mpv[ttype] then
                    tracks_mpv[ttype][mpv_id] = tr
                    tracks_mpv[ttype][mpv_id].osc_id = #tracks_osc[ttype]
                end
            end
        end
    end
end

function M.get_tracklist(ttype)
    local texts = osc_state.texts
    local nice = nicetypes[ttype] or ttype
    local res_msg = (texts.available or 'Available ') .. nice .. (texts.track or ' Tracks:')
    local tlist = tracks_osc[ttype] or {}
    if #tlist == 0 then
        res_msg = res_msg .. (texts.none or 'none')
    else
        local cur_id = tonumber(mp.get_property(ttype))
        for n = 1, #tlist do
            local track = tlist[n]
            local lang = track.lang or 'unknown'
            local title = track.title or ''
            local selected = (track.id == cur_id) and '●' or '○'
            res_msg = res_msg .. '\n' .. selected .. ' ' .. n .. ': [' .. lang .. '] ' .. title
        end
    end
    return res_msg
end

function M.set_track(ttype, next_offset)
    local current_track_mpv, current_track_osc
    local prop = mp.get_property(ttype)
    local tlist = tracks_osc[ttype] or {}
    if prop == 'no' or prop == nil then
        current_track_osc = 0
    else
        current_track_mpv = tonumber(prop)
        local item = tracks_mpv[ttype] and tracks_mpv[ttype][current_track_mpv]
        current_track_osc = item and item.osc_id or 0
    end
    local count = #tlist
    local new_track_osc = (current_track_osc + next_offset) % (count + 1)
    local new_track_mpv
    if new_track_osc == 0 then
        new_track_mpv = 'no'
    else
        new_track_mpv = tlist[new_track_osc] and tlist[new_track_osc].id
    end

    if new_track_mpv ~= nil then
        mp.commandv('set', ttype, new_track_mpv)
    end
end

function M.get_track(ttype)
    local track = mp.get_property(ttype)
    if track ~= 'no' and track ~= nil then
        local tr = tracks_mpv[ttype] and tracks_mpv[ttype][tonumber(track)]
        if tr then
            return tr.osc_id
        end
    end
    return 0
end

function M.get_tracks_osc()
    return tracks_osc
end

-- Playlist format string
function M.get_playlist()
    local pos = mp.get_property_number('playlist-pos', 0) + 1
    local count, limlist = osc_seekbar.limited_list('playlist', pos)
    local texts = osc_state.texts
    if not count or count == 0 then
        return texts.nolist or 'Empty playlist.'
    end

    local message = string.format((texts.playlist or 'Playlist') .. ' [%d/%d]:\n', pos or 1, count)
    for _, v in ipairs(limlist or {}) do
        if v then
            local title = v.title
            local _, filename = utils.split_path(v.filename or '')
            if title == nil then
                title = filename or ''
            end
            message = message .. string.format('%s %s\n', (v.current and '●' or '○'), title)
        end
    end
    return message
end

-- Messages
function M.show_message(text, duration, request_tick_fn)
    if duration == nil then
        local dur_prop = tonumber(mp.get_property('options/osd-duration')) or tonumber(mp.get_property('osd-duration')) or 2000
        duration = dur_prop / 1000
    end

    text = string.sub(text, 1, 4000)
    text = string.gsub(text, '\n', '\\N')

    local state = osc_state.state
    state.message_text = text

    if not state.message_hide_timer then
        state.message_hide_timer = mp.add_timeout(0, function()
            if request_tick_fn then request_tick_fn() end
        end)
    end
    state.message_hide_timer:kill()
    state.message_hide_timer.timeout = duration
    state.message_hide_timer:resume()
    if request_tick_fn then request_tick_fn() end
end

function M.render_message(ass)
    local state = osc_state.state
    local osc_param = osc_state.osc_param
    if state.message_hide_timer and state.message_hide_timer:is_enabled() and state.message_text then
        local _, lines = string.gsub(state.message_text, '\\N', '')
        local fontsize = tonumber(mp.get_property('options/osd-font-size')) or tonumber(mp.get_property('osd-font-size')) or 28
        local outline = tonumber(mp.get_property('options/osd-border-size')) or tonumber(mp.get_property('osd-border-size')) or 2
        local unscaled_y = osc_param.unscaled_y > 0 and osc_param.unscaled_y or 720
        local playresy = osc_param.playresy > 0 and osc_param.playresy or 720
        local maxlines = math.ceil(unscaled_y * 0.75 / math.max(1, fontsize))
        local counterscale = playresy / unscaled_y

        fontsize = fontsize * counterscale / math.max(0.65 + math.min(lines / maxlines, 1), 1)
        outline = outline * counterscale / math.max(0.75 + math.min(lines / maxlines, 1) / 2, 1)

        local style = '{\\bord' .. outline .. '\\fs' .. fontsize .. '}'
        ass:new_event()
        ass:append(style .. state.message_text)
    else
        state.message_text = nil
    end
end

return M
