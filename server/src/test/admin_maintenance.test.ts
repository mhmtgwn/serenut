import assert from 'node:assert/strict';
import {
  MAINTENANCE_TASKS,
  validateMaintenanceTasks,
} from '../modules/admin/maintenance-agent.client';

assert.deepEqual(validateMaintenanceTasks(['docker_build_cache', 'old_releases']), [
  'docker_build_cache',
  'old_releases',
]);
assert.deepEqual(validateMaintenanceTasks(['old_releases', 'old_releases']), ['old_releases']);
assert.deepEqual(validateMaintenanceTasks(['database', '../logs', 'shell']), []);
assert.equal(MAINTENANCE_TASKS.includes('archived_logs'), true);
assert.equal(MAINTENANCE_TASKS.includes('stopped_containers'), true);

console.log('Admin maintenance validation tests passed.');
