// swift-tools-version: 6.2

import Foundation
import PackageDescription

/// Build against the sibling checkouts (`../NucleantVulkan`, `../NucleantUI`,
/// `../NucleantSkia`)
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

/// WebAssembly (`swift build --swift-sdk <version>_wasm`): the manifest can't
/// see the SDK, so it's the same explicit opt-in as in the packages this
/// builds on.
let wasm = ProcessInfo.processInfo.environment["WASM_BUILD"] == "1"

/// In the browser there is one module and no libCKivyNUI: the app has the C
/// api compiled in, and Kivy's extension modules, which Python loads next to
/// it, find it among the app's exports. So the app exports every
/// `KIVY_NUI_API` function of kivy_nui.h.
let kivyNUIExports: [LinkerSetting] = {
    let header = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .appendingPathComponent("dependencies/CKivyNUI/include/kivy_nui.h")
    guard let text = try? String(contentsOf: header, encoding: .utf8) else { return [] }
    let names = text.split(separator: "\n")
        .filter { $0.hasPrefix("KIVY_NUI_API ") }
        .compactMap { line in line.split(separator: "(").first?.split(separator: " ").last?.trimmingCharacters(in: CharacterSet(charactersIn: "*")) }
    return [.unsafeFlags(names.flatMap { ["-Xlinker", "--export-if-defined=\($0)"] })]
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
        // A windowless host for a process that already runs Python (tests):
        // Kivy renders through KivyRepresentable's GL, frames are read back.
        .library(name: "KivyNUIHeadless", type: .dynamic, targets: ["KivyNUIHeadless"]),
    ],
    dependencies: [("NucleantVulkan", "master"), ("NucleantUI", "master"), ("NucleantSkia", "master")].map { name, branch in
        devMode
            ? .package(path: "../\(name)")
            : .package(url: "https://github.com/NucleantUI/\(name).git", branch: branch)
    } + [
        // Python, embedded: how Kivy is started inside the Swift app. CPython
        // by the URL PySwiftKit uses, so the two are one package.
        .package(url: "https://github.com/Py-Swift/PySwiftKit.git", branch: "master"),
        .package(url: "https://github.com/py-swift/CPython", branch: "master"),
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
        // NucleantSkia draws into GL textures' images, as it is.
        .target(
            name: "KivyRepresentable",
            dependencies: [
                "CKivyNUI",
                .product(name: "NucleantVulkan", package: "NucleantVulkan"),
                .product(name: "NucleantShader", package: "NucleantVulkan"),
                .product(name: "NucleantUI", package: "NucleantUI"),
                .product(name: "NucleantSkia", package: "NucleantSkia"),
                .product(name: "PySwiftKitStatic", package: "PySwiftKit"),
                .product(name: "CPython", package: "CPython"),
            ],
            linkerSettings: wasm ? kivyNUIExports : []
        ),
        .target(
            name: "KivyNUIHeadless",
            dependencies: [
                "KivyRepresentable",
                .product(name: "NucleantSkia", package: "NucleantSkia"),
            ],
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
                .product(name: "NucleantSkia", package: "NucleantSkia"),
            ],
            linkerSettings: pythonFramework
        ),
    ]
)
