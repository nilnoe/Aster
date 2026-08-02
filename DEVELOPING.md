# DEVELOPING — 构建与运行

目标环境（ADR-002）：仅支持**最新版 macOS**，使用 Xcode 最新稳定版。

## 前置要求

- macOS 最新版
- Xcode 最新稳定版（含 Command Line Tools）
- Rust stable（rustup 管理）
- swift-format：`brew install swift-format`
- swift-bridge CLI：按 [swift-bridge](https://github.com/chinedufn/swift-bridge) 官方指引安装

## 项目结构（预期）

```text
core/     Rust Core（Buffer、Layout、Theme、Undo、Event、Plugin、Lua、SQLite、PTY）
bridge/   Swift ↔ Rust 桥接（swift-bridge）
app/      Swift + AppKit + Metal（Window、Menu、Animation、Metal View）
```

## 常用命令

### Rust Core

```text
cargo fmt
cargo clippy --all-targets -- -D warnings
cargo test
```

### Swift

```text
swift-format lint --recursive Sources Tests
swift test
```

### 构建运行

首个代码切片落地后补充具体命令（如 `xcodebuild` / `swift run`）。

## 质量门禁

任何 Commit 前必须全绿（宪法 Rule 6），并由 CI（`.github/workflows/ci.yml`）机械强制。

## 备注

- 路径与命令以首个代码切片（Rust Core 骨架）落地为准，届时更新本文档。
