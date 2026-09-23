#!/usr/bin/env bash
# 心潮念命令行直调（走 MCP 的 Streamable HTTP，不经过任何客户端的连接器，改完不用重启窗口）
#   xinchao.sh tools                         列全部工具与参数
#   xinchao.sh context [turn]                开窗/续接时拉信封（turn = 聊了一阵看全貌）
#   xinchao.sh event <类型> ["cause"]         记一次真实互动：companionship|affection|intimacy|conflict|... 只记结果明确的
#   xinchao.sh event exchange "这轮对话"       拿不准类型就把对话塞进去让服务端判
#   xinchao.sh handoff "进度摘要"              换窗前存便签（脱水，不写原话）
#   xinchao.sh awareness [list|confirm <id>|drop <id>]
#   xinchao.sh <任意工具名> '<JSON 参数>'        通用：xinchao.sh xinchao_hold '{"content":"…","meaning":"…"}'
# 配置和钩子共用 ~/.xinchao-hook.env（XINCHAO_URL、XINCHAO_TOKEN）；XINCHAO_SESSION_ID 是这个窗口的标识，默认 local-cli。
set -u
D="$(cd "$(dirname "$0")" && pwd)"
ENV_FILE="${XINCHAO_HOOK_ENV_FILE:-$HOME/.xinchao-hook.env}"
[ -f "$ENV_FILE" ] && set -a && . "$ENV_FILE" && set +a
TOKEN="${XINCHAO_TOKEN:?请在 $ENV_FILE 里设置 XINCHAO_TOKEN}"
BASE="${XINCHAO_URL:-http://127.0.0.1:18110}"; URL="${BASE%/}/mcp"; SID_DEFAULT="${XINCHAO_SESSION_ID:-local-cli}"
call() { "$D/mcp-call.sh" "$URL" "$TOKEN" "$@"; }
j() { python3 -c 'import sys,json,uuid
o=json.loads(sys.argv[1])
if "session_id" in sys.argv[2].split(",") and "session_id" not in o: o["session_id"]=sys.argv[3]
if "event_id" in sys.argv[2].split(",") and "event_id" not in o: o["event_id"]=str(uuid.uuid4())
print(json.dumps(o,ensure_ascii=False))' "$1" "$2" "$SID_DEFAULT"; }
case "${1:-}" in
  ""|-h|--help) sed -n '2,10p' "$0";;
  tools) call tools;;
  context) call xinchao_context "$(j "{\"mode\":\"${2:-compact}\"}" session_id)";;
  event)
    [ -n "${2:-}" ] || { echo "要类型或 exchange"; exit 2; }
    if [ "$2" = exchange ]; then A=$(python3 -c 'import sys,json; print(json.dumps({"exchange":sys.argv[1]},ensure_ascii=False))' "${3:-}")
    else A=$(python3 -c 'import sys,json; o={"interaction_type":sys.argv[1]}
if len(sys.argv)>2 and sys.argv[2]: o["cause"]=sys.argv[2]
print(json.dumps(o,ensure_ascii=False))' "$2" "${3:-}"); fi
    call xinchao_event "$(j "$A" session_id,event_id)";;
  handoff) call xinchao_handoff_note "$(j "$(python3 -c 'import sys,json; print(json.dumps({"note":sys.argv[1]},ensure_ascii=False))' "${2:-}")" session_id,event_id)";;
  awareness) A=$(python3 -c 'import sys,json; o={"action":sys.argv[1] if len(sys.argv)>1 and sys.argv[1] else "list"}
if len(sys.argv)>2: o["id"]=sys.argv[2]
print(json.dumps(o))' "${2:-}" "${3:-}"); call xinchao_awareness "$A";;
  *) case "$1" in
       xinchao_event|xinchao_handoff_note|xinchao_cabin_note) call "$1" "$(j "${2:-{\}}" session_id,event_id)";;
       xinchao_context) call "$1" "$(j "${2:-{\}}" session_id)";;
       *) call "$1" "${2:-{\}}";;
     esac;;
esac
