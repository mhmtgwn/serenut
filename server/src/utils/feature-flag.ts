import { pgPool } from '../config/database';
import { logger } from '../config/logger';

export class FeatureFlagManager {
  // Local defaults dictionary overrides for specific companies
  private static defaultFlags: Record<string, string[]> = {
    'serenut_cloud': ['websocket', 'analytics', 'billing', 'invoices', 'new-sync-engine'],
    'comp-A': ['websocket', 'billing'],
    'comp-B': ['websocket', 'analytics'],
    '*': ['websocket'] // default enabled features for all tenants
  };

  /**
   * Checks if a specific feature is enabled for a given tenant company.
   * Leverages static overrides, plans database checking, and wildcards.
   */
  public static async isFeatureEnabled(companyId: string, featureKey: string): Promise<boolean> {
    // 1. Check local configuration overrides
    if (this.defaultFlags[companyId] && this.defaultFlags[companyId].includes(featureKey)) {
      return true;
    }

    // 2. Query company package/features from PostgreSQL
    try {
      const client = await pgPool.connect();
      try {
        await client.query("SET LOCAL app.bypass_rls = 'true'");
        // Check if there is an active subscription plan that unlocks specific features
        const res = await client.query(`
          SELECT p.id, s.status,
                 COALESCE(p.features,'{}'::jsonb)||COALESCE(o.feature_overrides,'{}'::jsonb) AS features
          FROM subscriptions s
          JOIN plans p ON s.plan_id = p.id
          LEFT JOIN subscription_overrides o ON o.company_id=s.company_id AND o.base_plan_id=s.plan_id
            AND o.is_active=TRUE AND CURRENT_TIMESTAMP BETWEEN o.valid_from AND o.valid_until
          WHERE s.company_id = $1 AND s.status IN ('active', 'grace_period')
        `, [companyId]);
        
        if (res.rows.length > 0) {
          const planId = res.rows[0].id;
          const features = res.rows[0].features || {};
          if (features[featureKey] === true || features[featureKey] === 1 ||
              (Array.isArray(features.enabled) && features.enabled.includes(featureKey))) return true;
          // Plan tiers can unlock feature flags logically
          if (planId === 'plan-pro' || planId === 'plan-proplus') {
            return true; // Pro plans have all features unlocked
          }
        }
      } catch (err: any) {
        logger.error(`Error querying database for feature flags: ${err.message}`);
      } finally {
        client.release();
      }
    } catch (_) {}

    // 3. Check wildcard defaults
    if (this.defaultFlags['*'] && this.defaultFlags['*'].includes(featureKey)) {
      return true;
    }

    return false;
  }
}
