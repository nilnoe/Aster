# Experience — 经验沉淀（Agent Memory）

本文件是项目会话之间的**记忆载体**：沉淀已经踩过的坑、验证过的工作方式、和"别再重新讨论一遍"的决策。它不是规则（规则看宪法），但**每次任务开始前必须读**。

## 项目现状速览（截至 2026-08-03 收工；T-001 ~ T-051 + BUG-010~012 完成；Beta V0.1.2 已发布）

- **代码：**
  - Rust Core：T-001 ~ T-013 + T-023 + T-032 + T-033 + T-035~T-043（buffer /
    selection / history / layout / theme / command / event / lua / store / bridge /
    editor / document_manager / snapshot），`core/src` 共 2182 行，127 个测试全绿（含 7 个
    属性测试，ADR-022 v1.1；T-035 拆分后 fuzz 与基础属性测试为两个二进制）；
    依赖：mlua 0.12（lua54+vendored）、rusqlite 0.40（bundled）、swift-bridge
    0.1.59（build-dep swift-bridge-build）、criterion 0.8.2（dev，ADR-021）、
    proptest 1.11（dev，ADR-022）。
  - bridge/：swift-bridge 绑定 Swift Package（20 个 XCTest 全绿；生成代码与 .a
    不提交，`bridge/build.sh` 是唯一生成入口）。
  - app/：AppKit 壳 + Metal 编辑视图（**86 个 XCTest 全绿**：T-050 五组集成测试 +
    T-051 失败注入 / 状态机不变量 + BUG-010~012 回归），源码 2139 行（Rule 12
    的 Swift 预算 ≤5,000 行生效中）。
- **决策：** ADR-001 ~ ADR-023 全部 Accepted（索引见 `docs/adr/README.md`；
  v1.1 修订：ADR-001 / ADR-006（2026-08-03 数据结构评估进展）/ ADR-013 / ADR-021 /
  ADR-022 / ADR-023）；宪法 V1.4（Rule 13~16：ADR 闭环 / 无消费者不交付 /
  文档机械门禁 / 性能数据驱动）。
- **本会话完成（2026-08-02 晚 ~ 2026-08-03 收工，均已推送 origin/main，工作树干净）：**
  - T-050 App 集成测试套件（520892b）：五组进程内集成测试（启动链路 / 文档
    生命周期 / 退出三分支 / 崩溃恢复 / 端到端 keyDown），App 63 → 78；AppDelegate
    抽取两个提示 seam + 移除 final（docs/testing.md「App 集成测试」）
  - BUG-010/011/012 修复（435e3a0）：多文件打开共享快照序号互相覆盖（数据丢失）、
    崩溃恢复后保存链路断裂（无法保存 / 退出卡死）、undo 回快照内容后假 dirty；
    新增 committedTextByDocId 比较基线；回归测试 BugReproTests 先红后绿
  - T-051 测试方法论强化（b4d1406）：变异测试 6 变体定位盲区（M1 合并顺序颠倒
    全绿 = 保存失败路径无测试）→ 失败注入测试（SaveFailurePathTests）+ 随机
    操作序列不变量测试（SaveStateInvariantTests，3 种子 × 50 步）；App 86 全绿
  - Phase 7 测试专项登记（aed01f8）：T-052~T-062（IME 契约 / 渲染变异 / 失败
    可见性 / 原子写 / 存储损坏 / 时序 / 状态机扩展 / 已知限制固化 / 崩溃完整 /
    跨日轮转 / 变异工具化）——用户将专门投入测试，执行原则 = 先变异定位盲区
  - 数据结构评估落地（34ca7e5，ADR-006 v1.1）：4 项热点 / 基准缺口（App 每键
    全量文本流、Core 移动全量重建、中间编辑基准缺口、History 空间）+ Phase 8
    T-063~T-066（基准扩展 / move 缓存 / 自动保存节流（需用户确认）/ WAL）
  - T-034 审查问题登记（440c75b）：docs/issues.md（I-001~I-008）+ Phase 6 切片排期
  - T-035 Up/Down 边界修复（29bdf9d，BUG-008）：floor_char_boundary 钳制 + Up/Down
    纳入属性差分 + 边界不变量（PROPTEST_CASES=3000 通过）；property.rs 拆 support
  - T-036 存量清理（6ceb0fe）：撤销 Selection::clamp（ADR-007 v1.1）、计数校正、
    T-032 hash 回填；I-006 核验为误报（.DS_Store 从未入库）
  - T-037 Disk 保存（135f44a，ADR-023）：save_text + Bridge FFI + 菜单 ⌘S +
    dirty 标题 + 关闭保护
  - T-038 渲染数据路径重构（7220747）：缓存行结构、每帧单次 shaping、二分定位
  - T-039 审计与门禁加固（3171806）：CI-Docs 审计完整性机械检查（未回填 ≤1 +
    hash 全存在）+ CI-Release 门禁对齐（app/Sources lint、fuzz、规模预算、docs、
    基准回归）
  - T-040 保存改为 SQLite 快照（d28cb9b，ADR-023 v1.2）：用户确认反转 T-037 磁盘
    写回——Cmd+S 每次保存新建「日期+序号」文件（单日多版本，Store::open_next /
    open_latest）；撤销 save_text（Rule 14）
  - T-041 缓冲 + 快照保存模型（c4b4710，ADR-023 v1.3）：Cmd+N 建快照 / 内容变更
    自动写 buffer.sqlite（崩溃保护）/ Cmd+S 合并缓冲 → 当前快照；修复 BUG-009
    （默认 Buffer onChange 未接线 → 无 dirty ● / 退出保护）
  - T-042 快照改为纯文本（b8cd54b，ADR-023 v1.4）：快照 = `.txt` 文本文件（Buffer
    可打开），SQLite 仅作缓冲；新增 snapshot 模块
  - T-043 崩溃恢复 v1（cab4045，ADR-013 v1.1）：clean_exit 哨兵 + 启动检测 +
    恢复提示（载回缓冲文档）
  - T-044 SQLite 保留论证（7a1408d，ADR-013 v1.2）：文档 = 文本 / SQLite = 内部
    状态边界 + 三条保留论据 + 拆除条件；决议保留
  - T-045 缓冲生命周期（8dacfff，ADR-013 v1.3）：保留 = 未提交且未明确丢弃；
    删除 = 合并 / 恢复 / 不保存三时机；AppDelegate 与 bridge.rs Rule 3 拆分
  - T-046 多文档状态全程检查（5ac474c，ADR-013 v1.4 / ADR-023 v1.5）：
    PendingDocs 登记全部未决；退出覆盖全部（保存全部 / 全部不保存 / 取消）；
    无模态弹窗原则（底部 y/n 随 T-026）
  - T-047 空快照退出清理（80adf3c，ADR-023 v1.6）：干净退出删零长度 .txt 快照
  - T-048 发版 CI 检查修复（86d456a）：clippy 1.97 新 lint / CI-Bench 结果目录 /
    版本断言格式校验（ADR-021 v1.2）
  - T-049 CI-Bench 稳定性（a55ba64，ADR-021 v1.3）：median + 阈值 200%
  - T-018 水平滚动 + 前置拆分（47c1dc2）：新增 `Viewport` / `MetalView+Input.swift` /
    `VertexBuilder.swift`（Rule 3 拆分）；随后 BUG-006 光标边缘留白（98cfb30）、
    BUG-007 组合期间横向滚动（1d7dfe7）——均带回归测试
  - T-015 文件打开接线（e6a7ebd）：File 菜单「打开…」+ 拖放，DocumentManager
    首次进产品（ADR-001 v1.1，Bridge FFI 3 项）
  - T-033 fuzz + 基准回归告警（9a60b08）：CI-Bench 作业 + `bench-baseline/`
    （17 项基线）+ `scripts/bench-regression.py` + 2 个 fuzz 属性测试
    （ADR-021 / ADR-022 v1.1）
  - 审计 hash 回填：794f5f6 / 0c5f8d3 / 27a86a3 / f4d2fba / b760698
- **下一任务：** T-014 剪贴板（方向见 ADR-018：深浅色不跟随系统，主题由 Lua 提供；
  系统 NSPasteboard，Principle 4；粘贴 = 选区替换 `type_text` 路径，ADR-017）→
  随后 T-019 软换行（默认关，视觉折行属 App 渲染层）。
- **审计纪律（T-039 起机械强制）**：audits.md 的 Commit 列不得累积「本切片」
  （CI-Docs 检查 ≤1 行且 hash 真实存在）；审计行必须含行为证据。**提交前先本地
  模拟门禁**：`grep -cE '\| 本切片 \|' docs/audits.md` 必须 ≤1。
- **版本：** Beta 阶段，当前 **Beta V0.1.2**（core `0.1.2` 单一来源，三处同步：
  Changelog / 应用版本（core_version）/ git tag）。模板 `Beta V0.0.0`（末位补丁 /
  中间位功能 / 首位恒 0）。**发布 = 打 `Beta-V*` tag 推送，CI-Release 自动门禁 +
  打包 Aster.app zip + 附到 Release（ADR-020）**。V0.1.2 按所有者指定为补丁号
  （功能周期按策略应为 V0.2.0，差异已记录于 Changelog）。
- **远程：** remote 名是 `origin`（`git@github-nilnoe:nilnoe/Aster.git`），SSH 别名 `github-nilnoe` 在 URL 中；**不要**把别名当 remote 名用（T-006 踩过）；不要用 `github.com` 入口。
- **部署目标：** macOS 26（ADR-002）：app/bridge manifest `platforms: [.macOS(.v26)]`（swift-tools-version 6.2+）+ `MACOSX_DEPLOYMENT_TARGET=26.0` 编译 Rust C 对象，两端必须一致。

## 工作方式（验证有效，继续保持）

- 每个切片严格走 WORKFLOW 11 步；**顺序不可跳**：ADR → 测试（Red）→ 实现 → 门禁 → 审计 → 文档。
- 审计必须留痕：每切片在 docs/audits.md 追加一行（含违规与处置），无记录视为未执行（ADR-022）。
- 公共 API 必须先 ADR（宪法 Rule 4）；不建 Trait / 抽象层，除非有证明（Rule 1 / 2）。
- 切片完成时一次性更新：Roadmap 状态、Changelog、ADR 索引、Benchmarks——这四件套是 DoD 的一部分，容易忘。
- Commit 用 Conventional Commits 并引用 `T-XXX` 与 `ADR-XXX`；每个切片独立 commit + push。
- 遇到"未确定项"直接进实现 = 违规：未确定项清单在 ADR-006，必须先更新 ADR。
- 宪法（docs/constitution.md）不可由 agent 自行修改；修订需用户确认。
- 沙箱环境：git 写 `.git` 需要提权（`require_escalated`）；既有依赖构建本地可用，**新增依赖首次构建需联网**（沙箱内 `cargo add` / 首次 `cargo test` 需 `require_escalated`）。
- **多包构建链**：`core/`（Rust）→ `bridge/`（绑定包）→ `app/`（AppKit）。改动 core / bridge.rs 后必须先 `./bridge/build.sh`（cargo build --release + 复制绑定 / staticlib / lua / sqlite）再 `swift test`；CI-Swift 作业第一步行同一脚本。
- **Swift 门禁现状**：`swift-format lint --recursive app/Sources bridge/Tests app/Tests` + `swift test`（bridge、app 两个包分别跑）；生成绑定（bridge/Sources）不 lint，手写的 app/Sources 必须 lint（CI 已覆盖）。
- 需要运行 GUI（app 启动验证）时用短时后台运行 + kill 抓 stderr，别长时间驻留。

## 技术经验（Rust / Clippy / 测试）

1. **`#[expect(dead_code)]` 与测试构建冲突**：字段被单元测试读取时，`expect` 在 `cargo test` 下报"unfulfilled"。解法：`#[cfg_attr(not(test), expect(dead_code))]`（T-002 踩过）。
2. **clippy `new_without_default`**：提供 `new()` 的公开类型会被 lint 要求补 `Default`。零成本惯例，直接实现并注释理由。
3. **返回刚 push 的值触发 E0382**：undo/redo 把 op push 进栈又想返回它——栈 push `op.clone()`，返回原值；理由是"非热路径，不为零拷贝优化引入复杂度"（Rule 9 精神）。
4. **跨模块类型从定义处导入**：`BufferError` 从 `crate::error` 导入，不要试图从 `crate::buffer` 转发导入（那只是私有 `use`，会报 E0603）。
5. **合并规则会干扰 LIFO 测试**：History 的相邻 Insert 合并会让"连续 insert"测试意外合并成一步。用**前插**（`at: 0`）构造非相邻 op，LIFO 语义才能独立验证（T-004 踩过）。
6. **测试失败先怀疑测试自身**：T-004 两个失败全是测试 bug（buffer 初始化误删、未意识到合并规则），不是实现 bug。断言前先检查前提。
7. **集成测试只能看公共 API**：私有状态验证放 crate 内单元测试。当前策略：公共契约走 `core/tests/`，内部状态走 `#[cfg(test)] mod tests`。
8. **有序向量二分**：用 `Vec::partition_point`（Layout::line_at 的解法）。
9. **CI 按语言拆分**：Rust 与 Swift 门禁放在两个 workflow，用 `paths` 过滤——避免只改 core 时 Swift 作业误红（代码没落地前尤其重要）。
10. **`Box<dyn Fn>` 字段触发 clippy type_complexity**：`HashMap<String, Box<dyn Fn(...)>>` 或订阅表这类存储直接报"very complex type"。解法：**私有类型别名**（`type CommandHandler = Box<dyn Fn(...)>`）——不公开就不构成公共 API（Rule 4），无需 ADR（T-007 踩过）。
11. **mlua 0.12 API 速记**（T-008）：`Lua::new()` 不可失败；`create_function` 回调签名是 `Fn(&Lua, A) -> Result<R>`（闭包须标注 `&Lua` 参数）；`Table::sequence_values` / `pairs` / `raw_len` 可用；从 Lua 侧回调进入 Lua 会 panic（先存表后显式桥入，勿在回调内再调 Lua）。
12. **clippy `new_without_default` 只对无参返回 `Self` 的 `new()` 触发**：返回 `Result<Self, _>` 的构造器不会触发——**不要**为它手写含 `expect` 的 `Default`（panic 违反 ADR-004；T-008 先加了后移除）。
13. **rusqlite API 注意**（T-009）：`u64` 不实现 `FromSql` / `ToSql`（读写一律 `as i64` 转型）；`Connection` 不实现 `Debug`（手动 impl 输出 `conn.path()`）；`unwrap_err` 要求 `Store: Debug`。
14. **rusqlite 0.40 默认特性会引入 wasm 相关依赖**：`cargo add rusqlite --no-default-features --features bundled` 收窄依赖树（默认特性含 `ffi-sqlite-wasm-rs` / `cache` 等，编辑器不需要）。
15. **swift-bridge 0.1.59 集成要点**（T-010）：
    - `parse_bridges` 接收路径**集合**（`["src/bridge.rs"]`），不是单路径；方法需显式 `self: &T` / `self: &mut T`。
    - 桥接已存在的 payload 枚举（`already_declared`）要手写 `SharedEnum` + repr(C) FFI 类型——即手写 FFI 胶水，违反总纲 3.4，**规避**（错误用 String 传递）。
    - `Result<T, E>` 返回 + `&str` 参数组合生成的 Swift 无法编译（throwing closure 传非 throwing 参数）——改用 `String` 参数规避。
    - 生成的 C 头（modulemap）顺序必须 `SwiftBridgeCore.h` 在前（定义 `RustStr`），`aster_core.h` 在后。
    - **Rust staticlib 不向 Swift 链接器传播传递静态依赖**：mlua vendored 的 `liblua5.4.a` 与 rusqlite bundled 的 `libsqlite3.a` 需在 Swift 包显式 `-llua5.4 -lsqlite3`（build.sh 里 find + 复制）。
    - Swift C importer 会把 `__swift_bridge__$*` 符号名改名成 `___swift_bridge__$*`（3 下划线），Rust 导出与 Swift 引用天然一致，无需处理。
    - manifest 的 `#filePath` 可能丢前导斜杠；`-L` 必须保证绝对路径。
16. **SPM 跨包消费要点**（T-011）：依赖包必须声明 `products: [.library(...)]` 才能被消费；`.product(name:package:)` 的 `package` 参数是**目录名**（如 `bridge`）而非包内 name；`@testable import` 可测试 executable target（Swift 5.5+）。
17. **Swift App 规模预算自 T-011 生效**：app/ 源码计入宪法 Rule 12（≤5,000 行）；AppKit 壳保持 ~160 行，新 UI 切片需持续记账。
18. **部署目标必须两端一致**（T-011 修复）：Rust C 对象（mlua/rusqlite 的 vendored/bundled C）默认按 SDK 版本编译，Swift 包部署目标较低时产生 30+ 条 `built for newer macOS version` 链接警告。解法：manifest `platforms: [.macOS(.v26)]`（需 swift-tools-version 6.2+）+ `MACOSX_DEPLOYMENT_TARGET=26.0 cargo build`；改 env 后需 `cargo clean`（cargo 不跟踪 env 变化，且 Lua 由 **lua-src** 的 build script 编译，清理要打中它）。
19. **swift-bridge 生成 Swift 的 Swift 6 警告**（T-011 修复）：生成的 `SwiftBridgeCore.swift` 有 retroactive conformance 警告（RustStr: Identifiable/Equatable），上游不支持 `@retroactive`；该目标只含生成代码，加 `swiftSettings: [.unsafeFlags(["-suppress-warnings"])]`（注意 swiftSettings 里**不要**再带 `-Xswiftc` 前缀）。

## 架构决策速查（勿重新讨论，除非出现新数据）

| 主题 | 现状 | 替换 / 决策触发点 |
| --- | --- | --- |
| 文本存储 | `String`（Buffer 内部实现细节） | 基准已建立（benchmarks.md，T-023 / ADR-021）；是否换 Rope/Gap 由 ADR-006 门禁 + 用户确认 |
| 行索引 | 不可变快照 `Layout`，编辑后调用方重建 | 随存储一起替换（T-023 基准后），接口不变 |
| 软换行 | 用户可选、默认关闭；默认按行渲染 + 水平滚动（ADR-019） | 配置系统（Lua/Config DSL）切片落地后经配置开启 |
| 水平滚动 | 已落地（T-018，ADR-019）：`Viewport` 持有 scrollX/scrollY + 钳制 + 光标可见性；触控板双指 / Shift+滚轮（macOS 事件层自动交换轴向）；内容宽度 = 可见行最大宽度 | 平滑滚动动画随 T-022 |
| 行分隔符 | `\n` 唯一；`\r` 暂为行内容 | CRLF 归一化在文件模型切片 |
| Undo | 内存 inverse-operation 栈 + 相邻 Insert 合并 | SQLite 持久化边界在 T-029（Crash Recovery） |
| 多光标 / mmap | 未定 | T-023 基准后定 |
| 插件信任 | 默认信任，不沙箱 | 引入插件市场时重估（ADR-003） |
| macOS | 仅最新版，零兼容负担 | 永久（ADR-002） |
| 遥测 | 默认无，显式开启 | 永久（ADR-004） |
| Lua 宿主 | mlua 0.12（lua54 + vendored） | 插件线程化时重估 Send/Sync（T-008 已评估） |
| Bridge 构建 | swift-bridge 0.1.59 + `bridge/build.sh`；staticlib + lua/sqlite 传递依赖显式链接进 Swift 包 | swift-bridge 升级（major）另走 ADR（依赖政策） |
| AppKit 壳 | 程序化 AppKit（无 xib），最小菜单 App/Edit/Window；部署目标 macOS 26 | T-012 换 MetalView；T-013 菜单接线编辑循环 |
| 文本渲染 | CoreText shaping（CTLine/CTRun）→ 字形图集（RGBA8 按需栅格化，font+像素尺寸+glyph 键）→ Metal quad（32B/顶点）；IME = 系统 NSTextInputClient；行结构复用 Core Layout（bridge `layout_line_starts`） | 按需整帧重建（增量失效未做）；sRGB+gamma 在 T-016；颜色接 Theme 由 Lua 主题切片提供（ADR-018） |
| CI 发布 | `CI-Release`：打 Beta-V* tag → 门禁 + 构建 + 打包 Aster.app zip + 附到 Release（ADR-020）；手动 dispatch 在 main 上只验证到 artifact 步骤 | 签名/公证在 V1.0.0 前按需评估 |
| 基准体系 | 本地 release 全量测量（T-023，ADR-021）；`CI-Bench` 用 `--quick` + `bench-baseline/`（提交基线）做粗告警（v1.3：median 对比 + 阈值 200% / 下限 100µs——共享 runner 噪声最高 +120%，100% 仍偶发误报；精确回归以本地为准） | 阈值再误报时调整并记录（ADR-021 v1.3 备注 1）；基线随机器 / macOS 变化重新生成提交；本地命令 `cd core && CARGO_TARGET_DIR=target cargo bench` |
| 深浅色 | 固定深色启动态，不跟随系统 appearance；主题可编程能力由 Lua 提供（ADR-018） | Lua 主题切片（ADR-010 Theme 模型已就绪） |
| 编辑会话 | Core `Editor`（Buffer+Selection+History 协调者，ADR-017）：type/delete/move/undo/redo/selectAll/setSelection；IME 组合文本内联光标处；滚动是视图状态 | 命令上下文 / 激活文档随 T-024（Command Palette）；剪贴板 T-014 / 拖放 T-015 |
| DocumentManager | 首次进产品（T-015，ADR-001 v1.1）：File 菜单「打开…」与文件拖入统一经 `open(Disk)`；Bridge FFI 3 项（id 以 usize 透传）；注册表 Buffer 副本与编辑会话分离（激活文档统一归属随 T-024，Rule 9 边界） | 激活文档 / 命令上下文随 T-024；Scratch 工作流 T-028 |
| 保存 | 双文件模型（T-042，ADR-023 v1.4）：Cmd+N 建「日期+序号」**纯文本**快照（`aster-YYYY-MM-DD-<seq>.txt`，Buffer 可打开）；内容变更自动写缓冲 `buffer.sqlite`（SQLite 崩溃保护）；Cmd+S 合并缓冲 → 当前快照（提交）；dirty「●」= 缓冲 ≠ 快照；默认目录 `~/Library/Application Support/Aster`（`ASTER_STORE_DIR` 覆盖） | 磁盘写回（用户指定路径）Deferred 到未来文件系统切片；保留期 / 自动清理随配置系统；T-028 读回 latest 恢复会话 |
| 保存（BUG-010/012 修订，435e3a0） | **每个打开的文件分配独立快照序号**（不再继承当前文档序号，多文件保存互不覆盖）；`committedTextByDocId` 记录各文档最近一次合并进快照的文本——undo/redo 回快照内容时不再标记未保存（内容比较基线，非「发生编辑即脏」）；合并成功**先写快照再删缓冲行**（顺序不可颠倒，快照写失败必须保全缓冲行，T-051 变异验证） | 自动保存节流（合并连续按键）已排 T-065，**反转 ADR-023「每次内容变更写入」粒度需用户确认**；快照合并写非原子属已识别改进（T-055 原子写） |
| 崩溃恢复 | v1（T-043，ADR-013 v1.1）：缓冲 `meta.clean_exit` 哨兵（正常退出 true / 启动清 false）；启动时哨兵非干净且有缓冲文档 → 「恢复最近一个」提示；恢复载回缓冲内容并置脏，Cmd+S 合并进新快照 | 多文档会话 / 窗口状态完整恢复在 T-029（剩余部分）；恢复内容未合并前仍在缓冲（崩溃不丢） |
| SQLite 角色 | 边界（T-044，ADR-013 v1.2）：文档 = 文本文件（快照 .txt）；SQLite = 编辑器内部状态（缓冲 / session / 最近文件 / 工作区 / undo 持久化），永不混用；三条保留论据（崩溃保护事务性写入 / 多文档缓冲 / 总纲 §5 既定路线） | 拆除条件：砍掉会话 / 最近文件 / 工作区 / undo 路线时按 ADR 反转拆 rusqlite；session 表不许悬挂（T-029 消费）；快照原子写为已识别改进未排期 |
| 缓冲生命周期 | 规则（T-045，ADR-013 v1.3）：保留 = 未提交且未明确丢弃（崩溃后 / 忽略 / 干净退出不删数据）；删除 = ⌘S 合并成功 / 恢复载入 / 退出「不保存」三时机；不变量：缓冲行存在 ⟺ 存在未决编辑 | 多文档未决行的完整清单随 T-029；恢复 v1 只呈现最新一个（其余行是「未决」的守恒结果，不是 bug） |
| 缓冲生命周期（BUG-011 修订，435e3a0） | 崩溃恢复分支**必须先把恢复内容写入缓冲**（新 id 的 scratch 行）再删旧行，否则 ⌘S / 保存全部读不到内容；**其余未决缓冲文档逐个登记快照序号并置未决**（否则退出「保存全部」找不到合并目标而卡死） | 恢复 v1 仍只呈现最新一个（T-029）；恢复内容在内存 + 缓冲双份（崩溃保护） |
| 多文档状态 | 全程检查（T-046，ADR-013 v1.4）：PendingDocs 登记所有未决文档（切换 / 打开新文件不抛弃前一个）；退出提示覆盖全部未决（保存全部 / 全部不保存 / 取消）→ 干净退出后缓冲清空；缓冲 = 强杀 / 意外退出边界专用 | 未来：无模态弹窗（ADR-023 v1.5）——StatusBar overlay 底部 y/n 提示（T-026）替代过渡期 NSAlert；多文档逐个处置 UI 随 T-026 / T-029 |
| 空快照清理 | 退出清理（T-047，ADR-023 v1.6）：进程干净退出删除内容为空的 `aster-*.txt`（启动即建 / 从未合并的空文档不累积）；只删零长度，崩溃退出不清理 | 保留期 / 非空旧文件自动清理属未来配置切片 |

## 踩坑记录（可追加）

| 日期 | 切片 | 问题 | 解法 |
| --- | --- | --- | --- |
| 2026-08-02 | T-050 | 测试子类覆写 AppDelegate 提示方法报 "does not override"：① 方法在 extension 里（Swift 不允许跨模块覆写 extension 方法，须声明在类体）；② 覆写返回类型 `Int?` 与基类 `Int` 不匹配（override 必须同返回类型）；③ AppDelegate 是 `final class`（测试不能子类化） | 两个 seam 方法（`presentPendingDocsAlert` / `presentRecoveryAlert`）抽为类体 internal 方法；返回类型统一 `Int?`（nil = 取消）；移除 `final`（编译期优化非架构约束，docs/testing.md 记录依据） |
| 2026-08-02 | T-050 | swift-bridge 的 `Result<String, String>` 抛出的错误是 `RustString` 对象：`XCTAssertThrowsError` 里 `"\(error)".contains(...)` 拿不到消息文本 | 断言用 `(error as? RustString)?.toString().contains(...) == true`（ADR-014 桥接惯例延伸：错误消息也要 toString） |
| 2026-08-02 | T-050 | 测试经独立 SQLite 连接播种，AppDelegate 连接读不到（跨连接可见性依赖提交时序） | 播种必须经被测对象持有的同一连接（`appDelegate.bufferStore`），或独立连接写完即释放再启动（恢复测试：launch 前无连接，独立连接落盘后释放） |
| 2026-08-02 | T-050 | 集成测试启动即崩（Fatal error: nil）：`NSApp` 在测试进程为 nil | setUp 先 `_ = NSApplication.shared` 实例化共享应用（不启动 run loop）；真实 `applicationDidFinishLaunching` 才能执行 |
| 2026-08-02 | T-050 | `@MainActor` 标注的 XCTestCase 里 override `setUp()/tearDown()` 报不同 actor 隔离（XCTest 基类非隔离） | 类级 `@MainActor` 已让成员隔离，不要再给 setUp/tearDown 单独加标注（冗余标注反而编译错） |
| 2026-08-02 | T-050 | `typeText` 在光标处插入（默认光标 = 字节 0）："输入 + 默认内容"而不是"默认内容 + 输入"；`snapshotFiles` 断言没过滤 `buffer.sqlite` | 断言先推演光标语义：先 `move(.docEnd)` 再输入；目录断言只取 `aster-*.txt` 前缀（测试失败先怀疑测试，老教训再次应验） |
| 2026-08-02 | BUG-012 | 回归测试「undo 回到快照内容」一直红：`typeText("X")` 后 `typeText("Y")` 是相邻追加 Insert，History 合并成一步，一次 undo 撤掉的是整个 "XY" 而非 "Y"（T-004 老坑重现） | 用选区替换（selectAll + typeText）构造 Replace op（单独成步不合并），一次 undo 恰好撤掉单次编辑；构造 undo 场景前先推演 History 合并规则 |
| 2026-08-02 | BUG-010~012 | 「保存全部互相覆盖」「恢复后无法保存/退出」「undo 假 dirty」三个 bug 都藏在集成测试的**组合路径**里（多文件打开、多未决文档+恢复、保存后 undo）——单测与单文档 happy path 都测不到 | 缺陷狩猎从「跨文档状态机」入手：snapshotSeqByDocId / pendingDocs / committedText 三个映射的一致性就是保存链路的全部风险面；每个候选先写复现测试再改代码 |
| 2026-08-03 | T-051 | 手写场景永远追不上边界组合——变异测试首轮 6 个变体暴露「保存失败路径」整体盲区（合并顺序颠倒全绿） | 用变异测试定位盲区再补测试：失败注入（快照目标被目录占用强制写失败）+ 随机操作序列不变量（固定种子 LCG，每步断言缓冲行 ⟺ 未决守恒）；变异注入后必须逐项 diff 核对恢复（M1/M2 恢复补丁未对齐导致残留变异 + 6 个假失败） |
| 2026-08-02 | T-002 | `expect(dead_code)` 在测试构建报 unfulfilled | `#[cfg_attr(not(test), expect(dead_code))]` |
| 2026-08-02 | T-002 | clippy `new_without_default` | 实现 `Default` 并注释理由 |
| 2026-08-02 | T-004 | 返回 push 后的 op 触发 E0382 | 栈存 clone，返回原值 |
| 2026-08-02 | T-004 | 连续 insert 测试被合并规则干扰 | 用前插构造非相邻 op |
| 2026-08-02 | T-004 | 测试失败实为测试 bug | 先自查测试前提与合并语义 |
| 2026-08-02 | T-006 | `git push github-nilnoe` 报 not a repository | remote 名是 `origin`，SSH 别名 `github-nilnoe` 只存在于 URL（`git@github-nilnoe:...`）；`git remote -v` 确认后用 `git push origin main` |
| 2026-08-02 | T-008 | `matches!(err, Variant(msg))` 后 format `{err:?}` 报部分移动 | 用 `matches!(&err, ...)` 匹配引用，不移动 `err` |
| 2026-08-02 | T-009 | rusqlite `row.get::<u64>()` 编译失败 | 存储层以 i64 读写，读取时 `as u64` 转型 |
| 2026-08-02 | T-010 | swift-format 默认 2 空格，手写测试 4 空格被 lint 警告 | `swift-format format --in-place` 格式化；生成绑定不 lint |
| 2026-08-02 | T-010 | 链接报 `___swift_bridge__$*` 符号缺失 | 非符号问题，是 `-L` 路径丢前导斜杠（#filePath）或未链 Lua/SQLite 静态库 |
| 2026-08-02 | T-011 | `swift run` 30+ 条链接警告（built for newer macOS） | 部署目标不一致：manifest `.v26` + `MACOSX_DEPLOYMENT_TARGET=26.0`；改 env 后必须 `cargo clean --release`（cargo 不跟踪 env，Lua 由 lua-src 编译） |
| 2026-08-02 | T-011 | 生成 Swift 的 Swift 6 retroactive conformance 警告 | 生成代码目标加 `swiftSettings: [.unsafeFlags(["-suppress-warnings"])]`（不带 -Xswiftc 前缀） |
| 2026-08-02 | T-011 | `.product(name:package:)` 报 unknown package | `package` 参数用目录名（`bridge`）而非包内 name；依赖包需声明 `products: [.library(...)]` |
| 2026-08-02 | T-012 | `CTRunGetFont` 未导出到 Swift（macOS 26 SDK） | 经 `CTRunGetAttributes` 取 `kCTFontAttributeName`（含 cascade fallback 字体，CJK → PingFang） |
| 2026-08-02 | T-012 | `NSTextInputClient` 在 SDK 为函数式协议（`selectedRange()` 等）且非 MainActor 隔离 | 用方法形式实现；conformance 声明 `@MainActor NSTextInputClient`（隔离 conformance，Swift 6.2 #ConformanceIsolation）；`doCommand(by:)` 需 `override`（NSResponder 已有同名方法） |
| 2026-08-02 | T-012 | swift-bridge `Vec<usize>` 生成 `RustVec<UInt>` 而非 `[UInt]` | Swift 测试用 `Array(...)` 包装；App 侧可直接当 Collection 用（下标 / count） |
| 2026-08-02 | T-012 | `XCTAssertEqual(len, text.utf8.count)`（UInt vs Int）触发编译器 "failed to produce diagnostic" | 显式 `UInt(text.utf8.count)`；bridge 返回的 usize 一律当 UInt 处理 |
| 2026-08-02 | T-012 | CGBitmapContext 内存行序与 Metal 纹理行序的坐标映射 | 默认上下文 y 向上：纹理行 r ↔ 用户 y = H - r；字形放进图集矩形 (x,y,w,h) 后基线 y = H - y - h - bounds.minY；用像素测试（读回纹理）验证，别凭直觉 |
| 2026-08-02 | T-012 | app 测试 target 直接写 `AsterBridge` 依赖名报 not found | 跨包产品必须 `.product(name: "AsterBridge", package: "bridge")`；裸名只对同包 target 有效 |
| 2026-08-02 | BUG-001 | Retina 下文本渲染模糊：图集按 pt 栅格化而 quad 按 px 绘制，2× 线性放大 | 图集按像素尺寸栅格化（`CTFontCreateCopyWithAttributes` 按 scale 缩放），键含 pixelSize；quad 吸附像素网格 + nearest 采样；回归测试断言 2× 图集矩形 > 1× |
| 2026-08-02 | T-013 | 编辑测试三连失败全是测试 bug（光标初始在 0、UTF-8 字节数算错、列语义算错） | 再次印证"测试失败先自查测试"；断言前先推演光标状态与字节区间 |
| 2026-08-02 | T-013 | `XCTAssertEqual((Int, Int), ...)` 编译报 tuple 不 Equatable | 拆成两个单值断言 |
| 2026-08-02 | T-013 | `undo(_:)`/`redo(_:)` 加 override 报"does not override"；`selectAll(_:)` 不加报"requires override" | NSResponder 无 undo:/redo: 方法（菜单用字符串 Selector），但有 selectAll:；分别对待 |
| 2026-08-02 | T-013 | IME 区间单位混用：selectedRange/markedRange 的 location 是 UTF-16，Core 光标是字节 | 一律经 EditorModel 的 `utf16Range(fromByteRange:)` 换算；组合文本的 markedRange 用 displayText 前缀长度计算，不能直接拿 Buffer 字节 |
| 2026-08-02 | T-013 | 选区替换需要"一步撤销"：Insert+Delete 两条记录要按两次撤销 | `EditOp::Replace { at, end, deleted, text }`：保存被删文本，逆操作自足（ADR-008 原则）；History 合并规则不受影响 |
| 2026-08-02 | T-013 | swift-bridge 枚举桥接（Movement）有 already_declared 手写 FFI 风险 | 桥接面拆成 8 个方向函数（`editor_move_left` 等），Core 保留 Movement 枚举供 Rust/测试使用 |
| 2026-08-02 | T-013 | TextRenderer 达 303 行超 Rule 3 | 拆出 `MetalPipeline.swift`（shader/管线/采样器）；渲染顶点生成与管线资源分离 |
| 2026-08-02 | T-013 | 方向键用 selector 名（moveLeft: 等）脆弱，且 doCommand 只收到部分 | keyDown 按 keyCode（123-126/51/36/53）+ modifierFlags 直连，普通字符与 IME 仍走 interpretKeyEvents |
| 2026-08-02 | BUG-002 | 光标 / 选区 / IME 下划线不可见：白像素画在用户 y=0，落在纹理**最后**一行，UV 采样纹理行 0 全是透明 | CGBitmapContext 默认 y 向上：纹理行 r ↔ 用户 y = H - r；纯色像素必须画在用户 y = H-1..H（`fillWhite` 用 `H - rect.maxY` 换算用户坐标） |
| 2026-08-02 | T-017 | 离屏渲染读回为脏数据 / 全零 | ① 离屏纹理格式必须与管线 color attachment 一致（bgra8Unorm，否则整帧被丢）；② `renderOffscreen` 提交后必须 `waitUntilCompleted` 再 `getBytes` |
| 2026-08-02 | T-017 | 渲染像素测试假阳性：扫描区与文本字形重叠，把字形像素当光标 | 光标用"贯穿行高的竖直线"判据（>20 行白色），字形墨迹仅 ~11 行；断言前先算坐标 |
| 2026-08-02 | BUG-003 | 拼音按回车不提交：keyDown 对 keyCode 36 无条件直连 typeText("\n")，组合被清空、IME 拿不到回车 | 组合激活期间所有按键交还 interpretKeyEvents（IME 拥有键盘，Principle 4）；数字键选词正常正是走默认分支的证据 |
| 2026-08-02 | CI | Beta V0.1.0/V0.1.1 压缩包均为手动打包上传；CI 只有门禁无打包 job | ADR-020 流水线化：tag 触发 CI-Release（门禁 → 构建 → 打包 → 附 zip）；dispatch 模式可验证到 artifact 步骤 |
| 2026-08-02 | BUG-004 | 组合期间光标画在组合起点，不跟随拼音 | 组合内联于光标处，光标应画在 cursor + composition 长度处（同一行，无换行） |
| 2026-08-02 | T-013/IME | "拼音按回车得到英文字母" 是 macOS 系统输入法固有行为（回车提交原始拼音，空格/数字确认汉字），TextEdit 同样如此，非我方 bug | 不要"修复"它（改 = 重实现 IME，违反 Principle 4）；如需回车确认候选，用户侧换第三方输入法（如 Rime） |
| 2026-08-02 | T-017 | 渲染像素测试崩溃 SIGTRAP：`r + 100`（UInt8 255+100）算术溢出 | 像素比较先转 Int；又是测试自身的问题（"测试失败先怀疑测试"） |
| 2026-08-02 | BUG-005 | 文本区鼠标指针是箭头而非 I 型 | `resetCursorRects` + `addCursorRect(bounds, .iBeam)`（系统能力，Principle 4） |
| 2026-08-02 | 复审 | 文档漂移漏检：ADR 索引漏登 ADR-018（changelog/roadmap 却反复引用）；experience 现状速览行数/测试数过期 | 本次补索引、校正行数；长期靠 CI 文档完整性检查（已列入修复 TODO） |
| 2026-08-02 | T-023 | criterion bench 二进制显示 running 0 tests（libtest 壳吞掉 criterion main）；闭包内 RefCell borrow 临时值悬垂（E0716） | `[[bench]]` 显式声明 `harness = false`；借用先 `let` 绑定再传 `&mut`；另 criterion 默认特性带 plotters/rayon/wasm 依赖，关默认特性只留 cargo_bench_support（同 rusqlite 瘦身教训） |
| 2026-08-02 | T-032 | proptest 三坑：`prop::char::range` 是两个参数（不是 Range）；`prop_assert_eq!` 消息用字面量 + 参数（`{}` 捕获式 `{op:?}` 不展开）；Editor `undo/redo` 返回 `Result<bool>` 而非 Option；`proptest_config` 属性需要 `attr-macro` 特性（没开） | 分别改为双参数 / 字面量格式串 / `while undo() {}` / 去掉属性用默认用例数（避免额外 proc-macro 依赖）；测试失败先看宏与 API 签名（老教训再次应验） |
| 2026-08-02 | T-018 | swift-format 自动换行把 TextRenderer 推到 303 行超 Rule 3 | 顶点生成抽为 `VertexBuilder`（与 MetalPipeline 拆分同一模式，ADR-016 备注）；格式化后必须复查 `wc -l`（"门禁通过"以格式化后为准） |
| 2026-08-02 | T-018 | `NSEvent.scrollWheelEvent(...)` 在现代 SDK 不存在 | 用 `CGEvent(scrollWheelEvent2Source:units: .pixel, wheelCount: 2, wheel1:dy, wheel2:dx)` + `NSEvent(cgEvent:)`；像素单位下 `scrollingDeltaX/Y` 直接携带 wheel2/wheel1 值（实测探针验证） |
| 2026-08-02 | T-018 | 滚轮测试断言受「自然滚动」偏好符号影响：正 delta 被钳回 0，误判为接线失效 | 断言只验量级与轴映射：先把视口平移到可视区中部（正负 delta 都不会被钳制）；方向语义交给系统偏好（Principle 4） |
| 2026-08-02 | T-018 | 跨文件 extension 访问 `private` 成员报 inaccessible | 需要跨文件访问的成员提升为 internal（App 模块内封装，Rule 4 / 12 在模块边界内成立）；override 方法（keyDown / scrollWheel 等）不能进 extension，必须留在类体 |
| 2026-08-02 | T-018 | ViewportTests 向上滚动期望 300 实际 200 | 又是测试 bug：`ensureCursorVisible` 把 scrollY 设到行顶后被内容上限钳制（既有行为）；先推演钳制再写断言（"测试失败先怀疑测试"再次应验） |
| 2026-08-02 | BUG-006 | 光标可见性把光标滚到「恰好贴边」：右缘 2pt 宽光标整体出视口（行末光标消失）；左缘回车到行首时 scrollX=cursorX，12pt 左边距被滚出视口 | 边缘可见性必须带留白：左右各 12pt（与 leftPad 对称）；且内容宽度必须计入右留白，否则滚动到最右时 clamp 吃掉留白、光标仍贴边。回归先写 Viewport 单测 + MetalView 接线 + 离屏像素三层 |
| 2026-08-02 | BUG-007 | IME 组合期间不横向滚动：`setMarkedText` 缺 `scrollCursorIntoView`（只有 `insertText` 提交路径有） | IME 两条回调（组合更新 / 提交）都必须维护光标可见性；组合末尾光标用 BUG-004 的「光标 + 组合长度」语义，`scrollCursorIntoView` 已支持，缺的只是调用 |
| 2026-08-02 | T-015 | swift-bridge 0.1.59 对 `Result<u64, String>` 生成崩溃：bridged_type.rs `to_alpha_numeric_underscore_name` 对 Result 的 ok 类型 u64 无匹配分支 → `todo!()` panic | id 以 usize 透传（既有验证路径）；生成器能力短板一律机械适配规避（ADR-014 惯例），并回写 ADR-001 v1.1 |
| 2026-08-02 | T-015 | `extension MetalView: NSDraggingDestination` 报 redundant conformance：NSView 已内建一致性 | 只 override `draggingEntered` / `performDragOperation`，不声明一致性；override 必须留在类体 |
| 2026-08-02 | T-015 | 生成的 `document_manager_text` 返回 `RustString` 而非 `String`，测试直接比较报类型错误 | swift-bridge 的 String 返回值一律 `.toString()` 后再断言（同 `editor_text` 惯例） |
| 2026-08-02 | T-033 | criterion 0.8.2 的 `--baseline` 对比只打印报告，不因回归失败退出（exit 0） | 自建 `scripts/bench-regression.py`（stdlib）读 `new/estimates.json` 的 `mean.point_estimate` 对比提交基线，回归超阈值 exit 1（ADR-021 v1.1） |
| 2026-08-02 | T-033 | `cd core && cargo bench` 产生 `core/target/`，`/target` 只忽略仓库根 | `.gitignore` 补 `core/target/`；CI-Bench 作业在 `core/` 内跑 bench，脚本经 `--criterion-root core/target/criterion` 定位结果 |
| 2026-08-02 | T-033 | `PROPTEST_CASES=3000 cargo test --test property` 耗时 ~9s（默认 256 例 ~0.8s） | CI 专项 fuzz 步骤可接受；属性测试仍无 attr-macro 依赖（ADR-022 决策 4 不变） |
| 2026-08-02 | BUG-008 | 属性测试差分排除 Up/Down，恰是 CJK 光标边界 bug 藏身处：字节列目标 `t_start + column.min(...)` 落在多字节字符内部，后续编辑全部 InvalidCharBoundary | 所有移动统一 `floor_char_boundary(new_head.min(len))`（Left/Right 已停边界，floor 恒等）；差分排除某操作 = 该操作不受不变量保护，不变量（如"光标必为字符边界"）应单独显式断言，不能只靠差分同构 |
| 2026-08-02 | BUG-008 | 回归测试期望值写错（head=3 退格删除的是"你"而非留空） | 又是"测试失败先怀疑测试"：先推演字节区间再写断言 |
| 2026-08-02 | T-038 | Swift `Array.partitioningIndex(where:)` 在 macOS 26 SDK 不可用（编译报 no member） | 手写标准二分（low/high 循环），Rule 11 注释说明"这是标准二分而非自研算法"；编译错误先怀疑 API 可用性再怀疑写法 |
| 2026-08-02 | T-036 | 审查误报 .DS_Store"入库"：`find` 输出不区分跟踪状态，磁盘残留被当成已提交 | 判断"某文件是否入库"必须 `git ls-files | grep` + `git log -- <path>` 双重核验；登记表如实标记"误报撤销"并记录核验方法（Rule 15：证据优先） |
| 2026-08-02 | T-036 | experience / audits 计数再次漂移（core 1676 vs 实 1726；App 1483 vs 1615） | 写入计数前必须 `wc -l` 实测；CI 机械门禁只覆盖 ADR 索引，experience/audits 计数靠纪律 + T-039 起审计"行为证据必填"倒逼 |
| 2026-08-02 | T-039 | 审计回填此前靠自觉，T-018/T-015/T-033 均为事后回填 commit | 回填改为 CI 机械门禁（未回填行 ≤1 + hash 存在，fetch-depth 0）；审计行必须含行为证据（跑过的测试 / 基准 / 验证的边界） |
| 2026-08-02 | T-037→T-040 | T-037 把「Cmd+S 写回磁盘绑定路径」当成现在需求实现，用户纠正：保存走 SQLite 是总纲 §5/§6 既定方向，磁盘写回（用户指定路径）是未来路线 | 切片前先核对 ADR 总纲 + Roadmap 的「现在 vs 未来」边界，别把未来路线当当前需求；反转 Accepted 决策必须用户确认并留痕（ADR-023 v1.1→v1.2） |
| 2026-08-02 | T-040 | 用户细化轮转语义：单日内可写入多个文件、日期后加序号 | 文件名 `aster-YYYY-MM-DD-<seq>.sqlite`，每次保存一个新快照（同日多版本）；seq 用数值排序（零填充词法序 >999 会错），取最大 + 1 容忍缺号 |
| 2026-08-02 | T-040 | 日期换算不想引 chrono | Howard Hinnant civil_from_days 标准算法（~15 行），UTC 日期 + 已知 epoch 单测；本地时区午夜轮转留给配置系统 |
| 2026-08-02 | T-041 | 用户再细化保存语义：Cmd+N 建新快照、编辑自动写缓冲、Cmd+S 是合并缓冲 | 三文件模型（快照 = 提交版本，缓冲 = 崩溃保护工作区）；实现前先确认「谁创建文件、谁写入、谁合并」，避免每次 Cmd+S 建新文件的重复返工 |
| 2026-08-02 | T-041 | 新 FFI 声明与实现不在同一处时，apply_patch 整块失败导致函数根本没进文件，build.sh 后 Swift 侧报 cannot find | 补丁整块失败 = 文件未被修改；改动 bridge.rs 后先 `rg` 确认 ffi 声明与实现都在，再 build.sh（生成为唯一事实源） |
| 2026-08-02 | T-041 | 默认 Buffer 无 dirty「●」/ 退出保护：onChange 只在 open() 接线（BUG-009） | 统一走 makeModel 接线；「启动默认文档」与「打开的文件」必须同一条初始化路径，否则默认路径的行为永远游离在测试之外 |
| 2026-08-02 | T-042 | 快照做成 .sqlite 数据库，用户反馈「保存为 .sqlite 无法在 buffer 打开」 | 提交产物必须是**可打开的文本文件**（文档 = 文本，Buffer 第一公民）；SQLite 只做内部缓冲；设计存储前先确认「产物格式谁能消费」，别把数据库当文档 |
| 2026-08-02 | T-042 | 新增模块从 store 拆快照职责 | Store = SQLite（ADR-013 SRP），快照 = 纯文本 → 独立 snapshot 模块（Rule 3）；删掉 Store 里失去消费者的 SQLite 快照 API（Rule 12/14） |
| 2026-08-02 | T-043 | 「崩溃后如何恢复」——缓冲只保护数据，恢复流程缺失（无哨兵、无提示） | 哨兵模式：正常退出写 clean_exit=true，启动读后立即清 false；崩溃不执行终止回调 → 下次启动检测到异常退出；恢复决策抽纯函数（shouldOfferRecovery）便于单测 |
| 2026-08-02 | T-044 | 用户质询「快照改文本后 SQLite 意义还有多大」 | 诚实区分「现有使用薄」与「角色价值」：现用仅缓冲 KV + 哨兵，但总纲 §5 的角色是内部状态存储（会话 / 最近文件 / 工作区 / undo 都在路上）；论证落 ADR-013 v1.2，决议保留；「现有使用量小」不是拆的理由，「既定路线不再需要」才是 |
| 2026-08-02 | T-045 | 缓冲只写不删：delete_scratch 是死代码，生命周期未定义（用户要求厘清保留 / 删除时机） | 规则化：保留 4 类（未决编辑 / 崩溃未处理 / 忽略 / 干净退出），删除 3 时机（合并 / 恢复 / 明确丢弃）；「哨兵只记录退出状态，不承担数据清理」——干净退出不清缓冲，未决行跨会话守恒 |
| 2026-08-02 | T-045 | AppDelegate 334 行、bridge.rs 308 行双双超 Rule 3 | AppDelegate 拆壳 + 存储扩展（T-018 同款）；bridge 适配拆 bridge_store 子模块——swift-bridge 宏经 `use crate::bridge_store::*` 按名解析可用（实测生成绑定 + Swift 测试通过）；每次加功能后跑 `wc -l` 复查 |
| 2026-08-02 | T-046 | 用户定调：全生命周期检查所有文件状态（打开新文件不抛弃前一个）；不弹窗（Buffer 底部 y/n）；缓冲只服务强杀 / 意外退出 | isDirty 单布尔 → PendingDocs 集合登记；退出提示覆盖全部未决（保存全部逐文档合并）；忽略 = 登记为未决并分配快照序号；弹窗标注过渡，T-026 落地移除；设计先听方向再动手，别把「以后要做的 UI」当成现在做 |
| 2026-08-02 | T-047 | 用户加规则：空文件在进程生命周期结束后删除 | 启动即建的空快照（001）与从未输入 / 合并的 ⌘N 文档是主要累积源；prune_empty 只删零长度且 `aster-*.txt` 命名规范内，目录缺失幂等；挂 applicationWillTerminate（干净退出路径），崩溃退出下次再清 |
| 2026-08-02 | T-048 | 发版 CI 三连红：① clippy 1.97 新 lint；② CI-Bench 结果落 workspace 根 target；③ 两处测试硬编码版本号 | ① 测试模块移到文件末尾；② `CARGO_TARGET_DIR=target` 固定落点（本地实测 16 项 0 回归）；③ 版本断言改格式校验，一致性交给 CI-Release（Rule 15）；共享 runner quick 模式噪声 +26%~+120% → 阈值 100% / 下限 100µs（ADR-021 v1.2），CI 只做数量级恶化告警 |

## 给下一个 agent 的提醒

- 开始任务前读：ADR-006（数据结构现状）、ADR-009（Layout）、ADR-011（Command/Event）、
  ADR-014/015（Bridge/App 构建链）、ADR-016~020（渲染/编辑/方向/滚动/发布）、
  WORKFLOW、本文件。
- 新 Public API 必须有 ADR；未确定项进入实现前必须先更新 ADR。
- 测试先红后绿；测试失败先自查测试。
- 提交前五项门禁 + 规模检查（CI 有机械检查，本地也可跑）。
- 宪法 V1.4：Accepted 且需落地的 ADR 必须排入 Roadmap 或显式 Deferred（Rule 13）；新 Public API 必须同切片有真实消费者（Rule 14）；文档索引与版本一致性由 CI 检查（Rule 15）；数据结构等性能决策先建基线（Rule 16，评估框架见 ADR-006）。
- 每次切片遇到新问题，把解法追加到上面的踩坑记录。
- **发布**：版本号三处同步（core/Cargo.toml → 应用版本；Changelog 归档；tag）。
  打 `Beta-V*` tag 推送即自动发布（CI-Release，ADR-020）；本地等价：`./bridge/build.sh`
  + `cd app && swift build -c release` + 手工组装 Aster.app + zip。release 产物未公证，
  首次打开需右键 → 打开。
- **CI 历史教训**：CI-Swift 曾因渲染像素测试的 UInt8 溢出（SIGTRAP）连续两轮红，
  修复在测试自身；CI 只按路径触发（改 core 不跑 Swift，纯文档不触发）是设计行为。
- **测试专项（2026-08-03，Phase 7 T-052~T-062）**：用户将专门投入各种测试，
  计划已登记 roadmap（IME 契约 / 渲染变异 / 失败可见性 / 原子写 / 存储损坏 /
  时序 / 状态机扩展 / 已知限制固化 / 崩溃完整 / 跨日轮转 / 变异工具化）；
  执行原则 = 先变异定位盲区再补测试，发现缺陷登记 BUG 并修复，0 生产代码改动
  不作为验收。执行顺序按风险可调整。**当前候选风险（人工验证，未自动化）**：
  `characterIndex(for:)` 返回字节偏移而 NSTextInputClient 契约是 UTF-16 索引
  （CJK IME 点击定位）；`setMarkedText` 忽略 replacementRange；缓冲自动保存失败
  仅 NSLog（用户不可见）；崩溃循环累积空快照。
- **数据结构评估（2026-08-03，ADR-006 v1.1）**：全仓复审结论已入 ADR-006——
  ① App 每键全量文本流（Bridge 拷贝 + 全量 upsert，O(n)/键，最大热点）；
  ② Core move_cursor 每移动全量 Layout::build（O(n)，App 已缓存而 Core 没有）；
  ③ 中间编辑无基准（现有 bench 只测末尾，Gap/Rope 决策缺数据）；
  ④ History 空间 O(编辑总量)（设计取舍，监控）。优化切片 T-063~T-066 在
  roadmap Phase 8；任何结构替换先补基线（Rule 16），反转 ADR 决策（T-065
  自动保存节流）需用户确认。
- **测试方法论（T-050 / T-051 沉淀，务必复用）**：① 手写场景追不上组合路径，
  跨文档状态机（snapshotSeqByDocId / pendingDocs / committedTextByDocId）的
  一致性就是保存链路全部风险面；② 测试全绿 ≠ 无 bug——变异测试量化查错能力，
  全绿变体 = 盲区；③ 失败路径与成功路径分开测（快照写失败必须保全缓冲行）；
  ④ 固定种子随机操作序列验证守恒不变量（缓冲行 ⟺ 未决、未决必有快照序号）；
  ⑤ History 相邻 Insert 合并会干扰「undo 回快照内容」场景，用选区替换拆步。
- **当前下一步**：功能线 T-014 剪贴板（NSPasteboard，ADR-018）；并行线 Phase 7
  测试（用户投入）与 Phase 8 性能（T-063 基准先行）。**ADR-024（Bridge FFI 总账
  计数校正）仍为未决提议**——ADR-013 头部「7 方法」与索引计数已漂移（实际 11 方法
  + 7 FFI），纯文档修订，需用户确认后执行。
- **上下文压缩恢复**：本文件 + ADR 索引是会话记忆载体；压缩后先读本文件现状速览与
  给下一个 agent 的提醒，不要重读全部源码。
- **Bridge FFI 新增必读（T-015 踩坑）**：swift-bridge 0.1.59 对 `Result<u64, _>`
  的 C 结构命名未实现（`todo!()` 崩溃）——id / 数值一律 usize 透传；改
  `core/src/bridge.rs` 后必须先 `./bridge/build.sh` 再生绑定 + staticlib，再
  `swift test`（CI-Swift 第一步同此）。
- **CI-Bench（T-033，ADR-021 v1.1）**：改 core 后 CI 会跑 `cargo bench -- --quick`
  对比 `bench-baseline/`，回归超 10% 即红。**本地改基准后必须重新生成基线并提交**：
  `cd core && cargo bench` 后执行 `python3 scripts/bench-regression.py --save-baseline
  bench-baseline --criterion-root core/target/criterion`（机器记录进 benchmarks.md）。
- **会话结束未决项（2026-08-02）**：遗留项全部清零——T-018（含前置拆分）、
  T-015 文件打开接线、T-033 fuzz + 基准回归告警（ADR-021 v1.1 反转经用户确认）
  均已完成并推送。下一步按 Roadmap 为 T-014 剪贴板。另外：audits.md 审计登记
  制度已生效，新切片必须留审计行。
- **T-014 前置**：剪贴板 = 系统 NSPasteboard（总纲 Principle 4，Rule 11）；Edit
  菜单已有 `cut:` / `copy:` / `paste:`（target nil 走响应链，T-011 建好未接线）——
  T-014 在 MetalView 实现响应链方法 → NSPasteboard；粘贴 = 选区替换
  （`EditorModel.typeText` 路径，ADR-017；`set_selection` 已桥接）；深浅色不跟随
  系统（ADR-018）。拖放 / 打开已落地（T-015），DocumentManager 已桥接
  （`document_manager_open_disk` / `document_manager_text`）。Command 上下文 /
  激活文档接线在 T-024（Command Palette，ADR-017 备注）。
- **T-019 前置（ADR-019）**：软换行默认关，开启后视觉折行属 App 渲染层（Layout
  逻辑行不变）；`wrapEnabled` 先做常量开关，配置系统落地后经 Config DSL / Lua 开启；
  水平滚动已在 T-018 完成（Viewport.scrollX + 光标横向可见性）。
- **快速启动命令**：`cargo test`（core）；`./bridge/build.sh && cd bridge && swift test`；`cd app && swift test`；`cd app && swift run`（GUI，会开窗口）。
