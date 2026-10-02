-- ============================================================================
-- Test Suite: Updater & Config Security Test Matrix
-- Tests SemVer edge cases, zero-clobber config migrations, TMDB API key preservation,
-- input.conf & mpv.conf preservation, and in-player update state machine failsafes.
-- ============================================================================

package.path = './scripts/LuminaX/?.lua;' .. package.path
local version = require('version')

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

print("=== 1. Testing SemVer Comparator & Versioning Edge Cases ===")

-- Standard comparisons
assert_eq("1.0.0 < 1.0.1", version.compare("1.0.0", "1.0.1"), -1)
assert_eq("1.0.1 > 1.0.0", version.compare("1.0.1", "1.0.0"), 1)
assert_eq("1.1.0 == 1.1.0", version.compare("1.1.0", "1.1.0"), 0)

-- Numeric vs Lexicographical (Critical: 1.10.0 must be greater than 1.9.0)
assert_eq("1.10.0 > 1.9.0 (Numeric, not lexicographical)", version.compare("1.10.0", "1.9.0"), 1)
assert_eq("1.9.0 < 1.10.0", version.compare("1.9.0", "1.10.0"), -1)
assert_eq("2.0.0 > 1.99.99", version.compare("2.0.0", "1.99.99"), 1)

-- 'v' and 'V' prefix stripping
assert_eq("v1.1.0 == 1.1.0", version.compare("v1.1.0", "1.1.0"), 0)
assert_eq("V2.0.0 > v1.9.9", version.compare("V2.0.0", "v1.9.9"), 1)
assert_eq("v1.0.5 < v1.1.0", version.compare("v1.0.5", "v1.1.0"), -1)

-- Partial version strings (2-part vs 3-part)
assert_eq("1.1 == 1.1.0", version.compare("1.1", "1.1.0"), 0)
assert_eq("2 == 2.0.0", version.compare("2", "2.0.0"), 0)
assert_eq("1.2 > 1.1.9", version.compare("1.2", "1.1.9"), 1)

-- Prerelease strings (e.g. 1.2.0-beta.1)
assert_eq("1.2.0-beta.1 == 1.2.0 (base semver matched)", version.compare("1.2.0-beta.1", "1.2.0"), 0)

-- Nil & malformed failsafes
assert_eq("Nil input returns 0 without crashing", version.compare(nil, "1.0.0"), 0)
assert_eq("Invalid string parsed safely", version.compare("invalid", "1.0.0"), -1)


print("\n=== 2. Testing Config Security & Zero-Clobber Migration Engine ===")

-- Simulation function mirroring cross-platform update.ps1 & update.sh config merge logic
local function simulate_config_merge(existing_osc_text, template_osc_text)
    -- Normalize lines (support Windows \r\n and Unix \n)
    local existing_lines = {}
    for line in existing_osc_text:gmatch('[^\r\n]+') do
        table.insert(existing_lines, line)
    end

    local existing_keys = {}
    for _, l in ipairs(existing_lines) do
        local key = l:match('^%s*([%w%-_]+)%s*=')
        if key then
            existing_keys[key] = true
        end
    end

    local merged_lines = {}
    for _, l in ipairs(existing_lines) do
        table.insert(merged_lines, l)
    end

    local new_settings_added = 0
    for line in template_osc_text:gmatch('[^\r\n]+') do
        local clean_line = line:gsub('^%s+', ''):gsub('%s+$', '')
        if clean_line ~= '' and clean_line:sub(1, 1) ~= '#' then
            local key, val = clean_line:match('^([%w%-_]+)%s*=%s*(.*)$')
            if key and not existing_keys[key] then
                existing_keys[key] = true
                table.insert(merged_lines, string.format('%s=%s', key, val))
                new_settings_added = new_settings_added + 1
            end
        end
    end

    return table.concat(merged_lines, '\n'), new_settings_added
end

local user_custom_osc = [[
# ==============================================================================
# My Customized LuminaX Configuration
# ==============================================================================
scalewindowed=1.35
scalefullscreen=1.20
screensaver_delay=12
screensaver_align=left
screensaver_anti_burnin=yes
tmdb_api_key=my_secret_production_key_99887766
showjump=no
]]

local incoming_template_osc = [[
# Template osc.def.conf from new release
scalewindowed=1.0
scalefullscreen=1.05
screensaver_delay=5
screensaver_align=center
screensaver_anti_burnin=no
tmdb_api_key=your_api_key_here
showjump=yes
tmdb_cache_lookup=yes
tmdb_cache_max_mb=250
new_future_option=yes
]]

local merged_result, added_count = simulate_config_merge(user_custom_osc, incoming_template_osc)

-- 2.1 Verify API Key is 100% preserved
assert_true("User TMDB API key is preserved intact", merged_result:find("tmdb_api_key=my_secret_production_key_99887766") ~= nil)
assert_true("Placeholder key is NOT present", merged_result:find("your_api_key_here") == nil)

-- 2.2 Verify User custom flags are NOT reset to template defaults
assert_true("Custom screensaver_delay=12 preserved (not reset to 5)", merged_result:find("screensaver_delay=12") ~= nil)
assert_true("Custom screensaver_align=left preserved (not reset to center)", merged_result:find("screensaver_align=left") ~= nil)
assert_true("Custom scalewindowed=1.35 preserved (not reset to 1.0)", merged_result:find("scalewindowed=1.35") ~= nil)
assert_true("Custom showjump=no preserved (not reset to yes)", merged_result:find("showjump=no") ~= nil)
assert_true("Custom anti_burnin=yes preserved", merged_result:find("screensaver_anti_burnin=yes") ~= nil)

-- 2.3 Verify New settings from template are merged
assert_eq("Exactly 3 new settings merged", added_count, 3)
assert_true("New setting tmdb_cache_lookup added", merged_result:find("tmdb_cache_lookup=yes") ~= nil)
assert_true("New setting tmdb_cache_max_mb added", merged_result:find("tmdb_cache_max_mb=250") ~= nil)
assert_true("New setting new_future_option added", merged_result:find("new_future_option=yes") ~= nil)

-- 2.4 Verify User comments are retained
assert_true("User header comment preserved", merged_result:find("# My Customized LuminaX Configuration") ~= nil)

-- 2.5 Verify No duplicate keys exist
local key_occurrences = {}
for line in merged_result:gmatch('[^\n]+') do
    local k = line:match('^%s*([%w%-_]+)%s*=')
    if k then
        key_occurrences[k] = (key_occurrences[k] or 0) + 1
    end
end
local has_duplicates = false
for k, count in pairs(key_occurrences) do
    if count > 1 then
        has_duplicates = true
        print(string.format("    Duplicate key found: %s (%d times)", k, count))
    end
end
assert_eq("Zero duplicate keys in merged output", has_duplicates, false)


print("\n=== 3. Testing Quoted TMDB Key & Windows CRLF Resilience ===")

local crlf_osc = "# Windows Config\r\n tmdb_api_key = \"token_with_quotes_and_spaces\" \r\n screensaver_delay = 8 \r\n"
local crlf_template = "tmdb_api_key=your_api_key_here\r\nscreensaver_delay=5\r\ntmdb_cache_max_mb=250\r\n"

local crlf_merged, crlf_added = simulate_config_merge(crlf_osc, crlf_template)
assert_true("Quoted TMDB key preserved without corruption", crlf_merged:find('tmdb_api_key = "token_with_quotes_and_spaces"') ~= nil)
assert_true("Custom delay=8 preserved under CRLF", crlf_merged:find('screensaver_delay = 8') ~= nil)
assert_true("New option merged under CRLF", crlf_merged:find('tmdb_cache_max_mb=250') ~= nil)


print("\n=== 4. Testing input.conf Safety & Keybinding Preservation ===")

local function simulate_input_conf_merge(existing_input, new_bindings)
    local existing_lower = existing_input:lower()
    local lines_to_add = {}

    for _, bind_line in ipairs(new_bindings) do
        local action = bind_line:match('script%-binding%s+(%S+)')
        if action and not existing_lower:find(action:lower(), 1, true) then
            table.insert(lines_to_add, bind_line)
        end
    end

    if #lines_to_add == 0 then return existing_input, 0 end
    return existing_input .. '\n\n# LuminaX Menu Shortcuts\n' .. table.concat(lines_to_add, '\n'), #lines_to_add
end

local user_input_conf = [[
# User Custom Keybindings
SPACE cycle pause
f cycle fullscreen
s cycle sub
q quit
WHEEL_UP add volume 2
WHEEL_DOWN add volume -2
]]

local luminax_default_bindings = {
    "tab               script-binding LuminaX/visibility",
    "p                 script-binding LuminaX/menu-playlist",
    "c                 script-binding LuminaX/menu-chapters",
    "a                 script-binding LuminaX/menu-audio",
    "s                 script-binding LuminaX/menu-sub",
    "Alt+s             script-binding LuminaX/menu-sub-config",
    "V                 script-binding LuminaX/menu-video",
    "T                 script-binding LuminaX/toggle-tags-menu",
}

local merged_input, added_bindings = simulate_input_conf_merge(user_input_conf, luminax_default_bindings)

-- User's existing bindings must remain untouched
assert_true("User SPACE cycle pause retained", merged_input:find("SPACE cycle pause", 1, true) ~= nil)
assert_true("User f cycle fullscreen retained", merged_input:find("f cycle fullscreen", 1, true) ~= nil)
assert_true("User WHEEL_UP retained", merged_input:find("WHEEL_UP add volume 2", 1, true) ~= nil)

-- Missing LuminaX bindings added
assert_true("tab LuminaX/visibility added", merged_input:find("LuminaX/visibility", 1, true) ~= nil)
assert_true("p LuminaX/menu-playlist added", merged_input:find("LuminaX/menu-playlist", 1, true) ~= nil)
assert_true("c LuminaX/menu-chapters added", merged_input:find("LuminaX/menu-chapters", 1, true) ~= nil)
assert_true("T LuminaX/toggle-tags-menu added", merged_input:find("LuminaX/toggle-tags-menu", 1, true) ~= nil)


print("\n=== 5. Testing mpv.conf Protection (Zero Clobber of Shaders & Profiles) ===")

local function simulate_mpv_conf_check(existing_mpv)
    local has_osc_no = false
    local has_osd_bar_no = false
    for line in existing_mpv:gmatch('[^\r\n]+') do
        if line:match('^%s*osc%s*=%s*no') then has_osc_no = true end
        if line:match('^%s*osd%-bar%s*=%s*no') then has_osd_bar_no = true end
    end

    local updated_mpv = existing_mpv
    if not has_osc_no then
        updated_mpv = updated_mpv .. "\n# Disable default mpv OSC for LuminaX\nosc=no"
    end
    if not has_osd_bar_no then
        updated_mpv = updated_mpv .. "\nosd-bar=no"
    end
    return updated_mpv, not has_osc_no or not has_osd_bar_no
end

local user_mpv_conf = [[
# User Custom High-End Configuration
vo=gpu-next
gpu-api=vulkan
hwdec=auto-safe
profile=high-quality
glsl-shaders="~~/shaders/Anime4K.glsl"
volume=80
]]

local updated_mpv, modified = simulate_mpv_conf_check(user_mpv_conf)

assert_true("User vo=gpu-next preserved", updated_mpv:find("vo=gpu-next", 1, true) ~= nil)
assert_true("User Vulkan and high-quality profiles preserved", updated_mpv:find("gpu-api=vulkan", 1, true) ~= nil and updated_mpv:find("profile=high-quality", 1, true) ~= nil)
assert_true("User shaders preserved", updated_mpv:find('glsl-shaders="~~/shaders/Anime4K.glsl"', 1, true) ~= nil)
assert_true("osc=no safely added", updated_mpv:find("osc=no", 1, true) ~= nil)
assert_true("osd-bar=no safely added", updated_mpv:find("osd-bar=no", 1, true) ~= nil)

-- Running check again should make 0 modifications
local _, modified_again = simulate_mpv_conf_check(updated_mpv)
assert_eq("Subsequent checks make zero duplicate modifications", modified_again, false)


print("\n=== 6. Testing In-Player Updater State Machine & Failsafes ===")

package.loaded['mp.utils'] = {
    parse_json = function(str)
        if not str or str == '' or str == 'malformed' then return nil end
        -- Basic simulation of json parse
        local tag = str:match('"tag_name"%s*:%s*"([^"]+)"')
        local url = str:match('"html_url"%s*:%s*"([^"]+)"')
        if tag then return { tag_name = tag, html_url = url or '' } end
        return nil
    end,
    format_json = function(t) return "{}" end,
}

local mock_async_result = nil
local mock_async_ok = true

_G.mp = _G.mp or {}
_G.mp.command_native = function(args) return '/tmp' end
_G.mp.command_native_async = function(cmd, cb)
    if cb then cb(mock_async_ok, mock_async_result) end
    return 1
end
_G.mp.add_key_binding = function() end
_G.mp.add_timeout = function() end
_G.mp.osd_message = function() end

local updater = require('modules.updater')
assert_true("Updater module loaded", updater ~= nil)

updater.init({
    user_opts = { check_updates = true },
    state = {},
    request_tick = function() end,
})

-- 6.1 Status is nil before any check
assert_eq("Initial update status is nil", updater.get_update_status(), nil)

-- 6.2 Simulate successful newer release detection
mock_async_ok = true
mock_async_result = { stdout = '{"tag_name": "v1.2.0", "html_url": "https://github.com/lumidenoir/LuminaX/releases/tag/v1.2.0"}' }

local detected_newer = false
local detected_ver = nil
updater.check_for_updates(function(is_newer, ver, info)
    detected_newer = is_newer
    detected_ver = ver
end, true)

assert_true("Newer version v1.2.0 detected", detected_newer == true)
assert_eq("Detected version string parsed correctly", detected_ver, "1.2.0")
assert_true("State holds active update_available record", updater.get_update_status() ~= nil)

-- 6.3 Simulate current or older release (v1.0.0 vs current v1.1.0)
mock_async_result = { stdout = '{"tag_name": "v1.0.0", "html_url": ""}' }
local older_detected = nil
updater.check_for_updates(function(is_newer)
    older_detected = is_newer
end, true)
assert_eq("Older release v1.0.0 not reported as newer", older_detected, false)

-- 6.4 Simulate Network Error / Timeout Failsafe
mock_async_ok = false
mock_async_result = nil
local err_callback_called = false
updater.check_for_updates(function(is_newer, ver)
    err_callback_called = true
    assert_eq("On network failure, is_newer is false", is_newer, false)
end, true)
assert_true("Failsafe callback called on network error", err_callback_called)

-- 6.5 Simulate Malformed JSON / GitHub 500 error
mock_async_ok = true
mock_async_result = { stdout = 'malformed' }
local malformed_handled = false
updater.check_for_updates(function(is_newer)
    malformed_handled = true
    assert_eq("Malformed response safely handled without crash", is_newer, false)
end, true)
assert_true("Malformed response handled gracefully", malformed_handled)


print(string.format("\n========================================================"))
print(string.format("Updater & Config Security Matrix: %d / %d Passed (%.1f%%)", pass_count, test_count, (pass_count/test_count)*100))
print(string.format("========================================================"))

if pass_count ~= test_count then
    os.exit(1)
end
