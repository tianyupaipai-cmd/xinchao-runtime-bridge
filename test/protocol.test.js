import test from 'node:test';
import assert from 'node:assert/strict';
import {
  parseRuntimeEnvelope,
  parseStreamEvent,
  RUNTIME_PROTOCOL,
  STREAM_PROTOCOL,
} from '../src/protocol.js';

test('parses delivery notifications and runtime envelopes', () => {
  const notice = parseStreamEvent({
    event: 'delivery',
    data: JSON.stringify({ protocol: STREAM_PROTOCOL, deliveryId: 'delivery-001' }),
  });
  assert.deepEqual(notice, { kind: 'delivery', deliveryId: 'delivery-001' });

  const envelope = parseRuntimeEnvelope({
    protocol: RUNTIME_PROTOCOL,
    deliveryId: 'delivery-001',
    reason: 'scheduled_interaction',
    message: '她留下一次拥抱。',
  }, 'delivery-001');
  assert.equal(envelope.message, '她留下一次拥抱。');
});

test('rejects mismatched delivery IDs and oversized messages', () => {
  assert.throws(() => parseRuntimeEnvelope({
    protocol: RUNTIME_PROTOCOL,
    deliveryId: 'delivery-001',
    reason: 'scheduled_interaction',
    message: 'hello',
  }, 'delivery-002'), /mismatch/);

  assert.throws(() => parseRuntimeEnvelope({
    protocol: RUNTIME_PROTOCOL,
    deliveryId: 'delivery-001',
    reason: 'scheduled_interaction',
    message: 'a'.repeat(4097),
  }), /message/);
});

test('rejects autonomous AI content because the bridge is user-interaction only', () => {
  assert.throws(() => parseRuntimeEnvelope({
    protocol: 'xinchao-runtime-wake/1',
    deliveryId: 'delivery-123',
    reason: 'dream_residue',
    message: 'This must remain in Xinchao until the user chooses to respond.',
  }), /user-originated interactions only/);
});

test('self_signal is rejected by default and accepted only when opted in', () => {
  const envelope = {
    protocol: RUNTIME_PROTOCOL,
    deliveryId: 'delivery-333',
    reason: 'self_signal',
    message: '刚才心里那股劲冲到顶了，想找她。',
  };
  assert.throws(() => parseRuntimeEnvelope(envelope), /XINCHAO_BRIDGE_ACCEPT_SELF_SIGNALS/);
  assert.throws(() => parseRuntimeEnvelope(envelope, null, { acceptSelfSignals: false }), /self_signal/);
  const parsed = parseRuntimeEnvelope(envelope, 'delivery-333', { acceptSelfSignals: true });
  assert.equal(parsed.reason, 'self_signal');
  // 开关不放行别的自主内容
  assert.throws(() => parseRuntimeEnvelope({ ...envelope, reason: 'dream_residue' }, null, { acceptSelfSignals: true }), /user-originated interactions only/);
});
