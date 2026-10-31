// server/src/modules/tenant/tenant.repository.ts
import { pgPool } from '../../config/database';

export class TenantRepository {
  async getCompanyProfile(companyId: string): Promise<any | null> {
    const res = await pgPool.query(
      `SELECT id, name, tax_number, tax_office, phone, email, address, status,
              owner_name, type, city, district, currency, logo_url,
              version, created_at, updated_at
       FROM companies WHERE id = $1`,
      [companyId]
    );
    return res.rows[0] || null;
  }

  async getCompanyVersion(companyId: string): Promise<number | null> {
    const res = await pgPool.query('SELECT version FROM companies WHERE id = $1', [companyId]);
    return res.rows.length > 0 ? res.rows[0].version : null;
  }

  async findCompanyByTaxNumberExcept(taxNumber: string, excludeCompanyId: string): Promise<{ id: string } | null> {
    const res = await pgPool.query(
      'SELECT id FROM companies WHERE tax_number = $1 AND id != $2 LIMIT 1',
      [taxNumber, excludeCompanyId]
    );
    return res.rows[0] || null;
  }

  async updateCompany(updatesSql: string, values: any[]): Promise<any | null> {
    const res = await pgPool.query(updatesSql, values);
    return res.rows[0] || null;
  }

  async getCompanyCurrentLegacy(companyId: string): Promise<any | null> {
    const res = await pgPool.query(
      `SELECT id, name, tax_number, tax_office, phone, email, address, logo_url, status,
              owner_name, type, city, district, currency, created_at
       FROM companies WHERE id = $1`,
      [companyId]
    );
    return res.rows[0] || null;
  }

  async getStores(companyId: string): Promise<any[]> {
    const res = await pgPool.query(
      `SELECT id, name, address, created_at FROM branches WHERE company_id = $1 AND is_active = TRUE
       UNION ALL
       SELECT id, name, address, created_at FROM stores WHERE company_id = $1 AND NOT EXISTS (SELECT 1 FROM branches WHERE company_id = $1)
       ORDER BY name ASC`,
      [companyId]
    );
    return res.rows;
  }

  async getDevices(companyId: string): Promise<any[]> {
    const res = await pgPool.query(
      `SELECT activation.id, activation.device_hash, activation.device_name AS name,
              activation.platform, activation.status, activation.last_seen_at,
              activation.activated_at AS created_at, runtime.current_version,
              runtime.channel, runtime.last_reported_at
       FROM device_activations activation
       LEFT JOIN device_runtime_state runtime ON runtime.device_activation_id = activation.id
       WHERE activation.company_id = $1
       ORDER BY activation.last_seen_at DESC NULLS LAST, activation.activated_at DESC`,
      [companyId]
    );
    return res.rows;
  }
}

export const tenantRepository = new TenantRepository();
