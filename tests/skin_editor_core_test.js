const assert = require('assert');

const core = require('../Rime皮肤编辑器/src/core.js');

function test(name, fn) {
  try {
    fn();
    console.log(`ok - ${name}`);
  } catch (error) {
    console.error(`not ok - ${name}`);
    throw error;
  }
}

test('squirrel config writer does not emit weasel-only mark_text', () => {
  const updated = core.updateSquirrelConfig('patch:\n', {
    id: 'test_skin',
    displayName: 'Test Skin',
    colors: {},
    layout: {
      candidateListLayout: 'stacked',
      candidateFormat: '%c. %@',
      markText: '▌',
    },
  });

  assert.ok(!updated.includes('mark_text'), updated);
});

test('weasel config writer emits mark_text', () => {
  const updated = core.updateWeaselConfig('patch:\n', {
    id: 'test_skin',
    displayName: 'Test Skin',
    colors: {},
    layout: {
      horizontal: false,
      labelFormat: '%s.',
      markText: '▌',
    },
  });

  assert.ok(updated.includes('mark_text: "▌"') || updated.includes('mark_text: ▌'), updated);
});
