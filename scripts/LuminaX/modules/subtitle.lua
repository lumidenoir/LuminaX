-- ============================================================================
-- LuminaX Module: Subtitle
-- Apple visionOS Rounded Rectangle Subtitle Renderer & Live Configuration System
-- ============================================================================

local ok_ass, assdraw = pcall(require, 'mp.assdraw')
local ok_mp_utils, mp_utils = pcall(require, 'mp.utils')
if not ok_mp_utils or not mp_utils then mp_utils = {} end

local M = {}

local ctx_ref = {}
local overlay = nil
local current_sub_text = ''
local live_preview_active = false
local config_file_path = nil

-- Default Subtitle Configuration
local default_config = {
    preset          = 'visionos_pill', -- 'visionos_pill', 'netflix_modern', 'cinema_yellow', 'cyber_neon', 'anime_outline', 'minimal_clean', 'high_contrast', 'custom'
    mode            = 'rounded_rect',   -- 'rounded_rect' (Lua overlay) or 'native'
    -- Font & Typography
    font            = 'Inter',
    font_size       = 34,
    font_bold       = false,
    text_color      = '#FFFFFF',
    text_alpha      = '00',            -- ASS alpha hex ('00' = 100% opaque, 'FF' = transparent)
    -- Border & Outline
    border_color    = '#101014',
    border_alpha    = '00',
    border_size     = 0.0,
    -- Shadow
    shadow_color    = '#000000',
    shadow_alpha    = 'B0',
    shadow_offset   = 0.0,
    -- Positioning & Spacing
    margin_y        = 28,
    line_spacing    = 6,
    letter_spacing  = 0.2,
    -- Rounded Rectangle Box (Overlay Mode)
    box_enabled     = true,
    box_radius      = 14,              -- Corner radius in px (-1 = full pill)
    box_color       = '#121216',        -- Background fill hex (#RRGGBB)
    box_alpha       = '36',            -- ASS alpha hex ('36' = ~79% opacity)
    box_pad_x       = 22,              -- Horizontal padding around text
    box_pad_y       = 10,              -- Vertical padding around text
    box_rim_enabled = true,            -- Subtle glassmorphic hairline rim highlight
    box_rim_color   = '#FFFFFF',
    box_rim_alpha   = 'D8',            -- ~16% subtle white rim
    box_rim_size    = 1.0,
    box_per_line    = false,           -- false: unified pill; true: pill per line
}

local config = {}
for k, v in pairs(default_config) do config[k] = v end

-- Prebuilt Style Presets
local PRESETS = {
    visionos_pill = {
        name            = 'visionOS Glass Pill',
        description     = 'Translucent frosted glass pill, crisp white Inter font, subtle light rim',
        mode            = 'rounded_rect',
        box_enabled     = true,
        box_radius      = 14,
        box_color       = '#121216',
        box_alpha       = '36',
        box_rim_enabled = true,
        box_rim_color   = '#FFFFFF',
        box_rim_alpha   = 'D8',
        box_rim_size    = 1.0,
        box_pad_x       = 22,
        box_pad_y       = 10,
        text_color      = '#FFFFFF',
        text_alpha      = '00',
        font            = 'Inter',
        font_size       = 34,
        font_bold       = false,
        border_size     = 0.0,
        shadow_offset   = 0.0,
        margin_y        = 28,
        line_spacing    = 6,
    },
    netflix_modern = {
        name            = 'Netflix Modern Box',
        description     = 'Sleek rounded dark box, pure white text, compact balanced padding',
        mode            = 'rounded_rect',
        box_enabled     = true,
        box_radius      = 8,
        box_color       = '#000000',
        box_alpha       = '44',
        box_rim_enabled = false,
        box_pad_x       = 18,
        box_pad_y       = 8,
        text_color      = '#FFFFFF',
        text_alpha      = '00',
        font            = 'Inter',
        font_size       = 32,
        font_bold       = false,
        border_size     = 0.0,
        shadow_offset   = 0.0,
        margin_y        = 26,
        line_spacing    = 4,
    },
    cinema_yellow = {
        name            = 'Cinema Warm Yellow',
        description     = 'Warm golden yellow text, soft dark charcoal pill, cinematic depth',
        mode            = 'rounded_rect',
        box_enabled     = true,
        box_radius      = 10,
        box_color       = '#0D0E12',
        box_alpha       = '28',
        box_rim_enabled = false,
        box_pad_x       = 20,
        box_pad_y       = 9,
        text_color      = '#FFE066',
        text_alpha      = '00',
        font            = 'Inter',
        font_size       = 34,
        font_bold       = false,
        border_size     = 0.5,
        border_color    = '#000000',
        border_alpha    = '60',
        shadow_offset   = 1.0,
        shadow_color    = '#000000',
        shadow_alpha    = 'A0',
        margin_y        = 30,
        line_spacing    = 6,
    },
    cyber_neon = {
        name            = 'Cyberpunk Cyan Neon',
        description     = 'Electric cyan font, dark indigo glass pill with cyan-tinted hairline glow',
        mode            = 'rounded_rect',
        box_enabled     = true,
        box_radius      = 16,
        box_color       = '#080C18',
        box_alpha       = '30',
        box_rim_enabled = true,
        box_rim_color   = '#00F0FF',
        box_rim_alpha   = 'B0',
        box_rim_size    = 1.2,
        box_pad_x       = 24,
        box_pad_y       = 11,
        text_color      = '#00F0FF',
        text_alpha      = '00',
        font            = 'Inter',
        font_size       = 34,
        font_bold       = true,
        border_size     = 0.0,
        shadow_offset   = 0.0,
        margin_y        = 30,
        line_spacing    = 6,
    },
    anime_outline = {
        name            = 'Anime Crisp Outline',
        description     = 'Pure white text, bold 3.2px pitch-black halo outline, maximum contrast',
        mode            = 'native',
        box_enabled     = false,
        text_color      = '#FFFFFF',
        text_alpha      = '00',
        border_color    = '#000000',
        border_alpha    = '00',
        border_size     = 3.2,
        shadow_offset   = 1.5,
        shadow_color    = '#000000',
        shadow_alpha    = '80',
        font            = 'Inter',
        font_size       = 36,
        font_bold       = true,
        margin_y        = 26,
        line_spacing    = 4,
    },
    minimal_clean = {
        name            = 'Minimalist Clean',
        description     = 'Off-white font, subtle 1.2px drop shadow, completely borderless & boxless',
        mode            = 'native',
        box_enabled     = false,
        text_color      = '#F2F2F5',
        text_alpha      = '00',
        border_color    = '#101014',
        border_alpha    = 'A0',
        border_size     = 1.0,
        shadow_offset   = 1.2,
        shadow_color    = '#000000',
        shadow_alpha    = '80',
        font            = 'Inter',
        font_size       = 32,
        font_bold       = false,
        margin_y        = 24,
        line_spacing    = 4,
    },
    high_contrast = {
        name            = 'High Contrast Studio',
        description     = 'Bold yellow text on solid 96% black 12px pill, maximum readability',
        mode            = 'rounded_rect',
        box_enabled     = true,
        box_radius      = 12,
        box_color       = '#000000',
        box_alpha       = '0A',
        box_rim_enabled = true,
        box_rim_color   = '#FFDE03',
        box_rim_alpha   = 'C0',
        box_rim_size    = 1.0,
        box_pad_x       = 22,
        box_pad_y       = 10,
        text_color      = '#FFDE03',
        text_alpha      = '00',
        font            = 'Inter',
        font_size       = 36,
        font_bold       = true,
        border_size     = 0.0,
        shadow_offset   = 0.0,
        margin_y        = 30,
        line_spacing    = 6,
    },
}

-- Hex to ASS BGR and Alpha Conversion Helper
local function hex_to_ass(hex_str)
    if not hex_str or type(hex_str) ~= 'string' then return '&HFFFFFF&', '00' end
    local h = hex_str:gsub('#', ''):upper()
    if #h == 6 then
        local r, g, b = h:sub(1, 2), h:sub(3, 4), h:sub(5, 6)
        return '&H' .. b .. g .. r .. '&', '00'
    elseif #h == 8 then
        local a, r, g, b = h:sub(1, 2), h:sub(3, 4), h:sub(5, 6), h:sub(7, 8)
        return '&H' .. b .. g .. r .. '&', a
    end
    return '&HFFFFFF&', '00'
end

-- Strip ASS override tags and basic HTML tags for accurate width estimation
local function strip_tags(str)
    if not str then return '' end
    local clean = str:gsub('\\N', '\n')
    clean = clean:gsub('{[^}]-}', '')
    clean = clean:gsub('<[^>]->', '')
    return clean
end

-- Font Metric Character Width Estimation
local function estimate_char_width(byte, next_byte, fs, is_bold)
    local bold_factor = is_bold and 1.06 or 1.0
    -- Multi-byte UTF-8 character (e.g. CJK, emoji)
    if byte >= 0xC0 then
        return fs * 0.95 * bold_factor
    end
    local ch = string.char(byte)
    if ch:match('[WwMm@]') then
        return fs * 0.72 * bold_factor
    elseif ch:match('[A-Z]') then
        return fs * 0.60 * bold_factor
    elseif ch:match('[a-z0-9]') then
        if ch:match('[iljtfr]') then
            return fs * 0.32 * bold_factor
        end
        return fs * 0.50 * bold_factor
    elseif ch:match('[%s]') then
        return fs * 0.28
    elseif ch:match('[,%.!;:|\'"%-_]') then
        return fs * 0.26
    else
        return fs * 0.45 * bold_factor
    end
end

local function estimate_text_width(text, fs, is_bold)
    if not text or text == '' then return 0 end
    local w = 0
    local len = #text
    local i = 1
    while i <= len do
        local b = text:byte(i)
        local step = 1
        if b >= 0xF0 then step = 4
        elseif b >= 0xE0 then step = 3
        elseif b >= 0xC0 then step = 2
        end
        w = w + estimate_char_width(b, nil, fs, is_bold)
        i = i + step
    end
    return math.ceil(w)
end

-- Load and Save Configuration Persistence
local function get_config_path()
    if config_file_path then return config_file_path end
    if mp and mp.command_native then
        local p = mp.command_native({'expand-path', '~~/script-opts/lumina_subtitle.json'})
        if p and p ~= '' then config_file_path = p; return p end
    end
    config_file_path = (os.getenv('HOME') or '.') .. '/.config/mpv/script-opts/lumina_subtitle.json'
    return config_file_path
end

local function load_saved_config()
    local path = get_config_path()
    local f = io.open(path, 'r')
    if not f then return end
    local content = f:read('*all')
    f:close()
    if not content or content == '' then return end
    if mp_utils and mp_utils.parse_json then
        local ok, data = pcall(mp_utils.parse_json, content)
        if ok and type(data) == 'table' then
            for k, v in pairs(data) do
                config[k] = v
            end
        end
    end
end

local function save_config()
    local path = get_config_path()
    local dir = path:match('^(.*)[/\\][^/\\]+$')
    if dir and ctx_ref.utils and ctx_ref.utils.mkdir_p then
        ctx_ref.utils.mkdir_p(dir)
    end
    local f = io.open(path, 'w')
    if not f then return end
    if mp_utils and mp_utils.format_json then
        local ok, str = pcall(mp_utils.format_json, config)
        if ok and str then
            f:write(str)
        end
    end
    f:close()
end

-- Apply Configuration: sync native properties or activate overlay
function M.apply_config(skip_save)
    if not skip_save then save_config() end

    local is_overlay = (config.mode == 'rounded_rect' and config.box_enabled)
    local sid = mp.get_property('sid')
    local sub_off = (sid == 'no' or sid == nil)

    if is_overlay then
        -- In rounded rect mode, hide native subtitles so only the clean pill is drawn
        if not sub_off then
            mp.set_property_bool('sub-visibility', false)
        end
        M.update_overlay()
    else
        -- Native mode: restore sub-visibility and sync native properties
        if not sub_off then
            mp.set_property_bool('sub-visibility', true)
        end
        if overlay then overlay:remove() end

        -- Push styling to mpv native properties
        pcall(mp.set_property, 'sub-font', config.font)
        pcall(mp.set_property, 'sub-font-size', tostring(config.font_size))
        pcall(mp.set_property, 'sub-bold', config.font_bold and 'yes' or 'no')
        pcall(mp.set_property, 'sub-color', config.text_color)
        pcall(mp.set_property, 'sub-border-color', config.border_color)
        pcall(mp.set_property, 'sub-border-size', tostring(config.border_size))
        pcall(mp.set_property, 'sub-shadow-offset', tostring(config.shadow_offset))
        pcall(mp.set_property, 'sub-shadow-color', config.shadow_color .. config.shadow_alpha)
        pcall(mp.set_property, 'sub-margin-y', tostring(config.margin_y))
    end

    if ctx_ref.request_tick then ctx_ref.request_tick() end
end

-- Apply a prebuilt style preset
function M.apply_preset(preset_key)
    local p = PRESETS[preset_key]
    if not p then return end
    config.preset = preset_key
    for k, v in pairs(p) do
        if k ~= 'name' and k ~= 'description' then
            config[k] = v
        end
    end
    M.apply_config()
    mp.osd_message('✓ Subtitle Preset: ' .. p.name, 2.5)
end

-- Render Rounded Rectangle Subtitle Overlay
function M.update_overlay()
    if not overlay then return end

    local is_overlay = (config.mode == 'rounded_rect' and config.box_enabled)
    if not is_overlay then
        overlay:remove()
        return
    end

    local sid = mp.get_property('sid')
    local sub_off = (sid == 'no' or sid == nil)

    local text_to_render = current_sub_text
    if live_preview_active and (text_to_render == '' or sub_off) then
        text_to_render = 'Sample Subtitle  •  Apple visionOS Pill Style'
    end

    if (text_to_render == '' or sub_off) and not live_preview_active then
        overlay:remove()
        return
    end

    local w, h = 1280, 720
    if ctx_ref.utils and ctx_ref.utils.get_canvas_size then
        w, h = ctx_ref.utils.get_canvas_size(ctx_ref.osc_param)
    else
        local ow, oh = mp.get_osd_size()
        w = ow or 1280; h = oh or 720
    end

    -- Process subtitle text lines
    local raw_lines = {}
    local norm_text = text_to_render:gsub('\\N', '\n'):gsub('\r\n', '\n'):gsub('\r', '\n')
    for line in norm_text:gmatch('[^\n]+') do
        local trimmed = line:gsub('^%s+', ''):gsub('%s+$', '')
        if #trimmed > 0 then
            table.insert(raw_lines, trimmed)
        end
    end

    if #raw_lines == 0 then
        overlay:remove()
        return
    end

    local fs        = config.font_size or 34
    local is_bold   = config.font_bold or false
    local line_h    = math.ceil(fs * 1.28 + (config.line_spacing or 6))
    local pad_x     = config.box_pad_x or 22
    local pad_y     = config.box_pad_y or 10

    local line_widths = {}
    local max_lw = 0
    for _, l in ipairs(raw_lines) do
        local clean_l = strip_tags(l)
        local lw = estimate_text_width(clean_l, fs, is_bold)
        table.insert(line_widths, lw)
        if lw > max_lw then max_lw = lw end
    end

    local total_lines = #raw_lines
    local ass = assdraw.ass_new()

    -- Color conversions
    local box_bgr, _        = hex_to_ass(config.box_color)
    local box_a             = config.box_alpha or '36'
    local rim_bgr, _        = hex_to_ass(config.box_rim_color or '#FFFFFF')
    local rim_a             = config.box_rim_alpha or 'D8'
    local rim_w             = config.box_rim_enabled and (config.box_rim_size or 1.0) or 0

    local txt_bgr, _        = hex_to_ass(config.text_color)
    local txt_a             = config.text_alpha or '00'
    local bord_bgr, _       = hex_to_ass(config.border_color)
    local bord_a            = config.border_alpha or '00'
    local bord_w            = config.border_size or 0
    local shad_bgr, _       = hex_to_ass(config.shadow_color)
    local shad_a            = config.shadow_alpha or 'B0'
    local shad_off          = config.shadow_offset or 0

    local cx                = math.floor(w / 2)
    local margin_y          = config.margin_y or 28

    if config.box_per_line and total_lines > 1 then
        -- Multi-pill mode: individual rounded pill per line
        local total_h = total_lines * line_h + (total_lines - 1) * 6
        local start_y = h - margin_y - total_h
        for i, line in ipairs(raw_lines) do
            local lw   = line_widths[i] or max_lw
            local pw   = lw + pad_x * 2
            local ph   = line_h + pad_y
            local r    = (config.box_radius == -1) and math.floor(ph / 2) or math.min(config.box_radius or 14, math.floor(ph / 2))
            local ly0  = start_y + (i - 1) * (ph + 6)
            local ly1  = ly0 + ph
            local lx0  = cx - math.floor(pw / 2)
            local lx1  = cx + math.floor(pw / 2)

            -- 1. Draw Pill Box
            ass:new_event()
            ass:pos(0, 0)
            ass:an(7)
            ass:append(string.format('{\\blur0\\bord%s\\1c%s\\1a&H%s&\\3c%s\\3a&H%s&}',
                tostring(rim_w), box_bgr, box_a, rim_bgr, rim_a))
            ass:draw_start()
            ass:round_rect_cw(lx0, ly0, lx1, ly1, r)
            ass:draw_stop()

            -- 2. Draw Text Line
            local text_cy = ly0 + math.floor(ph / 2)
            ass:new_event()
            ass:pos(cx, text_cy)
            ass:an(5)
            ass:append(string.format('{\\fn%s\\fs%d%s\\1c%s\\1a&H%s&\\bord%s\\3c%s\\3a&H%s&\\shad%s\\4c%s\\4a&H%s&\\q2}',
                config.font or 'Inter', fs, is_bold and '\\b700' or '\\b400',
                txt_bgr, txt_a, tostring(bord_w), bord_bgr, bord_a, tostring(shad_off), shad_bgr, shad_a))
            ass:append(line)
        end
    else
        -- Unified pill mode (Apple visionOS standard)
        local pill_w = max_lw + pad_x * 2
        local pill_h = (total_lines * line_h) + pad_y * 2
        local r      = (config.box_radius == -1) and math.floor(pill_h / 2) or math.min(config.box_radius or 14, math.floor(pill_h / 2))

        local y1     = h - margin_y
        local y0     = y1 - pill_h
        local x0     = cx - math.floor(pill_w / 2)
        local x1     = cx + math.floor(pill_w / 2)

        -- 1. Draw Background Rounded Rectangle
        ass:new_event()
        ass:pos(0, 0)
        ass:an(7)
        ass:append(string.format('{\\blur0\\bord%s\\1c%s\\1a&H%s&\\3c%s\\3a&H%s&}',
            tostring(rim_w), box_bgr, box_a, rim_bgr, rim_a))
        ass:draw_start()
        ass:round_rect_cw(x0, y0, x1, y1, r)
        ass:draw_stop()

        -- 2. Draw Each Line of Text
        for i, line in ipairs(raw_lines) do
            local text_cy = y0 + pad_y + math.floor((i - 0.5) * line_h)
            ass:new_event()
            ass:pos(cx, text_cy)
            ass:an(5)
            ass:append(string.format('{\\fn%s\\fs%d%s\\1c%s\\1a&H%s&\\bord%s\\3c%s\\3a&H%s&\\shad%s\\4c%s\\4a&H%s&\\q2}',
                config.font or 'Inter', fs, is_bold and '\\b700' or '\\b400',
                txt_bgr, txt_a, tostring(bord_w), bord_bgr, bord_a, tostring(shad_off), shad_bgr, shad_a))
            ass:append(line)
        end
    end

    overlay.res_x = w
    overlay.res_y = h
    overlay.data  = ass.text
    overlay:update()
end

-- Module Initialization
function M.init(ctx)
    ctx_ref = ctx or {}
    overlay = mp.create_osd_overlay('ass-events')

    load_saved_config()

    -- Observe subtitle text changes
    mp.observe_property('sub-text', 'string', function(_, text)
        current_sub_text = text or ''
        M.update_overlay()
    end)

    -- Observe subtitle track changes
    mp.observe_property('sid', nil, function()
        M.apply_config(true)
    end)

    -- Observe canvas / window geometry changes
    mp.observe_property('osd-dimensions', nil, function()
        M.update_overlay()
    end)

    M.apply_config(true)
end

-- Get Current Configuration Copy
function M.get_config()
    return config
end

-- Set Live Preview Mode (when menu is active to preview style tweaks)
function M.set_live_preview(active)
    live_preview_active = active
    M.update_overlay()
end

-- ────────────────────────────────────────────────────────────────────────────
-- Subtitle Configuration Menu Data & Generators
-- ────────────────────────────────────────────────────────────────────────────

function M.get_menu_title(menu_type)
    local titles = {
        sub_config  = 'SUBTITLE CONFIGURATION',
        sub_presets = 'SUBTITLE STYLE PRESETS',
        sub_box     = 'ROUNDED RECTANGLE STYLE',
        sub_text    = 'TEXT COLOR & TYPOGRAPHY',
        sub_border  = 'BORDER & SHADOW STYLING',
        sub_layout  = 'POSITION & SPACING',
    }
    return titles[menu_type] or 'SUBTITLE SETTINGS'
end

function M.get_menu_items(menu_type)
    local items = {}

    if menu_type == 'sub_config' then
        local p_name = PRESETS[config.preset] and PRESETS[config.preset].name or 'Custom'
        local box_status = (config.mode == 'rounded_rect' and config.box_enabled)
            and ('Pill Enabled (' .. (config.box_radius == -1 and 'Full' or (config.box_radius .. 'px')) .. ')')
            or 'Disabled (Native)'

        items[#items + 1] = {
            label = '✦  Style Presets  ▸',
            sublabel = 'Active: ' .. p_name .. ' • Press Enter to select presets',
            action = 'nav_menu',
            target = 'sub_presets',
            index = #items + 1
        }
        items[#items + 1] = {
            label = '▢  Rounded Rectangle Style  ▸',
            sublabel = box_status .. ' • Corner radius, opacity, padding & glass rim',
            action = 'nav_menu',
            target = 'sub_box',
            index = #items + 1
        }
        items[#items + 1] = {
            label = '🎨  Text Color & Typography  ▸',
            sublabel = string.format('%s  •  %dpt  •  %s', config.font, config.font_size, config.text_color),
            action = 'nav_menu',
            target = 'sub_text',
            index = #items + 1
        }
        items[#items + 1] = {
            label = '🔲  Border & Shadow  ▸',
            sublabel = string.format('Border: %.1fpx  •  Shadow: %.1fpx', config.border_size, config.shadow_offset),
            action = 'nav_menu',
            target = 'sub_border',
            index = #items + 1
        }
        items[#items + 1] = {
            label = '📐  Position & Line Spacing  ▸',
            sublabel = string.format('Bottom Margin: %dpx  •  Spacing: %+dpx', config.margin_y, config.line_spacing),
            action = 'nav_menu',
            target = 'sub_layout',
            index = #items + 1
        }
        items[#items + 1] = {
            label = config.mode == 'rounded_rect' and '👁  Switch Mode: Native MPV Style' or '👁  Switch Mode: visionOS Rounded Pill',
            sublabel = config.mode == 'rounded_rect' and 'Toggle to native libass subtitle rendering' or 'Toggle to Apple-grade rounded glass overlay',
            action = 'toggle_mode',
            current = (config.mode == 'rounded_rect'),
            index = #items + 1
        }
        items[#items + 1] = {
            label = '↺  Reset to Default (visionOS Pill)',
            sublabel = 'Restores default Apple visionOS frosted pill styling',
            action = 'reset_defaults',
            index = #items + 1
        }
        items[#items + 1] = {
            label = '⬅  Back to Subtitle Tracks',
            sublabel = 'Select active audio / subtitle language tracks',
            action = 'nav_menu',
            target = 'sub',
            index = #items + 1
        }

    elseif menu_type == 'sub_presets' then
        local order = {'visionos_pill', 'netflix_modern', 'cinema_yellow', 'cyber_neon', 'anime_outline', 'minimal_clean', 'high_contrast'}
        for _, key in ipairs(order) do
            local p = PRESETS[key]
            items[#items + 1] = {
                label = p.name,
                sublabel = p.description,
                action = 'set_preset',
                preset_key = key,
                current = (config.preset == key),
                index = #items + 1
            }
        end
        items[#items + 1] = {
            label = '⬅  Back to Subtitle Settings',
            action = 'nav_menu',
            target = 'sub_config',
            index = #items + 1
        }

    elseif menu_type == 'sub_box' then
        items[#items + 1] = {
            label = config.box_enabled and 'Box Mode: [ON] Rounded Rectangle' or 'Box Mode: [OFF] Transparent Background',
            sublabel = 'Enable/disable drawing rounded background pill behind subtitles',
            action = 'toggle_box_enabled',
            current = config.box_enabled,
            index = #items + 1
        }
        local radii = {
            {label = 'Full Pill (Smooth Capsule)', val = -1, sub = 'Fully rounded capsule ends'},
            {label = '20px Corner Radius', val = 20, sub = 'Extra soft modern rounded corners'},
            {label = '14px Corner Radius (Standard)', val = 14, sub = 'Apple visionOS standard curvature'},
            {label = '8px Corner Radius', val = 8, sub = 'Subtle modern TV rounded box'},
            {label = '4px Corner Radius', val = 4, sub = 'Slightly rounded compact box'},
        }
        for _, r in ipairs(radii) do
            items[#items + 1] = {
                label = 'Curvature: ' .. r.label,
                sublabel = r.sub,
                action = 'set_box_radius',
                val = r.val,
                current = (config.box_radius == r.val),
                index = #items + 1
            }
        end
        local opacities = {
            {label = '95% Solid Dark', val = '0D'},
            {label = '80% Balanced Glass (Default)', val = '36'},
            {label = '65% Translucent Glass', val = '5A'},
            {label = '45% Subtle Tint', val = '8C'},
        }
        for _, op in ipairs(opacities) do
            items[#items + 1] = {
                label = 'Box Opacity: ' .. op.label,
                sublabel = 'Adjust glass translucency and dialog readability',
                action = 'set_box_alpha',
                val = op.val,
                current = (config.box_alpha == op.val),
                index = #items + 1
            }
        end
        items[#items + 1] = {
            label = config.box_rim_enabled and 'Glass Hairline Rim: [ON] 1.0px' or 'Glass Hairline Rim: [OFF]',
            sublabel = 'Sleek frosted visionOS glass edge highlight',
            action = 'toggle_box_rim',
            current = config.box_rim_enabled,
            index = #items + 1
        }
        items[#items + 1] = {
            label = config.box_per_line and 'Pill Layout: Individual Pill Per Line' or 'Pill Layout: Single Unified Pill',
            sublabel = 'Toggle between single pill or segmented multi-line pills',
            action = 'toggle_per_line',
            current = config.box_per_line,
            index = #items + 1
        }
        items[#items + 1] = {
            label = '⬅  Back to Subtitle Settings',
            action = 'nav_menu',
            target = 'sub_config',
            index = #items + 1
        }

    elseif menu_type == 'sub_text' then
        local colors = {
            {name = 'Pure White', hex = '#FFFFFF', desc = 'Crisp standard white'},
            {name = 'Warm Ivory', hex = '#FFF8E7', desc = 'Soft warm white for reduced eye fatigue'},
            {name = 'Cinema Yellow', hex = '#FFE066', desc = 'Golden yellow for bright backgrounds'},
            {name = 'Cyber Cyan', hex = '#00F0FF', desc = 'Vibrant neon cyan accent'},
            {name = 'Pastel Mint', hex = '#70E0B0', desc = 'Soft modern pastel green'},
            {name = 'Soft Peach', hex = '#FFD1BA', desc = 'Warm cinematic peach hue'},
        }
        for _, c in ipairs(colors) do
            items[#items + 1] = {
                label = 'Color: ' .. c.name .. ' (' .. c.hex .. ')',
                sublabel = c.desc,
                action = 'set_text_color',
                hex = c.hex,
                current = (config.text_color == c.hex),
                index = #items + 1
            }
        end
        local sizes = {28, 32, 34, 38, 44, 50}
        for _, s in ipairs(sizes) do
            items[#items + 1] = {
                label = string.format('Font Size: %dpt %s', s, (s == 34 and '(Default)' or '')),
                sublabel = 'Adjust subtitle typography scale',
                action = 'set_font_size',
                val = s,
                current = (config.font_size == s),
                index = #items + 1
            }
        end
        items[#items + 1] = {
            label = config.font_bold and 'Font Weight: Bold [ON]' or 'Font Weight: Regular [OFF]',
            sublabel = 'Toggle between medium and bold typeface',
            action = 'toggle_bold',
            current = config.font_bold,
            index = #items + 1
        }
        items[#items + 1] = {
            label = '⬅  Back to Subtitle Settings',
            action = 'nav_menu',
            target = 'sub_config',
            index = #items + 1
        }

    elseif menu_type == 'sub_border' then
        local b_sizes = {
            {label = '0.0px (None / Flat)', val = 0.0},
            {label = '1.0px (Delicate Hairline)', val = 1.0},
            {label = '1.8px (Standard Halo)', val = 1.8},
            {label = '2.8px (High Visibility)', val = 2.8},
            {label = '3.5px (Heavy Anime Outline)', val = 3.5},
        }
        for _, b in ipairs(b_sizes) do
            items[#items + 1] = {
                label = 'Outline: ' .. b.label,
                sublabel = 'Text outline border width',
                action = 'set_border_size',
                val = b.val,
                current = (math.abs(config.border_size - b.val) < 0.1),
                index = #items + 1
            }
        end
        local shadows = {
            {label = '0.0px (No Shadow)', val = 0.0},
            {label = '1.0px (Subtle Depth)', val = 1.0},
            {label = '1.8px (Standard Shadow)', val = 1.8},
            {label = '3.0px (Deep Shadow)', val = 3.0},
        }
        for _, s in ipairs(shadows) do
            items[#items + 1] = {
                label = 'Shadow: ' .. s.label,
                sublabel = 'Text drop-shadow offset',
                action = 'set_shadow_offset',
                val = s.val,
                current = (math.abs(config.shadow_offset - s.val) < 0.1),
                index = #items + 1
            }
        end
        items[#items + 1] = {
            label = '⬅  Back to Subtitle Settings',
            action = 'nav_menu',
            target = 'sub_config',
            index = #items + 1
        }

    elseif menu_type == 'sub_layout' then
        local margins = {
            {label = '18px (Low / Screen Edge)', val = 18},
            {label = '28px (Standard Apple TV)', val = 28},
            {label = '42px (Elevated / Safe Zone)', val = 42},
            {label = '60px (High / Upper Bar Clear)', val = 60},
        }
        for _, m in ipairs(margins) do
            items[#items + 1] = {
                label = 'Bottom Margin: ' .. m.label,
                sublabel = 'Vertical position above bottom window edge',
                action = 'set_margin_y',
                val = m.val,
                current = (config.margin_y == m.val),
                index = #items + 1
            }
        end
        local spacings = {
            {label = 'Compact (+2px)', val = 2},
            {label = 'Standard (+6px)', val = 6},
            {label = 'Relaxed (+10px)', val = 10},
            {label = 'Spacious (+16px)', val = 16},
        }
        for _, sp in ipairs(spacings) do
            items[#items + 1] = {
                label = 'Line Spacing: ' .. sp.label,
                sublabel = 'Vertical gap between multi-line subtitle dialog',
                action = 'set_line_spacing',
                val = sp.val,
                current = (config.line_spacing == sp.val),
                index = #items + 1
            }
        end
        items[#items + 1] = {
            label = '⬅  Back to Subtitle Settings',
            action = 'nav_menu',
            target = 'sub_config',
            index = #items + 1
        }
    end

    return items
end

-- Handle Subtitle Menu Actions
function M.handle_action(item)
    if not item or not item.action then return end

    if item.action == 'set_preset' and item.preset_key then
        M.apply_preset(item.preset_key)

    elseif item.action == 'toggle_mode' then
        if config.mode == 'rounded_rect' then
            config.mode = 'native'
            config.box_enabled = false
            mp.osd_message('Mode: Native MPV Subtitles', 2)
        else
            config.mode = 'rounded_rect'
            config.box_enabled = true
            mp.osd_message('Mode: visionOS Rounded Rectangle Pill', 2)
        end
        config.preset = 'custom'
        M.apply_config()

    elseif item.action == 'reset_defaults' then
        for k, v in pairs(default_config) do config[k] = v end
        M.apply_preset('visionos_pill')

    elseif item.action == 'toggle_box_enabled' then
        config.box_enabled = not config.box_enabled
        config.preset = 'custom'
        M.apply_config()
        mp.osd_message(config.box_enabled and '✓ Subtitle Box: Enabled' or '✓ Subtitle Box: Disabled', 2)

    elseif item.action == 'set_box_radius' and item.val ~= nil then
        config.box_radius = item.val
        config.preset = 'custom'
        M.apply_config()
        mp.osd_message(string.format('✓ Corner Radius: %s', item.val == -1 and 'Full Pill' or (item.val .. 'px')), 2)

    elseif item.action == 'set_box_alpha' and item.val then
        config.box_alpha = item.val
        config.preset = 'custom'
        M.apply_config()
        mp.osd_message('✓ Box Opacity Updated', 2)

    elseif item.action == 'toggle_box_rim' then
        config.box_rim_enabled = not config.box_rim_enabled
        config.preset = 'custom'
        M.apply_config()
        mp.osd_message(config.box_rim_enabled and '✓ Glass Rim: Enabled' or '✓ Glass Rim: Disabled', 2)

    elseif item.action == 'toggle_per_line' then
        config.box_per_line = not config.box_per_line
        config.preset = 'custom'
        M.apply_config()
        mp.osd_message(config.box_per_line and '✓ Pill: Per-Line' or '✓ Pill: Single Unified', 2)

    elseif item.action == 'set_text_color' and item.hex then
        config.text_color = item.hex
        config.preset = 'custom'
        M.apply_config()
        mp.osd_message('✓ Subtitle Color: ' .. item.hex, 2)

    elseif item.action == 'set_font_size' and item.val then
        config.font_size = item.val
        config.preset = 'custom'
        M.apply_config()
        mp.osd_message(string.format('✓ Subtitle Size: %dpt', item.val), 2)

    elseif item.action == 'toggle_bold' then
        config.font_bold = not config.font_bold
        config.preset = 'custom'
        M.apply_config()
        mp.osd_message(config.font_bold and '✓ Font Weight: Bold' or '✓ Font Weight: Regular', 2)

    elseif item.action == 'set_border_size' and item.val ~= nil then
        config.border_size = item.val
        config.preset = 'custom'
        M.apply_config()
        mp.osd_message(string.format('✓ Border Outline: %.1fpx', item.val), 2)

    elseif item.action == 'set_shadow_offset' and item.val ~= nil then
        config.shadow_offset = item.val
        config.preset = 'custom'
        M.apply_config()
        mp.osd_message(string.format('✓ Shadow Offset: %.1fpx', item.val), 2)

    elseif item.action == 'set_margin_y' and item.val then
        config.margin_y = item.val
        config.preset = 'custom'
        M.apply_config()
        mp.osd_message(string.format('✓ Bottom Margin: %dpx', item.val), 2)

    elseif item.action == 'set_line_spacing' and item.val ~= nil then
        config.line_spacing = item.val
        config.preset = 'custom'
        M.apply_config()
        mp.osd_message(string.format('✓ Line Spacing: %+dpx', item.val), 2)
    end
end

return M
