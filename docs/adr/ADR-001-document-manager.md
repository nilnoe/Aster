# ADR-001 — DocumentManager

- **Status:** Accepted
- **Date:** 2026-08-02
- **Version:** 1.1
- **新增 Public API:** Core 2 方法 + Bridge FFI 3 项（v1.1，T-015）
- **影响模块:** Buffer, Theme
- **是否违反 Single Responsibility:** 否
- **是否增加循环依赖:** 否

---

## 决策

在 Rust Core 中新增 `DocumentManager`，作为所有 Document / Buffer 的统一注册表与生命周期所有者。

内部注册表：`HashMap<BufferId, Document>`，其中 `Document` 是私有类型（`Buffer` + `Option<PathBuf>`：`None` 即 Scratch）。

**激活状态（active buffer）不属于本切片**：由 T-013（编辑循环）决定管理归属，本 ADR 不锁定。

## 原因

1. **Buffer 是第一公民，但缺少统一所有者。** 文件、Scratch、Shell、Search 最终都以 Buffer 形态存在；目前没有任何模块负责 Buffer 的注册、生命周期与状态归属。
2. **防止 Core 依赖具体 UI。** 若由 AppKit 层（Window / View / Menu）或各个插件自行管理 Buffer 生命周期，Core 将反向依赖具体 UI，违反 ADR"Core 不允许依赖任何具体 UI"与"所有 UI 都是可选 Overlay"的原则。
3. **保持 UI 薄。** Window、Menu、Command、Plugin 只通过 DocumentManager 这一个稳定入口访问当前 Buffer，不直接持有 Buffer 状态。
4. **统一持久化边界。** Scratch 自动保存、Attach Path、Session / Crash Recovery 都经由 DocumentManager 落到 SQLite，存储逻辑不散落在编辑热路径。

## 审计

### Single Responsibility — 否（不违反）

DocumentManager 的唯一职责是 Document / Buffer 的生命周期与注册表。渲染、布局、命令分发分别属于 Metal Renderer、Layout、Command，不进入本模块。

### 循环依赖 — 否（不违反）

依赖方向单一：

```text
DocumentManager → Buffer
DocumentManager → Theme
```

Buffer 与 Theme 不反向依赖 DocumentManager。

## 新增 Public API（2 个公开方法 + 支撑类型）

1. `open(&mut self, source: DocumentSource) -> Result<BufferId, DocumentManagerError>`
   - `Disk(PathBuf)`：读取文件内容创建 Buffer，记录绑定路径（Attach Path 语义）。
   - `Scratch`：创建无路径 Buffer。
   - 返回 `Result`：磁盘读取可能失败，失败必须可见（ADR-004）。
2. `close(&mut self, id: BufferId) -> Result<(), DocumentManagerError>`
   - 移除 Buffer 及其注册信息；未知 id 返回 `UnknownBuffer`。

支撑类型（计入本 ADR，不另外计 API 数）：

- `DocumentSource`：`Disk(PathBuf)` / `Scratch`。
- `DocumentManagerError`：`UnknownBuffer(BufferId)` / `ReadFailed { path, kind }`。

构造器：`DocumentManager::new()`。

其他 Core 模块对注册内容的访问（如后续 Command / 编辑循环）先使用 `pub(crate)` 内部通道；提升为公共 API 时必须另走 ADR（宪法 Rule 4）。

## 影响模块

- **Buffer** — 获得统一的生命周期管理；Buffer 自身保持无状态、不持有所有者。
- **Theme** — 文档 / 会话状态包含 Theme 关联（如 Scratch 与 Session 的持久化主题属性），DocumentManager 需要与之协作；依赖方向单向。

## 复杂度预算（宪法 Rule 9）

1. **增加了哪些复杂度？** 一个模块（DocumentManager）、两个 Public API（`open` / `close`）、一条持久化路由（Scratch → SQLite）。不引入抽象层或 Trait。
2. **是否是永久性的？** 是——Buffer 生命周期管理是 Core 的长期结构，属于永久复杂度；但其规模由单一职责和两个 API 锁定，不会随功能增长而膨胀。
3. **有没有更简单但同样满足需求的方案？**
   - 备选一：由 AppKit 层直接持有 Buffer——短期更简单，但违反"Core 不允许依赖具体 UI"，长期维护成本更高。
   - 备选二：由插件管理 Buffer 生命周期——违反"Core 必须保持稳定"。
   - 两者都不满足既有 ADR 约束，因此本方案是最简单且合规的方案。

结论：新增 1 模块、2 Public API、无抽象层，未触及红线。

## T-015 修订（v1.1）

### Bridge FFI 面（宪法 Rule 4）

文件打开切片（T-015）接线本 ADR 的 `open(Disk)`，桥接面新增 3 个函数：

| FFI | 职责 |
| --- | --- |
| `document_manager_new() -> DocumentManager` | 建立注册表（App 持有 opaque） |
| `document_manager_open_disk(&mut DocumentManager, path: String) -> Result<usize, String>` | `open(Disk)` 适配；id 以 usize 透传（swift-bridge 0.1.59 的 Result C 结构命名对 u64 未实现，实测 todo!() 崩溃；usize 为既有验证路径，ADR-014 机械适配惯例）；错误映射为消息字符串 |
| `document_manager_text(&DocumentManager, id: usize) -> String` | 按 id 取注册 Buffer 文本（App 用它建 Editor 会话）；未知 id 返回空串（调用方只查询刚由 open 返回的 id） |

### App 接线与激活状态边界

- 打开路径（NSOpenPanel / 拖放）经 DocumentManager Disk 源读取内容，App 以内容
  新建 Buffer + Editor 会话（ADR-017：Editor 消费 Buffer）。
- 注册表持有的 Buffer 副本与编辑会话分离：激活文档 / 命令上下文的统一归属随
  T-024（Command Palette）落地，本切片不引入激活状态语义（Rule 9：不为最小
  切片增加状态维度）。
- 访问器 `DocumentManager::text(id)` 为 `pub(crate)`（仅 Bridge 使用，Rule 12
  的 `pub` 才是决策）。

## 备注

- 本次仅记录 ADR，不包含实现（遵循 Workflow：Architecture 阶段先记录决策，Test Design 在前，实现在后）。
- 后续切片：为 `open` / `close` 编写测试（Red），再实现。
- 实现顺序：T-002 实现注册与生命周期（内存态）；SQLite 存储层由 T-009（ADR-013）交付，Scratch 自动保存工作流接线在 T-019，Session / Crash Recovery 编排在 T-021；激活状态由 T-013 决定。
- v1.1：T-015 落地文件打开接线（Disk 源首次进产品，Rule 14 存量处置推进）；
  Bridge FFI 3 项 + App（NSOpenPanel / 拖放）。
