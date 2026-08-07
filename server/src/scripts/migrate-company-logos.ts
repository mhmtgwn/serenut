import fs from 'fs/promises';
import path from 'path';
import { pgPool } from '../config/database';
import { decodeDataImage, publicLogoUrl, storeCompanyLogo } from '../modules/tenant/company-logo.service';

async function main() {
  const apply = process.argv.includes('--apply');
  if (apply && !process.env.PUBLIC_BASE_URL) {
    throw new Error('PUBLIC_BASE_URL is required with --apply');
  }
  const result = await pgPool.query(
    `SELECT id, logo_url FROM companies
     WHERE logo_url LIKE 'data:image/%;base64,%'
     ORDER BY id`,
  );
  const rollback: Array<{ companyId: string; previous: string; next: string }> = [];
  let failed = 0;

  for (const company of result.rows) {
    const input = decodeDataImage(company.logo_url);
    if (!input) {
      failed++;
      console.error(`[skip] ${company.id}: invalid data image`);
      continue;
    }
    try {
      const stored = await storeCompanyLogo(company.id, input);
      const next = publicLogoUrl(stored.displayPath);
      rollback.push({ companyId: company.id, previous: company.logo_url, next });
      if (apply) {
        await pgPool.query(
          `UPDATE companies
           SET logo_url = $1, version = version + 1, updated_at = CURRENT_TIMESTAMP
           WHERE id = $2 AND logo_url = $3`,
          [next, company.id, company.logo_url],
        );
      }
      console.log(`[${apply ? 'migrated' : 'dry-run'}] ${company.id} -> ${next}`);
    } catch (error) {
      failed++;
      console.error(`[failed] ${company.id}:`, error);
    }
  }

  const manifestDir = path.join(process.cwd(), 'logs');
  await fs.mkdir(manifestDir, { recursive: true });
  const manifest = path.join(manifestDir, `company-logo-migration-${Date.now()}.json`);
  await fs.writeFile(manifest, JSON.stringify({ apply, failed, entries: rollback }, null, 2));
  console.log(`Completed: ${rollback.length} convertible, ${failed} failed. Manifest: ${manifest}`);
  if (!apply) console.log('No database rows changed. Re-run with --apply after reviewing the manifest.');
}

main()
  .catch((error) => {
    console.error(error);
    process.exitCode = 1;
  })
  .finally(() => pgPool.end());
