import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

import core from '../src/core.js';

const {
  detectBrowserCapabilities,
  detectPreferredPlatform,
  generateSkinId,
  rimeHexToRgba,
  rgbaToRimeHex,
  formatBackupFolderName,
  parseYaml,
  parseSquirrelConfig,
  parseWeaselConfig,
  updateSquirrelConfig,
  updateWeaselConfig,
  deleteSquirrelSkinConfig,
  deleteWeaselSkinConfig,
  copySkinToPlatform,
  createBackupManifest,
  createRollbackPlan,
} = core;

test('blocks local editing when directory picker is unavailable', () => {
  function FileSystemFileHandle() {}
  FileSystemFileHandle.prototype.createWritable = function createWritable() {};
  const result = detectBrowserCapabilities({
    isSecureContext: true,
    showDirectoryPicker: undefined,
    FileSystemDirectoryHandle: function FileSystemDirectoryHandle() {},
    FileSystemFileHandle,
  });

  assert.equal(result.canEditLocalRime, false);
  assert.match(result.reason, /不支持|支持/);
});

test('allows local editing when required file system APIs are present', () => {
  function FileSystemFileHandle() {}
  FileSystemFileHandle.prototype.createWritable = function createWritable() {};
  const result = detectBrowserCapabilities({
    isSecureContext: true,
    showDirectoryPicker() {},
    FileSystemDirectoryHandle: function FileSystemDirectoryHandle() {},
    FileSystemFileHandle,
  });

  assert.equal(result.canEditLocalRime, true);
  assert.equal(result.reason, '');
});

test('blocks local editing when writable file handles are unavailable', () => {
  const result = detectBrowserCapabilities({
    isSecureContext: true,
    showDirectoryPicker() {},
    FileSystemDirectoryHandle: function FileSystemDirectoryHandle() {},
  });

  assert.equal(result.canEditLocalRime, false);
  assert.match(result.reason, /文件|读写|支持/);
});

test('blocks local editing when file handles cannot create writable streams', () => {
  const result = detectBrowserCapabilities({
    isSecureContext: true,
    showDirectoryPicker() {},
    FileSystemDirectoryHandle: function FileSystemDirectoryHandle() {},
    FileSystemFileHandle: function FileSystemFileHandle() {},
  });

  assert.equal(result.canEditLocalRime, false);
  assert.match(result.reason, /文件|读写|支持/);
});

test('detects macOS as Squirrel and Windows as Weasel', () => {
  assert.equal(detectPreferredPlatform({ platform: 'MacIntel', userAgent: '' }), 'squirrel');
  assert.equal(detectPreferredPlatform({ platform: 'Win32', userAgent: '' }), 'weasel');
  assert.equal(detectPreferredPlatform({ platform: 'Linux x86_64', userAgent: '' }), 'unknown');
});

test('generates safe unique skin ids from Chinese and English display names', () => {
  assert.equal(generateSkinId('Win11 浅色', []), 'win11');
  assert.equal(generateSkinId('鼠须管 亮色', []), 'skin');
  assert.equal(generateSkinId('Win11 浅色', ['win11', 'win11_2']), 'win11_3');
});

test('converts Rime hex colors to normalized RGBA', () => {
  assert.deepEqual(rimeHexToRgba('0xFFFFFF'), { r: 255, g: 255, b: 255, a: 255 });
  assert.deepEqual(rimeHexToRgba('0x80A996F1'), { r: 241, g: 150, b: 169, a: 128 });
  assert.deepEqual(rimeHexToRgba('0xc202020'), { r: 32, g: 32, b: 32, a: 12 });
});

test('converts normalized RGBA to Rime ABGR hex', () => {
  assert.equal(rgbaToRimeHex({ r: 255, g: 255, b: 255, a: 255 }, false), '0xFFFFFF');
  assert.equal(rgbaToRimeHex({ r: 241, g: 150, b: 169, a: 128 }, true), '0x80A996F1');
});

test('formats human-readable backup folder names with operation summaries', () => {
  const date = new Date('2026-06-26T07:30:12.000Z');
  const name = formatBackupFolderName(date, '保存鼠须管-win11light', 8 * 60);

  assert.equal(name, '2026-06-26 15-30-12 保存鼠须管-win11light');
});

test('formats unique backup folder names when a same-second name already exists', () => {
  const date = new Date('2026-06-26T07:30:12.000Z');
  const first = '2026-06-26 15-30-12 保存鼠须管-win11light';
  const name = formatBackupFolderName(date, '保存鼠须管-win11light', 8 * 60, new Set([first]));

  assert.equal(name, '2026-06-26 15-30-12 保存鼠须管-win11light 2');
});

test('parses Squirrel nested preset schemes and active light/dark schemes', () => {
  const parsed = parseSquirrelConfig(`
patch:
  preset_color_schemes:
    win11light:
      name: Win11Light
      back_color: 0xfff9f9f9
      candidate_text_color: 0x000000
    easy_dark:
      name: Easy Dark
      back_color: 0x36261F
  style:
    color_scheme: win11light
    color_scheme_dark: easy_dark
    font_point: 16
`);

  assert.equal(parsed.platform, 'squirrel');
  assert.equal(parsed.activeSkinId, 'win11light');
  assert.equal(parsed.darkSkinId, 'easy_dark');
  assert.equal(parsed.skins.length, 2);
  assert.equal(parsed.skins[0].displayName, 'Win11Light');
  assert.equal(parsed.skins[0].colors.back.r, 249);
  assert.equal(parsed.skins[0].layout.fontPoint, 16);
});

test('parses Weasel slash-path preset schemes and active scheme', () => {
  const parsed = parseWeaselConfig(`
patch:
  "preset_color_schemes/win11light":
    name: "Win11Light"
    back_color: 0xfff9f9f9
    candidate_text_color: 0x000000
  "preset_color_schemes/blackpink":
    name: "Black Pink"
    back_color: 0x1e1e1e
  style:
    font_point: 15
    layout: {corner_radius: 5, margin_x: 5}
  "style/color_scheme": win11light
`);

  assert.equal(parsed.platform, 'weasel');
  assert.equal(parsed.activeSkinId, 'win11light');
  assert.equal(parsed.skins.length, 2);
  assert.equal(parsed.skins[1].id, 'blackpink');
  assert.equal(parsed.skins[1].displayName, 'Black Pink');
  assert.equal(parsed.skins[0].layout.fontPoint, 15);
  assert.equal(parsed.skins[0].layout.cornerRadius, 5);
});

test('rejects malformed or unsupported YAML before editing', () => {
  assert.throws(() => parseYaml('patch:\n  style\n    color_scheme: old\n'), /YAML|语法|不支持/);
  assert.throws(() => parseYaml('patch:\n\tstyle:\n'), /YAML|缩进|不支持/);
  assert.throws(() => parseYaml('patch:\n  - broken\n'), /YAML|列表|不支持/);
  assert.throws(() => parseYaml('patch:\n  layout: {corner_radius: 5}\n    corner_radius: 6\n'), /YAML|缩进|不支持/);
  assert.throws(() => parseSquirrelConfig('patch:\n  preset_color_schemes: broken\n'), /preset_color_schemes/);
  assert.throws(() => parseWeaselConfig('patch: broken\n'), /patch/);
});

test('throws instead of writing when existing frontend YAML is malformed', () => {
  assert.throws(() => updateSquirrelConfig('patch:\n  style\n', {
    platform: 'squirrel',
    id: 'safe',
    displayName: 'Safe',
    colors: {},
    layout: {},
  }), /YAML|语法|不支持/);
});

test('updates Squirrel skin and preserves unrelated patch keys', () => {
  const input = `
patch:
  schema_list:
    - schema: tiger
  preset_color_schemes:
    old:
      name: Old
      back_color: 0xFFFFFF
  style:
    color_scheme: old
`;
  const output = updateSquirrelConfig(input, {
    platform: 'squirrel',
    id: 'new_skin',
    displayName: 'New Skin',
    author: 'Tester',
    colors: {
      back: { r: 10, g: 20, b: 30, a: 255 },
      candidateText: { r: 255, g: 255, b: 255, a: 255 },
    },
    layout: { fontPoint: 18, candidateListLayout: 'linear' },
  }, { makeActive: true });
  const parsed = parseSquirrelConfig(output);

  assert.match(output, /- schema: tiger/);
  assert.equal(parsed.activeSkinId, 'new_skin');
  assert.equal(parsed.skins.find((skin) => skin.id === 'new_skin').displayName, 'New Skin');
  assert.equal(parsed.skins.find((skin) => skin.id === 'new_skin').layout.fontPoint, 18);
});

test('updates Squirrel skin without dropping unsupported skin or style fields', () => {
  const input = `
patch:
  preset_color_schemes:
    old:
      name: Old
      back_color: 0xFFFFFF
      inline_preedit: true
      platform_specific:
        deep_value: keep
  style:
    color_scheme: old
    candidate_format: "%c %@"
    memorize_size: true
`;
  const output = updateSquirrelConfig(input, {
    platform: 'squirrel',
    id: 'old',
    displayName: 'Old Updated',
    colors: {
      back: { r: 10, g: 20, b: 30, a: 255 },
    },
    layout: { fontPoint: 18 },
  }, { makeActive: true });
  const doc = parseYaml(output);

  assert.equal(doc.patch.preset_color_schemes.old.inline_preedit, true);
  assert.equal(doc.patch.preset_color_schemes.old.platform_specific.deep_value, 'keep');
  assert.equal(doc.patch.preset_color_schemes.old.name, 'Old Updated');
  assert.equal(doc.patch.style.candidate_format, '%c %@');
  assert.equal(doc.patch.style.memorize_size, true);
  assert.equal(doc.patch.style.font_point, 18);
});

test('updates Squirrel skin by creating missing preset section inside existing patch', () => {
  const output = updateSquirrelConfig(`
patch:
  style:
    color_scheme: old
`, {
    platform: 'squirrel',
    id: 'new_skin',
    displayName: 'New Skin',
    colors: {
      back: { r: 10, g: 20, b: 30, a: 255 },
    },
    layout: {},
  }, { makeActive: true });
  const doc = parseYaml(output);

  assert.equal((output.match(/^patch:/gm) || []).length, 1);
  assert.equal(doc.patch.style.color_scheme, 'new_skin');
  assert.equal(doc.patch.preset_color_schemes.new_skin.name, 'New Skin');
});

test('updates files with patch line comments and four-space indentation without duplicate patch', () => {
  const output = updateSquirrelConfig(`
patch: # user patch
    style:
        color_scheme: old # active
`, {
    platform: 'squirrel',
    id: 'new_skin',
    displayName: 'New Skin',
    colors: {},
    layout: {},
  }, { makeActive: true });
  const doc = parseYaml(output);

  assert.equal((output.match(/^patch:/gm) || []).length, 1);
  assert.equal(doc.patch.style.color_scheme, 'new_skin');
  assert.equal(doc.patch.preset_color_schemes.new_skin.name, 'New Skin');
});

test('updates Weasel skin and preserves unrelated patch keys', () => {
  const input = `
patch:
  schema_list:
    - schema: tiger
  "preset_color_schemes/old":
    name: Old
    back_color: 0xFFFFFF
  "style/color_scheme": old
`;
  const output = updateWeaselConfig(input, {
    platform: 'weasel',
    id: 'new_skin',
    displayName: 'New Skin',
    author: 'Tester',
    colors: {
      back: { r: 10, g: 20, b: 30, a: 255 },
      candidateText: { r: 255, g: 255, b: 255, a: 255 },
    },
    layout: { fontPoint: 18, cornerRadius: 6 },
  }, { makeActive: true });
  const parsed = parseWeaselConfig(output);

  assert.match(output, /- schema: tiger/);
  assert.equal(parsed.activeSkinId, 'new_skin');
  assert.equal(parsed.skins.find((skin) => skin.id === 'new_skin').displayName, 'New Skin');
  assert.equal(parsed.skins.find((skin) => skin.id === 'new_skin').layout.fontPoint, 18);
});

test('updates Weasel skin without dropping unsupported skin or style fields', () => {
  const input = `
patch:
  "preset_color_schemes/old":
    name: Old
    back_color: 0xFFFFFF
    translucency: true
    mutual_exclusive: keep
  style:
    font_point: 14
    label_format: "%s."
    layout:
      margin_x: 9
      min_width: 120
  "style/color_scheme": old
`;
  const output = updateWeaselConfig(input, {
    platform: 'weasel',
    id: 'old',
    displayName: 'Old Updated',
    colors: {
      back: { r: 10, g: 20, b: 30, a: 255 },
    },
    layout: { fontPoint: 18, cornerRadius: 6 },
  }, { makeActive: true });
  const doc = parseYaml(output);

  assert.equal(doc.patch['preset_color_schemes/old'].translucency, true);
  assert.equal(doc.patch['preset_color_schemes/old'].mutual_exclusive, 'keep');
  assert.equal(doc.patch['preset_color_schemes/old'].name, 'Old Updated');
  assert.equal(doc.patch.style.label_format, '%s.');
  assert.equal(doc.patch.style.layout.min_width, 120);
  assert.equal(doc.patch.style.layout.corner_radius, 6);
  assert.equal(doc.patch.style.font_point, 18);
});

test('updates nested Weasel layout when existing layout is inline object', () => {
  const output = updateWeaselConfig(`
patch:
  "preset_color_schemes/old":
    name: Old
  style:
    layout: {corner_radius: 5, min_width: 120}
  "style/color_scheme": old
`, {
    platform: 'weasel',
    id: 'old',
    displayName: 'Old',
    colors: {},
    layout: { cornerRadius: 6 },
  }, { makeActive: true });
  const doc = parseYaml(output);

  assert.equal(doc.patch.style.layout.corner_radius, 6);
  assert.equal(doc.patch.style.layout.min_width, 120);
  assert.doesNotMatch(output, /layout: \{.*\}\n\s+corner_radius:/);
});

test('deletes quoted active skin references with comments', () => {
  const squirrelOutput = deleteSquirrelSkinConfig(`
patch:
  preset_color_schemes:
    old:
      name: Old
  style:
    color_scheme: "old" # active
    color_scheme_dark: 'old' # dark
`, 'old');
  const weaselOutput = deleteWeaselSkinConfig(`
patch:
  "preset_color_schemes/old":
    name: Old
  "style/color_scheme": "old" # active
`, 'old');

  assert.doesNotMatch(squirrelOutput, /^\s+color_scheme:/m);
  assert.doesNotMatch(squirrelOutput, /^\s+color_scheme_dark:/m);
  assert.doesNotMatch(weaselOutput, /style\/color_scheme/);
});

test('maps Squirrel horizontal compatibility field to canonical layout mode', () => {
  const parsed = parseSquirrelConfig(`
patch:
  preset_color_schemes:
    old:
      name: Old
      horizontal: true
`);

  assert.equal(parsed.skins[0].layout.candidateListLayout, 'linear');
});

test('copies skins between platforms with mapped fields but no binding', () => {
  const squirrelSkin = {
    platform: 'squirrel',
    id: 'soft_blue',
    displayName: 'Soft Blue',
    author: 'Tester',
    colors: {
      back: { r: 240, g: 245, b: 255, a: 255 },
      hilitedCandidateBack: { r: 40, g: 120, b: 220, a: 255 },
    },
    layout: { fontPoint: 16, candidateListLayout: 'linear' },
  };

  const weaselSkin = copySkinToPlatform(squirrelSkin, 'weasel');
  const squirrelCopy = copySkinToPlatform(weaselSkin, 'squirrel');

  assert.equal(weaselSkin.platform, 'weasel');
  assert.equal(weaselSkin.id, 'soft_blue');
  assert.equal(weaselSkin.layout.horizontal, true);
  assert.equal(squirrelCopy.platform, 'squirrel');
  assert.equal(squirrelCopy.layout.candidateListLayout, 'linear');
  assert.notEqual(weaselSkin, squirrelSkin);
});

test('creates backup manifest with operation and file metadata', () => {
  const manifest = createBackupManifest({
    createdAt: '2026-06-26T15:30:12+08:00',
    operation: 'save',
    sourcePlatform: 'squirrel',
    targetPlatform: '',
    skinIdBefore: 'old',
    skinIdAfter: 'new_skin',
    files: ['squirrel.custom.yaml'],
    browser: 'Chrome',
  });

  assert.equal(manifest.operation, 'save');
  assert.equal(manifest.sourcePlatform, 'squirrel');
  assert.deepEqual(manifest.files, ['squirrel.custom.yaml']);
});

test('creates rollback plan only when manifest files exist', () => {
  const plan = createRollbackPlan({
    manifest: {
      operation: 'save',
      files: ['squirrel.custom.yaml'],
      createdFiles: [],
    },
    availableFiles: new Set(['squirrel.custom.yaml']),
  }, new Set(['squirrel.custom.yaml']));

  assert.deepEqual(plan.filesToRestore, ['squirrel.custom.yaml']);
  assert.deepEqual(plan.filesToDelete, []);
  assert.equal(plan.requiresCurrentBackup, true);

  assert.throws(() => createRollbackPlan({
    manifest: { operation: 'save', files: ['missing.yaml'] },
    availableFiles: new Set(),
  }, new Set(['missing.yaml'])), /备份文件缺失/);
});

test('rollback plan deletes files created by the backed-up operation', () => {
  const plan = createRollbackPlan({
    manifest: {
      operation: 'save',
      files: [],
      createdFiles: ['weasel.custom.yaml'],
    },
    availableFiles: new Set(['manifest.json']),
  }, new Set(['weasel.custom.yaml']));

  assert.deepEqual(plan.filesToRestore, []);
  assert.deepEqual(plan.filesToDelete, ['weasel.custom.yaml']);
});

test('rollback can restore missing current files and ignores already deleted created files', () => {
  const plan = createRollbackPlan({
    manifest: {
      operation: 'save',
      files: ['squirrel.custom.yaml'],
      createdFiles: ['weasel.custom.yaml'],
    },
    availableFiles: new Set(['squirrel.custom.yaml']),
  }, new Set());

  assert.deepEqual(plan.filesToRestore, ['squirrel.custom.yaml']);
  assert.deepEqual(plan.filesToDelete, []);
});

test('deletes skins without removing unrelated config', () => {
  const squirrelOutput = deleteSquirrelSkinConfig(`
patch:
  schema_list:
    - schema: tiger
  preset_color_schemes:
    old:
      name: Old
    keep:
      name: Keep
  style:
    color_scheme: old
`, 'old');
  const weaselOutput = deleteWeaselSkinConfig(`
patch:
  schema_list:
    - schema: tiger
  "preset_color_schemes/old":
    name: Old
  "preset_color_schemes/keep":
    name: Keep
  "style/color_scheme": old
`, 'old');

  assert.doesNotMatch(squirrelOutput, /old:\n\s+name: Old/);
  assert.match(squirrelOutput, /keep:/);
  assert.match(squirrelOutput, /- schema: tiger/);
  assert.doesNotMatch(weaselOutput, /preset_color_schemes\/old/);
  assert.match(weaselOutput, /preset_color_schemes\/keep/);
  assert.match(weaselOutput, /- schema: tiger/);
});

test('parses the repository Squirrel and Weasel custom files', () => {
  const root = resolve(import.meta.dirname, '../..');
  const squirrel = parseSquirrelConfig(readFileSync(resolve(root, 'squirrel.custom.yaml'), 'utf8'));
  const weasel = parseWeaselConfig(readFileSync(resolve(root, 'weasel.custom.yaml'), 'utf8'));

  assert.ok(squirrel.skins.length >= 10);
  assert.ok(weasel.skins.length >= 10);
  assert.equal(squirrel.activeSkinId, 'win11light');
  assert.equal(weasel.activeSkinId, 'win11light');
});
