import { MutationPayload } from './conflict-resolver';

export class MutationValidatorDomain {
  public static readonly ALLOWED_OP_TYPES = ['INSERT', 'UPDATE', 'DELETE', 'RESTORE'];
  public static readonly ALLOWED_DOMAINS = ['sales', 'stock', 'customer', 'invoice', 'settings'];

  public static validate(mutation: Partial<MutationPayload>): { valid: boolean; error?: string } {
    if (!mutation.client_mutation_id || typeof mutation.client_mutation_id !== 'string') {
      return { valid: false, error: 'Missing or invalid client_mutation_id' };
    }

    if (!mutation.tenant_id || typeof mutation.tenant_id !== 'string') {
      return { valid: false, error: 'Missing or invalid tenant_id' };
    }

    if (!mutation.device_id || typeof mutation.device_id !== 'string') {
      return { valid: false, error: 'Missing or invalid device_id' };
    }

    if (!mutation.domain || !this.ALLOWED_DOMAINS.includes(mutation.domain)) {
      return { valid: false, error: `Invalid domain. Allowed: ${this.ALLOWED_DOMAINS.join(', ')}` };
    }

    if (!mutation.op_type || !this.ALLOWED_OP_TYPES.includes(mutation.op_type)) {
      return { valid: false, error: `Invalid op_type. Allowed: ${this.ALLOWED_OP_TYPES.join(', ')}` };
    }

    if (!mutation.entity_type || typeof mutation.entity_type !== 'string') {
      return { valid: false, error: 'Missing or invalid entity_type' };
    }

    if (!mutation.entity_id || typeof mutation.entity_id !== 'string') {
      return { valid: false, error: 'Missing or invalid entity_id' };
    }

    if (typeof mutation.base_revision !== 'number' || mutation.base_revision < 0) {
      return { valid: false, error: 'Invalid base_revision' };
    }

    if (!mutation.payload || typeof mutation.payload !== 'object') {
      return { valid: false, error: 'Missing or invalid payload' };
    }

    return { valid: true };
  }
}
