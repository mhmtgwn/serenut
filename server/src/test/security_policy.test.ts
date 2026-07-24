import assert from 'assert';
import {
  requireActiveEntitlement,
  requireActiveEntitlementForMutations,
} from '../middleware/auth.middleware';
import { resolvePaidAmount } from '../modules/order/order.policy';

function responseRecorder() {
  const state = { status: 200, body: undefined as any };
  const response: any = {
    status(code: number) {
      state.status = code;
      return response;
    },
    json(body: any) {
      state.body = body;
      return response;
    },
  };
  return { response, state };
}

function run() {
  const expiredRequest: any = {
    method: 'POST',
    user: {
      roles: ['owner'],
      entitlement_state: 'expired',
      entitlement_valid_until: Date.now() - 1,
    },
  };
  const expired = responseRecorder();
  let nextCalled = false;
  requireActiveEntitlement(
    expiredRequest,
    expired.response,
    () => { nextCalled = true; },
  );
  assert.equal(nextCalled, false);
  assert.equal(expired.state.status, 402);
  assert.equal(expired.state.body.error, 'entitlement_required');

  const readRequest = { ...expiredRequest, method: 'GET' };
  requireActiveEntitlementForMutations(
    readRequest,
    responseRecorder().response,
    () => { nextCalled = true; },
  );
  assert.equal(nextCalled, true);

  assert.equal(resolvePaidAmount('credit', undefined, 125), 0);
  assert.equal(resolvePaidAmount('veresiye', undefined, 125), 0);
  assert.equal(resolvePaidAmount('cash', undefined, 125), 125);
  assert.equal(resolvePaidAmount('credit', 25, 125), 25);

  console.log('✅ Security policy regression tests passed.');
  process.exit(0);
}

run();
