function detectBrowserCapabilities(env = globalThis) {
  if (!env.isSecureContext) {
    return {
      canEditLocalRime: false,
      reason: '当前页面不是安全上下文，浏览器不允许读写本地配置文件夹。',
    };
  }

  if (
    typeof env.showDirectoryPicker !== 'function' ||
    !('FileSystemDirectoryHandle' in env) ||
    !('FileSystemFileHandle' in env) ||
    typeof env.FileSystemFileHandle?.prototype?.createWritable !== 'function'
  ) {
    return {
      canEditLocalRime: false,
      reason: '当前浏览器不支持本地文件夹读写，请使用 Chrome、Edge 或 Opera 等支持的浏览器。',
    };
  }

  return { canEditLocalRime: true, reason: '' };
}

function detectPreferredPlatform(env = {}) {
  const platform = String(env.platform || env.navigator?.platform || '').toLowerCase();
  const userAgent = String(env.userAgent || env.navigator?.userAgent || '').toLowerCase();
  const value = `${platform} ${userAgent}`;

  if (value.includes('mac')) return 'squirrel';
  if (value.includes('win')) return 'weasel';
  return 'unknown';
}

function generateSkinId(displayName, existingIds = []) {
  const ascii = String(displayName || '')
    .normalize('NFKD')
    .replace(/[\u0300-\u036f]/g, '')
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '_')
    .replace(/^_+|_+$/g, '')
    .replace(/_{2,}/g, '_');
  const base = ascii || 'skin';
  const existing = new Set(existingIds);
  if (!existing.has(base)) return base;

  let index = 2;
  while (existing.has(`${base}_${index}`)) index += 1;
  return `${base}_${index}`;
}

function rimeHexToRgba(value) {
  const raw = String(value || '').trim().replace(/^0x/i, '');
  if (!/^[0-9a-fA-F]{1,8}$/.test(raw)) {
    throw new Error(`Invalid Rime color: ${value}`);
  }

  const padded = raw.length <= 6 ? `FF${raw.padStart(6, '0')}` : raw.padStart(8, '0');
  const a = parseInt(padded.slice(0, 2), 16);
  const b = parseInt(padded.slice(2, 4), 16);
  const g = parseInt(padded.slice(4, 6), 16);
  const r = parseInt(padded.slice(6, 8), 16);
  return { r, g, b, a };
}

function rgbaToRimeHex(rgba, includeAlpha = true) {
  const r = byteToHex(rgba.r);
  const g = byteToHex(rgba.g);
  const b = byteToHex(rgba.b);
  const a = byteToHex(rgba.a ?? 255);
  return includeAlpha ? `0x${a}${b}${g}${r}` : `0x${b}${g}${r}`;
}

function formatBackupFolderName(
  date,
  summary,
  timezoneOffsetMinutes = -date.getTimezoneOffset(),
  existingNames = new Set(),
) {
  const local = new Date(date.getTime() + timezoneOffsetMinutes * 60 * 1000);
  const stamp = [
    local.getUTCFullYear(),
    pad2(local.getUTCMonth() + 1),
    pad2(local.getUTCDate()),
  ].join('-');
  const time = [
    pad2(local.getUTCHours()),
    pad2(local.getUTCMinutes()),
    pad2(local.getUTCSeconds()),
  ].join('-');
  const safeSummary = String(summary || '保存皮肤')
    .replace(/[\\/:*?"<>|]/g, '-')
    .replace(/\s+/g, ' ')
    .trim();
  const base = `${stamp} ${time} ${safeSummary}`;
  if (!existingNames.has(base)) return base;
  let index = 2;
  while (existingNames.has(`${base} ${index}`)) index += 1;
  return `${base} ${index}`;
}

function parseYaml(text) {
  const root = {};
  const stack = [{ indent: -1, value: root }];
  const lines = String(text || '').split(/\r?\n/);
  let previousScalarIndent = null;

  for (let lineIndex = 0; lineIndex < lines.length; lineIndex += 1) {
    const rawLine = lines[lineIndex];
    if (rawLine.includes('\t')) {
      throw new Error(`YAML 缩进不支持 Tab：第 ${lineIndex + 1} 行`);
    }
    const withoutComment = stripYamlComment(rawLine);
    if (!withoutComment.trim()) continue;

    const indent = withoutComment.match(/^ */)?.[0].length ?? 0;
    if (indent % 2 !== 0) {
      throw new Error(`YAML 缩进必须使用 2 个空格：第 ${lineIndex + 1} 行`);
    }
    if (previousScalarIndent !== null && indent > previousScalarIndent) {
      throw new Error(`YAML 标量值后不能继续缩进：第 ${lineIndex + 1} 行`);
    }
    const trimmed = withoutComment.trim();
    if (trimmed === '---' || trimmed === '...') continue;
    if (trimmed.startsWith('- ')) {
      while (stack.length > 1 && indent < stack[stack.length - 1].indent) {
        stack.pop();
      }
      const frame = stack[stack.length - 1];
      if (!Array.isArray(frame.value)) {
        throw new Error(`YAML 列表位置不支持：第 ${lineIndex + 1} 行`);
      }
      frame.value.push(parseScalar(trimmed.slice(2).trim()));
      previousScalarIndent = indent;
      continue;
    }

    const colonIndex = findTopLevelColon(trimmed);
    if (colonIndex < 0) {
      throw new Error(`YAML 语法无法识别：第 ${lineIndex + 1} 行`);
    }

    const rawKey = trimmed.slice(0, colonIndex).trim();
    const rawValue = trimmed.slice(colonIndex + 1).trim();
    if (!rawKey) throw new Error(`YAML 键名为空：第 ${lineIndex + 1} 行`);
    const key = unquote(rawKey);

    while (stack.length > 1 && indent <= stack[stack.length - 1].indent) {
      stack.pop();
    }

    const parent = stack[stack.length - 1].value;
    if (!isPlainObject(parent)) {
      throw new Error(`YAML 列表项内的嵌套对象暂不支持：第 ${lineIndex + 1} 行`);
    }
    if (rawValue === '') {
      const nextLine = nextContentLine(lines, lineIndex + 1);
      const child = nextLine?.trim().startsWith('- ') ? [] : {};
      if (Array.isArray(child) && !allowsListChildren(key)) {
        throw new Error(`YAML 列表位置不支持：第 ${lineIndex + 1} 行`);
      }
      parent[key] = child;
      stack.push({ indent, value: child });
      previousScalarIndent = null;
    } else {
      parent[key] = parseScalar(rawValue);
      previousScalarIndent = indent;
    }
  }

  return root;
}

function stringifyYaml(value, indent = 0) {
  const lines = [];
  if (Array.isArray(value)) {
    for (const item of value) {
      const prefix = ' '.repeat(indent);
      lines.push(`${prefix}- ${renderScalar(item)}`);
    }
    return lines.join('\n');
  }
  for (const [key, child] of Object.entries(value || {})) {
    const renderedKey = renderKey(key);
    const prefix = ' '.repeat(indent);
    if (isPlainObject(child)) {
      lines.push(`${prefix}${renderedKey}:`);
      lines.push(stringifyYaml(child, indent + 2));
    } else if (Array.isArray(child)) {
      lines.push(`${prefix}${renderedKey}:`);
      lines.push(stringifyYaml(child, indent + 2));
    } else {
      lines.push(`${prefix}${renderedKey}: ${renderScalar(child)}`);
    }
  }
  return lines.filter(Boolean).join('\n');
}

function parseSquirrelConfig(text) {
  const doc = parseYaml(text);
  const patch = validatePatchObject(doc, 'squirrel.custom.yaml');
  const style = patch.style || {};
  if (!isPlainObject(style)) throw new Error('squirrel.custom.yaml 的 patch.style 必须是对象。');
  const schemes = patch.preset_color_schemes || {};
  if (!isPlainObject(schemes)) {
    throw new Error('squirrel.custom.yaml 的 patch.preset_color_schemes 必须是对象。');
  }
  const globalLayout = layoutFromStyle(style);
  const skins = Object.entries(schemes).map(([id, scheme]) =>
    skinFromScheme('squirrel', id, scheme, globalLayout, {
      file: 'squirrel.custom.yaml',
      path: `patch.preset_color_schemes.${id}`,
    }),
  );

  return {
    platform: 'squirrel',
    document: doc,
    skins,
    activeSkinId: style.color_scheme || '',
    darkSkinId: style.color_scheme_dark || '',
  };
}

function parseWeaselConfig(text) {
  const doc = parseYaml(text);
  const patch = validatePatchObject(doc, 'weasel.custom.yaml');
  const style = patch.style || {};
  if (!isPlainObject(style)) throw new Error('weasel.custom.yaml 的 patch.style 必须是对象。');
  const globalLayout = layoutFromStyle(style);
  const skins = [];

  for (const [key, value] of Object.entries(patch)) {
    if (!key.startsWith('preset_color_schemes/')) continue;
    if (!isPlainObject(value)) throw new Error(`weasel.custom.yaml 的 ${key} 必须是对象。`);
    const id = key.slice('preset_color_schemes/'.length);
    skins.push(
      skinFromScheme('weasel', id, value, globalLayout, {
        file: 'weasel.custom.yaml',
        path: `patch["${key}"]`,
      }),
    );
  }

  return {
    platform: 'weasel',
    document: doc,
    skins,
    activeSkinId: patch['style/color_scheme'] || style.color_scheme || '',
    darkSkinId: '',
  };
}

function validatePatchObject(doc, filename) {
  const patch = doc.patch || {};
  if (!isPlainObject(patch)) throw new Error(`${filename} 的 patch 必须是对象。`);
  return patch;
}

function updateSquirrelConfig(text, skin, options = {}) {
  validatePatchObject(parseYaml(text || ''), 'squirrel.custom.yaml');
  const schemePatch = schemeFromSkin(skin, 'squirrel');
  const stylePatch = {
    ...styleFromSkin(skin, 'squirrel'),
    ...(options.makeActive ? { color_scheme: skin.id } : {}),
    ...(options.makeDark ? { color_scheme_dark: skin.id } : {}),
  };
  let output = ensurePatchText(text || 'patch:\n');
  output = upsertObjectFields(output, ['patch', 'preset_color_schemes', skin.id], schemePatch);
  output = upsertObjectFields(output, ['patch', 'style'], stylePatch);
  if (schemePatch.candidate_list_layout !== undefined) {
    output = removeNestedBlock(output, ['patch', 'preset_color_schemes', skin.id, 'horizontal']);
  }
  if (stylePatch.candidate_list_layout !== undefined) {
    output = removeNestedBlock(output, ['patch', 'style', 'horizontal']);
  }
  return ensureTrailingNewline(output);
}

function updateWeaselConfig(text, skin, options = {}) {
  validatePatchObject(parseYaml(text || ''), 'weasel.custom.yaml');
  const schemePatch = schemeFromSkin(skin, 'weasel');
  const stylePatch = styleFromSkin(skin, 'weasel');
  let output = ensurePatchText(text || 'patch:\n');
  output = upsertObjectFields(output, ['patch', `preset_color_schemes/${skin.id}`], schemePatch);
  output = upsertObjectFields(output, ['patch', 'style'], stylePatch);
  if (options.makeActive) output = upsertNestedValue(output, ['patch', 'style/color_scheme'], skin.id);
  return ensureTrailingNewline(output);
}

function deleteSquirrelSkinConfig(text, skinId) {
  validatePatchObject(parseYaml(text || ''), 'squirrel.custom.yaml');
  let output = removeNestedBlock(text, ['patch', 'preset_color_schemes', skinId]);
  output = removeNestedValue(output, ['patch', 'style', 'color_scheme'], skinId);
  output = removeNestedValue(output, ['patch', 'style', 'color_scheme_dark'], skinId);
  return ensureTrailingNewline(output);
}

function deleteWeaselSkinConfig(text, skinId) {
  validatePatchObject(parseYaml(text || ''), 'weasel.custom.yaml');
  let output = removeNestedBlock(text, ['patch', `preset_color_schemes/${skinId}`]);
  output = removeNestedValue(output, ['patch', 'style/color_scheme'], skinId);
  return ensureTrailingNewline(output);
}

function copySkinToPlatform(skin, targetPlatform) {
  const sourceLayout = skin.layout || {};
  const layout = { ...sourceLayout };

  if (targetPlatform === 'weasel') {
    if (sourceLayout.candidateListLayout) {
      layout.horizontal = sourceLayout.candidateListLayout === 'linear';
    }
    delete layout.candidateListLayout;
    delete layout.textOrientation;
  } else if (targetPlatform === 'squirrel') {
    if (typeof sourceLayout.horizontal === 'boolean') {
      layout.candidateListLayout = sourceLayout.horizontal ? 'linear' : 'stacked';
    }
    delete layout.horizontal;
  }

  return {
    ...skin,
    platform: targetPlatform,
    colors: cloneJson(skin.colors || {}),
    layout,
    source: undefined,
    unsupportedFields: {},
    copiedFrom: skin.platform,
  };
}

function createBackupManifest(input) {
  return {
    version: 1,
    createdAt: input.createdAt,
    operation: input.operation,
    sourcePlatform: input.sourcePlatform || '',
    targetPlatform: input.targetPlatform || '',
    skinIdBefore: input.skinIdBefore || '',
    skinIdAfter: input.skinIdAfter || '',
    files: [...(input.files || [])],
    createdFiles: [...(input.createdFiles || [])],
    browser: input.browser || '',
    rimeFolder: input.rimeFolder || '',
  };
}

function createRollbackPlan(backupEntry, currentFiles = new Set()) {
  const manifest = backupEntry?.manifest;
  if (!manifest || !Array.isArray(manifest.files)) {
    throw new Error('备份清单缺失，无法安全回退。');
  }

  const available = backupEntry.availableFiles || new Set();
  const filesToRestore = [];
  for (const file of manifest.files) {
    if (!available.has(file)) throw new Error(`备份文件缺失：${file}`);
    filesToRestore.push(file);
  }
  const filesToDelete = [];
  for (const file of manifest.createdFiles || []) {
    if (currentFiles.has(file)) filesToDelete.push(file);
  }

  return {
    operation: manifest.operation || '',
    filesToRestore,
    filesToDelete,
    requiresCurrentBackup: true,
  };
}

function byteToHex(value) {
  const number = Number(value);
  if (!Number.isFinite(number)) throw new Error(`Invalid color byte: ${value}`);
  return Math.max(0, Math.min(255, Math.round(number)))
    .toString(16)
    .toUpperCase()
    .padStart(2, '0');
}

function pad2(value) {
  return String(value).padStart(2, '0');
}

function stripYamlComment(line) {
  let quote = '';
  for (let index = 0; index < line.length; index += 1) {
    const char = line[index];
    if ((char === '"' || char === "'") && line[index - 1] !== '\\') {
      quote = quote === char ? '' : quote || char;
    }
    if (char === '#' && !quote) {
      return line.slice(0, index);
    }
  }
  return line;
}

function nextContentLine(lines, startIndex) {
  for (let index = startIndex; index < lines.length; index += 1) {
    const line = stripYamlComment(lines[index]);
    if (line.trim()) return line;
  }
  return '';
}

function findTopLevelColon(line) {
  let quote = '';
  let braceDepth = 0;
  for (let index = 0; index < line.length; index += 1) {
    const char = line[index];
    if ((char === '"' || char === "'") && line[index - 1] !== '\\') {
      quote = quote === char ? '' : quote || char;
    } else if (!quote && char === '{') {
      braceDepth += 1;
    } else if (!quote && char === '}') {
      braceDepth -= 1;
    } else if (!quote && braceDepth === 0 && char === ':') {
      return index;
    }
  }
  return -1;
}

function parseScalar(value) {
  const trimmed = value.trim();
  if (trimmed.startsWith('{') && trimmed.endsWith('}')) return parseInlineObject(trimmed);
  if (/^["']/.test(trimmed)) return unquote(trimmed);
  if (/^(true|false)$/i.test(trimmed)) return /^true$/i.test(trimmed);
  if (/^-?\d+(\.\d+)?$/.test(trimmed)) return Number(trimmed);
  return trimmed;
}

function parseInlineObject(value) {
  const inner = value.slice(1, -1).trim();
  const result = {};
  if (!inner) return result;

  for (const part of splitTopLevel(inner, ',')) {
    const colon = findTopLevelColon(part);
    if (colon < 0) continue;
    const key = unquote(part.slice(0, colon).trim());
    const rawValue = part.slice(colon + 1).trim();
    result[key] = parseScalar(rawValue);
  }
  return result;
}

function splitTopLevel(value, separator) {
  const parts = [];
  let quote = '';
  let braceDepth = 0;
  let start = 0;
  for (let index = 0; index < value.length; index += 1) {
    const char = value[index];
    if ((char === '"' || char === "'") && value[index - 1] !== '\\') {
      quote = quote === char ? '' : quote || char;
    } else if (!quote && char === '{') {
      braceDepth += 1;
    } else if (!quote && char === '}') {
      braceDepth -= 1;
    } else if (!quote && braceDepth === 0 && char === separator) {
      parts.push(value.slice(start, index).trim());
      start = index + 1;
    }
  }
  parts.push(value.slice(start).trim());
  return parts;
}

function unquote(value) {
  const trimmed = String(value || '').trim();
  if (
    (trimmed.startsWith('"') && trimmed.endsWith('"')) ||
    (trimmed.startsWith("'") && trimmed.endsWith("'"))
  ) {
    return trimmed.slice(1, -1);
  }
  return trimmed;
}

function renderKey(key) {
  return /[\s/:.[\]"']/.test(key) ? JSON.stringify(key) : key;
}

function renderScalar(value) {
  if (typeof value === 'string') {
    if (/^0x[0-9a-fA-F]+$/.test(value)) return value;
    if (/^[A-Za-z0-9_.-]+$/.test(value)) return value;
    return JSON.stringify(value);
  }
  if (typeof value === 'boolean' || typeof value === 'number') return String(value);
  if (isPlainObject(value)) {
    return `{${Object.entries(value)
      .map(([key, child]) => `${key}: ${renderScalar(child)}`)
      .join(', ')}}`;
  }
  return JSON.stringify(value);
}

function isPlainObject(value) {
  return value && typeof value === 'object' && !Array.isArray(value);
}

function allowsListChildren(key) {
  return /(^|\/)(schema_list|switches|bindings|schema_dependencies|accept|reject|import_tables|columns|encoder\/rules)$/.test(key);
}

function deepMergeObjects(base, updates) {
  const result = cloneJson(base || {});
  for (const [key, value] of Object.entries(updates || {})) {
    if (isPlainObject(value) && isPlainObject(result[key])) {
      result[key] = deepMergeObjects(result[key], value);
    } else {
      result[key] = cloneJson(value);
    }
  }
  return result;
}

function skinFromScheme(platform, id, scheme = {}, layout = {}, source) {
  return {
    platform,
    id,
    displayName: scheme.name || id,
    author: scheme.author || '',
    colors: colorsFromScheme(scheme),
    layout: {
      ...layout,
      ...layoutFromStyle(scheme),
    },
    source,
    unsupportedFields: {},
  };
}

function colorsFromScheme(scheme) {
  const mapping = {
    back: 'back_color',
    border: 'border_color',
    text: 'text_color',
    candidateText: 'candidate_text_color',
    candidateBack: 'candidate_back_color',
    commentText: 'comment_text_color',
    label: 'label_color',
    hilitedText: 'hilited_text_color',
    hilitedBack: 'hilited_back_color',
    hilitedCandidateText: 'hilited_candidate_text_color',
    hilitedCandidateBack: 'hilited_candidate_back_color',
    hilitedCommentText: 'hilited_comment_text_color',
    hilitedLabel: 'hilited_label_color',
    shadow: 'shadow_color',
  };
  const colors = {};
  for (const [role, key] of Object.entries(mapping)) {
    if (scheme[key] !== undefined) colors[role] = rimeHexToRgba(scheme[key]);
  }
  return colors;
}

function layoutFromStyle(style = {}) {
  const layout = {};
  if (style.font_face !== undefined) layout.fontFace = style.font_face;
  if (style.font_point !== undefined) layout.fontPoint = style.font_point;
  if (style.label_font_point !== undefined) layout.labelFontPoint = style.label_font_point;
  if (style.comment_font_point !== undefined) layout.commentFontPoint = style.comment_font_point;
  if (style.corner_radius !== undefined) layout.cornerRadius = style.corner_radius;
  if (style.hilited_corner_radius !== undefined) layout.hilitedCornerRadius = style.hilited_corner_radius;
  if (style.candidate_list_layout !== undefined) layout.candidateListLayout = style.candidate_list_layout;
  if (style.text_orientation !== undefined) layout.textOrientation = style.text_orientation;
  if (style.horizontal !== undefined) layout.horizontal = style.horizontal;
  if (style.candidate_list_layout === undefined && typeof style.horizontal === 'boolean') {
    layout.candidateListLayout = style.horizontal ? 'linear' : 'stacked';
  }
  if (isPlainObject(style.layout)) {
    if (style.layout.corner_radius !== undefined) layout.cornerRadius = style.layout.corner_radius;
    if (style.layout.round_corner !== undefined) layout.hilitedCornerRadius = style.layout.round_corner;
    if (style.layout.margin_x !== undefined) layout.marginX = style.layout.margin_x;
    if (style.layout.margin_y !== undefined) layout.marginY = style.layout.margin_y;
    if (style.layout.candidate_spacing !== undefined) layout.candidateSpacing = style.layout.candidate_spacing;
    if (style.layout.hilite_spacing !== undefined) layout.hiliteSpacing = style.layout.hilite_spacing;
    if (style.layout.spacing !== undefined) layout.spacing = style.layout.spacing;
  }
  return layout;
}

function ensurePatchText(text) {
  const source = String(text || '').trimEnd();
  if (!source.trim()) return 'patch:\n';
  if (source.split(/\r?\n/).some((line) => parseLineKey(line) === 'patch')) return `${source}\n`;
  return `${source}\npatch:\n`;
}

function ensureTrailingNewline(text) {
  return `${String(text).replace(/\s+$/g, '')}\n`;
}

function upsertNestedValue(text, path, value) {
  return upsertNestedBlock(text, path, value);
}

function upsertObjectFields(text, path, fields) {
  let output = ensurePatchText(text);
  output = ensureNestedObjectPath(output, path);
  for (const [key, value] of Object.entries(fields || {})) {
    if (isPlainObject(value)) {
      output = upsertObjectFields(output, [...path, key], value);
    } else {
      output = upsertNestedBlock(output, [...path, key], value);
    }
  }
  return output;
}

function ensureNestedObjectPath(text, path) {
  let output = ensurePatchText(text);
  for (let depth = 1; depth <= path.length; depth += 1) {
    const partial = path.slice(0, depth);
    output = expandInlineObjectAtPath(output, partial);
    const lines = ensurePatchText(output).split(/\n/);
    if (!findPathRange(lines, partial)) {
      output = upsertNestedBlock(output, partial, {});
    }
  }
  return output;
}

function expandInlineObjectAtPath(text, path) {
  const lines = ensurePatchText(text).split(/\n/);
  const found = findPathRange(lines, path);
  if (!found) return text;
  const line = lines[found.start] || '';
  const rawValue = stripYamlComment(line.slice(line.indexOf(':') + 1)).trim();
  if (!rawValue.startsWith('{') || !rawValue.endsWith('}')) return text;
  const object = parseInlineObject(rawValue);
  lines.splice(found.start, found.end - found.start, ...renderPathBlock(path[path.length - 1], object, found.indent));
  return lines.join('\n');
}

function upsertNestedBlock(text, path, value) {
  const lines = ensurePatchText(text).split(/\n/);
  const found = findPathRange(lines, path);
  const parent = findPathRange(lines, path.slice(0, -1));
  const indent = found?.indent ?? childIndentFor(lines, parent, path.length - 1);
  const block = renderPathBlock(path[path.length - 1], value, indent);

  if (found) {
    lines.splice(found.start, found.end - found.start, ...block);
    return lines.join('\n');
  }

  const parentPath = path.slice(0, -1);
  if (parent) {
    lines.splice(parent.end, 0, ...block);
    return lines.join('\n');
  }

  const ancestor = findDeepestPathAncestor(lines, path);
  if (ancestor) {
    const missingPath = path.slice(ancestor.depth);
    const baseIndent = childIndentFor(lines, ancestor.range, ancestor.depth);
    lines.splice(ancestor.range.end, 0, ...renderRelativePathChain(missingPath, value, baseIndent));
    return lines.join('\n');
  }

  return `${lines.join('\n')}${lines.at(-1) === '' ? '' : '\n'}${renderPathChain(path, value).join('\n')}`;
}

function removeNestedBlock(text, path) {
  const lines = String(text || '').split(/\n/);
  const found = findPathRange(lines, path);
  if (!found) return text;
  lines.splice(found.start, found.end - found.start);
  return lines.join('\n');
}

function removeNestedValue(text, path, matchingValue) {
  const lines = String(text || '').split(/\n/);
  const found = findPathRange(lines, path);
  if (!found) return text;
  const line = lines[found.start] || '';
  const valuePart = line.slice(line.indexOf(':') + 1).trim();
  const parsedValue = parseScalar(stripYamlComment(valuePart));
  if (matchingValue !== undefined && parsedValue !== matchingValue) return text;
  lines.splice(found.start, found.end - found.start);
  return lines.join('\n');
}

function renderPathChain(path, value) {
  const lines = [];
  for (let index = 0; index < path.length - 1; index += 1) {
    lines.push(`${' '.repeat(index * 2)}${renderKey(path[index])}:`);
  }
  lines.push(...renderPathBlock(path[path.length - 1], value, (path.length - 1) * 2));
  return lines;
}

function renderRelativePathChain(path, value, baseIndent) {
  if (path.length === 1) return renderPathBlock(path[0], value, baseIndent);
  const lines = [];
  for (let index = 0; index < path.length - 1; index += 1) {
    lines.push(`${' '.repeat(baseIndent + index * 2)}${renderKey(path[index])}:`);
  }
  lines.push(...renderPathBlock(path[path.length - 1], value, baseIndent + (path.length - 1) * 2));
  return lines;
}

function findDeepestPathAncestor(lines, path) {
  for (let depth = path.length - 1; depth > 0; depth -= 1) {
    const range = findPathRange(lines, path.slice(0, depth));
    if (range) return { depth, range };
  }
  return null;
}

function renderPathBlock(key, value, indent) {
  const prefix = ' '.repeat(indent);
  const renderedKey = renderKey(key);
  if (isPlainObject(value)) {
    const lines = [`${prefix}${renderedKey}:`];
    const body = stringifyYaml(value, indent + 2);
    if (body) lines.push(...body.split('\n'));
    return lines;
  }
  return [`${prefix}${renderedKey}: ${renderScalar(value)}`];
}

function findPathRange(lines, path) {
  if (!path.length) return { start: 0, end: lines.length, indent: -1 };
  let searchStart = 0;
  let parentEnd = lines.length;
  let expectedIndent = 0;
  let current = null;

  for (let depth = 0; depth < path.length; depth += 1) {
    const key = path[depth];
    current = null;
    for (let index = searchStart; index < parentEnd; index += 1) {
      const line = lines[index];
      if (!line?.trim() || line.trimStart().startsWith('#')) continue;
      const indent = line.match(/^ */)?.[0].length ?? 0;
      if (indent !== expectedIndent) continue;
      const parsed = parseLineKey(line);
      if (parsed === key) {
        const end = findBlockEnd(lines, index, indent);
        current = { start: index, end, indent };
        break;
      }
    }
    if (!current) return null;
    searchStart = current.start + 1;
    parentEnd = current.end;
    expectedIndent = childIndentFor(lines, current, depth + 1);
  }
  return current;
}

function childIndentFor(lines, parent, depth) {
  if (!parent || parent.indent < 0) return depth * 2;
  for (let index = parent.start + 1; index < parent.end; index += 1) {
    const line = lines[index];
    if (!line?.trim() || line.trimStart().startsWith('#')) continue;
    const indent = line.match(/^ */)?.[0].length ?? 0;
    if (indent > parent.indent) return indent;
  }
  return parent.indent + 2;
}

function parseLineKey(line) {
  const trimmed = stripYamlComment(line).trim();
  if (trimmed.startsWith('- ')) return null;
  const colon = findTopLevelColon(trimmed);
  if (colon < 0) return null;
  return unquote(trimmed.slice(0, colon).trim());
}

function findBlockEnd(lines, start, indent) {
  for (let index = start + 1; index < lines.length; index += 1) {
    const line = lines[index];
    if (!line.trim()) continue;
    const currentIndent = line.match(/^ */)?.[0].length ?? 0;
    if (currentIndent <= indent) return index;
  }
  return lines.length;
}

function schemeFromSkin(skin, platform) {
  const scheme = {
    name: skin.displayName || skin.id,
  };
  if (skin.author) scheme.author = skin.author;

  const colorKeys = {
    back: 'back_color',
    border: 'border_color',
    text: 'text_color',
    candidateText: 'candidate_text_color',
    candidateBack: 'candidate_back_color',
    commentText: 'comment_text_color',
    label: 'label_color',
    hilitedText: 'hilited_text_color',
    hilitedBack: 'hilited_back_color',
    hilitedCandidateText: 'hilited_candidate_text_color',
    hilitedCandidateBack: 'hilited_candidate_back_color',
    hilitedCommentText: 'hilited_comment_text_color',
    hilitedLabel: 'hilited_label_color',
    shadow: 'shadow_color',
  };

  for (const [role, key] of Object.entries(colorKeys)) {
    if (skin.colors?.[role]) {
      const color = skin.colors[role];
      scheme[key] = rgbaToRimeHex(color, color.a !== 255);
    }
  }

  const layout = skin.layout || {};
  if (platform === 'squirrel') {
    if (layout.fontPoint !== undefined) scheme.font_point = layout.fontPoint;
    if (layout.candidateListLayout !== undefined) scheme.candidate_list_layout = layout.candidateListLayout;
    if (layout.cornerRadius !== undefined) scheme.corner_radius = layout.cornerRadius;
    if (layout.hilitedCornerRadius !== undefined) scheme.hilited_corner_radius = layout.hilitedCornerRadius;
  }

  return scheme;
}

function styleFromSkin(skin, platform) {
  const layout = skin.layout || {};
  const style = {};

  if (layout.fontFace !== undefined) style.font_face = layout.fontFace;
  if (layout.fontPoint !== undefined) style.font_point = layout.fontPoint;
  if (layout.labelFontPoint !== undefined) style.label_font_point = layout.labelFontPoint;
  if (layout.commentFontPoint !== undefined) style.comment_font_point = layout.commentFontPoint;

  if (platform === 'squirrel') {
    if (layout.candidateListLayout !== undefined) style.candidate_list_layout = layout.candidateListLayout;
    if (layout.textOrientation !== undefined) style.text_orientation = layout.textOrientation;
    if (layout.cornerRadius !== undefined) style.corner_radius = layout.cornerRadius;
    if (layout.hilitedCornerRadius !== undefined) style.hilited_corner_radius = layout.hilitedCornerRadius;
    if (layout.spacing !== undefined) style.spacing = layout.spacing;
    if (layout.lineSpacing !== undefined) style.line_spacing = layout.lineSpacing;
    return style;
  }

  if (layout.horizontal !== undefined) style.horizontal = layout.horizontal;
  const nested = {};
  if (layout.cornerRadius !== undefined) nested.corner_radius = layout.cornerRadius;
  if (layout.hilitedCornerRadius !== undefined) nested.round_corner = layout.hilitedCornerRadius;
  if (layout.marginX !== undefined) nested.margin_x = layout.marginX;
  if (layout.marginY !== undefined) nested.margin_y = layout.marginY;
  if (layout.candidateSpacing !== undefined) nested.candidate_spacing = layout.candidateSpacing;
  if (layout.hiliteSpacing !== undefined) nested.hilite_spacing = layout.hiliteSpacing;
  if (layout.spacing !== undefined) nested.spacing = layout.spacing;
  if (Object.keys(nested).length) style.layout = nested;
  return style;
}

function cloneJson(value) {
  return JSON.parse(JSON.stringify(value));
}

const RimeSkinCore = {
  detectBrowserCapabilities,
  detectPreferredPlatform,
  generateSkinId,
  rimeHexToRgba,
  rgbaToRimeHex,
  formatBackupFolderName,
  parseYaml,
  stringifyYaml,
  parseSquirrelConfig,
  parseWeaselConfig,
  updateSquirrelConfig,
  updateWeaselConfig,
  deleteSquirrelSkinConfig,
  deleteWeaselSkinConfig,
  copySkinToPlatform,
  createBackupManifest,
  createRollbackPlan,
};

if (typeof globalThis !== 'undefined') {
  globalThis.RimeSkinCore = RimeSkinCore;
}

if (typeof module !== 'undefined' && module.exports) {
  module.exports = RimeSkinCore;
}
