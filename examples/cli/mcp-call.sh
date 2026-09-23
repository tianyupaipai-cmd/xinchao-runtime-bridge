#!/usr/bin/env bash
# MCP（Streamable HTTP）直调内核，给 xinchao.sh 用，也能直调任何 Streamable HTTP 的 MCP 服务。
#   mcp-call.sh <url> <token|-> tools            列工具（名字 | 说明 | 参数，* 为必填）
#   mcp-call.sh <url> <token|-> <tool> ['<json>'] 调一个工具，打印文本结果
set -u
URL="$1"; TOKEN="$2"; TOOL="${3:-tools}"; ARGS="${4:-{\}}"
H=(-H 'Content-Type: application/json' -H 'Accept: application/json, text/event-stream'); [ "$TOKEN" != "-" ] && H+=(-H "Authorization: Bearer $TOKEN")
first_json() { sed 's/^data: //' | python3 -c 'import sys,json
for l in sys.stdin:
    l=l.strip()
    if l.startswith("{"): print(l); break'; }
SID=$(curl -s -m 15 -D - -o /dev/null "${H[@]}" -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"xinchao-cli","version":"1"}}}' "$URL" | grep -i '^mcp-session-id' | tr -d '\r' | cut -d' ' -f2)
[ -n "$SID" ] || { echo "服务没响应或拒绝（$URL）" >&2; exit 1; }
curl -s -m 15 "${H[@]}" -H "Mcp-Session-Id: $SID" -d '{"jsonrpc":"2.0","method":"notifications/initialized"}' "$URL" >/dev/null
if [ "$TOOL" = tools ]; then
  curl -s -m 15 "${H[@]}" -H "Mcp-Session-Id: $SID" -d '{"jsonrpc":"2.0","id":2,"method":"tools/list"}' "$URL" | first_json | python3 -c 'import sys,json
d=json.loads(sys.stdin.read())
for t in d.get("result",{}).get("tools",[]):
    s=t.get("inputSchema",{}); p=s.get("properties",{}); r=s.get("required",[])
    desc=(t.get("description") or "")[:80].replace(chr(10)," ")
    args=",".join(k+("*" if k in r else "") for k in p)
    print("%s | %s | %s" % (t["name"], desc, args))'
  exit 0
fi
python3 -c 'import sys,json; json.loads(sys.argv[1])' "$ARGS" 2>/dev/null || { echo "参数不是合法 JSON：$ARGS" >&2; exit 2; }
BODY=$(python3 -c 'import sys,json; print(json.dumps({"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":sys.argv[1],"arguments":json.loads(sys.argv[2])}},ensure_ascii=False))' "$TOOL" "$ARGS")
curl -s -m 120 "${H[@]}" -H "Mcp-Session-Id: $SID" -d "$BODY" "$URL" | first_json | python3 -c 'import sys,json
d=json.loads(sys.stdin.read() or "{}")
if "error" in d: print("错误:", d["error"].get("message", d["error"])); sys.exit(1)
r=d.get("result",{})
c=r.get("content") or []
out=[x.get("text","") for x in c if isinstance(x,dict) and x.get("type")=="text"]
print("\n".join(out) if out else json.dumps(r,ensure_ascii=False,indent=1))
if r.get("isError"): sys.exit(1)'
