# Editor Project — Architecture Decision Record (ADR)

- **Version:** 1.0
- **Status:** Accepted

本文件为项目级总纲。逐条新增决策记录于 `docs/adr/`，索引与模板见 `docs/adr/README.md` 与 `docs/adr/_template.md`。

---

## 1. Project Philosophy

本项目不是 VSCode、Cursor、Zed、Sublime、Emacs 或 Vim 的替代品。

目标不是：

- 更多功能
- 更多插件
- AI First
- IDE

目标只有一个：**做一个真正属于 macOS 的、极简但高度可编程的编辑器。**

编辑器默认应该让用户感觉：

> 我打开的是一个 Buffer，而不是一个 IDE。

因此：

- 启动以后只有一个空白窗口。
- 除此之外什么都没有。
- 所有其它 UI 都必须是可选的。

---

## 2. Core Principles

### Principle 1 — Editor First

不是 Project First。
不是 File First。
不是 Workspace First。

整个系统围绕 **Document / Buffer** 构建。
不是围绕 Sidebar、Explorer、Terminal、Git、Project 构建。

### Principle 2 — Everything is Optional

默认不存在：

- Sidebar
- Toolbar
- StatusBar
- ActivityBar
- Welcome Page
- Terminal

所有 UI 都必须可以完全关闭。
如果用户想要，通过 Lua 或配置文件创建。

### Principle 3 — Native macOS Experience

整个项目只支持 macOS。不考虑：

- Windows
- Linux
- Android
- Web

因此可以大胆使用：

- AppKit
- Metal
- CoreText
- 系统输入法
- 系统快捷键
- 系统菜单
- 系统窗口管理

不允许为了跨平台而降低 macOS 体验。

### Principle 4 — Do Not Fight The Operating System

凡是系统已经做好的，全部直接使用。例如：

- IME
- Clipboard
- Window
- Menu
- Accessibility
- Drag & Drop
- Document Picker

不要重复造轮子。

---

## 3. Technology Stack

### 3.1 UI — Swift + AppKit

| 项目 | 选择 |
| --- | --- |
| 语言 | Swift |
| 框架 | AppKit |
| 决策 | 使用 **Swift + AppKit** |
| 拒绝 | SwiftUI |

**理由：** 编辑器需要精确事件、输入法、鼠标、快捷键、Window、Menu。AppKit 比 SwiftUI 更成熟。

SwiftUI 不适合作为编辑器核心 UI。SwiftUI 可以用于 Settings、About、Preferences；不能用于 Editor View。

### 3.2 Rendering — Metal

| 项目 | 选择 |
| --- | --- |
| 语言 | Metal |
| 决策 | 使用 **Metal** |
| 拒绝 | TextKit、CoreGraphics |

**理由：** 整个编辑器应该拥有自己的 Render Pipeline，需要 GPU Rendering、Smooth Scroll、Animation、Selection、Cursor、Future Shader。

- **拒绝 TextKit：** 控制权不足。
- **拒绝 CoreGraphics：** CPU Rendering，未来扩展能力不足。

### 3.3 Core Engine — Rust

职责：

- Document
- Buffer
- Cursor
- Selection
- Undo
- Redo
- Layout
- Theme
- Command
- Event
- Plugin API
- Scheduler

约束：Rust 不允许依赖 AppKit、SwiftUI、NSView、NSWindow。Rust 必须保持平台无关。

### 3.4 Swift ↔ Rust Bridge — swift-bridge

| 项目 | 选择 |
| --- | --- |
| 决策 | 使用 **swift-bridge** |
| 拒绝 | FFI 手写 Binding、IPC |

**理由：** API 更自然，Swift 可以直接调用 Rust。

- **拒绝手写 FFI Binding：** 维护成本高。
- **拒绝 IPC：** 没有必要。

### 3.5 Plugin Runtime — Lua (mlua)

| 项目 | 选择 |
| --- | --- |
| 决策 | 使用 **Lua**，库为 **mlua** |

**理由：** Lua 启动快、Runtime 小、嵌入简单、API 干净，适合作为编辑器 Runtime。

- **拒绝 Python：** Runtime 太重，依赖复杂，启动慢。
- **拒绝 JavaScript：** Runtime 比 Lua 更大，GC 更复杂。
- **拒绝 Rhai：** 生态太小。
- **拒绝 WASM（第一阶段）：** 复杂度过高，第一版不需要；未来可以作为第二插件 Runtime。

---

## 4. Configuration

配置分三层。

### Layer 1 — Theme DSL

声明式、无逻辑、适合新手。例如：

```text
editor {

    background: rgba(0,0,0,255)

}
```

### Layer 2 — Config DSL

- 允许：简单表达式、简单条件。
- 不允许：复杂脚本。

### Layer 3 — Lua

真正控制：

- Editor
- Window
- UI
- Command
- Event
- Plugin
- Animation
- Layout
- Theme

所有 DSL 最终都转换成 Lua API。整个编辑器只维护一个 Runtime。

---

## 5. Storage — SQLite

| 项目 | 选择 |
| --- | --- |
| 决策 | 使用 **SQLite** |
| 拒绝 | JSON、YAML |

SQLite 不是数据库软件，而是编辑器内部状态管理。负责：

- Scratch
- Undo History
- Recent Files
- Workspace
- Crash Recovery
- Session

- **拒绝 JSON：** 无法承担复杂状态。
- **拒绝 YAML：** 解析慢，不适合数据库。

---

## 6. Scratch Document

- 默认 `Cmd+N` 创建 Scratch。
- Scratch 自动保存，无需命名，无需路径。
- 保存在 SQLite。
- 用户真正需要文件时，通过命令绑定路径。
- 不是 "Save As"，而是 "Attach Path"。

---

## 7. File Model

Buffer 永远是第一公民，File 只是 Buffer 的一个存储目标。

```text
Buffer
  |
  +-- 可绑定：Disk File
  |
  +-- 或：SQLite Scratch
```

---

## 8. Shell

| 项目 | 选择 |
| --- | --- |
| 决策 | 使用系统 Shell（zsh / bash / dash / fish） |
| 拒绝 | 自己实现 Shell |

Shell 永远不是编辑器实现。编辑器通过 PTY 与 Shell 通信，负责输入、输出、渲染、Overlay。

**理由：** Shell 已经成熟，没有必要重复实现。

---

## 9. Terminal UI — Shell Overlay

拒绝：

- Dock Bottom Terminal
- Right Terminal
- Split Terminal

决策：**Shell Overlay。**

- 进入：整个 Buffer 轻微模糊，Shell Overlay 出现。
- 退出：恢复 Buffer。

Editor 永远保持中心。Terminal 永远不是一个固定 Panel。

---

## 10. UI Philosophy

UI 不是固定布局，UI 是 **Overlay**。

例如 StatusBar、Sidebar、Search、Shell、Command Palette 全部都是 Overlay。

Core 不允许依赖任何具体 UI。

---

## 11. Plugin Philosophy

Plugin 可以：

- 增加 UI
- 增加 Command
- 增加 Event
- 增加 Renderer

Plugin 不能修改 Core。Core 必须保持稳定。

---

## 12. Performance Goals

- **Cold Startup：** 尽可能快（具体目标可在后续基准测试中确定）。
- **Document Opening：** 即时。
- **Rendering：** GPU。
- No unnecessary allocations.
- No polling.
- Everything event driven.

---

## 13. Project Structure

```text
App
│
├── Swift(AppKit)
│      │
│      ├── Window
│      ├── Menu
│      ├── Animation
│      └── Metal View
│
├── Bridge
│
├── Rust Core
│      │
│      ├── Buffer
│      ├── Layout
│      ├── Theme
│      ├── Undo
│      ├── Event
│      ├── Plugin
│      ├── Lua
│      ├── SQLite
│      └── PTY
│
└── Assets
```

---

## 14. Explicit Non-Goals

本项目明确不追求：

- 跨平台
- Electron
- Web 技术栈
- AI First
- IDE
- 默认集成 Git 面板
- 默认集成终端
- 默认集成项目树
- 默认集成 Marketplace
- 默认集成云同步
- 默认大量 UI

这些能力如果存在，也必须通过插件或用户配置按需启用，而不是默认加载。

---

## 15. Final Design Statement

编辑器启动时，用户面对的不应该是一个 IDE，而应该是一个空白、安静、响应迅速的 Buffer。

整个系统只有一个真正的核心对象：**Buffer / Document**。文件、Scratch、Shell、状态栏、侧边栏、搜索、命令面板，都只是围绕这个核心按需出现的能力，而不是编辑器存在的前提。

所有技术选型都必须服务于这一理念。如果某项新技术或新功能增加了复杂度，却不能强化这一设计目标，应当优先拒绝，而不是默认接受。
