-- 火星文候选滤镜。
-- 大字表在 mars 开关开启后才加载；关闭后释放映射表引用。

local option_state = require("option_state")
local simple_to_mars = nil
local complex_to_mars = nil
local loaded = false
local was_enabled = false
local OPTION_NAME = "mars"
local COMMAND = "\\chol"
local kAccepted = 1
local kNoop = 2
local KEY_SPACE = 0x20
local KEY_RETURN = 0xff0d

local processor = {}
local translator = {}

local function iter_chars(text)
  return text:gmatch("[%z\1-\127\194-\244][\128-\191]*")
end

local function build_maps(simple_text, complex_text, mars_text)
  local simple_map = {}
  local complex_map = {}
  local simple_iter = iter_chars(simple_text)
  local complex_iter = iter_chars(complex_text)
  local mars_iter = iter_chars(mars_text)

  while true do
    local simple_ch = simple_iter()
    local complex_ch = complex_iter()
    local mars_ch = mars_iter()
    if not simple_ch or not complex_ch or not mars_ch then
      if simple_ch or complex_ch or mars_ch then
        error("mars_data strings must have the same character length")
      end
      break
    end
    if simple_ch ~= mars_ch then
      simple_map[simple_ch] = mars_ch
    end
    if complex_ch ~= mars_ch then
      complex_map[complex_ch] = mars_ch
    end
  end

  return simple_map, complex_map
end

local function release_data()
  local had_data = loaded or simple_to_mars ~= nil or complex_to_mars ~= nil or package.loaded["mars_data"] ~= nil
  simple_to_mars = nil
  complex_to_mars = nil
  loaded = false
  package.loaded["mars_data"] = nil
  if had_data then
    collectgarbage("collect")
  end
end

local function ensure_loaded()
  if loaded then
    return
  end

  local data = require("mars_data")
  simple_to_mars, complex_to_mars = build_maps(data.simple, data.complex, data.mars)
  data.simple = nil
  data.complex = nil
  data.mars = nil
  package.loaded["mars_data"] = nil
  loaded = true
end

local function convert_text(text)
  ensure_loaded()
  local out = {}
  for ch in iter_chars(text) do
    out[#out + 1] = simple_to_mars[ch] or complex_to_mars[ch] or ch
  end
  return table.concat(out)
end

local function converted_candidate(cand, text)
  if ShadowCandidate then
    return ShadowCandidate(cand, cand.type, text, cand.comment)
  end

  local genuine = cand.get_genuine and cand:get_genuine() or cand
  genuine.text = text
  return cand
end

local function get_context(env)
  if env and env.engine and env.engine.context then
    return env.engine.context
  end
  return nil
end

local function enabled(env, force_sync)
  local context = get_context(env)
  if not context or not context.get_option then
    return option_state.get(OPTION_NAME, false, force_sync)
  end
  return option_state.sync(env, OPTION_NAME, context:get_option(OPTION_NAME) and true or false, force_sync)
end

local function selected_index(context)
  if context and context.composition and context.composition.back then
    local seg = context.composition:back()
    if seg and seg.selected_index then
      return seg.selected_index
    end
  end
  return 0
end

local function yield_candidate(seg, text, comment, quality)
  local cand = Candidate("mars_command", seg.start, seg._end, text, comment or "")
  cand.quality = quality or 1200
  yield(cand)
end

local function mars_filter(input, env)
  local context = env.engine.context
  local is_enabled = enabled(env)

  if not is_enabled then
    if was_enabled or loaded then
      release_data()
    end
    was_enabled = false
    for cand in input:iter() do
      yield(cand)
    end
    return
  end

  was_enabled = true
  if (context.input or ""):sub(1, 1) == "\\" then
    for cand in input:iter() do
      yield(cand)
    end
    return
  end

  for cand in input:iter() do
    local text = convert_text(cand.text)
    local out_cand = cand
    if text ~= cand.text then
      out_cand = converted_candidate(cand, text)
    end
    yield(out_cand)
  end
end

local function init(env)
  local context = env and env.engine and env.engine.context
  local notifier = context and context.option_update_notifier
  if notifier and notifier.connect then
    env.mars_option_update_notifier = notifier:connect(function()
      local current = context:get_option(OPTION_NAME) and true or false
      option_state.set(OPTION_NAME, current)
      if not current then
        release_data()
        was_enabled = false
      end
    end)
  end
  enabled(env, true)
end

local function fini(env)
  if env and env.mars_option_update_notifier and env.mars_option_update_notifier.disconnect then
    env.mars_option_update_notifier:disconnect()
  end
  release_data()
  was_enabled = false
end

function translator.func(input_text, seg, env)
  if input_text ~= "\\" and COMMAND:sub(1, #input_text) ~= input_text then
    return
  end

  if input_text == "\\" then
    yield_candidate(seg, COMMAND, "切换火星文", 1190)
    return
  end

  if input_text ~= COMMAND then
    yield_candidate(seg, COMMAND, "继续输入 chol", 1190)
    return
  end

  if enabled(env, true) then
    yield_candidate(seg, "火星文 开", "确认切换为火星文 关")
  else
    yield_candidate(seg, "火星文 关", "确认切换为火星文 开")
  end
end

function processor.func(key_event, env)
  if key_event:release() or key_event:alt() or key_event:ctrl() or key_event:caps() then
    return kNoop
  end

  local context = get_context(env)
  if not context or context.input ~= COMMAND then
    return kNoop
  end

  local keycode = key_event.keycode
  if keycode ~= KEY_SPACE and keycode ~= KEY_RETURN then
    return kNoop
  end
  if selected_index(context) ~= 0 then
    return kNoop
  end

  if context.set_option then
    local next_enabled = not enabled(env, true)
    if option_state.can_sync(env) then
      option_state.set(OPTION_NAME, next_enabled)
    end
    context:set_option(OPTION_NAME, next_enabled)
  end
  if context.clear then
    context:clear()
  end
  return kAccepted
end

return {
  init = init,
  fini = fini,
  func = mars_filter,
  processor = processor,
  translator = translator,
  _test_loaded = function()
    return loaded
  end,
  _test_reset = function()
    release_data()
    was_enabled = false
  end,
}
