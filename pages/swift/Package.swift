// swift-tools-version: 6.2

import Foundation
import PackageDescription

/// NucleantUI from the sibling checkout next to KivyRepresentable, or from
/// GitHub, decided as KivyRepresentable decides it: `NUCLEANT_LOCAL_DEV`, else
/// whether the sibling exists.
let devMode: Bool = {
    if let flag = ProcessInfo.processInfo.environment["NUCLEANT_LOCAL_DEV"] {
        return ["1", "true", "yes"].contains(flag.lowercased())
    }
    let siblings = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    return FileManager.default.fileExists(atPath: siblings.appendingPathComponent("NucleantUI").path)
}()

/// WebAssembly (`WASM_BUILD=1`, as for the packages the app builds on).
let wasm = ProcessInfo.processInfo.environment["WASM_BUILD"] == "1"

let package = Package(
    name: "WebPlayground",
    platforms: [
        .macOS(.v14),
    ],
    dependencies: [
        .package(path: "../.."), // KivyRepresentable
        devMode
            ? .package(path: "../../../NucleantUI")
            : .package(url: "https://github.com/NucleantUI/NucleantUI.git", branch: "master"),
        // Python's C api, for handing the page's sources to the runner: the
        // CPython KivyRepresentable uses.
        .package(url: "https://github.com/py-swift/CPython", branch: "master"),
    ],
    targets: [
        .target(name: "CKivyPlaygroundPage"),
        .executableTarget(
            name: "WebPlayground",
            dependencies: [
                "CKivyPlaygroundPage",
                .product(name: "KivyRepresentable", package: "KivyRepresentable"),
                .product(name: "NucleantUI", package: "NucleantUI"),
                .product(name: "CPython", package: "CPython"),
            ],
            // site_packages: kivy_playground, Kivy and their dependencies,
            // installed by ../build.sh (uv pip install --target). The host
            // script is the page's side (Web/nucleant-app.js loads it).
            resources: [.copy("site_packages"), .copy("kivy-playground.wasm-host.mjs")],
            linkerSettings: wasm ? [] : [.unsafeFlags(["-F/Library/Frameworks"])]
        ),
    ]
)
