// swift-tools-version: 6.2

import Foundation
import PackageDescription

/// Build against the sibling checkouts (`../NucleantVulkan`, `../NucleantUI`)
/// or against each repo on GitHub, decided the same way as in NucleantSkia:
/// `NUCLEANT_LOCAL_DEV=1|0` in the environment wins; otherwise local when the
/// sibling checkouts exist next to this package.
let devMode: Bool = {
    if let flag = ProcessInfo.processInfo.environment["NUCLEANT_LOCAL_DEV"] {
        return ["1", "true", "yes"].contains(flag.lowercased())
    }
    let siblings = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    return FileManager.default.fileExists(atPath: siblings.appendingPathComponent("NucleantVulkan").path)
}()

let package = Package(
    name: "KivyRepresentable",
    platforms: [
        .macOS(.v14),
        .iOS(.v17)
    ],
    products: [
        .library(name: "KivyRepresentable", targets: ["KivyRepresentable"]),
        // The shared C api as its own dynamic library: the Swift host and
        // Kivy's Cython extensions both link this one, so the host and Kivy
        // tables they register live in one place in the process.
        .library(name: "CKivyNUI", type: .dynamic, targets: ["CKivyNUI"]),
    ],
    dependencies: [("NucleantVulkan", "master"), ("NucleantUI", "master")].map { name, branch in
        devMode
            ? .package(path: "../\(name)")
            : .package(url: "https://github.com/NucleantUI/\(name).git", branch: branch)
    },
    targets: [
        .target(
            name: "CKivyNUI",
            path: "dependencies/CKivyNUI",
            exclude: ["generate_kivy_nui_gl.py"]
        ),
        // The shader node and the GL table behind it on NucleantVulkan —
        // the way NucleantSkia ships its own node — and the view that shows
        // it, built on NucleantUI as it is (NucleantUI itself is not changed).
        .target(
            name: "KivyRepresentable",
            dependencies: [
                "CKivyNUI",
                .product(name: "NucleantVulkan", package: "NucleantVulkan"),
                .product(name: "NucleantUI", package: "NucleantUI"),
            ]
        ),
        // The shared C api on its own: registration, forwarding and the
        // event queue, without the GPU or NucleantUI.
        .testTarget(
            name: "CKivyNUITests",
            dependencies: ["CKivyNUI"]
        ),
        .testTarget(
            name: "KivyRepresentableTests",
            dependencies: [
                "KivyRepresentable",
                .product(name: "NucleantUI", package: "NucleantUI"),
            ]
        ),
    ]
)
