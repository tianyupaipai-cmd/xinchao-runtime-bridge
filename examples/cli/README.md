# 命令行直调

不经过任何客户端的连接器，直接用 MCP 的 Streamable HTTP 调心潮念——窗口里的 AI 用 Bash 就能记事件、拉信封、看觉察；改了服务端也不用重启窗口。

- `mcp-call.sh`：通用内核，`mcp-call.sh <url> <token|-> tools` 列工具，`mcp-call.sh <url> <token> <工具名> '<JSON>'` 调一个。任何 Streamable HTTP 的 MCP 服务都能用。
- `xinchao.sh`：心潮念的薄封装，常用的几个有快捷写法（`context`、`event`、`handoff`、`awareness`），其余 `xinchao.sh <工具名> '<JSON>'`。`session_id` / `event_id` 缺了会自动补。

配置和钩子共用 `~/.xinchao-hook.env`（`XINCHAO_URL`、`XINCHAO_TOKEN`，权限 600）；`XINCHAO_SESSION_ID` 是这个窗口的标识，默认 `local-cli`。两个脚本放在同一个目录。
