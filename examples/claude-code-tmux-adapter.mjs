#!/usr/bin/env node
// Runtime Adapter 示例 · 终端窗口版（Claude Code / Codex / 任何跑在 tmux 里的 CLI 代理）
//
// 桥以 process 模式启动本文件，把一行 JSON 信封写进 stdin；本文件把它作为一条普通的用户输入
// 送进指定的 tmux 窗口，成功退出码 0，失败非零并在 stderr 留一句短原因（不含正文）。
//
// 环境变量：
//   XINCHAO_ADAPTER_TMUX_TARGET   tmux 目标，如 "claude" 或 "main:1"（必填）
//   XINCHAO_ADAPTER_CABIN_NAME    用户发起消息的前缀名，默认 小屋桥
//   XINCHAO_ADAPTER_STATE_DIR     幂等记录目录，默认 ~/.xinchao-adapter
//
// .env 里这样配：
//   XINCHAO_BRIDGE_INJECTOR_MODE=process
//   XINCHAO_BRIDGE_INJECTOR_EXECUTABLE=node
//   XINCHAO_BRIDGE_INJECTOR_ARGS_JSON=["/abs/path/examples/claude-code-tmux-adapter.mjs"]
//   XINCHAO_BRIDGE_ACCEPT_SELF_SIGNALS=true      # 实时动态版才开
import { execFileSync } from 'node:child_process';
import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { homedir } from 'node:os';
import { join } from 'node:path';
import { renderText } from './render.mjs';

const TARGET = String(process.env.XINCHAO_ADAPTER_TMUX_TARGET ?? '').trim();
const CABIN = String(process.env.XINCHAO_ADAPTER_CABIN_NAME ?? '小屋桥').trim() || '小屋桥';
const STATE_DIR = String(process.env.XINCHAO_ADAPTER_STATE_DIR ?? join(homedir(), '.xinchao-adapter')).trim();
const SEEN_FILE = join(STATE_DIR, 'delivered.json');

function fail(msg, code = 1) { process.stderr.write(`${msg}\n`); process.exit(code); }

function readEnvelope() {
  const raw = readFileSync(0, 'utf8').trim();
  let v; try { v = JSON.parse(raw); } catch { fail('envelope is not JSON'); }
  if (v?.protocol !== 'xinchao-runtime-wake/1') fail('unsupported envelope protocol');
  if (typeof v.deliveryId !== 'string' || typeof v.reason !== 'string' || typeof v.message !== 'string') fail('envelope missing fields');
  return v;
}

function seen() { try { return new Set(JSON.parse(readFileSync(SEEN_FILE, 'utf8'))); } catch { return new Set(); } }
function remember(set, id) {
  mkdirSync(STATE_DIR, { recursive: true });
  const list = [...set, id].slice(-2000);
  writeFileSync(SEEN_FILE, JSON.stringify(list));
}

function tmux(...args) { return execFileSync('tmux', args, { stdio: ['ignore', 'pipe', 'pipe'] }).toString(); }

function windowAlive(target) {
  try { tmux('has-session', '-t', target); return true; } catch { return false; }
}

function inject(target, text) {
  // 用 buffer 粘贴而不是 send-keys 逐字输入：多行、特殊字符都安全；最后回车提交
  const bufName = `xinchao-${process.pid}`;
  tmux('set-buffer', '-b', bufName, text);
  tmux('paste-buffer', '-b', bufName, '-t', target, '-d');
  tmux('send-keys', '-t', target, 'Enter');
}

const envelope = readEnvelope();
if (!TARGET) fail('XINCHAO_ADAPTER_TMUX_TARGET is required');
const done = seen();
if (done.has(envelope.deliveryId)) process.exit(0);           // 幂等：重复投递直接当成功
if (!windowAlive(TARGET)) fail('runtime_offline', 2);         // 窗口不在：非零，桥会回 retryable_failed，心潮留着下次补投
try {
  inject(TARGET, renderText(envelope, { cabinName: CABIN }));
} catch (error) {
  fail(`inject_failed: ${String(error.message ?? error).slice(0, 80)}`, 3);
}
remember(done, envelope.deliveryId);
process.exit(0);
