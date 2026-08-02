# Release — 发布流程

## 分支模型

Trunk-based：`main` 永远可发布。功能走短生命周期分支 + PR（PR 模板强制门禁）。

## 版本

现阶段为 **Beta**，不考虑正式版。

- 版本模板：`Beta V0.0.0`
- **小补丁**（bug fix / 热修复）：递增末位 → `Beta V0.0.1`
- **功能开发**（新功能切片）：递增中间位，末位归零 → `Beta V0.1.0`
- **首位恒为 0**，Beta 阶段永不变化
- 版本号三处同步：Changelog、应用版本、git tag（格式 `Beta-V0.0.1`）
- 首个正式版为 `V1.0.0`；何时转正式版另行决定，Beta 阶段不为正式版预留任何流程

## 发布清单

1. **Changelog**：`Unreleased` 归档到 `[Beta V0.x.y]`，补发布日期。
2. **ADR**：本周期 `Proposed` → `Accepted` / `Rejected` / `Superseded`，更新索引。
3. **门禁**：CI 全绿 + 本地五项（宪法 Rule 6）。
4. **Benchmark**：确认基线无退化；有退化必须解释或回滚。
5. **Tag**：`Beta-V0.x.y`，推送后由 `CI-Release` workflow 自动跑门禁、
   构建 release、打包 `Aster.app` zip 并附加到 GitHub Release（ADR-020）；
   发布说明可直接在 Release 编辑。
6. **记录**：注明当时的最新 macOS 版本（ADR-002）。

## 热修复

严重 Bug：走 [docs/bug-workflow.md](bug-workflow.md)，修复后直接出 patch 版本，不等待下一里程碑。

## 节奏

无固定日期；Roadmap 里程碑完成即发布（复审政策见 [docs/roadmap.md](roadmap.md)）。
