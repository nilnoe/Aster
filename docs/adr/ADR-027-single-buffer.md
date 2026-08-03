# ADR-027 — 文档内容单一事实来源（单 Buffer 共享所有权）

- **Status:** Accepted
- **Date:** 2026-08-03
- **Version:** 1.0
- **新增 Public API:** `Session::editor` / `Editor::from_shared` + `Session::open_scratch`（seed 参数）+ `Session::content_changed`（删文本参数）+ `Editor::text`（&str → String）+ Bridge FFI +1（`session_editor`）/ 2 项签名变更
- **影响模块:** core（editor / document_manager / session / bridge / bridge_session）、app（AppDelegate、EditorModel）、docs
- **是否违反 Single Responsibility:** 否
- **是否增加循环依赖:** 否

---

## 决策

1. **每个文档的内容只存在一份 Buffer**：`DocumentManager` 注册表存
   `Rc<RefCell<Buffer>>`，`Editor` 与注册表共享同一 Rc（`Editor::from_shared`）——
   编辑经 Editor 修改即注册表内容，结构上不可能失鲜（I-009 双副本消除）。
   缓冲为 `String` 不变（ADR-005 / ADR-006 已确定，结构替换仍受基准门禁）。
2. **`Session::content_changed(id)` 不再接收文本参数**：从注册表 Buffer 直接
   读当前内容比较基线并写 SQLite 缓冲——App 每次按键不再把全文推过 Bridge
   （消除 ADR-006 v1.1 热点 1 的 O(n)/键桥接拷贝）。
3. **App 不再自行构造 Buffer**：`session_open_scratch(seed)`（启动样例文本由
   Core 注入，不进历史 / 不置脏）、`session_editor(id)` 取编辑句柄；
   生产路径经 `EditorModel.init(editor:)`；`EditorModel.init(buffer:)` 与
   `editor_new` FFI 保留为测试便利（Rule 14：消费者 = 测试，ADR-027 标注）。
4. **`Editor::text()` 返回 `String`**（原 `&str`，ADR-017 v1.1 修订）：共享
   Buffer 经 RefCell，`&str` 无法跨守卫返回；App 侧原本就经 Bridge 拷贝消费
   （RustString→String），无新增成本；Core 内部编辑路径经 `borrow_mut`
   零拷贝操作。
5. **保存域冻结期修订（ADR-023 v1.8）**：`content_changed` 语义从「App 推全文」
   变为「Core 读活文」——用户 2026-08-03 指示方向②（单 Buffer）并明确
   「性能第一、参考 Phase 8」，作为本修订的方向确认。

## 原因

- **I-009（P0）**：打开文件时 App 另建 Buffer 经 `editor_new` 进 Editor，
  注册表副本从此失鲜——`content_changed` 只写 SQLite 不回写注册表；
  T-024 激活文档接线后任何经 `session_text` 的读取会读到陈旧内容。
- **ADR-006 v1.1 热点 1**：App 每键全量文本流（Bridge 拷贝 + 全量 upsert，
  O(n)/键）——单 Buffer 让持久化直接读 Core 活文，桥接拷贝消失，是 Phase 8
  优化（T-063 / T-064 / T-065）的结构性前置。
- **为什么 Rc<RefCell<Buffer>>**：两个 Core 模块（注册表 / 编辑会话）共享同一
  可变内容，`RefCell` 是 std 内部可变性（Rule 11：标准库 > 自研）；Core 单线程、
  桥接调用顺序化，借用均在单个方法调用内短命，不变量由方法作用域保证
  （Rule 18）。对比方案：Session 持有 Editor（违反 ADR-025 SRP）、Editor 改
  BufferId 路由（每操作跨表拆分借用，复杂度更高）、Option ① 镜像回写（仍是
  双副本，只保鲜不根治）。

## 审计

### Single Responsibility

- `DocumentManager`：仍是注册表（ADR-001），内容形态从 `Buffer` 变为
  `Rc<RefCell<Buffer>>`（v1.4 备注）。
- `Editor`：仍是编辑语义唯一实现（ADR-017）；新增 `from_shared` 构造，不扩大
  编辑职责。
- `Session`：只新增「返回编辑句柄」的工厂访问器（`editor(id)`），不实现编辑
  语义（ADR-025 SRP 不变）。

### 循环依赖

`session → editor / document_manager`（新增 session → editor 单向工厂依赖）；
`editor → buffer`；`bridge → session / editor`；无反向。

## 新增 Public API

| API | 职责 |
| --- | --- |
| `Session::editor(&self, id) -> Result<Editor, SessionError>` | 返回文档的编辑会话句柄（共享注册表 Buffer；未知 id 显式报错） |
| `Editor::from_shared(Rc<RefCell<Buffer>>)` | 以共享 Buffer 构造 Editor（pub(crate)，同 crate 消费） |
| `Session::open_scratch(&mut self, seed: &str)` | 新增 seed：启动样例文本由 Core 注入（不进历史 / 不置脏）；空串 = 原语义 |
| `Session::content_changed(&mut self, id)` | 删除 `content` 参数：读注册表活文比较基线并写缓冲 |
| `Session::text(&self, id) -> Result<String, _>` | 返回类型 `&str` → `String`（RefCell 守卫约束） |
| `Editor::text(&self) -> String` | 同上（ADR-017 v1.1 修订） |
| Bridge `session_editor` | +1 项；`session_open_scratch`（seed）/ `session_content_changed` 签名变更 |

## 影响模块

- **core/editor**：Buffer 字段改 `Rc<RefCell<Buffer>>`；`text()` 返回 String；
  内部路径 `borrow` / `borrow_mut`。
- **core/document_manager**：注册表条目改共享句柄；`text(id)` 返回
  `Option<String>`；新增 `pub(crate) shared_buffer(id)`。
- **core/session**：`open_scratch(seed)`、`content_changed(id)`、
  `text(id) -> String`、新增 `editor(id)` 工厂。
- **core/bridge / bridge_session**：FFI 如上；`editor_text` 返回 String。
- **app**：`AppDelegate` 不再构造 Buffer（open / makeFrame / 恢复路径改
  `session_open_scratch(seed)` + `session_editor`）；`onContentChanged` 不再推
  全文；`EditorModel` 新增 `init(editor:)`。
- **docs**：ADR-017 / ADR-025 头部标注修订见本 ADR；ADR-023 v1.8 冻结修订留痕；
  ADR-024 FFI 计数 51 → 52；changelog / roadmap / issues 同步。

## 复杂度预算（宪法 Rule 9）

1. **增加了哪些复杂度？** 1 个共享句柄类型 + 1 个工厂 + 2 个签名变更 +
   App 接线重写；`RefCell` 借用纪律由方法作用域保证；0 抽象层 / 0 依赖。
2. **是否永久？** 是——单事实来源是编辑器的永久结构；共享句柄替代双副本是
   净简化（删除 App 构造 Buffer 路径与全文推送）。
3. **有没有更简单方案？** Option ① 镜像回写最省事但仍是双副本（只保鲜不根治，
   每次编辑多一份内存镜像）；Session 持有 Editor 更「省」但违反 ADR-025 SRP。
   结论：Rc<RefCell> 共享是满足「单事实来源 + 各自 SRP」的最简合规方案。

## 备注

- **Phase 8 集成（本分支 `feat/single-buffer-perf`）**：T-064（Editor 行索引
  缓存：编辑失效、移动复用）紧随本切片；T-063（中间编辑 / 移动 / 大 blob
  基准）补齐数据；T-065（自动保存节流，反转 ADR-023「每次内容变更写入」粒度）
  与 T-066（SQLite WAL）为后续切片——用户已确认性能优先方向，语义冻结流程
  在 T-065 落地时留痕。
- 保存域语义冻结（ADR-023 v1.7）：本 ADR 是冻结期第一次方向确认
  （2026-08-03 用户指示），后续保存域改动仍须逐项确认。
- 实现切片：T-075（本 ADR 同切片交付消费者——Core / Bridge / App 全链路 +
  测试 + 门禁）。
