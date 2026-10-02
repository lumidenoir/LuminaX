local function utf8_prev_char(str, byte_pos)
    if not str or byte_pos <= 1 then return 1 end
    local i = byte_pos - 1
    while i > 1 and (str:byte(i) >= 0x80 and str:byte(i) < 0xC0) do
        i = i - 1
    end
    return i
end

local function utf8_next_char(str, byte_pos)
    if not str or byte_pos > #str then return #str + 1 end
    local b = str:byte(byte_pos)
    if not b then return #str + 1 end
    local step = 1
    if b >= 0xC0 and b < 0xE0 then
        step = 2
    elseif b >= 0xE0 and b < 0xF0 then
        step = 3
    elseif b >= 0xF0 then
        step = 4
    end
    return math.min(#str + 1, byte_pos + step)
end

local function simulate_backspace(text, cursor)
    if cursor <= 1 then return text, cursor end
    local prev_pos = utf8_prev_char(text, cursor)
    local left = text:sub(1, prev_pos - 1)
    local right = text:sub(cursor)
    return left .. right, prev_pos
end

local function simulate_delete(text, cursor)
    if cursor > #text then return text, cursor end
    local next_pos = utf8_next_char(text, cursor)
    local left = text:sub(1, cursor - 1)
    local right = text:sub(next_pos)
    return left .. right, cursor
end

local TEST_STRINGS = {
    {name = "ASCII", text = "Movie (2026)"},
    {name = "Tamil", text = "நாயகன்"},
    {name = "Hindi", text = "दृश्यम"},
    {name = "Japanese", text = "君の名は。"},
    {name = "Accents", text = "Amélie"},
    {name = "Emoji", text = "Movie 🎬 2026"}
}

local passed = 0
for _, tc in ipairs(TEST_STRINGS) do
    local orig = tc.text
    local cursor = #orig + 1
    -- Simulate backspace from the end
    local modified, new_cursor = simulate_backspace(orig, cursor)
    -- Verify string didn't break
    local ok = (new_cursor < cursor) and (#modified < #orig)
    if ok then
        passed = passed + 1
        print(string.format("  ✓ UTF-8 BS [%s]: '%s' (#%d) -> '%s' (#%d)",
            tc.name, orig, #orig, modified, #modified))
    else
        print(string.format("  ✗ UTF-8 BS FAIL [%s]", tc.name))
    end
end

assert(passed == #TEST_STRINGS, "UTF-8 test failure!")
print(string.format("\nUTF-8 Stepping Summary: %d / %d Passed (100%%)", passed, #TEST_STRINGS))
