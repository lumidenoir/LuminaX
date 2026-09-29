-- ============================================================================
-- LuminaX Module: Subtitle
-- Industry-Standard Subtitle Presets & Apple visionOS Rounded Pill Subtitle System
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

local current_sub_scale = 1.0
local mpv_conf_sub_font_size = 26

-- ────────────────────────────────────────────────────────────────────────────
-- 8 Industry-Standard Subtitle Presets (Sleek & Proportional Modern Typographies)
-- ────────────────────────────────────────────────────────────────────────────
local PRESETS = {
    apple_tv = {
        id            = 'apple_tv',
        name          = 'Apple TV+ Glass',
        icon          = '',
        desc          = 'Translucent frosted pill with refined spatial glass aesthetics',
        font_name     = 'Inter, SF Pro Text, -apple-system, sans-serif',
        font_size     = 24,           -- Sleek modern proportional size
        font_color    = 'FFFFFF',
        bold          = false,
        box_enabled   = true,
        box_mode      = 'unified',     -- single capsule enclosing all lines
        box_color     = '000000',
        box_opacity   = 0.68,         -- ~70% allows background video motion to seep through
        box_radius    = 14,           -- smooth organic pill rounding
        glass_rim     = true,         -- subtle white highlight rim (1px, ~15% alpha)
        rim_color     = 'FFFFFF',
        rim_alpha     = 'D0',         -- ASS hex alpha (D0 = ~18% visibility)
        border_size   = 0,
        border_color  = '000000',
        shadow_offset = 0,
        shadow_color  = '000000',
        padding_x     = 18,
        padding_y     = 7,
        line_spacing  = 4,
        bottom_margin = 26,
    },
    netflix_box = {
        id            = 'netflix_box',
        name          = 'Netflix Standard',
        icon          = '🎬',
        desc          = 'Clean dark pill with compact line spacing and balanced contrast',
        font_name     = 'Netflix Sans, Roboto, Arial, sans-serif',
        font_size     = 24,
        font_color    = 'FFFFFF',
        bold          = false,
        box_enabled   = true,
        box_mode      = 'per_line',    -- individual rounded boxes per line
        box_color     = '080808',
        box_opacity   = 0.78,
        box_radius    = 7,
        glass_rim     = false,
        rim_color     = 'FFFFFF',
        rim_alpha     = 'D0',
        border_size   = 0,
        border_color  = '000000',
        shadow_offset = 0,
        shadow_color  = '000000',
        padding_x     = 14,
        padding_y     = 6,
        line_spacing  = 3,
        bottom_margin = 24,
    },
    youtube_cc = {
        id            = 'youtube_cc',
        name          = 'YouTube Studio CC',
        icon          = '▶',
        desc          = 'Compact per-line pills hugging text tightly with small radius',
        font_name     = 'Roboto, Arial, sans-serif',
        font_size     = 22,
        font_color    = 'FFFFFF',
        bold          = true,
        box_enabled   = true,
        box_mode      = 'per_line',
        box_color     = '000000',
        box_opacity   = 0.82,
        box_radius    = 5,
        glass_rim     = false,
        rim_color     = 'FFFFFF',
        rim_alpha     = 'D0',
        border_size   = 0,
        border_color  = '000000',
        shadow_offset = 0,
        shadow_color  = '000000',
        padding_x     = 12,
        padding_y     = 5,
        line_spacing  = 3,
        bottom_margin = 22,
    },
    cinema_gold = {
        id            = 'cinema_gold',
        name          = 'Theatrical Gold',
        icon          = '🍿',
        desc          = 'Soft cinema warm yellow on a subtle dark pill for dark-room viewing',
        font_name     = 'Futura, Gill Sans, Trebuchet MS, sans-serif',
        font_size     = 25,
        font_color    = 'FFE675',     -- warm pale amber/gold
        bold          = false,
        box_enabled   = true,
        box_mode      = 'unified',
        box_color     = '0A0A0A',
        box_opacity   = 0.60,        -- lighter tint to feel more organic on film grain
        box_radius    = 10,
        glass_rim     = false,
        rim_color     = 'FFFFFF',
        rim_alpha     = 'D0',
        border_size   = 0,
        border_color  = '000000',
        shadow_offset = 1.0,
        shadow_color  = '000000',
        padding_x     = 18,
        padding_y     = 7,
        line_spacing  = 4,
        bottom_margin = 28,
    },
    criterion_minimal = {
        id            = 'criterion_minimal',
        name          = 'Criterion Float',
        icon          = '⚪',
        desc          = 'Boxless pure typography with soft drop-shadow depth',
        font_name     = 'Gill Sans, Futura, Inter, sans-serif',
        font_size     = 25,
        font_color    = 'F7F7F7',
        bold          = false,
        box_enabled   = false,
        box_mode      = 'unified',
        box_color     = '000000',
        box_opacity   = 0.0,
        box_radius    = 0,
        glass_rim     = false,
        rim_color     = 'FFFFFF',
        rim_alpha     = 'D0',
        border_size   = 1.0,
        border_color  = '141414',
        shadow_offset = 1.5,
        shadow_color  = '000000',
        padding_x     = 16,
        padding_y     = 6,
        line_spacing  = 4,
        bottom_margin = 24,
    },
    anime_outline = {
        id            = 'anime_outline',
        name          = 'Anime Fansub',
        icon          = '⚔️',
        desc          = 'Bold white text with thick pitch-black contour; boxless',
        font_name     = 'Trebuchet MS, Montserrat, Arial, sans-serif',
        font_size     = 26,
        font_color    = 'FFFFFF',
        bold          = true,
        box_enabled   = false,
        box_mode      = 'unified',
        box_color     = '000000',
        box_opacity   = 0.0,
        box_radius    = 0,
        glass_rim     = false,
        rim_color     = 'FFFFFF',
        rim_alpha     = 'D0',
        border_size   = 2.8,
        border_color  = '000000',
        shadow_offset = 1.0,
        shadow_color  = '000000',
        padding_x     = 16,
        padding_y     = 6,
        line_spacing  = 3,
        bottom_margin = 22,
    },
    bbc_accessible = {
        id            = 'bbc_accessible',
        name          = 'Studio Accessible CC',
        icon          = '👁',
        desc          = 'High-contrast cadmium yellow on 95% solid black capsule (WCAG AAA)',
        font_name     = 'Atkinson Hyperlegible, Arial, sans-serif',
        font_size     = 28,
        font_color    = 'FFFF00',     -- pure high-visibility yellow
        bold          = true,
        box_enabled   = true,
        box_mode      = 'per_line',
        box_color     = '000000',
        box_opacity   = 0.94,        -- almost solid
        box_radius    = 7,
        glass_rim     = false,
        rim_color     = 'FFFFFF',
        rim_alpha     = 'D0',
        border_size   = 0,
        border_color  = '000000',
        shadow_offset = 0,
        shadow_color  = '000000',
        padding_x     = 16,
        padding_y     = 7,
        line_spacing  = 4,
        bottom_margin = 26,
    },
    disney_slate = {
        id            = 'disney_slate',
        name          = 'Disney+ Midnight',
        icon          = '✨',
        desc          = 'Deep midnight navy glass capsule for a softer contrast transition',
        font_name     = 'Avenir, Inter, Helvetica Neue, sans-serif',
        font_size     = 24,
        font_color    = 'FFFFFF',
        bold          = false,
        box_enabled   = true,
        box_mode      = 'unified',
        box_color     = '0B101E',     -- deep midnight navy
        box_opacity   = 0.75,
        box_radius    = 10,
        glass_rim     = true,
        rim_color     = '7090C0',     -- muted slate-blue hairline
        rim_alpha     = 'E0',
        border_size   = 0,
        border_color  = '000000',
        shadow_offset = 0,
        shadow_color  = '000000',
        padding_x     = 18,
        padding_y     = 7,
        line_spacing  = 4,
        bottom_margin = 26,
    },
}

-- Default Active Subtitle Configuration (Initialized to Apple TV+ Glass)
local default_config = {
    preset        = 'apple_tv',
    font_name     = PRESETS.apple_tv.font_name,
    font_size     = PRESETS.apple_tv.font_size,
    font_color    = PRESETS.apple_tv.font_color,
    bold          = PRESETS.apple_tv.bold,
    box_enabled   = PRESETS.apple_tv.box_enabled,
    box_mode      = PRESETS.apple_tv.box_mode,
    box_color     = PRESETS.apple_tv.box_color,
    box_opacity   = PRESETS.apple_tv.box_opacity,
    box_radius    = PRESETS.apple_tv.box_radius,
    glass_rim     = PRESETS.apple_tv.glass_rim,
    rim_color     = PRESETS.apple_tv.rim_color,
    rim_alpha     = PRESETS.apple_tv.rim_alpha,
    border_size   = PRESETS.apple_tv.border_size,
    border_color  = PRESETS.apple_tv.border_color,
    shadow_offset = PRESETS.apple_tv.shadow_offset,
    shadow_color  = PRESETS.apple_tv.shadow_color,
    padding_x     = PRESETS.apple_tv.padding_x,
    padding_y     = PRESETS.apple_tv.padding_y,
    line_spacing  = PRESETS.apple_tv.line_spacing,
    bottom_margin = PRESETS.apple_tv.bottom_margin,
}

local config = {}
for k, v in pairs(default_config) do config[k] = v end

-- ────────────────────────────────────────────────────────────────────────────
-- Helper Functions: Color Conversion, Metrics & Scaling
-- ────────────────────────────────────────────────────────────────────────────

-- ASS Color Encoding Caution: Convert RGB hex "RRGGBB" -> ASS BGR "&HBBGGRR&"
local function rgb_to_ass(hex_str)
    if not hex_str or type(hex_str) ~= 'string' then return '&HFFFFFF&' end
    local h = hex_str:gsub('#', ''):upper()
    if #h == 6 then
        local r, g, b = h:sub(1, 2), h:sub(3, 4), h:sub(5, 6)
        return '&H' .. b .. g .. r .. '&'
    elseif #h == 8 then
        local r, g, b = h:sub(3, 4), h:sub(5, 6), h:sub(7, 8)
        return '&H' .. b .. g .. r .. '&'
    end
    return '&HFFFFFF&'
end

-- Convert opacity (0.0 to 1.0) -> ASS alpha hex (00 = 100% opaque, FF = transparent)
local function opacity_to_ass_alpha(opacity)
    local op = tonumber(opacity) or 1.0
    op = math.max(0.0, math.min(1.0, op))
    local alpha = math.floor((1.0 - op) * 255 + 0.5)
    return string.format('%02X', alpha)
end

-- Extract primary typeface family from comma-separated list
local function get_primary_font(font_str)
    if not font_str or font_str == '' then return 'Inter' end
    local first = font_str:match('^%s*([^,]+)')
    return first and first:gsub('^%s+', ''):gsub('%s+$', '') or 'Inter'
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
local function estimate_char_width(byte, fs, is_bold)
    local bold_factor = is_bold and 1.05 or 1.0
    -- Multi-byte UTF-8 character (e.g. CJK, emoji)
    if byte >= 0xC0 then
        return fs * 0.95 * bold_factor
    end
    local ch = string.char(byte)
    if ch:match('[WwMm@]') then
        return fs * 0.72 * bold_factor
    elseif ch:match('[A-Z]') then
        return fs * 0.58 * bold_factor
    elseif ch:match('[a-z0-9]') then
        if ch:match('[iljtfr]') then
            return fs * 0.30 * bold_factor
        end
        return fs * 0.48 * bold_factor
    elseif ch:match('[%s]') then
        return fs * 0.28
    elseif ch:match('[,%.!;:|\'"%-_]') then
        return fs * 0.25
    else
        return fs * 0.44 * bold_factor
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
        w = w + estimate_char_width(b, fs, is_bold)
        i = i + step
    end
    return math.ceil(w)
end

-- ────────────────────────────────────────────────────────────────────────────
-- Persistence (Save & Load Config)
-- ────────────────────────────────────────────────────────────────────────────

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

-- ────────────────────────────────────────────────────────────────────────────
-- Apply Configuration & Synchronize Native MPV Properties
-- ────────────────────────────────────────────────────────────────────────────

function M.apply_config(skip_save)
    if not skip_save then save_config() end

    local sid = mp.get_property('sid')
    local sub_off = (sid == 'no' or sid == nil)

    if config.box_enabled then
        -- In pill overlay mode, visually hide native subtitles so only the rounded pill is drawn
        if not sub_off then
            mp.set_property_bool('sub-visibility', false)
        end
        M.update_overlay()
    else
        -- Boxless mode: hide native if we render via overlay, or sync native properties
        if not sub_off then
            mp.set_property_bool('sub-visibility', false)
        end
        M.update_overlay()

        -- Also keep mpv native properties synchronized in case user toggles visibility manually
        local font = get_primary_font(config.font_name)
        pcall(mp.set_property, 'sub-font', font)
        pcall(mp.set_property, 'sub-font-size', tostring(config.font_size))
        pcall(mp.set_property, 'sub-bold', config.bold and 'yes' or 'no')
        pcall(mp.set_property, 'sub-color', '#' .. (config.font_color or 'FFFFFF'))
        pcall(mp.set_property, 'sub-border-color', '#' .. (config.border_color or '000000'))
        pcall(mp.set_property, 'sub-border-size', tostring(config.border_size or 0))
        pcall(mp.set_property, 'sub-shadow-offset', tostring(config.shadow_offset or 0))
        pcall(mp.set_property, 'sub-shadow-color', '#' .. (config.shadow_color or '000000') .. 'A0')
        pcall(mp.set_property, 'sub-margin-y', tostring(config.bottom_margin or 26))
    end

    if ctx_ref.request_tick then ctx_ref.request_tick() end
end

-- Apply an industry-standard style preset
function M.apply_preset(preset_id)
    local p = PRESETS[preset_id]
    if not p then return end
    config.preset = preset_id
    for k, v in pairs(p) do
        if k ~= 'id' and k ~= 'name' and k ~= 'desc' and k ~= 'icon' then
            config[k] = v
        end
    end
    M.apply_config()
    mp.osd_message(string.format('%s  Preset: %s (%dpt)', p.icon or '✓', p.name, config.font_size), 2.0)
end

-- ────────────────────────────────────────────────────────────────────────────
-- Rounded Rectangle Subtitle Overlay Renderer
-- ────────────────────────────────────────────────────────────────────────────

function M.update_overlay()
    if not overlay then return end

    local sid = mp.get_property('sid')
    local sub_off = (sid == 'no' or sid == nil)

    local text_to_render = current_sub_text
    if live_preview_active and (text_to_render == '' or sub_off) then
        local p_info = PRESETS[config.preset]
        local p_name = p_info and p_info.name or 'Custom'
        text_to_render = string.format('Sample Subtitle  •  %s Style', p_name)
    end

    if (text_to_render == '' or sub_off) and not live_preview_active then
        overlay:remove()
        return
    end

    -- Reference canvas: 720p virtual height for perfect ASS coordinate consistency
    local ow, oh = mp.get_osd_size()
    local aspect = (ow and oh and oh > 0) and (ow / oh) or (16 / 9)
    local canvas_h = 720
    local canvas_w = math.floor(720 * aspect + 0.5)

    -- Dynamic Font Scaling based on user sub-scale multiplier
    local scale_factor = current_sub_scale or 1.0
    local fs    = math.floor((config.font_size or 24) * scale_factor + 0.5)
    local is_bold = config.bold or false

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

    local line_sp  = math.floor((config.line_spacing or 4) * scale_factor + 0.5)
    local line_h   = math.ceil(fs * 1.18 + line_sp)
    local pad_x    = math.floor((config.padding_x or 18) * scale_factor + 0.5)
    local pad_y    = math.floor((config.padding_y or 7) * scale_factor + 0.5)
    local margin_y = math.floor((config.bottom_margin or 26) * scale_factor + 0.5)

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

    -- Color & Alpha encodings (ASS expects BGR)
    local txt_bgr   = rgb_to_ass(config.font_color or 'FFFFFF')
    local box_bgr   = rgb_to_ass(config.box_color or '000000')
    local box_a     = opacity_to_ass_alpha(config.box_opacity or 0.70)
    local rim_bgr   = rgb_to_ass(config.rim_color or 'FFFFFF')
    local rim_a     = config.rim_alpha or 'D0'
    local rim_w     = config.glass_rim and 1.0 or 0

    local bord_bgr  = rgb_to_ass(config.border_color or '000000')
    local bord_w    = (config.border_size and config.border_size > 0) and (config.border_size * scale_factor) or 0
    local shad_bgr  = rgb_to_ass(config.shadow_color or '000000')
    local shad_off  = (config.shadow_offset and config.shadow_offset > 0) and (config.shadow_offset * scale_factor) or 0

    local cx        = math.floor(canvas_w / 2)
    local font_face = get_primary_font(config.font_name)

    local raw_r     = config.box_radius or 14
    local scaled_r  = (raw_r == -1) and -1 or math.floor(raw_r * scale_factor + 0.5)

    if config.box_enabled and config.box_mode == 'per_line' then
        -- ────────────────────────────────────────────────────────────────────
        -- 1. Per-Line Pill Rendering (YouTube Studio / Netflix / BBC CC)
        -- ────────────────────────────────────────────────────────────────────
        local gap = math.max(3, math.floor(line_sp * 0.7))
        local line_box_h = line_h + pad_y * 2
        local total_h = (total_lines * line_box_h) + ((total_lines - 1) * gap)
        local start_y = canvas_h - margin_y - total_h

        for i, line in ipairs(raw_lines) do
            local lw   = line_widths[i] or max_lw
            local pw   = lw + pad_x * 2
            local ph   = line_box_h
            local r    = (scaled_r == -1) and math.floor(ph / 2) or math.min(scaled_r, math.floor(ph / 2))
            local ly0  = start_y + (i - 1) * (ph + gap)
            local ly1  = ly0 + ph
            local lx0  = cx - math.floor(pw / 2)
            local lx1  = cx + math.floor(pw / 2)

            -- Background Pill
            ass:new_event()
            ass:pos(0, 0)
            ass:an(7)
            ass:append(string.format('{\\blur0\\bord%s\\1c%s\\1a&H%s&\\3c%s\\3a&H%s&}',
                tostring(rim_w), box_bgr, box_a, rim_bgr, rim_a))
            ass:draw_start()
            ass:round_rect_cw(lx0, ly0, lx1, ly1, r)
            ass:draw_stop()

            -- Text inside line pill
            local text_cy = ly0 + math.floor(ph / 2)
            ass:new_event()
            ass:pos(cx, text_cy)
            ass:an(5)
            ass:append(string.format('{\\fn%s\\fs%d%s\\1c%s\\1a&H00&\\bord%s\\3c%s\\3a&H00&\\shad%s\\4c%s\\4a&H80&\\fsp0.5\\q2}',
                font_face, fs, is_bold and '\\b700' or '\\b400',
                txt_bgr, tostring(bord_w), bord_bgr, tostring(shad_off), shad_bgr))
            ass:append(line)
        end

    elseif config.box_enabled then
        -- ────────────────────────────────────────────────────────────────────
        -- 2. Unified Pill Rendering (Apple TV+ / Cinema Gold / Disney+)
        -- ────────────────────────────────────────────────────────────────────
        local pill_w = max_lw + pad_x * 2
        local pill_h = (total_lines * line_h) + pad_y * 2
        local r      = (scaled_r == -1) and math.floor(pill_h / 2) or math.min(scaled_r, math.floor(pill_h / 2))

        local y1     = canvas_h - margin_y
        local y0     = y1 - pill_h
        local x0     = cx - math.floor(pill_w / 2)
        local x1     = cx + math.floor(pill_w / 2)

        -- Background Capsule
        ass:new_event()
        ass:pos(0, 0)
        ass:an(7)
        ass:append(string.format('{\\blur0\\bord%s\\1c%s\\1a&H%s&\\3c%s\\3a&H%s&}',
            tostring(rim_w), box_bgr, box_a, rim_bgr, rim_a))
        ass:draw_start()
        ass:round_rect_cw(x0, y0, x1, y1, r)
        ass:draw_stop()

        -- Text Lines inside unified capsule
        for i, line in ipairs(raw_lines) do
            local text_cy = y0 + pad_y + math.floor((i - 0.5) * line_h)
            ass:new_event()
            ass:pos(cx, text_cy)
            ass:an(5)
            ass:append(string.format('{\\fn%s\\fs%d%s\\1c%s\\1a&H00&\\bord%s\\3c%s\\3a&H00&\\shad%s\\4c%s\\4a&H80&\\fsp0.5\\q2}',
                font_face, fs, is_bold and '\\b700' or '\\b400',
                txt_bgr, tostring(bord_w), bord_bgr, tostring(shad_off), shad_bgr))
            ass:append(line)
        end

    else
        -- ────────────────────────────────────────────────────────────────────
        -- 3. Boxless Typography (Anime Fansub / Criterion Float)
        -- ────────────────────────────────────────────────────────────────────
        local total_h = total_lines * line_h
        local y1      = canvas_h - margin_y
        local y0      = y1 - total_h

        for i, line in ipairs(raw_lines) do
            local text_cy = y0 + math.floor((i - 0.5) * line_h)
            ass:new_event()
            ass:pos(cx, text_cy)
            ass:an(5)
            ass:append(string.format('{\\fn%s\\fs%d%s\\1c%s\\1a&H00&\\bord%s\\3c%s\\3a&H00&\\shad%s\\4c%s\\4a&H90&\\fsp0.5\\q2}',
                font_face, fs, is_bold and '\\b700' or '\\b400',
                txt_bgr, tostring(bord_w), bord_bgr, tostring(shad_off), shad_bgr))
            ass:append(line)
        end
    end

    overlay.res_x = canvas_w
    overlay.res_y = canvas_h
    overlay.data  = ass.text
    overlay:update()
end

-- ────────────────────────────────────────────────────────────────────────────
-- Subtitle Scale Adjustment & Keybinding Helpers
-- ────────────────────────────────────────────────────────────────────────────

function M.add_sub_scale(delta)
    local cur = mp.get_property_number('sub-scale', 1.0)
    local new_val = math.max(0.4, math.min(2.5, cur + delta))
    new_val = math.floor(new_val * 100 + 0.5) / 100
    pcall(mp.set_property_number, 'sub-scale', new_val)
    current_sub_scale = new_val
    M.update_overlay()
    local eff_fs = math.floor((config.font_size or 24) * current_sub_scale + 0.5)
    mp.osd_message(string.format('Subtitle Size: %dpt (%d%%)', eff_fs, math.floor(new_val * 100)), 1.5)
end

function M.reset_sub_scale()
    pcall(mp.set_property_number, 'sub-scale', 1.0)
    current_sub_scale = 1.0
    M.update_overlay()
    mp.osd_message(string.format('Subtitle Size: %dpt (100%%)', config.font_size or 24), 1.5)
end

-- ────────────────────────────────────────────────────────────────────────────
-- Module Lifecycle & Event Listeners
-- ────────────────────────────────────────────────────────────────────────────

function M.init(ctx)
    ctx_ref = ctx or {}
    overlay = mp.create_osd_overlay('ass-events')

    -- Read configured font size from mpv.conf if set
    local cfg_fs = mp.get_property_number('sub-font-size')
    if cfg_fs and cfg_fs > 0 then
        mpv_conf_sub_font_size = cfg_fs
    end

    current_sub_scale = mp.get_property_number('sub-scale', 1.0)

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

    -- Observe MPV's sub-scale keybindings (Shift+G / Shift+F, Ctrl+= / Ctrl+-)
    mp.observe_property('sub-scale', 'number', function(_, s)
        current_sub_scale = s or 1.0
        M.update_overlay()
    end)

    -- Observe mpv.conf sub-font-size changes
    mp.observe_property('sub-font-size', 'number', function(_, fs)
        if fs and fs > 0 then
            mpv_conf_sub_font_size = fs
        end
    end)

    M.apply_config(true)
end

function M.get_config()
    return config
end

function M.get_presets()
    return PRESETS
end

function M.get_current_scale()
    return current_sub_scale
end

function M.get_mpv_conf_font_size()
    return mpv_conf_sub_font_size
end

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
        sub_presets = 'INDUSTRY STYLE PRESETS',
        sub_box     = 'ROUNDED PILL & BOX STYLE',
        sub_text    = 'TEXT SIZE, SCALE & COLOR',
        sub_border  = 'BORDER & SHADOW STYLING',
        sub_layout  = 'POSITION & SPACING',
    }
    return titles[menu_type] or 'SUBTITLE SETTINGS'
end

function M.get_menu_items(menu_type)
    local items = {}
    local eff_fs = math.floor((config.font_size or 24) * current_sub_scale + 0.5)

    if menu_type == 'sub_config' then
        local p_info = PRESETS[config.preset]
        local p_name = p_info and (p_info.icon .. '  ' .. p_info.name) or '🎨 Custom'
        local box_desc = config.box_enabled
            and (string.format('%s  •  %dpx  •  %d%% Opacity',
                    config.box_mode == 'per_line' and 'Per-Line Pill' or 'Unified Pill',
                    config.box_radius, math.floor(config.box_opacity * 100)))
            or 'Disabled (Boxless)'

        items[#items + 1] = {
            label = '✦  Style Presets  ▸',
            sublabel = 'Active: ' .. p_name .. ' • 8 Industry Platform Standards',
            action = 'nav_menu',
            target = 'sub_presets',
            index = #items + 1
        }
        items[#items + 1] = {
            label = '▢  Rounded Pill & Box Style  ▸',
            sublabel = box_desc .. ' • Curvature, glass rim & opacity',
            action = 'nav_menu',
            target = 'sub_box',
            index = #items + 1
        }
        items[#items + 1] = {
            label = '🎨  Text Size, Scale & Color  ▸',
            sublabel = string.format('%s  •  %dpt (Scale: %d%%)  •  #%s', get_primary_font(config.font_name), eff_fs, math.floor(current_sub_scale * 100), config.font_color),
            action = 'nav_menu',
            target = 'sub_text',
            index = #items + 1
        }
        items[#items + 1] = {
            label = '🔲  Border & Shadow  ▸',
            sublabel = string.format('Border: %.1fpx  •  Shadow: %.1fpx', config.border_size or 0, config.shadow_offset or 0),
            action = 'nav_menu',
            target = 'sub_border',
            index = #items + 1
        }
        items[#items + 1] = {
            label = '📐  Position & Line Spacing  ▸',
            sublabel = string.format('Bottom Margin: %dpx  •  Line Spacing: %+dpx', config.bottom_margin or 26, config.line_spacing or 4),
            action = 'nav_menu',
            target = 'sub_layout',
            index = #items + 1
        }
        items[#items + 1] = {
            label = config.box_enabled and '👁  Pill Background: [ON]' or '👁  Pill Background: [OFF] Boxless',
            sublabel = 'Quick toggle between rounded capsule backdrop and pure boxless text',
            action = 'toggle_box_enabled',
            current = config.box_enabled,
            index = #items + 1
        }
        items[#items + 1] = {
            label = '↺  Reset to Apple TV+ Glass',
            sublabel = 'Restores Apple visionOS spatial frosted pill styling',
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
        local order = {
            'apple_tv',
            'netflix_box',
            'youtube_cc',
            'cinema_gold',
            'criterion_minimal',
            'anime_outline',
            'bbc_accessible',
            'disney_slate'
        }
        for _, id in ipairs(order) do
            local p = PRESETS[id]
            items[#items + 1] = {
                label = string.format('%s  %s  (%dpt)', p.icon or '•', p.name, p.font_size),
                sublabel = p.desc,
                action = 'set_preset',
                preset_id = id,
                current = (config.preset == id),
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
            label = config.box_enabled and 'Box Mode: [ON] Rounded Capsule' or 'Box Mode: [OFF] Boxless Text',
            sublabel = 'Enable/disable drawing rounded pill backdrop behind dialogue',
            action = 'toggle_box_enabled',
            current = config.box_enabled,
            index = #items + 1
        }
        items[#items + 1] = {
            label = config.box_mode == 'unified' and 'Layout: Single Unified Capsule' or 'Layout: Per-Line Individual Pills',
            sublabel = config.box_mode == 'unified' and 'Single enclosing pill for all lines (Apple TV / Cinema)' or 'Individual badges hugging each line tightly (YouTube / Netflix)',
            action = 'toggle_box_mode',
            current = (config.box_mode == 'per_line'),
            index = #items + 1
        }
        local radii = {
            {label = 'Full Capsule (Pill)', val = -1, sub = 'Fully rounded capsule ends'},
            {label = '14px Corner Radius (Apple TV+)', val = 14, sub = 'Organic smooth spatial curve'},
            {label = '10px Corner Radius (Disney+)', val = 10, sub = 'Balanced modern TV curvature'},
            {label = '7px Corner Radius (Netflix)', val = 7, sub = 'Compact modern streaming box'},
            {label = '5px Corner Radius (YouTube CC)', val = 5, sub = 'Tight badge corner rounding'},
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
            {label = '94% Solid Black (Studio CC)', val = 0.94},
            {label = '82% High Contrast (YouTube)', val = 0.82},
            {label = '78% Balanced (Netflix Standard)', val = 0.78},
            {label = '75% Slate (Disney+ Midnight)', val = 0.75},
            {label = '68% Spatial Glass (Apple TV+)', val = 0.68},
            {label = '60% Ambient Tint (Cinema 35mm)', val = 0.60},
        }
        for _, op in ipairs(opacities) do
            items[#items + 1] = {
                label = 'Box Opacity: ' .. op.label,
                sublabel = 'Adjust glass translucency and dialog readability',
                action = 'set_box_opacity',
                val = op.val,
                current = (math.abs(config.box_opacity - op.val) < 0.02),
                index = #items + 1
            }
        end
        items[#items + 1] = {
            label = config.glass_rim and 'Glass Rim Highlight: [ON]' or 'Glass Rim Highlight: [OFF]',
            sublabel = 'Subtle translucent hairline highlight rim separating pill from bright backgrounds',
            action = 'toggle_glass_rim',
            current = config.glass_rim,
            index = #items + 1
        }
        items[#items + 1] = {
            label = '⬅  Back to Subtitle Settings',
            action = 'nav_menu',
            target = 'sub_config',
            index = #items + 1
        }

    elseif menu_type == 'sub_text' then
        -- Scale Keybinding Actions
        items[#items + 1] = {
            label = string.format('Scale: %d%% (Effective: %dpt)', math.floor(current_sub_scale * 100), eff_fs),
            sublabel = 'Keys: Shift+G / Shift+F or Ctrl+= / Ctrl+- to scale dynamically',
            action = 'none',
            index = #items + 1
        }
        items[#items + 1] = {
            label = '➕  Increase Subtitle Size (+10%)',
            sublabel = 'Shortcut: Shift+G or Ctrl+= or Ctrl+Shift+UP',
            action = 'scale_up',
            index = #items + 1
        }
        items[#items + 1] = {
            label = '➖  Decrease Subtitle Size (-10%)',
            sublabel = 'Shortcut: Shift+F or Ctrl+- or Ctrl+Shift+DOWN',
            action = 'scale_down',
            index = #items + 1
        }
        items[#items + 1] = {
            label = '↺  Reset Scale to 100%',
            sublabel = 'Restores 1.0x neutral scale multiplier',
            action = 'scale_reset',
            index = #items + 1
        }

        -- Preset Font Sizes (Compact & Proportional)
        local sizes = {
            {label = '20pt (Extra Small)', val = 20, desc = 'Compact for high resolution displays'},
            {label = '22pt (Small - YouTube CC)', val = 22, desc = 'Tight and minimal'},
            {label = '24pt (Standard - Apple TV+)', val = 24, desc = 'Ideal modern golden ratio'},
            {label = '25pt (Medium - Netflix/Cinema)', val = 25, desc = 'Balanced high readability'},
            {label = '28pt (Large - Accessible)', val = 28, desc = 'Higher visibility without crowding'},
            {label = string.format('Use mpv.conf Base Size (%dpt)', mpv_conf_sub_font_size), val = mpv_conf_sub_font_size, desc = 'Directly syncs to your mpv.conf sub-font-size'},
        }
        for _, s in ipairs(sizes) do
            items[#items + 1] = {
                label = 'Size: ' .. s.label,
                sublabel = s.desc,
                action = 'set_font_size',
                val = s.val,
                current = (config.font_size == s.val),
                index = #items + 1
            }
        end

        local colors = {
            {name = 'Pure White', hex = 'FFFFFF', desc = 'Crisp standard white (Apple / Netflix)'},
            {name = 'Theatrical Warm Gold', hex = 'FFE675', desc = 'Cinema 35mm pale amber gold for dark rooms'},
            {name = 'Accessible Yellow', hex = 'FFFF00', desc = 'WCAG AAA pure cadmium yellow (BBC CC)'},
            {name = 'Criterion Off-White', hex = 'F7F7F7', desc = 'Clean neutral ivory for film immersion'},
            {name = 'Cyber Cyan', hex = '00F0FF', desc = 'High-visibility neon cyan accent'},
        }
        for _, c in ipairs(colors) do
            items[#items + 1] = {
                label = 'Color: ' .. c.name .. ' (#' .. c.hex .. ')',
                sublabel = c.desc,
                action = 'set_font_color',
                hex = c.hex,
                current = (config.font_color:upper() == c.hex:upper()),
                index = #items + 1
            }
        end

        items[#items + 1] = {
            label = config.bold and 'Font Weight: Bold [ON]' or 'Font Weight: Regular [OFF]',
            sublabel = 'Toggle between regular and bold typeface weight',
            action = 'toggle_bold',
            current = config.bold,
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
            {label = '0.0px (None / Clean Glass)', val = 0.0},
            {label = '1.0px (Criterion Depth)', val = 1.0},
            {label = '1.8px (Standard Contour)', val = 1.8},
            {label = '2.8px (Anime Fansub Stroke)', val = 2.8},
        }
        for _, b in ipairs(b_sizes) do
            items[#items + 1] = {
                label = 'Outline: ' .. b.label,
                sublabel = 'Text contour stroke width',
                action = 'set_border_size',
                val = b.val,
                current = (math.abs((config.border_size or 0) - b.val) < 0.1),
                index = #items + 1
            }
        end
        local shadows = {
            {label = '0.0px (None / Flat)', val = 0.0},
            {label = '1.0px (Cinema Subtle Shadow)', val = 1.0},
            {label = '1.5px (Criterion Float Shadow)', val = 1.5},
            {label = '2.5px (Deep Drop Shadow)', val = 2.5},
        }
        for _, s in ipairs(shadows) do
            items[#items + 1] = {
                label = 'Shadow: ' .. s.label,
                sublabel = 'Text drop-shadow offset',
                action = 'set_shadow_offset',
                val = s.val,
                current = (math.abs((config.shadow_offset or 0) - s.val) < 0.1),
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
            {label = '20px (Ultra Low / Screen Edge)', val = 20},
            {label = '24px (Netflix Standard)', val = 24},
            {label = '26px (Apple TV+ Standard)', val = 26},
            {label = '30px (Elevated)', val = 30},
            {label = '36px (High / Upper Safe Zone)', val = 36},
        }
        for _, m in ipairs(margins) do
            items[#items + 1] = {
                label = 'Bottom Margin: ' .. m.label,
                sublabel = 'Vertical elevation above video bottom edge',
                action = 'set_bottom_margin',
                val = m.val,
                current = (config.bottom_margin == m.val),
                index = #items + 1
            }
        end
        local spacings = {
            {label = '2px (Ultra Compact)', val = 2},
            {label = '3px (YouTube / Netflix Compact)', val = 3},
            {label = '4px (Apple TV+ Standard)', val = 4},
            {label = '6px (Relaxed Arthouse)', val = 6},
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

-- ────────────────────────────────────────────────────────────────────────────
-- Handle Subtitle Menu Action Dispatcher
-- ────────────────────────────────────────────────────────────────────────────

function M.handle_action(item)
    if not item or not item.action then return end

    if item.action == 'set_preset' and item.preset_id then
        M.apply_preset(item.preset_id)

    elseif item.action == 'reset_defaults' then
        M.apply_preset('apple_tv')

    elseif item.action == 'scale_up' then
        M.add_sub_scale(0.10)

    elseif item.action == 'scale_down' then
        M.add_sub_scale(-0.10)

    elseif item.action == 'scale_reset' then
        M.reset_sub_scale()

    elseif item.action == 'toggle_box_enabled' then
        config.box_enabled = not config.box_enabled
        config.preset = 'custom'
        M.apply_config()
        mp.osd_message(config.box_enabled and '✓ Subtitle Pill: Enabled' or '✓ Subtitle Box: Disabled (Boxless)', 2)

    elseif item.action == 'toggle_box_mode' then
        config.box_mode = (config.box_mode == 'unified') and 'per_line' or 'unified'
        config.preset = 'custom'
        M.apply_config()
        mp.osd_message(config.box_mode == 'per_line' and '✓ Layout: Per-Line Pills' or '✓ Layout: Single Unified Capsule', 2)

    elseif item.action == 'set_box_radius' and item.val ~= nil then
        config.box_radius = item.val
        config.preset = 'custom'
        M.apply_config()
        mp.osd_message(string.format('✓ Curvature: %s', item.val == -1 and 'Full Pill' or (item.val .. 'px')), 2)

    elseif item.action == 'set_box_opacity' and item.val then
        config.box_opacity = item.val
        config.preset = 'custom'
        M.apply_config()
        mp.osd_message(string.format('✓ Box Opacity: %d%%', math.floor(item.val * 100)), 2)

    elseif item.action == 'toggle_glass_rim' then
        config.glass_rim = not config.glass_rim
        config.preset = 'custom'
        M.apply_config()
        mp.osd_message(config.glass_rim and '✓ Glass Rim: Enabled' or '✓ Glass Rim: Disabled', 2)

    elseif item.action == 'set_font_color' and item.hex then
        config.font_color = item.hex
        config.preset = 'custom'
        M.apply_config()
        mp.osd_message('✓ Subtitle Color: #' .. item.hex, 2)

    elseif item.action == 'set_font_size' and item.val then
        config.font_size = item.val
        config.preset = 'custom'
        M.apply_config()
        local eff_fs = math.floor(item.val * current_sub_scale + 0.5)
        mp.osd_message(string.format('✓ Font Size: %dpt', eff_fs), 2)

    elseif item.action == 'toggle_bold' then
        config.bold = not config.bold
        config.preset = 'custom'
        M.apply_config()
        mp.osd_message(config.bold and '✓ Font Weight: Bold' or '✓ Font Weight: Regular', 2)

    elseif item.action == 'set_border_size' and item.val ~= nil then
        config.border_size = item.val
        config.preset = 'custom'
        M.apply_config()
        mp.osd_message(string.format('✓ Contour Outline: %.1fpx', item.val), 2)

    elseif item.action == 'set_shadow_offset' and item.val ~= nil then
        config.shadow_offset = item.val
        config.preset = 'custom'
        M.apply_config()
        mp.osd_message(string.format('✓ Shadow Offset: %.1fpx', item.val), 2)

    elseif item.action == 'set_bottom_margin' and item.val then
        config.bottom_margin = item.val
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
