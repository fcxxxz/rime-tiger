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
  { code = "chol", label = "火星文" },
  { code = "py", label = "拼音" },
  { code = "zy", label = "注音" },
  { code = "tq", label = "天气" },
  { code = "yy", label = "音乐" },
  { code = "hb", label = "货币" },
  { code = "kh", label = "括号" },
  { code = "date", label = "日期" },
  { code = "frq", label = "日期" },
  { code = "orzh", label = "日期" },
  { code = "cdate", label = "农历" },
  { code = "fnl", label = "农历" },
  { code = "wtxs", label = "农历" },
  { code = "time", label = "时间" },
  { code = "fsj", label = "时间" },
  { code = "fuj", label = "时间" },
  { code = "okao", label = "时间" },
  { code = "week", label = "星期" },
  { code = "fxq", label = "星期" },
  { code = "olzh", label = "星期" },
  { code = "fjq", label = "节气" },
  { code = "lzvq", label = "节气" },
  { code = "djs", label = "倒计时/管理" },
  { code = "huma", label = "虎码官网" },
  { code = "zhmn", label = "虎码官网" },
  { code = "baidu", label = "百度" },
  { code = "bddu", label = "百度" },
  { code = "fuxl", label = "百度" },
  { code = "biying", label = "必应" },
  { code = "bing", label = "必应" },
  { code = "biyk", label = "必应" },
  { code = "htxk", label = "必应" },
  { code = "guge", label = "Google" },
  { code = "google", label = "Google" },
  { code = "hgzz", label = "Google" },
  { code = "wangpan", label = "虎码网盘" },
  { code = "whpj", label = "虎码网盘" },
  { code = "mbia", label = "虎码网盘" },
  { code = "genda", label = "跟打器" },
  { code = "gfda", label = "跟打器" },
  { code = "piua", label = "跟打器" },
  { code = "muyi", label = "跟打器" },
  { code = "emon", label = "跟打器" },
  { code = "zitong", label = "字统" },
  { code = "zits", label = "字统" },
  { code = "whib", label = "字统" },
  { code = "yedian", label = "叶典" },
  { code = "yedm", label = "叶典" },
  { code = "dnih", label = "叶典" },
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
    end
  end
end

return translator
