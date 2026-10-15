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

/// CPython links Python.framework (python.org's, in /Library/Frameworks),
/// which the linker no longer searches on its own. Only on what links here —
/// the library target stays free of unsafe flags for its dependents.
let pythonFramework: [LinkerSetting] = [.unsafeFlags(["-F/Library/Frameworks"])]

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
        // A windowless host for a process that already runs Python (tests):
        // Kivy renders through KivyRepresentable's GL, frames are read back.
        .library(name: "KivyNUIHeadless", type: .dynamic, targets: ["KivyNUIHeadless"]),
    ],
    dependencies: [("NucleantVulkan", "master"), ("NucleantUI", "master")].map { name, branch in
        devMode
            ? .package(path: "../\(name)")
            : .package(url: "https://github.com/NucleantUI/\(name).git", branch: branch)
    } + [
        // Python, embedded: how Kivy is started inside the Swift app. Local
        // checkouts for now.
        .package(path: "/Volumes/CodeSSD/dev_projects/pyswiftkit/PySwiftKit"),
        .package(path: "/Volumes/CodeSSD/dev_projects/pyswiftkit/CPython"),
    ],
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
                .product(name: "NucleantShader", package: "NucleantVulkan"),
                .product(name: "NucleantUI", package: "NucleantUI"),
                .product(name: "PySwiftKitStatic", package: "PySwiftKit"),
                .product(name: "CPython", package: "CPython"),
            ]
        ),
        .target(
            name: "KivyNUIHeadless",
            dependencies: ["KivyRepresentable"],
            linkerSettings: pythonFramework
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
            ],
            linkerSettings: pythonFramework
        ),
    ]
)
