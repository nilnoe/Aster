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

## 测试方法论强化（T-051，2026-08-03）

手写场景无法穷尽组合路径（BUG-010/011/012 均藏在单测与 happy path 测不到的
组合里）。T-051 起引入三层补充方法，**以变异测试驱动用例设计**：

1. **变异测试（Mutation Testing）**：向实现注入「常见错误变体」，跑全量测试，
   全绿 = 真实盲区。2026-08-03 首轮 6 个变体结果：合并顺序颠倒（M1）全绿 →
   暴露「保存失败路径」整体无测试；比较反转 / 恢复漏写缓冲 / 取消退出 /
   丢弃不清行（M2~M5）均被既有测试抓到（回归保护有效）。
2. **失败注入测试**：正常路径全绿不代表失败路径正确。用「快照目标被同名目录
   占用」强制 `snapshot_write` 失败，断言：保存失败可见（错误提示）、缓冲行与
   未决状态保留（崩溃保护不因保存失败而丢）、障碍解除后重试成功且快照完整。
3. **状态机不变量测试（属性化）**：固定种子随机操作序列（打开 / 新建 / 编辑 /
   保存）驱动真实 AppDelegate，每步断言守恒不变量（缓冲行集合 == 未决登记
   集合，ADR-013 v1.3；每个未决文档都有快照序号，BUG-011 泛化），终局断言
   保存全部成功且缓冲清空。种子固定保证 CI 确定性；多种子扩展状态空间。

新增用例：`SaveFailurePathTests`（2）+ `SaveStateInvariantTests`（3 种子 × 50 步）。
后续切片新增状态机逻辑时，先跑一轮变异定位盲区，再补对应失败 / 不变量测试。

## IME 契约测试（T-052，2026-08-03）

NSTextInputClient 的协议方法无法用真实输入法在 CI 脚本化，改用**模拟协议调用**
固化契约（BUG-013 / BUG-014 均以 SDK 头文件原文为据）：

1. `characterIndex(for:)` 的 point 是**屏幕坐标系**、返回值是 **UTF-16 字符索引**
   （协议全量区间为 UTF-16 单位，ADR-017 备注）；实现换算顺序 = 屏幕 → 视图 →
   byteOffset → UTF-16。回归测试含真实 NSWindow 的屏幕坐标换算（窗口必须
   `orderFront` 进入窗口服务器，否则 xctest 挂载 MTKView 崩溃）。
2. `setMarkedText` 必须按 `replacementRange`（UTF-16）替换 Buffer 对应区间——
   选中文本输入拼音时组合落在替换位置；组合更新（NSNotFound）不得触碰 Buffer。
3. 修复后再变异复验：还原旧实现跑回归，characterIndex 报 3≠1 / 8≠1，
   确认测试确实抓到旧缺陷（T-051 方法论闭环）。

## 失败可见性测试（T-054，2026-08-03）

失败注入覆盖「正常路径全绿 ≠ 失败路径正确」（T-051 原则的延续）：

1. 缓冲自动保存失败（崩溃保护失效）必须用户可见，但**同一失败段落只提示一次**
   ——目录只读注入写失败后连续两次编辑断言 saveErrorCount 1→1（防逐键弹窗），
   障碍解除成功后复位，再失败断言 1→2（新段落再次提示）。
2. `setupStorage` 失败（ASTER_STORE_DIR 指向普通文件）必须启动即提示（ADR-004），
   且后续保存失败提示必须准确（「存储未就绪」≠「文档没有可合并的快照」——
   存储未就绪与未登记快照是两类失败，guard 拆分）。
3. 提示经既有 `presentSaveError` 接缝注入（测试子类覆写计数 + 记录文本，
   生产路径 NSAlert 为过渡实现，随 T-026 统一为底部 y/n 提示）。

## 状态机不变量扩展（T-058，2026-08-03）

`SaveStateInvariantTests` 的操作空间从 4 类扩展到 9 类：打开 / **同名打开** /
新建 / 编辑 / **undo** / **redo** / 保存 / **丢弃全部** / **崩溃恢复**（恢复与
忽略两分支，`presentRecoveryIfNeeded` 中途播种触发）；种子 3 → 6、步数 50 → 60。
新增不变量 3：**快照序号全局唯一**（BUG-010 泛化）。6 种子 × 60 步全绿 = 保存
状态机对新操作泛化成立（负结果如实记录）；变异复验（还原 BUG-011 修复）seed 7
立即失败——扩展测试保持历史缺陷捕获能力。

## 已知限制契约固化（T-059，2026-08-03）

把「修复前不得漂移」的行为写成契约测试并标注 ADR 限制（对应切片落地时更新断言）：

1. **T-024 前**：打开第二个文件 = 视图切换，前一个文档的未决状态 / 缓冲行 /
   快照序号保留，退出「保存全部」仍覆盖（ADR-013 v1.4 多文档状态全程检查）。
2. **T-029 前**：崩溃恢复只把最新缓冲文档载入视图；其余缓冲文档保持登记未决 +
   快照序号（BUG-011 泛化），退出可一并固化。
3. 契约测试暴露 **BUG-016**：恢复选「忽略」只登记最新文档——修复为遍历全部
   缓冲文档（ADR-013 v1.4 保留规则 3/4：不因忽略而失管、不留「没被问过」的
   文档）；已登记过的保留原快照序号。

## 存储损坏与迁移契约（T-056，2026-08-03）

Core 层契约测试固化 ADR-013 的存储底线：

1. **损坏不 panic**：乱字节 / 合法头 + 截断体的 buffer.sqlite 打开返回
   `Sqlite` 错误（App 侧复用 T-054 提示路径：启动不崩 + 失败可见）。
2. **旧 schema 迁移**：user_version=0 的旧库打开后补齐表（IF NOT EXISTS）、
   迁移锚点推进到 v1、可正常读写。
3. **只读目录**：`open_buffer` 失败干净（非 root 断言；root 不受权限约束）。
4. **多实例**：两个连接打开同一 buffer.sqlite，已提交行跨连接可见（SQLite
   文件锁串行化；App 单线程主 actor 顺序操作，ADR-015）。

## 变异测试工具化（T-062，2026-08-03）

T-051 的手工变异流程（注入变体 → 跑全量测试 → 全绿 = 盲区 → 补测试）脚本化：

- `scripts/mutations.json`：变异点清单（old / new 精确文本 + 目标测试 +
  expected 判定）。当前 5 个确定性变异点：M1 合并顺序颠倒、M2 dirty 比较
  反转、M3 恢复漏写缓冲、M5 丢弃不清缓冲行、M-charIndex 字节偏移回归；
  M6（挂起变体）不可自动化，不纳入。
- `scripts/mutate.py`：自动注入 / 跑目标测试 / 恢复 / 结果记录；`old` 必须
  唯一匹配（漂移即失败，防注入错位置）；退出码 0 = 无盲区存活。
- **每切片门禁**：新增状态机逻辑后先 `python3 scripts/mutate.py` 跑一轮，
  确认没有「全绿变体」= 没有未保护的路径；实测 5/5 全被捕获（~10s）。

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
