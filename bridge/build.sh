#!/bin/sh
# 生成 swift-bridge 绑定并准备 Swift 包构建产物（T-010，ADR-014）。
#
# 决策依据：本地与 CI 使用同一入口；生成文件与 staticlib 不提交
# （target/ 与 bridge/artifacts、bridge/Sources/AsterBridge 均 gitignore）。
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BRIDGE="$ROOT/bridge"
GENERATED="$ROOT/target/generated"

# MACOSX_DEPLOYMENT_TARGET 与 Swift 包部署目标（.v26 → 26.0）一致：
# 否则 mlua / rusqlite 的 C 对象按 SDK 版本编译，链接时报
# "built for newer macOS version" 警告（ADR-002 / T-011 修复）。
MACOSX_DEPLOYMENT_TARGET=26.0 cargo build --release --manifest-path "$ROOT/core/Cargo.toml"

rm -rf "$BRIDGE/Sources/AsterBridge" "$BRIDGE/artifacts" "$BRIDGE/Sources/CAsterBridge/aster_core.h" "$BRIDGE/Sources/CAsterBridge/SwiftBridgeCore.h"
mkdir -p "$BRIDGE/Sources/AsterBridge" "$BRIDGE/artifacts"

# 生成的 Swift 需要 import CAsterBridge 才能解析 C 函数（与 create_package 前置
# import RustXcframework 同理）。
for swift in "$GENERATED/SwiftBridgeCore.swift" "$GENERATED/aster_core/aster_core.swift"; do
    name="$(basename "$swift")"
    { echo "import CAsterBridge"; cat "$swift"; } > "$BRIDGE/Sources/AsterBridge/$name"
done

cp "$GENERATED/aster_core/aster_core.h" "$BRIDGE/Sources/CAsterBridge/"
cp "$GENERATED/SwiftBridgeCore.h" "$BRIDGE/Sources/CAsterBridge/"
cp "$ROOT/target/release/libaster_core.a" "$BRIDGE/artifacts/"

# Rust staticlib 的传递静态依赖不会自动传播到 Swift 链接器（ADR-014 备注）：
# mlua vendored 的 Lua 与 rusqlite bundled 的 SQLite 需显式一并链接。
LUA_LIB="$(find "$ROOT/target/release/build" -name 'liblua5.4.a' | head -1)"
SQLITE_LIB="$(find "$ROOT/target/release/build" -name 'libsqlite3.a' | head -1)"
cp "$LUA_LIB" "$SQLITE_LIB" "$BRIDGE/artifacts/"
