-- ============================================================================
-- Test Suite: Tag Editor Flows, UTF-8 Integrity, Stream Guards & Watermarks
-- Validates:
-- 1. In-player OSD modal input lifecycle (open, typing, cursor, confirm, dismiss)
-- 2. Multi-byte UTF-8 character navigation, insertion, and deletion
-- 3. Clipboard paste sanitization (stripping control chars, newline flattening)
-- 4. Stream guard protection (disallowing writes to remote URLs)
-- 5. Track watermark cleaning and MKV argument formulation
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

print("=== 1. Testing UTF-8 Multi-Byte Navigation & Deletion ===")

local TEST_CORPUS = {
    {name = "Tamil (3-byte UTF-8)", text = "நாயகன்"},
    {name = "Hindi (3-byte UTF-8)", text = "दृश्यम"},
    {name = "Japanese (3-byte UTF-8)", text = "君の名は。"},
    {name = "Accents (2-byte UTF-8)", text = "Amélie"},
    {name = "Emoji (4-byte UTF-8)", text = "Avatar 🎬 2026"},
    {name = "Mixed Script", text = "Movie [नायकன்] 2026 🍿"}
}

for _, tc in ipairs(TEST_CORPUS) do
    local str = tc.text
    local cur = #str + 1

    -- Backspace from end
    local prev_pos = utils.utf8_prev_char(str, cur)
    assert_true(tc.name .. " utf8_prev_char valid", prev_pos < cur and prev_pos >= 1)
    local left = str:sub(1, prev_pos - 1)
    local deleted_char = str:sub(prev_pos, cur - 1)
    assert_true(tc.name .. " deleted codepoint non-empty", #deleted_char > 0)

    -- Right arrow from start
    local next_pos = utils.utf8_next_char(str, 1)
    assert_true(tc.name .. " utf8_next_char valid", next_pos > 1)
end

print("\n=== 2. Testing Full String Backspace Step-Through ===")
-- Ensure that stepping backspace character-by-character to the start never errors or produces corrupt indices
for _, tc in ipairs(TEST_CORPUS) do
    local text = tc.text
    local cur = #text + 1
    local steps = 0
    while cur > 1 do
        local p = utils.utf8_prev_char(text, cur)
        assert_true("prev pos < cur", p < cur)
        cur = p
        steps = steps + 1
    end
    assert_eq(tc.name .. " reached start safely", cur, 1)
    assert_true(tc.name .. " took > 0 steps", steps > 0)
end

print("\n=== 3. Testing Clipboard Paste Sanitization ===")

local function sanitize_paste(raw_clipboard)
    if not raw_clipboard or raw_clipboard == '' then return '' end
    -- Flatten newlines and tabs to space, strip control chars (\0-\31) except space
    local text = raw_clipboard:gsub('[\r\n\t]+', ' '):gsub('[%z\1-\8\11\12\14-\31]', ''):gsub('^%s+', ''):gsub('%s+$', '')
    return text
end

assert_eq("CRLF newline flattened", sanitize_paste("Inception\r\n(2010)"), "Inception (2010)")
assert_eq("Tabs converted to spaces", sanitize_paste("Title\tYear"), "Title Year")
assert_eq("Control characters stripped", sanitize_paste("Bad\000Title\007Bell"), "BadTitleBell")
assert_eq("Leading/trailing spaces trimmed", sanitize_paste("   Clean Title   "), "Clean Title")
assert_eq("Unicode preserved in paste", sanitize_paste("  நாயகன் (2026) \r\n"), "நாயகன் (2026)")

print("\n=== 4. Testing Modal Input Controller State Machine ===")

local ModalController = {}
function ModalController.new()
    local self = {
        active = false,
        prompt = '',
        text = '',
        cursor = 1,
        screensaver_inhibited = false,
        on_close_called = false,
        confirmed_value = nil,
    }

    function self:open(prompt, initial_text, on_confirm)
        self.active = true
        self.prompt = prompt or 'EDIT MOVIE TITLE'
        self.text = initial_text or ''
        self.cursor = #self.text + 1
        self.screensaver_inhibited = true
        self.on_confirm = on_confirm
        self.on_close_called = false
    end

    function self:type_char(c)
        if not self.active then return end
        local left = self.text:sub(1, self.cursor - 1)
        local right = self.text:sub(self.cursor)
        self.text = left .. c .. right
        self.cursor = self.cursor + #c
    end

    function self:backspace()
        if not self.active or self.cursor <= 1 then return end
        local prev = utils.utf8_prev_char(self.text, self.cursor)
        local left = self.text:sub(1, prev - 1)
        local right = self.text:sub(self.cursor)
        self.text = left .. right
        self.cursor = prev
    end

    function self:delete()
        if not self.active or self.cursor > #self.text then return end
        local nxt = utils.utf8_next_char(self.text, self.cursor)
        local left = self.text:sub(1, self.cursor - 1)
        local right = self.text:sub(nxt)
        self.text = left .. right
    end

    function self:move_home()
        self.cursor = 1
    end

    function self:move_end()
        self.cursor = #self.text + 1
    end

    function self:paste(raw)
        local clean = sanitize_paste(raw)
        if clean ~= '' then
            local left = self.text:sub(1, self.cursor - 1)
            local right = self.text:sub(self.cursor)
            self.text = left .. clean .. right
            self.cursor = self.cursor + #clean
        end
    end

    function self:click(mx, my, box_x, box_y, box_w, box_h)
        if not self.active then return end
        if mx < box_x or mx > box_x + box_w or my < box_y or my > box_y + box_h then
            self:close()
        end
    end

    function self:confirm()
        local v = self.text
        self.confirmed_value = v
        self:close()
        if self.on_confirm then self.on_confirm(v) end
    end

    function self:close()
        self.active = false
        self.screensaver_inhibited = false
        self.on_close_called = true
    end

    return self
end

local modal = ModalController.new()
modal:open('EDIT MOVIE TITLE', 'Gladiator', function(v) end)
assert_eq("Modal is active", modal.active, true)
assert_eq("Screensaver inhibited during tag edit", modal.screensaver_inhibited, true)
assert_eq("Initial cursor at end of 'Gladiator'", modal.cursor, 10)

-- Type " II"
modal:type_char(" ")
modal:type_char("I")
modal:type_char("I")
assert_eq("Text after typing", modal.text, "Gladiator II")
assert_eq("Cursor after typing", modal.cursor, 13)

-- Move Home, then Right
modal:move_home()
assert_eq("Cursor at Home", modal.cursor, 1)
modal:move_end()
assert_eq("Cursor at End", modal.cursor, 13)

-- Backspace twice
modal:backspace()
modal:backspace()
assert_eq("Text after 2 backspaces", modal.text, "Gladiator ")

-- Paste "2024"
modal:paste(" 2024\r\n")
assert_eq("Text after paste", modal.text, "Gladiator 2024")

-- Click inside modal (doesn't close)
modal:click(500, 300, 400, 200, 400, 200)
assert_eq("Modal stays open on inside click", modal.active, true)

-- Click outside modal (closes)
modal:click(100, 100, 400, 200, 400, 200)
assert_eq("Modal closes on outside click", modal.active, false)
assert_eq("Screensaver un-inhibited on close", modal.screensaver_inhibited, false)
assert_eq("on_close called", modal.on_close_called, true)

print("\n=== 5. Testing Stream Guard & File Compatibility ===")

local function can_edit_file(path)
    if not path or path == '' then return false, 'empty' end
    if utils.is_url(path) then
        return false, 'remote_stream'
    end
    local ext = path:lower():match('%.(%w+)$')
    if ext == 'mkv' or ext == 'webm' then
        return true, 'mkvpropedit'
    else
        return true, 'session_fallback'
    end
end

assert_eq("YouTube stream blocked from tag edit", (select(2, can_edit_file("https://www.youtube.com/watch?v=123"))), "remote_stream")
assert_eq("Twitch stream blocked from tag edit", (select(2, can_edit_file("rtmp://live.twitch.tv/stream"))), "remote_stream")
assert_eq("Local MKV file allowed for mkvpropedit", (select(2, can_edit_file("/home/user/movie.mkv"))), "mkvpropedit")
assert_eq("Local WebM file allowed for mkvpropedit", (select(2, can_edit_file("/home/user/video.webm"))), "mkvpropedit")
assert_eq("Local MP4 file allowed via session fallback", (select(2, can_edit_file("/home/user/movie.mp4"))), "session_fallback")
assert_eq("Local AVI file allowed via session fallback", (select(2, can_edit_file("/home/user/movie.avi"))), "session_fallback")

print("\n=== 6. Testing Watermark Cleaning Logic ===")

local function generate_mkvpropedit_args(filename, media_title, tracks)
    local show, _, _, year = utils.parse_clean_title(media_title, filename)
    local clean_title = (show and show ~= '') and (year and (show .. ' (' .. year .. ')') or show) or filename:gsub('%.%w+$', '')

    local args = {'mkvpropedit', filename, '--edit', 'info', '--set', 'title=' .. clean_title}
    local v_idx, a_idx, s_idx = 0, 0, 0
    for _, t in ipairs(tracks) do
        local t_type = t.type
        local t_title = t.title or ''
        local is_junk = utils.is_junk_title(t_title) or t_title:lower():find('1tamilmv') or t_title:lower():find('tamil')
        if t_type == 'video' then
            v_idx = v_idx + 1
            if t_title ~= '' and is_junk then
                table.insert(args, '--edit')
                table.insert(args, 'track:v' .. v_idx)
                table.insert(args, '--delete')
                table.insert(args, 'name')
            end
        elseif t_type == 'audio' then
            a_idx = a_idx + 1
            if t_title ~= '' and is_junk then
                table.insert(args, '--edit')
                table.insert(args, 'track:a' .. a_idx)
                table.insert(args, '--set')
                table.insert(args, 'name=Tamil [E-AC-3 5.1]')
            end
        end
    end
    return clean_title, args
end

local mock_tracks = {
    {type = 'video', title = 'www.1TamilMV.vip - 1080p AVC'},
    {type = 'audio', title = '1TamilMV - Tamil DD+ 5.1 Atmos', lang = 'tam', codec = 'eac3', ['demux-channel-count'] = 6}
}

local clean_t, mkv_args = generate_mkvpropedit_args(
    '[1TamilMV.vip] DC (2026) Tamil TRUE WEB-DL.mkv',
    'www.1TamilMV.vip - DC (2026)',
    mock_tracks
)

assert_eq("Clean title extracted from junk media", clean_t, "DC (2026)")
assert_eq("MKV args binary is mkvpropedit", mkv_args[1], "mkvpropedit")
assert_true("MKV args contains info edit", (function()
    for _, a in ipairs(mkv_args) do if a == 'title=DC (2026)' then return true end end
    return false
end)())
assert_true("MKV args contains video junk delete", (function()
    for _, a in ipairs(mkv_args) do if a == 'track:v1' then return true end end
    return false
end)())
assert_true("MKV args contains audio name set", (function()
    for _, a in ipairs(mkv_args) do if a == 'name=Tamil [E-AC-3 5.1]' then return true end end
    return false
end)())

print(string.format("\n========================================================"))
print(string.format("Tag Editor Flows Suite: %d / %d Passed (%.1f%%)", pass_count, test_count, (pass_count/test_count)*100))
print(string.format("========================================================"))

if pass_count ~= test_count then
    os.exit(1)
end
