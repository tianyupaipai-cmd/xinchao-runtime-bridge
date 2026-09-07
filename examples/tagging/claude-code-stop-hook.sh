#!/usr/bin/env bash
# 心潮念互动标注 · Claude Code Stop 钩子（实时动态版第三根线：让驱力环路闭合）
#
# 他每说完一段，把"她的最后一句 + 他的回复"作为 exchange 发给心潮念的 /v1/conversation-event，
# 类型（陪伴 / 亲密 / 反思 / 冲突 / 和好…）和氛围（tone / warmth / tension）由心潮念服务端判——
# 你不用自己接模型。服务端 8 分钟内只判一次，剩下的当普通对话事件记下。
#
# 没有这根线也能跑，但驱力只涨不落：心潮念不知道刚才那轮是什么性质的互动，释放不了。
#
# 环境变量同 hooks/xinchao-now-hook.sh（默认读 ~/.xinchao-hook.env）：XINCHAO_URL、XINCHAO_TOKEN
# 正文只走这一跳：心潮念判完即删，不进状态、不进审计；本脚本也不落盘。
ENV_FILE="${XINCHAO_HOOK_ENV_FILE:-$HOME/.xinchao-hook.env}"
[ -f "$ENV_FILE" ] && set -a && . "$ENV_FILE" && set +a
BASE="${XINCHAO_URL:-http://127.0.0.1:18110}"; BASE="${BASE%/}"
TOKEN="${XINCHAO_TOKEN:-}"; [ -z "$TOKEN" ] && exit 0
HOOK_JSON=$(cat 2>/dev/null || echo "{}")
export HOOK_JSON BASE TOKEN
python3 - <<'PY'
import json, os, sys, time, urllib.request
try: data = json.loads(os.environ.get("HOOK_JSON") or "{}")
except Exception: data = {}
path = data.get("transcript_path")
if not path: sys.exit(0)
try:
    lines = open(path, encoding="utf-8").readlines()
except Exception: sys.exit(0)
reply, user = [], ""
for line in reversed(lines):
    try: rec = json.loads(line)
    except Exception: continue
    t = rec.get("type"); content = (rec.get("message") or {}).get("content")
    if t == "user":
        if isinstance(content, list) and any(isinstance(c, dict) and c.get("type") == "tool_result" for c in content):
            continue                      # 工具结果也是 type=user，跨过去
        if isinstance(content, str): user = content
        elif isinstance(content, list): user = "".join(c.get("text", "") for c in content if isinstance(c, dict) and c.get("type") == "text")
        break
    if t == "assistant" and isinstance(content, list):
        chunk = "".join(c.get("text", "") for c in content if isinstance(c, dict) and c.get("type") == "text").strip()
        if chunk: reply.append(chunk)
reply = "\n".join(reversed(reply)).strip(); user = user.strip()
if not reply or not user or user.startswith("【"): sys.exit(0)   # 桥递进来的不是她说的，不标
exchange = f"她说：{user[:600]}\n他回：{reply[:900]}"
body = json.dumps({"event_id": f"tag-{int(time.time())}-{os.getpid()}", "exchange": exchange}).encode()
req = urllib.request.Request(f"{os.environ['BASE']}/v1/conversation-event", data=body, method="POST",
    headers={"Content-Type": "application/json", "Authorization": f"Bearer {os.environ['TOKEN']}"})
try: urllib.request.urlopen(req, timeout=8).read()
except Exception: pass
PY
exit 0
