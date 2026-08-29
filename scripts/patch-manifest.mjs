#!/usr/bin/env node
// Merges a Safari override document over the upstream extension manifest.
// Usage: patch-manifest.mjs <upstream-manifest> <override> <output>
// Semantics:
//   - Keys starting with '$' are dropped (comment convention).
//   - `null` values in the override remove the key from the merged output.
//   - Objects are merged recursively; arrays and scalars are replaced whole.

import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

export function isPlainObject(v) {
  return v !== null && typeof v === 'object' && !Array.isArray(v);
}

export function merge(base, patch) {
  if (!isPlainObject(patch)) return patch;
  const out = isPlainObject(base) ? { ...base } : {};
  for (const [k, v] of Object.entries(patch)) {
    if (k.startsWith('$')) continue;
    if (v === null) {
      delete out[k];
    } else if (isPlainObject(v)) {
      out[k] = merge(out[k], v);
    } else {
      out[k] = v;
    }
  }
  return out;
}

export function patchManifest(upstream, override) {
  return merge(upstream, override);
}

function main(argv) {
  const [, , upstreamPath, overridePath, outPath] = argv;
  if (!upstreamPath || !overridePath || !outPath) {
    console.error('usage: patch-manifest.mjs <upstream> <override> <output>');
    process.exit(2);
  }

  const upstream = JSON.parse(readFileSync(upstreamPath, 'utf8'));
  const override = JSON.parse(readFileSync(overridePath, 'utf8'));
  const merged = merge(upstream, override);

  mkdirSync(dirname(outPath), { recursive: true });
  writeFileSync(outPath, JSON.stringify(merged, null, 2) + '\n');
  console.error(`wrote ${outPath}`);
}

if (fileURLToPath(import.meta.url) === process.argv[1]) {
  main(process.argv);
}
