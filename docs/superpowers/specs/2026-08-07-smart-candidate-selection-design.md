# Smart Candidate Selection Design

## Goal

Keep emoji and symbol associations available in the candidate menu without
letting them consume Tiger's `;` second-choice key or `'` third-choice key.

The behavior applies to both `tiger` and `tigress`, which inherit the shared
processor and configuration from `tiger_base.schema.yaml`.

## Approaches Considered

### Smart selection in the existing symbol processor

Extend `lua/symbol_proc.lua` so the two choice keys count normal text
candidates while skipping emoji and symbol associations. This preserves the
visible candidate menu and keeps the behavior close to the existing
unique-candidate punctuation handling. This approach is selected.

### Reorder emoji output

Moving associations after all lexical candidates would make raw numeric
selection work, but an OpenCC simplifier emits alternatives beside each source
candidate and does not provide a stable global ordering mechanism. This
approach is rejected.

### Remove symbol associations from the emoji dictionary

Reducing `opencc/emoji.txt` would avoid some collisions but remove useful
features and require ongoing data maintenance. This approach is rejected.

## Configuration

The shared schema exposes one static setting, enabled by default:

```yaml
smart_candidate_selection:
  enabled: true  # 次选键跳过 emoji 和符号联想；false 恢复按候选位置选重
```

Users can restore the current positional behavior in
`tiger_base.custom.yaml`:

```yaml
patch:
  smart_candidate_selection/enabled: false  # false：; 选第 2 项，' 选第 3 项
```

The production setting, the user custom example, and the configuration guide
must all include a concise Chinese comment explaining both values. Missing or
invalid configuration falls back to enabled so upgrades receive the corrected
behavior.

## Selection Behavior

When enabled (updated 2026-11-02):

- `;` selects the second normal text candidate;
- `'` selects the third normal text candidate;
- candidates beginning with emoji or symbols are skipped;
- single-letter codes (一简) keep positional selection so the curated
  second-choice symbols in `tiger.user.dict.yaml` stay reachable with `;`
  and `'`;
- smart selection applies after navigating beyond the first page, so `;`
  still means "the second text candidate" instead of the second candidate on
  the currently visible page;
- scanning starts with the configured page size, then prepares 32 more
  candidates at a time until the requested text candidate is found;
- scanning stops after 512 candidates so an abnormal candidate stream cannot
  introduce unbounded key latency;
- Han text and ASCII letters count as normal text candidates;
- ASCII digits count unless the candidate is a `simplified` association, which
  covers keycap emoji such as `1️⃣`;
- when the requested text candidate does not exist, the current first text
  candidate is committed and the pressed punctuation key continues through
  the normal Rime pipeline, matching Tiger's existing unique-candidate
  behavior.

The implementation follows Moran's proven first-codepoint classification but
extends it to both Tiger choice keys. It does not classify candidates by
`cand.type` alone because other enabled simplifiers can legitimately produce
Chinese candidates with the same `simplified` type.

## Compatibility Boundaries

Smart selection does not intercept:

- explicit backslash symbol menus such as `\\bq`;
- semicolon-prefixed quick-symbol input;
- single-letter codes (一简), which keep positional selection;
- modified or released key events.

Those paths retain raw page-relative second/third selection through the
existing key bindings. When the setting is disabled, all paths retain the
current raw `; -> 2` and `' -> 3` behavior.

The processor remains before `key_binder`. It returns an accepted result only
when it directly selects a text candidate; otherwise it either preserves the
existing unique-candidate commit-and-pass-through behavior or lets
`key_binder` handle the key.

## Documentation

Document the setting in:

- `tiger_base.custom.yaml`, as a commented user override;
- `配置说明/示例.custom.yaml`, as a copyable example;
- `配置说明/配置说明.txt`, including default behavior, disable syntax, and the
  fact that explicit symbol menus are unaffected.

## Tests

Automated Lua tests cover:

- `;` skipping emoji/symbol associations to select the second text candidate;
- `'` skipping associations to select the third text candidate;
- keycap digit associations being skipped;
- ordinary Han, ASCII, and numeric candidates remaining selectable;
- insufficient text candidates using commit-and-pass-through behavior;
- backslash symbols, semicolon-prefixed input, single-letter codes, and
  disabled mode retaining positional selection;
- paged menus still receiving smart text-candidate selection;
- the setting defaulting to enabled when absent;
- schema and documentation examples containing the setting and its explanatory
  comments;
- the repository's complete existing test suite.
