const {
  copySkinToPlatform,
  createBackupManifest,
  createRollbackPlan,
  detectBrowserCapabilities,
  detectPreferredPlatform,
  deleteSquirrelSkinConfig,
  deleteWeaselSkinConfig,
  formatBackupFolderName,
  generateSkinId,
  parseSquirrelConfig,
  parseWeaselConfig,
  rgbaToRimeHex,
  updateSquirrelConfig,
  updateWeaselConfig,
} = window.RimeSkinCore;

const BACKUP_ROOT = 'Rime皮肤编辑器备份';
const PLATFORM_FILES = {
  squirrel: 'squirrel.custom.yaml',
  weasel: 'weasel.custom.yaml',
};
const PLATFORM_LABELS = {
  squirrel: '鼠须管',
  weasel: '小狼毫',
};
const COMMON_FONTS = [
  'LXGW WenKai GB Screen',
  'PingFang SC',
  'Microsoft YaHei',
  'Segoe UI',
  'Consolas',
  'SimSun',
  'Apple Color Emoji',
  'Noto Color Emoji',
];
const COLOR_CONTROLS = [
  ['back', '背景'],
  ['border', '边框'],
  ['text', '编码文字'],
  ['candidateText', '候选文字'],
  ['commentText', '注释文字'],
  ['label', '编号'],
  ['hilitedCandidateBack', '高亮背景'],
  ['hilitedCandidateText', '高亮文字'],
  ['hilitedCommentText', '高亮注释'],
  ['shadow', '阴影'],
];
const DEFAULT_COLORS = {
  back: { r: 255, g: 255, b: 255, a: 255 },
  border: { r: 230, g: 230, b: 230, a: 255 },
  text: { r: 51, g: 51, b: 51, a: 255 },
  candidateText: { r: 34, g: 34, b: 34, a: 255 },
  commentText: { r: 102, g: 102, b: 102, a: 255 },
  label: { r: 120, g: 120, b: 120, a: 255 },
  hilitedCandidateBack: { r: 240, g: 240, b: 240, a: 255 },
  hilitedCandidateText: { r: 0, g: 0, b: 0, a: 255 },
  hilitedCommentText: { r: 80, g: 80, b: 80, a: 255 },
  shadow: { r: 0, g: 0, b: 0, a: 32 },
};

const state = {
  capability: null,
  preferredPlatform: 'unknown',
  dirHandle: null,
  folderName: '',
  configs: {
    squirrel: null,
    weasel: null,
  },
  fileExists: {
    squirrel: false,
    weasel: false,
    default: false,
  },
  rawFiles: {
    squirrel: '',
    weasel: '',
    default: '',
  },
  hasAnySchemaFile: false,
  selectedPlatform: 'squirrel',
  selectedSkinId: '',
  originalSkinId: '',
  draftSkin: null,
  backups: [],
};

const dom = {};

document.addEventListener('DOMContentLoaded', () => {
  bindDom();
  initialize();
});

function bindDom() {
  for (const id of [
    'supportStatus',
    'chooseFolderButton',
    'folderName',
    'blockedPanel',
    'blockedReason',
    'workspace',
    'squirrelTab',
    'weaselTab',
    'platformHint',
    'skinList',
    'newSkinButton',
    'duplicateSkinButton',
    'deleteSkinButton',
    'previewPlatform',
    'candidatePreview',
    'colorControls',
    'layoutMode',
    'fontFace',
    'fontPoint',
    'fontPointNumber',
    'fontPointValue',
    'cornerRadius',
    'cornerRadiusNumber',
    'cornerRadiusValue',
    'candidateSpacing',
    'candidateSpacingNumber',
    'candidateSpacingValue',
    'shadowSize',
    'shadowSizeNumber',
    'shadowSizeValue',
    'displayName',
    'author',
    'skinId',
    'setActiveButton',
    'saveButton',
    'copyButton',
    'reloadBackupsButton',
    'backupList',
    'messageLog',
  ]) {
    dom[id] = document.getElementById(id);
  }
}

function initialize() {
  state.capability = detectBrowserCapabilities(window);
  state.preferredPlatform = detectPreferredPlatform(navigator);
  state.selectedPlatform = state.preferredPlatform === 'weasel' ? 'weasel' : 'squirrel';
  state.configs.squirrel = emptyConfig('squirrel');
  state.configs.weasel = emptyConfig('weasel');
  populateFontOptions();
  renderCapability();
  bindEvents();
  renderAll();
}

function bindEvents() {
  dom.chooseFolderButton.addEventListener('click', chooseFolder);
  dom.squirrelTab.addEventListener('click', () => selectPlatform('squirrel'));
  dom.weaselTab.addEventListener('click', () => selectPlatform('weasel'));
  dom.newSkinButton.addEventListener('click', createNewSkin);
  dom.duplicateSkinButton.addEventListener('click', duplicateCurrentSkin);
  dom.deleteSkinButton.addEventListener('click', deleteCurrentSkin);
  dom.setActiveButton.addEventListener('click', setActiveSkin);
  dom.saveButton.addEventListener('click', saveCurrentSkin);
  dom.copyButton.addEventListener('click', copyCurrentSkin);
  dom.reloadBackupsButton.addEventListener('click', refreshBackups);

  dom.displayName.addEventListener('input', () => updateDraftText('displayName', dom.displayName.value));
  dom.author.addEventListener('input', () => updateDraftText('author', dom.author.value));
  dom.skinId.addEventListener('change', () => updateDraftId(dom.skinId.value));
  dom.layoutMode.addEventListener('change', updateLayoutMode);
  dom.fontFace.addEventListener('change', updateFontFace);
  bindRange(dom.fontPoint, dom.fontPointNumber, dom.fontPointValue, 'fontPoint');
  bindRange(dom.cornerRadius, dom.cornerRadiusNumber, dom.cornerRadiusValue, 'cornerRadius');
  bindRange(dom.candidateSpacing, dom.candidateSpacingNumber, dom.candidateSpacingValue, 'candidateSpacing');
  bindRange(dom.shadowSize, dom.shadowSizeNumber, dom.shadowSizeValue, 'shadowSize');
}

function bindRange(rangeInput, numberInput, output, field) {
  const sync = (source) => {
    const value = clampNumber(source.value, Number(rangeInput.min), Number(rangeInput.max));
    rangeInput.value = String(value);
    numberInput.value = String(value);
    output.value = String(value);
    updateDraftLayout(field, value);
  };
  rangeInput.addEventListener('input', () => sync(rangeInput));
  numberInput.addEventListener('input', () => sync(numberInput));
}

function renderCapability() {
  if (state.capability.canEditLocalRime) {
    dom.supportStatus.textContent = '浏览器支持本地配置文件夹读写。';
    dom.blockedPanel.classList.add('hidden');
    return;
  }

  dom.supportStatus.textContent = '当前浏览器不支持直接编辑。';
  dom.blockedReason.textContent = state.capability.reason;
  dom.blockedPanel.classList.remove('hidden');
  dom.chooseFolderButton.disabled = true;
}

async function chooseFolder() {
  try {
    const dirHandle = await window.showDirectoryPicker({ mode: 'readwrite' });
    const loaded = await loadConfigsFromHandle(dirHandle);
    if (!looksLikeRimeFolder(loaded)) {
      dom.workspace.classList.add('hidden');
      logMessage('选择的文件夹不像 Rime 配置文件夹：未找到前端配置、方案配置或 default.custom.yaml。');
      return;
    }
    applyLoadedConfigs(dirHandle, loaded);
    dom.folderName.textContent = state.folderName;
    chooseInitialPlatform();
    await refreshBackups();
    dom.workspace.classList.remove('hidden');
    logMessage('已读取配置文件夹。');
  } catch (error) {
    if (error?.name === 'AbortError') return;
    dom.workspace.classList.add('hidden');
    logMessage(`选择文件夹失败：${error.message}`);
  }
}

async function loadConfigs() {
  const loaded = await loadConfigsFromHandle(state.dirHandle);
  applyLoadedConfigs(state.dirHandle, loaded);
}

async function loadConfigsFromHandle(dirHandle) {
  const loaded = {
    folderName: dirHandle.name || '已选择的 Rime 配置文件夹',
    configs: {},
    rawFiles: {},
    fileExists: {},
    hasAnySchemaFile: false,
  };
  for (const platform of Object.keys(PLATFORM_FILES)) {
    const filename = PLATFORM_FILES[platform];
    const entry = await readOptionalFileEntry(filename, dirHandle);
    const text = entry.text;
    loaded.fileExists[platform] = entry.exists;
    loaded.rawFiles[platform] = text;
    loaded.configs[platform] = text ? parseConfig(platform, text) : emptyConfig(platform);
  }
  const defaultEntry = await readOptionalFileEntry('default.custom.yaml', dirHandle);
  loaded.fileExists.default = defaultEntry.exists;
  loaded.rawFiles.default = defaultEntry.text;
  loaded.hasAnySchemaFile = await directoryHasSchemaFile(dirHandle);
  return loaded;
}

function applyLoadedConfigs(dirHandle, loaded) {
  state.dirHandle = dirHandle;
  state.folderName = loaded.folderName;
  state.configs.squirrel = loaded.configs.squirrel;
  state.configs.weasel = loaded.configs.weasel;
  state.rawFiles.squirrel = loaded.rawFiles.squirrel;
  state.rawFiles.weasel = loaded.rawFiles.weasel;
  state.rawFiles.default = loaded.rawFiles.default;
  state.fileExists.squirrel = loaded.fileExists.squirrel;
  state.fileExists.weasel = loaded.fileExists.weasel;
  state.fileExists.default = loaded.fileExists.default;
  state.hasAnySchemaFile = loaded.hasAnySchemaFile;
}

function chooseInitialPlatform() {
  const hasSquirrel = state.fileExists.squirrel;
  const hasWeasel = state.fileExists.weasel;
  if (hasSquirrel && !hasWeasel) state.selectedPlatform = 'squirrel';
  else if (hasWeasel && !hasSquirrel) state.selectedPlatform = 'weasel';
  else state.selectedPlatform = state.preferredPlatform === 'weasel' ? 'weasel' : 'squirrel';

  const active = state.configs[state.selectedPlatform].activeSkinId;
  const first = state.configs[state.selectedPlatform].skins[0]?.id || '';
  selectSkin(active || first);
}

async function readOptionalFile(filename, dirHandle = state.dirHandle) {
  return (await readOptionalFileEntry(filename, dirHandle)).text;
}

async function readOptionalFileEntry(filename, dirHandle = state.dirHandle) {
  try {
    const handle = await dirHandle.getFileHandle(filename);
    const file = await handle.getFile();
    return { exists: true, text: await file.text() };
  } catch (error) {
    if (error?.name === 'NotFoundError') return { exists: false, text: '' };
    throw error;
  }
}

async function directoryHasSchemaFile(dirHandle = state.dirHandle) {
  try {
    for await (const [name, handle] of dirHandle.entries()) {
      if (handle.kind === 'file' && name.endsWith('.schema.yaml')) return true;
    }
  } catch (error) {
    logMessage(`扫描方案文件失败：${error.message}`);
  }
  return false;
}

function parseConfig(platform, text) {
  return platform === 'squirrel' ? parseSquirrelConfig(text) : parseWeaselConfig(text);
}

async function readAndValidateFrontendFile(platform) {
  const filename = PLATFORM_FILES[platform];
  const entry = await readOptionalFileEntry(filename);
  if (!entry.exists) return { exists: false, text: '', config: emptyConfig(platform) };
  const config = parseConfig(platform, entry.text);
  return { exists: true, text: entry.text, config };
}

function emptyConfig(platform) {
  return {
    platform,
    document: { patch: platform === 'squirrel' ? { preset_color_schemes: {}, style: {} } : {} },
    skins: [],
    activeSkinId: '',
    darkSkinId: '',
  };
}

function looksLikeRimeFolder(snapshot = state) {
  return Boolean(
    snapshot.fileExists.squirrel ||
      snapshot.fileExists.weasel ||
      snapshot.fileExists.default ||
      snapshot.hasAnySchemaFile,
  );
}

function selectPlatform(platform) {
  state.selectedPlatform = platform;
  const active = state.configs[platform].activeSkinId;
  const first = state.configs[platform].skins[0]?.id || '';
  selectSkin(active || first);
}

function selectSkin(id) {
  const config = state.configs[state.selectedPlatform];
  const skin = config.skins.find((item) => item.id === id) || config.skins[0] || null;
  state.selectedSkinId = skin?.id || '';
  state.originalSkinId = skin?.id || '';
  state.draftSkin = skin ? cloneSkin(skin) : null;
  renderAll();
}

function createNewSkin() {
  const config = state.configs[state.selectedPlatform];
  const id = generateSkinId('新皮肤', config.skins.map((skin) => skin.id));
  state.draftSkin = {
    platform: state.selectedPlatform,
    id,
    displayName: '新皮肤',
    author: '',
    colors: cloneJson(DEFAULT_COLORS),
    layout: defaultLayoutForPlatform(state.selectedPlatform),
    unsupportedFields: {},
  };
  state.selectedSkinId = id;
  state.originalSkinId = '';
  renderAll();
}

function duplicateCurrentSkin() {
  if (!state.draftSkin) return;
  const config = state.configs[state.selectedPlatform];
  const id = generateSkinId(`${state.draftSkin.id}_copy`, config.skins.map((skin) => skin.id));
  state.draftSkin = {
    ...cloneSkin(state.draftSkin),
    id,
    displayName: `${state.draftSkin.displayName || state.draftSkin.id} 副本`,
  };
  state.selectedSkinId = id;
  state.originalSkinId = '';
  renderAll();
}

async function deleteCurrentSkin() {
  if (!state.draftSkin || !state.dirHandle) return;
  const config = state.configs[state.selectedPlatform];
  if (state.originalSkinId && state.draftSkin.id !== state.originalSkinId) {
    logMessage('当前皮肤 ID 已改动。请先保存为新皮肤，或重新选择原皮肤后再删除。');
    return;
  }
  const deleteId = state.originalSkinId || state.draftSkin.id;
  const persisted = config.skins.some((skin) => skin.id === deleteId);
  if (!persisted) {
    state.draftSkin = null;
    state.selectedSkinId = '';
    state.originalSkinId = '';
    selectSkin(config.activeSkinId || config.skins[0]?.id || '');
    logMessage('已丢弃未保存的皮肤草稿。');
    return;
  }
  const confirmed = window.confirm(`确认删除皮肤「${state.draftSkin.displayName}」？保存前会先备份当前配置。`);
  if (!confirmed) return;

  try {
    const platform = state.selectedPlatform;
    const filename = PLATFORM_FILES[platform];
    const current = await readAndValidateFrontendFile(platform);
    if (!current.exists) throw new Error(`${filename} 不存在，无法删除已保存皮肤。`);
    const operation = `删除${PLATFORM_LABELS[platform]}-${deleteId}`;
    await backupFiles(operation, [filename], {
      operation: 'delete',
      sourcePlatform: platform,
      targetPlatform: '',
      skinIdBefore: deleteId,
      skinIdAfter: '',
    }, { [filename]: current });
    const output = platform === 'squirrel'
      ? deleteSquirrelSkinConfig(current.text, deleteId)
      : deleteWeaselSkinConfig(current.text, deleteId);
    await writeFile(filename, output);
    const written = await readOptionalFileEntry(filename);
    if (!written.exists) throw new Error(`删除后无法重新读取 ${filename}`);
    state.rawFiles[platform] = written.text;
    state.configs[platform] = parseConfig(platform, written.text);
    const next = state.configs[platform].activeSkinId || state.configs[platform].skins[0]?.id || '';
    await refreshBackups();
    selectSkin(next);
    logMessage('已删除并备份。请重新部署 Rime。');
  } catch (error) {
    logMessage(`删除失败：${error.message}`);
  }
}

function renderAll() {
  renderPlatform();
  renderSkinList();
  renderEditor();
  renderPreview();
  renderBackupList();
}

function renderPlatform() {
  dom.squirrelTab.classList.toggle('active', state.selectedPlatform === 'squirrel');
  dom.weaselTab.classList.toggle('active', state.selectedPlatform === 'weasel');
  const detected = state.preferredPlatform === 'squirrel' ? '检测到 macOS，默认鼠须管。'
    : state.preferredPlatform === 'weasel' ? '检测到 Windows，默认小狼毫。'
      : '未识别当前 Rime 前端，可手动选择平台。';
  dom.platformHint.textContent = detected;
}

function renderSkinList() {
  const config = state.configs[state.selectedPlatform];
  dom.skinList.replaceChildren();
  if (!config.skins.length && !state.draftSkin) {
    const empty = document.createElement('p');
    empty.className = 'hint';
    empty.textContent = '还没有皮肤，点击“新建”。';
    dom.skinList.append(empty);
    return;
  }

  for (const skin of config.skins) {
    const button = document.createElement('button');
    button.className = `skin-item ${skin.id === state.selectedSkinId ? 'active' : ''}`;
    button.innerHTML = `<span class="skin-title">${escapeHtml(skin.displayName)}</span><span class="skin-meta">${escapeHtml(skin.id)}${skin.id === config.activeSkinId ? ' · 当前' : ''}${skin.id === config.darkSkinId ? ' · 暗色' : ''}</span>`;
    button.addEventListener('click', () => selectSkin(skin.id));
    dom.skinList.append(button);
  }

  if (state.draftSkin && !config.skins.some((skin) => skin.id === state.draftSkin.id)) {
    const button = document.createElement('button');
    button.className = 'skin-item active';
    button.innerHTML = `<span class="skin-title">${escapeHtml(state.draftSkin.displayName)}</span><span class="skin-meta">${escapeHtml(state.draftSkin.id)} · 未保存</span>`;
    dom.skinList.prepend(button);
  }
}

function renderEditor() {
  const skin = state.draftSkin;
  const disabled = !skin;
  const canDelete = !disabled;
  for (const element of [
    dom.displayName,
    dom.author,
    dom.skinId,
    dom.layoutMode,
    dom.fontFace,
    dom.fontPoint,
    dom.fontPointNumber,
    dom.cornerRadius,
    dom.cornerRadiusNumber,
    dom.candidateSpacing,
    dom.candidateSpacingNumber,
    dom.shadowSize,
    dom.shadowSizeNumber,
    dom.setActiveButton,
    dom.saveButton,
    dom.copyButton,
    dom.duplicateSkinButton,
  ]) {
    element.disabled = disabled;
  }
  dom.deleteSkinButton.disabled = !canDelete;
  const target = state.selectedPlatform === 'squirrel' ? 'weasel' : 'squirrel';
  dom.copyButton.textContent = `复制到${PLATFORM_LABELS[target]}`;
  dom.colorControls.replaceChildren();
  if (!skin) return;

  dom.displayName.value = skin.displayName || '';
  dom.author.value = skin.author || '';
  dom.skinId.value = skin.id || '';
  dom.previewPlatform.textContent = PLATFORM_LABELS[state.selectedPlatform];

  const layout = normalizedLayout(skin);
  dom.layoutMode.value = layout.mode;
  syncSelect(dom.fontFace, layout.fontFace);
  setRange(dom.fontPoint, dom.fontPointNumber, dom.fontPointValue, layout.fontPoint);
  setRange(dom.cornerRadius, dom.cornerRadiusNumber, dom.cornerRadiusValue, layout.cornerRadius);
  setRange(dom.candidateSpacing, dom.candidateSpacingNumber, dom.candidateSpacingValue, layout.candidateSpacing);
  setRange(dom.shadowSize, dom.shadowSizeNumber, dom.shadowSizeValue, layout.shadowSize);

  for (const [role, label] of COLOR_CONTROLS) {
    const wrapper = document.createElement('label');
    const color = skin.colors?.[role] || DEFAULT_COLORS[role] || DEFAULT_COLORS.back;
    wrapper.innerHTML = `<span>${label}</span>`;
    const input = document.createElement('input');
    input.type = 'color';
    input.value = rgbaToCssHex(color);
    input.addEventListener('input', () => updateDraftColor(role, cssHexToRgba(input.value)));
    wrapper.append(input);
    dom.colorControls.append(wrapper);
  }
}

function renderPreview() {
  const skin = state.draftSkin;
  if (!skin) return;
  const colors = { ...DEFAULT_COLORS, ...(skin.colors || {}) };
  const layout = normalizedLayout(skin);
  const preview = dom.candidatePreview;
  const row = preview.querySelector('.candidate-row');
  const active = preview.querySelector('.candidate.active');
  const candidates = preview.querySelectorAll('.candidate:not(.active)');
  const comment = preview.querySelector('.comment');
  const preedit = preview.querySelector('.preedit');

  preview.style.backgroundColor = rgbaToCss(colors.back);
  preview.style.borderColor = rgbaToCss(colors.border || colors.back);
  preview.style.borderRadius = `${layout.cornerRadius}px`;
  preview.style.fontFamily = layout.fontFace;
  preview.style.fontSize = `${layout.fontPoint}px`;
  preview.style.boxShadow = layout.shadowSize
    ? `0 ${Math.max(4, layout.shadowSize)}px ${layout.shadowSize * 2}px ${rgbaToCss(colors.shadow)}`
    : 'none';
  preedit.style.color = rgbaToCss(colors.text);
  row.classList.toggle('stacked', layout.mode === 'stacked');
  row.style.gap = `${layout.candidateSpacing}px`;
  active.style.backgroundColor = rgbaToCss(colors.hilitedCandidateBack);
  active.style.color = rgbaToCss(colors.hilitedCandidateText);
  for (const item of candidates) item.style.color = rgbaToCss(colors.candidateText);
  comment.style.color = rgbaToCss(colors.commentText);
}

function renderBackupList() {
  dom.backupList.replaceChildren();
  if (!state.backups.length) {
    const empty = document.createElement('p');
    empty.className = 'hint';
    empty.textContent = '暂无备份。';
    dom.backupList.append(empty);
    return;
  }
  for (const backup of state.backups) {
    const button = document.createElement('button');
    button.className = 'backup-item';
    const summary = manifestSummary(backup.manifest);
    const backupFiles = [
      ...(backup.manifest?.files || []),
      ...(backup.manifest?.createdFiles || []).map((file) => `${file}（新建）`),
    ];
    const files = backupFiles.join(', ') || '未知文件';
    button.innerHTML = `<span class="skin-title">${escapeHtml(backup.name)}</span><span class="backup-meta">${escapeHtml(summary)} · ${escapeHtml(files)}</span>`;
    button.addEventListener('click', () => rollbackBackup(backup));
    dom.backupList.append(button);
  }
}

function updateDraftText(field, value) {
  if (!state.draftSkin) return;
  state.draftSkin[field] = value;
  if (field === 'displayName') renderSkinList();
  renderPreview();
}

function updateDraftId(value) {
  if (!state.draftSkin) return;
  const safe = generateSkinId(value || state.draftSkin.displayName, []);
  state.draftSkin.id = safe;
  dom.skinId.value = safe;
  state.selectedSkinId = safe;
  renderSkinList();
}

function updateLayoutMode() {
  if (!state.draftSkin) return;
  const mode = dom.layoutMode.value;
  if (state.selectedPlatform === 'squirrel') {
    state.draftSkin.layout.candidateListLayout = mode;
  } else {
    state.draftSkin.layout.horizontal = mode === 'linear';
  }
  renderPreview();
}

function updateDraftLayout(field, value) {
  if (!state.draftSkin) return;
  state.draftSkin.layout ||= {};
  state.draftSkin.layout[field] = value;
  renderPreview();
}

function updateDraftColor(role, color) {
  if (!state.draftSkin) return;
  state.draftSkin.colors ||= {};
  state.draftSkin.colors[role] = color;
  renderPreview();
}

function resolveSkinIdConflict(platform, id, actionLabel) {
  const result = window.prompt(
    `${PLATFORM_LABELS[platform]}中已存在 ID「${id}」。输入 1 覆盖，输入 2 另存为新 ID，留空取消。`,
    '2',
  );
  if (result === '1') return 'overwrite';
  if (result === '2') return 'new';
  logMessage(`${actionLabel}已取消，未覆盖同名皮肤。`);
  return 'cancel';
}

function manifestSummary(manifest) {
  if (!manifest) return '缺少备份清单';
  const operation = {
    save: '保存',
    copy: '复制',
    delete: '删除',
    'rollback-before': '回退前备份',
  }[manifest.operation] || manifest.operation || '操作';
  const source = manifest.sourcePlatform ? PLATFORM_LABELS[manifest.sourcePlatform] || manifest.sourcePlatform : '';
  const target = manifest.targetPlatform ? `到${PLATFORM_LABELS[manifest.targetPlatform] || manifest.targetPlatform}` : '';
  const skin = manifest.skinIdAfter || manifest.skinIdBefore || '';
  return [operation, `${source}${target}`, skin].filter(Boolean).join(' ');
}

function setActiveSkin() {
  if (!state.draftSkin) return;
  state.configs[state.selectedPlatform].activeSkinId = state.draftSkin.id;
  logMessage(`已设为当前皮肤。保存后请重新部署 Rime。`);
  renderSkinList();
}

async function saveCurrentSkin() {
  if (!state.draftSkin || !state.dirHandle) return;
  try {
    const platform = state.selectedPlatform;
    const filename = PLATFORM_FILES[platform];
    const current = await readAndValidateFrontendFile(platform);
    const existingText = current.exists ? current.text : minimalConfigText(platform);
    const config = current.exists ? current.config : state.configs[platform];
    let overwriteConfirmed = false;
    const isRename = state.originalSkinId && state.originalSkinId !== state.draftSkin.id;
    if (isRename) {
      const saveAsNew = window.confirm('已保存皮肤的 ID 不能直接改名。是否另存为一个新皮肤？原皮肤会保留。');
      if (!saveAsNew) return;
      if (config.skins.some((skin) => skin.id === state.draftSkin.id)) {
        const resolution = resolveSkinIdConflict(platform, state.draftSkin.id, '另存');
        if (resolution === 'cancel') return;
        if (resolution === 'new') state.draftSkin.id = generateSkinId(state.draftSkin.id, config.skins.map((skin) => skin.id));
        if (resolution === 'overwrite') overwriteConfirmed = true;
      }
      state.originalSkinId = '';
    }
    const existingSkin = config.skins.find((skin) => skin.id === state.draftSkin.id);
    if (!overwriteConfirmed && existingSkin && existingSkin.id !== state.originalSkinId) {
      const resolution = resolveSkinIdConflict(platform, state.draftSkin.id, '保存');
      if (resolution === 'cancel') return;
      if (resolution === 'new') state.draftSkin.id = generateSkinId(state.draftSkin.id, config.skins.map((skin) => skin.id));
    }
    const makeActive = Boolean(
      (!state.originalSkinId && !config.activeSkinId) ||
        config.activeSkinId === state.draftSkin.id ||
        (state.originalSkinId && config.activeSkinId === state.originalSkinId),
    );
    const operation = `保存${PLATFORM_LABELS[platform]}-${state.draftSkin.id}`;
    const fileExists = current.exists;
    if (!fileExists) {
      const createFile = window.confirm(`未找到 ${filename}。是否创建这个前端配置文件并保存皮肤？`);
      if (!createFile) return;
    }

    await backupFiles(operation, [filename], {
      operation: 'save',
      sourcePlatform: platform,
      targetPlatform: '',
      skinIdBefore: state.originalSkinId || config.activeSkinId,
      skinIdAfter: state.draftSkin.id,
      createdFiles: fileExists ? [] : [filename],
    }, { [filename]: current });

    const output = platform === 'squirrel'
      ? updateSquirrelConfig(existingText, state.draftSkin, { makeActive })
      : updateWeaselConfig(existingText, state.draftSkin, { makeActive });
    await writeFile(filename, output);
    const written = await readOptionalFileEntry(filename);
    if (!written.exists) throw new Error(`保存后无法重新读取 ${filename}`);
    state.fileExists[platform] = true;
    state.rawFiles[platform] = written.text;
    state.configs[platform] = parseConfig(platform, written.text);
    state.selectedSkinId = state.draftSkin.id;
    await refreshBackups();
    selectSkin(state.selectedSkinId);
    logMessage('已保存并备份。请重新部署 Rime。');
  } catch (error) {
    logMessage(`保存失败：${error.message}`);
  }
}

async function copyCurrentSkin() {
  if (!state.draftSkin || !state.dirHandle) return;
  const target = state.selectedPlatform === 'squirrel' ? 'weasel' : 'squirrel';
  try {
    const targetFile = PLATFORM_FILES[target];
    const current = await readAndValidateFrontendFile(target);
    const targetText = current.exists ? current.text : minimalConfigText(target);
    const targetConfig = current.exists ? current.config : state.configs[target];
    const copied = copySkinToPlatform(state.draftSkin, target);
    const confirmed = window.confirm(`将当前皮肤复制到${PLATFORM_LABELS[target]}。颜色和布局会自动映射，少数平台专属设置可能需要复制后检查。继续？`);
    if (!confirmed) return;
    const targetExists = targetConfig.skins.some((skin) => skin.id === copied.id);
    if (targetExists) {
      const resolution = resolveSkinIdConflict(target, copied.id, '复制');
      if (resolution === 'cancel') return;
      if (resolution === 'new') copied.id = generateSkinId(copied.id, targetConfig.skins.map((skin) => skin.id));
    }
    const operation = `复制${PLATFORM_LABELS[state.selectedPlatform]}到${PLATFORM_LABELS[target]}-${copied.id}`;
    const fileExists = current.exists;
    if (!fileExists) {
      const createFile = window.confirm(`未找到 ${targetFile}。是否创建这个前端配置文件并写入复制的皮肤？`);
      if (!createFile) return;
    }
    await backupFiles(operation, [targetFile], {
      operation: 'copy',
      sourcePlatform: state.selectedPlatform,
      targetPlatform: target,
      skinIdBefore: targetConfig.activeSkinId,
      skinIdAfter: copied.id,
      createdFiles: fileExists ? [] : [targetFile],
    }, { [targetFile]: current });
    const output = target === 'squirrel'
      ? updateSquirrelConfig(targetText, copied, { makeActive: false })
      : updateWeaselConfig(targetText, copied, { makeActive: false });
    await writeFile(targetFile, output);
    const written = await readOptionalFileEntry(targetFile);
    if (!written.exists) throw new Error(`复制后无法重新读取 ${targetFile}`);
    state.fileExists[target] = true;
    state.rawFiles[target] = written.text;
    state.configs[target] = parseConfig(target, written.text);
    await refreshBackups();
    logMessage(`已复制到${PLATFORM_LABELS[target]}，请重新部署 Rime。`);
    renderAll();
  } catch (error) {
    logMessage(`复制失败：${error.message}`);
  }
}

async function backupFiles(operationSummary, filenames, manifestInput, snapshots = {}) {
  const root = await state.dirHandle.getDirectoryHandle(BACKUP_ROOT, { create: true });
  const existingNames = await listDirectoryNames(root);
  const folderName = formatBackupFolderName(new Date(), operationSummary, -new Date().getTimezoneOffset(), existingNames);
  const backupDir = await root.getDirectoryHandle(folderName, { create: true });
  const backedUp = [];

  for (const filename of filenames) {
    const entry = snapshots[filename] || await readOptionalFileEntry(filename);
    if (!entry.exists) continue;
    await writeFileToDirectory(backupDir, filename, entry.text);
    backedUp.push(filename);
  }

  const manifest = createBackupManifest({
    createdAt: new Date().toISOString(),
    ...manifestInput,
    files: backedUp,
    createdFiles: manifestInput.createdFiles || [],
    browser: navigator.userAgent,
    rimeFolder: state.folderName,
  });
  await writeFileToDirectory(backupDir, 'manifest.json', JSON.stringify(manifest, null, 2));
  return folderName;
}

async function listDirectoryNames(directoryHandle) {
  const names = new Set();
  for await (const [name, handle] of directoryHandle.entries()) {
    if (handle.kind === 'directory') names.add(name);
  }
  return names;
}

async function refreshBackups() {
  state.backups = [];
  if (!state.dirHandle) {
    renderBackupList();
    return;
  }
  try {
    const root = await state.dirHandle.getDirectoryHandle(BACKUP_ROOT);
    for await (const [name, handle] of root.entries()) {
      if (handle.kind !== 'directory') continue;
      const manifestText = await readFileFromDirectory(handle, 'manifest.json').catch(() => '');
      const manifest = manifestText ? JSON.parse(manifestText) : null;
      const availableFiles = new Set();
      for await (const [fileName, fileHandle] of handle.entries()) {
        if (fileHandle.kind === 'file') availableFiles.add(fileName);
      }
      state.backups.push({ name, handle, manifest, availableFiles });
    }
    state.backups.sort((a, b) => b.name.localeCompare(a.name));
  } catch (error) {
    if (error?.name !== 'NotFoundError') logMessage(`读取备份失败：${error.message}`);
  }
  renderBackupList();
}

async function rollbackBackup(backup) {
  if (!backup?.manifest) {
    logMessage('这个备份没有 manifest.json，暂不自动回退。');
    return;
  }
  const currentFiles = currentFrontendFiles();
  let plan;
  try {
    plan = createRollbackPlan(backup, currentFiles);
  } catch (error) {
    logMessage(`无法回退：${error.message}`);
    return;
  }
  const restoreText = plan.filesToRestore.length ? `将恢复：${plan.filesToRestore.join(', ')}` : '';
  const deleteText = plan.filesToDelete.length ? `将删除：${plan.filesToDelete.join(', ')}` : '';
  const confirmed = window.confirm(`确认回退这个备份？\n${backup.name}\n${manifestSummary(backup.manifest)}\n${[restoreText, deleteText].filter(Boolean).join('\n')}`);
  if (!confirmed) return;

  try {
    const filesToBackup = [...new Set([...plan.filesToRestore, ...plan.filesToDelete])];
    await backupFiles(`回退前备份-${backup.name}`, filesToBackup, {
      operation: 'rollback-before',
      sourcePlatform: backup.manifest.sourcePlatform,
      targetPlatform: backup.manifest.targetPlatform,
      skinIdBefore: backup.manifest.skinIdAfter,
      skinIdAfter: backup.manifest.skinIdBefore,
    });
    for (const filename of plan.filesToRestore) {
      const text = await readFileFromDirectory(backup.handle, filename);
      await writeFile(filename, text);
    }
    for (const filename of plan.filesToDelete) {
      await state.dirHandle.removeEntry(filename).catch((error) => {
        if (error?.name !== 'NotFoundError') throw error;
      });
    }
    await loadConfigs();
    chooseInitialPlatform();
    await refreshBackups();
    logMessage('已回退到所选备份。请重新部署 Rime。');
  } catch (error) {
    logMessage(`回退失败：${error.message}`);
  }
}

async function writeFile(filename, text) {
  const handle = await state.dirHandle.getFileHandle(filename, { create: true });
  const writable = await handle.createWritable();
  try {
    await writable.write(text);
    await writable.close();
  } catch (error) {
    await writable.abort?.();
    throw error;
  }
}

async function writeFileToDirectory(directoryHandle, filename, text) {
  const handle = await directoryHandle.getFileHandle(filename, { create: true });
  const writable = await handle.createWritable();
  try {
    await writable.write(text);
    await writable.close();
  } catch (error) {
    await writable.abort?.();
    throw error;
  }
}

async function readFileFromDirectory(directoryHandle, filename) {
  const handle = await directoryHandle.getFileHandle(filename);
  const file = await handle.getFile();
  return await file.text();
}

function minimalConfigText(platform) {
  if (platform === 'squirrel') return 'patch:\n  preset_color_schemes:\n  style:\n';
  return 'patch:\n';
}

function populateFontOptions() {
  dom.fontFace.replaceChildren();
  for (const font of COMMON_FONTS) {
    const option = document.createElement('option');
    option.value = font;
    option.textContent = font;
    dom.fontFace.append(option);
  }
  const custom = document.createElement('option');
  custom.value = '__custom_font__';
  custom.textContent = '自定义字体...';
  dom.fontFace.append(custom);
}

function syncSelect(select, value) {
  if (value && ![...select.options].some((option) => option.value === value)) {
    const option = document.createElement('option');
    option.value = value;
    option.textContent = value;
    select.prepend(option);
  }
  select.value = value || select.options[0]?.value || '';
}

function setRange(rangeInput, numberInput, output, value) {
  rangeInput.value = String(value);
  numberInput.value = String(value);
  output.value = String(value);
}

function clampNumber(value, min, max) {
  const number = Number(value);
  if (!Number.isFinite(number)) return min;
  return Math.max(min, Math.min(max, Math.round(number)));
}

function updateFontFace() {
  if (!state.draftSkin) return;
  if (dom.fontFace.value !== '__custom_font__') {
    updateDraftLayout('fontFace', dom.fontFace.value);
    return;
  }
  const current = state.draftSkin.layout?.fontFace || '';
  const value = window.prompt('输入字体名称，多个字体可用逗号分隔。', current);
  if (!value) {
    syncSelect(dom.fontFace, current);
    return;
  }
  const trimmed = value.trim();
  syncSelect(dom.fontFace, trimmed);
  updateDraftLayout('fontFace', trimmed);
}

function currentFrontendFiles() {
  const files = new Set();
  for (const [platform, filename] of Object.entries(PLATFORM_FILES)) {
    if (state.fileExists[platform]) files.add(filename);
  }
  return files;
}

function normalizedLayout(skin) {
  const layout = skin.layout || {};
  return {
    mode: state.selectedPlatform === 'squirrel'
      ? layout.candidateListLayout || 'stacked'
      : layout.horizontal ? 'linear' : 'stacked',
    fontFace: layout.fontFace || COMMON_FONTS[0],
    fontPoint: layout.fontPoint || 16,
    cornerRadius: layout.cornerRadius ?? 6,
    candidateSpacing: layout.candidateSpacing ?? layout.spacing ?? 8,
    shadowSize: layout.shadowSize ?? 8,
  };
}

function defaultLayoutForPlatform(platform) {
  return platform === 'squirrel'
    ? { fontFace: COMMON_FONTS[0], fontPoint: 16, candidateListLayout: 'stacked', cornerRadius: 6 }
    : { fontFace: COMMON_FONTS[0], fontPoint: 16, horizontal: false, cornerRadius: 6 };
}

function cloneSkin(skin) {
  return cloneJson(skin);
}

function cloneJson(value) {
  return JSON.parse(JSON.stringify(value));
}

function rgbaToCssHex(color) {
  return `#${toHex(color.r)}${toHex(color.g)}${toHex(color.b)}`;
}

function cssHexToRgba(value) {
  const raw = value.replace('#', '');
  return {
    r: parseInt(raw.slice(0, 2), 16),
    g: parseInt(raw.slice(2, 4), 16),
    b: parseInt(raw.slice(4, 6), 16),
    a: 255,
  };
}

function rgbaToCss(color) {
  return `rgba(${color.r}, ${color.g}, ${color.b}, ${(color.a ?? 255) / 255})`;
}

function toHex(value) {
  return Math.max(0, Math.min(255, Math.round(value))).toString(16).padStart(2, '0');
}

function escapeHtml(value) {
  return String(value ?? '')
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');
}

function logMessage(message) {
  dom.messageLog.textContent = `${new Date().toLocaleTimeString()} ${message}\n${dom.messageLog.textContent || ''}`.trim();
}
