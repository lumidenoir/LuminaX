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
-- 10 Industry-Standard Subtitle Presets (Sleek & Proportional Modern Typographies)
-- ────────────────────────────────────────────────────────────────────────────
local PRESETS = {
    apple_tv = {
        id            = 'apple_tv',
        name          = 'Apple TV+ Glass',
        icon          = '✦',
        desc          = 'Translucent frosted pill with refined spatial glass aesthetics',
        font_name     = 'Geist Medium, Instrument Sans Medium, SF Pro Text, Inter, sans-serif',
        font_size     = 27,
        font_color    = 'FFFFFF',
        bold          = false,
        spacing       = 0.2,
        box_enabled   = true,
        box_mode      = 'unified',     -- single capsule enclosing all lines
        box_color     = '000000',
        box_opacity   = 0.68,
        box_radius    = 14,
        glass_rim     = true,
        rim_color     = 'FFFFFF',
        rim_alpha     = 'D0',
        border_size   = 0,
        border_color  = '000000',
        shadow_offset = 0,
        shadow_color  = '000000',
        padding_x     = 18,
        padding_y     = 7,
        line_spacing  = 4,
        bottom_margin = 28,
    },
    netflix_box = {
        id            = 'netflix_box',
        name          = 'Netflix Standard',
        icon          = '🎬',
        desc          = 'Clean dark pill with compact line spacing and balanced contrast',
        font_name     = 'General Sans Semibold, Albert Sans SemiBold, Netflix Sans, Roboto, sans-serif',
        font_size     = 26,
        font_color    = 'FFFFFF',
        bold          = false,
        spacing       = 0.1,
        box_enabled   = true,
        box_mode      = 'per_line',    -- individual rounded boxes per line
        box_color     = '080808',
        box_opacity   = 0.80,
        box_radius    = 8,
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
    prime_video = {
        id            = 'prime_video',
        name          = 'Prime Video Dark',
        icon          = '🟦',
        desc          = 'Per-line opaque dark pill with tight radius; Amazon Prime Video signature style',
        font_name     = 'Figtree SemiBold, Overpass SemiBold, Amazon Ember, Overpass, sans-serif',
        font_size     = 24,
        font_color    = 'FFFFFF',
        bold          = false,
        spacing       = 0.1,
        box_enabled   = true,
        box_mode      = 'per_line',
        box_color     = '040404',
        box_opacity   = 0.82,
        box_radius    = 8,
        glass_rim     = false,
        rim_color     = 'FFFFFF',
        rim_alpha     = 'D0',
        border_size   = 0,
        border_color  = '000000',
        shadow_offset = 0,
        shadow_color  = '000000',
        padding_x     = 14,
        padding_y     = 5,
        line_spacing  = 3,
        bottom_margin = 24,
    },
    disney_slate = {
        id            = 'disney_slate',
        name          = 'Disney+ Midnight',
        icon          = '✨',
        desc          = 'Deep midnight navy glass capsule for a softer contrast transition',
        font_name     = 'Outfit Medium, Lexend Medium, Avenir, Inter, sans-serif',
        font_size     = 25,
        font_color    = 'FFFFFF',
        bold          = false,
        spacing       = 0.2,
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
    hbo_max = {
        id            = 'hbo_max',
        name          = 'Max (HBO)',
        icon          = '💜',
        desc          = 'Dark charcoal unified capsule; HBO Max signature dense and premium look',
        font_name     = 'Metropolis SemiBold, Red Hat Display Medium, Gotham, Red Hat Display, sans-serif',
        font_size     = 25,
        font_color    = 'FFFFFF',
        bold          = false,
        spacing       = 0.0,
        box_enabled   = true,
        box_mode      = 'unified',
        box_color     = '141414',
        box_opacity   = 0.84,
        box_radius    = 10,
        glass_rim     = false,
        rim_color     = 'FFFFFF',
        rim_alpha     = 'D0',
        border_size   = 0,
        border_color  = '000000',
        shadow_offset = 0,
        shadow_color  = '000000',
        padding_x     = 16,
        padding_y     = 6,
        line_spacing  = 3,
        bottom_margin = 26,
    },
    youtube_cc = {
        id            = 'youtube_cc',
        name          = 'YouTube Studio CC',
        icon          = '▶',
        desc          = 'Compact per-line pills hugging text tightly with small radius',
        font_name     = 'Roboto Medium, Roboto, Arial, sans-serif',
        font_size     = 24,
        font_color    = 'FFFFFF',
        bold          = false,
        spacing       = 0.0,
        box_enabled   = true,
        box_mode      = 'per_line',
        box_color     = '080808',
        box_opacity   = 0.76,
        box_radius    = 6,
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
        bottom_margin = 24,
    },
    bbc_accessible = {
        id            = 'bbc_accessible',
        name          = 'Studio Accessible CC',
        icon          = '👁',
        desc          = 'High-contrast cadmium yellow on 95% solid black capsule (WCAG AAA)',
        font_name     = 'Atkinson Hyperlegible Bold, Atkinson Hyperlegible Next, Atkinson Hyperlegible, Arial, sans-serif',
        font_size     = 28,
        font_color    = 'FFFF00',     -- pure high-visibility yellow
        bold          = true,
        spacing       = 0.3,
        box_enabled   = true,
        box_mode      = 'per_line',
        box_color     = '000000',
        box_opacity   = 0.95,
        box_radius    = 8,
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
    hulu_white = {
        id            = 'hulu_white',
        name          = 'Hulu Signature',
        icon          = '📺',
        desc          = 'Clean boxless white text with a hairline stroke; minimal streaming clarity',
        font_name     = 'Switzer Medium, Schibsted Grotesk, Graphik, sans-serif',
        font_size     = 24,
        font_color    = 'FFFFFF',
        bold          = false,
        spacing       = 0.3,
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
        shadow_offset = 1.0,
        shadow_color  = '000000',
        padding_x     = 16,
        padding_y     = 6,
        line_spacing  = 4,
        bottom_margin = 26,
    },
    criterion_minimal = {
        id            = 'criterion_minimal',
        name          = 'Criterion Float',
        icon          = '⚪',
        desc          = 'Boxless pure typography with soft drop-shadow depth',
        font_name     = 'Cabin Medium, Gillius ADF No2, Gill Sans, sans-serif',
        font_size     = 24,
        font_color    = 'F7F7F7',
        bold          = false,
        spacing       = 0.4,
        box_enabled   = false,
        box_mode      = 'unified',
        box_color     = '000000',
        box_opacity   = 0.0,
        box_radius    = 0,
        glass_rim     = false,
        rim_color     = 'FFFFFF',
        rim_alpha     = 'D0',
        border_size   = 1.2,
        border_color  = '101010',
        shadow_offset = 1.4,
        shadow_color  = '000000',
        padding_x     = 16,
        padding_y     = 6,
        line_spacing  = 4,
        bottom_margin = 26,
    },
    mubi_minimal = {
        id            = 'mubi_minimal',
        name          = 'MUBI Arthouse',
        icon          = '🏛️',
        desc          = 'Compact, elegant European typography with non-intrusive footprint',
        font_name     = 'Satoshi Medium, Apercu, Inter, sans-serif',
        font_size     = 22,
        font_color    = 'ECECEC',
        bold          = false,
        spacing       = 0.3,
        box_enabled   = false,
        box_mode      = 'unified',
        box_color     = '000000',
        box_opacity   = 0.0,
        box_radius    = 0,
        glass_rim     = false,
        rim_color     = 'FFFFFF',
        rim_alpha     = 'D0',
        border_size   = 0.8,
        border_color  = '121212',
        shadow_offset = 1.0,
        shadow_color  = '000000',
        padding_x     = 14,
        padding_y     = 5,
        line_spacing  = 3,
        bottom_margin = 22,
    },
    cinema_gold = {
        id            = 'cinema_gold',
        name          = 'Theatrical Gold',
        icon          = '🍿',
        desc          = 'Warm amber cinema typography with delicate halo for dark-room viewing; boxless',
        font_name     = 'Jost Medium, Futura Medium, Futura, Trebuchet MS, sans-serif',
        font_size     = 25,
        font_color    = 'FFE675',
        bold          = false,
        spacing       = 0.3,
        box_enabled   = false,
        box_mode      = 'unified',
        box_color     = '000000',
        box_opacity   = 0.0,
        box_radius    = 0,
        glass_rim     = false,
        rim_color     = 'FFFFFF',
        rim_alpha     = 'D0',
        border_size   = 1.2,
        border_color  = '0A0A0A',
        shadow_offset = 1.2,
        shadow_color  = '000000',
        padding_x     = 18,
        padding_y     = 7,
        line_spacing  = 4,
        bottom_margin = 28,
    },
    film_print = {
        id            = 'film_print',
        name          = '35mm Film Print',
        icon          = '🎞️',
        desc          = 'Warm ivory typography with subtle halo separation for vintage film prints',
        font_name     = 'IBM Plex Sans Medium, Archivo SemiBold, Archivo, Univers, sans-serif',
        font_size     = 25,
        font_color    = 'F5EFE6',
        bold          = false,
        spacing       = 0.2,
        box_enabled   = false,
        box_mode      = 'unified',
        box_color     = '000000',
        box_opacity   = 0.0,
        box_radius    = 0,
        glass_rim     = false,
        rim_color     = 'FFFFFF',
        rim_alpha     = 'D0',
        border_size   = 1.2,
        border_color  = '101010',
        shadow_offset = 1.2,
        shadow_color  = '000000',
        padding_x     = 16,
        padding_y     = 6,
        line_spacing  = 4,
        bottom_margin = 28,
    },
    crunchyroll = {
        id            = 'crunchyroll',
        name          = 'Crunchyroll',
        icon          = '🟠',
        desc          = 'Clean white text with subtle stroke & drop-shadow; Crunchyroll web renderer style',
        font_name     = 'Plus Jakarta Sans SemiBold, Lexend Medium, Open Sans, sans-serif',
        font_size     = 26,
        font_color    = 'FFFFFF',
        bold          = false,
        spacing       = 0.2,
        box_enabled   = false,
        box_mode      = 'unified',
        box_color     = '000000',
        box_opacity   = 0.0,
        box_radius    = 0,
        glass_rim     = false,
        rim_color     = 'FFFFFF',
        rim_alpha     = 'D0',
        border_size   = 1.2,
        border_color  = '000000',
        shadow_offset = 1.8,
        shadow_color  = '000000',
        padding_x     = 16,
        padding_y     = 6,
        line_spacing  = 4,
        bottom_margin = 26,
    },
    anime_outline = {
        id            = 'anime_outline',
        name          = 'Anime Fansub',
        icon          = '⚔️',
        desc          = 'Bold white text with thick pitch-black contour; boxless',
        font_name     = 'Rubik, Trebuchet MS, Gandhi Sans, sans-serif',
        font_size     = 26,
        font_color    = 'FFFFFF',
        bold          = true,
        spacing       = 0.2,
        box_enabled   = false,
        box_mode      = 'unified',
        box_color     = '000000',
        box_opacity   = 0.0,
        box_radius    = 0,
        glass_rim     = false,
        rim_color     = 'FFFFFF',
        rim_alpha     = 'D0',
        border_size   = 3.0,
        border_color  = '000000',
        shadow_offset = 0.0,
        shadow_color  = '000000',
        padding_x     = 16,
        padding_y     = 6,
        line_spacing  = 3,
        bottom_margin = 22,
    },
    vlc_classic = {
        id            = 'vlc_classic',
        name          = 'VLC Classic',
        icon          = '📙',
        desc          = 'High-visibility yellow with solid black stroke; classic media player look',
        font_name     = 'Arimo Bold, Liberation Sans Bold, Liberation Sans, Arial, sans-serif',
        font_size     = 28,
        font_color    = 'FFFF00',
        bold          = true,
        spacing       = 0.0,
        box_enabled   = false,
        box_mode      = 'unified',
        box_color     = '000000',
        box_opacity   = 0.0,
        box_radius    = 0,
        glass_rim     = false,
        rim_color     = 'FFFFFF',
        rim_alpha     = 'D0',
        border_size   = 2.5,
        border_color  = '000000',
        shadow_offset = 1.0,
        shadow_color  = '000000',
        padding_x     = 16,
        padding_y     = 6,
        line_spacing  = 4,
        bottom_margin = 24,
    },
}

-- Default Active Subtitle Configuration (Initialized to Apple TV+ Glass)
local default_config = {
    preset        = 'apple_tv',
    font_name     = PRESETS.apple_tv.font_name,
    font_size     = PRESETS.apple_tv.font_size,
    font_color    = PRESETS.apple_tv.font_color,
    bold          = PRESETS.apple_tv.bold,
    spacing       = PRESETS.apple_tv.spacing or 0.2,
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
    visible       = true,
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
    local clean = str:gsub('\\[Nn]', '\n')
    clean = clean:gsub('{[^}]-}', '')
    clean = clean:gsub('<[^>]->', '')
    clean = clean:gsub('\\h', ' ')
    return clean
end

-- Sanitize a subtitle line for our overlay renderer:
-- Removes ASS layout-control tags that would override our own positioning,
-- rotation, scaling, and drawing commands — which cause vertical text on
-- OP/ED karaoke tracks. Preserves color, alpha, karaoke timing tags.
local LAYOUT_TAG_PATTERNS = {
    '\\pos%b()',          -- \pos(x,y)       overrides our ass:pos()
    '\\move%b()',         -- \move(...)       animated position
    '\\an%d',            -- \an1-9           overrides our ass:an(5)
    '\\a%d%d?',          -- \a1-11 (legacy alignment)
    '\\frz?%-?%d+%.?%d*',-- \frz / \fr       z-rotation (causes vertical text)
    '\\fry%-?%d+%.?%d*', -- \fry             y-axis rotation
    '\\frx%-?%d+%.?%d*', -- \frx             x-axis rotation
    '\\fscx%d+%.?%d*',   -- \fscx            x-scale distortion
    '\\fscy%d+%.?%d*',   -- \fscy            y-scale distortion
    '\\org%b()',          -- \org(x,y)        rotation origin
    '\\clip%b()',         -- \clip(...)       clipping rectangle
    '\\iclip%b()',        -- \iclip(...)      inverse clip
    '\\p%d+',            -- \p1 \p2 etc.     drawing mode (produces shapes not text)
    '\\pbo%-?%d+',       -- \pbo              drawing baseline offset
}

local function sanitize_sub_line(line, bord_w)
    if not line or line == '' then return line end
    -- Process each {…} override block:
    -- If it contains no backslash, it is a pure comment (e.g. {translator note}) -> strip completely
    local res = line:gsub('({[^}]*})', function(block)
        local inner = block:sub(2, -2)  -- strip surrounding { }
        if not inner:find('\\') then
            return '' -- strip editor/translator comments
        end
        for _, pat in ipairs(LAYOUT_TAG_PATTERNS) do
            inner = inner:gsub(pat, '')
        end
        if inner == '' or not inner:find('\\') then return '' end
        return '{' .. inner .. '}'
    end)
    -- When using thick contour borders (>= 2.0px), add non-breaking space buffers between words
    -- so thick black borders don't eat into the inter-word space and cause letters to collide
    if bord_w and bord_w >= 2.0 then
        res = res:gsub('([^} \t\r\n])([ \t]+)([^<{ \t\r\n])', '%1\\h %3')
    end
    return res
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

-- Soft-wrap subtitle text at word boundaries if dialogue exceeds safe zone width
local function wrap_line_if_needed(line, fs, is_bold, max_w)
    local w = estimate_text_width(strip_tags(line), fs, is_bold)
    if w <= max_w then return { line } end
    local words = {}
    for word in line:gmatch('%S+') do table.insert(words, word) end
    if #words <= 1 then return { line } end
    local wrapped = {}
    local cur_line = words[1]
    for i = 2, #words do
        local test_line = cur_line .. ' ' .. words[i]
        if estimate_text_width(strip_tags(test_line), fs, is_bold) <= max_w then
            cur_line = test_line
        else
            table.insert(wrapped, cur_line)
            cur_line = words[i]
        end
    end
    table.insert(wrapped, cur_line)
    return wrapped
end

-- Count UTF-8 characters (codepoints) in a string
local function utf8_char_count(str)
    if not str or str == '' then return 0 end
    local count = 0
    local i = 1
    local len = #str
    while i <= len do
        local b = str:byte(i)
        count = count + 1
        if b >= 0xF0 then i = i + 4
        elseif b >= 0xE0 then i = i + 3
        elseif b >= 0xC0 then i = i + 2
        else i = i + 1 end
    end
    return count
end

-- Detect and collapse vertical character stacks (common in anime OP/ED karaoke and vertical signs)
-- into natural horizontal lines, while strictly preserving normal multi-line dialogue.
local function collapse_vertical_text(text)
    if not text or text == '' then return text end

    local normalized = text:gsub('\\[Nn]', '\n'):gsub('\r\n', '\n'):gsub('\r', '\n')
    local lines = {}
    for line in (normalized .. '\n'):gmatch('(.-)\n') do
        table.insert(lines, line)
    end
    if #lines > 0 and lines[#lines] == '' then
        table.remove(lines)
    end
    if #lines < 4 then return normalized end

    local result_lines = {}
    local vertical_run = {}

    local function flush_vertical_run()
        if #vertical_run == 0 then return end
        if #vertical_run >= 4 then
            -- 4 or more consecutive single-character lines: collapse into a horizontal word/phrase
            local raw_chars = {}
            for _, l in ipairs(vertical_run) do
                local clean = strip_tags(l)
                local trimmed = clean:gsub('^%s+', ''):gsub('%s+$', '')
                if trimmed == '' then
                    table.insert(raw_chars, ' ')
                else
                    table.insert(raw_chars, trimmed)
                end
            end
            -- Deduplicate karaoke frame runs where the exact same character repeats >= 3 times
            -- (preserves normal double letters like 'll' in 'Hello')
            local collapsed = {}
            local i = 1
            while i <= #raw_chars do
                local ch = raw_chars[i]
                if ch ~= ' ' then
                    local run_len = 1
                    while i + run_len <= #raw_chars and raw_chars[i + run_len] == ch do
                        run_len = run_len + 1
                    end
                    if run_len >= 3 then
                        table.insert(collapsed, ch)
                        i = i + run_len
                    else
                        table.insert(collapsed, ch)
                        i = i + 1
                    end
                else
                    table.insert(collapsed, ' ')
                    i = i + 1
                end
            end
            local combined = table.concat(collapsed, ''):gsub('%s%s+', ' ')
            local trimmed = combined:gsub('^%s+', ''):gsub('%s+$', '')
            if #trimmed > 0 then
                table.insert(result_lines, trimmed)
            end
        else
            for _, l in ipairs(vertical_run) do
                table.insert(result_lines, l)
            end
        end
        vertical_run = {}
    end

    for _, line in ipairs(lines) do
        local clean = strip_tags(line)
        local trimmed = clean:gsub('^%s+', ''):gsub('%s+$', '')
        local ulen = utf8_char_count(trimmed)

        -- A vertical letter line is strictly 1 single character or empty line separator
        if ulen == 1 or trimmed == '' then
            table.insert(vertical_run, line)
        else
            flush_vertical_run()
            table.insert(result_lines, line)
        end
    end
    flush_vertical_run()

    return table.concat(result_lines, '\n')
end

M.collapse_vertical_text = collapse_vertical_text

-- ────────────────────────────────────────────────────────────────────────────
-- Anime OP / ED Native Rendering Fallback Engine
-- In anime opening & ending themes, Aegisub typesetting uses per-character \pos,
-- \k karaoke timing, special colors, animations, and graphic signs.
-- When inside an OP/ED segment, LuminaX yields directly to native MPV libass so
-- the song's original artistic animations and typography render flawlessly!
-- ────────────────────────────────────────────────────────────────────────────

local current_chapter_is_op_ed = false

local function check_is_op_ed_chapter()
    -- 1. Check current filename / path (for standalone NC OP / ED files)
    local fn = mp.get_property('filename', '')
    local fp = mp.get_property('path', '')
    local full_path = ((fp or '') .. '/' .. (fn or '')):lower()
    if full_path:find('/nc/op') or full_path:find('/nc/ed')
       or full_path:find('ncop') or full_path:find('nced')
       or full_path:find('creditless') then
        return true
    end

    -- 2. Check current chapter title
    local ch_idx = mp.get_property_number('chapter')
    if not ch_idx or ch_idx < 0 then
        return false
    end

    local chapters = mp.get_property_native('chapter-list', {})
    local cur_ch = chapters and chapters[ch_idx + 1]
    local title = cur_ch and cur_ch.title or mp.get_property('chapter-metadata/by-key/title')
    if title and title ~= '' then
        local lower = title:lower():gsub('^%s+', ''):gsub('%s+$', '')
        -- Strict story protection: Prologue & Epilogue are essential story beats, never skip
        if lower:find('%f[%a]prologue%f[%A]') or lower:find('%f[%a]epilogue%f[%A]') then
            return false
        end

        if lower:find('^%s*op%s*$') or lower:find('^%s*op%s*%d+%s*$')
           or lower:find('%f[%a]op%s*%d*%f[%A]')
           or lower:find('%f[%a]opening%f[%A]')
           or lower:find('%f[%a]intro%f[%A]')
           or lower:find('^%s*ed%s*$') or lower:find('^%s*ed%s*%d+%s*$')
           or lower:find('%f[%a]ed%s*%d*%f[%A]')
           or lower:find('%f[%a]ending%f[%A]')
           or lower:find('%f[%a]outro%f[%A]')
           or lower:find('%f[%a]credits%f[%A]')
           or lower:find('%f[%a]theme%f[%A]')
           or lower:find('%f[%a]ncop%f[%A]')
           or lower:find('%f[%a]nced%f[%A]') then
            if not lower:find('opening%s+scene') and not lower:find('operation') and not lower:find('^%s*end%s+of%f[%A]') then
                return true
            end
        end
    end
    return false
end

-- Heuristic to detect letter-by-letter vertical karaoke breakdown in unchaptered anime
local function is_karaoke_sub_stream(text)
    if not text or text == '' then return false end
    local count = 0
    local single_or_short = 0
    for line in text:gmatch('[^\r\n]+') do
        local clean = strip_tags(line)
        local trimmed = clean:gsub('^%s+', ''):gsub('%s+$', '')
        if #trimmed > 0 then
            count = count + 1
            local ulen = utf8_char_count(trimmed)
            if ulen <= 2 then
                single_or_short = single_or_short + 1
            end
        end
    end
    if count >= 4 and (single_or_short / count) >= 0.75 then
        return true
    end
    return false
end

local function is_op_ed_active(text)
    if current_chapter_is_op_ed then return true end
    if check_is_op_ed_chapter() then
        current_chapter_is_op_ed = true
        return true
    end
    if text and is_karaoke_sub_stream(text) then
        return true
    end
    return false
end

M.is_op_ed_active = is_op_ed_active
M.check_is_op_ed_chapter = check_is_op_ed_chapter
M.is_karaoke_sub_stream = is_karaoke_sub_stream

-- ────────────────────────────────────────────────────────────────────────────
-- Persistence (Save & Load Config)
-- ────────────────────────────────────────────────────────────────────────────

local function get_config_path()
    if config_file_path then return config_file_path end
    if ctx_ref and ctx_ref.config_file then
        config_file_path = ctx_ref.config_file
        return config_file_path
    end
    if mp and mp.command_native then
        local p = mp.command_native({'expand-path', '~~/script-opts/lumina_subtitle.json'})
        if p and p ~= '' and p ~= '~~/script-opts/lumina_subtitle.json' then
            config_file_path = p
            return p
        end
    end
    local xdg = os.getenv('XDG_CONFIG_HOME')
    if xdg and xdg ~= '' then
        config_file_path = xdg:gsub('[/\\]+$', '') .. '/mpv/script-opts/lumina_subtitle.json'
        return config_file_path
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
    local is_visible = (config.visible ~= false)

    if sub_off or not is_visible then
        if overlay then overlay:remove() end
        mp.set_property_bool('sub-visibility', false)
        if ctx_ref.request_tick then ctx_ref.request_tick() end
        return
    end

    if is_op_ed_active(current_sub_text) then
        if overlay then overlay:remove() end
        mp.set_property_bool('sub-visibility', false)
        if ctx_ref.request_tick then ctx_ref.request_tick() end
        return
    end

    if config.box_enabled then
        -- In pill overlay mode, visually hide native subtitles so only the rounded pill is drawn
        mp.set_property_bool('sub-visibility', false)
        M.update_overlay()
    else
        -- Boxless mode: hide native if we render via overlay, or sync native properties
        mp.set_property_bool('sub-visibility', false)
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
        pcall(mp.set_property, 'sub-spacing', tostring(config.spacing or 0.0))
        pcall(mp.set_property, 'sub-margin-y', tostring(config.bottom_margin or 26))
    end

    if ctx_ref.request_tick then ctx_ref.request_tick() end
end

local user_base_preset = 'apple_tv'
local auto_switched_anime = false
local user_overrode_preset = false
local tmdb_applied_for_file = false

-- Apply an industry-standard style preset
function M.apply_preset(preset_id, opts)
    local p = PRESETS[preset_id]
    if not p then return end
    config.preset = preset_id
    for k, v in pairs(p) do
        if k ~= 'id' and k ~= 'name' and k ~= 'desc' and k ~= 'icon' then
            config[k] = v
        end
    end
    local is_auto = opts and opts.is_auto
    local skip_save = opts and (opts.skip_save or is_auto)
    if not is_auto then
        user_base_preset = preset_id
        if tmdb_applied_for_file then
            user_overrode_preset = true
        end
    end
    M.apply_config(skip_save)
    if opts and opts.silent then return end

    if ctx_ref and ctx_ref.huds and ctx_ref.huds.show_pill then
        ctx_ref.huds.show_pill({
            key       = 'SUB PRESET',
            val       = string.format('%s (%dpt)', p.name, config.font_size or 24),
            icon      = '\238\129\136',
            val_color = 'FFFFFF',
            dur       = 2.0,
        })
    else
        mp.osd_message(string.format('%s  Preset: %s (%dpt)', p.icon or '✓', p.name, config.font_size), 2.0)
    end
end

-- ────────────────────────────────────────────────────────────────────────────
-- Rounded Rectangle Subtitle Overlay Renderer
-- ────────────────────────────────────────────────────────────────────────────

function M.update_overlay()
    if not overlay then return end

    -- Keep live preview active whenever user is actively inside a subtitle styling menu
    if ctx_ref and ctx_ref.state and ctx_ref.state.menu_active and ctx_ref.state.menu_active:find('^sub_') then
        live_preview_active = true
    end

    -- Check if screensaver is active (avoid obscuring TMDB backdrop art and synopsis)
    if not live_preview_active and ((ctx_ref.screensaver and ctx_ref.screensaver.is_active and ctx_ref.screensaver.is_active()) or
       (ctx_ref.state and ctx_ref.state.screensaver_active)) then
        overlay:remove()
        return
    end

    local sid = mp.get_property('sid')
    local sub_off = (sid == 'no' or sid == nil)
    local is_visible = (config.visible ~= false)

    if (sub_off or not is_visible) and not live_preview_active then
        if overlay then overlay:remove() end
        mp.set_property_bool('sub-visibility', false)
        return
    end

    local text_to_render = current_sub_text
    if live_preview_active and (text_to_render == '' or sub_off or not is_visible) then
        text_to_render = "The quick brown fox jumps over the lazy dog\nSample dialogue renders live in real time"
    end

    -- Anime OP / ED:
    -- When playing inside an OP / ED song segment or receiving karaoke letter breakdown,
    -- turn off subtitles completely to avoid karaoke artifacts, and resume on normal episode dialogue.
    if not live_preview_active and is_op_ed_active(text_to_render) then
        if overlay then overlay:remove() end
        mp.set_property_bool('sub-visibility', false)
        return
    else
        -- Regular dialogue: mute native libass and draw LuminaX's styled preset
        if not sub_off and is_visible then
            mp.set_property_bool('sub-visibility', false)
        end
    end

    if (text_to_render == '' or sub_off or not is_visible) and not live_preview_active then
        if overlay then overlay:remove() end
        return
    end

    -- Reference canvas: 720p virtual height for perfect ASS coordinate consistency
    local ow, oh = mp.get_osd_size()
    local dims = mp.get_property_native('osd-dimensions')
    local w = (dims and dims.w and dims.w > 0) and dims.w or (ow or 1280)
    local h = (dims and dims.h and dims.h > 0) and dims.h or (oh or 720)
    local aspect = (w > 0 and h > 0) and (w / h) or (16 / 9)
    local canvas_h = 720
    local canvas_w = math.floor(canvas_h * aspect + 0.5)

    -- Dynamic Font Scaling based on user sub-scale multiplier
    local scale_factor = current_sub_scale or 1.0
    local fs    = math.floor((config.font_size or 24) * scale_factor + 0.5)
    local is_bold = config.bold or false

    -- Video frame bounds & letterbox/pillarbox margins
    local mb = (dims and dims.mb) or 0
    local mt = (dims and dims.mt) or 0
    local ml = (dims and dims.ml) or 0
    local mr = (dims and dims.mr) or 0

    local scale_coord_y = canvas_h / (h > 0 and h or canvas_h)
    local scale_coord_x = canvas_w / (w > 0 and w or canvas_w)

    local v_mb = math.floor(mb * scale_coord_y + 0.5)
    local v_mt = math.floor(mt * scale_coord_y + 0.5)
    local v_ml = math.floor(ml * scale_coord_x + 0.5)
    local v_mr = math.floor(mr * scale_coord_x + 0.5)

    local active_video_w = canvas_w - (v_ml + v_mr)
    if active_video_w <= 0 then active_video_w = canvas_w end
    local cx = math.floor(v_ml + active_video_w / 2)

    -- Fullscreen safe zone: subtitle pill should never exceed 88% of active video width
    local max_safe_w = math.max(180, math.floor(active_video_w * 0.88))

    -- Process subtitle text lines with auto-wrapping if dialog exceeds safe zone
    local raw_lines = {}
    local norm_text = text_to_render:gsub('\\[Nn]', '\n'):gsub('\r\n', '\n'):gsub('\r', '\n')
    norm_text = collapse_vertical_text(norm_text)
    for line in norm_text:gmatch('[^\n]+') do
        local trimmed = line:gsub('^%s+', ''):gsub('%s+$', '')
        if #trimmed > 0 then
            local wrapped = wrap_line_if_needed(trimmed, fs, is_bold, max_safe_w)
            for _, wl in ipairs(wrapped) do
                table.insert(raw_lines, wl)
            end
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

    -- Determine baseline Y position (respecting sub-use-margins)
    local use_margins = mp.get_property_bool('sub-use-margins', false)
    local base_y = canvas_h
    if not use_margins and v_mb > 0 then
        -- Constrain inside active video frame rather than falling into black bar
        base_y = canvas_h - v_mb
    end

    -- Respect user sub-pos if customized
    local sub_pos = mp.get_property_number('sub-pos', 100)
    if sub_pos and sub_pos ~= 100 then
        base_y = math.floor(base_y * (sub_pos / 100.0) + 0.5)
    end

    -- Dynamic OSC Collision Avoidance
    -- If LuminaX bottom transport bar is visible, ensure subtitles float safely above seekbar
    if ctx_ref.state and ctx_ref.state.osc_visible then
        local osc_clearance = canvas_h - 78
        if base_y > osc_clearance then
            base_y = osc_clearance - 8
        end
    end
    base_y = math.floor(base_y + 0.5)

    local line_widths = {}
    local max_lw = 0
    for _, l in ipairs(raw_lines) do
        local clean_l = strip_tags(l)
        local lw = estimate_text_width(clean_l, fs, is_bold)
        table.insert(line_widths, lw)
        if lw > max_lw then max_lw = lw end
    end

    -- Geometric/grotesque fonts (Outfit, Geist, General Sans, Figtree…) are ~12%
    -- narrower than the generic per-character estimates above. Apply a correction
    -- factor to the pill-sizing values only — the wrapping pass above intentionally
    -- keeps the wider (conservative) estimate to avoid under-wrapping.
    local PILL_W_CORRECTION = 0.93
    for i = 1, #line_widths do
        line_widths[i] = math.ceil(line_widths[i] * PILL_W_CORRECTION)
    end
    max_lw = math.ceil(max_lw * PILL_W_CORRECTION)

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

    local font_face = get_primary_font(config.font_name)

    local raw_r     = config.box_radius or 14
    local scaled_r  = (raw_r == -1) and -1 or math.floor(raw_r * scale_factor + 0.5)
    local fsp_val   = string.format('%.1f', (config.spacing or 0.0) * scale_factor)

    if config.box_enabled and config.box_mode == 'per_line' then
        -- ────────────────────────────────────────────────────────────────────
        -- 1. Per-Line Pill Rendering (YouTube Studio / Netflix / BBC CC)
        -- ────────────────────────────────────────────────────────────────────
        local gap = math.max(3, math.floor(line_sp * 0.7))
        local line_box_h = line_h + pad_y * 2
        local total_h = (total_lines * line_box_h) + ((total_lines - 1) * gap)
        local start_y = base_y - margin_y - total_h

        for i, line in ipairs(raw_lines) do
            local lw   = line_widths[i] or max_lw
            local pw   = lw + pad_x * 2
            local ph   = line_box_h
            local r    = (scaled_r == -1) and math.floor(ph / 2) or math.min(scaled_r, math.floor(ph / 2))
            local ly0  = start_y + (i - 1) * (ph + gap)
            local ly1  = ly0 + ph
            local lx0  = cx - math.floor(pw / 2)
            local lx1  = cx + math.floor(pw / 2)

            -- Background Pill (rim border only emitted when glass_rim is active)
            ass:new_event()
            ass:pos(0, 0)
            ass:an(7)
            if rim_w > 0 then
                ass:append(string.format('{\\blur0\\bord%.1f\\1c%s\\1a&H%s&\\3c%s\\3a&H%s&}',
                    rim_w, box_bgr, box_a, rim_bgr, rim_a))
            else
                ass:append(string.format('{\\blur0\\bord0\\1c%s\\1a&H%s&}',
                    box_bgr, box_a))
            end
            ass:draw_start()
            ass:round_rect_cw(lx0, ly0, lx1, ly1, r)
            ass:draw_stop()

            -- Text inside line pill
            local text_cy = ly0 + math.floor(ph / 2)
            ass:new_event()
            ass:pos(cx, text_cy)
            ass:an(5)
            ass:append(string.format('{\\fn%s\\fs%d%s\\1c%s\\1a&H00&\\bord%s\\3c%s\\3a&H00&\\shad%s\\4c%s\\4a&H80&\\fsp%s\\q2}',
                font_face, fs, is_bold and '\\b700' or '\\b400',
                txt_bgr, tostring(bord_w), bord_bgr, tostring(shad_off), shad_bgr, fsp_val))
            ass:append(sanitize_sub_line(line, bord_w))
        end

    elseif config.box_enabled then
        -- ────────────────────────────────────────────────────────────────────
        -- 2. Unified Pill Rendering (Apple TV+ / Cinema Gold / Disney+)
        -- ────────────────────────────────────────────────────────────────────
        local pill_w = max_lw + pad_x * 2
        -- Subtract one trailing line_sp: line_h = ceil(fs*1.18 + line_sp), so N lines
        -- have N trailing gaps baked in; the last one overshoots into bottom padding.
        local pill_h = (total_lines * line_h) - line_sp + pad_y * 2
        local r      = (scaled_r == -1) and math.floor(pill_h / 2) or math.min(scaled_r, math.floor(pill_h / 2))

        local y1     = base_y - margin_y
        local y0     = y1 - pill_h
        local x0     = cx - math.floor(pill_w / 2)
        local x1     = cx + math.floor(pill_w / 2)

        -- Background Capsule (rim border only emitted when glass_rim is active)
        ass:new_event()
        ass:pos(0, 0)
        ass:an(7)
        if rim_w > 0 then
            ass:append(string.format('{\\blur0\\bord%.1f\\1c%s\\1a&H%s&\\3c%s\\3a&H%s&}',
                rim_w, box_bgr, box_a, rim_bgr, rim_a))
        else
            ass:append(string.format('{\\blur0\\bord0\\1c%s\\1a&H%s&}',
                box_bgr, box_a))
        end
        ass:draw_start()
        ass:round_rect_cw(x0, y0, x1, y1, r)
        ass:draw_stop()

        -- Text Lines inside unified capsule
        for i, line in ipairs(raw_lines) do
            local text_cy = y0 + pad_y + math.floor((i - 0.5) * line_h)
            ass:new_event()
            ass:pos(cx, text_cy)
            ass:an(5)
            ass:append(string.format('{\\fn%s\\fs%d%s\\1c%s\\1a&H00&\\bord%s\\3c%s\\3a&H00&\\shad%s\\4c%s\\4a&H80&\\fsp%s\\q2}',
                font_face, fs, is_bold and '\\b700' or '\\b400',
                txt_bgr, tostring(bord_w), bord_bgr, tostring(shad_off), shad_bgr, fsp_val))
            ass:append(sanitize_sub_line(line, bord_w))
        end

    else
        -- ────────────────────────────────────────────────────────────────────
        -- 3. Boxless Typography (Anime Fansub / Criterion Float)
        -- ────────────────────────────────────────────────────────────────────
        local total_h = total_lines * line_h
        local y1      = base_y - margin_y
        local y0      = y1 - total_h

        for i, line in ipairs(raw_lines) do
            local text_cy = y0 + math.floor((i - 0.5) * line_h)
            ass:new_event()
            ass:pos(cx, text_cy)
            ass:an(5)
            ass:append(string.format('{\\fn%s\\fs%d%s\\1c%s\\1a&H00&\\bord%s\\3c%s\\3a&H00&\\shad%s\\4c%s\\4a&H90&\\fsp%s\\q2}',
                font_face, fs, is_bold and '\\b700' or '\\b400',
                txt_bgr, tostring(bord_w), bord_bgr, tostring(shad_off), shad_bgr, fsp_val))
            ass:append(sanitize_sub_line(line, bord_w))
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
    local msg = string.format('Sub Size: %dpt (%d%%)', eff_fs, math.floor(new_val * 100))
    if ctx_ref.huds and ctx_ref.huds.show_pill then
        ctx_ref.huds.show_pill('\238\129\136', msg)
    else
        mp.osd_message(msg, 1.5)
    end
end

function M.reset_sub_scale()
    pcall(mp.set_property_number, 'sub-scale', 1.0)
    current_sub_scale = 1.0
    M.update_overlay()
    local msg = string.format('Sub Size: %dpt (100%%)', config.font_size or 24)
    if ctx_ref.huds and ctx_ref.huds.show_pill then
        ctx_ref.huds.show_pill('\238\129\136', msg)
    else
        mp.osd_message(msg, 1.5)
    end
end

function M.toggle_visibility()
    config.visible = not (config.visible ~= false)
    save_config()
    if config.visible then
        M.update_overlay()
    else
        if overlay then overlay:remove() end
    end
    local msg = config.visible and 'Subtitles: Visible' or 'Subtitles: Hidden'
    if ctx_ref.huds and ctx_ref.huds.show_pill then
        ctx_ref.huds.show_pill('\238\129\136', msg)
    else
        mp.osd_message(msg, 1.5)
    end
    if ctx_ref.request_tick then ctx_ref.request_tick() end
end

function M.is_visible()
    return config.visible ~= false
end

-- Automatic Animation Detection Handler (Switches to Anime Fansub on anime, restores base preset on live action)
function M.on_tmdb_loaded(data)
    if not data or not data.genres then return end
    local auto_opt = ctx_ref.user_opts and ctx_ref.user_opts.sub_auto_anime_preset
    if auto_opt == false or auto_opt == 'no' or auto_opt == 'off' then return end

    if user_overrode_preset then
        -- User explicitly selected a preset during playback; do not clobber on pause/events
        return
    end

    tmdb_applied_for_file = true

    local g = tostring(data.genres):lower()
    local is_anime = g:find('animation') or g:find('anime')

    if is_anime then
        if config.preset ~= 'anime_outline' then
            auto_switched_anime = true
            M.apply_preset('anime_outline', { skip_save = true, is_auto = true })
        end
    else
        -- Non-anime title (e.g. live-action drama / comedy like Sheep Detective)
        if auto_switched_anime or (config.preset == 'anime_outline' and user_base_preset ~= 'anime_outline') then
            auto_switched_anime = false
            local restore = (user_base_preset and user_base_preset ~= 'anime_outline') and user_base_preset or 'apple_tv'
            M.apply_preset(restore, { skip_save = true, is_auto = true })
        end
    end
end

-- ────────────────────────────────────────────────────────────────────────────
-- Module Lifecycle & Event Listeners
-- ────────────────────────────────────────────────────────────────────
function M.init(ctx)
    ctx_ref = ctx or {}
    user_overrode_preset = false
    tmdb_applied_for_file = false
    overlay = mp.create_osd_overlay('ass-events')

    -- Read configured font size from mpv.conf if set
    local cfg_fs = mp.get_property_number('sub-font-size')
    if cfg_fs and cfg_fs > 0 then
        mpv_conf_sub_font_size = cfg_fs
    end

    current_sub_scale = mp.get_property_number('sub-scale', 1.0)

    load_saved_config()

    -- Reset temporary auto-switched anime preset and re-check OP/ED when switching files
    if mp.register_event then
        mp.register_event('start-file', function()
            user_overrode_preset = false
            tmdb_applied_for_file = false
            current_chapter_is_op_ed = check_is_op_ed_chapter()
            if auto_switched_anime then
                auto_switched_anime = false
                local restore = (user_base_preset and user_base_preset ~= 'anime_outline') and user_base_preset or 'apple_tv'
                M.apply_preset(restore, { skip_save = true, is_auto = true, silent = true })
            end
        end)
    end

    -- Observe chapter boundaries to switch seamlessly between native MPV libass and LuminaX presets
    mp.observe_property('chapter', 'number', function()
        current_chapter_is_op_ed = check_is_op_ed_chapter()
        M.update_overlay()
    end)
    mp.observe_property('chapter-list', nil, function()
        current_chapter_is_op_ed = check_is_op_ed_chapter()
        M.update_overlay()
    end)

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

    -- Observe fullscreen state transitions
    mp.observe_property('fullscreen', 'bool', function()
        M.update_overlay()
    end)

    -- Observe letterbox margin behavior setting
    mp.observe_property('sub-use-margins', 'bool', function()
        M.update_overlay()
    end)

    -- Observe vertical position setting
    mp.observe_property('sub-pos', 'number', function()
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

    -- Bind 'v' to toggle our custom subtitle pill visibility
    pcall(mp.add_forced_key_binding, 'v', 'toggle-sub-visibility', M.toggle_visibility)

    -- Allow programmatic preset switching via IPC or external triggers
    mp.register_script_message('sub-apply-preset', function(pid)
        if pid and pid ~= '' then
            M.apply_preset(pid)
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

local live_preview_timer = nil

function M.set_live_preview(active)
    if live_preview_timer then
        live_preview_timer:kill()
        live_preview_timer = nil
    end
    live_preview_active = active
    M.update_overlay()
end

local active_customize_tab = 'pill'

function M.get_active_tab()
    return active_customize_tab
end

function M.set_active_tab(tab)
    active_customize_tab = tab
end

function M.next_tab()
    -- Backward compatibility stub
end

function M.prev_tab()
    -- Backward compatibility stub
end

function M.cycle_tab()
    -- Backward compatibility stub
end

-- ────────────────────────────────────────────────────────────────────────────
-- Industry Presets, Color Palette & Stepper Definitions
-- ────────────────────────────────────────────────────────────────────────────

local PRESET_IDS = {
    'apple_tv',
    'netflix_box',
    'prime_video',
    'disney_slate',
    'hbo_max',
    'youtube_cc',
    'bbc_accessible',
    'hulu_white',
    'criterion_minimal',
    'mubi_minimal',
    'cinema_gold',
    'film_print',
    'crunchyroll',
    'anime_outline',
    'vlc_classic',
}

local COLOR_PALETTE = {
    { hex = 'FFFFFF', name = 'Pure White' },
    { hex = 'FFE675', name = 'Warm Gold' },
    { hex = 'FFFF00', name = 'Studio Yellow' },
    { hex = 'F7F7F7', name = 'Ivory White' },
    { hex = '00F0FF', name = 'Sky Cyan' },
    { hex = 'A8F0D0', name = 'Soft Mint' },
    { hex = 'FF9E80', name = 'Warm Coral' },
}

local RADIUS_OPTIONS = {
    { val = 0,  name = '0px (Square)' },
    { val = 5,  name = '5px (YouTube)' },
    { val = 7,  name = '7px (Netflix)' },
    { val = 8,  name = '8px (Prime)' },
    { val = 10, name = '10px (Disney+)' },
    { val = 14, name = '14px (Medium)' },
    { val = 18, name = '18px (Spacious)' },
    { val = -1, name = 'Capsule (Full)' },
}

function M.get_color_info(hex)
    local target = (hex or 'FFFFFF'):upper():gsub('#', '')
    for _, c in ipairs(COLOR_PALETTE) do
        if c.hex:upper() == target then
            return c
        end
    end
    return { hex = target, name = '#' .. target }
end

-- ────────────────────────────────────────────────────────────────────────────
-- Dirty State Tracking
-- ────────────────────────────────────────────────────────────────────────────

function M.is_preset_dirty()
    local p = PRESETS[config.preset]
    if not p then return true end
    if config.font_size ~= p.font_size then return true end
    if (config.font_color or ''):upper() ~= (p.font_color or ''):upper() then return true end
    if (config.bold or false) ~= (p.bold or false) then return true end
    if (config.box_enabled or false) ~= (p.box_enabled or false) then return true end
    if config.box_mode ~= p.box_mode then return true end
    if math.abs((config.box_opacity or 0) - (p.box_opacity or 0)) > 0.02 then return true end
    if (config.box_radius or 0) ~= (p.box_radius or 0) then return true end
    if (config.glass_rim or false) ~= (p.glass_rim or false) then return true end
    if math.abs((config.border_size or 0) - (p.border_size or 0)) > 0.05 then return true end
    if math.abs((config.shadow_offset or 0) - (p.shadow_offset or 0)) > 0.05 then return true end
    if (config.padding_x or 0) ~= (p.padding_x or 0) then return true end
    if (config.padding_y or 0) ~= (p.padding_y or 0) then return true end
    if (config.line_spacing or 0) ~= (p.line_spacing or 0) then return true end
    if (config.bottom_margin or 0) ~= (p.bottom_margin or 0) then return true end
    if math.abs((config.spacing or 0) - (p.spacing or 0)) > 0.05 then return true end
    return false
end

-- ────────────────────────────────────────────────────────────────────────────
-- In-Place Stepper Action Handlers
-- ────────────────────────────────────────────────────────────────────────────

function M.cycle_preset(dir)
    local cur_id = config.preset or 'apple_tv'
    local cur_idx = 1
    for i, pid in ipairs(PRESET_IDS) do
        if pid == cur_id then
            cur_idx = i
            break
        end
    end
    local next_idx = ((cur_idx - 1 + dir) % #PRESET_IDS) + 1
    M.apply_preset(PRESET_IDS[next_idx])
end

function M.step_font_size(delta)
    local cur = config.font_size or 24
    local nxt = math.max(14, math.min(48, cur + delta))
    config.font_size = nxt
    M.apply_config()
    local eff_fs = math.floor(nxt * (current_sub_scale or 1.0) + 0.5)
    mp.osd_message(string.format('✓ Font Size: %dpt', eff_fs), 1.5)
end

function M.cycle_box_mode(dir)
    local cur_state = 1
    if not config.box_enabled then
        cur_state = 3
    elseif config.box_mode == 'per_line' then
        cur_state = 2
    else
        cur_state = 1
    end
    local nxt = ((cur_state - 1 + dir) % 3) + 1
    if nxt == 1 then
        config.box_enabled = true
        config.box_mode = 'unified'
        mp.osd_message('✓ Box Mode: Unified Pill', 1.5)
    elseif nxt == 2 then
        config.box_enabled = true
        config.box_mode = 'per_line'
        mp.osd_message('✓ Box Mode: Per-Line Pills', 1.5)
    else
        config.box_enabled = false
        mp.osd_message('✓ Box Mode: Disabled (Boxless)', 1.5)
    end
    M.apply_config()
end

function M.step_box_opacity(delta)
    local cur = config.box_opacity or 0.70
    local nxt = math.floor((cur + delta) * 100 + 0.5) / 100
    nxt = math.max(0.0, math.min(1.0, nxt))
    config.box_opacity = nxt
    M.apply_config()
    mp.osd_message(string.format('✓ Box Opacity: %d%%', math.floor(nxt * 100 + 0.5)), 1.5)
end

function M.cycle_box_radius(dir)
    local cur = config.box_radius or 14
    local best_idx = 6
    local min_diff = 999
    for i, r in ipairs(RADIUS_OPTIONS) do
        if r.val == cur then
            best_idx = i
            break
        else
            local diff = math.abs(r.val - cur)
            if diff < min_diff then
                min_diff = diff
                best_idx = i
            end
        end
    end
    local nxt = ((best_idx - 1 + dir) % #RADIUS_OPTIONS) + 1
    config.box_radius = RADIUS_OPTIONS[nxt].val
    M.apply_config()
    mp.osd_message('✓ Curvature: ' .. RADIUS_OPTIONS[nxt].name, 1.5)
end

function M.cycle_font_color(dir)
    local cur = (config.font_color or 'FFFFFF'):upper():gsub('#', '')
    local cur_idx = 1
    for i, c in ipairs(COLOR_PALETTE) do
        if c.hex:upper() == cur then
            cur_idx = i
            break
        end
    end
    local next_idx = ((cur_idx - 1 + dir) % #COLOR_PALETTE) + 1
    config.font_color = COLOR_PALETTE[next_idx].hex
    M.apply_config()
    mp.osd_message(string.format('✓ Subtitle Color: %s (#%s)', COLOR_PALETTE[next_idx].name, config.font_color), 1.5)
end

function M.step_bottom_margin(delta)
    local cur = config.bottom_margin or 26
    local nxt = math.max(8, math.min(80, cur + delta))
    config.bottom_margin = nxt
    M.apply_config()
    mp.osd_message(string.format('✓ Vertical Position: Bottom %dpx', nxt), 1.5)
end

function M.toggle_glass_rim()
    config.glass_rim = not config.glass_rim
    M.apply_config()
    mp.osd_message(config.glass_rim and '✓ Glass Rim Highlight: On' or '✓ Glass Rim Highlight: Off', 1.5)
end

function M.step_border_size(delta)
    local cur = config.border_size or 0
    local nxt = math.max(0.0, math.min(4.0, math.floor((cur + delta) * 10 + 0.5) / 10))
    config.border_size = nxt
    M.apply_config()
    mp.osd_message(string.format('✓ Outline Stroke: %.1fpx', nxt), 1.5)
end

function M.step_shadow_offset(delta)
    local cur = config.shadow_offset or 0
    local nxt = math.max(0.0, math.min(4.0, math.floor((cur + delta) * 10 + 0.5) / 10))
    config.shadow_offset = nxt
    M.apply_config()
    mp.osd_message(string.format('✓ Drop Shadow: %.1fpx', nxt), 1.5)
end

function M.step_padding(key, delta)
    if key == 'padding_x' then
        local cur = config.padding_x or 18
        local nxt = math.max(8, math.min(36, cur + delta))
        config.padding_x = nxt
        mp.osd_message(string.format('✓ Horizontal Padding: %dpx', nxt), 1.5)
    else
        local cur = config.padding_y or 7
        local nxt = math.max(2, math.min(20, cur + delta))
        config.padding_y = nxt
        mp.osd_message(string.format('✓ Vertical Padding: %dpx', nxt), 1.5)
    end
    M.apply_config()
end

function M.step_line_spacing(delta)
    local cur = config.line_spacing or 4
    local nxt = math.max(0, math.min(16, cur + delta))
    config.line_spacing = nxt
    M.apply_config()
    mp.osd_message(string.format('✓ Line Spacing: %+dpx', nxt), 1.5)
end

function M.step_spacing(delta)
    local cur = config.spacing or 0.0
    local nxt = math.floor((math.max(0.0, math.min(1.5, cur + delta))) * 10 + 0.5) / 10
    config.spacing = nxt
    M.apply_config()
    mp.osd_message(string.format('✓ Tracking (Spacing): %+.1f', nxt), 1.5)
end

function M.toggle_bold()
    config.bold = not config.bold
    M.apply_config()
    mp.osd_message(config.bold and '✓ Font Weight: Bold' or '✓ Font Weight: Regular', 1.5)
end

function M.toggle_sub_use_margins()
    local cur = mp.get_property_bool('sub-use-margins', false)
    local nxt = not cur
    pcall(mp.set_property_bool, 'sub-use-margins', nxt)
    M.update_overlay()
    mp.osd_message(nxt and '✓ Letterbox: Black Bars Allowed' or '✓ Letterbox: Inside Frame', 1.5)
end

function M.reset_defaults()
    local target_preset = config.preset
    if not PRESETS[target_preset] then
        target_preset = 'apple_tv'
    end
    M.apply_preset(target_preset)
    mp.osd_message('✓ Reset to ' .. PRESETS[target_preset].name .. ' Defaults', 2.0)
end

function M.step_sub_delay(delta)
    local cur = mp.get_property_number('sub-delay', 0.0) or 0.0
    local nxt = math.floor((cur + delta) * 10 + 0.5) / 10
    pcall(mp.set_property_number, 'sub-delay', nxt)
    if ctx_ref.request_tick then ctx_ref.request_tick() end
end

function M.reset_sub_delay()
    pcall(mp.set_property_number, 'sub-delay', 0.0)
    if ctx_ref.request_tick then ctx_ref.request_tick() end
end

-- ────────────────────────────────────────────────────────────────────────────
-- Subtitle Configuration Menu Data & Generators
-- ────────────────────────────────────────────────────────────────────────────

function M.get_menu_title(menu_type)
    if menu_type == 'sub_config' then
        return 'SUBTITLE STYLING'
    elseif menu_type == 'sub_presets' then
        return 'STYLE PRESETS'
    elseif menu_type == 'sub_advanced' or menu_type == 'sub_customize' then
        return 'ADVANCED TUNING'
    elseif menu_type and menu_type:find('^sub_') then
        return 'SUBTITLE SETTINGS'
    end
    return nil
end

function M.get_menu_items(menu_type)
    local items = {}
    local eff_fs = math.floor((config.font_size or 24) * current_sub_scale + 0.5)

    if menu_type == 'sub_config' then
        -- ── Level 1 & Level 2: In-Place Steppers (Accessible Flat Layout) ────

        -- 1. Style Presets (Instant Gratification & Expandable)
        local cur_p = PRESETS[config.preset] or PRESETS.apple_tv
        local dirty = M.is_preset_dirty()
        local preset_display = string.format('%s%s', cur_p.name, dirty and ' (Customized)' or '')

        items[#items + 1] = {
            label    = 'Style Presets',
            value    = preset_display,
            type     = 'stepper',
            on_prev  = function() M.cycle_preset(-1) end,
            on_next  = function() M.cycle_preset(1) end,
            action   = 'nav_menu',
            target   = 'sub_presets',
            index    = #items + 1,
        }

        -- 2. Text Size (Stepper ±2pt)
        items[#items + 1] = {
            label    = 'Text Size',
            value    = string.format('%d pt', eff_fs),
            type     = 'stepper',
            on_prev  = function() M.step_font_size(-2) end,
            on_next  = function() M.step_font_size(2) end,
            index    = #items + 1,
        }

        -- 3. Background Box (Unified Pill / Per-Line / Off)
        local box_val = 'Unified Pill'
        if not config.box_enabled then
            box_val = 'Off (Boxless)'
        elseif config.box_mode == 'per_line' then
            box_val = 'Per-Line'
        end
        items[#items + 1] = {
            label    = 'Background Box',
            value    = box_val,
            type     = 'stepper',
            on_prev  = function() M.cycle_box_mode(-1) end,
            on_next  = function() M.cycle_box_mode(1) end,
            index    = #items + 1,
        }

        -- 4. Box Opacity (Stepper ±5%)
        items[#items + 1] = {
            label    = 'Box Opacity',
            value    = string.format('%d%%', math.floor((config.box_opacity or 0.70) * 100 + 0.5)),
            type     = 'stepper',
            on_prev  = function() M.step_box_opacity(-0.05) end,
            on_next  = function() M.step_box_opacity(0.05) end,
            index    = #items + 1,
        }

        -- 5. Corner Radius (Stepper)
        local rad_val = '14px (Medium)'
        for _, r in ipairs(RADIUS_OPTIONS) do
            if r.val == config.box_radius then
                rad_val = r.name
                break
            end
        end
        items[#items + 1] = {
            label    = 'Corner Radius',
            value    = rad_val,
            type     = 'stepper',
            on_prev  = function() M.cycle_box_radius(-1) end,
            on_next  = function() M.cycle_box_radius(1) end,
            index    = #items + 1,
        }

        -- 6. Text Color (Stepper with swatch)
        local col_info = M.get_color_info(config.font_color)
        items[#items + 1] = {
            label     = 'Text Color',
            value     = col_info.name,
            color_hex = col_info.hex,
            type      = 'stepper',
            on_prev   = function() M.cycle_font_color(-1) end,
            on_next   = function() M.cycle_font_color(1) end,
            index     = #items + 1,
        }

        -- 7. Vertical Position (Stepper ±4px)
        items[#items + 1] = {
            label    = 'Vertical Position',
            value    = string.format('Bottom %dpx', config.bottom_margin or 26),
            type     = 'stepper',
            on_prev  = function() M.step_bottom_margin(-4) end,
            on_next  = function() M.step_bottom_margin(4) end,
            index    = #items + 1,
        }

        -- 8. Subtitle Delay / Audio Sync (Stepper ±0.1s / 100ms)
        local cur_delay = mp.get_property_number('sub-delay', 0.0) or 0.0
        local delay_display = 'Synced (0 ms)'
        if math.abs(cur_delay) >= 0.005 then
            delay_display = string.format('%+.1f s (%+d ms)', cur_delay, math.floor(cur_delay * 1000 + 0.5))
        end
        items[#items + 1] = {
            label    = 'Subtitle Delay',
            value    = delay_display,
            type     = 'stepper',
            on_prev  = function() M.step_sub_delay(-0.1) end,
            on_next  = function() M.step_sub_delay(0.1) end,
            action   = 'reset_delay',
            index    = #items + 1,
        }

        -- 9. Advanced Tuning... (Level 3 Deep Customizer)
        items[#items + 1] = {
            label    = 'Advanced Tuning...',
            value    = '',
            type     = 'action',
            action   = 'nav_menu',
            target   = 'sub_advanced',
            index    = #items + 1,
        }

        -- 10. Reset to Defaults
        items[#items + 1] = {
            label    = 'Reset to Defaults',
            value    = '',
            type     = 'action',
            action   = 'reset_defaults',
            index    = #items + 1,
        }

    elseif menu_type == 'sub_presets' then
        -- ── Full 10 Industry Style Presets Gallery ──────────────────────────
        for _, pid in ipairs(PRESET_IDS) do
            local p = PRESETS[pid]
            if p then
                local is_cur = (config.preset == pid) and not M.is_preset_dirty()
                items[#items + 1] = {
                    label     = p.name,
                    value     = is_cur and 'Active' or '',
                    current   = is_cur,
                    type      = 'action',
                    action    = 'apply_preset',
                    preset_id = pid,
                    index     = #items + 1,
                }
            end
        end

        items[#items + 1] = {
            label  = 'Back to Styling (ESC)',
            value  = '',
            type   = 'action',
            action = 'nav_menu',
            target = 'sub_config',
            index  = #items + 1,
        }

    elseif menu_type == 'sub_advanced' or menu_type == 'sub_customize' then
        -- ── Level 3: Deep Customizer Submenu ────────────────────────────────

        -- 1. Glass Rim Highlight
        items[#items + 1] = {
            label    = 'Glass Rim Highlight',
            value    = config.glass_rim and 'On' or 'Off',
            type     = 'stepper',
            on_prev  = function() M.toggle_glass_rim() end,
            on_next  = function() M.toggle_glass_rim() end,
            index    = #items + 1,
        }

        -- 2. Outline / Stroke Width
        items[#items + 1] = {
            label    = 'Outline Stroke',
            value    = string.format('%.1fpx', config.border_size or 0),
            type     = 'stepper',
            on_prev  = function() M.step_border_size(-0.5) end,
            on_next  = function() M.step_border_size(0.5) end,
            index    = #items + 1,
        }

        -- 3. Drop Shadow Depth
        items[#items + 1] = {
            label    = 'Drop Shadow',
            value    = string.format('%.1fpx', config.shadow_offset or 0),
            type     = 'stepper',
            on_prev  = function() M.step_shadow_offset(-0.5) end,
            on_next  = function() M.step_shadow_offset(0.5) end,
            index    = #items + 1,
        }

        -- 4. Horizontal Padding
        items[#items + 1] = {
            label    = 'Horizontal Padding',
            value    = string.format('%dpx', config.padding_x or 18),
            type     = 'stepper',
            on_prev  = function() M.step_padding('padding_x', -2) end,
            on_next  = function() M.step_padding('padding_x', 2) end,
            index    = #items + 1,
        }

        -- 5. Vertical Padding
        items[#items + 1] = {
            label    = 'Vertical Padding',
            value    = string.format('%dpx', config.padding_y or 7),
            type     = 'stepper',
            on_prev  = function() M.step_padding('padding_y', -1) end,
            on_next  = function() M.step_padding('padding_y', 1) end,
            index    = #items + 1,
        }

        -- 6. Line Spacing
        items[#items + 1] = {
            label    = 'Line Spacing',
            value    = string.format('%+dpx', config.line_spacing or 4),
            type     = 'stepper',
            on_prev  = function() M.step_line_spacing(-1) end,
            on_next  = function() M.step_line_spacing(1) end,
            index    = #items + 1,
        }

        -- 7. Letter Spacing (Tracking)
        items[#items + 1] = {
            label    = 'Letter Spacing',
            value    = string.format('%+.1f', config.spacing or 0.0),
            type     = 'stepper',
            on_prev  = function() M.step_spacing(-0.1) end,
            on_next  = function() M.step_spacing(0.1) end,
            index    = #items + 1,
        }

        -- 8. Font Weight (Bold)
        items[#items + 1] = {
            label    = 'Font Weight',
            value    = config.bold and 'Bold' or 'Regular',
            type     = 'stepper',
            on_prev  = function() M.toggle_bold() end,
            on_next  = function() M.toggle_bold() end,
            index    = #items + 1,
        }

        -- 9. Letterbox Margins
        local use_margins = mp.get_property_bool('sub-use-margins', false)
        items[#items + 1] = {
            label    = 'Letterbox Margins',
            value    = use_margins and 'Black Bars' or 'Inside Frame',
            type     = 'stepper',
            on_prev  = function() M.toggle_sub_use_margins() end,
            on_next  = function() M.toggle_sub_use_margins() end,
            index    = #items + 1,
        }

        -- 10. Back to Styling
        items[#items + 1] = {
            label  = 'Back to Styling (ESC)',
            value  = '',
            type   = 'action',
            action = 'nav_menu',
            target = 'sub_config',
            index  = #items + 1,
        }
    end

    return items
end

-- ────────────────────────────────────────────────────────────────────────────
-- Handle Subtitle Menu Action Dispatcher
-- ────────────────────────────────────────────────────────────────────────────

function M.handle_action(item)
    if not item or not item.action then return end

    if item.action == 'apply_preset' and item.preset_id then
        M.apply_preset(item.preset_id)

    elseif item.action == 'reset_defaults' then
        M.reset_defaults()

    elseif item.action == 'toggle_visibility' then
        M.toggle_visibility()

    elseif item.action == 'toggle_sub_use_margins' then
        M.toggle_sub_use_margins()

    elseif item.action == 'scale_up' then
        M.add_sub_scale(0.10)

    elseif item.action == 'scale_down' then
        M.add_sub_scale(-0.10)

    elseif item.action == 'reset_delay' then
        M.reset_sub_delay()

    elseif item.action == 'scale_reset' then
        M.reset_sub_scale()
    end
end

return M

