import { mkdtempSync, writeFileSync, readFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import test from 'node:test';
import assert from 'node:assert/strict';

import { merge } from './patch-manifest.mjs';

const script = fileURLToPath(new URL('./patch-manifest.mjs', import.meta.url));

test('merge keeps upstream keys, overlays nested objects, and drops $ comments', () => {
  const merged = merge(
    {
      name: 'Hister',
      icons: { 128: 'assets/icons/icon128.png' },
      action: { default_icon: { 128: 'assets/icons/icon128.png' }, default_popup: 'popup.html' },
      key: 'UPSTREAM-KEY',
    },
    {
      $comment: 'ignored',
      key: null,
      icons: { 16: 'assets/icons/icon-16.png', 32: 'assets/icons/icon-32.png' },
      action: { default_icon: { 16: 'assets/icons/icon-16.png' } },
    },
  );

  assert.equal(merged.name, 'Hister');
  assert.equal(merged.key, undefined);
  assert.equal(merged.$comment, undefined);
  assert.deepEqual(merged.icons, {
    128: 'assets/icons/icon128.png',
    16: 'assets/icons/icon-16.png',
    32: 'assets/icons/icon-32.png',
  });
  assert.deepEqual(merged.action, {
    default_icon: {
      128: 'assets/icons/icon128.png',
      16: 'assets/icons/icon-16.png',
    },
    default_popup: 'popup.html',
  });
});

test('CLI writes the merged manifest', () => {
  const dir = mkdtempSync(join(tmpdir(), 'hister-manifest-'));
  try {
    const upstream = join(dir, 'upstream.json');
    const override = join(dir, 'override.json');
    const out = join(dir, 'out.json');
    writeFileSync(upstream, JSON.stringify({ name: 'Hister', key: 'K' }));
    writeFileSync(override, JSON.stringify({ key: null, icons: { 16: 'a.png' } }));

    const result = spawnSync(process.execPath, [script, upstream, override, out], {
      encoding: 'utf8',
    });
    assert.equal(result.status, 0, result.stderr);
    const written = JSON.parse(readFileSync(out, 'utf8'));
    assert.equal(written.name, 'Hister');
    assert.equal(written.key, undefined);
    assert.equal(written.icons[16], 'a.png');
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});
