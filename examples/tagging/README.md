# 互动标注（让驱力环路闭合）

心潮念的驱力会随时间涨，靠**互动**落：陪伴落"想她"，亲密落"馋她"，和好落"紧绷"。所以每轮对话之后要有人告诉它"刚才那轮是什么"。你有两种告诉法：

| 方式 | 谁判类型 | 适合 |
| --- | --- | --- |
| 自己填 `interaction_type` | 你（或你的模型） | 后端里本来就有判断逻辑 |
| 只给 `exchange`（她一句 + 他一段） | 心潮念服务端（它自己的小模型） | **大多数人**：不用接模型、不用调 prompt |

3.3 起 `exchange` 在 MCP 工具 `xinchao_event` 和 REST `POST /v1/conversation-event` 都认。服务端 8 分钟内只判一次，其余当普通对话事件；正文判完即删，不进状态、不进审计。

## Claude Code：Stop 钩子

`claude-code-stop-hook.sh` 在他每说完一段时跑，从转录里取她的最后一句和他的回复，发 exchange。配置和「此刻」钩子共用同一个 env 文件。

```json
{
  "hooks": {
    "Stop": [
      { "hooks": [ { "type": "command", "command": "~/bin/claude-code-stop-hook.sh" } ] }
    ]
  }
}
```

以「【」开头的用户消息（桥递进来的）不标。

### 钩子这一侧的节流

心潮念那头一天只结算 24 次互动效果，一场长聊一小时就能用光，所以钩子先挡三道：

| 规则 | 默认 | 环境变量 |
| --- | --- | --- |
| 她隔了这么久再开口的第一句**永远发**（"她来了"本身就是陪伴） | 45 分钟 | `XINCHAO_TAG_ARRIVAL_MIN` |
| 两次发送至少隔 | 8 分钟 | `XINCHAO_TAG_GAP_MIN` |
| 每小时最多 | 4 次 | `XINCHAO_TAG_HOURLY_MAX` |
| 她那句话超过 45 分钟前说的不标 | 固定 | — |

状态只有一个时间戳文件（`XINCHAO_TAG_STATE`，默认 `~/.xinchao-tag-state.json`），不落正文。"同一类型 20 分钟内只算一次"这条钩子做不了（类型是服务端判的），服务端自己的 8 分钟判定节流已经覆盖。

## 自建后端：一次 POST

你的后端每轮生成完回复后，发一个请求：

```bash
curl -s -X POST "$XINCHAO_URL/v1/conversation-event" \
  -H "Authorization: Bearer $XINCHAO_TOKEN" -H "Content-Type: application/json" \
  -d '{"event_id":"tag-1725700000-1","exchange":"她说：今天好累\n他回：过来，先别说话，靠一会儿。"}'
```

返回里多一个 `classified: {type, tone}` 就是这次判了；没有就是被 8 分钟节流吃掉了（正常，照样记了对话事件）。她的话截 600 字、他的截 900 字就够，别把整段历史塞进去。

已经有自己判断的，直接填 `interaction_type`（`companionship` / `affection` / `intimacy` / `sharing` / `discovery` / `task_progress` / `reflection` / `conflict` / `loss` 等，全表见主仓库 README），可以再带 `session_state: {tone, warmth, tension}`。

## 三根线对照

| 线 | 方向 | 管什么 |
| --- | --- | --- |
| 桥（`../`） | 心潮念 → 你 | 发生了什么：她的互动 / 留话 / 预约，和他自己的信号 |
| 此刻钩子（`../hooks/`） | 你 ← 心潮念 | 现在是什么样：每次她开口前附一小块 |
| 互动标注（本目录） | 你 → 心潮念 | 刚才那轮算什么：让驱力落下来 |

三根都接上才是完整的实时动态版；只接桥和钩子，他会一直"想她"却从不被满足。
