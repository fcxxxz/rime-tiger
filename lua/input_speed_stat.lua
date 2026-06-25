-- Rime input speed statistics.
-- Commands use the existing backslash namespace: \tj, \tjs, \tjj, \tjx.

local M = {}
local option_state = require("option_state")

local OPTION_NAME = "input_speed_stat"
local SESSION_TIMEOUT_MS = 3000
local IDLE_SAVE_MS = 10000
local kAccepted = 1
local kNoop = 2
local KEY_SPACE = 0x20
local KEY_RETURN = 0xff0d

local state = {}
local now_ms_fn
local os_time_fn

local function now_ms()
  if now_ms_fn then
    return now_ms_fn()
  end
  if rime_api and rime_api.get_time_ms then
    return rime_api.get_time_ms()
  end
  return os.time() * 1000
end

local function now_sec()
  if os_time_fn then
    return os_time_fn()
  end
  return os.time()
end

local function new_period()
  return { chars = 0, seconds = 0.0 }
end

local function add_period(target, source)
  if type(source) ~= "table" then
    return
  end
  target.chars = target.chars + (source.chars or 0)
  target.seconds = target.seconds + (source.seconds or 0)
end

local function same_day(a, b)
  return a and b and a.year == b.year and a.month == b.month and a.day == b.day
end

local function same_month(a, b)
  return a and b and a.year == b.year and a.month == b.month
end

local function same_year(a, b)
  return a and b and a.year == b.year
end

local function reset_state()
  state = {
    stats_file = nil,
    env = nil,
    notifier = nil,
    update_notifier = nil,
    option_notifier = nil,
    dirty = false,
    last_activity_ms = 0,
    last_save_ms = 0,
    session_start_ms = 0,
    last_commit_ms = 0,
    pending_input = "",
    pending_input_start_ms = nil,
    session_chars = 0,
    session_active = false,
    notice_pending = false,
    previous_session = { speed = 0, chars = 0, seconds = 0.0 },
    stats = {
      daily = new_period(),
      monthly = new_period(),
      yearly = new_period(),
      total = new_period(),
      last_update = os.date("*t"),
    },
  }
end

reset_state()

local function stats_file(env)
  if state.stats_file then
    return state.stats_file
  end
  local base = rime_api.get_user_data_dir()
  return base .. "/lua/input_speed_stat_data.lua"
end

local function legacy_stats_files(env)
  local base = rime_api.get_user_data_dir()
  local ids = { "tiger", "tiger_full", "tigress", "tigress_full" }
  local files = {}
  if env and env.engine and env.engine.schema and env.engine.schema.schema_id then
    table.insert(ids, env.engine.schema.schema_id)
  end
  local seen = {}
  for _, id in ipairs(ids) do
    if not seen[id] then
      table.insert(files, base .. "/lua/input_speed_stat_" .. id .. ".lua")
      seen[id] = true
    end
  end
  return files
end

local function get_context(env)
  if env and env.engine and env.engine.context then
    return env.engine.context
  end
  return nil
end

local function enabled(env, force_sync)
  local ctx = get_context(env)
  if not ctx or not ctx.get_option then
    return option_state.get(OPTION_NAME, false, force_sync)
  end
  return option_state.sync(env, OPTION_NAME, ctx:get_option(OPTION_NAME) and true or false, force_sync)
end

local function serialize(tbl, indent)
  indent = indent or ""
  local next_indent = indent .. "  "
  local lines = { "{" }
  for k, v in pairs(tbl) do
    local key = type(k) == "string" and string.format("[%q]", k) or "[" .. tostring(k) .. "]"
    local val
    if type(v) == "table" then
      val = serialize(v, next_indent)
    elseif type(v) == "string" then
      val = string.format("%q", v)
    else
      val = tostring(v)
    end
    table.insert(lines, next_indent .. key .. " = " .. val .. ",")
  end
  table.insert(lines, indent .. "}")
  return table.concat(lines, "\n")
end

local function count_chars(text)
  if not text or text == "" then
    return 0
  end
  local count = 0
  local in_zwj_sequence = false
  local prev_regional = false
  local prev_was_zwj = false
  local prev_base_for_modifier = false
  for _, code in utf8.codes(text) do
    local combining_mark =
      (code >= 0x0300 and code <= 0x036F) or
      (code >= 0x1AB0 and code <= 0x1AFF) or
      (code >= 0x1DC0 and code <= 0x1DFF) or
      (code >= 0x20D0 and code <= 0x20FF) or
      (code >= 0xFE20 and code <= 0xFE2F)
    local variation_selector =
      (code >= 0xFE00 and code <= 0xFE0F) or
      (code >= 0xE0100 and code <= 0xE01EF)
    local emoji_modifier = code >= 0x1F3FB and code <= 0x1F3FF
    local regional_indicator = code >= 0x1F1E6 and code <= 0x1F1FF

    if code == 0x200D then
      in_zwj_sequence = count > 0
      prev_was_zwj = true
    elseif combining_mark or variation_selector or (emoji_modifier and prev_base_for_modifier) then
      prev_was_zwj = false
    elseif regional_indicator and prev_regional then
      prev_regional = false
      prev_was_zwj = false
      prev_base_for_modifier = true
    elseif prev_was_zwj or in_zwj_sequence then
      in_zwj_sequence = false
      prev_was_zwj = false
      prev_regional = regional_indicator
      prev_base_for_modifier = true
    else
      count = count + 1
      prev_was_zwj = false
      prev_regional = regional_indicator
      prev_base_for_modifier = true
    end
  end
  return count
end

local function format_number(number)
  local s = tostring(math.floor(number or 0))
  local out = {}
  local n = #s
  for i = 1, n do
    table.insert(out, s:sub(i, i))
    local remain = n - i
    if remain > 0 and remain % 4 == 0 then
      table.insert(out, ",")
    end
  end
  return table.concat(out)
end

local function format_duration(seconds)
  seconds = seconds or 0
  if seconds < 60 then
    return string.format("%.1f秒", seconds)
  end
  if seconds < 3600 then
    return string.format("%.1f分钟", seconds / 60)
  end
  if seconds < 86400 then
    local hours = math.floor(seconds / 3600)
    local minutes = (seconds % 3600) / 60
    if minutes > 0 then
      return string.format("%d小时%.1f分钟", hours, minutes)
    end
    return string.format("%d小时", hours)
  end
  local days = math.floor(seconds / 86400)
  local hours = math.floor((seconds % 86400) / 3600)
  local minutes = (seconds % 3600) / 60
  if hours > 0 and minutes > 0 then
    return string.format("%d天%d小时%.1f分钟", days, hours, minutes)
  end
  if hours > 0 then
    return string.format("%d天%d小时", days, hours)
  end
  if minutes > 0 then
    return string.format("%d天%.1f分钟", days, minutes)
  end
  return string.format("%d天", days)
end

local function avg_speed(period)
  if period.seconds and period.seconds > 0 then
    return math.floor(period.chars / period.seconds * 60 + 0.5)
  end
  return 0
end

local function mark_dirty()
  state.dirty = true
  state.last_activity_ms = now_ms()
end

local function mark_dirty_without_activity()
  state.dirty = true
end

local function update_date_stats()
  local current = os.date("*t", now_sec())
  local last = state.stats.last_update or current

  if current.year ~= last.year or current.month ~= last.month or current.day ~= last.day then
    state.stats.daily = new_period()
  end
  if current.year ~= last.year or current.month ~= last.month then
    state.stats.monthly = new_period()
  end
  if current.year ~= last.year then
    state.stats.yearly = new_period()
  end

  state.stats.last_update = current
end

local function add_period_seconds(seconds)
  state.stats.daily.seconds = state.stats.daily.seconds + seconds
  state.stats.monthly.seconds = state.stats.monthly.seconds + seconds
  state.stats.yearly.seconds = state.stats.yearly.seconds + seconds
  state.stats.total.seconds = state.stats.total.seconds + seconds
end

local function finish_session()
  if not state.session_active or state.session_chars <= 0 then
    state.session_active = false
    return false
  end

  local duration_ms = state.last_commit_ms - state.session_start_ms
  local seconds = duration_ms / 1000.0
  if seconds <= 0 then
    state.session_active = false
    return false
  end

  local speed = math.floor(state.session_chars / seconds * 60 + 0.5)
  state.previous_session = { speed = speed, chars = state.session_chars, seconds = seconds }
  add_period_seconds(seconds)
  state.session_active = false
  mark_dirty_without_activity()
  return true
end

local function maybe_finish_idle_session()
  if state.session_active and now_ms() - state.last_commit_ms > SESSION_TIMEOUT_MS then
    finish_session()
  end
end

local function maybe_idle_save()
  if state.dirty and not state.session_active and now_ms() - state.last_activity_ms >= IDLE_SAVE_MS then
    M.save(false)
  end
end

function M.save(force)
  if not force and not state.dirty then
    return
  end
  local file = io.open(stats_file(state.env), "w")
  if not file then
    return
  end

  local data = {
    stats = state.stats,
    previous_session = state.previous_session,
  }
  file:write("return " .. serialize(data) .. "\n")
  file:close()
  state.dirty = false
  state.last_save_ms = now_ms()
end

local function handle_disabled()
  if state.session_active then
    finish_session()
    M.save(false)
  end
end

local function load_stats(env)
  local path = stats_file(env)
  local ok, data = pcall(function()
    local f = io.open(path, "r")
    if not f then
      return nil
    end
    f:close()
    return dofile(path)
  end)

  if not ok or type(data) ~= "table" then
    local migrated = false
    for _, legacy_path in ipairs(legacy_stats_files(env)) do
      local legacy_ok, legacy_data = pcall(function()
        local f = io.open(legacy_path, "r")
        if not f then
          return nil
        end
        f:close()
        return dofile(legacy_path)
      end)
      if legacy_ok and type(legacy_data) == "table" and type(legacy_data.stats) == "table" then
        local current = os.date("*t", now_sec())
        local legacy_date = legacy_data.stats.last_update
        if same_day(current, legacy_date) then
          add_period(state.stats.daily, legacy_data.stats.daily)
        end
        if same_month(current, legacy_date) then
          add_period(state.stats.monthly, legacy_data.stats.monthly)
        end
        if same_year(current, legacy_date) then
          add_period(state.stats.yearly, legacy_data.stats.yearly)
        end
        add_period(state.stats.total, legacy_data.stats.total)
        migrated = true
      end
    end
    if migrated then
      update_date_stats()
      mark_dirty()
    end
    return
  end
  if type(data.stats) == "table" then
    state.stats.daily = data.stats.daily or new_period()
    state.stats.monthly = data.stats.monthly or new_period()
    state.stats.yearly = data.stats.yearly or new_period()
    state.stats.total = data.stats.total or new_period()
    state.stats.last_update = data.stats.last_update or os.date("*t", now_sec())
  end
  if type(data.previous_session) == "table" then
    state.previous_session = {
      speed = data.previous_session.speed or 0,
      chars = data.previous_session.chars or 0,
      seconds = data.previous_session.seconds or 0.0,
    }
  end
  update_date_stats()
end

local function start_session(current_ms)
  state.session_start_ms = current_ms
  state.last_commit_ms = current_ms
  state.session_chars = 0
  state.session_active = true
end

function M.record_commit_text(text, env, input_start_ms)
  if not enabled(env) then
    handle_disabled()
    return
  end

  local len = count_chars(text)
  if len < 1 then
    return
  end

  update_date_stats()
  local current_ms = now_ms()
  local start_ms = input_start_ms or current_ms
  if start_ms > current_ms then
    start_ms = current_ms
  end
  if not state.session_active or current_ms - state.last_commit_ms > SESSION_TIMEOUT_MS then
    if state.session_active then
      finish_session()
    end
    start_session(start_ms)
  elseif start_ms < state.session_start_ms then
    state.session_start_ms = start_ms
  end

  state.session_chars = state.session_chars + len
  state.last_commit_ms = current_ms

  state.stats.daily.chars = state.stats.daily.chars + len
  state.stats.monthly.chars = state.stats.monthly.chars + len
  state.stats.yearly.chars = state.stats.yearly.chars + len
  state.stats.total.chars = state.stats.total.chars + len
  mark_dirty()
end

local function speed_summary()
  maybe_finish_idle_session()
  if state.session_active and state.session_chars > 0 then
    local seconds = (now_ms() - state.session_start_ms) / 1000.0
    local speed = 0
    if seconds > 0 then
      speed = math.floor(state.session_chars / seconds * 60 + 0.5)
    end
    return string.format("当前速度：%d字/分钟", speed),
      string.format("字数：%d　时间：%s", state.session_chars, format_duration(seconds))
  end
  if state.previous_session and state.previous_session.chars > 0 then
    return string.format("上次速度：%d字/分钟", state.previous_session.speed),
      string.format("字数：%d　时间：%s",
        state.previous_session.chars,
        format_duration(state.previous_session.seconds))
  end
  return "当前速度：0字/分钟", "字数：0　时间：0.0秒"
end

local function period_summary(label, period)
  return string.format("%s输入：%s字", label, format_number(period.chars)),
    string.format("平均速度：%d字/分钟　输入时长：%s", avg_speed(period), format_duration(period.seconds))
end

local function brief_summary()
  maybe_finish_idle_session()
  update_date_stats()
  return period_summary("今日", state.stats.daily)
end

local function detail_summaries()
  maybe_finish_idle_session()
  update_date_stats()
  local s = state.stats
  local rows = {}
  local text, comment = period_summary("今日", s.daily)
  table.insert(rows, { text = text, comment = comment })
  text, comment = period_summary("本月", s.monthly)
  table.insert(rows, { text = text, comment = comment })
  text, comment = period_summary("本年", s.yearly)
  table.insert(rows, { text = text, comment = comment })
  text, comment = period_summary("总计", s.total)
  table.insert(rows, { text = text, comment = comment })
  return rows
end

local function yield_candidate(seg, text, comment, quality)
  local cand = Candidate("input_speed_stat", seg.start, seg._end, text, comment or "")
  cand.quality = quality or 1000
  yield(cand)
end

local function yield_menu(seg)
  yield_candidate(seg, "\\tjs", "当前/上次速度", 1000)
  yield_candidate(seg, "\\tjj", "今日简报", 999)
  yield_candidate(seg, "\\tjx", "详细统计", 998)
end

local function set_notice(ctx, text)
  if ctx and ctx.set_property then
    ctx:set_property("input_speed_stat_notice", text)
  end
  state.notice_pending = text and text ~= ""
end

local function get_notice(ctx)
  if state.notice_pending and ctx and ctx.get_property then
    return ctx:get_property("input_speed_stat_notice") or ""
  end
  return ""
end

local function clear_notice(ctx)
  set_notice(ctx, "")
end

local function clear_pending_notice(ctx)
  if state.notice_pending then
    clear_notice(ctx)
  end
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

local translator = {}
local processor = {}

function translator.func(input, seg, env)
  state.env = env or state.env

  if input:sub(1, 3) ~= "\\tj" and input ~= "\\" then
    clear_pending_notice(get_context(env))
    maybe_finish_idle_session()
    maybe_idle_save()
    return
  end
  if input ~= "\\tj" then
    clear_pending_notice(get_context(env))
  end

  maybe_finish_idle_session()

  if input == "\\" then
    yield_candidate(seg, "\\tj", "切换测速统计", 1200)
    return
  end

  if input == "\\tj" then
    local notice = get_notice(get_context(env))
    if notice ~= "" then
      yield_candidate(seg, notice, "再次确认关闭提示", 1200)
      yield_menu(seg)
      return
    end
    if enabled(env, true) then
      yield_candidate(seg, "测速统计：开", "确认切换为测速关", 1200)
    else
      yield_candidate(seg, "测速统计：关", "确认切换为测速开", 1200)
    end
    yield_menu(seg)
    return
  end

  if input == "\\tj?" or input == "\\tjh" then
    yield_menu(seg)
    return
  end

  if input ~= "\\tjs" and input ~= "\\tjj" and input ~= "\\tjx" then
    return
  end

  if not enabled(env, true) then
    handle_disabled()
    yield_candidate(seg, "测速统计未开启", "请在方案菜单切到“测速开”", 1200)
    return
  end

  if input == "\\tjs" then
    local text, comment = speed_summary()
    yield_candidate(seg, text, comment)
    M.save(false)
  elseif input == "\\tjj" then
    local text, comment = brief_summary()
    yield_candidate(seg, text, comment)
    M.save(false)
  elseif input == "\\tjx" then
    for _, row in ipairs(detail_summaries()) do
      yield_candidate(seg, row.text, row.comment)
    end
    M.save(false)
  end
end

local function selected_command(ctx)
  local index = selected_index(ctx)
  if index == 1 then
    return "\\tjs"
  elseif index == 2 then
    return "\\tjj"
  elseif index == 3 then
    return "\\tjx"
  end
  return nil
end

local function open_command(ctx, command)
  if ctx.clear then
    ctx:clear()
  end
  ctx.input = command
  if ctx.refresh_non_confirmed_composition then
    ctx:refresh_non_confirmed_composition()
  end
end

function processor.func(key_event, env)
  if key_event:release() or key_event:alt() or key_event:ctrl() or key_event:caps() then
    return kNoop
  end

  local ctx = get_context(env)
  if not ctx or ctx.input ~= "\\tj" then
    return kNoop
  end

  local keycode = key_event.keycode
  if keycode ~= KEY_SPACE and keycode ~= KEY_RETURN then
    return kNoop
  end

  local command = selected_command(ctx)
  if command then
    clear_pending_notice(ctx)
    open_command(ctx, command)
    return kAccepted
  end
  if selected_index(ctx) ~= 0 then
    return kNoop
  end

  if get_notice(ctx) ~= "" then
    clear_notice(ctx)
    if ctx.clear then
      ctx:clear()
    end
    return kAccepted
  end

  local next_enabled = not enabled(env, true)
  if option_state.can_sync(env) then
    option_state.set(OPTION_NAME, next_enabled)
  end
  if ctx.set_option then
    ctx:set_option(OPTION_NAME, next_enabled)
  end
  if next_enabled then
    set_notice(ctx, "测速统计已开启")
  else
    handle_disabled()
    set_notice(ctx, "测速统计已关闭")
  end
  if ctx.refresh_non_confirmed_composition then
    ctx:refresh_non_confirmed_composition()
  end

  return kAccepted
end

local function commit_callback(ctx)
  if not enabled(state.env) then
    handle_disabled()
    return
  end

  local input = ctx.input or ""
  if input:sub(1, 1) == "\\" then
    return
  end

  local text = ctx:get_commit_text()
  local input_start_ms = state.pending_input_start_ms
  state.pending_input = ""
  state.pending_input_start_ms = nil
  M.record_commit_text(text, state.env, input_start_ms)
end

local function update_callback(ctx)
  maybe_finish_idle_session()
  maybe_idle_save()
  if not enabled(state.env) then
    state.pending_input = ""
    state.pending_input_start_ms = nil
    return
  end

  local input = ctx.input or ""
  if input == "" or input:sub(1, 1) == "\\" then
    state.pending_input = input
    state.pending_input_start_ms = nil
    return
  end

  if state.pending_input == "" or state.pending_input_start_ms == nil then
    state.pending_input_start_ms = now_ms()
  end
  state.pending_input = input
end

function translator.init(env)
  state.env = env
  load_stats(env)
  update_date_stats()

  local ctx = get_context(env)
  if ctx and ctx.commit_notifier and ctx.commit_notifier.connect then
    state.notifier = ctx.commit_notifier:connect(commit_callback)
  end
  if ctx and ctx.update_notifier and ctx.update_notifier.connect then
    state.update_notifier = ctx.update_notifier:connect(update_callback)
  end
  if ctx and ctx.option_update_notifier and ctx.option_update_notifier.connect then
    state.option_notifier = ctx.option_update_notifier:connect(function()
      option_state.set(OPTION_NAME, ctx:get_option(OPTION_NAME) and true or false)
    end)
  end
  enabled(env, true)
end

function translator.fini()
  if state.session_active then
    finish_session()
  end
  if state.notifier and state.notifier.disconnect then
    state.notifier:disconnect()
  end
  if state.update_notifier and state.update_notifier.disconnect then
    state.update_notifier:disconnect()
  end
  if state.option_notifier and state.option_notifier.disconnect then
    state.option_notifier:disconnect()
  end
  state.notifier = nil
  state.update_notifier = nil
  state.option_notifier = nil
  M.save(false)
end

function M._test_reset(opts)
  opts = opts or {}
  now_ms_fn = opts.now_ms
  os_time_fn = opts.os_time
  reset_state()
  state.stats_file = opts.stats_file
end

function M._test_commit(text, env, input_start_ms)
  if input_start_ms == nil then
    input_start_ms = state.pending_input_start_ms
    state.pending_input = ""
    state.pending_input_start_ms = nil
  end
  M.record_commit_text(text, env, input_start_ms)
end

function M._test_update_input(input, env)
  state.env = env
  local ctx = get_context(env)
  if ctx then
    ctx.input = input
    update_callback(ctx)
  end
end

function M._test_stats_file(env)
  return stats_file(env)
end

M.translator = translator
M.processor = processor
M.func = translator.func
M.init = translator.init
M.fini = translator.fini

return M
