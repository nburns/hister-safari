#!/usr/bin/env node
// Merges a Safari override document over the upstream extension manifest.
// Usage: patch-manifest.mjs <upstream-manifest> <override> <output>
// Semantics:
//   - Keys starting with '$' are dropped (comment convention).
//   - `null` values in the override remove the key from the merged output.
//   - Objects are merged recursively; arrays and scalars are replaced whole.

import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { dirname } from 'node:path';

const [, , upstreamPath, overridePath, outPath] = process.argv;
if (!upstreamPath || !overridePath || !outPath) {
  console.error('usage: patch-manifest.mjs <upstream> <override> <output>');
  process.exit(2);
}

function isPlainObject(v) {
  return v !== null && typeof v === 'object' && !Array.isArray(v);
}

function merge(base, patch) {
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

const upstream = JSON.parse(readFileSync(upstreamPath, 'utf8'));
const override = JSON.parse(readFileSync(overridePath, 'utf8'));
const merged = merge(upstream, override);

mkdirSync(dirname(outPath), { recursive: true });
writeFileSync(outPath, JSON.stringify(merged, null, 2) + '\n');
console.error(`wrote ${outPath}`);
