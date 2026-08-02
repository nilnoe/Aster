// swift-tools-version:6.2

// Aster App（T-011，ADR-015）：AppKit 壳，消费 bridge/ 的 AsterBridge 绑定。
// 决策依据：可执行目标不构成公共 API（Rule 4 不触发）；Swift App 规模预算
// （宪法 Rule 12：app/ ≤ 5,000 行）自此生效。

import PackageDescription

let package = Package(
    name: "AsterApp",
    // 决策依据（ADR-002）：仅支持最新 macOS；部署目标与 Rust C 对象
    // （build.sh 的 MACOSX_DEPLOYMENT_TARGET=26.0）保持一致，消除链接警告。
    platforms: [.macOS(.v26)],
    dependencies: [
        .package(path: "../bridge"),
    ],
    targets: [
        .executableTarget(
            name: "AsterApp",
            dependencies: [
                .product(name: "AsterBridge", package: "bridge"),
            ]
        ),
        .testTarget(
            name: "AsterAppTests",
            dependencies: [
                "AsterApp",
                .product(name: "AsterBridge", package: "bridge"),
            ]
        ),
    ]
)
