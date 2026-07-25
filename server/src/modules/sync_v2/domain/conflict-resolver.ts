export interface MutationPayload {
  client_mutation_id: string;
  device_id: string;
  tenant_id: string;
  domain: string;
  entity_type: string;
  entity_id: string;
  op_type: 'INSERT' | 'UPDATE' | 'DELETE' | 'RESTORE';
  payload: Record<string, any>;
  client_timestamp: number;
  base_revision: number;
}

export interface ReconciliationResult {
  hasConflict: boolean;
  resolvedPayload: Record<string, any>;
  strategyUsed: 'CLEAN_APPLY' | 'FIELD_LEVEL_MERGE' | 'SERVER_WIN' | 'TOMBSTONE_OVERRIDE';
}

export class ConflictResolverDomain {
  /**
   * Deterministically reconciles incoming client mutation with existing server entity state.
   */
  public static reconcile(
    incomingMutation: MutationPayload,
    existingServerPayload: Record<string, any> | null,
    currentServerRev: number
  ): ReconciliationResult {
    // 1. Clean Insert
    if (!existingServerPayload) {
      return {
        hasConflict: false,
        resolvedPayload: incomingMutation.payload,
        strategyUsed: 'CLEAN_APPLY',
      };
    }

    // 2. Base Revision Alignment (No Conflict)
    if (incomingMutation.base_revision >= currentServerRev) {
      return {
        hasConflict: false,
        resolvedPayload: {
          ...existingServerPayload,
          ...incomingMutation.payload,
        },
        strategyUsed: 'CLEAN_APPLY',
      };
    }

    // 3. Tombstone Override Check
    if (existingServerPayload.is_deleted === true && incomingMutation.op_type !== 'RESTORE') {
      return {
        hasConflict: true,
        resolvedPayload: existingServerPayload,
        strategyUsed: 'TOMBSTONE_OVERRIDE',
      };
    }

    // 4. Field-Level Merge Resolution
    const merged: Record<string, any> = { ...existingServerPayload };
    let hasFieldConflict = false;

    for (const [key, clientValue] of Object.entries(incomingMutation.payload)) {
      const serverValue = existingServerPayload[key];
      if (serverValue !== undefined && serverValue !== clientValue) {
        hasFieldConflict = true;
        // Deterministic Field Resolution: Apply non-null client fields or server timestamp tie-break
        merged[key] = clientValue !== null ? clientValue : serverValue;
      } else {
        merged[key] = clientValue;
      }
    }

    return {
      hasConflict: hasFieldConflict,
      resolvedPayload: merged,
      strategyUsed: hasFieldConflict ? 'FIELD_LEVEL_MERGE' : 'CLEAN_APPLY',
    };
  }
}
