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

### Bridge（swift-bridge）

```text
./bridge/build.sh   # cargo build --release + 复制生成绑定 / staticlib / 传递依赖到 Swift 包
cd bridge && swift test
swift-format lint --recursive Tests   # 生成绑定（Sources/AsterBridge）为工具产物，不 lint
```

生成的 Swift 绑定与 `libaster_core.a` 不提交（gitignore），`bridge/build.sh` 是唯一入口；CI-Swift 作业执行同一脚本（ADR-014）。

### Swift

```text
swift-format lint --recursive Sources Tests
swift test
```

### App（AppKit + Metal 渲染）

```text
cd app && swift run          # 启动编辑器：Metal 视图渲染 Core Buffer 样例文本（含 CJK）
cd app && swift test         # 薄测试（AppInfo / 菜单结构）
```

app 依赖 bridge 的 AsterBridge 产品（本地包）；运行前先执行 `./bridge/build.sh` 生成绑定与 staticlib（T-011，ADR-015）。T-012 起内容视图为 MTKView（CoreText shaping → 字形图集 → Metal quad），T-013 起支持编辑循环：方向键 / 退格 / 回车、点击定位与拖选、滚轮滚动（T-018 起含横向滚动与光标横向可见性，ADR-019）、IME 组合文本内联显示与提交（经 `NSTextInputClient`），Edit 菜单撤销 / 重做 / 全选接线；T-015 起 File 菜单「打开…」（Cmd+O，NSOpenPanel）与文件拖入均经 DocumentManager 打开（ADR-001）。

### 构建运行

首个代码切片落地后补充具体命令（如 `xcodebuild` / `swift run`）。

## 质量门禁

任何 Commit 前必须全绿（宪法 Rule 6），并由 CI（`.github/workflows/ci.yml`）机械强制。

## 备注

- 路径与命令以首个代码切片（Rust Core 骨架）落地为准，届时更新本文档。

### 发布打包

打 `Beta-V*` tag 后 `CI-Release` workflow 自动执行：五项门禁 → `swift build -c release`
→ 打包 `Aster.app`（版本取自 core/Cargo.toml）→ zip 上传到 GitHub Release（ADR-020）。
本地等价命令：`./bridge/build.sh` + `cd app && swift build -c release`，再手工组装
`Aster.app/Contents`（MacOS/AsterApp + Info.plist）并 `zip`。
