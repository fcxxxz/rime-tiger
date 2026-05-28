--- by 晴
--[[
候选唯一时分号顶字

放在 key_binder 前面：

engine:
  processors:
    - ascii_composer
    - recognizer
    - lua_processor@*space_proc3
    - lua_processor@*semicolon_proc #候选唯一时分号顶字
    - key_binder

有第二候选时不处理，继续交给 key_binder 的分号次选。
]]

local semicolon_proc = {}

local kAccepted = 1
local kNoop = 2

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

function semicolon_proc.func(key_event, env)
  if key_event:release() or key_event:alt() or key_event:ctrl()
      or key_event:shift() or key_event:caps() then
    return kNoop
  end

  if key_event:repr() ~= "semicolon" then
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

  local second = second_candidate(seg)
  if second then
    return kNoop
  end

  context:confirm_current_selection()
  return kAccepted
end

return semicolon_proc
