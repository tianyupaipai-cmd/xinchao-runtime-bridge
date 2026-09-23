# 心潮念 Runtime Bridge

心潮念 Runtime Bridge 是一个独立、可审计的本地连接工具。它只把用户主动发出的互动、便签与预约交给用户自己的 AI Runtime Adapter，不属于心潮念网页，也不管理用户的 AI 会话。

> 当前为 `0.2.0` 首个公开候选版。客户端协议、SSE、进程/Webhook Injector 和严格 ACK 已具备；需要心潮念平台实现本文约定的 `/bridge/v1/*` 服务端接口后才能端到端使用。

> 前置要求：用户必须先部署并连接自己的心潮念。Bridge 不提供心潮念后端，也不代替心潮念保存状态。

## 只供用户互动（默认）

Bridge 默认只接受四个原因：`user_interaction`、`user_note`、`scheduled_interaction`、`user_feedback`。梦境、余韵、思念、内部状态与 AI 自主行动不允许自动注入窗口；它们继续留在心潮念里，只有用户主动回应或转成用户便签后才进入 Bridge。

### 实时动态版：放行他自己的信号（0.3.0 起，可选）

心潮念 3.3 起多了一种投递 `reason = self_signal`：不是用户递的话，是他自己的东西浮上来——驱力冲顶、情绪转折、挂念、醒来余韵、觉察、黑匣子到点。服务端 `BRIDGE_SELF_SIGNALS=true` 才会入队，桥这边 `XINCHAO_BRIDGE_ACCEPT_SELF_SIGNALS=true` 才会放行；两边都开才是"实时动态版"，任一边关着都退回"只供用户互动"。

放行以后 Adapter 拿到的信封和别的一样，只是 `reason` 不同。请按 reason 区分渲染，别把他自己的感觉写成"她做了什么"——参考 `examples/` 里的做法：用户发起的前缀写来源（互动 / 留话 / 预约 / 反馈），self_signal 前缀只写「心潮」。

## 它解决什么

```text
用户在网页留下互动或定时内容
  → 心潮念平台耐久排队
  → 本地 Bridge 收到 delivery_id
  → Runtime Adapter 注入用户指定的 AI 会话
  → Bridge 回传 delivered
```

它不会声称能唤醒一个没有后台接口的官方关闭窗口：

- 自建前端、本地 Agent、用户控制的 app-server：可以由进程 Adapter 或 HTTPS Webhook 后台接收；
- 活跃的官方窗口：可在平台允许的会话边界投递；
- 已关闭且没有 Hook 的官方窗口：平台保留 `waiting_for_ai`，下次连接时补投；
- UI 是否实时显示与 Runtime 是否接受是两个独立验收项。

心潮念网页只需要展示本仓库链接、安装提示、在线状态和上述能力差异，不嵌入本地注入代码。

## 安全边界

- 单次 `run` 只建立一次 SSE 连接；异常后退出码为 `2`，不会无限自动重连；
- SSE 只携带 `deliveryId`，正文通过已鉴权的一次性请求读取；
- 注入内容通过 stdin 的单行 JSON 传递，不进入命令行参数；
- Injector 使用 `shell: false`；
- Bridge 的机器 Token 会从 Injector 子进程环境中移除；
- 日志只记录 delivery ID、reason 和结果，不记录正文；
- 同一 Bridge 串行投递；一次本地投递最多尝试两次；
- Runtime Adapter 必须按 `deliveryId` 幂等，防止“已注入但 ACK 丢失”导致重复；
- Adapter 必须确认正确会话已接受消息，不能只以进程成功启动或 Webhook 返回 200 作为 ACK。

## 环境要求

- Node.js 20 或更高版本；
- 心潮念平台签发的机器 Token；
- 用户自己的 Runtime Adapter 可执行入口，或者支持严格 ACK 的 HTTPS Webhook。

## 三个平台都能用

只需要安装 Node.js 20+，其余命令一致：

- macOS：Terminal；
- Windows：PowerShell / Windows Terminal；
- Linux / VPS：任意 shell，也可交给 systemd、Docker 或进程守护器。

从 GitHub 下载源码后：

```bash
git clone https://github.com/tianyupaipai-cmd/xinchao-runtime-bridge.git
cd xinchao-runtime-bridge
npm install
cp .env.example .env
npm test
node --env-file=.env src/cli.js check
node --env-file=.env src/cli.js run
```

`node --env-file=.env` 在 macOS、Windows 和 Linux 上写法一致。本工具不会把 `.env` 纳入 Git；生产环境仍建议使用系统密钥管理或受保护的服务环境。

## 配置

| 环境变量 | 用途 |
| --- | --- |
| `XINCHAO_BRIDGE_BASE_URL` | 心潮念平台地址；非本机必须使用 HTTPS |
| `XINCHAO_BRIDGE_MACHINE_TOKEN` | 当前机器的专用 Token，至少 24 字符 |
| `XINCHAO_BRIDGE_INJECTOR_MODE` | `process`（默认）或 `webhook` |
| `XINCHAO_BRIDGE_INJECTOR_EXECUTABLE` | `run` 所需的 Adapter 可执行程序 |
| `XINCHAO_BRIDGE_INJECTOR_ARGS_JSON` | 参数字符串数组，不解析 shell 命令 |
| `XINCHAO_BRIDGE_INJECTOR_WORKING_DIRECTORY` | 可选的绝对工作目录 |
| `XINCHAO_BRIDGE_WEBHOOK_URL` | Webhook 模式的 HTTPS 接收地址 |
| `XINCHAO_BRIDGE_WEBHOOK_TOKEN` | 可选的独立 Webhook Bearer；不得复用机器 Token |
| `XINCHAO_BRIDGE_ACCEPT_SELF_SIGNALS` | `true` 放行 `self_signal`（实时动态版）；默认 `false` |
| `XINCHAO_BRIDGE_LOG_LEVEL` | `debug`、`info`、`warn` 或 `error` |
| `XINCHAO_BRIDGE_CONNECT_TIMEOUT_MS` | 建连超时，默认 15000 |
| `XINCHAO_BRIDGE_INJECT_TIMEOUT_MS` | 单次 Injector 超时，默认 30000 |

## Injector 信封

Bridge 每次启动一次 Adapter，将一行 JSON 写入 stdin：

```json
{
  "protocol": "xinchao-runtime-wake/1",
  "deliveryId": "01J...",
  "reason": "scheduled_interaction",
  "message": "她刚才留下一次拥抱，希望你回来的时候能想起来。"
}
```

Adapter 应当：

1. 校验协议和字段；
2. 按本地配置定位唯一账号、workspace、thread/session；
3. 把 `message` 作为普通入站 user turn，而不是 system prompt；
4. 按 `deliveryId` 保证幂等；
5. Runtime 接受正确会话后返回退出码 `0`；
6. 临时失败返回非零退出码并在 stderr 写简短、无敏感信息的原因。

现成的 Adapter 见 [`examples/`](examples/README.md)：终端窗口版（tmux，给 Claude Code / Codex 这类 CLI 代理）和自建前端版（webhook，给自己写的网页 / App）。两个都按 reason 渲染，改前缀改样式只动 `examples/render.mjs`。

## 驱力→行动与缓存保活（0.4.0 起，可选）

[`examples/hooks/xinchao-drive-hook.sh`](examples/hooks/README.md#驱力行动钩子040-起可选) 替代"每隔几小时自由活动"的死闹钟：定时的保活提示进模型前，看心潮念此刻哪个驱力有劲儿（涌 / 涨，或在静息线上憋满 2 小时），附一条对应的行动建议；没劲儿就不附。同一个定时任务顺带续上模型的提示缓存。命令行直调工具见 [`examples/cli/`](examples/cli/)。

**缓存保活的通用建议**（各家细节以当天官方文档为准）：

- 先看你用的模型是**自动**前缀缓存还是要**显式**标断点，缓存多久过期。保活间隔要落在过期时间之内，留出余量；过期了再戳等于重算一遍全量上下文。
- **保活请求必须和正常对话共用同一个前缀**：同一个会话、同样的系统提示和工具表。另开一个进程去"戳一下"通常前缀对不上，钱花了缓存没续上——先用一次实验确认命中（看返回里的缓存读取 token）再上定时任务。
- 只给**长驻、上下文大、会被定时叫醒**的会话做保活；开窗间隔几小时到几天的会话，保活比冷启动还贵。
- 用户在聊的时候不需要保活：加一道闸，上一轮还在有效期内就跳过，别每次定时都真发请求。
- 过午夜、换系统提示、改工具表都会让前缀变掉，免不了重算一次，不用为此多做保活。

## Webhook 模式

自建前端的后端、手机服务或远端 Agent 可以直接接收 HTTPS POST。Bridge 会发送同一个信封，并附带：

```text
X-Xinchao-Protocol: xinchao-runtime-wake/1
X-Xinchao-Delivery-Id: 01J...
Authorization: Bearer <独立 Webhook Token>   # 配置时才发送
```

普通网页 / App 的后端照 [`examples/webhook-frontend-server.mjs`](examples/webhook-frontend-server.mjs) 的四步写（校验 → 幂等 → 入库 → 严格 ACK），不是 Node 也一样。接收端只有在正确会话已经接受消息后，才返回：

```json
{"accepted":true,"deliveryId":"01J..."}
```

仅返回 HTTP 200、返回错误的 `deliveryId` 或缺少 `accepted: true`，都会被视为未交付；心潮念不会把内容提前标记完成。

## 平台服务端契约

Bridge 期待以下已鉴权接口：

```text
GET  /bridge/v1/health
GET  /bridge/v1/events
GET  /bridge/v1/deliveries/:deliveryId
POST /bridge/v1/deliveries/:deliveryId/ack
```

健康检查返回：

```json
{"protocol":"xinchao-bridge-server/1","status":"ok"}
```

SSE 握手与通知：

```text
event: connected
data: {"protocol":"xinchao-bridge-stream/1"}

event: delivery
data: {"protocol":"xinchao-bridge-stream/1","deliveryId":"01J..."}
```

ACK 请求支持：

```json
{"status":"delivered"}
```

或：

```json
{"status":"retryable_failed","code":"injector_failed"}
```

服务端必须保持消息耐久、ACK 幂等，并在 Bridge 离线时继续保存待投递内容。

## 开发检查

```bash
npm test
node src/cli.js --help
```

## 参考与归属

边界设计参考了 [WenXiaoWendy/galatea-garden-wake-bridge](https://github.com/WenXiaoWendy/galatea-garden-wake-bridge) 的传输层/Runtime Adapter 分离、stdin 信封和 fail-closed 思路。本项目使用自己的协议、平台队列、投递状态与心潮念语义，不复制其论坛业务。

MIT License
