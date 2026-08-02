# ADR-015 — AppKit 壳（Window / Menu / 空白视图）

- **Status:** Accepted
- **Date:** 2026-08-02
- **Version:** 1.0
- **新增 Public API:** 0（可执行目标，非库；`AppInfo` / `AppMenu` 为内部类型）
- **影响模块:** app/（新增 Swift 包）、bridge/（消费绑定）
- **是否违反 Single Responsibility:** 否
- **是否增加循环依赖:** 否

---

## 决策

新增 `app/` SPM 可执行包（产品名 Aster）：`main.swift` 程序化启动 `NSApplication`（无 xib / storyboard），启动后创建**单个空白窗口**（NSWindow + 空 NSView），并构建最小主菜单：**App**（关于 / 隐藏 / 退出）、**Edit**（标准编辑动作）、**Window**（最小化 / 缩放）。关闭最后一个窗口即退出。

消费 T-010 交付的 `AsterBridge` 绑定：关于面板的版本号来自 `core_version()`（Rust Core），经 App → Bridge → Core 单一路径。

## 原因

- **ADR 总纲 3.1：** UI = Swift + AppKit（SwiftUI 被拒绝作为编辑器核心 UI）；本切片落地总纲的"空白、安静、响应迅速"启动态（启动后只有一个空白窗口，无其他 UI）。
- **Principle 4（Do Not Fight The OS）+ 宪法 Rule 11：** 窗口、菜单、关于面板全部使用系统能力；不造自定义 chrome。
- **程序化而非 xib：** 与"极简、高度可编程"一致；xib 是编辑器不可编程的负担（Rule 9）。
- **版本号单一来源：** App 版本 = Core 版本（`Cargo.toml` 经桥接），避免两处漂移（Rule 9：一份数据源）。
- **菜单最小集：** File / Sidebar / Toolbar / StatusBar 等按项目哲学在后续切片按需加入（T-013 编辑循环加编辑动作接线，T-015+ Overlay）。

## 审计

### Single Responsibility — 否（不违反）

app 包只负责进程启动、窗口与菜单壳；业务逻辑全部留在 Rust Core，UI 保持薄（docs/testing.md）。

### 循环依赖 — 否（不违反）

`app → bridge → core`（依赖方向单一，ADR 总纲分层）。

## 新增 Public API

无（可执行目标）。`AppInfo`（name / version）与 `AppMenu.build(aboutTarget:)` 是内部类型，不构成公共 API（Rule 4 不触发）。

## 影响模块

- **bridge/** — app 作为本地包依赖消费生成绑定与 staticlib（T-010 管线）。
- **T-012（Metal 渲染）** — 空白 contentView 替换为 MetalView。
- **T-013（编辑循环）** — Edit 菜单动作接线到 Core 命令。
- **CI** — ci-swift 增加 app 包的 lint 与 test；Cold Startup 正式基线在 T-020。

## 复杂度预算（宪法 Rule 9）

1. **增加了哪些复杂度？** 1 个可执行包、约 160 行 Swift、0 抽象层（AppInfo / AppMenu 是组织性枚举，非抽象层）。
2. **是否是永久性的？** AppKit 壳是永久结构；窗口 / 菜单按切片增量扩展。
3. **有没有更简单但同样满足需求的方案？** xib / storyboard 更"可视化"但不可编程（Rule 9 拒绝）；SwiftUI 违反总纲 3.1。程序化 AppKit 是最简合规方案。

结论：1 包 / 0 公共 API / 0 抽象层，未触及红线。

## 备注

- **Swift App 规模预算（宪法 Rule 12：app/ ≤ 5,000 行）自此切片生效**；本切片约 160 行。
- 关于面板经 `orderFrontStandardAboutPanel(options:)` 传版本号——系统 UI + Core 数据。
- 窗口内容与菜单动作的接线随渲染 / 编辑切片替换，不预置占位 UI。
- **部署目标（ADR-002 执行）：** app 与 bridge 包 `platforms: [.macOS(.v26)]`（tools 6.2+），且 `bridge/build.sh` 以 `MACOSX_DEPLOYMENT_TARGET=26.0` 编译 Rust C 对象——两端一致，否则链接器报 "built for newer macOS version" 警告。tools 6.0 的 PackageDescription 无 `.v26`。
