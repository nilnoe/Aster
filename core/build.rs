//! 生成 swift-bridge 的 Swift 绑定与 C 头（T-010，ADR-014）。
//!
//! 决策依据：输出写入仓库级 `target/generated`（gitignore），由
//! `bridge/build.sh` 复制进 Swift 包——生成文件不提交，构建入口唯一。

use std::path::PathBuf;

fn main() {
    println!("cargo:rerun-if-changed=src/bridge.rs");

    let manifest_dir = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let out_dir = manifest_dir.join("../target/generated");
    swift_bridge_build::parse_bridges(["src/bridge.rs"])
        .write_all_concatenated(&out_dir, "aster_core");
}
