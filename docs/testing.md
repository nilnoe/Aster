# Testing — 测试策略

原则：测试先于实现（宪法 Rule 5）；UI 保持薄，可测试逻辑尽可能落在 Rust Core。

## 分层

| 层 | 测试类型 | 覆盖内容 |
| --- | --- | --- |
| Core（Rust） | 单元测试 / 属性测试 | Buffer、Undo、Layout、Theme、Command、Event 等纯逻辑，不依赖 I/O |
| Core（Rust） | 集成测试 | SQLite 持久化、PTY 会话、Lua 宿主 |
| Bridge | 集成测试 | Swift ↔ Rust 往返调用；API 签名与行为契约 |
| App（Swift） | 薄测试 | 仅测抽出的逻辑（T-012 起：输入状态机 / 图集分配器 / 字形图集像素读回 / LineLayout 命中换算；无 GPU 时跳过）；View 层靠手动验证与基准 |
| 性能 | benchmark | 见 [docs/benchmarks.md](benchmarks.md)；每个切片刷新基线 |

## App 集成测试（T-050，2026-08-02）

单测覆盖了 Core 契约、Bridge 往返与 App 纯逻辑，但 **AppKit 生命周期与
App → Bridge → Core 全链路**此前只靠手动验证。T-050 起在 `app/Tests/
AsterAppTests/` 增加进程内集成测试：在 `swift test` 进程内驱动真实
`NSApplication` / `AppDelegate` / `NSWindow` / `MetalView`（不引 XCUITest、
不起子进程、不加依赖；Rule 11 复用系统能力），按层间风险分五组：

1. **启动链路**：`applicationDidFinishLaunching` 真实执行——Store / 缓冲 /
   哨兵初始化、默认 Scratch 文档、onChange 接线、窗口标题。
2. **文档生命周期**：⌘N 建快照文件（日期+序号）、编辑自动写缓冲、⌘S 合并、
   缓冲行删除、空快照退出清理——经 `ASTER_STORE_DIR` 指向临时目录验证真实落盘。
3. **退出流程**：PendingDocs 全覆盖三分支——保存全部 / 全部不保存 / 取消。
4. **崩溃恢复**：伪造非干净哨兵 + 缓冲文档 → 恢复 / 忽略决策，验证内容载回与
   缓冲行生命周期（ADR-013 v1.3 删除时机 2 / 保留规则 3）。
5. **端到端数据流**：合成 `NSEvent` 经 `MetalView.keyDown` 驱动真实按键 →
   Bridge → Core 编辑 → onChange → 置脏 → 缓冲自动保存；无 GPU 时跳过（同
   T-012 守卫惯例）。

### 可测试接缝（实现时最小抽取）

- `AppDelegate` 的退出提示与恢复提示经 `runModal()` 阻塞，测试无法直接驱动。
  抽取两个 internal 方法（`presentRecoveryAlert(count:)` /
  `presentPendingDocsAlert()`）承载模态交互，测试子类覆写返回固定决策；
  生产路径行为不变（Rule 9：两个方法而非抽象层，无协议 / 无依赖注入框架）。
- 存储目录经 `ASTER_STORE_DIR` 注入（既有机制，ADR-023 v1.2 决策 3）；
  测试套件用 `setenv` 指向临时目录，测试间互不污染。

### 执行与门禁

- 与现有 App XCTest 同一 `swift test` 目标，无 GPU 环境的机器自动跳过
  Metal 相关用例（既有守卫模式）。
- 审计行、benchmark 记录、changelog 随切片 DoD 同步（WORKFLOW 第 8 / 9 / 10 步）。

## 规则

- Red → Green → Refactor（宪法 Rule 5）；Bug 回归测试见 [docs/bug-workflow.md](bug-workflow.md)。
- 属性测试用于易漏边界的逻辑（文本操作、布局）。
- 错误路径与 panic 路径必须测试（ADR-004：失败要可见）。
- 性能相关切片必须先建立可复现基线再实现，并在 DoD 报告对比（宪法 Rule 16）。
- Public API 的行为契约（ADR 定义）必须覆盖。
- 测试命名：`<module>_<behavior>`，断言行为而非实现。

## 工具（现状）

- Rust：`cargo test`（单元 + 集成 + 属性测试）、proptest（ADR-022，Buffer / Editor /
  Layout 不变量，见 `core/tests/property.rs`）、criterion（ADR-021 / T-023，性能基线）
- Swift：XCTest + swift-format

分层策略见上表；属性测试覆盖手写用例无法穷举的边界（UTF-8 非边界偏移、任意操作
序列、undo/redo 往返、行结构不变量），随 `cargo test` 在 CI 运行。
