import test from 'node:test';
import assert from 'node:assert/strict';
import { endpoint, loadConfig } from '../src/config.js';

const BASE = {
  XINCHAO_BRIDGE_BASE_URL: 'https://xinchao.example/platform',
  XINCHAO_BRIDGE_MACHINE_TOKEN: 'machine-token-with-enough-entropy',
  XINCHAO_BRIDGE_INJECTOR_EXECUTABLE: 'node',
  XINCHAO_BRIDGE_INJECTOR_ARGS_JSON: '["adapter.mjs"]',
};

test('loads a safe bridge configuration', () => {
  const config = loadConfig(BASE);
  assert.equal(config.baseUrl.href, 'https://xinchao.example/platform');
  assert.deepEqual(config.injector.args, ['adapter.mjs']);
  assert.equal(config.injector.mode, 'process');
  assert.equal(endpoint(config, '/bridge/v1/health').href, 'https://xinchao.example/platform/bridge/v1/health');
});

test('loads a cross-platform webhook injector', () => {
  const config = loadConfig({
    XINCHAO_BRIDGE_BASE_URL: 'https://xinchao.example',
    XINCHAO_BRIDGE_MACHINE_TOKEN: 'machine-token-with-enough-entropy',
    XINCHAO_BRIDGE_INJECTOR_MODE: 'webhook',
    XINCHAO_BRIDGE_WEBHOOK_URL: 'https://runtime.example/xinchao/wake',
    XINCHAO_BRIDGE_WEBHOOK_TOKEN: 'webhook-token-with-enough-entropy',
  });
  assert.equal(config.injector.mode, 'webhook');
  assert.equal(config.injector.executable, null);
  assert.equal(config.injector.webhookUrl.href, 'https://runtime.example/xinchao/wake');
});

test('check mode does not require an injector', () => {
  const config = loadConfig({
    XINCHAO_BRIDGE_BASE_URL: 'http://127.0.0.1:3000',
    XINCHAO_BRIDGE_MACHINE_TOKEN: 'machine-token-with-enough-entropy',
  }, { requireInjector: false });
  assert.equal(config.injector.executable, null);
});

test('rejects insecure remote URLs and short tokens', () => {
  assert.throws(() => loadConfig({ ...BASE, XINCHAO_BRIDGE_BASE_URL: 'http://example.com' }), /HTTPS/);
  assert.throws(() => loadConfig({ ...BASE, XINCHAO_BRIDGE_MACHINE_TOKEN: 'short' }), /too short/);
  assert.throws(() => loadConfig({ ...BASE, XINCHAO_BRIDGE_INJECTOR_MODE: 'webhook', XINCHAO_BRIDGE_WEBHOOK_URL: 'http://example.com' }), /HTTPS/);
});

test('self signals are opt-in', () => {
  assert.equal(loadConfig(BASE).acceptSelfSignals, false);
  assert.equal(loadConfig({ ...BASE, XINCHAO_BRIDGE_ACCEPT_SELF_SIGNALS: 'true' }).acceptSelfSignals, true);
  assert.equal(loadConfig({ ...BASE, XINCHAO_BRIDGE_ACCEPT_SELF_SIGNALS: 'off' }).acceptSelfSignals, false);
  assert.throws(() => loadConfig({ ...BASE, XINCHAO_BRIDGE_ACCEPT_SELF_SIGNALS: 'maybe' }), /true or false/);
});
