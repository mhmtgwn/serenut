import fs from 'fs';

export const MAINTENANCE_TASKS = [
  'docker_build_cache',
  'dangling_images',
  'stopped_containers',
  'old_releases',
  'temporary_releases',
  'archived_logs',
] as const;

export type MaintenanceTask = typeof MAINTENANCE_TASKS[number];

const taskSet = new Set<string>(MAINTENANCE_TASKS);

function readAgentToken(): string {
  const tokenFile = process.env.MAINTENANCE_AGENT_TOKEN_FILE
    || '/run/secrets/maintenance_agent_token';
  return fs.readFileSync(tokenFile, 'utf8').trim();
}

export function validateMaintenanceTasks(value: unknown): MaintenanceTask[] {
  if (!Array.isArray(value)) return [];
  return [...new Set(value.map(String))]
    .filter((task): task is MaintenanceTask => taskSet.has(task));
}

export async function callMaintenanceAgent(
  path: '/preview' | '/cleanup',
  options: { method?: 'GET' | 'POST'; body?: Record<string, unknown> } = {},
): Promise<any> {
  const baseUrl = process.env.MAINTENANCE_AGENT_URL || 'http://maintenance-agent:3070';
  let token: string;
  try {
    token = readAgentToken();
  } catch {
    throw new Error('maintenance_agent_token_unavailable');
  }
  if (!token) throw new Error('maintenance_agent_token_unavailable');

  const response = await fetch(`${baseUrl}${path}`, {
    method: options.method || 'GET',
    headers: {
      authorization: `Bearer ${token}`,
      ...(options.body ? { 'content-type': 'application/json' } : {}),
    },
    body: options.body ? JSON.stringify(options.body) : undefined,
    signal: AbortSignal.timeout(path === '/cleanup' ? 120_000 : 15_000),
  });
  const payload: any = await response.json().catch(() => ({}));
  if (!response.ok) {
    const error = new Error(payload?.error || `maintenance_agent_http_${response.status}`);
    (error as any).status = response.status;
    throw error;
  }
  return payload;
}
