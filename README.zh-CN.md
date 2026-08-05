# Godot MCP Toolkit（简体中文）

> 让支持 MCP 的 AI 客户端，以结构化、可验证的方式理解、创建、修改、运行和调试 Godot 4 项目。

[![Godot 4](https://img.shields.io/badge/Godot-4.x-478cbf?logo=godotengine&logoColor=white)](https://godotengine.org/)
[![Node.js 18+](https://img.shields.io/badge/Node.js-18%2B-339933?logo=node.js&logoColor=white)](https://nodejs.org/)
[![MCP](https://img.shields.io/badge/MCP-2025--06--18-6f42c1)](https://modelcontextprotocol.io/)
[![许可证](https://img.shields.io/badge/license-MIT-22c55e)](LICENSE)
[![English](https://img.shields.io/badge/docs-English-2563eb)](README.md)

[English](README.md) · [详细使用教程](docs/tutorial.zh-CN.md) · [能力清单](docs/capabilities.md) · [编辑器桥接](docs/editor-bridge.md) · [兼容性](docs/compatibility.md) · [路线图](docs/roadmap.md)

Godot MCP Toolkit 通过三部分连接 MCP 客户端与 Godot：可复现的**无头自动化**、可选的实时 **Editor Bridge**，以及用于观察真实游戏的 **Runtime Agent**。它让工作流从“先理解项目”开始，以“完成修改并验证结果”结束，不需要依赖脆弱的屏幕坐标点击。

> [!TIP]
> 描述目标，而不是描述点击步骤：例如“创建自适应暂停菜单”“给测试场景添加相机和主光”“运行场景并报告生命值变化与帧时间”。

## 先选使用路径

| 你想要…… | 从这里开始 | 是否需要插件 |
| --- | --- | --- |
| 检查或修改项目文件、场景、脚本和资源 | [快速开始](#快速开始) | 否 |
| 在打开的 Godot 编辑器中保留场景上下文、选择集和 Undo/Redo | [Editor Bridge](docs/editor-bridge.md) | 是 |
| 检查和控制正在运行的游戏 | [运行时教程](docs/tutorial.zh-CN.md#五运行时调试与问题复现) | 是 |
| 减少 MCP 客户端看到的工具数量 | [按任务加载工具组](#按任务加载工具组) | 否 |

## 工作方式

```mermaid
flowchart LR
    Client["MCP 客户端 / AI 助手"] --> Server["Godot MCP Toolkit\nNode.js MCP Server"]
    Server --> Headless["无头 Godot\n文件 · 场景 · 校验 · 测试"]
    Server --> Bridge["Editor Bridge\n已打开的 Godot 编辑器"]
    Server --> Agent["Runtime Agent\n正在运行的游戏"]
    Bridge --> Editor["场景树 · Inspector · 2D · 3D · UI"]
    Agent --> Game["输入 · 属性 · 日志 · 帧指标"]
```

### 三种模式

- **无头自动化**：工程发现与创建、场景和节点修改、资源与 UID 检查、GDScript 生成与解析、截图、自动化测试、TileMap 检查和轻量性能采样。
- **Editor Bridge**：操作当前打开的 Godot Editor，包括场景树、Inspector 属性、选择集、2D/3D 内容、UI、效果、动画、导航、物理、音频、Theme、插件和工作区。
- **Runtime Agent**：查看远程节点和属性，调用方法，暂停/继续/单步，注入键盘和鼠标/触摸输入，截图，执行射线、点和基础形状重叠物理查询，查询导航路径，控制音频，监视属性，并收集日志与帧指标。

## 能力总览

| 方向 | 示例 | 适合解决的问题 |
| --- | --- | --- |
| **项目理解** | `get_project_info`、文件搜索、资源、UID、项目上下文 | 修改前快速理解陌生项目 |
| **场景创作** | 创建、检查、复制、保存、添加、移动、改名、删除和配置节点 | 将自然语言需求转成可复现的场景修改 |
| **2D 与 UI** | 精灵、Control、相机、灯光、UI Screen、布局、Theme 覆盖 | 菜单、HUD、弹窗和 2D 原型 |
| **3D 创作** | 原始网格、相机、灯光、Transform、StandardMaterial、风格化渲染 | 快速搭建和布置 3D 测试场景 |
| **玩法系统** | 动画轨道、AnimationTree 状态、导航节点、Agent、碰撞形状、音频 | 不把关键修改隐藏在难以审查的生成文件里 |
| **运行时验证** | 远程树/属性、输入注入、截图、射线/点/基础形状重叠查询、导航路径、Watch、日志、帧指标 | 复现问题并用运行证据确认结果 |

完整工具清单见 [docs/capabilities.md](docs/capabilities.md)。

## 快速开始

### 1. 准备环境

- Node.js **18 或更高版本**。
- Godot **4.x**，可通过 `GODOT_BIN`、`GODOT_PATH` 配置，或将 `godot` / `godot4` 加入 `PATH`。
- 一个能够启动本地 stdio Server 的 MCP 客户端。

### 2. 安装并构建

```powershell
git clone https://github.com/woyucbugongdaitian/godot-mcp-toolkit.git
Set-Location godot-mcp-toolkit
npm.cmd install
npm.cmd run build
```

构建后的入口是 `build/index.mjs`。请从仓库根目录构建，以便 Server 正确找到内置的 Godot 操作脚本。

### 3. 配置 MCP Server

把下面配置加入 MCP 客户端，并替换两个本机路径：

```json
{
  "mcpServers": {
    "godot-mcp-toolkit": {
      "command": "node",
      "args": ["E:/Tools/godot-mcp-toolkit/build/index.mjs"],
      "env": {
        "GODOT_PATH": "E:/Tools/Godot/Godot_v4.x-stable_win64.exe",
        "GODOT_MCP_PROJECT": "E:/Games/MyGodotProject"
      }
    }
  }
}
```

`GODOT_MCP_PROJECT` 是可选项。不设置时，每次项目操作都传入绝对路径 `projectPath`。可直接复制的模板见 [examples/mcp-config.json](examples/mcp-config.json)。

### 4. 验证连接

让 MCP 客户端按顺序调用：

1. `get_server_info`：确认 Server 可访问并读取能力信息。
2. `get_godot_version`：确认可以启动指定的 Godot 可执行文件。
3. `get_project_info`：读取项目元数据和关键设置。
4. `get_game_context`：为 AI 构建紧凑的项目上下文图。

四步都成功后，无头工作流就准备好了。接着阅读[详细使用教程](docs/tutorial.zh-CN.md)，完成一次完整的“理解 → 修改 → 验证”闭环。

## 启用 Editor 与 Runtime

实时能力默认关闭。只有在需要操作打开的 Godot Editor 或正在运行的游戏时，才需要安装插件。

1. 将 `godot/addons/godot_mcp_pro` 复制到目标项目的 `addons/godot_mcp_pro`。
2. 在 Godot 中打开 **项目设置 → 插件**，启用 **Godot MCP Toolkit**。
3. 给 MCP Server 增加以下环境变量：

```json
{
  "GODOT_MCP_ENABLE_EDITOR_BRIDGE": "1",
  "GODOT_MCP_TOOL_GROUPS": "all"
}
```

4. 重载 Godot 项目，并重连 MCP 客户端。
5. 编辑打开的场景前先调用 `bind_editor`。
6. 控制运行中的游戏时，先调用 `run_project`，再调用 `get_runtime_info`。

Windows 可以使用安装助手复制插件并生成配置：

```powershell
.\portable\install.ps1 -ProjectPath "E:\Games\MyGodotProject" -GodotPath "E:\Tools\Godot\Godot_v4.x-stable_win64.exe"
```

安装助手**不会**自动替你在 Godot 内启用插件。绑定规则见 [docs/editor-bridge.md](docs/editor-bridge.md)，完整流程见 [docs/tutorial.zh-CN.md](docs/tutorial.zh-CN.md)。

## 按任务加载工具组

设置 `GODOT_MCP_TOOL_GROUPS`，只让 MCP 客户端看到当前任务需要的能力：

| 工作内容 | 推荐工具组 |
| --- | --- |
| 工程修复或脚本生成 | `project,scenes,nodes,scripts,resources,performance,ai,diagnostics` |
| 2D 地图和 UI | `editor,ui,effects,project,scenes,nodes,scripts,visuals,tilemap` |
| 3D 原型和玩法系统 | `editor,advanced_editor,effects,project,scenes,nodes,animation,resources` |
| 运行时测试和调试 | `runtime,performance,diagnostics` |
| 全部能力 | `all` |

`editor`、`ui`、`effects`、`advanced_editor` 需要 Editor Bridge。Runtime 的远程控制也需要插件；`run_project`、输出读取、无头输入模拟和自动化测试无需插件即可使用。

## 常见工作流

### 理解并改进现有项目

1. 调用 `get_project_info`、`list_scenes`、`get_game_context`。
2. 让 AI 找出相关场景、脚本和资源，并说明修改范围。
3. 用项目、场景、脚本工具或实时 Editor 工具做小范围修改。
4. 运行 `check_project`、`analyze_script` 和 `run_automation_test`。

**示例请求：**“检查这个项目，找到标题场景，添加一个加载主场景的开始按钮，然后运行脚本解析检查。”

### 制作精致的 2D 界面

1. 启用 Editor Bridge 并调用 `bind_editor`。
2. 用 `create_ui_screen` 创建层级，用 `create_ui_component` 添加语义控件。
3. 用 `configure_control_layout` 调布局，用 `set_theme_override` 调样式，用 `inspect_ui_layout` 检查结构。
4. 添加过渡或视觉效果，最后截取 Editor 视口截图评审。

**示例请求：**“创建响应式暂停菜单，包含继续、设置、退出三个按钮；使用深色半透明面板，居中并快速淡入。”

### 调试正在运行的游戏

1. 运行项目并调用 `get_runtime_info`，建立 Runtime 绑定。
2. 检查远程场景树，为生命、速度或状态配置 Watch。
3. 轮询 `poll_runtime_observability`，收集属性变化、日志和滚动帧指标。
4. 注入键盘、鼠标、触摸、滚轮或拖拽输入来复现问题，并保存截图证据。
5. 结束时调用 `release_runtime_binding` 和 `stop_project`。

**示例请求：**“运行当前场景，监视玩家生命和移动状态，模拟一次背包拖拽，并报告新增警告和平均帧时间。”

## 配置速查

| 变量 | 是否必需 | 作用 |
| --- | --- | --- |
| `GODOT_BIN` | 否 | 本地启动和 portable 助手优先使用的 Godot 路径。 |
| `GODOT_PATH` | 否 | MCP Server 配置中使用的 Godot 可执行文件路径。 |
| `GODOT_MCP_PROJECT` | 否 | 项目操作默认使用的绝对项目路径。 |
| `GODOT_MCP_ENABLE_EDITOR_BRIDGE` | 否 | 设置为 `1`，启用实时 Editor Bridge 转发。 |
| `GODOT_MCP_TOOL_GROUPS` | 否 | 逗号分隔的工具组，或设置为 `all`。 |
| `GODOT_MCP_RUNTIME_PORT` | 否 | 覆盖启动项目使用的 Runtime 端口。 |
| `GODOT_MCP_EXTENSIONS_DIR` | 否 | 加载额外 `.mjs` 工具扩展的目录。 |

## 会话安全与绑定规则

- 未配置 `GODOT_MCP_PROJECT` 时，项目操作使用绝对路径 `projectPath`。
- 一个 MCP 对话同一时间只绑定一个实时 Editor 或 Runtime 项目；90 秒无请求后绑定会过期。
- Editor 与 Runtime 绑定相互独立；切换项目之前调用对应的 `release_editor_binding` 或 `release_runtime_binding`。
- Editor 实时修改会尽可能接入 Godot 的 Undo/Redo 工作流。
- Bridge 使用本机回环 WebSocket，不需要云端中转。
- 不支持的 Godot 4.x API 会返回结构化错误，不会直接终止 MCP Server。

## 文档导航

| 文档 | 适合什么时候阅读 |
| --- | --- |
| [详细使用教程](docs/tutorial.zh-CN.md) | 从安装、配置到编辑器和运行时调试，完整走一遍 |
| [能力清单](docs/capabilities.md) | 查看支持的操作家族 |
| [编辑器桥接与运行时代理](docs/editor-bridge.md) | 启用插件、理解端口和释放绑定 |
| [多项目使用](docs/multi-project.md) | 同时处理多个项目或多个 Godot 版本 |
| [兼容性](docs/compatibility.md) | 确认 MCP 协议和 Godot 支持范围 |
| [路线图](docs/roadmap.md) | 查看当前边界与后续优先级 |
| [贡献指南](CONTRIBUTING.md) | 运行检查、提交问题或贡献改进 |

## 当前边界

Godot MCP Toolkit 优先提供稳定、可验证的语义操作，而不是像素级复刻每一个 Godot Editor 面板。网格和骨骼编辑、高级动画图、Navigation Mesh 烘焙、详细物理调试可视化、Audio Bus 效果链分析、导出预设执行，以及高级 TileMap/Theme 子编辑仍属于路线图内容。详见 [docs/roadmap.md](docs/roadmap.md)。

## 开发

```powershell
npm.cmd run check
npm.cmd test
npm.cmd run build
```

测试覆盖 MCP 合约以及 Editor/Runtime 一对一绑定行为。

## 许可证

本项目采用 [MIT License](LICENSE)，归属信息见 [NOTICE.md](NOTICE.md)。
