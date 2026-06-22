--- by 晴
--[[
候选唯一时标点符号顶字

放在 key_binder 前面：

engine:
  processors:
    - ascii_composer
    - recognizer
    - lua_processor@*space_proc3
    - lua_processor@*symbol_proc #候选唯一时符号顶字
    - key_binder

有第二候选时不处理，继续交给 key_binder 的符号选重。
单引号是三选键，只有出现第三候选时才不处理。
唯一候选上屏后放行当前符号，让后续 speller、punctuator 等继续触发快符、反查或标点。
]]

local symbol_proc = {}

local kNoop = 2

local function is_symbol_key(key_event)
  local keycode = key_event.keycode
  if key_event:repr() == "space" or keycode < 0x21 or keycode > 0x7e then
    return false
  end

  local ch = string.char(keycode)
  return rime_api.regex_match(ch, "[^0-9A-Za-z\\s]")
end

local function first_candidate(seg)
  if not seg or not seg.menu then
    return nil
  end
  seg.menu:prepare(1)
  return seg.menu:get_candidate_at(0)
end

local function second_candidate(seg)
  if not seg or not seg.menu then
    return nil
  end
  seg.menu:prepare(2)
  return seg.menu:get_candidate_at(1)
end

local function third_candidate(seg)
  if not seg or not seg.menu then
    return nil
  end
  seg.menu:prepare(3)
  return seg.menu:get_candidate_at(2)
end

function symbol_proc.func(key_event, env)
  if key_event:release() or key_event:alt() or key_event:ctrl()
      or key_event:caps() then
    return kNoop
  end

  if not is_symbol_key(key_event) then
    return kNoop
  end

  local context = env.engine.context
  if not context:has_menu() then
    return kNoop
  end

  local seg = context.composition:back()
  local first = first_candidate(seg)
  if not first or first.text == context.input then
    return kNoop
  end

  if key_event:repr() == "apostrophe" or key_event.keycode == string.byte("'") then
    if third_candidate(seg) then
      return kNoop
    end
  else
    if second_candidate(seg) then
      return kNoop
    end
  end

  context:confirm_current_selection()
  return kNoop -- 放行当前符号，让后续处理器继续触发快符、反查或标点
end

return symbol_proc
