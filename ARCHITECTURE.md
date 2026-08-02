# Architecture — 架构总览

## 分层

```text
App（Swift + AppKit）
  Window / Menu / Animation / Metal View
        │
     Bridge（swift-bridge）
        │
   Rust Core（平台无关）
  Buffer / Layout / Theme / Undo / Event
  Command / Plugin / Lua / SQLite / PTY
        │
      Assets
```

## 核心不变量（来自 ADR / 宪法）

- Rust Core 不依赖 AppKit、SwiftUI、NSView、NSWindow。
- Buffer 是唯一第一公民；文件、Scratch、Shell、Search 都以 Buffer 形态存在。
- 所有 UI 都是可选 Overlay；Core 不依赖任何具体 UI。
- 依赖方向单一：App → Bridge → Core，不允许反向。

## 数据流（按键到渲染）

```text
按键 / 输入法
  → AppKit 层（事件采集）
  → Bridge
  → Core Command 系统
  → Buffer 修改 + Event 发出
  → Layout 更新
  → Render Event
  → Bridge
  → Metal View 渲染
```

UI 动作（菜单、Lua、命令面板）与键盘走同一条 Command 入口；Core 不区分来源。

## 垂直切片的插入点

任何切片都必须穿透这条链路：至少包含 Core 逻辑与对应测试，UI 部分保持薄。
切片清单与顺序见 [docs/roadmap.md](docs/roadmap.md)。
