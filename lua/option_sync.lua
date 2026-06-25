-- Sync common Rime options across engine contexts.

local option_state = require("option_state")

local M = {}
local kNoop = 2
local syncing = false

local COMMON_OPTIONS = {
  "ascii_punct",
  "full_shape",
  "simplification",
  "pinyin",
  "emoji_cn",
  "input_speed_stat",
  "chaifen",
  "mars",
  "charset_comment_filter",
  "udpf_switch",
}

local SCHEMA_OPTIONS = {
  PY_c = {
    "ascii_punct",
    "full_shape",
    "simplification",
    "pinyin",
    "emoji_cn",
    "mars",
    "charset_comment_filter",
    "udpf_switch",
  },
}

local function get_context(env)
  return env and env.engine and env.engine.context or nil
end

local function option_names(env)
  local schema = env and env.engine and env.engine.schema
  local schema_id = schema and schema.schema_id
  return SCHEMA_OPTIONS[schema_id] or COMMON_OPTIONS
end

local function save_options(env)
  local ctx = get_context(env)
  if ctx and ctx.get_option then
    local values = {}
    for _, name in ipairs(option_names(env)) do
      values[name] = ctx:get_option(name) and true or false
    end
    option_state.set_many(values)
  end
end

local function sync_options(env, force)
  if syncing then
    return
  end
  syncing = true
  option_state.sync_many(env, option_names(env), force)
  syncing = false
end

function M.init(env)
  local ctx = get_context(env)
  if ctx and ctx.option_update_notifier and ctx.option_update_notifier.connect then
    env.option_sync_notifier = ctx.option_update_notifier:connect(function()
      if not syncing then
        save_options(env)
      end
    end)
  end
  sync_options(env, true)
end

function M.fini(env)
  if env and env.option_sync_notifier and env.option_sync_notifier.disconnect then
    env.option_sync_notifier:disconnect()
  end
end

function M.func(key_event, env)
  if key_event and key_event.release and key_event:release() then
    return kNoop
  end
  sync_options(env, false)
  return kNoop
end

function M._test_options()
  return COMMON_OPTIONS
end

return M
