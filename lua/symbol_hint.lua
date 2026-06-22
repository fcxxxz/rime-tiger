local hints = {
  { code = "bd", label = "标点符号" },
  { code = "bq", label = "表情" },
  { code = "pi", label = "π" },
  { code = "fh", label = "符号" },
  { code = "jt", label = "箭头" },
  { code = "sx", label = "数学" },
  { code = "dw", label = "单位" },
  { code = "rq", label = "日期" },
  { code = "sz", label = "色子" },
  { code = "py", label = "拼音" },
  { code = "zy", label = "注音" },
  { code = "tq", label = "天气" },
  { code = "yy", label = "音乐" },
  { code = "hb", label = "货币" },
  { code = "kh", label = "括号" },
}

local function starts_with(text, prefix)
  return text:sub(1, #prefix) == prefix
end

local function translator(input, seg)
  if input:sub(1, 1) ~= "\\" then
    return
  end

  local prefix = input:sub(2)
  local count = 0
  for _, item in ipairs(hints) do
    if prefix == "" or starts_with(item.code, prefix) then
      count = count + 1
      local cand = Candidate("symbol_hint", seg.start, seg._end, "\\" .. item.code .. " " .. item.label, "继续输入 " .. item.code)
      cand.quality = -1000 - count
      yield(cand)
      if count >= 9 then
        return
      end
    end
  end
end

return translator
