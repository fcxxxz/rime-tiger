# Rime 虎码配置

这是虎码的 Rime 配置文件，来源于秃包版本，并在此基础上做了个人化调整。

## 方案列表

本配置把字版和词版都拆成常用版、全字集版两套独立方案：

- `tiger`：虎码官方单字
- `tiger_full`：虎码官方单字·全字集
- `tigress`：虎码官方词库
- `tigress_full`：虎码官方词库·全字集
- `PY_c`：拼音方案

常用版和全字集版是完整 schema 切换，不是运行时过滤器切换。旧版常用字模式使用 `lua_filter@core2022` 逐候选过滤；现在改为词典层面拆分，常用版不再生成非常用候选。

`lua/core2022_filter.lua` 已删除。`core2022.dict.yaml` 仅作为常用字表数据保留。

## 用户词共享

用户自定义内容迁移到共享用户层：

- `tiger.user.dict.yaml`
- `tigress.user.dict.yaml`

常用版和全字集版都会导入对应用户层。已经通过旧版 `tigress_user_words.lua` 添加或屏蔽的词，会从旧词库迁移并继续生效。

## 顿号与符号菜单

`/` 键现在只输出顿号 `、`。

旧版 `/bd`、`/pi`、`/bq` 等符号命令迁移到反斜杠：

- `\bd`：标点符号
- `\bq`：表情
- `\pi`：π
- `\sz`：色子
- `\chol`：切换火星文

输入 `\`、`\b`、`\p` 等前缀时，候选框会提示可用符号命令。

## 空码与符号顶字

`tiger`、`tiger_full`、`tigress`、`tigress_full` 都接入了空码标顶清屏和候选唯一时符号顶字：

- 空码时按符号，会清掉错误编码并吞掉这次符号。
- 候选唯一时按符号，会先上屏唯一候选，再让该符号继续生效。
- 有第二候选时不顶字，继续交给原有选重逻辑，例如 `;` 仍然选二候选，`'` 仍然选三候选。

## 虎词加词、减词、调序

该功能接入 `tigress` 和 `tigress_full`。

快捷键：

- `Ctrl+;`：进入加词模式。
- `Ctrl+'`：进入减词模式，并默认带入当前高亮候选词。
- `Enter`：在加词/减词模式中确认。
- `Esc`：退出加词/减词模式。
- `Backspace`：删除正在输入的取字编码；没有取字编码时，删除已经取到的最后一个字。
- macOS 推荐 `Ctrl+Option+方向键`；Windows/Linux 可继续使用 `Ctrl+方向键`。
- `Ctrl+上/左` 或 `Ctrl+Option+上/左`：当前高亮候选前移一位。
- `Ctrl+下/右` 或 `Ctrl+Option+下/右`：当前高亮候选后移一位。
- `Ctrl+Home` 或 `Ctrl+Option+Home`：当前高亮候选移到当前页第一位。
- `Ctrl+End` 或 `Ctrl+Option+End`：当前高亮候选移到当前页最后一位。

用户加词和调序会写入 `tigress.user.dict.yaml` 的自动生成区。减词会在匹配到的词库条目前写入禁用标记并注释原条目，同时也会在用户词库记录操作历史。

## 倒计时

输入 `\djs` 显示倒计时，第 9 位固定为“管理倒计时”。进入管理后可新增、编辑、删除和恢复默认倒计时。

新增事件名时，选“新增倒计时”后会清空输入；直接正常打编码，输入期间会显示当前事件名状态，选候选后追加到事件名并清空输入，可继续打下一段，事件名填好后按 `Enter` 进入历法选择。日期输入使用 `YYYYMMDD`，可选公历或农历。

倒计时排序使用 `Command+上/左`、`Command+下/右` 调整当前高亮倒计时的位置；虎词词序排序仍使用 `Ctrl+方向` 或 `Ctrl+Option+方向`。

## 拼音与拆分提示

拼音滤镜已去掉注释里的全角圆括号。候选框显示拼音或拆分时，可以用：

- `Ctrl+Shift+Enter`：上屏候选注释中的拼音或拆分内容。

用户设置菜单里的拼音、拆分开关后面也会提示这个快捷键。

## 火星文滤镜

`tiger`、`tiger_full`、`tigress`、`tigress_full`、`PY_c` 都接入了火星文滤镜：

- 在方案选单/选项菜单里切换 `火星文 关 \chol` / `火星文 开 \chol`。
- 输入 `\chol` 并确认候选，也可以切换火星文开关。
- 火星文、测速统计、拼音提示、拆分提示等功能开关已加入 `switcher/save_options`，并由 `lua/option_sync.lua` / `lua/option_state.lua` 做跨窗口即时同步。
- 火星文数据来自 `zhanyuzhang/text-convert` 的 `convert.js`，保存在 `lua/mars_data.lua`。
- `lua/mars.lua` 只常驻轻量滤镜壳；`mars_data.lua` 会在火星文开关开启后首次处理候选时加载，关闭后释放映射表引用并触发一次 Lua GC。
- 移植到其他 Rime 配置时，复制 `lua/mars.lua`、`lua/mars_data.lua`、`lua/option_state.lua`；需要跨窗口同步普通开关时再复制 `lua/option_sync.lua` 并加 `lua_processor@*option_sync`。目标方案里还要加 `mars` 开关、`lua_processor@*mars*processor`、`lua_translator@*mars*translator` 和 `lua_filter@*mars`；不需要改 `rime.lua` 预加载。

## 鼠须管皮肤

仓库包含 `squirrel.custom.yaml`。在 macOS 鼠须管下部署后，会使用当前配置里的皮肤和配色；Windows 小狼毫仍使用 `weasel.custom.yaml`。
