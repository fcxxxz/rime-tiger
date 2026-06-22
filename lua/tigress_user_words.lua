-- tigress_user_words.lua
-- Runtime candidate management for the Tigress schema.
--
-- Shortcuts:
--   Ctrl+;           enter word capture
--   Ctrl+'           block current candidate, or enter block capture
--   Return           confirm word capture
--   Ctrl+arrows      move current candidate in the visible candidate page
--   Ctrl+Option+arrows is the macOS-friendly alternative
--   Ctrl+Home/End or Ctrl+Option+Home/End move current candidate to page edge

local kRejected = 0
local kAccepted = 1
local kNoop = 2

local USER_WORDS_MARKER = "USER_WORDS_MARKER"
local GENERATED_START = "# " .. USER_WORDS_MARKER .. " generated-start"
local GENERATED_END = "# " .. USER_WORDS_MARKER .. " generated-end"

local config = {
    extended_dict = "tigress.user.dict.yaml",
    legacy_migration_sources = {
        "tigress.extended.dict.yaml",
        "tigress_full.extended.dict.yaml",
    },
    source_dicts = {
        "tigress.user.dict.yaml",
        "tigress.extended.dict.yaml",
        "tigress_full.extended.dict.yaml",
        "tigress.common.dict.yaml",
        "tigress_ci.common.dict.yaml",
        "tigress_simp_ci.common.dict.yaml",
        "tigress.dict.yaml",
        "tigress_ci.dict.yaml",
        "tigress_simp_ci.dict.yaml",
    },
    weight_base = 100000000000,
    weight_step = 1000,
}

local shared_state = nil

local KEY = {
    BACKSPACE = 0xff08,
    RETURN = 0xff0d,
    ESCAPE = 0xff1b,
    HOME = 0xff50,
    LEFT = 0xff51,
    UP = 0xff52,
    RIGHT = 0xff53,
    DOWN = 0xff54,
    END = 0xff57,
    SPACE = 0x20,
    APOSTROPHE = 0x27,
    PLUS = 0x2b,
    MINUS = 0x2d,
    EQUAL = 0x3d,
    SEMICOLON = 0x3b,
}

local function pathsep()
    return (package.config or "\\"):sub(1, 1)
end

local function data_path(filename)
    return rime_api.get_user_data_dir() .. pathsep() .. filename
end

local function split_tab(line)
    local fields = {}
    for field in (line .. "\t"):gmatch("(.-)\t") do
        table.insert(fields, field)
    end
    return fields
end

local function trim_cr(line)
    return (line:gsub("\r$", ""))
end

local function read_lines(filename)
    local path = data_path(filename)
    local f = io.open(path, "r")
    if not f then
        return {}
    end
    local lines = {}
    for line in f:lines() do
        table.insert(lines, trim_cr(line))
    end
    f:close()
    return lines
end

local function write_lines(filename, lines)
    local path = data_path(filename)
    local f, err = io.open(path, "w")
    if not f then
        log.error("tigress_user_words: failed to write " .. path .. ": " .. tostring(err))
        return false
    end
    for _, line in ipairs(lines) do
        f:write(line)
        f:write("\n")
    end
    f:close()
    return true
end

local function now_stamp()
    return os.date("%Y-%m-%d %H:%M:%S")
end

local function ensure_code(state, code)
    state.added[code] = state.added[code] or {}
    state.blocked[code] = state.blocked[code] or {}
    state.weights[code] = state.weights[code] or {}
end

local function set_added(state, code, text, weight)
    if not code or code == "" or not text or text == "" then
        return
    end
    ensure_code(state, code)
    state.added[code][text] = true
    state.blocked[code][text] = nil
    state.weights[code][text] = weight or state.weights[code][text] or config.weight_base
end

local function set_blocked(state, code, text)
    if not code or code == "" or not text or text == "" then
        return
    end
    ensure_code(state, code)
    state.blocked[code][text] = true
    state.added[code][text] = nil
    state.weights[code][text] = nil
end

local function is_user_layer_dict(filename)
    return filename == config.extended_dict
        or filename == "tigress.extended.dict.yaml"
        or filename == "tigress_full.extended.dict.yaml"
end

local function parse_entry(filename, line)
    if line:match("^%s*$") or line:match("^%s*#") then
        return nil
    end
    local fields = split_tab(line)
    if is_user_layer_dict(filename) then
        local text, code, weight = fields[1], fields[2], tonumber(fields[3])
        if text and code and text ~= "" and code ~= "" then
            return { text = text, code = code, weight = weight }
        end
        if text and text ~= "" and not code then
            return { text = text, code = nil, weight = nil }
        end
    else
        local text, weight, code = fields[1], tonumber(fields[2]), fields[3]
        if text and code and text ~= "" and code ~= "" then
            return { text = text, code = code, weight = weight }
        end
    end
    return nil
end

local function parse_marker(line)
    local op, code, text, value = line:match("^#%s*" .. USER_WORDS_MARKER .. "\t([a-z]+)\t([^\t]+)\t([^\t]+)\t?([^\t]*)")
    if op and code and text then
        return {
            op = op,
            code = code,
            text = text,
            value = value,
        }
    end
    return nil
end

local function contains_body_marker(lines)
    for _, line in ipairs(lines) do
        if line == "..." then
            return true
        end
    end
    return false
end

local function default_user_dict_lines()
    return {
        "# Rime dictionary: tigress.user",
        "# encoding: utf-8",
        "",
        "---",
        "name: tigress.user",
        'version: "2026.06.22"',
        "sort: by_weight",
        "use_preset_vocabulary: false",
        "columns:",
        "  - text",
        "  - code",
        "  - weight",
        "  - stem",
        "encoder:",
        "  rules:",
        "    - length_equal: 2",
        '      formula: "AaAbBaBb"',
        "    - length_equal: 3",
        '      formula: "AaBaCaCb"',
        "    - length_in_range: [4, 99]",
        '      formula: "AaBaCaZa"',
        "...",
        "",
        "# Migrated from legacy tigress extended dictionaries when present.",
    }
end

local function has_legacy_migration_marker(lines)
    for _, line in ipairs(lines) do
        if line:find(USER_WORDS_MARKER .. "\tlegacy-migrated", 1, true) then
            return true
        end
    end
    return false
end

local function collect_legacy_user_entries(existing_lines)
    local existing = {}
    for _, line in ipairs(existing_lines) do
        existing[line] = true
    end

    local rows = {}
    for _, filename in ipairs(config.legacy_migration_sources) do
        local in_body = false
        for _, line in ipairs(read_lines(filename)) do
            if not in_body then
                if line == "..." then
                    in_body = true
                end
            else
                local marker = parse_marker(line)
                if marker then
                    if not existing[line] then
                        table.insert(rows, line)
                        existing[line] = true
                    end
                else
                    local entry = parse_entry(filename, line)
                    if entry then
                        local added_raw = false
                        if not existing[line] then
                            table.insert(rows, line)
                            existing[line] = true
                            added_raw = true
                        end
                        if added_raw and entry.code and entry.code ~= "" then
                            local marker_line = "# " .. USER_WORDS_MARKER .. "\tenabled\t" .. entry.code .. "\t" .. entry.text .. "\t" .. tostring(entry.weight or config.weight_base)
                            if not existing[marker_line] then
                                table.insert(rows, marker_line)
                                existing[marker_line] = true
                            end
                        end
                    end
                end
            end
        end
    end
    return rows
end

local function append_legacy_user_entries(lines, entries)
    if #entries == 0 then
        return false
    end
    table.insert(lines, "")
    table.insert(lines, "# " .. USER_WORDS_MARKER .. "\tlegacy-migrated\t" .. now_stamp())
    for _, line in ipairs(entries) do
        table.insert(lines, line)
    end
    return true
end

local function ensure_user_dict()
    local lines = read_lines(config.extended_dict)
    local changed = false

    if #lines == 0 or not contains_body_marker(lines) then
        lines = default_user_dict_lines()
        changed = true
    end

    if not has_legacy_migration_marker(lines) then
        local entries = collect_legacy_user_entries(lines)
        if append_legacy_user_entries(lines, entries) then
            changed = true
        end
    end

    if changed then
        write_lines(config.extended_dict, lines)
    end
end

local function load_state()
    ensure_user_dict()

    local state = {
        added = {},
        blocked = {},
        weights = {},
        generated_loaded = false,
    }

    for _, filename in ipairs(config.source_dicts) do
        local in_generated = false
        for _, line in ipairs(read_lines(filename)) do
            if line == GENERATED_START then
                in_generated = true
                if filename == config.extended_dict then
                    state.generated_loaded = true
                end
            elseif line == GENERATED_END then
                in_generated = false
            else
                local marker = parse_marker(line)
                if marker then
                    if marker.op == "disabled" then
                        set_blocked(state, marker.code, marker.text)
                    elseif marker.op == "enabled" then
                        set_added(state, marker.code, marker.text, tonumber(marker.value) or config.weight_base)
                    end
                elseif in_generated then
                    local entry = parse_entry(filename, line)
                    if entry then
                        set_added(state, entry.code, entry.text, entry.weight)
                    end
                end
            end
        end
    end

    return state
end

local function get_state()
    if not shared_state then
        shared_state = load_state()
    end
    return shared_state
end

local function sorted_generated_entries(state)
    local rows = {}
    for code, texts in pairs(state.weights) do
        for text, weight in pairs(texts) do
            if not (state.blocked[code] and state.blocked[code][text]) then
                table.insert(rows, {
                    code = code,
                    text = text,
                    weight = weight or config.weight_base,
                })
            end
        end
    end
    table.sort(rows, function(a, b)
        if a.code ~= b.code then
            return a.code < b.code
        end
        return a.text < b.text
    end)
    return rows
end

local function rewrite_generated_section(state)
    local filename = config.extended_dict
    local lines = read_lines(filename)
    local out = {}
    local in_generated = false
    local found = false

    for _, line in ipairs(lines) do
        if line == GENERATED_START then
            found = true
            in_generated = true
            table.insert(out, line)
            for _, row in ipairs(sorted_generated_entries(state)) do
                table.insert(out, row.text .. "\t" .. row.code .. "\t" .. tostring(row.weight))
            end
        elseif line == GENERATED_END then
            in_generated = false
            table.insert(out, line)
        elseif not in_generated then
            table.insert(out, line)
        end
    end

    if not found then
        table.insert(out, "")
        table.insert(out, "#----------用户快捷管理（自动生成）----------#")
        table.insert(out, GENERATED_START)
        for _, row in ipairs(sorted_generated_entries(state)) do
            table.insert(out, row.text .. "\t" .. row.code .. "\t" .. tostring(row.weight))
        end
        table.insert(out, GENERATED_END)
    end

    return write_lines(filename, out)
end

local function disable_in_file(filename, code, text)
    local lines = read_lines(filename)
    local out = {}
    local changed = false

    for _, line in ipairs(lines) do
        local entry = parse_entry(filename, line)
        if entry and entry.text == text and (entry.code == code or (is_user_layer_dict(filename) and entry.code == nil)) then
            table.insert(out, "# " .. USER_WORDS_MARKER .. "\tdisabled\t" .. code .. "\t" .. text .. "\t" .. now_stamp())
            table.insert(out, "# " .. line)
            changed = true
        else
            table.insert(out, line)
        end
    end

    if changed then
        write_lines(filename, out)
    end
    return changed
end

local function append_disable_marker(code, text)
    local lines = read_lines(config.extended_dict)
    table.insert(lines, "")
    table.insert(lines, "# " .. USER_WORDS_MARKER .. "\tdisabled\t" .. code .. "\t" .. text .. "\t" .. now_stamp())
    write_lines(config.extended_dict, lines)
end

local function append_enable_marker(code, text, weight)
    local lines = read_lines(config.extended_dict)
    table.insert(lines, "")
    table.insert(lines, "# " .. USER_WORDS_MARKER .. "\tenabled\t" .. code .. "\t" .. text .. "\t" .. tostring(weight or config.weight_base) .. "\t" .. now_stamp())
    write_lines(config.extended_dict, lines)
end

local function persist_disable(state, code, text)
    set_blocked(state, code, text)
    local changed = false
    for _, filename in ipairs(config.source_dicts) do
        if disable_in_file(filename, code, text) then
            changed = true
        end
    end
    rewrite_generated_section(state)
    append_disable_marker(code, text)
end

local function persist_weight(state, code, text, weight)
    set_added(state, code, text, weight)
    rewrite_generated_section(state)
    append_enable_marker(code, text, weight)
end

local function current_segment(env)
    local ctx = env.engine.context
    local comp = ctx.composition
    if comp:empty() then
        return nil
    end
    return comp:back()
end

local function current_code(env)
    local ctx = env.engine.context
    local seg = current_segment(env)
    if seg then
        return ctx.input:sub(seg._start + 1, seg._end)
    end
    return ctx.input or ""
end

local function genuine_text(cand)
    if not cand then
        return ""
    end
    if cand.get_genuine then
        local ok, genuine = pcall(function()
            return cand:get_genuine()
        end)
        if ok and genuine and genuine.text then
            return genuine.text
        end
    end
    return cand.text or ""
end

local function is_status_candidate(cand)
    return cand and cand.type == "tigress_user_status"
end

local function selected_candidate(env)
    return env.engine.context:get_selected_candidate()
end

local function current_selected_text(env)
    return genuine_text(selected_candidate(env))
end

local function remove_last_utf8_char(text)
    local pos = utf8.offset(text, -1)
    if not pos then
        return ""
    end
    return text:sub(1, pos - 1)
end

local function capture_status_text(capture)
    local text = capture.text
    if not text or text == "" then
        text = "未取字"
    end
    local label = capture.operation == "disable" and "减词" or "加词"
    return label .. " " .. capture.code .. "：" .. text
end

local function capture_status_comment()
    return "Enter确认  Esc退出  Backspace删除"
end

local function sync_capture_state(env)
    if env.state then
        env.state.capture = env.capture
    end
end

local function update_prompt(env)
    local capture = env.capture or (env.state and env.state.capture)
    if not capture then
        return
    end
    local seg = current_segment(env)
    if seg then
        seg.prompt = "〔" .. capture_status_text(capture) .. "｜" .. capture_status_comment() .. "〕"
    end
end

local function refresh_context(ctx)
    if ctx.refresh_non_confirmed_composition then
        ctx:refresh_non_confirmed_composition()
    end
end

local function show_capture_context(env)
    if not env.capture then
        return
    end
    local ctx = env.engine.context
    local query = env.capture.query or ""
    ctx:clear()
    ctx.input = query ~= "" and query or env.capture.code
    refresh_context(ctx)
    update_prompt(env)
end

local function clear_capture(env)
    env.capture = nil
    sync_capture_state(env)
end

local function enter_capture(env, operation, default_text)
    local code = current_code(env)
    if code == "" then
        return false
    end
    env.capture = {
        code = code,
        text = default_text or "",
        query = "",
        operation = operation or "add",
    }
    sync_capture_state(env)
    show_capture_context(env)
    return true
end

local function finish_capture(env)
    if not env.capture or env.capture.text == "" then
        return false
    end
    local code = env.capture.code
    local text = env.capture.text
    if env.capture.operation == "disable" then
        persist_disable(env.state, code, text)
    else
        persist_weight(env.state, code, text, config.weight_base)
    end
    clear_capture(env)
    local ctx = env.engine.context
    ctx:clear()
    ctx.input = code
    refresh_context(ctx)
    return true
end

local function append_capture_text(env, text)
    if not env.capture or text == "" then
        return false
    end
    env.capture.text = env.capture.text .. text
    env.capture.query = ""
    sync_capture_state(env)
    show_capture_context(env)
    return true
end

local function append_capture_input(env, keycode)
    local ch = nil
    if keycode >= 0x61 and keycode <= 0x7a then
        ch = string.char(keycode)
    elseif keycode >= 0x41 and keycode <= 0x5a then
        ch = string.char(keycode + 0x20)
    end
    if not ch then
        return false
    end
    env.capture.query = (env.capture.query or "") .. ch
    sync_capture_state(env)
    show_capture_context(env)
    return true
end

local function capture_backspace(env)
    if env.capture.query and env.capture.query ~= "" then
        env.capture.query = env.capture.query:sub(1, -2)
    else
        env.capture.text = remove_last_utf8_char(env.capture.text)
    end
    sync_capture_state(env)
    show_capture_context(env)
end

local function candidate_at(env, index)
    local seg = current_segment(env)
    if not seg or not seg.menu then
        return nil
    end
    seg.menu:prepare(index + 1)
    return seg.menu:get_candidate_at(index)
end

local function capture_selection(env, keycode)
    if not env.capture or not env.capture.query or env.capture.query == "" then
        return false
    end
    local seg = current_segment(env)
    if not seg then
        return false
    end
    local index = seg.selected_index or 0
    if keycode >= 0x31 and keycode <= 0x39 then
        local page_size = env.engine.schema.page_size or 5
        local page_start = math.floor(index / page_size) * page_size
        index = page_start + (keycode - 0x31)
    elseif keycode == KEY.SEMICOLON then
        index = math.floor(index / (env.engine.schema.page_size or 5)) * (env.engine.schema.page_size or 5) + 1
    elseif keycode == KEY.APOSTROPHE then
        index = math.floor(index / (env.engine.schema.page_size or 5)) * (env.engine.schema.page_size or 5) + 2
    elseif keycode ~= KEY.SPACE and keycode ~= KEY.RETURN then
        return false
    end
    local cand = candidate_at(env, index)
    while is_status_candidate(cand) do
        index = index + 1
        cand = candidate_at(env, index)
    end
    return append_capture_text(env, genuine_text(cand))
end

local function visible_page_candidates(env)
    local seg = current_segment(env)
    if not seg or not seg.menu then
        return nil
    end
    local page_size = env.engine.schema.page_size or 5
    local selected = seg.selected_index or 0
    local page_start = math.floor(selected / page_size) * page_size
    local items = {}
    for i = 0, page_size - 1 do
        local absolute = page_start + i
        local cand = candidate_at(env, absolute)
        if cand then
            table.insert(items, {
                index = absolute,
                text = genuine_text(cand),
            })
        end
    end
    return items, selected, page_start
end

local function apply_visible_order(env, items, code)
    for i, item in ipairs(items) do
        local weight = config.weight_base - (i - 1) * config.weight_step
        set_added(env.state, code, item.text, weight)
    end
    rewrite_generated_section(env.state)
    for i, item in ipairs(items) do
        local weight = config.weight_base - (i - 1) * config.weight_step
        append_enable_marker(code, item.text, weight)
    end
end

local function select_moved_candidate(env, moved, fallback_index)
    local seg = current_segment(env)
    if not seg or not seg.menu then
        return false
    end
    local page_size = env.engine.schema.page_size or 5
    local page_start = math.floor(fallback_index / page_size) * page_size
    for offset = 0, page_size - 1 do
        local index = page_start + offset
        local cand = candidate_at(env, index)
        if cand and genuine_text(cand) == moved.text then
            seg.selected_index = index
            return true
        end
    end
    seg.selected_index = fallback_index
    return false
end

local function move_selected(env, direction)
    local code = current_code(env)
    if code == "" then
        return false
    end
    local items, selected = visible_page_candidates(env)
    if not items or #items == 0 then
        return false
    end

    local rel = nil
    for i, item in ipairs(items) do
        if item.index == selected then
            rel = i
            break
        end
    end
    if not rel then
        return false
    end

    local target = rel
    if direction == "front" then
        target = 1
    elseif direction == "back" then
        target = #items
    elseif direction == "prev" then
        target = math.max(1, rel - 1)
    elseif direction == "next" then
        target = math.min(#items, rel + 1)
    end
    if target == rel then
        return true
    end

    local moved = table.remove(items, rel)
    table.insert(items, target, moved)
    apply_visible_order(env, items, code)
    env.engine.context:refresh_non_confirmed_composition()
    select_moved_candidate(env, moved, items[target].index)
    return true
end

local function disable_selected(env)
    local code = current_code(env)
    local cand = selected_candidate(env)
    local text = genuine_text(cand)
    if code == "" or text == "" then
        return false
    end
    persist_disable(env.state, code, text)
    env.engine.context:refresh_non_confirmed_composition()
    return true
end

local function is_ctrl_shortcut(key_event)
    return key_event:ctrl() and not key_event:alt() and not key_event:shift() and not key_event:release()
end

local function is_reorder_shortcut(key_event)
    local ctrl_only = key_event:ctrl() and not key_event:alt() and not key_event:shift() and not key_event:release()
    local ctrl_option = key_event:ctrl() and key_event:alt() and not key_event:shift() and not key_event:release()
    return ctrl_only or ctrl_option
end

local function handle_reorder_shortcut(keycode, env)
    if keycode == KEY.UP or keycode == KEY.LEFT then
        return move_selected(env, "prev") and kAccepted or kNoop
    elseif keycode == KEY.DOWN or keycode == KEY.RIGHT then
        return move_selected(env, "next") and kAccepted or kNoop
    elseif keycode == KEY.HOME then
        return move_selected(env, "front") and kAccepted or kNoop
    elseif keycode == KEY.END then
        return move_selected(env, "back") and kAccepted or kNoop
    end
    return kNoop
end

local processor = {}

function processor.init(env)
    env.state = get_state()
    env.capture = nil
    sync_capture_state(env)
    env.update_notifier = env.engine.context.update_notifier:connect(function()
        update_prompt(env)
    end)
    env.select_notifier = env.engine.context.select_notifier:connect(function()
        update_prompt(env)
    end)
end

function processor.fini(env)
    if env.update_notifier then
        env.update_notifier:disconnect()
    end
    if env.select_notifier then
        env.select_notifier:disconnect()
    end
end

function processor.func(key_event, env)
    local keycode = key_event.keycode

    if env.capture then
        if keycode == KEY.RETURN and not key_event:release() then
            finish_capture(env)
            return kAccepted
        elseif keycode == KEY.ESCAPE and not key_event:release() then
            clear_capture(env)
            env.engine.context:clear()
            return kAccepted
        elseif keycode == KEY.BACKSPACE and not key_event:release() then
            capture_backspace(env)
            return kAccepted
        elseif not key_event:ctrl() and not key_event:alt() and not key_event:release()
            and (keycode == KEY.SPACE or keycode == KEY.SEMICOLON or keycode == KEY.APOSTROPHE
                 or (keycode >= 0x31 and keycode <= 0x39)) then
            capture_selection(env, keycode)
            return kAccepted
        elseif not key_event:ctrl() and not key_event:alt() and not key_event:release()
            and ((keycode >= 0x61 and keycode <= 0x7a) or (keycode >= 0x41 and keycode <= 0x5a)) then
            append_capture_input(env, keycode)
            return kAccepted
        end
        update_prompt(env)
        return kNoop
    end

    if is_ctrl_shortcut(key_event) then
        if keycode == KEY.SEMICOLON then
            return enter_capture(env, "add") and kAccepted or kNoop
        elseif keycode == KEY.APOSTROPHE then
            return enter_capture(env, "disable", current_selected_text(env)) and kAccepted or disable_selected(env) and kAccepted or kNoop
        end
    end

    if is_reorder_shortcut(key_event) then
        return handle_reorder_shortcut(keycode, env)
    end

    return kNoop
end

local filter = {}

function filter.init(env)
    env.state = get_state()
end

local function capture_status_candidate(env, capture)
    local seg = current_segment(env)
    local start = seg and seg._start or 0
    local finish = seg and seg._end or start
    return Candidate("tigress_user_status", start, finish, capture_status_text(capture), capture_status_comment())
end

local function candidate_sort_key(state, code, text, fallback)
    local weight = state.weights[code] and state.weights[code][text]
    if weight then
        return weight
    end
    return fallback
end

function filter.func(input, env)
    if env.state and env.state.capture then
        yield(capture_status_candidate(env, env.state.capture))
        if not env.state.capture.query or env.state.capture.query == "" then
            return
        end
    end

    local code = current_code(env)
    if code == "" then
        for cand in input:iter() do
            yield(cand)
        end
        return
    end

    local state = env.state
    local blocked = state.blocked[code] or {}
    local weights = state.weights[code] or {}
    local added = state.added[code] or {}
    local has_added_or_weight = next(added) ~= nil or next(weights) ~= nil

    if not has_added_or_weight then
        for cand in input:iter() do
            local text = genuine_text(cand)
            if not is_status_candidate(cand) and not blocked[text] then
                yield(cand)
            end
        end
        return
    end

    local seen = {}
    local rows = {}
    local index = 0

    for cand in input:iter() do
        local text = genuine_text(cand)
        if not is_status_candidate(cand) and not blocked[text] then
            index = index + 1
            seen[text] = true
            table.insert(rows, {
                cand = cand,
                text = text,
                index = index,
                score = candidate_sort_key(state, code, text, 0 - index),
            })
        end
    end

    for text, _ in pairs(added) do
        if not seen[text] and not blocked[text] then
            index = index + 1
            local seg = current_segment(env)
            local start = seg and seg._start or 0
            local finish = seg and seg._end or #code
            local cand = Candidate("tigress_user_word", start, finish, text, "")
            cand.quality = weights[text] or config.weight_base
            table.insert(rows, {
                cand = cand,
                text = text,
                index = index,
                score = cand.quality,
            })
        end
    end

    table.sort(rows, function(a, b)
        if a.score ~= b.score then
            return a.score > b.score
        end
        return a.index < b.index
    end)

    for _, row in ipairs(rows) do
        yield(row.cand)
    end
end

return {
    processor = processor,
    filter = filter,
}
