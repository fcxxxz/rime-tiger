# Rime Skin Editor Design

## Goal

Build a web-based Rime global skin editor that lets users choose a Rime configuration folder, edit frontend skins visually, switch the active skin, and copy a skin between supported frontends with automatic field mapping.

The first version targets ordinary users. It should avoid exposing Rime YAML field names in the normal workflow, should prefer selectable controls over free-form inputs, and should make every write reversible through centralized backups.

## Product Scope

The editor is a pure web app. Users can open it as a static page or hosted web page without installing Node or a local helper.

All editor source files live under the visible Chinese directory `Rime皮肤编辑器/`. The first version should keep the user-facing entry point obvious, with `Rime皮肤编辑器/index.html` as the file users can open directly.

Local configuration editing is available only in browsers that support directory access through the File System Access API. The app should use feature detection rather than browser-name detection. If the required APIs are unavailable, the app blocks local editing and tells the user to open the editor in a compatible Chromium-based browser such as Chrome, Edge, or Opera.

The editor only manages frontend global skins:

- Weasel: `weasel.custom.yaml`
- Squirrel: `squirrel.custom.yaml`

It does not edit schema-specific appearance in `*.schema.yaml`, input method behavior, dictionaries, Lua scripts, or other Rime configuration.

The editor supports both Weasel and Squirrel in the first version. It should auto-detect the likely current platform from the browser environment, then verify that choice after scanning the selected configuration folder:

- macOS defaults to Squirrel.
- Windows defaults to Weasel.
- If only one frontend custom file exists, select that frontend.
- If both files exist, keep the system-appropriate frontend selected but allow manual switching.

Saving never attempts to deploy Rime or execute system commands. After saving, the app shows a clear prompt asking the user to redeploy Rime from their input method menu.

## Browser Capability Gate

Local editing requires:

- secure context
- `showDirectoryPicker`
- `FileSystemDirectoryHandle`
- writable file handles

If any required capability is missing, show a blocking state before the folder-selection workflow. Do not provide a partial import/export workflow in the first version, because it would look similar to local editing while failing to save back to the Rime folder.

## User Interaction Model

Use a platform-first workflow.

1. User opens the editor.
2. App checks browser capability.
3. User selects the Rime configuration folder.
4. App scans supported frontend files and auto-selects the current platform.
5. User selects a frontend: Squirrel or Weasel.
6. User selects, creates, duplicates, edits, or deletes a skin for that frontend.
7. User can set a skin as the active global skin.
8. User can save with backup.
9. User can copy the current skin to the other frontend. The copy is a one-time mapped copy, not a permanent binding.
10. User can roll back to a previous backup.
11. App prompts the user to redeploy Rime.

The copy operation should be explicit:

- `Copy to Weasel`
- `Copy to Squirrel`

After copying, each platform owns its own skin entry. Later edits do not automatically sync.

## UI Principles

Prefer controlled inputs over raw text.

- Platform: segmented control or tabs.
- Skin selection: list with badges such as current, dark, Weasel only, Squirrel only.
- Layout direction: segmented control.
- Boolean settings: toggles.
- Font size, radius, spacing, shadow: slider plus numeric stepper.
- Colors: color swatch and color picker.
- Font family: menu populated from current config values and common system fonts, with an advanced manual entry option.
- Skin id: generated from display name by default. Allow advanced editing only when needed.

Normal users should see labels such as background color, candidate text, highlighted candidate, comment text, border, radius, and spacing. Raw YAML paths and unsupported fields belong in an advanced panel.

## Main Screen

The main screen has four functional areas:

- Top bar: folder selection, browser support status, detected system, selected Rime folder.
- Left sidebar: platform selector and skin list.
- Center area: live candidate-window preview and visual controls.
- Right inspector: skin metadata, active-skin controls, save, copy-to-other-platform, and backup restore entry points.

The preview should simulate common candidate-window states:

- preedit text
- candidate labels
- highlighted first candidate
- normal candidates
- comments
- horizontal and vertical layouts
- light and dark Squirrel schemes when configured

The preview is an approximation, not a replacement for redeploying and checking in the real Rime frontend.

## Data Model

Internally, represent editable skins with a frontend-neutral model:

- `platform`: `weasel` or `squirrel`
- `id`: Rime skin id
- `displayName`: user-visible name
- `author`
- `colors`: normalized RGBA values
- `layout`: normalized layout settings
- `source`: source file and YAML path
- `unsupportedFields`: fields preserved from the source but not directly edited by the first-version UI

The app should keep platform ownership explicit. A Squirrel skin and a Weasel skin with the same id are related only if the user copies one to the other.

## File Adapters

Use separate adapters for each frontend.

`SquirrelAdapter` reads and writes:

- `squirrel.custom.yaml`
- `patch.preset_color_schemes.<id>`
- `patch.style.color_scheme`
- `patch.style.color_scheme_dark`
- Squirrel layout fields such as `candidate_list_layout`, `text_orientation`, `inline_candidate`, `memorize_size`, `translucency`, `show_paging`, `candidate_format`, font fields, radius, spacing, border, and shadow-related fields.

`WeaselAdapter` reads and writes:

- `weasel.custom.yaml`
- `patch["preset_color_schemes/<id>"]`
- `patch["style/color_scheme"]`
- Weasel style and layout fields such as `horizontal`, `inline_preedit`, `preedit_type`, `vertical_auto_reverse`, font fields, label format, margins, spacing, radius, shadow, min/max size, and related layout values.

Adapters should preserve unrelated configuration as much as practical. The first version should update known paths rather than regenerate entire files from scratch.

If a supported custom file does not exist, the app may create a minimal custom file for that frontend after user confirmation.

## Color Handling

The UI stores colors as normalized RGBA.

Adapters convert normalized colors to the frontend's Rime YAML color representation. The app must not require users to know Rime color byte order or alpha placement.

The copy-to-other-platform operation maps color roles by semantic meaning, for example:

- window background
- border
- preedit text
- candidate text
- comment text
- label text
- highlighted candidate background
- highlighted candidate text
- highlighted comment text
- shadow

If a field cannot be mapped cleanly, copy the mapped fields and show a concise warning.

## Backup Strategy

Before every save that writes a file, create a centralized visible backup folder inside the selected Rime configuration folder:

`Rime皮肤编辑器备份/`

Each save creates a human-readable subfolder:

`YYYY-MM-DD HH-mm-ss <operation summary>/`

Examples:

- `2026-06-26 15-30-12 保存鼠须管-win11light`
- `2026-06-26 15-34-09 保存小狼毫-blackpink`
- `2026-06-26 15-38-22 复制鼠须管到小狼毫-win11light`

The backup subfolder contains:

- the original version of every file that will be modified
- `manifest.json`

The manifest records:

- backup creation time
- selected Rime folder name or path if available from the browser handle
- operation type
- source platform
- target platform if applicable
- skin id before and after the operation
- files backed up
- browser and platform metadata available from the web runtime

The first version must support rollback from backup. Rollback reads `manifest.json`, shows the operation summary and files that will be restored, and asks for confirmation before writing.

Rollback is itself a write operation. Before restoring backup files, create a new backup of the current files using an operation summary such as:

`2026-06-26 16-02-44 回退前备份-保存鼠须管-win11light`

Then copy files from the selected backup folder back to their original frontend custom file names.

## Save Behavior

Save order:

1. Validate browser write capability.
2. Validate selected Rime folder handle.
3. Parse current target files.
4. Validate skin id, display name, and required fields.
5. Detect id conflicts and ask whether to overwrite, save as a new id, or cancel.
6. Create the backup directory.
7. Copy original files into the backup directory.
8. Write updated YAML.
9. Re-read the written file if possible to confirm it parses.
10. Show success and redeploy instructions.

If validation, parsing, backup, or writing fails, do not continue to later steps. Avoid partial writes when possible.

## Rollback Behavior

The backup view lists backup folders from `Rime皮肤编辑器备份/`, sorted newest first. Each entry should show the human-readable folder name, operation type, platform, skin id, and files included.

Rollback flow:

1. User opens backup history.
2. User selects a backup.
3. App reads `manifest.json` and verifies that the referenced backup files still exist.
4. App shows a preview of what will be restored.
5. User confirms rollback.
6. App creates a new backup of the current target files.
7. App restores the selected backup files.
8. App re-reads restored files and refreshes the skin list.
9. App shows success and redeploy instructions.

If the manifest is missing but backup files are present, the app may offer a cautious file-level restore with a stronger warning. If any target file cannot be restored, abort before writing.

## Error Handling

Handle these cases explicitly:

- unsupported browser
- insecure context if it prevents directory access
- user cancels folder selection
- selected folder does not look like a Rime folder
- missing `weasel.custom.yaml` or `squirrel.custom.yaml`
- malformed YAML
- unsupported YAML shape
- permission denied during read or write
- skin id conflict
- platform copy with lossy field mapping
- failed backup creation
- failed rollback validation or restore
- successful save but reminder that Rime still needs redeploying

Messages should be written for non-expert users and include the next action.

## Testing And Acceptance

Acceptance tests should cover real user flows:

- Compatible browsers enter the editor; unsupported browsers are blocked.
- Selecting a Rime folder discovers `weasel.custom.yaml` and `squirrel.custom.yaml`.
- macOS defaults to Squirrel and Windows defaults to Weasel, with folder scan correcting missing files.
- Existing skins are listed with active-skin markers.
- Squirrel dark color scheme is recognized and editable enough for first-version needs.
- Visual controls update the preview immediately.
- Save creates `Rime皮肤编辑器备份/<human-readable operation>/`.
- Save writes only intended frontend skin settings and preserves unrelated configuration.
- Copy from Squirrel to Weasel creates a Weasel skin with mapped colors and layout where possible.
- Copy from Weasel to Squirrel creates a Squirrel skin with mapped colors and layout where possible.
- Malformed YAML prevents saving and shows a clear error.
- Permission or backup failure prevents writing.
- Successful save shows redeploy instructions.
- Backup history lists human-readable backup folders.
- Rollback restores a selected backup and first backs up the current state.
- Rollback refreshes the visible skin list and active skin after restoration.

Automated tests should cover:

- browser capability detection
- skin id generation
- color conversion
- Squirrel YAML parsing and serialization
- Weasel YAML parsing and serialization
- backup folder naming
- manifest generation
- backup discovery and rollback
- copy-to-other-platform field mapping
- conflict handling decisions

Manual tests should include:

- a real macOS Squirrel folder
- sample Weasel configurations
- a folder containing both frontend custom files
- a folder containing only one frontend custom file
- missing custom file creation
- malformed YAML
- duplicate skin ids

## Out Of Scope For First Version

- executing Rime deployment commands
- installing browser extensions or local helper services
- schema-specific appearance
- editing dictionaries, Lua scripts, or input behavior
- theme marketplace or cloud sync
- automatic synchronization between copied platform skins
- full fidelity rendering of every frontend-specific visual behavior
