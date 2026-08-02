# Security Policy

## 报告漏洞

- 方式：GitHub Issue（标注 security）或直接联系维护者。
- 响应：尽快确认；修复走 [docs/bug-workflow.md](docs/bug-workflow.md) + 紧急 patch 发布。

## 信任模型

- 插件默认被信任（ADR-003）：用户对自己安装的插件负责。
- PTY 内容视为不可信数据，不作为代码执行来源。
- 默认无遥测、无崩溃上报（ADR-004）。

## 最佳实践

- 依赖锁定 + 定期 audit（[docs/dependencies.md](docs/dependencies.md)）。
- 公开仓库不提交任何密钥 / 凭据。
