# Adapter 示例

桥只负责"从心潮念把一条投递安全地搬到你这边并 ACK"。最后一跳——把它放进你的模型正在用的那个会话——是 Adapter 的事，因为每个人的运行时都不一样。这里给两种最常见的：

| 你的运行时 | 用哪个 | 桥的模式 |
| --- | --- | --- |
| 终端里的 CLI 代理（Claude Code、Codex、任何跑在 tmux 里的） | `claude-code-tmux-adapter.mjs` | `process` |
| 自建网页 / App，聊天走你自己的后端 | `webhook-frontend-server.mjs` | `webhook` |

两个都引用 `render.mjs`，那里是"按 reason 渲染"的规则，改前缀名、改样式都在那一个文件里。

## 终端窗口版

桥每次投递启动一次 `node claude-code-tmux-adapter.mjs`，把信封写进 stdin。Adapter 把它渲染成一条普通的用户输入，粘贴进 tmux 目标窗口并回车。

- 幂等：`~/.xinchao-adapter/delivered.json` 记已投递的 `deliveryId`，重复投递直接退出 0。
- 窗口不在（tmux 没开）：退出码 2，桥会向心潮念报 `retryable_failed`，心潮念留着下次补投——不会丢。
- 日志和状态文件都不记正文。

```bash
export XINCHAO_ADAPTER_TMUX_TARGET=main:1     # tmux 里跑着你代理的那个窗口
# 桥 .env：
#   XINCHAO_BRIDGE_INJECTOR_MODE=process
#   XINCHAO_BRIDGE_INJECTOR_EXECUTABLE=node
#   XINCHAO_BRIDGE_INJECTOR_ARGS_JSON=["/abs/path/examples/claude-code-tmux-adapter.mjs"]
```

## 自建前端版（普通网页 / App）

如果你的聊天界面是自己写的网页或 App，模型调用在你自己的后端——不要去模拟"往窗口里打字"，让桥直接 POST 到你后端的一个接口。`webhook-frontend-server.mjs` 就是这个接口的最小实现，四步：

1. **校验**：Bearer 必须等于 `XINCHAO_BRIDGE_WEBHOOK_TOKEN`（和机器 Token 不同的一串）；`X-Xinchao-Protocol` 必须是 `xinchao-runtime-wake/1`；body 里的 `deliveryId` 必须和 `X-Xinchao-Delivery-Id` 一致。
2. **幂等**：同一个 `deliveryId` 只入库一次；桥重试时你已经有了，直接返回成功。
3. **入库**：把信封转成你聊天里的一条（示例用 `toChatItem` 生成 `{id, kind, label, text, at}` 存进收件箱文件）。
4. **严格 ACK**：只有真的收进了你的会话，才返回 `{"accepted": true, "deliveryId": "<同一个>"}`。桥收到这个才向心潮念 ACK；返回别的或超时，心潮念都会留着重投。

然后你的前端怎么把收件箱显示出来，随你：

- 最简单：前端每 15–30 秒 `GET /inbox?after=<最后一条 id>`，有新条就插进聊天流；
- 要即时：把 `saveInbox` 那一步换成向前端推 SSE / WebSocket；
- **怎么进模型**：把收件箱的条目当作下一轮对话的一条入站消息（普通 user turn，不是 system prompt），拼在她下一句话前面，或者在她不在时单独触发一轮——这取决于你的后端怎么调模型。示例里的 `kind` 给前端分样式：`cabin` 是她/小屋递来的，`self_signal` 是他自己的信号，两种在界面上应该长得不一样。

```bash
export XINCHAO_WEBHOOK_TOKEN=<一串至少 24 字符>
node webhook-frontend-server.mjs
# 桥 .env：
#   XINCHAO_BRIDGE_INJECTOR_MODE=webhook
#   XINCHAO_BRIDGE_WEBHOOK_URL=http://127.0.0.1:8791/xinchao/wake   # 非本机必须 https
#   XINCHAO_BRIDGE_WEBHOOK_TOKEN=<同上>
```

如果你的后端不是 Node（Python / Go / PHP 都一样），照这四步写就行，协议就这么多。

## 按 reason 渲染

| reason | 谁发起 | 示例前缀 | 备注 |
| --- | --- | --- | --- |
| `user_interaction` | 她在小屋网页点了互动 | `【小屋桥·互动】` | 末尾加"不用特意回" |
| `user_note` | 她留了话 | `【小屋桥·留话】` | 同上 |
| `scheduled_interaction` | 她预约的时间到了 | `【小屋桥·预约】` | 同上 |
| `user_feedback` | 她在网页提交的反馈 | `【小屋桥·反馈】` | 同上 |
| `self_signal` | 心潮念自己（3.3，需两端打开开关） | `【心潮】` | **不加"不用回"**——那是他自己的感觉浮上来，要不要接由他定 |

`self_signal` 的正文由心潮念按信号种类生成（驱力冲顶 / 情绪转折 / 挂念 / 醒来余韵 / 觉察 / 黑匣子到点），Adapter 不需要理解种类，原样递就好。
