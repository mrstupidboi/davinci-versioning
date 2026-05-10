-- DaVinci Resolve Toggle Noise Reduction Nodes v_2 (Lua)
--
-- Scans every timeline in the current project for color nodes that appear to
-- contain Resolve noise reduction tools, then alternates disabling/enabling
-- those whole nodes.
--
-- Resolve's scripting API exposes Graph:SetNodeEnabled(), but does not expose a
-- matching GetNodeEnabled(), so the default mode toggles based on the last
-- successful run written to the temp directory. Set FORCE_ENABLED to true or
-- false if you prefer a one-way menu command.

local FORCE_ENABLED = nil
local LOG_UNMATCHED_NODE_TOOLS = true

local LOG_FILENAME = "resolve_toggle_noise_reduction_v_2_log.txt"
local STATE_FILENAME = "resolve_toggle_noise_reduction_v_2_state.txt"

local TOOL_MATCHERS = {
    "noise",
    "denoise",
    "spatialnr",
    "temporalnr",
    "spatial nr",
    "temporal nr",
}

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

local function temp_path(filename)
    local temp_dir = os.getenv("TMPDIR") or os.getenv("TEMP") or os.getenv("TMP") or "/tmp"
    return join_path(temp_dir, filename)
end

local function write_log()
    local log_path = temp_path(LOG_FILENAME)
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

local function read_state()
    local file = io.open(temp_path(STATE_FILENAME), "r")
    if not file then
        return nil
    end

    local value = file:read("*l")
    file:close()
    return value
end

local function write_state(enabled)
    local file = io.open(temp_path(STATE_FILENAME), "w")
    if not file then
        log_line("WARNING: Could not write toggle state file.")
        return
    end

    if enabled then
        file:write("enabled\n")
    else
        file:write("disabled\n")
    end
    file:close()
end

local function choose_target_enabled()
    if FORCE_ENABLED ~= nil then
        return FORCE_ENABLED
    end

    local previous = read_state()
    if previous == "disabled" then
        return true
    end

    return false
end

local function table_count(values)
    local count = 0
    if not values then
        return count
    end

    for _ in pairs(values) do
        count = count + 1
    end
    return count
end

local function item_display_name(item)
    local ok, name = pcall(function()
        return item:GetName()
    end)
    if ok and name and name ~= "" then
        return tostring(name)
    end
    return "Untitled timeline item"
end

local function get_graph(item)
    local ok, graph = pcall(function()
        return item:GetNodeGraph()
    end)
    if ok and graph then
        return graph
    end

    return nil
end

local function get_tools(graph, node_index)
    local ok, tools = pcall(function()
        return graph:GetToolsInNode(node_index)
    end)
    if ok then
        return tools
    end
    return nil
end

local function tool_matches_noise_reduction(tool_name)
    local normalized = tostring(tool_name or ""):lower():gsub("[_%-%s]+", " ")
    local compact = normalized:gsub("%s+", "")

    for _, matcher in ipairs(TOOL_MATCHERS) do
        local matcher_normalized = matcher:lower()
        local matcher_compact = matcher_normalized:gsub("%s+", "")
        if normalized:find(matcher_normalized, 1, true) or compact:find(matcher_compact, 1, true) then
            return true
        end
    end

    return false
end

local function node_has_noise_reduction(graph, node_index)
    local tools = get_tools(graph, node_index)
    if not tools or table_count(tools) == 0 then
        return false, "(no tools reported)"
    end

    local names = {}
    local matched = false
    for _, tool_name in pairs(tools) do
        table.insert(names, tostring(tool_name))
        if tool_matches_noise_reduction(tool_name) then
            matched = true
        end
    end

    table.sort(names)
    return matched, table.concat(names, ", ")
end

local function set_node_enabled(graph, node_index, enabled)
    local ok, result = pcall(function()
        return graph:SetNodeEnabled(node_index, enabled)
    end)
    return ok and result == true
end

local function process_item(item, timeline_index, timeline_name, track_index, item_index, target_enabled)
    local clip_name = item_display_name(item)
    local graph = get_graph(item)
    if not graph then
        log_line(
            "Timeline " .. timeline_index ..
            " (" .. timeline_name .. ")" ..
            " track " .. track_index ..
            " item " .. item_index ..
            " skipped, no color node graph: " .. clip_name
        )
        return 0, 0
    end

    local ok, node_count = pcall(function()
        return graph:GetNumNodes()
    end)
    if not ok or not node_count or node_count < 1 then
        log_line(
            "Timeline " .. timeline_index ..
            " (" .. timeline_name .. ")" ..
            " track " .. track_index ..
            " item " .. item_index ..
            " skipped, no nodes: " .. clip_name
        )
        return 0, 0
    end

    local matches = 0
    local changed = 0
    for node_index = 1, node_count do
        local matched, tool_summary = node_has_noise_reduction(graph, node_index)
        if matched then
            matches = matches + 1
            if set_node_enabled(graph, node_index, target_enabled) then
                changed = changed + 1
                log_line(
                    "Timeline " .. timeline_index ..
                    " (" .. timeline_name .. ")" ..
                    " track " .. track_index ..
                    " item " .. item_index ..
                    " node " .. node_index ..
                    " -> " .. (target_enabled and "enabled" or "disabled") ..
                    " | " .. clip_name ..
                    " | tools: " .. tool_summary
                )
            else
                log_line(
                    "ERROR: Failed to set timeline " .. timeline_index ..
                    " (" .. timeline_name .. ")" ..
                    " track " .. track_index ..
                    " item " .. item_index ..
                    " node " .. node_index ..
                    " | " .. clip_name ..
                    " | tools: " .. tool_summary
                )
            end
        elseif LOG_UNMATCHED_NODE_TOOLS and tool_summary ~= "(no tools reported)" then
            log_line(
                "Timeline " .. timeline_index ..
                " (" .. timeline_name .. ")" ..
                " track " .. track_index ..
                " item " .. item_index ..
                " node " .. node_index ..
                " not matched" ..
                " | " .. clip_name ..
                " | tools: " .. tool_summary
            )
        end
    end

    return matches, changed
end

local function timeline_display_name(timeline, timeline_index)
    local ok, name = pcall(function()
        return timeline:GetName()
    end)
    if ok and name and name ~= "" then
        return tostring(name)
    end
    return "Timeline " .. tostring(timeline_index)
end

local function process_timeline(project, timeline, timeline_index, target_enabled)
    local timeline_name = timeline_display_name(timeline, timeline_index)
    log_line("------------------------------------------")
    log_line("Timeline " .. tostring(timeline_index) .. ": " .. timeline_name)

    local ok_set_current, set_current_result = pcall(function()
        return project:SetCurrentTimeline(timeline)
    end)
    if not ok_set_current or set_current_result ~= true then
        log_line("WARNING: Could not make timeline current before processing: " .. timeline_name)
    end

    local ok_track_count, track_count = pcall(function()
        return timeline:GetTrackCount("video")
    end)
    if not ok_track_count or not track_count then
        log_line("WARNING: Could not read video tracks for timeline: " .. timeline_name)
        return 0, 0, 0
    end

    log_line("Video tracks: " .. tostring(track_count))

    local timeline_items = 0
    local timeline_matches = 0
    local timeline_changed = 0
    for track_index = 1, track_count do
        local ok_items, items = pcall(function()
            return timeline:GetItemListInTrack("video", track_index)
        end)
        if not ok_items or not items then
            log_line("WARNING: Could not read timeline " .. timeline_index .. " track " .. track_index)
        else
            log_line("Track " .. track_index .. " items: " .. tostring(table_count(items)))
            for item_index, item in pairs(items) do
                timeline_items = timeline_items + 1
                local matches, changed = process_item(
                    item,
                    timeline_index,
                    timeline_name,
                    track_index,
                    item_index,
                    target_enabled
                )
                timeline_matches = timeline_matches + matches
                timeline_changed = timeline_changed + changed
            end
        end
    end

    log_line("Timeline items scanned: " .. tostring(timeline_items))
    log_line("Matching nodes found: " .. tostring(timeline_matches))
    log_line("Nodes changed: " .. tostring(timeline_changed))
    return timeline_items, timeline_matches, timeline_changed
end

local function main()
    log_line("Resolve Toggle Noise Reduction Nodes v_2 (Lua)")
    log_line("----------------------------------------------")

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

    local original_timeline = project:GetCurrentTimeline()
    if not original_timeline then
        log_line("ERROR: No timeline is open.")
        write_log()
        return
    end

    local timeline_count = project:GetTimelineCount() or 0
    if timeline_count < 1 then
        log_line("ERROR: This project has no timelines.")
        write_log()
        return
    end

    local target_enabled = choose_target_enabled()
    log_line("Project: " .. tostring(project:GetName()))
    log_line("Timelines: " .. tostring(timeline_count))
    log_line("Action: " .. (target_enabled and "enable matching nodes" or "disable matching nodes"))

    local total_items = 0
    local total_matches = 0
    local total_changed = 0

    for timeline_index = 1, timeline_count do
        local timeline = project:GetTimelineByIndex(timeline_index)
        if timeline then
            local items, matches, changed = process_timeline(project, timeline, timeline_index, target_enabled)
            total_items = total_items + items
            total_matches = total_matches + matches
            total_changed = total_changed + changed
        else
            log_line("WARNING: Could not load timeline at index " .. tostring(timeline_index))
        end
    end

    if original_timeline then
        local ok_restore, restored = pcall(function()
            return project:SetCurrentTimeline(original_timeline)
        end)
        if ok_restore and restored == true then
            log_line("Restored original timeline: " .. timeline_display_name(original_timeline, "?"))
        else
            log_line("WARNING: Could not restore the original timeline.")
        end
    end

    if total_changed > 0 then
        write_state(target_enabled)
    end

    log_line("----------------------------------------------")
    log_line("Project timelines scanned: " .. tostring(timeline_count))
    log_line("Timeline items scanned: " .. tostring(total_items))
    log_line("Matching nodes found: " .. tostring(total_matches))
    log_line("Nodes changed: " .. tostring(total_changed))
    log_line("Log file: " .. temp_path(LOG_FILENAME))
    write_log()
end

main()
