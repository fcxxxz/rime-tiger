# Rime Skin Editor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the first version of a pure-web Rime global skin editor under `Rime皮肤编辑器/`.

**Architecture:** The app is static HTML/CSS/JavaScript. Core behavior is implemented as testable ES modules: capability detection, color conversion, skin model mapping, YAML adapter logic, backup planning, and rollback planning. Browser UI imports those modules and uses the File System Access API when available.

**Tech Stack:** Plain HTML, CSS, ES modules, Node's built-in test runner for unit tests, no build step and no package install required.

---

## File Structure

- Create `Rime皮肤编辑器/index.html`: user-facing static entry point.
- Create `Rime皮肤编辑器/styles.css`: application layout and component styles.
- Create `Rime皮肤编辑器/src/core.js`: pure functions for platform detection, capability detection, id generation, colors, YAML parsing/serialization, adapters, copy mapping, backup naming, and rollback planning.
- Create `Rime皮肤编辑器/src/app.js`: browser UI state, File System Access integration, editing interactions, save/copy/rollback workflows.
- Create `Rime皮肤编辑器/tests/core.test.mjs`: Node tests for all pure behavior.

## Tasks

### Task 1: Core Tests And Model

**Files:**
- Create: `Rime皮肤编辑器/src/core.js`
- Create: `Rime皮肤编辑器/tests/core.test.mjs`

- [ ] **Step 1: Write failing tests for capability detection, ids, colors, backup names**

Tests should assert:

- unsupported browser is blocked when `showDirectoryPicker` is missing
- macOS maps to Squirrel and Windows maps to Weasel
- Chinese/English names generate safe skin ids
- RGBA converts to and from Rime hex without exposing Rime byte order to callers
- backup folder names are human-readable and include operation summaries

- [ ] **Step 2: Run tests and verify they fail**

Run: `node --test Rime皮肤编辑器/tests/core.test.mjs`

- [ ] **Step 3: Implement minimal pure functions**

Implement:

- `detectBrowserCapabilities(env)`
- `detectPreferredPlatform(env)`
- `generateSkinId(displayName, existingIds)`
- `rimeHexToRgba(value)`
- `rgbaToRimeHex(rgba, includeAlpha)`
- `formatBackupFolderName(date, summary)`

- [ ] **Step 4: Run tests and verify they pass**

Run: `node --test Rime皮肤编辑器/tests/core.test.mjs`

### Task 2: YAML Adapters

**Files:**
- Modify: `Rime皮肤编辑器/src/core.js`
- Modify: `Rime皮肤编辑器/tests/core.test.mjs`

- [ ] **Step 1: Write failing tests for Squirrel and Weasel parsing**

Tests should use small YAML snippets with both nested and slash-path patch styles. Assert:

- Squirrel skins are read from `patch.preset_color_schemes`
- Squirrel active and dark scheme are read from `patch.style.color_scheme` and `patch.style.color_scheme_dark`
- Weasel skins are read from `patch["preset_color_schemes/id"]`
- Weasel active scheme is read from `patch["style/color_scheme"]`

- [ ] **Step 2: Run tests and verify they fail**

Run: `node --test Rime皮肤编辑器/tests/core.test.mjs`

- [ ] **Step 3: Implement parser and adapter extraction**

Implement a small YAML subset parser/serializer that handles the existing Rime custom file shape: indentation maps, quoted keys, scalars, comments ignored for parsing. Implement:

- `parseYaml(text)`
- `stringifyYaml(value)`
- `parseSquirrelConfig(text)`
- `parseWeaselConfig(text)`

- [ ] **Step 4: Run tests and verify they pass**

Run: `node --test Rime皮肤编辑器/tests/core.test.mjs`

### Task 3: Serialization, Copy Mapping, Backup And Rollback Plans

**Files:**
- Modify: `Rime皮肤编辑器/src/core.js`
- Modify: `Rime皮肤编辑器/tests/core.test.mjs`

- [ ] **Step 1: Write failing tests for writes, copy, backup manifest, rollback**

Tests should assert:

- updating a Squirrel skin preserves unrelated patch keys
- updating a Weasel skin preserves unrelated patch keys
- copying Squirrel to Weasel maps semantic color fields
- copying Weasel to Squirrel maps semantic color fields
- backup manifest records operation, platforms, skin id, and files
- rollback plan refuses missing manifest file entries

- [ ] **Step 2: Run tests and verify they fail**

Run: `node --test Rime皮肤编辑器/tests/core.test.mjs`

- [ ] **Step 3: Implement write and planning functions**

Implement:

- `updateSquirrelConfig(text, skin, options)`
- `updateWeaselConfig(text, skin, options)`
- `copySkinToPlatform(skin, targetPlatform)`
- `createBackupManifest(input)`
- `createRollbackPlan(backupEntry, currentFiles)`

- [ ] **Step 4: Run tests and verify they pass**

Run: `node --test Rime皮肤编辑器/tests/core.test.mjs`

### Task 4: Browser UI

**Files:**
- Create: `Rime皮肤编辑器/index.html`
- Create: `Rime皮肤编辑器/styles.css`
- Create: `Rime皮肤编辑器/src/app.js`
- Modify: `Rime皮肤编辑器/src/core.js`

- [ ] **Step 1: Implement the static shell**

Create the platform-first layout: top folder bar, left platform/skin list, center preview and controls, right actions and backup history.

- [ ] **Step 2: Implement browser workflows**

Wire:

- capability gate
- folder selection
- reading `squirrel.custom.yaml` and `weasel.custom.yaml`
- automatic platform selection
- skin selection
- controlled editing widgets
- live preview
- save with centralized readable backup
- copy to other platform
- rollback from backup
- redeploy prompt

- [ ] **Step 3: Run unit tests**

Run: `node --test Rime皮肤编辑器/tests/core.test.mjs`

### Task 5: Manual Verification And Review

**Files:**
- Modify as needed based on findings.

- [ ] **Step 1: Run all tests**

Run: `node --test Rime皮肤编辑器/tests/core.test.mjs`

- [ ] **Step 2: Serve app locally for browser smoke test**

Run: `python3 -m http.server 8765 --directory Rime皮肤编辑器`

Open `http://localhost:8765/` in a supported browser and check that the app shell loads.

- [ ] **Step 3: Perform two code review rounds**

Round 1: spec compliance review against `docs/superpowers/specs/2026-06-26-rime-skin-editor-design.md`.

Round 2: code quality review for maintainability, safety, and data-loss risks.

- [ ] **Step 4: Commit**

Commit source, tests, spec update, and plan. Do not commit `.DS_Store` or `.superpowers/`.
