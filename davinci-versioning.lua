-- DaVinci Resolve Auto-Version Render Job for Windows (Lua v2)
-- Checks the output folder for existing files and creates the next _v## filename.
-- Install to:
-- C:\ProgramData\Blackmagic Design\DaVinci Resolve\Fusion\Scripts\Utility

------------------------------------------------------------
-- USER SETTINGS
------------------------------------------------------------

-- IMPORTANT: Use double backslashes in Windows paths.
-- Example: "D:\\Renders" or "C:\\Users\\YourName\\Videos\\Resolve Exports"
local OUTPUT_FOLDER = "C:\\Users\\YOUR_NAME\\Videos\\Resolve Exports"

-- Change extension to match what you render from Resolve.
-- Examples: "mov", "mp4", "mxf", "wav"
local EXTENSION = "mov"

-- Version format: _v01, _v02, etc.
local VERSION_DIGITS = 2

-- Set to true if you want Notepad to open with a log every time.
local SHOW_LOG = true

------------------------------------------------------------
-- HELPERS
------------------------------------------------------------

local function log_line(lines, text)
    table.insert(lines, tostring(text))
end

local function write_log(lines)
    local log_path = os.getenv("TEMP") .. "\\resolve_auto_version_render_log.txt"
    local f = io.open(log_path, "w")
    if f then
        for _, line in ipairs(lines) do
            f:write(line .. "\n")
        end
        f:close()
        if SHOW_LOG then
            os.execute('start "" notepad "' .. log_path .. '"')
        end
    end
end

local function folder_exists(path)
    local ok, _, code = os.rename(path, path)
    if ok then return true end
    -- Windows can return permission denied for folders that still exist.
    return code == 13
end

local function sanitize_filename(name)
    -- Replace characters Windows does not allow in filenames.
    name = tostring(name or "Untitled")
    name = name:gsub('[<>:"/\\|%?%*]', "_")
    name = name:gsub("^%s+", ""):gsub("%s+$", "")
    if name == "" then name = "Untitled" end
    return name
end

local function escape_pattern(text)
    return text:gsub("([^%w])", "%%%1")
end

local function get_existing_versions(folder, base_name, extension, lines)
    local versions = {}

    -- /b = bare filenames only, /a-d = files only
    -- 2>nul hides error text if no files match.
    local wildcard = folder .. "\\" .. base_name .. "_v*." .. extension
    local cmd = 'dir /b /a-d "' .. wildcard .. '" 2>nul'
    log_line(lines, "Folder scan command: " .. cmd)

    local pipe = io.popen(cmd)
    if not pipe then
        log_line(lines, "ERROR: Could not run Windows dir command through io.popen().")
        return versions
    end

    local pattern = "^" .. escape_pattern(base_name) .. "_v(%d+)%.'" -- placeholder replaced below
    pattern = "^" .. escape_pattern(base_name) .. "_v(%d+)%." .. escape_pattern(extension) .. "$"

    for filename in pipe:lines() do
        log_line(lines, "Found matching-ish file: " .. filename)
        local v = filename:match(pattern)
        if v then
            table.insert(versions, tonumber(v))
            log_line(lines, "Parsed version: " .. v)
        else
            log_line(lines, "Skipped file because it did not match expected pattern exactly.")
        end
    end
    pipe:close()

    return versions
end

local function next_version_number(folder, base_name, extension, lines)
    local versions = get_existing_versions(folder, base_name, extension, lines)
    local max_v = 0
    for _, v in ipairs(versions) do
        if v and v > max_v then max_v = v end
    end
    return max_v + 1
end

local function zero_pad(num, digits)
    local fmt = "%0" .. tostring(digits) .. "d"
    return string.format(fmt, num)
end

------------------------------------------------------------
-- MAIN
------------------------------------------------------------

local lines = {}
log_line(lines, "Resolve Auto-Version Render v2")
log_line(lines, "--------------------------------")
log_line(lines, "Output folder: " .. OUTPUT_FOLDER)
log_line(lines, "Extension: " .. EXTENSION)

if not folder_exists(OUTPUT_FOLDER) then
    log_line(lines, "ERROR: Output folder does not exist. Create it or fix OUTPUT_FOLDER in the script.")
    write_log(lines)
    return
end

local resolve = Resolve()
if not resolve then
    log_line(lines, "ERROR: Could not connect to Resolve.")
    write_log(lines)
    return
end

local projectManager = resolve:GetProjectManager()
if not projectManager then
    log_line(lines, "ERROR: Could not get Project Manager.")
    write_log(lines)
    return
end

local project = projectManager:GetCurrentProject()
if not project then
    log_line(lines, "ERROR: No project is open.")
    write_log(lines)
    return
end

local timeline = project:GetCurrentTimeline()
if not timeline then
    log_line(lines, "ERROR: No timeline is open.")
    write_log(lines)
    return
end

local timeline_name = sanitize_filename(timeline:GetName())
local base_name = timeline_name
log_line(lines, "Timeline/base name: " .. base_name)

local next_v = next_version_number(OUTPUT_FOLDER, base_name, EXTENSION, lines)
local custom_name = base_name .. "_v" .. zero_pad(next_v, VERSION_DIGITS)
log_line(lines, "Next filename without extension: " .. custom_name)
log_line(lines, "Expected full file: " .. OUTPUT_FOLDER .. "\\" .. custom_name .. "." .. EXTENSION)

-- This preserves your Deliver-page codec/format settings, but changes output location/name.
local ok = project:SetRenderSettings({
    TargetDir = OUTPUT_FOLDER,
    CustomName = custom_name
})

if not ok then
    log_line(lines, "ERROR: SetRenderSettings failed. Open the Deliver page once, choose your render preset/settings, then try again.")
    write_log(lines)
    return
end

local job_id = project:AddRenderJob()
if not job_id then
    log_line(lines, "ERROR: AddRenderJob failed. Open the Deliver page and make sure render settings are valid.")
    write_log(lines)
    return
end

log_line(lines, "SUCCESS: Added render job ID: " .. tostring(job_id))
log_line(lines, "Now check Deliver page > Render Queue.")
write_log(lines)
