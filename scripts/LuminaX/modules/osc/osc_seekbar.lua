-- ============================================================================
-- LuminaX Sub-module: OSC Seekbar & Chapter Intelligence
-- Handles seekbar slider math, chapter markers, zone tinting and thumbfast integration.
-- ============================================================================

local osc_state = require('modules.osc.osc_state')
local utils     = require('mp.utils')

local M = {}

-- Translate value into element coordinates
function M.get_slider_ele_pos_for(element, val)
    local ele_pos = osc_state.scale_value(
        element.slider.min.value, element.slider.max.value,
        element.slider.min.ele_pos, element.slider.max.ele_pos,
        val)

    return osc_state.limit_range(
        element.slider.min.ele_pos, element.slider.max.ele_pos,
        ele_pos)
end

-- Translates global (mouse) coordinates to value
function M.get_slider_value_at(element, glob_pos)
    local val = osc_state.scale_value(
        element.slider.min.glob_pos, element.slider.max.glob_pos,
        element.slider.min.value, element.slider.max.value,
        glob_pos)

    return osc_state.limit_range(
        element.slider.min.value, element.slider.max.value,
        val)
end

-- Get value at current mouse position
function M.get_slider_value(element)
    return M.get_slider_value_at(element, osc_state.get_virt_mouse_pos())
end

-- Returns nil or a chapter element from the native property chapter-list
function M.get_chapter(possec, chapter_list)
    possec = tonumber(possec)
    if not possec then return nil end
    local cl = chapter_list or osc_state.state.chapter_list or {}

    for n = #cl, 1, -1 do
        local ct = cl[n] and tonumber(cl[n].time)
        if ct and possec >= ct then
            return cl[n]
        end
    end
    return nil
end

-- Limited list helper for playlist / chapters message display
function M.limited_list(prop, pos)
    local count = mp.get_property_number(prop .. '/count')
    if not count or count == 0 then
        return nil
    end

    local cut = 4
    local start = math.max(1, pos - cut)
    local stop = math.min(count, pos + cut)

    local reslist = {}
    for i = start, stop do
        local item = mp.get_property_native(string.format('%s/%d', prop, i - 1))
        if item then
            item.current = (i == pos)
            table.insert(reslist, item)
        end
    end
    return count, reslist
end

function M.get_chapterlist(ctx_ref)
    local pos = mp.get_property_number('chapter', 0) + 1
    local count, limlist = M.limited_list('chapter-list', pos)
    local texts = osc_state.texts
    if not count or count == 0 then
        return texts.nochapter or 'No chapters.'
    end

    local u = ctx_ref and ctx_ref.utils
    local message = string.format((texts.chapter or 'Chapter') .. ' [%d/%d]:\n', pos or 1, count)
    for i, v in ipairs(limlist or {}) do
        if v then
            local time = (u and u.format_time) and u.format_time(v.time) or '00:00'
            local title = v.title
            if title == nil then
                title = string.format((texts.chapter or 'Chapter') .. ' %02d', i)
            end
            if i == pos then
                message = message .. string.format('(%s) %s\n', time, title)
            else
                message = message .. string.format(' %s %s\n', time, title)
            end
        end
    end
    return message
end

-- Seekbar chapter zone tinting: detects intro/outro ranges for styling
function M.get_chapter_zones(duration, chapter_list)
    local zones = {}
    if not duration or duration <= 0 or not chapter_list then return zones end

    for i, ch in ipairs(chapter_list) do
        local title = (ch.title or ''):lower()
        local start_t = ch.time or 0
        local next_ch = chapter_list[i + 1]
        local end_t = next_ch and next_ch.time or duration

        if title:match('intro') or title:match('opening') or title:match('^op$') then
            table.insert(zones, { type = 'intro', start_t = start_t, end_t = end_t })
        elseif title:match('outro') or title:match('ending') or title:match('^ed$') or title:match('credits') then
            table.insert(zones, { type = 'outro', start_t = start_t, end_t = end_t })
        end
    end
    return zones
end

return M
