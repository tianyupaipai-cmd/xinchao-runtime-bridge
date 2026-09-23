#!/usr/bin/env bash
# 心潮念「此刻」钩子 · 通用版（实时动态版第二根线）
#
# 每次用户发一条消息前跑一次：
#   1) 给心潮念发一次心跳（她来了——这是驱力释放环路里"到来"的信号）；
#   2) 拉一次 /v1/now 的"此刻"压缩块，节流后原样打到 stdout。
# stdout 的内容由运行时附进这一轮的上下文——Claude Code 的 UserPromptSubmit 钩子就是这么用 stdout 的；
# 别的运行时在调模型前先跑本脚本，把 stdout 拼在用户消息前面即可（见 README）。
#
# 只用 bash + curl + python3。任何一步失败都静默退出 0，绝不阻塞对话。
#
# 环境变量（都可以写在 XINCHAO_HOOK_ENV_FILE 指向的文件里，默认 ~/.xinchao-hook.env，权限请设 600）：
#   XINCHAO_URL          心潮念地址，默认 http://127.0.0.1:18110
#   XINCHAO_TOKEN        心潮念的 DYNAMIC_MIND_TOKEN（同 MCP 用的那个）
#   XINCHAO_HOOK_STATE   状态目录，默认 /tmp/xinchao-hook
#   XINCHAO_HOOK_PREFIX  以这个字符开头的消息不算"她来了"（桥递进来的话），默认 【
# 节流规则：
#   - 块内容没变且 30 分钟内附过 → 不附；
#   - 她隔 90 分钟以上再来的第一条 → 必附；
#   - 心潮念自检 ok=false、块超 8 行 / 400 字、混进数字或英文键名 → 不附（硬门，防后端算坏了带坏他）；
#   - 存在 $XINCHAO_HOOK_STATE/off 这个文件 → 不附（一键关：touch 它；再开：rm 它）。
ENV_FILE="${XINCHAO_HOOK_ENV_FILE:-$HOME/.xinchao-hook.env}"
[ -f "$ENV_FILE" ] && set -a && . "$ENV_FILE" && set +a
BASE="${XINCHAO_URL:-http://127.0.0.1:18110}"; BASE="${BASE%/}"
TOKEN="${XINCHAO_TOKEN:-}"
STATE="${XINCHAO_HOOK_STATE:-/tmp/xinchao-hook}"
PREFIX="${XINCHAO_HOOK_PREFIX:-【}"
mkdir -p "$STATE" 2>/dev/null || exit 0
[ -z "$TOKEN" ] && exit 0

# 读 stdin 里的 prompt 开头（Claude Code 给的是 JSON {"prompt": ...}；别的运行时可以直接喂纯文本或什么都不喂）
HEAD=$(python3 -c 'import sys,json
raw=sys.stdin.read()
try: p=json.loads(raw).get("prompt","")
except Exception: p=raw
print(p.lstrip()[:1])' 2>/dev/null)
[ "$HEAD" = "$PREFIX" ] && exit 0      # 桥递进来的不是她来了

NOW_EPOCH=$(date +%s)
PREV_RUN=$(cat "$STATE/lastrun" 2>/dev/null || echo 0)
echo -n "$NOW_EPOCH" > "$STATE/lastrun"

# 1) 心跳（失败无所谓）
curl -s -X POST "$BASE/v1/heartbeat" -H "Content-Type: application/json" -H "Authorization: Bearer $TOKEN" \
  -d "{\"event_id\":\"hb-$NOW_EPOCH-$$\"}" --max-time 4 >/dev/null 2>&1

# 2) 此刻块
[ -f "$STATE/off" ] && exit 0
NOW_JSON=$(curl -s -H "Authorization: Bearer $TOKEN" --max-time 3 "$BASE/v1/now" 2>/dev/null) || exit 0
[ -z "$NOW_JSON" ] && exit 0
DIGEST=$(printf '%s' "$NOW_JSON" | python3 -c 'import sys,json,re
try:
    d=json.load(sys.stdin); t=d.get("text","")
    ok=d.get("ok") is True and 0<d.get("lines",0)<=8 and 0<len(t)<=400
    ok=ok and not re.search(r"\d\.\d|[a-z_]{6,}", re.sub(r"\d+ (条|句)|xinchao_context","",t))
    print(d.get("digest","") if ok else "")
except Exception: print("")' 2>/dev/null)
[ -z "$DIGEST" ] && exit 0
PREV_DIGEST=""; PREV_AT=0
[ -f "$STATE/now" ] && { PREV_DIGEST=$(cut -f1 "$STATE/now"); PREV_AT=$(cut -f2 "$STATE/now"); }
ARRIVAL=0; [ $((NOW_EPOCH - PREV_RUN)) -ge 5400 ] && ARRIVAL=1
[ "$ARRIVAL" -eq 0 ] && [ "$DIGEST" = "$PREV_DIGEST" ] && [ $((NOW_EPOCH - PREV_AT)) -lt 1800 ] && exit 0
TEXT=$(printf '%s' "$NOW_JSON" | python3 -c 'import sys,json
try: print(json.load(sys.stdin).get("text",""))
except Exception: print("")' 2>/dev/null)
[ -z "$TEXT" ] && exit 0
printf '%s\t%s' "$DIGEST" "$NOW_EPOCH" > "$STATE/now"
printf '%s\n' "$TEXT"
exit 0
