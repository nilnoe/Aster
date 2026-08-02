# ADR-020 — CI 发布流水线（自动构建 + 打包 + 附件）

- **Status:** Accepted
- **Date:** 2026-08-02
- **Version:** 1.0
- **新增 Public API:** 0（CI 基础设施；不影响运行时）
- **影响模块:** .github/workflows/ci-release.yml、docs/release.md、DEVELOPING.md
- **是否违反 Single Responsibility:** 否
- **是否增加循环依赖:** 否

---

## 决策

新增 `CI-Release` workflow：打 `Beta-V*` tag（或手动 dispatch）时，
先跑五项质量门禁（Release Gates），再构建 release 二进制、打包
`Aster.app`（含 Info.plist，版本取自 core/Cargo.toml 单一来源）、
zip 后作为附件上传到同名 GitHub Release；产物同时存为 workflow artifact。

## 原因

- **Beta V0.1.0 / V0.1.1 的压缩包都是手动打包上传**：发布清单第 5 步（Tag）
  没有机械执行，易漏、不可复现。流水线化后「打 tag = 自动发布」，与
  Trunk-based / CI 机械门禁（宪法 Rule 6 精神）一致。
- **门禁与打包同 workflow**：tag 上的提交不触发 ci-rust / ci-swift（分支推送
  过滤），Release Gates 保证发布时全绿（docs/release.md 清单第 3 项）。
- **版本单一来源**：Info.plist 版本从 `core/Cargo.toml` 读取（ADR-015 惯例），
  不手写。
- **新增依赖论证（Rule 7 / 8）**：GitHub 标准库（原生 Action）无「上传文件到
  Release」能力；`softprops/action-gh-release`（生态事实标准）与
  `actions/upload-artifact`（官方）按 major tag 锁定；不引入运行时依赖。

## 审计

### Single Responsibility

workflow 只做「发布」：门禁 → 构建 → 打包 → 附件；质量门禁本身仍在 ci-rust /
ci-swift 维护，Release Gates 是发布时刻的复核。

### 循环依赖

无；workflow 单向消费仓库代码与 Release API。

## 新增 Public API

无。

## 影响模块

- **.github/workflows/ci-release.yml** — 新增。
- **docs/release.md** — 发布清单第 5 步改为「打 tag，CI-Release 自动构建打包」。
- **DEVELOPING.md** — 补充发布打包说明（本地等价命令）。

## 复杂度预算（宪法 Rule 9）

1. **增加了哪些复杂度？** 1 个 workflow（约 60 行）+ 2 个 CI Action 引用；
   0 运行时依赖。
2. **是否是永久性的？** 发布流水线是长期基础设施；Action 版本随升级策略更新
   （docs/dependencies.md 的升级策略同样适用）。
3. **有没有更简单但同样满足需求的方案？** 继续手动打包——每次发布重复劳动且
   不可复现；只用官方 action 不附 zip——无法满足「发布 app 压缩包」需求。

结论：1 workflow / 2 CI 引用 / 0 运行时依赖，未触及红线。

## 备注

- 手动 dispatch 在 main 上只跑「门禁 + 构建 + 打包 + artifact」，不建 Release
  （附件步骤按 tag 前缀条件跳过），便于验证流水线。
- 产物未签名 / 未公证：用户首次打开需右键 → 打开；正式版 V1.0.0 前按需评估
  Developer ID 签名与公证（不排期）。
