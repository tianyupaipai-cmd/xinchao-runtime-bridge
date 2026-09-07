import { endpoint } from './config.js';
import { parseRuntimeEnvelope } from './protocol.js';

function authHeaders(config, extra = {}) {
  return {
    Authorization: `Bearer ${config.machineToken}`,
    ...extra,
  };
}

async function fetchConnected(url, init, timeoutMs, signal, fetchImpl) {
  const controller = new AbortController();
  const onAbort = () => controller.abort(signal.reason);
  signal?.addEventListener('abort', onAbort, { once: true });
  const timer = setTimeout(() => controller.abort(new Error('connection timed out')), timeoutMs);
  try {
    return await fetchImpl(url, { ...init, signal: controller.signal });
  } finally {
    clearTimeout(timer);
  }
}

async function readJson(response, label) {
  let value;
  try {
    value = await response.json();
  } catch {
    throw new Error(`${label} returned invalid JSON`);
  }
  return value;
}

export class BridgeClient {
  constructor(config, { fetchImpl = globalThis.fetch } = {}) {
    if (typeof fetchImpl !== 'function') throw new Error('fetch is unavailable');
    this.config = config;
    this.fetchImpl = fetchImpl;
  }

  async check(signal) {
    const response = await fetchConnected(
      endpoint(this.config, '/bridge/v1/health'),
      { headers: authHeaders(this.config, { Accept: 'application/json' }) },
      this.config.timeouts.connectMs,
      signal,
      this.fetchImpl,
    );
    if (!response.ok) throw new Error(`bridge health rejected with HTTP ${response.status}`);
    const payload = await readJson(response, 'bridge health');
    if (payload?.protocol !== 'xinchao-bridge-server/1' || payload?.status !== 'ok') {
      throw new Error('bridge health returned an incompatible protocol');
    }
    return payload;
  }

  async openStream(signal) {
    const response = await fetchConnected(
      endpoint(this.config, '/bridge/v1/events'),
      { headers: authHeaders(this.config, { Accept: 'text/event-stream' }) },
      this.config.timeouts.connectMs,
      signal,
      this.fetchImpl,
    );
    if (!response.ok) throw new Error(`bridge stream rejected with HTTP ${response.status}`);
    const contentType = response.headers.get('content-type') ?? '';
    if (!contentType.toLowerCase().startsWith('text/event-stream')) {
      throw new Error('bridge stream did not return text/event-stream');
    }
    return response.body;
  }

  async fetchDelivery(deliveryId, signal) {
    const response = await this.fetchImpl(endpoint(
      this.config,
      `/bridge/v1/deliveries/${encodeURIComponent(deliveryId)}`,
    ), {
      headers: authHeaders(this.config, { Accept: 'application/json' }),
      signal,
    });
    if (!response.ok) throw new Error(`delivery fetch rejected with HTTP ${response.status}`);
    return parseRuntimeEnvelope(await readJson(response, 'delivery fetch'), deliveryId, {
      acceptSelfSignals: this.config.acceptSelfSignals === true,
    });
  }

  async acknowledge(deliveryId, signal) {
    const response = await this.fetchImpl(endpoint(
      this.config,
      `/bridge/v1/deliveries/${encodeURIComponent(deliveryId)}/ack`,
    ), {
      method: 'POST',
      headers: authHeaders(this.config, { 'Content-Type': 'application/json' }),
      body: JSON.stringify({ status: 'delivered' }),
      signal,
    });
    if (!response.ok) throw new Error(`delivery ACK rejected with HTTP ${response.status}`);
  }

  async reportFailure(deliveryId, code, signal) {
    const response = await this.fetchImpl(endpoint(
      this.config,
      `/bridge/v1/deliveries/${encodeURIComponent(deliveryId)}/ack`,
    ), {
      method: 'POST',
      headers: authHeaders(this.config, { 'Content-Type': 'application/json' }),
      body: JSON.stringify({ status: 'retryable_failed', code: String(code).slice(0, 80) }),
      signal,
    });
    if (!response.ok) throw new Error(`delivery failure report rejected with HTTP ${response.status}`);
  }
}
