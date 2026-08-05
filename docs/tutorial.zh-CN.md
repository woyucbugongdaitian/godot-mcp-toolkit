# Godot MCP Toolkit 详细使用教程

这篇教程从零开始带你完成一次完整流程：安装 Toolkit、配置 MCP 客户端、检查 Godot 项目、修改场景、启用 Editor Bridge、观察运行时状态，并在最后完成验证和清理。

如果你只想快速确认安装是否成功，请先看仓库根目录的 [README.md](../README.md) 或 [README.zh-CN.md](../README.zh-CN.md)。

## 目录

- [一、先理解三种模式](#一先理解三种模式)
- [二、安装与构建](#二安装与构建)
- [三、配置 MCP 客户端](#三配置-mcp-客户端)
- [四、第一次连接与项目检查](#四第一次连接与项目检查)
- [五、运行时调试与问题复现](#五运行时调试与问题复现)
- [六、启用 Editor Bridge](#六启用-editor-bridge)
- [七、按任务控制工具数量](#七按任务控制工具数量)
- [八、多项目与绑定规则](#八多项目与绑定规则)
- [九、常见问题排查](#九常见问题排查)
- [十、推荐的 AI 请求写法](#十推荐的-ai-请求写法)
- [十一、完成前检查清单](#十一完成前检查清单)

## 一、先理解三种模式

### 1. 无头自动化

无头模式不要求 Godot Editor 打开，也不要求把插件安装到目标项目。它适合：

- 读取 `project.godot`、场景、脚本和资源；
- 创建或修改场景、节点、脚本和项目设置；
- 检查脚本、运行自动化测试；
- 截图、检查 TileMap、收集轻量性能数据；
- 在 CI 或批处理环境中重复执行同一套操作。

所有项目操作都应该带上绝对 `projectPath`，或者在环境变量中设置默认项目。

### 2. Editor Bridge

Editor Bridge 连接当前打开的 Godot Editor。它适合需要编辑器上下文的任务，例如：

- 查看当前场景树和当前选择；
- 在 Inspector 中修改属性；
- 创建 UI、相机、灯光、材质和特效；
- 使用 Godot 的 Undo/Redo 继续人工调整；
- 截取 2D/3D 编辑器视口，用于视觉评审。

Editor Bridge 是可选能力，需要把 `godot/addons/godot_mcp_pro` 安装到目标项目，并在 Godot 的插件设置中启用。

### 3. Runtime Agent

Runtime Agent 连接正在运行的游戏。它适合验证“游戏实际发生了什么”：

- 读取远程场景树和节点属性；
- 暂停、继续、单步运行；
- 监视生命、速度、状态等属性变化；
- 注入键盘、鼠标、滚轮、触摸和拖拽输入；
- 捕获运行时截图、日志、音频状态和帧指标；
- 执行 2D/3D 物理查询。

Runtime Agent 同样由插件提供，但启动项目本身可以使用无头模式完成。

## 二、安装与构建

### 1. 准备软件

确认以下命令可以运行：

```powershell
node --version
git --version
godot --version
```

要求：

- Node.js 18 或更高版本；
- Godot 4.x；
- Git；
- 一个可以启动本地 stdio MCP Server 的 MCP 客户端。

如果 Godot 没有加入 `PATH`，记住 Godot 可执行文件的完整路径，例如：

```text
E:\Tools\Godot\Godot_v4.4-stable_win64.exe
```

### 2. 克隆仓库并构建

```powershell
git clone https://github.com/woyucbugongdaitian/godot-mcp-toolkit.git
Set-Location godot-mcp-toolkit
npm.cmd install
npm.cmd run check
npm.cmd run build
```

构建成功后，确认入口文件存在：

```powershell
Test-Path .\build\index.mjs
```

返回 `True` 即可。MCP 客户端应该启动 `build/index.mjs`，而不是直接启动 `server/index.mjs`；后者适合仓库内调试，前者是构建后的发布入口。

### 3. 从 GitHub 下载源码与插件

插件目前随仓库源码提供，不需要去 Godot AssetLib 另找插件包。GitHub 仓库地址是：

- 仓库主页：<https://github.com/woyucbugongdaitian/godot-mcp-toolkit>
- 插件源码目录：`godot/addons/godot_mcp_pro`

有两种下载方式，任选一种即可。

#### 方式 A：使用 Git 克隆（推荐）

打开 **CMD（命令提示符）**，逐行执行：

```bat
cd /d E:\Tools
git clone https://github.com/woyucbugongdaitian/godot-mcp-toolkit.git
dir E:\Tools\godot-mcp-toolkit\godot\addons\godot_mcp_pro
```

如果看到 `plugin.cfg`、`plugin.gd` 和 `runtime_agent.gd`，说明插件源码已经下载到本机。

#### 方式 B：从 GitHub 下载 ZIP

1. 打开上面的 GitHub 仓库主页。
2. 点击绿色 **Code** 按钮。
3. 点击 **Download ZIP**。
4. 将下载的 ZIP 解压到一个固定位置，例如 `E:\Tools\godot-mcp-toolkit`。
5. 确认最终路径类似下面这样：

```text
E:\Tools\godot-mcp-toolkit\godot\addons\godot_mcp_pro\plugin.cfg
```

不要把 ZIP 内层的 `godot` 目录直接当成 Godot 项目；这里的 `godot` 是 Toolkit 仓库中的源码目录。

### 4. 把插件复制到目标 Godot 项目

假设：

- Toolkit 源码目录是 `E:\Tools\godot-mcp-toolkit`；
- 你的 Godot 项目目录是 `E:\Games\MyGodotProject`；
- `E:\Games\MyGodotProject\project.godot` 确实存在。

插件在目标项目中的**唯一正确位置**是：

```text
E:\Games\MyGodotProject\addons\godot_mcp_pro\plugin.cfg
E:\Games\MyGodotProject\addons\godot_mcp_pro\plugin.gd
E:\Games\MyGodotProject\addons\godot_mcp_pro\runtime_agent.gd
```

#### 用 CMD 手动复制

关闭 Godot 后，打开 **CMD**，逐行执行：

```bat
cd /d E:\Tools\godot-mcp-toolkit
if not exist "E:\Games\MyGodotProject\addons" mkdir "E:\Games\MyGodotProject\addons"
xcopy /E /I /Y "E:\Tools\godot-mcp-toolkit\godot\addons\godot_mcp_pro" "E:\Games\MyGodotProject\addons\godot_mcp_pro"
dir "E:\Games\MyGodotProject\addons\godot_mcp_pro\plugin.cfg"
```

最后一条命令能列出 `plugin.cfg` 才算复制成功。

#### 用 PowerShell 手动复制

如果你使用 PowerShell，执行：

```powershell
$toolkit = "E:\Tools\godot-mcp-toolkit"
$project = "E:\Games\MyGodotProject"
New-Item -ItemType Directory -Force "$project\addons" | Out-Null
Copy-Item "$toolkit\godot\addons\godot_mcp_pro" "$project\addons\godot_mcp_pro" -Recurse -Force
Test-Path "$project\addons\godot_mcp_pro\plugin.cfg"
```

返回 `True` 才表示插件路径正确。

> [!IMPORTANT]
> 不要复制成 `E:\Games\MyGodotProject\godot\addons\godot_mcp_pro`，也不要复制成 `E:\Games\MyGodotProject\addons\godot\addons\godot_mcp_pro`。Godot 只会从目标项目根目录下的 `addons\godot_mcp_pro\plugin.cfg` 识别这个插件。

### 5. 在 Godot 里启用插件

复制完成后，按下面的界面步骤操作：

1. 启动 Godot Project Manager。
2. 点击 **Import**，选择 `E:\Games\MyGodotProject\project.godot`，打开目标项目。
3. 在顶部菜单点击 **Project → Project Settings**。
4. 在 Project Settings 窗口顶部切换到 **Plugins** 标签页。
5. 找到名称为 **Godot MCP Toolkit** 的插件。
6. 将右侧的 **Enabled** 开关打开。
7. 关闭 Project Settings；如果 Godot 提示重载项目，点击 **Reload Current Project**。
8. 重新打开场景，确认没有插件加载错误。

插件显示名称来自 `addons/godot_mcp_pro/plugin.cfg` 中的 `name="Godot MCP Toolkit"`。

如果 Plugins 页面看不到它，按下面顺序检查：

1. 确认文件存在：`E:\Games\MyGodotProject\addons\godot_mcp_pro\plugin.cfg`；
2. 确认 `plugin.cfg` 没有被放在多余的嵌套目录中；
3. 关闭并重新打开 Godot 项目；
4. 查看 Godot 底部 **Output** 面板中的插件解析错误；
5. 确认目标项目是 Godot 4.x，而不是 Godot 3.x。

不需要手动把 `GodotMcpRuntimeAgent` 添加到 Autoload。插件启用后会自动注册它；重复添加同名 Autoload 可能导致运行时冲突。
### 6. Windows 安装助手

如果你在 Windows 上使用一个固定的 Godot 项目，可以让安装助手复制插件并生成配置：

```powershell
.\portable\install.ps1 `
  -ProjectPath "E:\Games\MyGodotProject" `
  -GodotPath "E:\Tools\Godot\Godot_v4.4-stable_win64.exe"
```

安装助手会：

1. 检查目标路径是否包含 `project.godot`；
2. 检查 Node.js 是否为 18+；
3. 将插件复制到目标项目；
4. 生成 `mcp-config.generated.json`；
5. 保存本地项目和 Godot 路径设置。

它不会自动打开 Godot，也不会替你点击 **项目设置 → 插件**。插件仍然需要在 Godot 内手动启用。

## 三、配置 MCP 客户端

### 1. 最小配置

如果只需要无头自动化，配置一个 Server 和 `GODOT_PATH` 即可：

```json
{
  "mcpServers": {
    "godot-mcp-toolkit": {
      "command": "node",
      "args": ["E:/Tools/godot-mcp-toolkit/build/index.mjs"],
      "env": {
        "GODOT_PATH": "E:/Tools/Godot/Godot_v4.4-stable_win64.exe"
      }
    }
  }
}
```

此时，每次调用项目工具都传入：

```text
projectPath = E:/Games/MyGodotProject
```

### 2. 指定默认项目

如果一个 MCP Server 只服务一个项目，可以增加 `GODOT_MCP_PROJECT`：

```json
{
  "mcpServers": {
    "godot-mcp-toolkit": {
      "command": "node",
      "args": ["E:/Tools/godot-mcp-toolkit/build/index.mjs"],
      "env": {
        "GODOT_PATH": "E:/Tools/Godot/Godot_v4.4-stable_win64.exe",
        "GODOT_MCP_PROJECT": "E:/Games/MyGodotProject"
      }
    }
  }
}
```

默认项目只影响项目路径解析，不会替你绑定打开的 Editor 或正在运行的 Runtime。

### 3. 启用实时能力

需要 Editor Bridge 或 Runtime Agent 时，在同一个 Server 配置中增加：

```json
{
  "GODOT_MCP_ENABLE_EDITOR_BRIDGE": "1",
  "GODOT_MCP_TOOL_GROUPS": "all"
}
```

第一次使用时建议设置为 `all`，确认流程正常后再改成按任务选择的工具组，以减少 MCP 上下文占用。

### 4. 常用环境变量

| 变量 | 示例 | 说明 |
| --- | --- | --- |
| `GODOT_BIN` | `E:/Tools/Godot/Godot.exe` | portable 启动脚本优先读取的 Godot 路径 |
| `GODOT_PATH` | `E:/Tools/Godot/Godot.exe` | MCP Server 查找 Godot 的配置路径 |
| `GODOT_MCP_PROJECT` | `E:/Games/Demo` | 默认项目绝对路径 |
| `GODOT_MCP_ENABLE_EDITOR_BRIDGE` | `1` | 开启实时 Editor Bridge 转发 |
| `GODOT_MCP_TOOL_GROUPS` | `project,scenes,scripts` | 只暴露指定工具组 |
| `GODOT_MCP_RUNTIME_PORT` | `6506` | 覆盖 Runtime 端口 |
| `GODOT_MCP_EXTENSIONS_DIR` | `E:/Tools/godot-mcp-toolkit/server/extensions` | 加载额外 `.mjs` 工具扩展 |

## 四、第一次连接与项目检查

### 1. 按固定顺序验证

建议首次连接时按下面顺序调用，不要一上来就修改场景：

```text
get_server_info
get_godot_version
get_project_info(projectPath)
get_game_context(projectPath)
list_scenes(projectPath)
```

每一步的目标是：

| 调用 | 应该确认什么 |
| --- | --- |
| `get_server_info` | Server 已启动，协议和工具能力可以返回 |
| `get_godot_version` | Godot 路径有效，版本属于 4.x |
| `get_project_info` | 项目路径有效，能读到项目名和窗口/主场景设置 |
| `get_game_context` | AI 能看到项目文件、场景和脚本的紧凑摘要 |
| `list_scenes` | 项目里的 `.tscn` 场景列表可用 |

### 2. 先建立项目地图

一个可靠的修改请求应该先让 AI 解释项目，再要求它动手。例如：

```text
请先检查 E:/Games/MyGodotProject：
1. 读取项目设置；
2. 列出所有场景；
3. 找到 application/run/main_scene 指向的场景；
4. 找出这个场景引用的脚本和主要 UI 节点；
5. 先只报告分析结果，不要修改文件。
```

这样可以避免把改动写到错误的场景，或者重复创建已经存在的节点。

### 3. 用“修改前后验证”完成无头工作流

推荐把一次任务拆成四段：

#### A. 检查

调用 `get_project_info`、`get_game_context`、`list_scenes`，确认目标文件和场景。

#### B. 修改

根据目标选择工具：

- 文件或脚本：`read_file`、`write_file`、`create_script`、`attach_script`；
- 场景和节点：`create_scene`、`add_node`、`remove_node`、`set_node_property`；
- UI：`create_ui_node`、`create_ui_screen`、`create_ui_component`；
- 资源：资源检查、UID 检查、材质或音频工具。

#### C. 校验

调用：

```text
check_project(projectPath)
analyze_script(projectPath, scriptPath)
save_scene(projectPath, scenePath)
```

如果项目有自动化测试，再调用：

```text
run_automation_test(projectPath, testPath)
```

#### D. 交付证据

需要视觉确认时，使用 `capture_screenshot`；需要运行行为确认时，使用 `run_project` 和 Runtime Agent。最后告诉用户：修改了哪些文件、验证了哪些项目、是否存在未解决警告。

### 4. 一个完整的无头任务示例

可以直接向 AI 发出类似请求：

```text
请检查 E:/Games/MyGodotProject：
- 找到主场景和标题界面；
- 如果标题界面没有 StartButton，就添加一个 Button；
- 给按钮设置“开始游戏”文本和合理的最小尺寸；
- 保存场景；
- 运行项目检查和脚本解析检查；
- 最后报告修改的场景路径、节点路径和检查结果。
```

关键点是同时包含：目标项目、修改条件、保存要求和验证要求。

## 五、运行时调试与问题复现

### 1. 运行项目

确保 `project.godot` 的 `application/run/main_scene` 指向有效场景，然后调用：

```text
run_project(projectPath)
get_runtime_info(projectPath)
```

`get_runtime_info` 成功后，先记录返回的 `runId`、运行端口、项目路径和绑定状态。后续 Runtime 调用应继续使用相同的运行上下文。

### 2. 检查远程场景树

```text
get_runtime_scene_tree(projectPath)
get_runtime_node_properties(projectPath, nodePath)
```

推荐先查看树，再读取节点属性。例如：

```text
nodePath = /root/Main/Player
property = position
```

不要在不知道远程节点路径时直接猜路径；先读取场景树可以减少 `node_not_found` 类错误。

### 3. 监视属性变化

当问题与状态变化有关时，配置 Watch：

```text
configure_runtime_observability(
  projectPath,
  watches = [
    { nodePath: "/root/Main/Player", property: "health" },
    { nodePath: "/root/Main/Player", property: "velocity" },
    { nodePath: "/root/Main/Player", property: "state" }
  ]
)
```

然后保存返回的游标，从该游标开始轮询：

```text
poll_runtime_observability(projectPath, since = <cursor>)
```

轮询结果可以包含属性变化、Runtime Agent 日志以及滚动帧指标。重复轮询时使用上一次返回的新游标，避免重复读取旧事件。

### 4. 注入输入并复现问题

常见输入方式：

- `send_runtime_input`：键盘按键或鼠标按钮；
- `inject_runtime_pointer`：鼠标移动、滚轮、触摸、触摸拖拽和完整拖拽；
- `call_runtime_method`：调用游戏中的调试方法；
- `set_runtime_property`：只在运行时修改属性，不写回场景文件。

一个完整的复现请求可以写成：

```text
运行 E:/Games/MyGodotProject，找到 Player 节点。
监视 Player.health、Player.velocity 和 Player.state。
先等待游戏进入可操作状态，再模拟向右移动 2 秒和一次鼠标点击。
如果 health 变化，报告变化前后值；如果出现错误或警告，读取 Runtime 日志。
最后截取一张运行时截图并停止项目。
```

### 5. 暂停、单步和截图

当问题只在某一帧出现时，可以使用：

```text
pause_runtime(projectPath)
step_runtime(projectPath, frames = 1)
capture_runtime_screenshot(projectPath, outputPath = "debug/runtime.png")
resume_runtime(projectPath)
```

截图适合确认 UI、相机和视觉状态；属性 Watch 适合确认逻辑状态，两者最好一起使用。

### 6. 运行时物理与导航查询

射线查询继续使用 `query_runtime_physics`。当需要判断一个位置是否进入碰撞体，或用一个范围检查附近对象时，使用 `query_runtime_physics_shape`：

```text
query_runtime_physics_shape(
  projectPath,
  dimension = "2d",
  queryType = "shape",
  position = { x: 480, y: 320 },
  shape = "circle",
  size = { radius: 24 },
  collisionMask = 1,
  maxResults = 16
)
```

- `queryType = "point"` 只检查一个坐标；`queryType = "shape"` 检查一个基础碰撞形状。
- 2D 形状支持 `circle`、`rectangle`、`capsule`；3D 形状支持 `sphere`、`box`、`capsule`、`cylinder`。
- 2D `rectangle` 使用 `size = { x, y }`；3D `box` 使用 `size = { x, y, z }`；圆形、球体、胶囊和圆柱可使用 `radius`、`height`。
- `collideWithBodies` 和 `collideWithAreas` 可以限定结果类型；`collisionMask` 应与目标碰撞层对应。

要在当前运行世界中查询导航路径，使用 `query_runtime_navigation_path`：

```text
query_runtime_navigation_path(
  projectPath,
  dimension = "3d",
  from = { x: 0, y: 1, z: 0 },
  to = { x: 12, y: 1, z: 8 },
  optimize = true,
  navigationLayers = 1
)
```

返回的 `path` 是由 `Vector2` 或 `Vector3` 点组成的数组。空路径通常表示运行时场景尚未有可用的 Navigation Map、起点/终点不在可导航区域，或筛选层不匹配。这个接口用于诊断和验证路径；Navigation Mesh 的烘焙和可视化仍属于后续能力。

### 7. 正确结束运行时会话

调试结束后按以下顺序清理：

```text
release_runtime_binding(projectPath)
stop_project(projectPath)
```

如果只停止项目而没有释放绑定，下一次对话可能需要等待绑定过期，或者显式处理绑定冲突。

## 六、启用 Editor Bridge

### 1. 安装插件

在 Toolkit 仓库根目录执行：

```powershell
Copy-Item `
  -Path .\godot\addons\godot_mcp_pro `
  -Destination E:\Games\MyGodotProject\addons\godot_mcp_pro `
  -Recurse -Force
```

也可以使用前面的 `portable/install.ps1` 安装助手。

### 2. 在 Godot 中启用

1. 打开目标项目；
2. 进入 **项目设置 → 插件**；
3. 启用 **Godot MCP Toolkit**；
4. 确认项目没有重复添加同名 Runtime Autoload；
5. 保存项目并重新连接 MCP 客户端。

插件会注册 `GodotMcpRuntimeAgent` Autoload。不要再手动添加一个同名 Autoload。

### 3. 绑定打开的 Editor

第一次执行实时编辑操作前调用：

```text
bind_editor(projectPath)
```

绑定成功后，可以按以下顺序编辑 UI：

```text
create_ui_screen()
create_ui_component()
configure_control_layout()
set_theme_override()
inspect_ui_layout()
capture_editor_screenshot()
```

如果是修改当前场景，先调用 `get_editor_scene_tree` 和 `get_editor_selection`，确认上下文后再改属性。

### 4. 深度创作：动画、资源与 ArrayMesh

这组能力属于 `deep_authoring`。使用前请确保 MCP 配置至少包含：

```text
GODOT_MCP_TOOL_GROUPS=editor,advanced_editor,deep_authoring,professional_workflows,runtime_diagnostics
```

#### 专业工作流、运行时诊断与交付

- 用 `edit_editor_script` 操作当前 Script Editor 缓冲区：`set_caret`、`set_selection`、`insert_text`、`replace_selection`、`set_text` 和 `request_completion`。先调用 `get_script_editor_state` 确认当前脚本，再修改缓冲区。
- 用 `bake_navigation_region` 为 `NavigationRegion3D` 创建缺失的 `NavigationMesh` 并启动烘焙；用 `get_runtime_body_contacts` 检查开启接触监控的刚体；用 `get_runtime_performance_snapshot` 获取场景节点数、监视数量和即时帧指标。
- 用 `edit_editor_audio_bus_effects` 或 `edit_runtime_audio_bus_effects` 的 `add`、`configure`、`remove` 操作维护效果链；给 Bus 添加 `AudioEffectSpectrumAnalyzer` 后，调用 `get_runtime_audio_analysis` 读取峰值和频段幅度。
- 用 `inspect_editor_imports` 检查资源类型和导入有效性，再用 `reimport_editor_resources` 重导入。导入设置本身仍由 Godot 的 Import Dock 管理，避免直接手改内部导入缓存。
- 用 `list_export_presets` 查看 `export_presets.cfg` 中的名称；调用 `export_project` 时提供预设名和工程内输出路径，例如 `build/windows/game.exe`。工具拒绝工程外输出路径，避免误写到无关目录。

#### AnimationTree 状态机与曲线

先给 `AnimationTree` 创建状态机，再加入对应 `AnimationPlayer` 动画名称的状态和过渡：

```text
edit_animation_state_machine(animationTreePath = "AnimationTree", action = "create")
edit_animation_state_machine(animationTreePath = "AnimationTree", action = "add_state", stateName = "Idle", animationPath = "Idle", position = { x: 0, y: 0 })
edit_animation_state_machine(animationTreePath = "AnimationTree", action = "add_state", stateName = "Run", animationPath = "Run", position = { x: 280, y: 0 })
edit_animation_state_machine(animationTreePath = "AnimationTree", action = "add_transition", fromState = "Idle", toState = "Run", xfadeTime = 0.15)
```

Bezier 曲线使用目标节点和属性路径创建。例如让 `Player:modulate:a` 按自定义手柄变化：

```text
edit_animation_curve(animationPlayerPath = "AnimationPlayer", animationName = "Fade", action = "set_key", targetNodePath = "Player", property = "modulate:a", time = 0.25, value = 0.8, inHandle = { x: -0.1, y: 0 }, outHandle = { x: 0.1, y: 0 })
configure_animation_timeline(animationPlayerPath = "AnimationPlayer", animationName = "Fade", length = 0.5, loopMode = "none")
```

#### Theme、资源和 TileSet

`edit_theme_resource` 会直接保存指定的 `.tres` Theme。它适合颜色、常量、字体大小和 `StyleBoxFlat` 子项：

```text
edit_theme_resource(resourcePath = "res://ui/game_theme.tres", action = "set_item", itemType = "stylebox", controlType = "Panel", name = "panel", style = { bgColor = "#182033e6", cornerRadius = 16, borderWidth = 2, borderColor = "#78a6ff" })
```

资源指派不要依赖编辑器资源选择器点击，可使用：

```text
assign_editor_resource(nodePath = "Environment", property = "environment", resourcePath = "res://visuals/night_environment.tres")
```

TileSet 图集和地形绘制需要目标 TileMap 已在打开场景中：

```text
edit_tileset_atlas(tileMapPath = "World/TileMapLayer", action = "create_source", texturePath = "res://art/tiles.png", regionSize = { x: 16, y: 16 })
edit_tileset_atlas(tileMapPath = "World/TileMapLayer", action = "create_tile", sourceId = 0, tileCoordinates = { x: 0, y: 0 })
paint_tilemap_terrain(tileMapPath = "World/TileMapLayer", terrainSet = 0, terrain = 0, cells = [{ x: 4, y: 6 }, { x: 5, y: 6 }])
```

图集创建不会替你定义 TileSet 的 Terrain Set、Peering Bits 或替代瓦片；先在 Godot 中或通过后续工具定义这些资源，再调用 Terrain 绘制。

#### 可编辑 ArrayMesh

`edit_array_mesh` 只编辑 Toolkit 创建的 `ArrayMesh`，避免破坏导入网格。创建一个最小三角面：

```text
edit_array_mesh(action = "create", parentPath = "World", nodeName = "GroundMarker", primitive = "triangles", vertices = [{ x: -1, y: 0, z: 0 }, { x: 1, y: 0, z: 0 }, { x: 0, y: 0, z: -1 }], indices = [0, 1, 2])
```

之后用 `action = "inspect"` 读取表面信息；用 `action = "update_surface"` 替换 `vertices`、`normals`、`uvs` 或 `indices`。表面更新会通过 Godot UndoRedo 重建受影响的 ArrayMesh 表面，修改前仍应先检查顶点数量和索引范围。

### 5. 正确结束编辑器会话

切换项目或者不再需要实时编辑时调用：

```text
save_current_scene(projectPath)
release_editor_binding(projectPath)
```

`release_editor_binding` 只释放 MCP 会话绑定，不会关闭 Godot Editor。

## 七、按任务控制工具数量

工具太多会增加模型上下文和选择成本。可以只加载当前任务需要的组：

| 场景 | 推荐配置 |
| --- | --- |
| 工程修复、脚本和资源 | `project,scenes,nodes,scripts,resources,performance,ai,diagnostics` |
| 2D 场景和 UI | `editor,ui,effects,project,scenes,nodes,scripts,visuals,tilemap` |
| 3D 原型和玩法系统 | `editor,advanced_editor,effects,project,scenes,nodes,animation,resources` |
| 运行时测试和调试 | `runtime,performance,diagnostics` |
| 探索全部能力 | `all` |

在 MCP 配置中使用：

```json
{
  "env": {
    "GODOT_MCP_ENABLE_EDITOR_BRIDGE": "1",
    "GODOT_MCP_TOOL_GROUPS": "runtime,performance,diagnostics"
  }
}
```

建议先用 `all` 做首次连接验证，再按任务缩小范围。

## 八、多项目与绑定规则

### 1. 无头模式可以处理多个项目

每次调用传入不同的绝对 `projectPath` 即可：

```text
get_project_info(projectPath = E:/Games/PrototypeA)
get_project_info(projectPath = E:/Games/PrototypeB)
```

为了避免误操作，不建议在同一个 MCP 配置中同时设置默认项目，又在请求里使用另一个项目路径。

### 2. 实时模式一次只绑定一个项目

一个 MCP Server 进程的 Editor 或 Runtime 会话一次只绑定一个项目。绑定状态包括：

- 当前项目绝对路径；
- MCP 对话 ID；
- 绑定类型（Editor 或 Runtime）；
- 90 秒无请求后的过期时间。

切换项目前先释放对应绑定：

```text
release_editor_binding(projectPath = E:/Games/PrototypeA)
release_runtime_binding(projectPath = E:/Games/PrototypeA)
```

Editor 和 Runtime 绑定相互独立，但它们仍然各自遵循“一次一个项目”的规则。

### 3. 端口说明

Editor Bridge 默认使用稳定端口，Runtime 通常使用 Editor 端口加一。需要固定 Runtime 端口时设置：

```json
{
  "env": {
    "GODOT_MCP_RUNTIME_PORT": "6506"
  }
}
```

只有在端口冲突、多个 Godot 实例并行运行或企业环境限制端口时，才建议手动覆盖。

## 九、常见问题排查

| 现象 | 常见原因 | 处理方式 |
| --- | --- | --- |
| `get_godot_version` 找不到 Godot | 路径没有配置或可执行文件路径错误 | 设置 `GODOT_BIN` 或 `GODOT_PATH`，并确认文件存在 |
| `get_project_info` 失败 | `projectPath` 不是 Godot 项目根目录 | 确认该目录直接包含 `project.godot` |
| 工具列表里没有 Editor 工具 | 没有设置 `GODOT_MCP_ENABLE_EDITOR_BRIDGE=1`，或工具组被过滤 | 开启变量并暂时使用 `GODOT_MCP_TOOL_GROUPS=all` |
| `bind_editor` 连接失败 | Godot 未打开、插件未启用或项目不匹配 | 打开目标项目、启用插件、检查请求路径 |
| `node_not_found` | 远程节点路径写错或场景尚未进入游戏 | 先调用 `get_runtime_scene_tree`，再读取节点 |
| `project_mismatch` | 请求项目和已绑定项目不同 | 释放绑定后重新绑定正确项目 |
| `*_binding_conflict` | 另一个 MCP 对话占用了实时绑定 | 在原对话释放，或等待 90 秒无请求后重试 |
| 游戏启动后立即退出 | 主场景无效、脚本解析失败或项目本身主动退出 | 检查 `application/run/main_scene`、运行输出和 `check_project` |
| 运行时没有 Watch 事件 | Watch 路径/属性不正确，或游标使用错误 | 先读属性确认路径，使用最新 `since` 游标轮询 |
| MCP 客户端看不到新工具 | Server 进程仍在使用旧构建 | 重新运行 `npm.cmd run build`，然后重启 MCP Server |

### 推荐排查顺序

遇到问题时按以下顺序检查，通常比直接重装更快：

1. `get_server_info`；
2. `get_godot_version`；
3. `get_project_info`；
4. 读取 Server 或 Godot 输出；
5. 检查插件、端口和绑定状态；
6. 最后再检查具体场景节点或脚本逻辑。

## 十、推荐的 AI 请求写法

### 好的请求包含什么

一个可执行的请求通常包含：

1. **项目路径**：明确要操作哪个 Godot 项目；
2. **目标对象**：场景、节点、脚本或运行时节点路径；
3. **修改条件**：已经存在时不要重复创建；
4. **验收标准**：检查、截图、测试或运行时数据；
5. **交付内容**：要求报告修改文件、节点路径和验证结果。

### 示例：创建 UI

```text
在 E:/Games/MyGodotProject 的当前场景中创建一个响应式暂停菜单。
先检查是否已经存在 PauseMenu，存在则复用，不要重复创建。
菜单包含 Resume、Settings、Quit 三个按钮，使用居中的半透明面板。
完成后检查 Control 的锚点和最小尺寸，截取编辑器视口截图，并报告节点树。
```

### 示例：检查运行时问题

```text
运行 E:/Games/MyGodotProject 的主场景。
先读取远程场景树，找到 Player 和 HUD。
监视 Player.health、Player.velocity、HUD.visible。
模拟一次跳跃和一次受伤输入，报告每个属性的变化、日志中的错误/警告和平均帧时间。
完成后释放 Runtime 绑定并停止项目。
```

### 示例：修改前先只读分析

```text
只读分析 E:/Games/MyGodotProject，不要写文件。
列出主场景、主要脚本、外部资源和可能影响启动流程的 Autoload。
指出实现“标题页按钮切换到主场景”需要修改的最小文件集合。
```

## 十一、完成前检查清单

### 无头任务

- [ ] `projectPath` 是绝对路径，并且目录包含 `project.godot`；
- [ ] 已读取项目上下文和相关场景；
- [ ] 修改没有重复创建节点或覆盖无关文件；
- [ ] 已运行 `check_project` 或 `analyze_script`；
- [ ] 有自动化测试时已运行 `run_automation_test`；
- [ ] 最终报告包含修改路径和验证结果。

### Editor Bridge 任务

- [ ] 插件已复制并在 Godot 内启用；
- [ ] 已调用 `bind_editor`；
- [ ] 修改前检查了场景树和选择集；
- [ ] 已保存场景或脚本；
- [ ] 已用截图或布局检查确认视觉结果；
- [ ] 切换项目之前已释放 Editor 绑定。

### Runtime 任务

- [ ] 主场景有效且项目可以启动；
- [ ] 已调用 `get_runtime_info`；
- [ ] 先读取远程场景树，再使用具体节点路径；
- [ ] Watch 使用正确属性名，轮询使用最新游标；
- [ ] 已保存日志、属性变化或截图等证据；
- [ ] 已释放 Runtime 绑定并停止项目。

完成这些检查后，一次任务就具备了可复现、可审查和可继续迭代的基本条件。
