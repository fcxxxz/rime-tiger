local M = {}

local kAccepted = 1
local kNoop = 2

local KEY = {
  BACKSPACE = 0xff08,
  RETURN = 0xff0d,
  ESCAPE = 0xff1b,
  SPACE = 0x20,
  SEMICOLON = 0x3b,
  APOSTROPHE = 0x27,
  UP = 0xff52,
  DOWN = 0xff54,
  LEFT = 0xff51,
  RIGHT = 0xff53,
}

-- 事件名捕获的锚点。关键约束：不能以 \ 开头——以 \ 开头的 input 会被
-- recognizer 的 punct 正则 ^\\[A-Za-z]*$ 吞掉所有字母，永远停在 punct segment、
-- 主词典出不来字（\djsm 当事件名锚点的死穴）。用 "：" 撑住候选窗口，未打字时
-- filter 隐藏它的候选、只留提示；打字时 processor 用 clear_and_set 整体替换成编码(abc)。
local NAME_ANCHOR = "："

local MODE = {
  MANAGE_MENU = "manage_menu",
  EDIT_SELECT = "edit_select",
  DELETE_SELECT = "delete_select",
  EDIT_MENU = "edit_menu",
  CAPTURE_NAME = "capture_name",
  CHOOSE_CALENDAR = "choose_calendar",
  CAPTURE_DATE = "capture_date",
  CHOOSE_REPEAT = "choose_repeat",
  NOTICE = "notice",
}

local DEFAULT_EVENTS = {
  {
    id = "default-birthday",
    name = "生日",
    calendar = "gregorian",
    year = 1998,
    month = 8,
    day = 14,
    repeat_mode = "yearly",
    enabled = true,
  },
  {
    id = "default-valentine",
    name = "情人节",
    calendar = "gregorian",
    year = 2021,
    month = 3,
    day = 14,
    repeat_mode = "yearly",
    enabled = true,
  },
}

local shared = rawget(_G, "__djs_countdown_shared")
if not shared then
  shared = {
    data_file = nil,
    now_fn = nil,
    lunar_to_gregorian_fn = nil,
    draft = nil,
    mode = nil,
    selected_event_id = nil,
    notice = nil,
    loaded_data = nil,
    ensured_dirs = {},
  }
  rawset(_G, "__djs_countdown_shared", shared)
end
shared.ensured_dirs = shared.ensured_dirs or {}

local get_context

local function pathsep()
  return (package.config or "/"):sub(1, 1)
end

local function data_file()
  if shared.data_file then
    return shared.data_file
  end
  local base = rime_api and rime_api.get_user_data_dir and rime_api.get_user_data_dir() or "."
  return base .. pathsep() .. "lua" .. pathsep() .. "djs_data.lua"
end

local function parent_dir(path)
  return path:match("^(.*)[/\\][^/\\]+$") or "."
end

local function ensure_parent(path)
  local dir = parent_dir(path)
  if shared.ensured_dirs[dir] then
    return
  end
  local sep = pathsep()
  if sep == "\\" then
    os.execute('mkdir "' .. dir .. '" >nul 2>nul')
  else
    os.execute("mkdir -p " .. string.format("%q", dir))
  end
  shared.ensured_dirs[dir] = true
end

local function now()
  if shared.now_fn then
    return shared.now_fn()
  end
  return os.time()
end

local function clone_event(event)
  local out = {}
  for k, v in pairs(event) do
    out[k] = v
  end
  return out
end

local function now_stamp()
  return os.date("%Y-%m-%d %H:%M:%S", now())
end

local function default_data()
  local stamp = now_stamp()
  local events = {}
  for index, event in ipairs(DEFAULT_EVENTS) do
    local row = clone_event(event)
    row.order = row.order or index
    row.created_at = row.created_at or stamp
    row.updated_at = row.updated_at or stamp
    table.insert(events, row)
  end
  return { version = 1, events = events }
end

local function clone_table(value)
  if type(value) ~= "table" then
    return value
  end
  local out = {}
  for k, v in pairs(value) do
    out[k] = clone_table(v)
  end
  return out
end

local function serialize_value(value, indent)
  indent = indent or ""
  local next_indent = indent .. "  "
  if type(value) == "table" then
    local lines = { "{" }
    for k, v in pairs(value) do
      local key
      if type(k) == "string" then
        key = string.format("[%q]", k)
      else
        key = "[" .. tostring(k) .. "]"
      end
      table.insert(lines, next_indent .. key .. " = " .. serialize_value(v, next_indent) .. ",")
    end
    table.insert(lines, indent .. "}")
    return table.concat(lines, "\n")
  elseif type(value) == "string" then
    return string.format("%q", value)
  elseif type(value) == "boolean" or type(value) == "number" then
    return tostring(value)
  end
  return "nil"
end

local function persisted_state()
  if not shared.mode then
    return nil
  end
  if shared.mode == MODE.NOTICE then
    return nil
  end
  return {
    mode = shared.mode,
    selected_event_id = shared.selected_event_id,
    notice = shared.notice,
    draft = clone_table(shared.draft),
  }
end

local function restore_state(data)
  if shared.mode or type(data) ~= "table" or type(data.state) ~= "table" then
    return
  end
  local state = data.state
  if type(state.mode) ~= "string" then
    return
  end
  shared.mode = state.mode
  shared.selected_event_id = state.selected_event_id
  shared.notice = state.notice
  shared.draft = type(state.draft) == "table" and clone_table(state.draft) or nil
end

function M.save(data)
  data = data or { version = 1, events = {} }
  ensure_parent(data_file())
  local file = io.open(data_file(), "w")
  if not file then
    return false
  end
  file:write("return " .. serialize_value(data) .. "\n")
  file:close()
  shared.loaded_data = data
  return true
end

local function load_data(restore_runtime_state)
  local path = data_file()
  local file = io.open(path, "r")
  if not file then
    local data = default_data()
    M.save(data)
    if restore_runtime_state ~= false then
      restore_state(data)
    end
    return data
  end
  file:close()

  local ok, data = pcall(dofile, path)
  if not ok or type(data) ~= "table" or type(data.events) ~= "table" then
    data = default_data()
    M.save(data)
    return data
  end
  data.version = data.version or 1
  shared.loaded_data = data
  if restore_runtime_state ~= false then
    restore_state(data)
  end
  return data
end

function M.load()
  return load_data(true)
end

local function persist_state()
  local data = load_data(false)
  data.state = persisted_state()
  M.save(data)
end

local function set_mode(mode)
  shared.mode = mode
  persist_state()
end

local function days_in_month(year, month)
  local days = { 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 }
  if month == 2 then
    if (year % 400 == 0) or (year % 4 == 0 and year % 100 ~= 0) then
      return 29
    end
  end
  return days[month] or 0
end

local function valid_date(year, month, day)
  year = tonumber(year)
  month = tonumber(month)
  day = tonumber(day)
  return year and month and day and year >= 1900 and year <= 2100 and month >= 1 and month <= 12 and day >= 1 and day <= days_in_month(year, month)
end

local function valid_lunar_date(year, month, day)
  year = tonumber(year)
  month = tonumber(month)
  day = tonumber(day)
  return year and month and day and year >= 1900 and year <= 2100 and month >= 1 and month <= 12 and day >= 1 and day <= 30
end

local function date_key(year, month, day)
  return string.format("%04d%02d%02d", year, month, day)
end

local function date_text(year, month, day)
  return string.format("%04d-%02d-%02d", year, month, day)
end

local function placeholder_text(index)
  return string.rep("　", index)
end

local function parse_ymd(value)
  local text = tostring(value or "")
  local y, m, d = text:match("^(%d%d%d%d)(%d%d)(%d%d)$")
  y, m, d = tonumber(y), tonumber(m), tonumber(d)
  if not valid_date(y, m, d) then
    return nil
  end
  return y, m, d
end

local function parse_ymd_parts(value)
  local text = tostring(value or ""):gsub("[^0-9]", "")
  if #text ~= 8 then
    return nil
  end
  local y, m, d = text:match("^(%d%d%d%d)(%d%d)(%d%d)$")
  return tonumber(y), tonumber(m), tonumber(d)
end

local function parse_ymd_loose(value, calendar)
  local y, m, d = parse_ymd_parts(value)
  if not y then
    return nil
  end
  if calendar == "lunar" then
    if not valid_lunar_date(y, m, d) then
      return nil
    end
    return y, m, d
  end
  if not valid_date(y, m, d) then
    return nil
  end
  return y, m, d
end

local function time_for_date(year, month, day)
  return os.time({ year = year, month = month, day = day, hour = 12, min = 0, sec = 0 })
end

local function start_of_day(t)
  local date = os.date("*t", t)
  return time_for_date(date.year, date.month, date.day)
end

local function diff_days(from_time, to_time)
  return math.floor((start_of_day(to_time) - start_of_day(from_time)) / 86400 + 0.5)
end

local function parse_gregorian_text(text)
  local y, m, d = tostring(text or ""):match("^(%d+)年(%d+)月(%d+)日$")
  y, m, d = tonumber(y), tonumber(m), tonumber(d)
  if valid_date(y, m, d) then
    return y, m, d
  end
  return nil
end

local function default_lunar_to_gregorian(year, month, day, is_leap)
  if type(shared.lunar_to_gregorian_fn) == "function" then
    return shared.lunar_to_gregorian_fn(year, month, day, is_leap)
  end
  if type(_G.LunarDate2Date) == "function" then
    local value = _G.LunarDate2Date(date_key(year, month, day), is_leap and 1 or 0)
    return parse_gregorian_text(value)
  end
  if valid_date(year, month, day) then
    return year, month, day
  end
  return nil
end

local function target_gregorian(event, from_time)
  local current = os.date("*t", from_time)
  local year = tonumber(event.year)
  local month = tonumber(event.month)
  local day = tonumber(event.day)
  if not year or not month or not day then
    return nil
  end

  if event.calendar == "lunar" then
    if event.repeat_mode == "yearly" then
      local y = current.year
      for _ = 1, 3 do
        local gy, gm, gd = default_lunar_to_gregorian(y, month, day, event.is_leap)
        if gy then
          local target_time = time_for_date(gy, gm, gd)
          if diff_days(from_time, target_time) >= 0 then
            return gy, gm, gd
          end
        end
        y = y + 1
      end
      return nil
    end
    return default_lunar_to_gregorian(year, month, day, event.is_leap)
  end

  if event.repeat_mode == "yearly" then
    local y = current.year
    if not valid_date(y, month, day) then
      return nil
    end
    local target_time = time_for_date(y, month, day)
    if diff_days(from_time, target_time) < 0 then
      y = y + 1
    end
    if not valid_date(y, month, day) then
      return nil
    end
    return y, month, day
  end

  if not valid_date(year, month, day) then
    return nil
  end
  return year, month, day
end

function M.countdown_rows(events, from_time)
  from_time = from_time or now()
  local rows = {}
  for index, event in ipairs(events or {}) do
    if event.enabled ~= false then
      local y, m, d = target_gregorian(event, from_time)
      if y then
        local days = diff_days(from_time, time_for_date(y, m, d))
        local calendar = event.calendar == "lunar" and "农历" or "公历"
        local date_comment = string.format("%s %04d-%02d-%02d", calendar, tonumber(event.year), tonumber(event.month), tonumber(event.day))
        local text
        if event.repeat_mode == "once" and days < 0 then
          text = string.format("%s已过%d天", event.name, math.abs(days))
        else
          text = string.format("距离%s还有%d天", event.name, days)
        end
        table.insert(rows, {
          kind = "countdown",
          event = event,
          event_index = index,
          days = days,
          target = { year = y, month = m, day = d },
          text = text,
          comment = date_comment,
        })
      end
    end
  end
  table.sort(rows, function(a, b)
    local a_order = tonumber(a.event.order)
    local b_order = tonumber(b.event.order)
    if a_order and b_order and a_order ~= b_order then
      return a_order < b_order
    elseif a_order then
      return true
    elseif b_order then
      return false
    end
    if a.days ~= b.days then
      return a.days < b.days
    end
    return tostring(a.event.name) < tostring(b.event.name)
  end)
  return rows
end

local function normalize_order(data)
  table.sort(data.events, function(a, b)
    local a_order = tonumber(a.order)
    local b_order = tonumber(b.order)
    if a_order and b_order and a_order ~= b_order then
      return a_order < b_order
    elseif a_order then
      return true
    elseif b_order then
      return false
    end
    return tostring(a.created_at or a.id or a.name) < tostring(b.created_at or b.id or b.name)
  end)
  for index, event in ipairs(data.events) do
    event.order = index
  end
end

local function assign_order(data)
  for index, event in ipairs(data.events) do
    event.order = index
  end
end

function M.menu_rows(events, from_time, page_size)
  page_size = page_size or 9
  local rows = {}
  local countdowns = M.countdown_rows(events, from_time)
  local max_countdowns = math.max(0, page_size - 1)
  for i = 1, math.min(max_countdowns, #countdowns) do
    rows[i] = countdowns[i]
    rows[i].slot = i
  end
  if page_size >= 9 then
    for i = #countdowns + 1, 8 do
      if not rows[i] then
        rows[i] = { kind = "placeholder", slot = i, text = placeholder_text(i), comment = "" }
      end
    end
    rows[9] = { kind = "manage", slot = 9, text = "管理倒计时", comment = "新增/编辑/删除" }
  else
    rows[#rows + 1] = { kind = "manage", slot = #rows + 1, text = "管理倒计时", comment = "新增/编辑/删除" }
  end
  return rows
end

local function find_event(data, id)
  for index, event in ipairs(data.events or {}) do
    if event.id == id then
      return event, index
    end
  end
  return nil
end

local function validate_event(event)
  if type(event) ~= "table" then
    return false, "事件无效"
  end
  if not event.name or event.name == "" then
    return false, "事件名不能为空"
  end
  if event.calendar ~= "gregorian" and event.calendar ~= "lunar" then
    return false, "请选择公历或农历"
  end
  if event.repeat_mode ~= "yearly" and event.repeat_mode ~= "once" then
    return false, "请选择重复方式"
  end
  local valid = event.calendar == "lunar" and valid_lunar_date(event.year, event.month, event.day) or valid_date(event.year, event.month, event.day)
  if not valid then
    return false, "日期需要是 YYYYMMDD"
  end
  return true
end

local function valid_draft_date(draft)
  if not draft then
    return false
  end
  if draft.calendar == "lunar" then
    return valid_lunar_date(draft.year, draft.month, draft.day)
  end
  return valid_date(draft.year, draft.month, draft.day)
end

local function next_id(name)
  local raw = tostring(name or "event"):gsub("[^%w]+", "-"):gsub("^-+", ""):gsub("-+$", "")
  if raw == "" then
    raw = "event"
  end
  return raw .. "-" .. tostring(now())
end

function M.add_event(event)
  local ok, err = validate_event(event)
  if not ok then
    return nil, err
  end
  local data = M.load()
  event = clone_event(event)
  event.id = event.id or next_id(event.name)
  event.enabled = event.enabled ~= false
  event.order = event.order or (#data.events + 1)
  event.created_at = event.created_at or now_stamp()
  event.updated_at = now_stamp()
  table.insert(data.events, event)
  M.save(data)
  return event
end

function M.update_event(id, fields)
  local data = M.load()
  local event = find_event(data, id)
  if not event then
    return nil
  end
  for k, v in pairs(fields or {}) do
    event[k] = v
  end
  local ok, err = validate_event(event)
  if not ok then
    return nil, err
  end
  event.updated_at = now_stamp()
  M.save(data)
  return event
end

function M.move_event(id, direction)
  local data = M.load()
  normalize_order(data)
  local _, index = find_event(data, id)
  if not index then
    return false
  end
  local target = index
  if direction == "up" then
    target = math.max(1, index - 1)
  elseif direction == "down" then
    target = math.min(#data.events, index + 1)
  else
    return false
  end
  if target == index then
    return true
  end
  data.events[index], data.events[target] = data.events[target], data.events[index]
  assign_order(data)
  M.save(data)
  return true
end

function M.delete_event(id)
  local data = M.load()
  local _, index = find_event(data, id)
  if not index then
    return false
  end
  table.remove(data.events, index)
  M.save(data)
  return true
end

function M.restore_defaults()
  local data = M.load()
  local existing = {}
  for _, event in ipairs(data.events) do
    existing[event.id] = true
  end
  local stamp = now_stamp()
  for _, event in ipairs(DEFAULT_EVENTS) do
    if not existing[event.id] then
      local row = clone_event(event)
      row.order = #data.events + 1
      row.created_at = stamp
      row.updated_at = stamp
      table.insert(data.events, row)
    end
  end
  M.save(data)
  return data
end

function M.start_add()
  shared.mode = MODE.CAPTURE_NAME
  shared.selected_event_id = nil
  shared.notice = nil
  shared.draft = {
    id = nil,
    name = "",
    name_query = "",
    calendar = "gregorian",
    year = nil,
    month = nil,
    day = nil,
    repeat_mode = "yearly",
    enabled = true,
  }
  persist_state()
  return shared.draft
end

function M.start_edit(id)
  local data = M.load()
  local event = find_event(data, id)
  if not event then
    return nil
  end
  shared.mode = MODE.EDIT_MENU
  shared.selected_event_id = id
  shared.draft = clone_event(event)
  persist_state()
  return shared.draft
end

function M.get_draft()
  M.load()
  return shared.draft
end

function M.get_mode()
  M.load()
  return shared.mode
end

function M.set_draft_field(field, value)
  if not shared.draft then
    M.start_add()
  end
  shared.draft[field] = value
  persist_state()
end

function M.clear_state()
  shared.mode = nil
  shared.selected_event_id = nil
  shared.draft = nil
  shared.notice = nil
  persist_state()
end

local function open_manage_menu()
  shared.mode = MODE.MANAGE_MENU
  shared.selected_event_id = nil
  shared.draft = nil
  shared.notice = nil
  persist_state()
end

local function set_notice(text)
  shared.mode = MODE.NOTICE
  shared.notice = text
  persist_state()
end

local function selected_event()
  if not shared.selected_event_id then
    return nil
  end
  local data = M.load()
  return find_event(data, shared.selected_event_id)
end

local function draft_summary()
  local draft = shared.draft
  if not draft then
    return ""
  end
  local name = draft.name ~= "" and draft.name or "未命名"
  local calendar = draft.calendar == "lunar" and "农历" or "公历"
  local date = draft.year and date_text(draft.year, draft.month, draft.day) or "未填日期"
  local repeat_mode = draft.repeat_mode == "once" and "一次" or "每年"
  return string.format("%s｜%s %s｜%s", name, calendar, date, repeat_mode)
end

local function candidate_at(env, index)
  local ctx = get_context(env)
  local seg = ctx and ctx.composition and ctx.composition.back and ctx.composition:back() or nil
  if not seg or not seg.menu then
    return nil
  end
  if seg.menu.prepare then
    seg.menu:prepare(index + 1)
  end
  if seg.menu.get_candidate_at then
    return seg.menu:get_candidate_at(index)
  end
  return nil
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

local function candidate_type(cand)
  if not cand then
    return ""
  end
  if cand.type then
    return cand.type
  end
  if cand.get_genuine then
    local ok, genuine = pcall(function()
      return cand:get_genuine()
    end)
    if ok and genuine and genuine.type then
      return genuine.type
    end
  end
  return ""
end

local function candidate_event_id(cand)
  if not cand then
    return nil
  end
  if cand.event_id then
    return cand.event_id
  end
  if cand.get_genuine then
    local ok, genuine = pcall(function()
      return cand:get_genuine()
    end)
    if ok and genuine and genuine.event_id then
      return genuine.event_id
    end
  end
  return nil
end

local function is_status_candidate(cand)
  local type_name = candidate_type(cand)
  return type_name == "djs_status" or type_name == "djs_capture" or type_name == "djs_notice"
end

local function remove_last_utf8_char(text)
  local pos = utf8 and utf8.offset and utf8.offset(text, -1)
  if not pos then
    return ""
  end
  return text:sub(1, pos - 1)
end

local function append_draft_text(text)
  if text and text ~= "" then
    shared.draft.name = (shared.draft.name or "") .. text
  end
end

local function has_method(value, name)
  return value and type(value[name]) == "function"
end

local function safe_key_method(key_event, name)
  if not has_method(key_event, name) then
    return false
  end
  local ok, result = pcall(function()
    return key_event[name](key_event)
  end)
  return ok and result or false
end

local function finish_draft()
  local draft = shared.draft
  if not draft then
    return false
  end
  if not valid_draft_date(draft) then
    set_notice("日期需要是 YYYYMMDD")
    return false
  end
  local saved, err
  if shared.selected_event_id then
    saved, err = M.update_event(shared.selected_event_id, draft)
  else
    saved, err = M.add_event(draft)
  end
  if not saved then
    set_notice(err or "保存失败")
    return false
  end
  set_notice("已保存：" .. saved.name)
  return true
end

local function yield_candidate(seg, type_name, text, comment, quality)
  local cand = Candidate(type_name, seg.start, seg._end, text, comment or "")
  cand.quality = quality or 1000
  yield(cand)
  return cand
end

local function yield_manage_menu(seg)
  yield_candidate(seg, "djs_action", "新增倒计时", "添加事件", 1200)
  yield_candidate(seg, "djs_action", "编辑倒计时", "选择已有事件修改", 1199)
  yield_candidate(seg, "djs_action", "删除倒计时", "直接删除事件", 1198)
  yield_candidate(seg, "djs_action", "恢复默认倒计时", "恢复生日/情人节", 1197)
  yield_candidate(seg, "djs_action", "返回倒计时", "\\djs", 1196)
end

local function yield_event_list(seg, type_name, comment)
  local data = M.load()
  for index, event in ipairs(data.events) do
    local calendar = event.calendar == "lunar" and "农历" or "公历"
    local repeat_mode = event.repeat_mode == "once" and "一次" or "每年"
    yield_candidate(
      seg,
      type_name,
      event.name,
      string.format("%d｜%s %04d-%02d-%02d｜%s", index, calendar, event.year, event.month, event.day, repeat_mode),
      1200 - index
    )
  end
  if #data.events == 0 then
    yield_candidate(seg, "djs_notice", "还没有倒计时", "请选择新增", 1200)
  end
end

local function yield_edit_menu(seg)
  local event = selected_event()
  if not event then
    yield_candidate(seg, "djs_notice", "未选择事件", "Esc退出", 1200)
    return
  end
  yield_candidate(seg, "djs_action", "改事件名", event.name, 1200)
  yield_candidate(seg, "djs_action", "改历法", event.calendar == "lunar" and "当前：农历" or "当前：公历", 1199)
  yield_candidate(seg, "djs_action", "改日期", date_text(event.year, event.month, event.day), 1198)
  yield_candidate(seg, "djs_action", "改重复", event.repeat_mode == "once" and "当前：一次" or "当前：每年", 1197)
  yield_candidate(seg, "djs_action", "保存修改", draft_summary(), 1196)
end

local function yield_calendar_menu(seg)
  yield_candidate(seg, "djs_calendar", "公历", "使用 YYYYMMDD", 1200)
  yield_candidate(seg, "djs_calendar", "农历", "使用农历年月日 YYYYMMDD", 1199)
end

local function yield_repeat_menu(seg)
  yield_candidate(seg, "djs_repeat", "每年重复", "生日/节日", 1200)
  yield_candidate(seg, "djs_repeat", "只算一次", "目标日期", 1199)
end

local function yield_state(seg)
  if shared.mode == MODE.MANAGE_MENU then
    yield_manage_menu(seg)
  elseif shared.mode == MODE.EDIT_SELECT then
    yield_event_list(seg, "djs_edit_event", "选择要编辑的事件")
  elseif shared.mode == MODE.DELETE_SELECT then
    yield_event_list(seg, "djs_delete_event", "选择即删除")
  elseif shared.mode == MODE.EDIT_MENU then
    yield_edit_menu(seg)
  elseif shared.mode == MODE.CAPTURE_NAME then
    return
  elseif shared.mode == MODE.CAPTURE_DATE then
    local date = shared.draft and shared.draft.date_input or ""
    yield_candidate(seg, "djs_capture", "日期：" .. (date ~= "" and date or "YYYYMMDD"), "输入8位数字，Enter确认", 1200)
  elseif shared.mode == MODE.CHOOSE_CALENDAR then
    yield_calendar_menu(seg)
  elseif shared.mode == MODE.CHOOSE_REPEAT then
    yield_repeat_menu(seg)
  elseif shared.mode == MODE.NOTICE then
    yield_candidate(seg, "djs_notice", shared.notice or "已完成", "Enter返回 \\djs", 1200)
  end
end

function M.translator(input, seg)
  if input == "\\djsm" then
    yield_state(seg)
    return true
  end

  if input ~= "\\djs" and input ~= "/djs" then
    return false
  end
  local data = M.load()
  local rows = M.menu_rows(data.events, now(), 9)
  for index = 1, 9 do
    local row = rows[index]
    if row then
      local quality = 1300 - index
      if row.kind == "countdown" then
        local cand = yield_candidate(seg, "djs_countdown", row.text, row.comment, quality)
        cand.event_id = row.event.id
      elseif row.kind == "manage" then
        yield_candidate(seg, "djs_manage", row.text, row.comment, quality)
      elseif row.kind == "placeholder" then
        yield_candidate(seg, "djs_placeholder", row.text, row.comment, quality)
      end
    end
  end
  return true
end

local processor = {}

get_context = function(env)
  return env and env.engine and env.engine.context
end

local function selected_index(ctx)
  if ctx and ctx.composition and ctx.composition.back then
    local seg = ctx.composition:back()
    if seg and seg.selected_index then
      return seg.selected_index
    end
  end
  return 0
end

local function selected_action_index(ctx, keycode)
  if keycode >= 0x31 and keycode <= 0x39 then
    return keycode - 0x31
  elseif keycode == KEY.SEMICOLON then
    return 1
  elseif keycode == KEY.APOSTROPHE then
    return 2
  end
  return selected_index(ctx)
end

local function is_reorder_key(key_event)
  if safe_key_method(key_event, "release") then
    return false
  end
  if safe_key_method(key_event, "super")
      and not safe_key_method(key_event, "ctrl")
      and not safe_key_method(key_event, "alt")
      and not safe_key_method(key_event, "shift") then
    return true
  end
  if has_method(key_event, "repr") then
    local ok, repr = pcall(function()
      return key_event:repr()
    end)
    if ok and type(repr) == "string" then
      local command_like = repr:find("Command", 1, true) ~= nil or repr:find("Super", 1, true) ~= nil or repr:find("Meta", 1, true) ~= nil
      local mixed_modifier = repr:find("Control", 1, true) ~= nil or repr:find("Ctrl", 1, true) ~= nil
        or repr:find("Alt", 1, true) ~= nil or repr:find("Option", 1, true) ~= nil
        or repr:find("Shift", 1, true) ~= nil
      return command_like and not mixed_modifier
    end
  end
  return false
end

local function is_name_query_input(input)
  if shared.mode ~= MODE.CAPTURE_NAME or not shared.draft then
    return false
  end
  local query = shared.draft.name_query or ""
  return query ~= "" and input == query
end

local function countdown_event_id_at_index(index)
  local data = M.load()
  local rows = M.menu_rows(data.events, now(), 9)
  local row = rows[index + 1]
  if row and row.kind == "countdown" and row.event then
    return row.event.id
  end
  return nil
end

local function move_selection_index(ctx, selected, direction)
  local data = M.load()
  local rows = M.menu_rows(data.events, now(), 9)
  local target = selected
  if direction == "up" then
    target = math.max(0, selected - 1)
  elseif direction == "down" then
    target = math.min(math.min(#rows, 8) - 1, selected + 1)
  end
  if target >= 0 and target < 8 then
    local row = rows[target + 1]
    if row and row.kind == "countdown" then
      local seg = ctx and ctx.composition and ctx.composition.back and ctx.composition:back() or nil
      if seg then
        seg.selected_index = target
      end
    end
  end
end

local function clear_and_set(ctx, input)
  if ctx.clear then
    ctx:clear()
  end
  ctx.input = input
  if ctx.refresh_non_confirmed_composition then
    ctx:refresh_non_confirmed_composition()
  end
end

local function open_state(ctx, mode)
  set_mode(mode)
  clear_and_set(ctx, "\\djsm")
end

local function handle_manage_action(index, ctx)
  if index == 0 then
    M.start_add()
    clear_and_set(ctx, NAME_ANCHOR)
    return true
  elseif index == 1 then
    open_state(ctx, MODE.EDIT_SELECT)
    return true
  elseif index == 2 then
    open_state(ctx, MODE.DELETE_SELECT)
    return true
  elseif index == 3 then
    M.restore_defaults()
    set_notice("已恢复默认倒计时")
    clear_and_set(ctx, "\\djsm")
    return true
  elseif index == 4 then
    M.clear_state()
    clear_and_set(ctx, "\\djs")
    return true
  end
  return false
end

local function data_event_by_index(index)
  local data = M.load()
  local event = data.events[index + 1]
  return event
end

local function handle_event_choice(index, ctx)
  local event = data_event_by_index(index)
  if not event then
    return false
  end
  if shared.mode == MODE.DELETE_SELECT then
    M.delete_event(event.id)
    set_notice("已删除：" .. event.name)
    clear_and_set(ctx, "\\djsm")
    return true
  end
  if shared.mode == MODE.EDIT_SELECT then
    M.start_edit(event.id)
    clear_and_set(ctx, "\\djsm")
    return true
  end
  return false
end

local function handle_edit_menu(index, ctx)
  if index == 0 then
    shared.mode = MODE.CAPTURE_NAME
    shared.draft.name = ""
    shared.draft.name_query = ""
    shared.notice = nil
  elseif index == 1 then
    set_mode(MODE.CHOOSE_CALENDAR)
  elseif index == 2 then
    shared.mode = MODE.CAPTURE_DATE
    shared.draft.date_input = ""
  elseif index == 3 then
    set_mode(MODE.CHOOSE_REPEAT)
  elseif index == 4 then
    finish_draft()
  else
    return false
  end
  persist_state()
  if shared.mode == MODE.CAPTURE_NAME then
    clear_and_set(ctx, NAME_ANCHOR)
  else
    clear_and_set(ctx, "\\djsm")
  end
  return true
end

local function handle_calendar_choice(index, ctx)
  if not shared.draft then
    return false
  end
  if index == 0 then
    shared.draft.calendar = "gregorian"
  elseif index == 1 then
    shared.draft.calendar = "lunar"
  else
    return false
  end
  shared.mode = MODE.CAPTURE_DATE
  shared.draft.date_input = ""
  persist_state()
  clear_and_set(ctx, "\\djsm")
  return true
end

local function handle_repeat_choice(index, ctx)
  if not shared.draft then
    return false
  end
  if index == 0 then
    shared.draft.repeat_mode = "yearly"
  elseif index == 1 then
    shared.draft.repeat_mode = "once"
  else
    return false
  end
  finish_draft()
  clear_and_set(ctx, "\\djsm")
  return true
end

local function append_capture_letter(keycode)
  if not shared.draft then
    return false
  end
  local ch
  if keycode >= 0x61 and keycode <= 0x7a then
    ch = string.char(keycode)
  elseif keycode >= 0x41 and keycode <= 0x5a then
    ch = string.char(keycode + 0x20)
  elseif keycode >= 0x30 and keycode <= 0x39 and shared.mode == MODE.CAPTURE_DATE then
    ch = string.char(keycode)
  end
  if not ch then
    return false
  end
  if shared.mode == MODE.CAPTURE_NAME then
    shared.draft.name_query = (shared.draft.name_query or "") .. ch
    shared.notice = nil
  elseif shared.mode == MODE.CAPTURE_DATE then
    shared.draft.date_input = (shared.draft.date_input or "") .. ch
  else
    return false
  end
  return true
end

local function handle_capture_selection(env, keycode)
  if shared.mode ~= MODE.CAPTURE_NAME then
    return false
  end
  local ctx = get_context(env)
  if not shared.draft.name_query or shared.draft.name_query == "" then
    return false
  end
  local index = selected_action_index(ctx, keycode)
  local cand = candidate_at(env, index)
  while is_status_candidate(cand) do
    index = index + 1
    cand = candidate_at(env, index)
  end
  local text = genuine_text(cand)
  if text == "" or text == "\\djsm" then
    return false
  end
  append_draft_text(text)
  shared.draft.name_query = ""
  shared.notice = nil
  persist_state()
  clear_and_set(ctx, NAME_ANCHOR)
  return true
end

local function handle_capture_return(ctx)
  if not shared.draft then
    return false
  end
  if shared.mode == MODE.CAPTURE_NAME then
    if not shared.draft.name or shared.draft.name == "" then
      shared.notice = "事件名不能为空"
      persist_state()
      clear_and_set(ctx, NAME_ANCHOR)
      return true
    elseif shared.draft.year then
      shared.mode = MODE.EDIT_MENU
    else
      shared.mode = MODE.CHOOSE_CALENDAR
    end
    shared.notice = nil
    persist_state()
    clear_and_set(ctx, "\\djsm")
    return true
  elseif shared.mode == MODE.CAPTURE_DATE then
    local y, m, d = parse_ymd_loose(shared.draft.date_input, shared.draft.calendar)
    if not y then
      set_notice("日期需要是8位数字，例如19970316")
    else
      shared.draft.year = y
      shared.draft.month = m
      shared.draft.day = d
      shared.draft.date_input = nil
      if shared.selected_event_id then
        shared.mode = MODE.EDIT_MENU
      else
        shared.mode = MODE.CHOOSE_REPEAT
      end
      persist_state()
    end
    clear_and_set(ctx, "\\djsm")
    return true
  elseif shared.mode == MODE.NOTICE then
    M.clear_state()
    clear_and_set(ctx, "\\djs")
    return true
  end
  return false
end

local function handle_backspace(ctx, persist)
  if not shared.draft then
    return false
  end
  if shared.mode == MODE.CAPTURE_NAME then
    if shared.draft.name_query and shared.draft.name_query ~= "" then
      shared.draft.name_query = shared.draft.name_query:sub(1, -2)
    else
      shared.draft.name = remove_last_utf8_char(shared.draft.name or "")
    end
    shared.notice = nil
  elseif shared.mode == MODE.CAPTURE_DATE then
    local date = shared.draft.date_input or ""
    shared.draft.date_input = date:sub(1, -2)
  else
    return false
  end
  if persist ~= false then
    persist_state()
  end
  if shared.mode == MODE.CAPTURE_NAME and shared.draft.name_query and shared.draft.name_query ~= "" then
    clear_and_set(ctx, shared.draft.name_query)
  elseif shared.mode == MODE.CAPTURE_NAME then
    clear_and_set(ctx, NAME_ANCHOR)
  else
    clear_and_set(ctx, "\\djsm")
  end
  return true
end

function processor.func(key_event, env)
  if safe_key_method(key_event, "release") or (safe_key_method(key_event, "alt") and not safe_key_method(key_event, "ctrl")) then
    return kNoop
  end
  local ctx = get_context(env)
  if not ctx then
    return kNoop
  end
  local input = ctx.input or ""
  local keycode = key_event.keycode
  local in_manage_flow = input == "\\djsm" or shared.mode == MODE.CAPTURE_NAME or shared.mode == MODE.CAPTURE_DATE
  if input == "\\djs" then
    if is_reorder_key(key_event) and (keycode == KEY.UP or keycode == KEY.LEFT or keycode == KEY.DOWN or keycode == KEY.RIGHT) then
      local selected = selected_index(ctx)
      local cand = candidate_at(env, selected)
      local event_id = candidate_event_id(cand) or countdown_event_id_at_index(selected)
      if event_id then
        local direction = (keycode == KEY.UP or keycode == KEY.LEFT) and "up" or "down"
        if M.move_event(event_id, direction) then
          move_selection_index(ctx, selected, direction)
        end
        if ctx.refresh_non_confirmed_composition then
          ctx:refresh_non_confirmed_composition()
        end
        return kAccepted
      end
      return kNoop
    end
    if safe_key_method(key_event, "ctrl") then
      return kNoop
    end
    local selected = selected_action_index(ctx, keycode)
    local selecting_candidate = keycode == KEY.SPACE or keycode == KEY.RETURN or (keycode >= 0x31 and keycode <= 0x39)
    local cand = candidate_at(env, selected)
    if selecting_candidate and (selected == 8 or candidate_type(cand) == "djs_manage") then
      open_manage_menu()
      clear_and_set(ctx, "\\djsm")
      return kAccepted
    end
    if selecting_candidate and candidate_type(cand) == "djs_placeholder" then
      return kAccepted
    end
  elseif in_manage_flow then
    if safe_key_method(key_event, "ctrl") or safe_key_method(key_event, "super") then
      return kNoop
    end
    local name_query_active = shared.mode == MODE.CAPTURE_NAME and shared.draft and shared.draft.name_query and shared.draft.name_query ~= ""
    if keycode == KEY.ESCAPE then
      M.clear_state()
      clear_and_set(ctx, "\\djs")
      return kAccepted
    elseif keycode == KEY.BACKSPACE and handle_backspace(ctx, false) then
      return kAccepted
    elseif name_query_active and (keycode == KEY.SPACE or keycode == KEY.RETURN or keycode == KEY.SEMICOLON or keycode == KEY.APOSTROPHE or (keycode >= 0x31 and keycode <= 0x39)) then
      return handle_capture_selection(env, keycode) and kAccepted or kNoop
    elseif keycode == KEY.RETURN and handle_capture_return(ctx) then
      return kAccepted
    elseif shared.mode == MODE.CAPTURE_NAME and append_capture_letter(keycode) then
      clear_and_set(ctx, shared.draft.name_query)
      return kAccepted
    elseif shared.mode == MODE.CAPTURE_DATE and append_capture_letter(keycode) then
      clear_and_set(ctx, "\\djsm")
      return kAccepted
    elseif keycode == KEY.SPACE or keycode == KEY.RETURN or keycode == KEY.SEMICOLON or keycode == KEY.APOSTROPHE or (keycode >= 0x31 and keycode <= 0x39) then
      local index = selected_action_index(ctx, keycode)
      local handled = false
      if shared.mode == MODE.MANAGE_MENU then
        handled = handle_manage_action(index, ctx)
      elseif shared.mode == MODE.EDIT_SELECT or shared.mode == MODE.DELETE_SELECT then
        handled = handle_event_choice(index, ctx)
      elseif shared.mode == MODE.EDIT_MENU then
        handled = handle_edit_menu(index, ctx)
      elseif shared.mode == MODE.CHOOSE_CALENDAR then
        handled = handle_calendar_choice(index, ctx)
      elseif shared.mode == MODE.CHOOSE_REPEAT then
        handled = handle_repeat_choice(index, ctx)
      elseif shared.mode == MODE.NOTICE then
        M.clear_state()
        clear_and_set(ctx, "\\djs")
        handled = true
      elseif shared.mode == MODE.CAPTURE_NAME or shared.mode == MODE.CAPTURE_DATE then
        -- 捕获态且未完成输入：消费空格/分号/数字等选择键，
        -- 否则会落到 key_binder 把"事件名/日期：…"状态候选上屏
        handled = true
      end
      return handled and kAccepted or kNoop
    elseif shared.mode == MODE.CAPTURE_NAME or shared.mode == MODE.CAPTURE_DATE then
      -- 捕获态落到这里的是符号等非常规键：消费掉，避免被 key_binder/symbol_proc
      -- 拿"事件名/日期：…"状态候选去上屏
      return kAccepted
    end
  end
  return kNoop
end

M.processor = processor

local filter = {}

local function current_segment(env)
  local ctx = get_context(env)
  if not ctx or not ctx.composition or not ctx.composition.back then
    return nil
  end
  return ctx.composition:back()
end

function filter.func(input, env)
  local ctx = get_context(env)
  local in_name_capture = shared.mode == MODE.CAPTURE_NAME and (is_name_query_input(ctx.input) or ctx.input == NAME_ANCHOR)
  if ctx and (in_name_capture or (ctx.input == "\\djsm" and shared.mode == MODE.CAPTURE_DATE)) then
    local seg = current_segment(env)
    local start = seg and seg.start or 0
    local finish = seg and seg._end or 0
    if shared.mode == MODE.CAPTURE_NAME then
      local name = (shared.draft and shared.draft.name) or ""
      local query = (shared.draft and shared.draft.name_query) or ""
      local text = name ~= "" and name or "未填写"
      local comment
      if shared.notice and shared.notice ~= "" then
        comment = shared.notice
      elseif query ~= "" then
        comment = "输入中：" .. query .. "，空格/回车选字"
      else
        comment = "Enter确认 Esc退出 Backspace删除"
      end
      yield(Candidate("djs_status", start, finish, "事件名：" .. text, comment))
    else
      yield(Candidate("djs_status", start, finish, "日期：" .. ((shared.draft and shared.draft.date_input) or ""), "输入YYYYMMDD Enter确认"))
    end
  end
  local hide_other_candidates = shared.mode == MODE.CAPTURE_NAME
    and (not shared.draft or not shared.draft.name_query or shared.draft.name_query == "")
  if not hide_other_candidates then
    for cand in input:iter() do
      yield(cand)
    end
  end
end

M.filter = filter
M.func = M.translator

function M._test_reset(options)
  options = options or {}
  shared.data_file = options.data_file
  shared.now_fn = options.now
  shared.lunar_to_gregorian_fn = options.lunar_to_gregorian
  shared.draft = nil
  shared.mode = nil
  shared.selected_event_id = nil
  shared.notice = nil
  shared.loaded_data = nil
  shared.ensured_dirs = {}
end

return M
