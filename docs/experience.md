# Experience — 经验沉淀（Agent Memory）

本文件是项目会话之间的**记忆载体**：沉淀已经踩过的坑、验证过的工作方式、和"别再重新讨论一遍"的决策。它不是规则（规则看宪法），但**每次任务开始前必须读**。

## 项目现状速览（截至 2026-08-02）

- **代码：** Rust Core 已完成 T-001 ~ T-010（core 1283 行 / 94 测试）；bridge/ 3 个 XCTest；app/ 4 个 XCTest，全绿。
- **决策：** ADR-001 ~ ADR-015 全部 Accepted（索引见 `docs/adr/README.md`）。
- **下一任务：** T-012（Metal 渲染管线：文本渲染 spike）。
- **版本：** Beta 阶段，模板 `Beta V0.0.0`（末位补丁 / 中间位功能 / 首位恒 0）。
- **远程：** `github.com/nilnoe/Aster`，走 SSH 别名 `github-nilnoe`（`.ssh/config` 中绑定 `nilnoe_github` 密钥；不要用 `github.com` 入口，那绑定的是另一把钥匙）。

## 工作方式（验证有效，继续保持）

- 每个切片严格走 WORKFLOW 11 步；**顺序不可跳**：ADR → 测试（Red）→ 实现 → 门禁 → 审计 → 文档。
- 公共 API 必须先 ADR（宪法 Rule 4）；不建 Trait / 抽象层，除非有证明（Rule 1 / 2）。
- 切片完成时一次性更新：Roadmap 状态、Changelog、ADR 索引、Benchmarks——这四件套是 DoD 的一部分，容易忘。
- Commit 用 Conventional Commits 并引用 `T-XXX` 与 `ADR-XXX`；每个切片独立 commit + push。
- 遇到"未确定项"直接进实现 = 违规：未确定项清单在 ADR-006，必须先更新 ADR。
- 宪法（docs/constitution.md）不可由 agent 自行修改；修订需用户确认。
- 沙箱环境：git 写 `.git` 需要提权（`require_escalated`）；既有依赖构建本地可用，**新增依赖首次构建需联网**（沙箱内 `cargo add` / 首次 `cargo test` 需 `require_escalated`）。

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

## 架构决策速查（勿重新讨论，除非出现新数据）

| 主题 | 现状 | 替换 / 决策触发点 |
| --- | --- | --- |
| 文本存储 | `String`（Buffer 内部实现细节） | T-020 基准证明不达标时换 Rope/Gap（ADR-006） |
| 行索引 | 不可变快照 `Layout`，编辑后调用方重建 | 随存储一起替换（T-020），接口不变 |
| 软换行 | v1 不做，按行渲染 + 水平滚动 | T-012 渲染切片另走 ADR |
| 行分隔符 | `\n` 唯一；`\r` 暂为行内容 | CRLF 归一化在文件模型切片 |
| Undo | 内存 inverse-operation 栈 + 相邻 Insert 合并 | SQLite 持久化边界在 T-021 |
| 多光标 / mmap | 未定 | T-020 基准后定 |
| 插件信任 | 默认信任，不沙箱 | 引入插件市场时重估（ADR-003） |
| macOS | 仅最新版，零兼容负担 | 永久（ADR-002） |
| 遥测 | 默认无，显式开启 | 永久（ADR-004） |

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

## 给下一个 agent 的提醒

- 开始任务前读：ADR-006（数据结构现状）、ADR-009（Layout）、ADR-011（Command/Event）、WORKFLOW、本文件。
- 新 Public API 必须有 ADR；未确定项进入实现前必须先更新 ADR。
- 测试先红后绿；测试失败先自查测试。
- 提交前五项门禁 + 规模检查（CI 有机械检查，本地也可跑）。
- 每次切片遇到新问题，把解法追加到上面的踩坑记录。
