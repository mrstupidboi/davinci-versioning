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
local CHOICE_FILENAME = "resolve_toggle_color_effects_v_1_choices.txt"

local TARGET_OPTIONS = { "Noise Reduction", "AI Ultra Sharpen", "Both" }
local ACTION_OPTIONS = { "Disable", "Enable" }
local SCOPE_OPTIONS = { "Pre-Clip", "Clip", "Post-Clip", "Timeline", "All" }
local DEFAULT_CHOICES = {
    ["Target"] = "Both",
    ["Action"] = "Disable",
    ["Scope"] = "All",
}

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

local function option_index(options, value)
    for index, option in ipairs(options) do
        if option == value then
            return index
        end
    end
    return nil
end

local function option_or_default(options, value, default_value)
    if option_index(options, value) then
        return value
    end
    return default_value
end

local function read_saved_choices()
    local choices = {
        ["Target"] = DEFAULT_CHOICES["Target"],
        ["Action"] = DEFAULT_CHOICES["Action"],
        ["Scope"] = DEFAULT_CHOICES["Scope"],
    }

    local file = io.open(temp_path(CHOICE_FILENAME), "r")
    if not file then
        return choices
    end

    for line in file:lines() do
        local key, value = tostring(line):match("^([^=]+)=(.*)$")
        if key and value then
            choices[key] = value
        end
    end
    file:close()

    choices["Target"] = option_or_default(TARGET_OPTIONS, choices["Target"], DEFAULT_CHOICES["Target"])
    choices["Action"] = option_or_default(ACTION_OPTIONS, choices["Action"], DEFAULT_CHOICES["Action"])
    choices["Scope"] = option_or_default(SCOPE_OPTIONS, choices["Scope"], DEFAULT_CHOICES["Scope"])
    return choices
end

local function write_saved_choices(choices)
    local file = io.open(temp_path(CHOICE_FILENAME), "w")
    if not file then
        log_line("WARNING: Could not write choice state file.")
        return
    end

    file:write("Target=" .. tostring(choices["Target"] or DEFAULT_CHOICES["Target"]) .. "\n")
    file:write("Action=" .. tostring(choices["Action"] or DEFAULT_CHOICES["Action"]) .. "\n")
    file:write("Scope=" .. tostring(choices["Scope"] or DEFAULT_CHOICES["Scope"]) .. "\n")
    file:close()
end

local function opposite_action(action)
    if action == "Disable" then
        return "Enable"
    end
    if action == "Enable" then
        return "Disable"
    end
    return DEFAULT_CHOICES["Action"]
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

local function process_graph(context_label, graph, selected_effects, target_enabled)
    local ok, node_count = pcall(function()
        return graph:GetNumNodes()
    end)
    if not ok or not node_count or node_count < 1 then
        log_line(context_label .. " skipped, no nodes")
        return 0, 0, 1
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
                    context_label ..
                    " node " .. node_index ..
                    " -> " .. (target_enabled and "enabled" or "disabled") ..
                    " | matched: " .. effect_summary ..
                    " | tools: " .. tool_summary
                )
            else
                log_line(
                    "ERROR: Failed to set " .. context_label ..
                    " node " .. node_index ..
                    " | matched: " .. effect_summary ..
                    " | tools: " .. tool_summary
                )
            end
        elseif LOG_UNMATCHED_NODE_TOOLS and tool_summary ~= "(no tools reported)" then
            log_line(
                context_label ..
                " node " .. node_index ..
                " not matched" ..
                " | tools: " .. tool_summary
            )
        end
    end

    return matches, changed, 1
end

local function get_clip_graph(item, layer_index)
    local ok, graph = pcall(function()
        return item:GetNodeGraph(layer_index)
    end)
    if ok and graph then
        return graph
    end

    if layer_index == 1 then
        local ok_fallback, fallback_graph = pcall(function()
            return item:GetNodeGraph()
        end)
        if ok_fallback and fallback_graph then
            return fallback_graph
        end
    end

    return nil
end

local function get_timeline_graph(timeline)
    local ok, graph = pcall(function()
        return timeline:GetNodeGraph()
    end)
    if ok and graph then
        return graph
    end
    return nil
end

local function get_color_group(item)
    local ok, color_group = pcall(function()
        return item:GetColorGroup()
    end)
    if ok and color_group then
        return color_group
    end
    return nil
end

local function color_group_display_name(color_group)
    local ok, name = pcall(function()
        return color_group:GetName()
    end)
    if ok and name and name ~= "" then
        return tostring(name)
    end
    return "Unnamed Color Group"
end

local function get_group_graph(color_group, graph_getter_name)
    local ok, graph = pcall(function()
        return color_group[graph_getter_name](color_group)
    end)
    if ok and graph then
        return graph
    end
    return nil
end

local function get_node_stack_layer_count(project)
    local ok, value = pcall(function()
        return project:GetSetting("nodeStackLayers")
    end)
    local count = tonumber(ok and value or nil)
    if count and count > 0 then
        return count
    end
    return 1
end

local function scope_includes(scope_choice, scope_name)
    return scope_choice == "All" or scope_choice == scope_name
end

local function is_valid_scope(scope_choice)
    return scope_choice == "Pre-Clip" or
        scope_choice == "Clip" or
        scope_choice == "Post-Clip" or
        scope_choice == "Timeline" or
        scope_choice == "All"
end

local function process_item(
    item,
    timeline_index,
    timeline_name,
    track_index,
    item_index,
    selected_effects,
    target_enabled,
    scope_choice,
    node_stack_layers,
    processed_groups
)
    local clip_name = item_display_name(item)
    local base_context =
        "Timeline " .. timeline_index ..
        " (" .. timeline_name .. ")" ..
        " track " .. track_index ..
        " item " .. item_index ..
        " | clip: " .. clip_name

    local total_matches = 0
    local total_changed = 0
    local total_graphs = 0

    if scope_includes(scope_choice, "Clip") then
        for layer_index = 1, node_stack_layers do
            local graph = get_clip_graph(item, layer_index)
            if graph then
                local context_label = base_context .. " | Clip layer " .. layer_index
                local matches, changed, graphs = process_graph(context_label, graph, selected_effects, target_enabled)
                total_matches = total_matches + matches
                total_changed = total_changed + changed
                total_graphs = total_graphs + graphs
            elseif layer_index == 1 then
                log_line(base_context .. " skipped, no clip node graph")
            end
        end
    end

    if scope_includes(scope_choice, "Pre-Clip") or scope_includes(scope_choice, "Post-Clip") then
        local color_group = get_color_group(item)
        if not color_group then
            return total_matches, total_changed, total_graphs
        end

        local group_name = color_group_display_name(color_group)
        if not processed_groups[group_name] then
            processed_groups[group_name] = true

            if scope_includes(scope_choice, "Pre-Clip") then
                local pre_graph = get_group_graph(color_group, "GetPreClipNodeGraph")
                if pre_graph then
                    local matches, changed, graphs = process_graph(
                        "Color group: " .. group_name .. " | Group Pre-Clip",
                        pre_graph,
                        selected_effects,
                        target_enabled
                    )
                    total_matches = total_matches + matches
                    total_changed = total_changed + changed
                    total_graphs = total_graphs + graphs
                end
            end

            if scope_includes(scope_choice, "Post-Clip") then
                local post_graph = get_group_graph(color_group, "GetPostClipNodeGraph")
                if post_graph then
                    local matches, changed, graphs = process_graph(
                        "Color group: " .. group_name .. " | Group Post-Clip",
                        post_graph,
                        selected_effects,
                        target_enabled
                    )
                    total_matches = total_matches + matches
                    total_changed = total_changed + changed
                    total_graphs = total_graphs + graphs
                end
            end
        end
    end

    return total_matches, total_changed, total_graphs
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

local function process_timeline(
    project,
    timeline,
    timeline_index,
    selected_effects,
    target_enabled,
    scope_choice,
    node_stack_layers,
    processed_groups
)
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
        return 0, 0, 0, 0
    end

    log_line("Video tracks: " .. tostring(track_count))

    local timeline_items = 0
    local timeline_graphs = 0
    local timeline_matches = 0
    local timeline_changed = 0

    if scope_includes(scope_choice, "Timeline") then
        local timeline_graph = get_timeline_graph(timeline)
        if timeline_graph then
            local matches, changed, graphs = process_graph(
                "Timeline " .. timeline_index .. " (" .. timeline_name .. ") | Timeline nodes",
                timeline_graph,
                selected_effects,
                target_enabled
            )
            timeline_matches = timeline_matches + matches
            timeline_changed = timeline_changed + changed
            timeline_graphs = timeline_graphs + graphs
        else
            log_line("Timeline " .. timeline_index .. " (" .. timeline_name .. ") skipped, no timeline node graph")
        end
    end

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
                    local matches, changed, graphs = process_item(
                        item,
                        timeline_index,
                        timeline_name,
                        track_index,
                        item_index,
                        selected_effects,
                        target_enabled,
                        scope_choice,
                        node_stack_layers,
                        processed_groups
                    )
                    timeline_matches = timeline_matches + matches
                    timeline_changed = timeline_changed + changed
                    timeline_graphs = timeline_graphs + graphs
                end
            end
        end
    end

    log_line("Timeline items scanned: " .. tostring(timeline_items))
    log_line("Node graphs scanned: " .. tostring(timeline_graphs))
    log_line("Matching nodes found: " .. tostring(timeline_matches))
    log_line("Nodes changed: " .. tostring(timeline_changed))
    return timeline_items, timeline_graphs, timeline_matches, timeline_changed
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

local function combo_selected_value(combo, options, default_one_based_index)
    local current_text = combo.CurrentText
    if current_text and current_text ~= "" then
        return tostring(current_text)
    end

    local index = combo.CurrentIndex
    if type(index) ~= "number" then
        return options[default_one_based_index]
    end

    return options[index] or options[index + 1] or options[default_one_based_index]
end

local function set_combo_to_choice(combo, options, choice, default_choice)
    local index = option_index(options, choice) or option_index(options, default_choice) or 1
    pcall(function()
        combo.CurrentIndex = index
    end)
    pcall(function()
        combo.CurrentText = options[index]
    end)
end

local function askuser_default_index(options, choice, default_choice)
    local index = option_index(options, choice) or option_index(options, default_choice) or 1
    return index - 1
end

local function ask_user_with_uimanager(fusion, saved_choices)
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
        Geometry = { 100, 100, 460, 190 },

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
                ui:Label{ Text = "Scope", MinimumSize = { 110, 24 } },
                ui:ComboBox{ ID = "ScopeCombo", Weight = 1 },
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
    for _, option in ipairs(TARGET_OPTIONS) do
        items.TargetCombo:AddItem(option)
    end
    for _, option in ipairs(ACTION_OPTIONS) do
        items.ActionCombo:AddItem(option)
    end
    for _, option in ipairs(SCOPE_OPTIONS) do
        items.ScopeCombo:AddItem(option)
    end
    set_combo_to_choice(items.TargetCombo, TARGET_OPTIONS, saved_choices["Target"], DEFAULT_CHOICES["Target"])
    set_combo_to_choice(items.ActionCombo, ACTION_OPTIONS, saved_choices["Action"], DEFAULT_CHOICES["Action"])
    set_combo_to_choice(items.ScopeCombo, SCOPE_OPTIONS, saved_choices["Scope"], DEFAULT_CHOICES["Scope"])

    local response = nil
    function window.On.ApplyButton.Clicked()
        response = {
            ["Target"] = combo_selected_value(items.TargetCombo, TARGET_OPTIONS, option_index(TARGET_OPTIONS, DEFAULT_CHOICES["Target"])),
            ["Action"] = combo_selected_value(items.ActionCombo, ACTION_OPTIONS, option_index(ACTION_OPTIONS, DEFAULT_CHOICES["Action"])),
            ["Scope"] = combo_selected_value(items.ScopeCombo, SCOPE_OPTIONS, option_index(SCOPE_OPTIONS, DEFAULT_CHOICES["Scope"])),
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
    local saved_choices = read_saved_choices()
    local controls = {
        { "Target", Name = "Target", "Dropdown", Options = TARGET_OPTIONS, Default = askuser_default_index(TARGET_OPTIONS, saved_choices["Target"], DEFAULT_CHOICES["Target"]) },
        { "Action", Name = "Action", "Dropdown", Options = ACTION_OPTIONS, Default = askuser_default_index(ACTION_OPTIONS, saved_choices["Action"], DEFAULT_CHOICES["Action"]) },
        { "Scope", Name = "Scope", "Dropdown", Options = SCOPE_OPTIONS, Default = askuser_default_index(SCOPE_OPTIONS, saved_choices["Scope"], DEFAULT_CHOICES["Scope"]) },
    }

    local fusion = resolve:Fusion()
    if not fusion then
        return nil, "Could not get Fusion object for the prompt."
    end

    local prompt_errors = {}
    local ok_ui, ui_response, ui_error = pcall(function()
        return ask_user_with_uimanager(fusion, saved_choices)
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
    local scope_choice = selected_dropdown_value(response["Scope"], { "Pre-Clip", "Clip", "Post-Clip", "Timeline", "All" })
    local selected_effects = selected_effects_from_choice(target_choice)
    if not selected_effects then
        log_line("ERROR: Unknown target choice: " .. tostring(target_choice))
        write_log()
        return
    end
    if not is_valid_scope(scope_choice) then
        log_line("ERROR: Unknown scope choice: " .. tostring(scope_choice))
        write_log()
        return
    end
    write_saved_choices({
        ["Target"] = target_choice,
        ["Action"] = opposite_action(action_choice),
        ["Scope"] = scope_choice,
    })

    local target_enabled = action_choice == "Enable"
    local node_stack_layers = get_node_stack_layer_count(project)
    log_line("Project: " .. tostring(project:GetName()))
    log_line("Timelines: " .. tostring(timeline_count))
    log_line("Clip node stack layers: " .. tostring(node_stack_layers))
    log_line("Target: " .. effect_labels(selected_effects))
    log_line("Action: " .. (target_enabled and "enable matching nodes" or "disable matching nodes"))
    log_line("Scope: " .. tostring(scope_choice))

    local total_items = 0
    local total_graphs = 0
    local total_matches = 0
    local total_changed = 0
    local processed_groups = {}

    for timeline_index = 1, timeline_count do
        local timeline = project:GetTimelineByIndex(timeline_index)
        if timeline then
            local items, graphs, matches, changed = process_timeline(
                project,
                timeline,
                timeline_index,
                selected_effects,
                target_enabled,
                scope_choice,
                node_stack_layers,
                processed_groups
            )
            total_items = total_items + items
            total_graphs = total_graphs + graphs
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
    log_line("Node graphs scanned: " .. tostring(total_graphs))
    log_line("Matching nodes found: " .. tostring(total_matches))
    log_line("Nodes changed: " .. tostring(total_changed))
    log_line("Log file: " .. temp_path(LOG_FILENAME))
    write_log()
end

main()
