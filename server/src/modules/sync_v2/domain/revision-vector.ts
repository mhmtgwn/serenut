export interface DomainRevisionVector {
  tenant_id: string;
  vectors: Record<string, number>;
  updated_at?: number;
}

export class RevisionVectorDomain {
  public static readonly DEFAULT_DOMAINS = ['sales', 'stock', 'customer', 'invoice', 'settings'];

  public static initializeDefaultVector(tenant_id: string): DomainRevisionVector {
    const vectors: Record<string, number> = {};
    for (const domain of this.DEFAULT_DOMAINS) {
      vectors[domain] = 0;
    }
    return {
      tenant_id,
      vectors,
      updated_at: Date.now(),
    };
  }

  /**
   * Compares client vector with head (server) vector and identifies domains that require delta synchronization.
   */
  public static computeRequiredDeltaDomains(
    clientVectors: Record<string, number>,
    headVectors: Record<string, number>
  ): { domain: string; clientRev: number; headRev: number }[] {
    const laggingDomains: { domain: string; clientRev: number; headRev: number }[] = [];

    for (const [domain, headRev] of Object.entries(headVectors)) {
      const clientRev = clientVectors[domain] ?? 0;
      if (clientRev < headRev) {
        laggingDomains.push({ domain, clientRev, headRev });
      }
    }

    return laggingDomains;
  }

  /**
   * Increments a specific domain revision and returns the updated vector map.
   */
  public static incrementDomainRevision(
    currentVectors: Record<string, number>,
    domain: string,
    newRev: number
  ): Record<string, number> {
    return {
      ...currentVectors,
      [domain]: newRev,
    };
  }
}
