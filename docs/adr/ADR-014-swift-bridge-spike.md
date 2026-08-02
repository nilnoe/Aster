# ADR-014 — Swift Bridge 接入（spike）

- **Status:** Accepted
- **Date:** 2026-08-02
- **Version:** 1.0
- **新增 Public API:** bridge FFI 面（`core_version` + `buffer_insert` + `Buffer` / `BufferId`）+ 新增依赖 **swift-bridge**、**swift-bridge-build**（宪法 Rule 7 / 8）
- **影响模块:** Core（新增 bridge 模块）、bridge/（新增 Swift Package）
- **是否违反 Single Responsibility:** 否
- **是否增加循环依赖:** 否

---

## 决策

在 `core/src/bridge.rs` 用 `#[swift_bridge::bridge]` 声明 FFI 面，桥接**真实的** `Buffer` / `BufferId` / `BufferError`（不造示例类型）；`core/build.rs` 用 `swift-bridge-build` 生成 Swift 绑定与 C 头（写入 `target/generated`，gitignore）；新增 `bridge/` Swift Package 链接 Rust staticlib，用 XCTest 验证 Swift → Rust → Swift 往返。

生成与构建入口统一为 `bridge/build.sh`（本地与 CI 同一脚本）：`cargo build --release` → 复制生成绑定与 staticlib 到 Swift 包。

## 原因

- **Rule 7 / 8：** Rust 标准库无 Swift 互操作能力；swift-bridge 是 ADR 总纲 3.4 已定的桥接方案（拒绝手写 FFI / IPC）。本 ADR 记录 crate 级选择：`swift-bridge` 0.1.59 + `swift-bridge-build`（构建脚本内同步代码生成，无需外部 CLI，构建封闭）。
- **为什么现在做 spike：** T-011 起 UI 依赖稳定的桥接管线。先以最小 API 面验证「代码生成 → 类型转换 → 静态链接 → 跨语言调用」全链路，把不支持的转换（&str 形态、enum payload、Result）在 UI 切片前暴露并记录。
- **桥接真实 Buffer 而非包装类型：** API 面验证才有意义；T-013 编辑循环直接复用，桥接侧只做机械类型适配。

## 审计

### Single Responsibility — 否（不违反）

bridge 模块只做 FFI 声明（+ `core_version` 一个只读常量函数）；业务逻辑仍留在 buffer / error 模块，Swift 侧只消费生成绑定。

### 循环依赖 — 否（不违反）

`bridge → buffer / error`（单向）；Swift 侧依赖生成代码与 staticlib，无反向依赖。

## 新增 Public API（FFI 面，宪法 Rule 4）

| API | 职责 |
| --- | --- |
| `core_version() -> String` | 核心版本号（验证 String 往返） |
| `BufferId::new(id: u64)` / `as_u64()` | opaque 类型 + u64 往返 |
| `Buffer::new(id: BufferId)` / `id()` / `len()` / `is_empty()` / `text() -> &str` | 真实 Buffer 的桥接面；验证 opaque 类型 / usize / &str |
| `buffer_insert(&mut Buffer, usize, &str) -> Result<usize, String>` | 桥接适配：`Buffer::insert` 的错误映射为消息字符串（错误可见，ADR-004） |

## 影响模块

- **T-011（AppKit 壳）** — app 目标消费同一绑定；build 集成（Xcode / SPM）在此 spike 验证后固化。
- **T-013（编辑循环）** — 键盘输入经 `Buffer::insert` 等桥接面进入 Core。
- **CI** — ci-swift 作业改为先跑 `bridge/build.sh` 再 lint / test。

## 复杂度预算（宪法 Rule 9）

1. **增加了哪些复杂度？** 1 个桥接模块、2 个构建依赖（swift-bridge 系）、1 个 Swift Package（测试用）、1 个构建脚本；0 业务抽象层。
2. **是否是永久性的？** bridge FFI 面是架构总纲（App → Bridge → Core）的永久结构；生成代码不手写维护。
3. **有没有更简单但同样满足需求的方案？** 把桥接风险推迟到 T-011 再探索（把未知项推给 UI 切片）；手写 FFI 违反总纲 3.4。spike 提前验证是成本最低路径。

结论：1 模块 / 2 依赖 / 1 Swift 包 / 0 抽象层，未触及红线。

## 备注

- **spike 结论（类型转换验证）：** usize → Swift `UInt`、u64 → `UInt64`、`&str` 参数由 Swift `String` 经 `ToRustStr` 满足、`&str` 返回为 `RustStr`（`.toString()`）、`Result<T, E>` → throws。生成绑定代码不提交（target/ 已 gitignore），`bridge/build.sh` 是唯一入口。
- **已发现的限制：** swift-bridge 0.1.59 对 `#[swift_bridge(already_declared)]` 的 payload 枚举不自动生成 FFI 转换，需手写 `SharedEnum` + repr(C) 类型（即手写 FFI 胶水，违反总纲 3.4）。因此本切片经 `buffer_insert` 用 String 传递错误；BufferError 的结构化桥接推迟到 T-013（编辑循环）评估。
- T-011 起 Xcode / SPM 构建集成以此 spike 的脚本为基础扩展。
