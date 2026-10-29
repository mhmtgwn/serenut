import { describe, it } from 'node:test';
import assert from 'node:assert';
import fs from 'fs';
import path from 'path';
import crypto from 'crypto';

describe('Migration Immutability and Sequence Contract', () => {
  const dbDir = path.join(__dirname, '../../db');

  it('verifies all migration files from v1 to highest version exist sequentially with no gaps', () => {
    const files = fs
      .readdirSync(dbDir)
      .filter((f) => f === 'schema.sql' || /^schema_v\d+\.sql$/.test(f));
    const versionMap = new Map<number, string>();

    for (const file of files) {
      if (file === 'schema.sql') {
        assert.ok(!versionMap.has(1), 'Duplicate migration for version 1');
        versionMap.set(1, file);
      } else {
        const match = file.match(/^schema_v(\d+)\.sql$/);
        assert.ok(match, `Invalid migration filename format: ${file}. Must match schema_v{N}.sql`);
        const version = parseInt(match[1], 10);
        assert.ok(!versionMap.has(version), `Duplicate migration version found: ${version} (${file})`);
        versionMap.set(version, file);
      }
    }

    const versions = Array.from(versionMap.keys()).sort((a, b) => a - b);
    assert.strictEqual(versions[0], 1, 'First migration must be version 1');
    const maxVersion = versions[versions.length - 1];

    for (let i = 1; i <= maxVersion; i++) {
      assert.ok(versionMap.has(i), `Migration version gap detected: missing version ${i}`);
    }
  });

  it('verifies all migration files calculate deterministic sha256 checksums invariant to CRLF/LF', () => {
    const files = fs.readdirSync(dbDir).filter((f) => f.endsWith('.sql'));
    for (const file of files) {
      const fullPath = path.join(dbDir, file);
      const raw = fs.readFileSync(fullPath, 'utf8');
      assert.ok(raw.trim().length > 0, `Migration file ${file} cannot be empty`);

      const normalized = raw.replace(/\r\n/g, '\n');
      const hash1 = crypto.createHash('sha256').update(normalized).digest('hex');
      const hash2 = crypto.createHash('sha256').update(normalized.replace(/\n/g, '\r\n').replace(/\r\n/g, '\n')).digest('hex');
      assert.strictEqual(hash1, hash2, `Checksum must be strictly invariant for ${file}`);
    }
  });
});
