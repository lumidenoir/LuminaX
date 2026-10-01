package.path = './scripts/LuminaX/?.lua;' .. package.path
local utils = require('modules.utils')

local TEST_CASES = {
    {raw = "[1TamilMV.vip] DC (2026) Tamil TRUE WEB-DL - 1080p - AVC - (DD+5.1 ATMOS - 448Kbps & AAC) - 5.5GB - ESub.mkv", exp_title = "DC", exp_year = "2026"},
    {raw = "www.1TamilBlasters.vip - Vishwanath and Sons (2026) Telugu (DS4K 1080p NF WEB-Rip E-AC3 5.1 10bit HEVC - SP1EG3L).mkv", exp_title = "Vishwanath and Sons", exp_year = "2026"},
    {raw = "Idhayam.Murali.2026.1080p.NF.WEB-DL.MULTi.DDP5.1.H.265-Telly.mkv", exp_title = "Idhayam Murali", exp_year = "2026"},
    {raw = "[TamilRockers.ws] Thug Life (2025) Tamil HQ PreDVDRip - x264 - MP3 - 700MB.mkv", exp_title = "Thug Life", exp_year = "2025"},
    {raw = "Kantara Chapter 1 (2025) Kannada 2160p UHD HDR10+ TrueHD 7.1 Atmos HEVC-DDR.mkv", exp_title = "Kantara Chapter 1", exp_year = "2025"},
    {raw = "Dune.Part.Two.2024.2160p.UHD.BluRay.x265.TrueHD.Atmos.7.1-SPARKS.mkv", exp_title = "Dune Part Two", exp_year = "2024"},
    {raw = "Oppenheimer.2023.IMAX.1080p.BluRay.x264.DTS-HD.MA.5.1-FGT.mkv", exp_title = "Oppenheimer", exp_year = "2023"},
    {raw = "Deadpool.&.Wolverine.2024.REPACK.1080p.WEB-DL.DDP5.1.Atmos.H.264-FLUX.mkv", exp_title = "Deadpool & Wolverine", exp_year = "2024"},
    {raw = "Supergirl 2026 1080p WEB-DL HEVC x265 5.1 BONE.mkv", exp_title = "Supergirl", exp_year = "2026"},
    {raw = "Avatar.The.Way.of.Water.2022.PROPER.2160p.WEB-DL.DDP5.1.Atmos.DV.HDR10plus.H.265-CMRG.mkv", exp_title = "Avatar The Way of Water", exp_year = "2022"},
    {raw = "Secret.Level.S01E05.Warhammer.40000.And.They.Shall.Know.No.Fear.2160p.AMZN.WEB-DL.Hindi.DDP5.1-English.DDP5.1.Atmos.HDR.H.265-4kHdHub.Com.mkv", exp_title = "Secret Level", exp_s = 1, exp_e = 5},
    {raw = "Severance.S02E01.Hello.Ms.Cobel.2160p.ATVP.WEB-DL.DDP5.1.Atmos.DV.HDR.H.265-FLUX.mkv", exp_title = "Severance", exp_s = 2, exp_e = 1},
    {raw = "Breaking Bad - S05E14 - Ozymandias (1080p BluRay x265 10bit Tigole).mkv", exp_title = "Breaking Bad", exp_s = 5, exp_e = 14},
    {raw = "[SubsPlease] Solo Leveling - 12 (1080p) [98B89E23].mkv", exp_title = "Solo Leveling", exp_s = 1, exp_e = 12},
    {raw = "Civil.War.2024.1080p.WEBRip.x264.AAC5.1-[YTS.MX].mp4", exp_title = "Civil War", exp_year = "2024"},
    {raw = "The.Batman.2022.1080p.10bit.WEBRip.6CH.x265.HEVC-PSA.mkv", exp_title = "The Batman", exp_year = "2022"},
    {raw = "Gladiator.II.2024.720p.HDCAM.x264.Clean.Audio-BONSAI.mkv", exp_title = "Gladiator II", exp_year = "2024"},
    {raw = "Godzilla.x.Kong.The.New.Empire.2024.1080p.HDRip.XviD.AC3-EVO.avi", exp_title = "Godzilla x Kong The New Empire", exp_year = "2024"},
    {raw = "Interstellar.2014.1080p.BluRay.x264.YIFY.mp4", exp_title = "Interstellar", exp_year = "2014"},
    {raw = "www.1TamilMV.gripe - Dacoit (2026) Telugu HQ PreDVD - 1080p - x264 - HQ Clean - AAC - 2.5GB.mkv", exp_title = "Dacoit", exp_year = "2026"},
    {raw = "www.1TamilMV.reisen - The Odyssey (2026) New HQ HDTS - 1080p - x264 - [Tam + Tel + Hin + Eng] - HQ Clean - 3.3GB.mkv", exp_title = "The Odyssey", exp_year = "2026"},
    {raw = "www.1TamilMV.immo - Project Hail Mary (2026) New HQ PreDVD - 1080p - x264 - [Tam + Tel + Eng] - HQ Clean - AAC - 2.9GB.mkv", exp_title = "Project Hail Mary", exp_year = "2026"},
}

local passed = 0
local failed = 0

for i, tc in ipairs(TEST_CASES) do
    local title, s, e, year = utils.parse_clean_title('', tc.raw)
    local ok = true
    if tc.exp_title and title ~= tc.exp_title then ok = false end
    if tc.exp_year and year ~= tc.exp_year then ok = false end
    if tc.exp_s and s ~= tc.exp_s then ok = false end
    if tc.exp_e and e ~= tc.exp_e then ok = false end

    if ok then
        passed = passed + 1
        print(string.format("  [%02d] ✓ PASS: '%s' -> '%s'%s%s",
            i, tc.raw:sub(1, 35) .. "...", title,
            year and (" (" .. year .. ")") or "",
            (s and e) and (" [S" .. s .. "E" .. e .. "]") or ""))
    else
        failed = failed + 1
        print(string.format("  [%02d] ✗ FAIL: '%s'\n         Got: '%s' (Y:%s, S:%s, E:%s)\n         Exp: '%s' (Y:%s, S:%s, E:%s)",
            i, tc.raw, title, tostring(year), tostring(s), tostring(e),
            tc.exp_title, tostring(tc.exp_year), tostring(tc.exp_s), tostring(tc.exp_e)))
    end
end

-- Junk title verification
assert(utils.is_junk_title("www.1TamilMV.immo") == true, "domain watermark must be junk")
assert(utils.is_junk_title("HQ Clean") == true, "standalone HQ Clean must be junk")
assert(utils.is_junk_title("PreDVD") == true, "standalone PreDVD must be junk")
assert(utils.is_junk_title("HDTS") == true, "standalone HDTS must be junk")
assert(utils.is_junk_title("TE [AAC 2.0]") == false, "clean audio tag must not be junk")
assert(utils.is_junk_title("Tamil [AAC 2.0]") == false, "clean audio tag must not be junk")

print(string.format("\nCorpus Test Summary: %d Passed, %d Failed (%.1f%%)",
    passed, failed, (passed / (passed + failed)) * 100))
assert(failed == 0, "Test failures detected in corpus!")
