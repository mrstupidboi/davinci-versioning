-- DaVinci Resolve Toggle Color Effect Nodes v_1 (Lua)
--
-- Scans every timeline in the current project for color nodes that appear to
-- contain selected Resolve tools, then enables/disables those whole nodes.
--
-- Resolve's scripting API exposes Graph:SetNodeEnabled(), but does not expose a
-- matching GetNodeEnabled(), so this script prompts for an explicit Enable or
-- Disable action instead of guessing each node's current state.

local LOG_UNMATCHED_NODE_TOOLS = true

local LOG_FILENAME = "resolve_toggle_color_effects_v_1_log.txt"

local EFFECTS = {
    {
        id = "noise_reduction",
        label = "Noise Reduction",
        matchers = {
            "noise",
            "denoise",
            "spatialnr",
            "temporalnr",
            "spatial nr",
            "temporal nr",
        },
    },
    {
        id = "ai_ultra_sharpen",
        label = "AI Ultra Sharpen",
        matchers = {
            "ai ultra sharpen",
            "ai ultrasharpen",
            "ultra sharpen",
            "ultrasharpen",
            "ultra sharp",
            "ultrasharp",
        },
    },
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

local function tool_matches_effect(tool_name, effect)
    local normalized = tostring(tool_name or ""):lower():gsub("[_%-%s]+", " ")
    local compact = normalized:gsub("%s+", "")

    for _, matcher in ipairs(effect.matchers) do
        local matcher_normalized = matcher:lower()
        local matcher_compact = matcher_normalized:gsub("%s+", "")
        if normalized:find(matcher_normalized, 1, true) or compact:find(matcher_compact, 1, true) then
            return true
        end
    end

    return false
end

local function node_matches_selected_effects(graph, node_index, selected_effects)
    local tools = get_tools(graph, node_index)
    if not tools or table_count(tools) == 0 then
        return false, "(no tools reported)", ""
    end

    local names = {}
    local matched_effects = {}
    for _, tool_name in pairs(tools) do
        table.insert(names, tostring(tool_name))
        for _, effect in ipairs(selected_effects) do
            if tool_matches_effect(tool_name, effect) then
                matched_effects[effect.id] = effect.label
            end
        end
    end

    table.sort(names)
    local labels = {}
    for _, label in pairs(matched_effects) do
        table.insert(labels, label)
    end
    table.sort(labels)

    return #labels > 0, table.concat(names, ", "), table.concat(labels, ", ")
end

local function set_node_enabled(graph, node_index, enabled)
    local ok, result = pcall(function()
        return graph:SetNodeEnabled(node_index, enabled)
    end)
    return ok and result == true
end

local function process_item(item, timeline_index, timeline_name, track_index, item_index, selected_effects, target_enabled)
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
        local matched, tool_summary, effect_summary = node_matches_selected_effects(graph, node_index, selected_effects)
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
                    " | matched: " .. effect_summary ..
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
                    " | matched: " .. effect_summary ..
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

local function process_timeline(project, timeline, timeline_index, selected_effects, target_enabled)
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
                if type(item_index) == "number" then
                    timeline_items = timeline_items + 1
                    local matches, changed = process_item(
                        item,
                        timeline_index,
                        timeline_name,
                        track_index,
                        item_index,
                        selected_effects,
                        target_enabled
                    )
                    timeline_matches = timeline_matches + matches
                    timeline_changed = timeline_changed + changed
                end
            end
        end
    end

    log_line("Timeline items scanned: " .. tostring(timeline_items))
    log_line("Matching nodes found: " .. tostring(timeline_matches))
    log_line("Nodes changed: " .. tostring(timeline_changed))
    return timeline_items, timeline_matches, timeline_changed
end

local function selected_dropdown_value(value, options)
    if type(value) == "number" then
        return options[value + 1] or options[value]
    end
    return tostring(value or "")
end

local function selected_effects_from_choice(choice)
    if choice == "Noise Reduction" then
        return { EFFECTS[1] }
    end
    if choice == "AI Ultra Sharpen" then
        return { EFFECTS[2] }
    end
    if choice == "Both" then
        return { EFFECTS[1], EFFECTS[2] }
    end
    return nil
end

local function effect_labels(selected_effects)
    local labels = {}
    for _, effect in ipairs(selected_effects) do
        table.insert(labels, effect.label)
    end
    return table.concat(labels, ", ")
end

local function ask_user_with_uimanager(fusion, target_options, action_options)
    local ui = fusion.UIManager
    if not ui then
        return nil, "Fusion UIManager is not available."
    end
    if not bmd or not bmd.UIDispatcher then
        return nil, "bmd.UIDispatcher is not available."
    end

    local dispatcher = bmd.UIDispatcher(ui)
    if not dispatcher then
        return nil, "Could not create a UI dispatcher."
    end

    local window = dispatcher:AddWindow({
        ID = "ToggleColorEffectNodes",
        WindowTitle = "Toggle Color Effect Nodes",
        Geometry = { 100, 100, 420, 150 },

        ui:VGroup{
            ID = "Root",
            Spacing = 8,

            ui:HGroup{
                ui:Label{ Text = "Target", MinimumSize = { 110, 24 } },
                ui:ComboBox{ ID = "TargetCombo", Weight = 1 },
            },

            ui:HGroup{
                ui:Label{ Text = "Action", MinimumSize = { 110, 24 } },
                ui:ComboBox{ ID = "ActionCombo", Weight = 1 },
            },

            ui:HGroup{
                ui:HGap(0, 1),
                ui:Button{ ID = "CancelButton", Text = "Cancel" },
                ui:Button{ ID = "ApplyButton", Text = "Apply" },
            },
        },
    })

    if not window then
        return nil, "Could not create the UIManager window."
    end

    local items = window:GetItems()
    for _, option in ipairs(target_options) do
        items.TargetCombo:AddItem(option)
    end
    for _, option in ipairs(action_options) do
        items.ActionCombo:AddItem(option)
    end
    items.TargetCombo.CurrentIndex = 2
    items.ActionCombo.CurrentIndex = 0

    local response = nil
    function window.On.ApplyButton.Clicked()
        local target_index = items.TargetCombo.CurrentIndex
        local action_index = items.ActionCombo.CurrentIndex
        response = {
            ["Target"] = target_options[(target_index or 2) + 1] or "Both",
            ["Action"] = action_options[(action_index or 0) + 1] or "Disable",
        }
        dispatcher:ExitLoop()
    end

    function window.On.CancelButton.Clicked()
        dispatcher:ExitLoop()
    end

    function window.On.ToggleColorEffectNodes.Close()
        dispatcher:ExitLoop()
    end

    window:Show()
    dispatcher:RunLoop()
    window:Hide()

    if response then
        return response, nil
    end
    return nil, "UIManager prompt was cancelled."
end

local function ask_user(resolve)
    local target_options = { "Noise Reduction", "AI Ultra Sharpen", "Both" }
    local action_options = { "Disable", "Enable" }
    local controls = {
        { "Target", Name = "Target", "Dropdown", Options = target_options, Default = 2 },
        { "Action", Name = "Action", "Dropdown", Options = action_options, Default = 0 },
    }

    local fusion = resolve:Fusion()
    if not fusion then
        return nil, "Could not get Fusion object for the prompt."
    end

    local prompt_errors = {}
    local ok_ui, ui_response, ui_error = pcall(function()
        return ask_user_with_uimanager(fusion, target_options, action_options)
    end)
    if ok_ui and ui_response then
        return ui_response, nil
    end
    if ok_ui then
        table.insert(prompt_errors, "UIManager: " .. tostring(ui_error))
    else
        table.insert(prompt_errors, "UIManager error: " .. tostring(ui_response))
    end

    local ok, response = pcall(function()
        return fusion:AskUser("Toggle Color Effect Nodes", controls)
    end)
    if ok and response then
        return response, nil
    end
    if ok then
        table.insert(prompt_errors, "fusion:AskUser returned no response.")
    else
        table.insert(prompt_errors, "fusion:AskUser error: " .. tostring(response))
    end

    local ok_comp, comp = pcall(function()
        return fusion:GetCurrentComp()
    end)
    if ok_comp and comp then
        local ok_comp_prompt, comp_response = pcall(function()
            return comp:AskUser("Toggle Color Effect Nodes", controls)
        end)
        if ok_comp_prompt and comp_response then
            return comp_response, nil
        end
        if ok_comp_prompt then
            table.insert(prompt_errors, "comp:AskUser returned no response.")
        else
            table.insert(prompt_errors, "comp:AskUser error: " .. tostring(comp_response))
        end
    elseif ok_comp then
        table.insert(prompt_errors, "fusion:GetCurrentComp returned no composition.")
    else
        table.insert(prompt_errors, "fusion:GetCurrentComp error: " .. tostring(comp))
    end

    return nil, table.concat(prompt_errors, " | ")
end

local function main()
    log_line("Resolve Toggle Color Effect Nodes v_1 (Lua)")
    log_line("-------------------------------------------")

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

    local response, prompt_error = ask_user(resolve)
    if not response then
        log_line("Cancelled: " .. tostring(prompt_error))
        write_log()
        return
    end

    local target_choice = selected_dropdown_value(response["Target"], { "Noise Reduction", "AI Ultra Sharpen", "Both" })
    local action_choice = selected_dropdown_value(response["Action"], { "Disable", "Enable" })
    local selected_effects = selected_effects_from_choice(target_choice)
    if not selected_effects then
        log_line("ERROR: Unknown target choice: " .. tostring(target_choice))
        write_log()
        return
    end

    local target_enabled = action_choice == "Enable"
    log_line("Project: " .. tostring(project:GetName()))
    log_line("Timelines: " .. tostring(timeline_count))
    log_line("Target: " .. effect_labels(selected_effects))
    log_line("Action: " .. (target_enabled and "enable matching nodes" or "disable matching nodes"))

    local total_items = 0
    local total_matches = 0
    local total_changed = 0

    for timeline_index = 1, timeline_count do
        local timeline = project:GetTimelineByIndex(timeline_index)
        if timeline then
            local items, matches, changed = process_timeline(project, timeline, timeline_index, selected_effects, target_enabled)
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

    log_line("-------------------------------------------")
    log_line("Project timelines scanned: " .. tostring(timeline_count))
    log_line("Timeline items scanned: " .. tostring(total_items))
    log_line("Matching nodes found: " .. tostring(total_matches))
    log_line("Nodes changed: " .. tostring(total_changed))
    log_line("Log file: " .. temp_path(LOG_FILENAME))
    write_log()
end

main()
