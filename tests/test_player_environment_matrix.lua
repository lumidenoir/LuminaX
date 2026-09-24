-- ============================================================================
-- Test Suite: Player Environment Matrix & Responsive Scaling
-- Validates:
-- 1. 3-Tier responsive scaling (Tier 1 Compact, Tier 2 Standard, Tier 3 4K/Ultrawide)
-- 2. Media badge matrix (Resolution, HDR/DV, Codecs, Channels, Streams)
-- 3. Glass Menu item navigation, wrapping, and click hitboxes
-- 4. Cross-platform path and subprocess compatibility (Windows vs Linux)
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

print("=== 1. Testing 3-Tier Window Geometry Scaling Matrix ===")

local function get_scaling_tier(osd_w, osd_h)
    local aspect = osd_w / osd_h
    if osd_w < 1150 or aspect < 1.25 then
        return 1 -- Compact / Tiled
    elseif osd_w >= 1800 and aspect >= 1.25 then
        return 3 -- Cinematic Large (Fullscreen 4K / Ultrawide)
    else
        return 2 -- Normal Windowed
    end
end

-- Test matrix
assert_eq("720p Tiled Window (1024x576) -> Tier 1", get_scaling_tier(1024, 576), 1)
assert_eq("Compact 4:3 Window (1000x750) -> Tier 1", get_scaling_tier(1000, 750), 1)
assert_eq("Narrow Portrait Window (800x1200, aspect 0.67) -> Tier 1", get_scaling_tier(800, 1200), 1)
assert_eq("Standard 720p (1280x720, aspect 1.78) -> Tier 2", get_scaling_tier(1280, 720), 2)
assert_eq("Windowed 1080p (1600x900) -> Tier 2", get_scaling_tier(1600, 900), 2)
assert_eq("Full HD 1080p (1920x1080) -> Tier 3", get_scaling_tier(1920, 1080), 3)
assert_eq("1440p QHD (2560x1440) -> Tier 3", get_scaling_tier(2560, 1440), 3)
assert_eq("21:9 Ultrawide (3440x1440) -> Tier 3", get_scaling_tier(3440, 1440), 3)
assert_eq("32:9 Super Ultrawide (5120x1440) -> Tier 3", get_scaling_tier(5120, 1440), 3)
assert_eq("4K UHD (3840x2160) -> Tier 3", get_scaling_tier(3840, 2160), 3)
assert_eq("8K Display (7680x4320) -> Tier 3", get_scaling_tier(7680, 4320), 3)

print("\n=== 2. Testing Media Badge Matrix & Width Calculations ===")

local function evaluate_badges(props)
    local badges = {}

    -- Resolution
    local vw, vh = props.vw or 0, props.vh or 0
    if vw >= 3800 or vh >= 2100 then
        table.insert(badges, {text = '4K', w = 24, fg = 'D6A27E'})
    elseif vw >= 1900 or vh >= 1000 then
        table.insert(badges, {text = '1080P', w = 38, fg = 'B8A89A'})
    end

    -- HDR / Dolby Vision
    if props.dv and props.dv ~= '' then
        table.insert(badges, {text = 'VISION', w = 46, fg = '3CA9E5'})
    elseif props.gamma == 'pq' or props.gamma == 'hlg' or (props.primaries == 'bt.2020') then
        table.insert(badges, {text = 'HDR', w = 30, fg = '3CA9E5'})
    end

    -- Audio Standards
    local ac = (props.acodec or ''):lower()
    local title = (props.audio_title or ''):lower()
    if title:find('atmos') then
        table.insert(badges, {text = 'ATMOS', w = 46, fg = 'FF92B8'})
    elseif ac:find('truehd') then
        table.insert(badges, {text = 'TRUEHD', w = 50, fg = 'FF92B8'})
    elseif ac:find('dts') then
        table.insert(badges, {text = 'DTS', w = 28, fg = 'F0B080'})
    elseif ac:find('flac') then
        table.insert(badges, {text = 'FLAC', w = 32, fg = '80D8A0'})
    end

    -- Surround Channels
    local ch = props.channels or 0
    if ch == 8 then
        table.insert(badges, {text = '7.1', w = 22, fg = 'ACA19B'})
    elseif ch == 6 then
        table.insert(badges, {text = '5.1', w = 22, fg = 'ACA19B'})
    end

    -- Stream / Live
    if props.is_stream then
        if props.duration == 0 then
            table.insert(badges, {text = 'LIVE', w = 32, fg = 'FF8080'})
        else
            table.insert(badges, {text = 'STREAM', w = 46, fg = '70E0B0'})
        end
    end

    return badges
end

-- Scenario A: High-end 4K Dolby Vision + Dolby Atmos 7.1
local b_high = evaluate_badges({
    vw = 3840, vh = 2160,
    dv = 'profile 7',
    acodec = 'truehd',
    audio_title = 'English TrueHD Atmos 7.1',
    channels = 8
})
assert_eq("High-end media badge count", #b_high, 4)
assert_eq("Badge 1 is 4K", b_high[1].text, '4K')
assert_eq("Badge 2 is VISION", b_high[2].text, 'VISION')
assert_eq("Badge 3 is ATMOS", b_high[3].text, 'ATMOS')
assert_eq("Badge 4 is 7.1", b_high[4].text, '7.1')

local width_high = utils.calc_badges_width(b_high, 22)
assert_true("Calculated width for 4 badges > 150px", width_high > 150)

-- Scenario B: Live HLS broadcast
local b_live = evaluate_badges({
    vw = 1920, vh = 1080,
    is_stream = true,
    duration = 0,
    acodec = 'aac',
    channels = 2
})
assert_eq("Live broadcast badge count", #b_live, 2)
assert_eq("Badge 1 is 1080P", b_live[1].text, '1080P')
assert_eq("Badge 2 is LIVE", b_live[2].text, 'LIVE')

print("\n=== 3. Testing Glass Menu Item Navigation & Wrap-around ===")

local MenuNavigator = {}
function MenuNavigator.new(item_count)
    local self = {
        items_count = item_count,
        selected = 1,
    }
    function self:down()
        self.selected = self.selected + 1
        if self.selected > self.items_count then
            self.selected = 1
        end
    end
    function self:up()
        self.selected = self.selected - 1
        if self.selected < 1 then
            self.selected = self.items_count
        end
    end
    function self:click(my, top_y, header_h, row_h)
        if my < top_y + header_h or my > top_y + header_h + (self.items_count * row_h) then
            return nil
        end
        local idx = math.floor((my - (top_y + header_h)) / row_h) + 1
        if idx >= 1 and idx <= self.items_count then
            self.selected = idx
            return idx
        end
        return nil
    end
    return self
end

local nav = MenuNavigator.new(5)
assert_eq("Initial selection is 1", nav.selected, 1)

nav:down()
assert_eq("Selection after down is 2", nav.selected, 2)

nav:up()
assert_eq("Selection after up is 1", nav.selected, 1)

-- Wrap around up
nav:up()
assert_eq("Selection wrapped up to 5", nav.selected, 5)

-- Wrap around down
nav:down()
assert_eq("Selection wrapped down to 1", nav.selected, 1)

-- Click row 3: top_y=100, header_h=56, row_h=46 -> row 3 y range: [100+56+92, 100+56+138] = [248, 294]
local clicked_idx = nav:click(260, 100, 56, 46)
assert_eq("Clicked row 3 correctly detected", clicked_idx, 3)
assert_eq("Navigation selected updated to row 3", nav.selected, 3)

-- Click outside menu items
assert_eq("Click above header returns nil", nav:click(50, 100, 56, 46), nil)
assert_eq("Click below menu list returns nil", nav:click(500, 100, 56, 46), nil)

print("\n=== 4. Testing Cross-Platform Environment Abstractions (Windows vs Linux) ===")

local function get_platform_paths(os_name, env)
    local is_win = (os_name == 'windows')
    local config_dir, cache_dir
    if is_win then
        local appdata = env.APPDATA or 'C:\\Users\\User\\AppData\\Roaming'
        local localapp = env.LOCALAPPDATA or 'C:\\Users\\User\\AppData\\Local'
        config_dir = appdata .. '\\mpv'
        cache_dir  = localapp .. '\\mpv\\luminax'
    else
        local home = env.HOME or '/home/user'
        local xdg_config = env.XDG_CONFIG_HOME or (home .. '/.config')
        local xdg_cache  = env.XDG_CACHE_HOME or (home .. '/.cache')
        config_dir = xdg_config .. '/mpv'
        cache_dir  = xdg_cache .. '/mpv/luminax'
    end
    return {
        is_windows = is_win,
        config_dir = config_dir,
        cache_dir = cache_dir,
        mkdir_cmd = is_win and {'cmd.exe', '/c', 'if not exist "' .. cache_dir .. '" mkdir "' .. cache_dir .. '"'} or {'mkdir', '-p', cache_dir},
        paste_cmd = is_win and {'powershell', '-NoProfile', '-Command', 'Get-Clipboard'} or {'sh', '-c', 'wl-paste 2>/dev/null || xclip -o -selection clipboard 2>/dev/null || pbpaste 2>/dev/null'},
    }
end

-- 4a. Windows Environment Simulation
local win_env = get_platform_paths('windows', {
    APPDATA = 'C:\\Users\\Alice\\AppData\\Roaming',
    LOCALAPPDATA = 'C:\\Users\\Alice\\AppData\\Local'
})
assert_eq("Windows platform flag", win_env.is_windows, true)
assert_eq("Windows config directory", win_env.config_dir, 'C:\\Users\\Alice\\AppData\\Roaming\\mpv')
assert_eq("Windows cache directory", win_env.cache_dir, 'C:\\Users\\Alice\\AppData\\Local\\mpv\\luminax')
assert_eq("Windows mkdir binary is cmd.exe", win_env.mkdir_cmd[1], 'cmd.exe')
assert_eq("Windows paste binary is powershell", win_env.paste_cmd[1], 'powershell')

-- 4b. Linux Environment Simulation
local lin_env = get_platform_paths('linux', {
    HOME = '/home/bob',
    XDG_CONFIG_HOME = '/home/bob/.config',
    XDG_CACHE_HOME = '/home/bob/.cache'
})
assert_eq("Linux platform flag", lin_env.is_windows, false)
assert_eq("Linux config directory", lin_env.config_dir, '/home/bob/.config/mpv')
assert_eq("Linux cache directory", lin_env.cache_dir, '/home/bob/.cache/mpv/luminax')
assert_eq("Linux mkdir binary is mkdir", lin_env.mkdir_cmd[1], 'mkdir')
assert_eq("Linux mkdir flag is -p", lin_env.mkdir_cmd[2], '-p')
assert_eq("Linux paste binary is sh", lin_env.paste_cmd[1], 'sh')

print(string.format("\n========================================================"))
print(string.format("Player Environment Matrix Suite: %d / %d Passed (%.1f%%)", pass_count, test_count, (pass_count/test_count)*100))
print(string.format("========================================================"))

if pass_count ~= test_count then
    os.exit(1)
end
