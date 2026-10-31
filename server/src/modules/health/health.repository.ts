// server/src/modules/health/health.repository.ts
import { pgPool } from '../../config/database';

export class HealthRepository {
  async insertReport(companyId: string, deviceId: string, status: string, services: any): Promise<void> {
    await pgPool.query(
      `INSERT INTO client_health_reports (company_id, device_id, status, services)
       VALUES ($1, $2, $3, $4)`,
      [companyId, deviceId, status, JSON.stringify(services)]
    );
  }

  async getRecentReports(companyId?: string): Promise<any[]> {
    if (companyId) {
      const res = await pgPool.query(
        'SELECT * FROM client_health_reports WHERE company_id = $1 ORDER BY reported_at DESC LIMIT 50',
        [companyId]
      );
      return res.rows;
    }
    const res = await pgPool.query(
      'SELECT * FROM client_health_reports ORDER BY reported_at DESC LIMIT 50'
    );
    return res.rows;
  }
}

export const healthRepository = new HealthRepository();
