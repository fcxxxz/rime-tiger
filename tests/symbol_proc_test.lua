package.path = "./lua/?.lua;" .. package.path

rime_api = {
  regex_match = function(text)
    return text:match("[^0-9A-Za-z%s]") ~= nil
  end,
}

local symbol_proc = require("symbol_proc")

local kAccepted = 1
local kNoop = 2

local function assert_equal(actual, expected, label)
  if actual ~= expected then
    error(string.format("%s: expected %s, got %s", label, tostring(expected), tostring(actual)), 2)
  end
end

local function key_event(repr, options)
  options = options or {}
  local keycodes = {
    semicolon = string.byte(";"),
    apostrophe = string.byte("'"),
  }
  return {
    keycode = keycodes[repr] or options.keycode or 0,
    repr = function()
      return repr
    end,
    release = function()
      return options.release or false
    end,
    alt = function()
      return options.alt or false
    end,
    ctrl = function()
      return options.ctrl or false
    end,
    shift = function()
      return options.shift or false
    end,
    caps = function()
      return options.caps or false
    end,
  }
end

local function candidate(text, candidate_type)
  return {
    text = text,
    type = candidate_type or "table",
  }
end

local function runtime(options)
  options = options or {}
  local candidates = options.candidates or {}
  local state = {
    confirmed = false,
    selected = nil,
    prepared = 0,
    prepare_calls = {},
  }
  local menu = {
    prepare = function(_, count)
      table.insert(state.prepare_calls, count)
      state.prepared = math.max(state.prepared, math.min(count, #candidates))
      return state.prepared
    end,
    get_candidate_at = function(_, index)
      if index >= state.prepared then
        return nil
      end
      return candidates[index + 1]
    end,
  }
  local segment = {
    menu = menu,
    selected_index = options.selected_index or 0,
  }
  local composition = {
    empty = function()
      return false
    end,
    back = function()
      return segment
    end,
  }
  local context = {
    composition = composition,
    input = options.input or "abcd",
    has_menu = function()
      return true
    end,
    select = function(_, index)
      state.selected = index
      segment.selected_index = index
    end,
    confirm_current_selection = function()
      state.confirmed = true
    end,
  }
  local config = {
    get_bool = function(_, path)
      assert_equal(path, "smart_candidate_selection/enabled", "processor reads the documented setting")
      return options.enabled
    end,
  }
  local env = {
    engine = {
      context = context,
      schema = {
        config = config,
        page_size = options.page_size or 9,
      },
    },
  }
  return env, state
end

local function process(options, repr, key_options)
  local env, state = runtime(options)
  symbol_proc.init(env)
  local result = symbol_proc.func(key_event(repr, key_options), env)
  return result, state
end

local function test_semicolon_skips_association_for_second_text_candidate()
  local result, state = process({
    candidates = {
      candidate("甲"),
      candidate("😀", "simplified"),
      candidate("乙"),
    },
  }, "semicolon")

  assert_equal(result, kAccepted, "semicolon consumes smart selection")
  assert_equal(state.selected, 2, "semicolon selects the second text candidate")
end

local function test_apostrophe_skips_associations_for_third_text_candidate()
  local result, state = process({
    candidates = {
      candidate("甲"),
      candidate("😀", "simplified"),
      candidate("乙"),
      candidate("✓", "simplified"),
      candidate("丙"),
    },
  }, "apostrophe")

  assert_equal(result, kAccepted, "apostrophe consumes smart selection")
  assert_equal(state.selected, 4, "apostrophe selects the third text candidate")
end

local function association_candidates(before_second, before_third)
  local candidates = { candidate("甲") }
  for _ = 1, before_second do
    table.insert(candidates, candidate("😀", "simplified"))
  end
  table.insert(candidates, candidate("乙"))
  for _ = 1, before_third or 0 do
    table.insert(candidates, candidate("✓", "simplified"))
  end
  if before_third then
    table.insert(candidates, candidate("丙"))
  end
  return candidates
end

local function test_semicolon_scans_beyond_first_candidate_page()
  local result, state = process({
    candidates = association_candidates(39),
  }, "semicolon")

  assert_equal(result, kAccepted, "semicolon consumes a later smart selection")
  assert_equal(state.selected, 40, "semicolon reaches the second text candidate beyond page one")
  assert_equal(#state.prepare_calls, 3, "later selection prepares only the needed chunks")
  assert_equal(state.prepare_calls[3], 41, "later selection grows the prepared menu by 32")
end

local function test_apostrophe_scans_multiple_candidate_chunks()
  local result, state = process({
    candidates = association_candidates(12, 30),
  }, "apostrophe")

  assert_equal(result, kAccepted, "apostrophe consumes a later smart selection")
  assert_equal(state.selected, 44, "apostrophe reaches the third text candidate across chunks")
  assert_equal(state.prepare_calls[4], 73, "third choice prepares another 32-candidate chunk")
end

local function test_smart_selection_includes_candidate_at_scan_limit()
  local result, state = process({
    candidates = association_candidates(510),
  }, "semicolon")

  assert_equal(result, kAccepted, "scan limit candidate remains selectable")
  assert_equal(state.selected, 511, "the 512th candidate is inside the scan limit")
  assert_equal(state.prepare_calls[#state.prepare_calls], 512, "scan stops at the hard limit")
end

local function test_smart_selection_does_not_scan_past_limit()
  local result, state = process({
    candidates = association_candidates(511),
  }, "semicolon")

  assert_equal(result, kNoop, "candidate beyond scan limit is not selected")
  assert_equal(state.selected, 0, "first text candidate is retained when the limit is exhausted")
  assert_equal(state.confirmed, true, "limit exhaustion preserves commit and pass-through")
  assert_equal(state.prepare_calls[#state.prepare_calls], 512, "no menu request exceeds the hard limit")
end

local function test_simplified_keycap_digit_is_skipped()
  local result, state = process({
    candidates = {
      candidate("甲"),
      candidate("1️⃣", "simplified"),
      candidate("乙"),
    },
  }, "semicolon")

  assert_equal(result, kAccepted, "keycap association is bypassed")
  assert_equal(state.selected, 2, "keycap association does not consume second choice")
end

local function test_normal_ascii_digit_counts_as_text_candidate()
  local result, state = process({
    candidates = {
      candidate("甲"),
      candidate("2", "table"),
      candidate("乙"),
    },
  }, "semicolon")

  assert_equal(result, kAccepted, "normal digit can be selected")
  assert_equal(state.selected, 1, "normal digit remains the second text candidate")
end

local function test_extension_han_counts_as_text_candidate()
  local result, state = process({
    candidates = {
      candidate("甲"),
      candidate("😀", "simplified"),
      candidate("𠀀"),
    },
  }, "semicolon")

  assert_equal(result, kAccepted, "extension Han candidate can be selected")
  assert_equal(state.selected, 2, "extension Han remains a text candidate")
end

local function test_insufficient_text_candidates_commits_first_and_passes_key()
  local result, state = process({
    candidates = {
      candidate("甲"),
      candidate("😀", "simplified"),
      candidate("✓", "simplified"),
    },
  }, "semicolon")

  assert_equal(result, kNoop, "punctuation continues after unique text candidate")
  assert_equal(state.selected, 0, "first text candidate is selected before commit")
  assert_equal(state.confirmed, true, "first text candidate is committed")
end

local function test_disabled_setting_preserves_positional_binding()
  local result, state = process({
    enabled = false,
    candidates = {
      candidate("甲"),
      candidate("😀", "simplified"),
      candidate("乙"),
    },
  }, "semicolon")

  assert_equal(result, kNoop, "disabled smart selection passes to key_binder")
  assert_equal(state.selected, nil, "disabled smart selection does not select directly")
  assert_equal(state.confirmed, false, "disabled smart selection keeps current behavior")
end

local function assert_bypasses_smart_selection(input, selected_index, repr, key_options, label)
  local result, state = process({
    input = input,
    selected_index = selected_index,
    candidates = {
      candidate("甲"),
      candidate("😀", "simplified"),
      candidate("乙"),
      candidate("丙"),
      candidate("丁"),
      candidate("戊"),
      candidate("己"),
      candidate("庚"),
      candidate("辛"),
      candidate("壬"),
      candidate("癸"),
    },
  }, repr or "semicolon", key_options)

  assert_equal(result, kNoop, label .. " passes to existing processors")
  assert_equal(state.selected, nil, label .. " does not select directly")
  assert_equal(state.confirmed, false, label .. " does not commit directly")
end

local function test_single_letter_code_keeps_positional_second_choice()
  local result, state = process({
    input = "a",
    candidates = {
      candidate("来"),
      candidate("！"),
    },
  }, "semicolon")

  assert_equal(result, kNoop, "single-letter code passes to key_binder for positional second choice")
  assert_equal(state.selected, nil, "single-letter code does not select directly")
  assert_equal(state.confirmed, false, "single-letter second-choice symbol stays positional")
end

local function test_single_letter_code_unique_candidate_still_commits()
  local result, state = process({
    input = "b",
    candidates = {
      candidate("不"),
    },
  }, "semicolon")

  assert_equal(result, kNoop, "unique candidate commits and passes the key through")
  assert_equal(state.confirmed, true, "single-letter unique candidate is committed")
end

local function test_single_letter_code_keeps_positional_third_choice()
  local result, state = process({
    input = "a",
    candidates = {
      candidate("来"),
      candidate("！"),
      candidate("的"),
    },
  }, "apostrophe")

  assert_equal(result, kNoop, "single-letter code passes apostrophe to key_binder")
  assert_equal(state.selected, nil, "single-letter third choice stays positional")
  assert_equal(state.confirmed, false, "single-letter third choice does not commit directly")
end

local function test_later_page_still_selects_second_text_candidate()
  local result, state = process({
    input = "abcd",
    selected_index = 9,
    candidates = {
      candidate("甲"),
      candidate("😀", "simplified"),
      candidate("乙"),
    },
  }, "semicolon")

  assert_equal(result, kAccepted, "semicolon keeps smart selection after paging")
  assert_equal(state.selected, 2, "paged menu still selects the second text candidate")
end

local function test_later_page_still_selects_third_text_candidate()
  local result, state = process({
    input = "abcd",
    selected_index = 18,
    candidates = {
      candidate("甲"),
      candidate("😀", "simplified"),
      candidate("乙"),
      candidate("✓", "simplified"),
      candidate("丙"),
    },
  }, "apostrophe")

  assert_equal(result, kAccepted, "apostrophe keeps smart selection after paging")
  assert_equal(state.selected, 4, "paged menu still selects the third text candidate")
end

local function test_compatibility_paths_bypass_smart_selection()
  assert_bypasses_smart_selection("\\bq", 0, "semicolon", nil, "backslash symbol menu")
  assert_bypasses_smart_selection(";bq", 0, "semicolon", nil, "semicolon quick-symbol input")
  assert_bypasses_smart_selection("a", 0, "semicolon", nil, "single-letter code")
  assert_bypasses_smart_selection("abcd", 0, "semicolon", { shift = true }, "shifted semicolon")
end

local tests = {
  test_semicolon_skips_association_for_second_text_candidate,
  test_apostrophe_skips_associations_for_third_text_candidate,
  test_semicolon_scans_beyond_first_candidate_page,
  test_apostrophe_scans_multiple_candidate_chunks,
  test_smart_selection_includes_candidate_at_scan_limit,
  test_smart_selection_does_not_scan_past_limit,
  test_simplified_keycap_digit_is_skipped,
  test_normal_ascii_digit_counts_as_text_candidate,
  test_extension_han_counts_as_text_candidate,
  test_insufficient_text_candidates_commits_first_and_passes_key,
  test_disabled_setting_preserves_positional_binding,
  test_single_letter_code_keeps_positional_second_choice,
  test_single_letter_code_unique_candidate_still_commits,
  test_single_letter_code_keeps_positional_third_choice,
  test_later_page_still_selects_second_text_candidate,
  test_later_page_still_selects_third_text_candidate,
  test_compatibility_paths_bypass_smart_selection,
}

for _, test in ipairs(tests) do
  test()
end

print("symbol_proc tests passed")
