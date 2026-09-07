#!/usr/bin/env node
// Runtime Adapter 示例 · 自建前端版（webhook 模式）
//
// 你的前端是一个网页/App，聊天走你自己的后端——那就不需要 tmux，让桥直接 POST 到你后端的一个接口。
// 本文件是这个接口的最小实现：校验 → 幂等 → 写入收件箱 → 严格 ACK。前端怎么拿到收件箱由你定
// （轮询 /inbox、SSE、WebSocket 都行），这里给了一个最简的 GET /inbox。
//
// 环境变量：
//   XINCHAO_WEBHOOK_PORT     监听端口，默认 8791（桥在同一台机就用 http://127.0.0.1:8791/xinchao/wake）
//   XINCHAO_WEBHOOK_TOKEN    和桥 .env 里 XINCHAO_BRIDGE_WEBHOOK_TOKEN 一致（≥24 字符，不能复用机器 Token）
//   XINCHAO_WEBHOOK_INBOX    收件箱文件，默认 ./xinchao-inbox.json
//
// 桥 .env：
//   XINCHAO_BRIDGE_INJECTOR_MODE=webhook
//   XINCHAO_BRIDGE_WEBHOOK_URL=http://127.0.0.1:8791/xinchao/wake     # 非本机必须 https
//   XINCHAO_BRIDGE_WEBHOOK_TOKEN=<同上>
//   XINCHAO_BRIDGE_ACCEPT_SELF_SIGNALS=true                            # 实时动态版才开
import { createServer } from 'node:http';
import { readFileSync, writeFileSync } from 'node:fs';
import { toChatItem } from './render.mjs';

const PORT = Number(process.env.XINCHAO_WEBHOOK_PORT ?? 8791);
const TOKEN = String(process.env.XINCHAO_WEBHOOK_TOKEN ?? '').trim();
const INBOX = String(process.env.XINCHAO_WEBHOOK_INBOX ?? './xinchao-inbox.json');
if (TOKEN.length < 24) { console.error('XINCHAO_WEBHOOK_TOKEN must be at least 24 chars'); process.exit(1); }

function loadInbox() { try { return JSON.parse(readFileSync(INBOX, 'utf8')); } catch { return []; } }
function saveInbox(items) { writeFileSync(INBOX, JSON.stringify(items.slice(-500), null, 2)); }

function json(res, code, body) {
  res.writeHead(code, { 'Content-Type': 'application/json' });
  res.end(JSON.stringify(body));
}

createServer(async (req, res) => {
  const url = new URL(req.url, 'http://x');
  if (req.method === 'GET' && url.pathname === '/inbox') {
    // 前端拉这个就够了：?after=<最后一条 id> 只取新的
    const items = loadInbox();
    const after = url.searchParams.get('after');
    const idx = after ? items.findIndex((i) => i.id === after) : -1;
    return json(res, 200, { items: items.slice(idx + 1) });
  }
  if (req.method !== 'POST' || url.pathname !== '/xinchao/wake') return json(res, 404, { error: 'not found' });

  const bearer = String(req.headers.authorization ?? '').replace(/^Bearer\s+/i, '');
  if (bearer !== TOKEN) return json(res, 401, { error: 'unauthorized' });
  if (req.headers['x-xinchao-protocol'] !== 'xinchao-runtime-wake/1') return json(res, 400, { error: 'unsupported protocol' });

  let raw = ''; for await (const chunk of req) { raw += chunk; if (raw.length > 16_384) return json(res, 413, { error: 'too large' }); }
  let envelope; try { envelope = JSON.parse(raw); } catch { return json(res, 400, { error: 'invalid json' }); }
  if (envelope?.protocol !== 'xinchao-runtime-wake/1' || envelope.deliveryId !== req.headers['x-xinchao-delivery-id']) {
    return json(res, 400, { error: 'envelope mismatch' });
  }
  if (typeof envelope.message !== 'string' || !envelope.message.trim()) return json(res, 400, { error: 'empty message' });

  const items = loadInbox();
  if (!items.some((i) => i.id === envelope.deliveryId)) {   // 幂等：同一 deliveryId 只进一次
    items.push(toChatItem(envelope));
    saveInbox(items);
  }
  // 严格 ACK：只有真的收进自己的会话后才返回 accepted + 同一个 deliveryId；桥收到这个才会向心潮念 ACK
  return json(res, 200, { accepted: true, deliveryId: envelope.deliveryId });
}).listen(PORT, '127.0.0.1', () => console.log(`xinchao webhook listening on 127.0.0.1:${PORT}`));
