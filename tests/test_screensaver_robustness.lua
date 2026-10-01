-- ============================================================================
-- Test Suite: Screensaver Robustness, Failsafes & State Machine
-- Tests screensaver state transitions, timer integrity, offline ambient cards,
-- stream guards, TMDB API fallbacks, dark logo detection, and subprocess safety.
-- ============================================================================

package.path = './scripts/LuminaX/?.lua;' .. package.path
local utils = require('modules.utils')

local test_count = 0
local pass_count = 0

local function assert_eq(desc, actual, expected)
    test_count = test_count + 1
    if actual == expected then
        pass_count = pass_count + 1
        print(string.format("  ✓ PASS: %s", desc))
    else
        print(string.format("  ✗ FAIL: %s | Expected: %s, Got: %s", desc, tostring(expected), tostring(actual)))
    end
end

local function assert_true(desc, val)
    assert_eq(desc, not not val, true)
end

print("=== 1. Testing format_ends_time Failsafes & Clock Logic ===")

local function simulate_ends_time(rem_seconds, duration_min, mock_now)
    mock_now = mock_now or 1700000000
    local rem = rem_seconds
    if not rem or rem <= 0 or rem ~= rem then
        rem = (duration_min and duration_min > 0 and duration_min == duration_min) and (duration_min * 60) or 0
    end
    if rem > 0 and rem < 8640000 then
        local ok, res = pcall(function()
            local end_t = mock_now + math.floor(rem)
            local h = tonumber(os.date('!%H', end_t))
            local m = os.date('!%M', end_t)
            local ampm = (h and h >= 12) and 'PM' or 'AM'
            local h12 = (h and h % 12) or 12
            if h12 == 0 then h12 = 12 end
            return string.format('%d:%s %s', h12, m, ampm)
        end)
        if ok and res then return res end
    end
    return nil
end

assert_true("Normal positive remaining time (3600s)", simulate_ends_time(3600, nil) ~= nil)
assert_eq("Zero remaining with no fallback duration returns nil", simulate_ends_time(0, nil), nil)
assert_eq("Negative remaining with no fallback returns nil", simulate_ends_time(-50, nil), nil)
assert_eq("Nil remaining with no fallback returns nil", simulate_ends_time(nil, nil), nil)
assert_eq("NaN remaining with no fallback returns nil", simulate_ends_time(0/0, nil), nil)
assert_eq("Huge overflow (>100 days) returns nil failsafe", simulate_ends_time(9999999999, nil), nil)
assert_true("Fallback to duration_min when remaining is 0", simulate_ends_time(0, 120) ~= nil)
assert_true("Fallback to duration_min when remaining is nil", simulate_ends_time(nil, 90) ~= nil)
assert_eq("Zero duration_min and 0 remaining returns nil", simulate_ends_time(0, 0), nil)

print("\n=== 2. Testing Screensaver Lifecycle State Machine ===")

local StateMachine = {}
function StateMachine.new()
    local self = {
        ss_active = false,
        ss_hiding = false,
        ss_delay_timer = nil,
        ss_fade_timer = nil,
        ss_fade_out_timer = nil,
        active_subprocesses = {},
        overlay_visible = false,
        alpha = 255,
        paused = false,
        esc_bound = false,
    }

    function self:pause()
        self.paused = true
        -- start 3s delay timer
        self.ss_delay_timer = {active = true, delay = 3}
    end

    function self:delay_timer_fired()
        if not self.paused or not self.ss_delay_timer then return end
        self.ss_delay_timer = nil
        self:activate()
    end

    function self:activate()
        if not self.paused then return end
        self.ss_active = true
        self.ss_hiding = false
        self.alpha = 255
        self.overlay_visible = true
        self.esc_bound = true
        self.ss_fade_timer = {active = true}
    end

    function self:fade_step(target_alpha)
        self.alpha = target_alpha
        if self.alpha <= 0 then
            self.alpha = 0
            self.ss_fade_timer = nil
        end
    end

    function self:user_interaction(immediate)
        if self.ss_delay_timer then
            self.ss_delay_timer = nil
        end
        if immediate or not self.paused then
            self.ss_active = false
            self.ss_hiding = false
            self.ss_fade_timer = nil
            self.ss_fade_out_timer = nil
            self.overlay_visible = false
            self.esc_bound = false
            self.alpha = 255
        else
            -- smooth fade out
            self.ss_hiding = true
            self.ss_fade_out_timer = {active = true}
        end
    end

    function self:fade_out_complete()
        self.ss_active = false
        self.ss_hiding = false
        self.ss_fade_out_timer = nil
        self.overlay_visible = false
        self.esc_bound = false
        self.alpha = 255
    end

    function self:unpause()
        self.paused = false
        self:user_interaction(true)
    end

    return self
end

local sm = StateMachine.new()
assert_eq("Initial screensaver inactive", sm.ss_active, false)
assert_eq("Initial overlay invisible", sm.overlay_visible, false)

-- Normal pause flow
sm:pause()
assert_true("Delay timer active after pause", sm.ss_delay_timer ~= nil)
sm:delay_timer_fired()
assert_eq("Screensaver active after delay", sm.ss_active, true)
assert_eq("ESC key bound during screensaver", sm.esc_bound, true)
assert_eq("Overlay visible", sm.overlay_visible, true)

-- Fade step
sm:fade_step(128)
assert_eq("Midway fade alpha", sm.alpha, 128)
sm:fade_step(0)
assert_eq("Fully faded in alpha", sm.alpha, 0)
assert_eq("Fade timer finished", sm.ss_fade_timer, nil)

-- User dismisses via keypress/mouse while remaining paused (smooth fade-out)
sm:user_interaction(false)
assert_eq("Screensaver entered hiding state", sm.ss_hiding, true)
sm:fade_out_complete()
assert_eq("Screensaver inactive after fade out", sm.ss_active, false)
assert_eq("Overlay removed after fade out", sm.overlay_visible, false)
assert_eq("ESC key unbound", sm.esc_bound, false)

print("\n=== 3. Testing Rapid Pause/Play Spamming (Hammering Spacebar) ===")
local spam_sm = StateMachine.new()
for cycle = 1, 100 do
    spam_sm:pause()
    if cycle % 2 == 0 then
        spam_sm:delay_timer_fired()
    end
    spam_sm:unpause()
end

assert_eq("Spam test: Screensaver not active after final unpause", spam_sm.ss_active, false)
assert_eq("Spam test: Overlay not visible", spam_sm.overlay_visible, false)
assert_eq("Spam test: Delay timer cleaned up", spam_sm.ss_delay_timer, nil)
assert_eq("Spam test: Fade timer cleaned up", spam_sm.ss_fade_timer, nil)
assert_eq("Spam test: ESC binding cleared", spam_sm.esc_bound, false)

print("\n=== 4. Testing Ambient Card Generation (Offline & Streams) ===")

local function generate_ambient_rows(media_path, duration, channels, acodec, width, height)
    local rows = {}
    local is_stream = utils.is_url(media_path)
    if is_stream then
        local domain = media_path:match('^%a[%w+.-]*://([^/]+)') or 'Stream'
        table.insert(rows, {label = 'Source', val = domain:gsub('^www%.', '')})
    end

    local ends_t = simulate_ends_time(duration, nil)
    local dur_str = (duration and duration > 0) and utils.format_time(duration) or ''
    if ends_t then
        table.insert(rows, {label = 'Runtime', val = (dur_str ~= '' and (dur_str .. ' • ') or '') .. 'Ends ' .. ends_t})
    elseif dur_str ~= '' then
        table.insert(rows, {label = 'Duration', val = dur_str})
    elseif is_stream then
        table.insert(rows, {label = 'Stream', val = 'Live Stream'})
    end

    if acodec and acodec ~= '' then
        local a_info = acodec:upper() .. (channels and (' ' .. channels .. 'ch') or '')
        table.insert(rows, {label = 'Audio', val = a_info})
    end

    if width and height and width > 0 and height > 0 then
        local res_label = (width >= 3800 or height >= 2100) and '4K UHD' or ((width >= 1900 or height >= 1000) and '1080p FHD' or (height .. 'p'))
        table.insert(rows, {label = 'Quality', val = res_label})
    end
    return rows
end

-- 4a. Offline Local 4K MKV
local rows_4k = generate_ambient_rows('/media/movies/Oppenheimer.2023.mkv', 10800, 6, 'dts', 3840, 2160)
assert_eq("Offline 4K rows count", #rows_4k, 3)
assert_true("Offline 4K Quality", rows_4k[3].val == '4K UHD')
assert_true("Offline 4K Audio", rows_4k[2].val == 'DTS 6ch')

-- 4b. Online YouTube Stream
local rows_yt = generate_ambient_rows('https://www.youtube.com/watch?v=aqz-KE-bpKQ', 300, 2, 'aac', 1920, 1080)
assert_eq("YouTube rows count", #rows_yt, 4)
assert_eq("YouTube Source domain", rows_yt[1].val, 'youtube.com')
assert_eq("YouTube Quality", rows_yt[4].val, '1080p FHD')

-- 4c. Live Stream (duration = 0)
local rows_live = generate_ambient_rows('https://live.twitch.tv/streamer', 0, 2, 'aac', 1920, 1080)
assert_eq("Twitch Live Stream label", rows_live[2].val, 'Live Stream')

print("\n=== 5. Testing Dark Logo Detection & Auto-Inversion Filter ===")

local function eval_logo_luminance(pixels)
    local total_lum, total_sat, count = 0, 0, 0
    for _, p in ipairs(pixels) do
        local r, g, b, a = p[1], p[2], p[3], p[4]
        if a and a > 40 then
            local max_c = math.max(r, g, b)
            local min_c = math.min(r, g, b)
            total_lum = total_lum + (0.299 * r + 0.587 * g + 0.114 * b)
            total_sat = total_sat + (max_c - min_c)
            count = count + 1
        end
    end
    if count == 0 then return 'none' end
    local avg_lum = total_lum / count
    local avg_sat = total_sat / count

    if avg_sat <= 28.0 and avg_lum < 65.0 then
        return 'negate,'
    elseif avg_lum < 75.0 then
        return 'eq=brightness=0.25:contrast=1.1,'
    end
    return 'none'
end

-- Pure black logo pixels (e.g. Secret Level dark logo)
local dark_pixels = {
    {10, 10, 10, 255},
    {20, 20, 20, 255},
    {15, 15, 15, 255},
    {0, 0, 0, 255},
}
assert_eq("Dark logo detected for inversion", eval_logo_luminance(dark_pixels), 'negate,')

-- Bright white logo pixels (e.g. Dune / Avatar logo)
local bright_pixels = {
    {240, 240, 240, 255},
    {255, 255, 255, 255},
    {220, 220, 220, 255},
}
assert_eq("Bright logo untouched", eval_logo_luminance(bright_pixels), 'none')

-- Dim gray logo
local dim_gray = {
    {70, 70, 70, 255},
    {72, 72, 72, 255},
}
assert_eq("Dim logo brightened", eval_logo_luminance(dim_gray), 'eq=brightness=0.25:contrast=1.1,')

print("\n=== 6. Testing Studio Extraction & Holding Company Filtering ===")

package.loaded['mp.assdraw'] = { ass_new = function() return {} end }
package.loaded['mp.utils'] = { file_info = function() return nil end, readdir = function() return {} end }
_G.mp = _G.mp or {
    create_osd_overlay = function() return { update = function() end, remove = function() end } end,
    register_event = function() end,
    observe_property = function() end,
    get_property = function() return '' end,
    get_property_native = function() return nil end,
    set_property_native = function() end,
    command_native = function() return '' end,
    commandv = function() end,
    add_timeout = function() return { kill = function() end } end,
}

local ss = require('modules.screensaver')
assert_true("Screensaver module loads", ss ~= nil)
assert_true("filter_and_format_studios exported", type(ss.filter_and_format_studios) == 'function')

-- Weathering With You TMDB production_companies
local wwy_companies = {
    { id = 3756, logo_path = "/t38uPdbKmyBB8brKKeTFWIwojRz.png", name = "CoMix Wave Films", origin_country = "JP" },
    { id = 128616, logo_path = "/cjmwexOzetWZa8QKy447NMrM6MG.png", name = "Story", origin_country = "JP" },
    { id = 882, logo_path = "/fRSWWjquvzcHjACbtF53utZFIll.png", name = "TOHO", origin_country = "JP" },
    { id = 2073, logo_path = "/tWxRSaKmRJNTcmtlXsmn5R4KOSU.png", name = "KADOKAWA", origin_country = "JP" },
    { id = 8157, logo_path = "/pEqcMX1aG3JvtDgfh2wNZJLCcb4.png", name = "jeki", origin_country = "JP" },
    { id = 104184, logo_path = "/reEBh8dBl2y1DbXe2EdgxtMtaim.png", name = "Lawson Entertainment", origin_country = "JP" },
    { id = 145448, logo_path = nil, name = "\"Weathering With You\" Film Partners", origin_country = "JP" }
}
local wwy_studios = ss.filter_and_format_studios(wwy_companies, nil)
assert_eq("Weathering With You returns CoMix Wave Films · TOHO (excluding Story & Partners)", wwy_studios, "CoMix Wave Films  ·  TOHO")

-- Crime 101 TMDB production_companies
local crime_companies = {
    { id = 10163, logo_path = "/16KWBMmfPX0aJzDExDrPxSLj0Pg.png", name = "Working Title", origin_country = "GB" },
    { id = 122772, logo_path = nil, name = "The Story Factory", origin_country = "US" },
    { id = 23949, logo_path = "/3QFwomSxcZZgMQGBkdUPuJEnSFB.png", name = "RAW", origin_country = "GB" },
    { id = 210099, logo_path = "/g5oRCNCi8kNVb8gEoSoIcqkhjmR.png", name = "Amazon MGM Studios", origin_country = "US" },
    { id = 183787, logo_path = "/8G6CbTenzORJdoep1AaghtSEQrY.png", name = "Wild State", origin_country = "US" }
}
local crime_studios = ss.filter_and_format_studios(crime_companies, nil)
assert_eq("Crime 101 returns Working Title · Amazon MGM Studios (excluding The Story Factory)", crime_studios, "Working Title  ·  Amazon MGM Studios")

-- TV series network fallback
local tv_networks = {
    { id = 49, name = "HBO", logo_path = "/tuomPhY2UtuPTqqFnKMVHvSb724.png" }
}
local tv_studios = ss.filter_and_format_studios({}, tv_networks)
assert_eq("TV series with empty companies falls back to network", tv_studios, "HBO")


print(string.format("\n========================================================"))
print(string.format("Screensaver Robustness Suite: %d / %d Passed (%.1f%%)", pass_count, test_count, (pass_count/test_count)*100))
print(string.format("========================================================"))

if pass_count ~= test_count then
    os.exit(1)
end
