-- DaVinci Resolve Auto-Version Render Job for macOS/Windows (Lua)
--
-- Checks the output folder for existing files and creates the next _v## filename.
-- Lua is used because Resolve's menu always supports Lua scripts, while Python
-- menu scripts depend on Resolve detecting a compatible host Python install.

local FALLBACK_OUTPUT_FOLDER = nil
local VERSION_DIGITS = 2

local log_lines = {}

local function log_line(text)
    local message = tostring(text)
    table.insert(log_lines, message)
    print(message)
end

local function join_path(left, right)
    if string.sub(left, -1) == "/" or string.sub(left, -1) == "\\" then
        return left .. right
    end
    return left .. "/" .. right
end

local function write_log()
    local temp_dir = os.getenv("TMPDIR") or os.getenv("TEMP") or os.getenv("TMP") or "/tmp"
    local log_path = join_path(temp_dir, "resolve_auto_version_render_log.txt")
    local file = io.open(log_path, "w")
    if not file then
        print("ERROR: Could not write log file: " .. log_path)
        return
    end

    for _, line in ipairs(log_lines) do
        file:write(line .. "\n")
    end
    file:close()
end

local function shell_quote(value)
    return "'" .. tostring(value):gsub("'", "'\\''") .. "'"
end

local function sanitize_filename(name)
    local sanitized = tostring(name or "Untitled")
    sanitized = sanitized:gsub('[<>:"/\\|%?%*]', "_")
    sanitized = sanitized:gsub("^%s+", ""):gsub("%s+$", "")
    if sanitized == "" then
        return "Untitled"
    end
    return sanitized
end

local function escape_lua_pattern(value)
    return tostring(value):gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1")
end

local function get_existing_versions(folder, base_name, extension)
    local versions = {}
    local escaped_base_name = escape_lua_pattern(base_name)
    local escaped_extension = escape_lua_pattern(extension)
    local pattern = "^" .. escaped_base_name .. "_v(%d+)%." .. escaped_extension .. "$"
    local command = "find " .. shell_quote(folder) .. " -maxdepth 1 -type f -name " ..
        shell_quote(base_name .. "_v*." .. extension)

    log_line("Scanning folder: " .. folder)

    local handle = io.popen(command)
    if not handle then
        log_line("ERROR: Could not scan output folder.")
        return versions
    end

    for path in handle:lines() do
        local filename = path:match("([^/\\]+)$") or path
        log_line("Found matching-ish file: " .. filename)
        local version = filename:match(pattern)
        if version then
            local parsed = tonumber(version)
            table.insert(versions, parsed)
            log_line("Parsed version: " .. tostring(parsed))
        else
            log_line("Skipped file because it did not match expected pattern exactly.")
        end
    end
    handle:close()

    return versions
end

local function next_version_number(folder, base_name, extension)
    local versions = get_existing_versions(folder, base_name, extension)
    local max_version = 0
    for _, version in ipairs(versions) do
        if version > max_version then
            max_version = version
        end
    end
    return max_version + 1
end

local function get_current_extension(project)
    local current_render = project:GetCurrentRenderFormatAndCodec()
    if not current_render then
        log_line("ERROR: Could not read current render format/codec from Resolve.")
        return nil
    end

    local render_format = current_render["format"]
    local render_codec = current_render["codec"]
    log_line("Current render format: " .. tostring(render_format))
    log_line("Current render codec: " .. tostring(render_codec))

    if not render_format or render_format == "" then
        log_line("ERROR: Resolve did not return a current render format.")
        return nil
    end

    local render_formats = project:GetRenderFormats()
    if not render_formats then
        log_line("ERROR: Could not read available render formats from Resolve.")
        return nil
    end

    local extension = nil
    for format_name, format_extension in pairs(render_formats) do
        if tostring(format_extension):lower() == tostring(render_format):lower() then
            extension = format_extension
            break
        end
        if tostring(format_name):lower() == tostring(render_format):lower() then
            extension = format_extension
            break
        end
    end

    if not extension then
        log_line("ERROR: Could not map render format '" .. tostring(render_format) .. "' to a file extension.")
        return nil
    end

    log_line("Resolved file extension: " .. tostring(extension))
    return tostring(extension)
end

local function get_project_output_folder(project)
    local render_jobs = project:GetRenderJobList()
    if render_jobs and #render_jobs > 0 then
        local latest_job = render_jobs[#render_jobs]
        local target_dir = latest_job["TargetDir"]
        local output_filename = latest_job["OutputFilename"]
        log_line("Using output folder from latest render job: " .. tostring(target_dir))
        log_line("Latest render job filename: " .. tostring(output_filename))
        if target_dir and target_dir ~= "" then
            return target_dir, false
        end
    end

    if FALLBACK_OUTPUT_FOLDER then
        log_line("Using fallback output folder: " .. tostring(FALLBACK_OUTPUT_FOLDER))
        return FALLBACK_OUTPUT_FOLDER, true
    end

    log_line("ERROR: No render jobs found for this project. Add one render job first, then rerun this script.")
    return nil, false
end

local function main()
    log_line("Resolve Auto-Version Render (Lua)")
    log_line("---------------------------------")

    local resolve = Resolve()
    if not resolve then
        log_line("ERROR: Could not connect to Resolve.")
        write_log()
        return
    end

    local project_manager = resolve:GetProjectManager()
    if not project_manager then
        log_line("ERROR: Could not get Project Manager.")
        write_log()
        return
    end

    local project = project_manager:GetCurrentProject()
    if not project then
        log_line("ERROR: No project is open.")
        write_log()
        return
    end

    local output_folder, should_set_target_dir = get_project_output_folder(project)
    if not output_folder then
        write_log()
        return
    end

    log_line("Resolved output folder: " .. tostring(output_folder))

    local extension = get_current_extension(project)
    if not extension then
        write_log()
        return
    end

    local timeline = project:GetCurrentTimeline()
    if not timeline then
        log_line("ERROR: No timeline is open.")
        write_log()
        return
    end

    local base_name = sanitize_filename(timeline:GetName())
    log_line("Timeline/base name: " .. base_name)

    local next_v = next_version_number(output_folder, base_name, extension)
    local custom_name = string.format("%s_v%0" .. tostring(VERSION_DIGITS) .. "d", base_name, next_v)
    local expected_file = join_path(output_folder, custom_name .. "." .. extension)
    log_line("Next filename without extension: " .. custom_name)
    log_line("Expected full file: " .. expected_file)

    local render_settings = {
        ["CustomName"] = custom_name,
    }
    if should_set_target_dir then
        render_settings["TargetDir"] = output_folder
    end

    log_line("Applying render settings: CustomName=" .. custom_name)
    if not project:SetRenderSettings(render_settings) then
        log_line("ERROR: Failed to set render settings.")
        write_log()
        return
    end

    local job_id = project:AddRenderJob()
    if not job_id then
        log_line("ERROR: Failed to add render job.")
        write_log()
        return
    end

    log_line("Created render job: " .. tostring(job_id))
    log_line("Created filename: " .. custom_name .. "." .. extension)
    write_log()
end

main()
