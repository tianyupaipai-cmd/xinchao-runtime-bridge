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
# 正文只走这一跳：心潮念判完即删，不进状态、不进审计；本脚本只落一个时间戳文件（节流用），不落正文。
#
# 节流（三道闸；心潮念那头一天只结算 24 次，一场长聊一小时就能用光，所以钩子先挡）：
#   - 她隔了 XINCHAO_TAG_ARRIVAL_MIN（默认 45）分钟以上再开口的第一句永远发——那是"她来了"，陪伴本身
#   - 两次发送之间至少隔 XINCHAO_TAG_GAP_MIN（默认 8）分钟
#   - 每小时最多 XINCHAO_TAG_HOURLY_MAX（默认 4）次
#   - 她那句话超过 45 分钟前说的不标（转录里没有时间就不判这条）
#   状态文件 XINCHAO_TAG_STATE（默认 ~/.xinchao-tag-state.json）只存发送时间戳。
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
def ts_of(rec):
    v = rec.get("timestamp")
    if not v: return None
    try:
        from datetime import datetime
        return datetime.fromisoformat(str(v).replace("Z", "+00:00")).timestamp()
    except Exception: return None
def user_text(content):
    if isinstance(content, str): return content
    if isinstance(content, list): return "".join(c.get("text", "") for c in content if isinstance(c, dict) and c.get("type") == "text")
    return ""
reply, user, user_ts, prev_user_ts = [], "", None, None
for line in reversed(lines):
    try: rec = json.loads(line)
    except Exception: continue
    t = rec.get("type"); content = (rec.get("message") or {}).get("content")
    if t == "user":
        if isinstance(content, list) and any(isinstance(c, dict) and c.get("type") == "tool_result" for c in content):
            continue                      # 工具结果也是 type=user，跨过去
        if not user:
            user = user_text(content); user_ts = ts_of(rec)
            if not user.strip(): user = ""; continue
            continue
        prev_user_ts = ts_of(rec)         # 再往前一条她说的话：算"她隔了多久再来"
        break
    if t == "assistant" and not user and isinstance(content, list):
        chunk = "".join(c.get("text", "") for c in content if isinstance(c, dict) and c.get("type") == "text").strip()
        if chunk: reply.append(chunk)
reply = "\n".join(reversed(reply)).strip(); user = user.strip()
if not reply or not user or user.startswith("【"): sys.exit(0)   # 桥递进来的不是她说的，不标

# ---- 节流 ----
now = time.time()
gap_min = float(os.environ.get("XINCHAO_TAG_GAP_MIN") or 8)
hourly_max = int(os.environ.get("XINCHAO_TAG_HOURLY_MAX") or 4)
arrival_min = float(os.environ.get("XINCHAO_TAG_ARRIVAL_MIN") or 45)
state_path = os.environ.get("XINCHAO_TAG_STATE") or os.path.expanduser("~/.xinchao-tag-state.json")
if user_ts and now - user_ts > 45 * 60: sys.exit(0)          # 她那句是 45 分钟前的，不算这轮
try: sent = [float(x) for x in json.load(open(state_path)).get("sent", [])]
except Exception: sent = []
sent = [x for x in sent if now - x < 3600]
arrival = bool(user_ts and prev_user_ts and user_ts - prev_user_ts >= arrival_min * 60)
if not arrival:
    if sent and now - sent[-1] < gap_min * 60: sys.exit(0)   # 间隔不够
    if len(sent) >= hourly_max: sys.exit(0)                  # 这小时够了
sent.append(now)
try: json.dump({"sent": sent[-50:]}, open(state_path, "w"))
except Exception: pass
exchange = f"她说：{user[:600]}\n他回：{reply[:900]}"
body = json.dumps({"event_id": f"tag-{int(time.time())}-{os.getpid()}", "exchange": exchange}).encode()
req = urllib.request.Request(f"{os.environ['BASE']}/v1/conversation-event", data=body, method="POST",
    headers={"Content-Type": "application/json", "Authorization": f"Bearer {os.environ['TOKEN']}"})
try: urllib.request.urlopen(req, timeout=8).read()
except Exception: pass
PY
exit 0
