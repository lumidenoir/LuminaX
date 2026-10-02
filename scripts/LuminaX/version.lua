-- ============================================================================
-- LuminaX: Central Version & Release Manifest
-- Single source of truth for versioning, repository coordinates, and schema migrations
-- ============================================================================

local Version = {
    VERSION            = '1.2.0',
    RELEASE_NAME       = 'LuminaX Rounded subs & Native updater',
    RELEASE_DATE       = '2026-10-03',
    GITHUB_REPO        = 'lumidenoir/LuminaX',
    GITHUB_API_URL     = 'https://api.github.com/repos/lumidenoir/LuminaX/releases/latest',
    CACHE_META_VERSION = 4,
}

-- SemVer comparator: returns -1 if v1 < v2, 0 if v1 == v2, 1 if v1 > v2
function Version.compare(v1, v2)
    if not v1 or not v2 then return 0 end
    local function parse_semver(s)
        s = s:gsub('^[vV]', '')
        local parts = {}
        for num in s:gmatch('%d+') do
            table.insert(parts, tonumber(num) or 0)
        end
        return parts[1] or 0, parts[2] or 0, parts[3] or 0
    end

    local maj1, min1, pat1 = parse_semver(v1)
    local maj2, min2, pat2 = parse_semver(v2)

    if maj1 ~= maj2 then return maj1 > maj2 and 1 or -1 end
    if min1 ~= min2 then return min1 > min2 and 1 or -1 end
    if pat1 ~= pat2 then return pat1 > pat2 and 1 or -1 end
    return 0
end

return Version
