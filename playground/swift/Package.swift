// swift-tools-version: 6.2

import Foundation
import PackageDescription

/// WebAssembly (`WASM_BUILD=1`, as for the packages the app builds on): the
/// app's packages are the Pyodide builds, from wasm/site_packages.
let wasm = ProcessInfo.processInfo.environment["WASM_BUILD"] == "1"
let sources = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Sources/PlaygroundApp")
let otherPlatform = wasm ? "site_packages" : "wasm"

let package = Package(
    name: "PlaygroundApp",
    platforms: [
        .macOS(.v14),
    ],
    dependencies: [
        .package(path: "../.."), // KivyRepresentable
        .package(path: "../../../NucleantUI"),
    ],
    targets: [
        .executableTarget(
            name: "PlaygroundApp",
            dependencies: [
                .product(name: "KivyRepresentable", package: "KivyRepresentable"),
                .product(name: "NucleantUI", package: "NucleantUI"),
            ],
            exclude: FileManager.default.fileExists(atPath: sources.appendingPathComponent(otherPlatform).path) ? [otherPlatform] : [],
            // The playground package, Kivy and their dependencies, installed
            // by ../build.sh (uv pip install --target) — the bundle's
            // site_packages either way.
            resources: [.copy(wasm ? "wasm/site_packages" : "site_packages")],
            // CPython links Python.framework (python.org's 3.13), which the
            // linker no longer looks for in /Library/Frameworks on its own.
            linkerSettings: wasm ? [] : [.unsafeFlags(["-F/Library/Frameworks"])]
        ),
    ]
)
