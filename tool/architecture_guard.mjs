#!/usr/bin/env node
// Serenut OS — Architecture Guard (Faz 0 korkulukları)
//
// Mevcut mimari ihlalleri `tool/architecture_baseline.json` içinde sayı olarak
// dondurur. CI'da her metrik baseline'a eşit ya da daha düşük olmalıdır:
// borç azalabilir, ARTAMAZ.
//
// Kullanım:
//   node tool/architecture_guard.mjs            # kontrol (CI)
//   node tool/architecture_guard.mjs --update   # iyileşmeden sonra baseline'ı düşür
//
// Bir metrik düştüğünde `--update` çalıştırıp baseline'ı commit edin; böylece
// kazanılan iyileşme kilitlenir ve geri kayamaz.

import { readFileSync, writeFileSync, readdirSync, statSync, existsSync } from 'node:fs';
import { join, relative, sep } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = join(fileURLToPath(new URL('.', import.meta.url)), '..');
const BASELINE_PATH = join(ROOT, 'tool', 'architecture_baseline.json');
const MAX_FILE_LINES = 800;

const SKIP_DIRS = new Set(['node_modules', 'dist', 'build', '.dart_tool', '.git', 'public']);

function walk(dir, exts, out = []) {
  if (!existsSync(dir)) return out;
  for (const name of readdirSync(dir)) {
    if (SKIP_DIRS.has(name)) continue;
    const full = join(dir, name);
    const st = statSync(full);
    if (st.isDirectory()) walk(full, exts, out);
    else if (exts.some((e) => name.endsWith(e)) && !/\.(g|freezed)\.dart$/.test(name)) out.push(full);
  }
  return out;
}

const rel = (f) => relative(ROOT, f).split(sep).join('/');
const read = (f) => readFileSync(f, 'utf8');

const dartLib = walk(join(ROOT, 'lib'), ['.dart']);
const serverSrc = walk(join(ROOT, 'server', 'src'), ['.ts']).filter((f) => !rel(f).includes('/test/'));

function countMatches(files, regex, filter = () => true) {
  let total = 0;
  for (const f of files) {
    if (!filter(rel(f))) continue;
    const m = read(f).match(regex);
    if (m) total += m.length;
  }
  return total;
}

function countFiles(files, regex, filter = () => true) {
  return files.filter((f) => filter(rel(f)) && regex.test(read(f))).length;
}

const RULES = [
  {
    id: 'money_real_columns',
    why: 'Para SQLite REAL kolonda tutulmamalı (Faz 1: tam sayı kuruş).',
    count: () => countMatches(dartLib, /\b\w*(price|amount|balance|total|cost)\w*\s+REAL\b/gi,
      (p) => p.includes('/database/')),
  },
  {
    id: 'money_double_fields',
    why: 'Para Dart double ile tutulmamalı (Faz 1: Money value object).',
    count: () => countMatches(dartLib, /\bdouble\??\s+(price|amount|total|balance|paid|debt|cost)\w*/gi),
  },
  {
    id: 'balance_formula_copies',
    why: "Bakiye kuralı tek yerde olmalı (Faz 2). 'manual_debt' içeren CASE kolları sayılır.",
    count: () => countMatches([...dartLib, ...serverSrc], /WHEN[^\n]*'manual_debt'/g),
  },
  {
    id: 'ledger_bypass_toggles',
    why: 'Defter append-only olmalı; bypass bayrağı açılmamalı (Faz 2).',
    count: () => countMatches(dartLib, /ledger_bypass_flag\s+SET\s+active\s*=\s*1/gi),
  },
  {
    id: 'hardcoded_data_repair_ids',
    why: 'Uygulama runtime koduna sabit ID ile veri onarımı yazılmamalı; migration kullanın (Faz 3).',
    count: () => countMatches(dartLib, /'trans-(cancel-)?\d{10,}'/g, (p) => !p.endsWith('db_migrations.dart')),
  },
  {
    id: 'ui_imports_database',
    why: 'Sunum katmanı veritabanını doğrudan import etmemeli (Faz 5).',
    count: () => countFiles(dartLib, /import\s+'package:(sqflite[^']*|serenutos\/infrastructure\/database\/[^']*)'/,
      (p) => p.startsWith('lib/presentation/')),
  },
  {
    id: 'ui_direct_repository_service',
    why: 'Sayfa/widget, repository/servise doğrudan değil controller üzerinden erişmeli (Faz 5).',
    count: () => countMatches(dartLib, /ref\.(read|watch)\(\s*\w*(Repository|Service)Provider/g,
      (p) => p.startsWith('lib/presentation/pages/') || p.startsWith('lib/presentation/widgets/')),
  },
  {
    id: 'database_manager_singleton',
    why: 'DatabaseManager() yerine enjekte edilen bağımlılık kullanılmalı (Faz 5).',
    count: () => countMatches(dartLib, /DatabaseManager\(\)/g),
  },
  {
    id: 'server_pgpool_in_controllers',
    why: 'Controller/route içinde pgPool kullanılmamalı; repository katmanı (Faz 5).',
    count: () => countMatches(serverSrc, /pgPool\./g, (p) => /\.(controller|routes)\.ts$/.test(p)),
  },
  {
    id: 'empty_catch_dart',
    why: 'Boş catch hatayı gizler; ele alın veya telemetriye yazıp fırlatın (Faz 6).',
    count: () => countMatches(dartLib, /catch\s*\([^)]*\)\s*\{\s*\}/g),
  },
  {
    id: 'empty_catch_ts',
    why: 'Boş catch hatayı gizler (Faz 6).',
    count: () => countMatches(serverSrc, /catch\s*(\([^)]*\))?\s*\{\s*\}/g),
  },
  {
    id: 'datetime_now',
    why: 'Doğrudan DateTime.now() yerine enjekte edilebilir Clock (Faz 6).',
    count: () => countMatches(dartLib, /DateTime\.now\(\)/g, (p) => !p.endsWith('db_migrations.dart')),
  },
];

function oversizedFiles() {
  return [...dartLib, ...serverSrc]
    .filter((f) => read(f).split('\n').length > MAX_FILE_LINES)
    .map(rel)
    .sort();
}

function measure() {
  const metrics = {};
  for (const r of RULES) metrics[r.id] = r.count();
  return { metrics, oversized_files: oversizedFiles() };
}

const update = process.argv.includes('--update');
const current = measure();

if (update || !existsSync(BASELINE_PATH)) {
  const payload = {
    _comment: 'node tool/architecture_guard.mjs tarafından üretilir. Sayılar yalnızca azalabilir.',
    max_file_lines: MAX_FILE_LINES,
    ...current,
  };
  writeFileSync(BASELINE_PATH, JSON.stringify(payload, null, 2) + '\n');
  console.log(`Baseline yazıldı: ${rel(BASELINE_PATH)}`);
  for (const r of RULES) console.log(`  ${r.id.padEnd(32)} ${current.metrics[r.id]}`);
  console.log(`  ${'oversized_files'.padEnd(32)} ${current.oversized_files.length}`);
  process.exit(0);
}

const baseline = JSON.parse(read(BASELINE_PATH));
let failed = false;
const improved = [];

console.log('Serenut OS — Architecture Guard');
console.log('metric'.padEnd(34) + 'baseline'.padStart(9) + 'current'.padStart(9));
for (const r of RULES) {
  const base = baseline.metrics?.[r.id];
  const cur = current.metrics[r.id];
  let mark = '  ';
  if (base === undefined) mark = '? ';
  else if (cur > base) { mark = '✗ '; failed = true; }
  else if (cur < base) { mark = '↓ '; improved.push(r.id); }
  console.log(`${mark}${r.id.padEnd(32)}${String(base ?? '-').padStart(9)}${String(cur).padStart(9)}`);
  if (base !== undefined && cur > base) console.log(`    → ${r.why}`);
}

const known = new Set(baseline.oversized_files ?? []);
const newOversized = current.oversized_files.filter((f) => !known.has(f));
if (newOversized.length) {
  failed = true;
  console.log(`✗ ${MAX_FILE_LINES} satırı aşan YENİ dosya(lar):`);
  for (const f of newOversized) console.log(`    ${f}`);
}

if (improved.length) {
  console.log(`\nİyileşme: ${improved.join(', ')}. Kilitlemek için: node tool/architecture_guard.mjs --update`);
}
if (failed) {
  console.error('\n❌ Architecture Guard: mimari borç arttı. Yukarıdaki kurallara bakın.');
  process.exit(1);
}
console.log('\n✅ Architecture Guard: borç artmadı.');
