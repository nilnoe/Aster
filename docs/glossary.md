# Glossary — 术语表

本表是项目领域语言的权威定义。文档与代码注释必须与之一致。

| 术语 | 定义 |
| --- | --- |
| Buffer | 编辑器唯一的第一公民：文本内容的容器，可以没有路径。 |
| Document | 与 Buffer 同义的抽象概念，强调"用户打开的是一个文档"。 |
| DocumentManager | Core 中负责 Buffer 注册、生命周期与持久化边界的模块（ADR-001）。 |
| Scratch | 无路径、自动保存到 SQLite 的 Buffer；`Cmd+N` 创建。 |
| Attach Path | 给 Buffer 绑定磁盘路径的行为；语义上不是 "Save As"。 |
| Overlay | 临时出现在 Buffer 之上的 UI（StatusBar、Search、Shell、Command Palette），不是固定布局。 |
| Shell Overlay | 通过 PTY 与系统 Shell 通信的覆盖层；进入时 Buffer 轻微模糊。 |
| PTY | 伪终端，编辑器与系统 Shell 之间的通信通道。 |
| Command | Core 的统一动作入口；键盘、菜单、Lua、命令面板都是 Command 的入口。 |
| Event | Core 向外发出的事件；UI 与插件只订阅、渲染、响应，不反向控制。 |
| Theme | 颜色与样式定义；由 Theme DSL 描述，最终转换为 Lua。 |
| DSL | 面向配置的领域语言；最终都转换成 Lua API，只有一套 Runtime。 |
| Core | Rust 实现的平台无关核心，不允许依赖 AppKit / SwiftUI / NSView / NSWindow。 |
| Bridge | Swift ↔ Rust 的桥接层，基于 swift-bridge（ADR 技术选型）。 |
| 垂直切片 | 穿透 Swift UI、Bridge、Core、测试的最小实现单元（WORKFLOW）。 |
| 复杂度预算 | 宪法 Rule 9：每个 PR 必须回答复杂度三问。 |
