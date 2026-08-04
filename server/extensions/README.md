# MCP 扩展工具

服务端支持通过 `GODOT_MCP_EXTENSIONS_DIR` 加载额外的 `.mjs` 工具模块。扩展模块导出一个 `tools` 数组，每个元素包含 `name`、`description`、`inputSchema` 和异步 `handler`。

```js
export const tools = [
  {
    name: "my_tool",
    description: "A project-specific tool",
    inputSchema: {
      type: "object",
      required: ["projectPath"],
      properties: { projectPath: { type: "string" } },
      additionalProperties: false,
    },
    async handler(args) {
      return { ok: true, projectPath: args.projectPath };
    },
  },
];
```

约定：

- 扩展工具名必须唯一，默认归入 `extension` 分组。
- 扩展工具不能直接修改服务端核心状态；需要项目文件时复用 `projectPath` 安全约束。
- 通过 `GODOT_MCP_TOOL_GROUPS=all,extension` 或显式分组开启扩展工具。
- 服务器升级时优先保持 MCP 工具入参兼容；破坏性变更应提升 `schemaVersion` 并提供迁移说明。
