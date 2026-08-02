# ADR-016 — Metal 文本渲染管线（spike）

- **Status:** Accepted
- **Date:** 2026-08-02
- **Version:** 1.0
- **新增 Public API:** 1 个（Bridge FFI：`layout_line_starts`）
- **影响模块:** app/（新增 Metal 渲染）、core/src/bridge.rs、core/src/layout.rs（内部访问器）
- **是否违反 Single Responsibility:** 否
- **是否增加循环依赖:** 否

---

## 决策

T-012 用 **CoreText shaping → 字形图集纹理 → Metal quad 绘制** 搭建最小 GPU 文本渲染管线，
替换 T-011 的空白视图：Core Buffer 的文本（经 Bridge）按行切分后逐行 shaping，
字形按需栅格化进单张 RGBA8 图集纹理，每字形以 6 顶点 quad 绘制；
视图实现系统 `NSTextInputClient`，IME 组合文本带下划线渲染，提交经 `buffer_insert` 写回 Core。

## 原因

- **总纲 3.2（Rendering — Metal）：** 拒绝 TextKit / CoreGraphics 的 CPU 渲染，整个编辑器走
  自己的 GPU 管线；本切片把「CoreText 拿字形 + Metal 画字形」的最小闭环跑通。
- **Principle 4（Do Not Fight The OS）：** shaping 与 IME 全部用系统能力（CoreText /
  `NSTextInputClient`），Metal 只负责绘制——不重复实现字形布局或输入法。
- **宪法 Rule 11（Reuse First）：** 行结构复用 Core 的 `Layout`（ADR-009 已注明 T-012
  基于其字节区间做视觉布局），App 不另造 `\n` 切分；字形缓存复用 CoreText 的
  `CTFontDrawGlyphs` 栅格化，不自己光栅化轮廓。
- **ADR-006 未确定项落定：** 「布局 / 字形缓存」进入实现前必须先定（ADR-006 规则），本 ADR 落定
  字形缓存与 GPU 缓冲格式；布局语义保持 ADR-009（逻辑行 + 字节区间，无软换行）。
- **垂直穿透：** 切片经 App（Metal 视图 + IME）→ Bridge（文本读 / `layout_line_starts` /
  `buffer_insert`）→ Core（Buffer / Layout）全链路，且 CJK 往返在 Bridge 测试中验证——
  swift-bridge 的 String 往返此前只测过 ASCII（T-010），CJK 是真实风险点。

## 审计

### Single Responsibility

App 新增文件各司一职：`EditorModel`（输入状态机，纯逻辑可测）、`GlyphAtlas`（字形栅格化 +
图集分配）、`TextRenderer`（Metal 管线与绘制）、`MetalView`（视图 + 输入事件采集）。
shaping 与像素坐标只存在于 App 层；Core 保持平台无关（ADR 总纲 3.3）。

### 循环依赖

`app → bridge → core` 单向；app 内的 `MetalView → TextRenderer / EditorModel`、
`TextRenderer → GlyphAtlas` 均无反向。

## 新增 Public API

| API | 职责 |
| --- | --- |
| Bridge `layout_line_starts(text: String) -> Vec<usize>` | 基于 Core `Layout::build` 返回每行起始字节偏移（首元素恒 0），App 用它把 Buffer 文本切行（ADR-009） |

Core 侧 `Layout::line_starts` 为 `pub(crate)` 访问器：仅 Bridge 使用，不构成公共 API
（宪法 Rule 12：`pub` 才是决策；Rule 4 不触发）。

## 影响模块

- **app/** — 空白 NSView 替换为 MetalView（T-011 预留的插入点）；新增 4 个源文件与对应测试。
- **core/src/bridge.rs** — 新增 1 个 FFI 函数；其余 API 面不变（复用 `Buffer::text` /
  `buffer_insert`）。
- **core/src/layout.rs** — 新增 `pub(crate)` 访问器 + 单元测试；公共 API 不变。
- **bridge/** — 生成绑定随 build.sh 自动更新；新增 CJK 往返测试。

## 复杂度预算（宪法 Rule 9）

1. **增加了哪些复杂度？** App 侧 1 条绘制管线（图集纹理 + quad 顶点流 + 一个内嵌 shader）、
   IME 客户端实现、1 个 Bridge FFI 函数；无新增依赖、无抽象层（Trait / Protocol）。
2. **是否是永久性的？** 图集 + quad 是 GPU 文本渲染的永久骨架（T-013 起在其上叠光标 /
   滚动 / 增量失效）；IME 客户端是永久结构，光标 / 选区状态机推迟到 T-013。
3. **有没有更简单但同样满足需求的方案？** 整行文本渲染为位图上屏（CoreGraphics）最简单，
   但违反总纲 3.2（CPU 渲染）；SDF / 每字独立纹理分别因复杂度与切换成本在 spike 阶段被拒。
   图集 + quad 是满足「GPU 渲染 + CJK + IME」的最低闭环。

结论：1 条管线 / 1 Bridge API / 0 抽象层 / 0 依赖，未触及红线。

## 备注

- **失效边界：** v1 图集按需增长，Buffer 文本变化即整体失效（`needsDisplay`），增量失效与
  Layout 重建一起在 T-013 细化；图集写满时整表重建（spike 文本规模远小于 2048² 图集）。
- **像素级栅格化（BUG-001 修订）：** 字形必须按像素尺寸栅格化——16pt 在 Retina（scale=2）
  下画成 32px 位图（`CTFontCreateCopyWithAttributes` 缩放），缓存键为
  font 名 + pixelSize + glyph；quad 位置吸附像素网格并配合 nearest 采样，保证 1:1 清晰。
- **颜色：** v1 顶点携带前景色（固定色），Theme 模型（T-006）的接线推迟到 T-014。
- **IME 边界：** 本切片只验证「组合文本渲染 + 提交写回 Core」闭环；光标移动、替换区间、
  选择编辑属 T-013 编辑循环。
- **刷新模型：** `enableSetNeedsDisplay` + 文本变化置 `needsDisplay`，无轮询
  （ADR Performance Goals：一切事件驱动）。
- **部署目标：** 与 ADR-002 / T-011 一致（manifest `.v26` + `MACOSX_DEPLOYMENT_TARGET=26.0`）。
