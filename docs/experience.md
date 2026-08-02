# Experience — 经验沉淀（Agent Memory）

本文件是项目会话之间的**记忆载体**：沉淀已经踩过的坑、验证过的工作方式、和"别再重新讨论一遍"的决策。它不是规则（规则看宪法），但**每次任务开始前必须读**。

## 项目现状速览（截至 2026-08-02，T-001 ~ T-013 完成，Beta V0.1.0 已发布）

- **代码：**
  - Rust Core：T-001 ~ T-013（buffer / selection / history / layout / theme / command / event / lua / store / bridge / editor），`core/src` 共 1676 行，107 个测试全绿；依赖：mlua 0.12（lua54+vendored）、rusqlite 0.40（bundled）、swift-bridge 0.1.59（build-dep swift-bridge-build）。
  - bridge/：swift-bridge 绑定 Swift Package（11 个 XCTest 全绿；生成代码与 .a 不提交，`bridge/build.sh` 是唯一生成入口）。
  - app/：AppKit 壳 + Metal 编辑视图（26 个 XCTest 全绿），源码 1226 行（Rule 12 的 Swift 预算 ≤5,000 行生效中）。
- **决策：** ADR-001 ~ ADR-017 全部 Accepted（索引见 `docs/adr/README.md`）。
- **下一任务：** T-018 水平滚动（ADR-019 已定：v1 默认，scrollX + 光标横向可见性）
  → 随后 T-014 剪贴板（方向见 ADR-018：深浅色不跟随系统，主题由 Lua 提供）。
- **版本：** Beta 阶段，模板 `Beta V0.0.0`（末位补丁 / 中间位功能 / 首位恒 0）。
- **远程：** remote 名是 `origin`（`git@github-nilnoe:nilnoe/Aster.git`），SSH 别名 `github-nilnoe` 在 URL 中；**不要**把别名当 remote 名用（T-006 踩过）；不要用 `github.com` 入口。
- **部署目标：** macOS 26（ADR-002）：app/bridge manifest `platforms: [.macOS(.v26)]`（swift-tools-version 6.2+）+ `MACOSX_DEPLOYMENT_TARGET=26.0` 编译 Rust C 对象，两端必须一致。

## 工作方式（验证有效，继续保持）

- 每个切片严格走 WORKFLOW 11 步；**顺序不可跳**：ADR → 测试（Red）→ 实现 → 门禁 → 审计 → 文档。
- 公共 API 必须先 ADR（宪法 Rule 4）；不建 Trait / 抽象层，除非有证明（Rule 1 / 2）。
- 切片完成时一次性更新：Roadmap 状态、Changelog、ADR 索引、Benchmarks——这四件套是 DoD 的一部分，容易忘。
- Commit 用 Conventional Commits 并引用 `T-XXX` 与 `ADR-XXX`；每个切片独立 commit + push。
- 遇到"未确定项"直接进实现 = 违规：未确定项清单在 ADR-006，必须先更新 ADR。
- 宪法（docs/constitution.md）不可由 agent 自行修改；修订需用户确认。
- 沙箱环境：git 写 `.git` 需要提权（`require_escalated`）；既有依赖构建本地可用，**新增依赖首次构建需联网**（沙箱内 `cargo add` / 首次 `cargo test` 需 `require_escalated`）。
- **多包构建链**：`core/`（Rust）→ `bridge/`（绑定包）→ `app/`（AppKit）。改动 core / bridge.rs 后必须先 `./bridge/build.sh`（cargo build --release + 复制绑定 / staticlib / lua / sqlite）再 `swift test`；CI-Swift 作业第一步行同一脚本。
- **Swift 门禁现状**：`swift-format lint --recursive bridge/Tests app/Tests` + `swift test`（bridge、app 两个包分别跑）；生成绑定（Sources）不 lint。
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
| 文本存储 | `String`（Buffer 内部实现细节） | T-020 基准证明不达标时换 Rope/Gap（ADR-006） |
| 行索引 | 不可变快照 `Layout`，编辑后调用方重建 | 随存储一起替换（T-020），接口不变 |
| 软换行 | 用户可选、默认关闭；默认按行渲染 + 水平滚动（ADR-019） | 配置系统（Lua/Config DSL）切片落地后经配置开启 |
| 水平滚动 | v1 默认能力（ADR-019，T-018）：scrollX 点值平移 + 光标横向可见性 | 平滑滚动动画随 T-022 |
| 行分隔符 | `\n` 唯一；`\r` 暂为行内容 | CRLF 归一化在文件模型切片 |
| Undo | 内存 inverse-operation 栈 + 相邻 Insert 合并 | SQLite 持久化边界在 T-021 |
| 多光标 / mmap | 未定 | T-020 基准后定 |
| 插件信任 | 默认信任，不沙箱 | 引入插件市场时重估（ADR-003） |
| macOS | 仅最新版，零兼容负担 | 永久（ADR-002） |
| 遥测 | 默认无，显式开启 | 永久（ADR-004） |
| Lua 宿主 | mlua 0.12（lua54 + vendored） | 插件线程化时重估 Send/Sync（T-008 已评估） |
| Bridge 构建 | swift-bridge 0.1.59 + `bridge/build.sh`；staticlib + lua/sqlite 传递依赖显式链接进 Swift 包 | swift-bridge 升级（major）另走 ADR（依赖政策） |
| AppKit 壳 | 程序化 AppKit（无 xib），最小菜单 App/Edit/Window；部署目标 macOS 26 | T-012 换 MetalView；T-013 菜单接线编辑循环 |
| 文本渲染 | CoreText shaping（CTLine/CTRun）→ 字形图集（RGBA8 按需栅格化，font+glyph 键）→ Metal quad（32B/顶点）；IME = 系统 NSTextInputClient；行结构复用 Core Layout（bridge `layout_line_starts`） | 增量失效随 T-013 细化（ADR-016）；sRGB+gamma 在 T-016；颜色接 Theme 由 Lua 主题切片提供（ADR-018） |
| 深浅色 | 固定深色启动态，不跟随系统 appearance；主题可编程能力由 Lua 提供（ADR-018） | Lua 主题切片（ADR-010 Theme 模型已就绪） |
| 编辑会话 | Core `Editor`（Buffer+Selection+History 协调者，ADR-017）：type/delete/move/undo/redo/selectAll/setSelection；IME 组合文本内联光标处；滚动是视图状态 | 命令上下文 / 激活文档随 T-015；剪贴板 / 拖放 / 深浅色随 T-014 |

## 踩坑记录（可追加）

| 日期 | 切片 | 问题 | 解法 |
| --- | --- | --- | --- |
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
| 2026-08-02 | BUG-004 | 组合期间光标画在组合起点，不跟随拼音 | 组合内联于光标处，光标应画在 cursor + composition 长度处（同一行，无换行） |
| 2026-08-02 | T-013/IME | "拼音按回车得到英文字母" 是 macOS 系统输入法固有行为（回车提交原始拼音，空格/数字确认汉字），TextEdit 同样如此，非我方 bug | 不要"修复"它（改 = 重实现 IME，违反 Principle 4）；如需回车确认候选，用户侧换第三方输入法（如 Rime） |
| 2026-08-02 | T-017 | 渲染像素测试崩溃 SIGTRAP：`r + 100`（UInt8 255+100）算术溢出 | 像素比较先转 Int；又是测试自身的问题（"测试失败先怀疑测试"） |

## 给下一个 agent 的提醒

- 开始任务前读：ADR-006（数据结构现状）、ADR-009（Layout）、ADR-011（Command/Event）、ADR-014/015（Bridge/App 构建链）、WORKFLOW、本文件。
- 新 Public API 必须有 ADR；未确定项进入实现前必须先更新 ADR。
- 测试先红后绿；测试失败先自查测试。
- 提交前五项门禁 + 规模检查（CI 有机械检查，本地也可跑）。
- 每次切片遇到新问题，把解法追加到上面的踩坑记录。
- **T-014 前置**：剪贴板（系统 NSPasteboard，总纲 Principle 4）、拖放（NSDraggingDestination）、文档选择器（NSOpenPanel）——全部系统能力，不造轮子（Rule 11）；深浅色不跟随系统（ADR-018）；`Editor` 桥接已有 `set_selection`，剪贴板粘贴 = 选区替换（`type_text` 路径）。Command 上下文 / 激活文档接线在 T-015（ADR-017 备注）。
- **T-018 前置（ADR-019）**：水平滚动 = 视图层 `scrollX` 点值 + 触控板双指 / Shift+滚轮
  平移 + 光标横向可见性（内容宽度按可见行最大宽度）；软换行默认关，开启后视觉折行
  属 App 渲染层（Layout 逻辑行不变）；`wrapEnabled` 先做常量开关，配置系统落地后经
  Config DSL / Lua 开启。
- **快速启动命令**：`cargo test`（core）；`./bridge/build.sh && cd bridge && swift test`；`cd app && swift test`；`cd app && swift run`（GUI，会开窗口）。
