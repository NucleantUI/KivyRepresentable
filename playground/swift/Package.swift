// swift-tools-version: 6.2

import PackageDescription

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
            // The playground package, Kivy and their dependencies, installed
            // by ../build.sh (uv pip install --target).
            resources: [.copy("site_packages")],
            // CPython links Python.framework (python.org's 3.13), which the
            // linker no longer looks for in /Library/Frameworks on its own.
            linkerSettings: [.unsafeFlags(["-F/Library/Frameworks"])]
        ),
    ]
)
