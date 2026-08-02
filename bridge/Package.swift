// swift-tools-version:6.0

// Aster Bridge：swift-bridge 生成的 Swift 绑定 + Rust staticlib 链接（T-010，ADR-014）。
// 决策依据：
// - 生成文件（Swift 绑定 + C 头）与 .a 由 bridge/build.sh 复制，不提交（.gitignore）。
// - CAsterBridge 是 systemLibrary：modulemap 把生成的 C 头暴露给 Swift
//   （生成的 Swift 直接引用 __swift_bridge__$* 函数，无 @_silgen_name 声明），
//   并在 modulemap 中 link "aster_core"。
// - artifacts 目录用 #filePath 计算绝对路径，避免链接器相对路径歧义
//   （manifest 环境无 Foundation，用字符串切分）。

import PackageDescription

// #filePath 在 manifest 编译环境可能丢前导斜杠，统一补成绝对路径。
let rawPackageDir = #filePath.split(separator: "/").dropLast().joined(separator: "/")
let packageDir = rawPackageDir.hasPrefix("/") ? rawPackageDir : "/" + rawPackageDir

let package = Package(
    name: "AsterBridge",
    targets: [
        .systemLibrary(
            name: "CAsterBridge",
            path: "Sources/CAsterBridge"
        ),
        .target(
            name: "AsterBridge",
            dependencies: ["CAsterBridge"],
            linkerSettings: [
                .unsafeFlags(["-L", packageDir + "/artifacts"]),
                .linkedLibrary("aster_core"),
                // 传递静态依赖（mlua vendored Lua / rusqlite bundled SQLite）：
                // staticlib 不传播 link 属性，需按依赖顺序显式声明（ADR-014）。
                .linkedLibrary("lua5.4"),
                .linkedLibrary("sqlite3"),
            ]
        ),
        .testTarget(
            name: "AsterBridgeTests",
            dependencies: ["AsterBridge"]
        ),
    ]
)
