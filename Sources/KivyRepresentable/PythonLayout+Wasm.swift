//
//  PythonLayout+Wasm.swift
//  KivyRepresentable
//
//  The browser: Python is Pyodide's build, loaded next to the app by the
//  CPython package's page host (pyodide.wasm-host.mjs), in its own runtime
//  with its own file system and C library.
//

#if os(WASI)
import Foundation
import CPython

extension PythonLayout {
    /// The host puts the standard library at /lib.
    func platformHome() -> String? { "/" }

    /// The standard library as the host writes it: one archive,
    /// /lib/python313.zip, plus the folders Python looks in next to it.
    func platformStandardLibrary(home: String) -> [String] {
        let lib = home.hasSuffix("/") ? "\(home)lib" : "\(home)/lib"
        return [
            "\(lib)/python\(PY_MAJOR_VERSION)\(PY_MINOR_VERSION).zip",
            "\(lib)/python\(PY_MAJOR_VERSION).\(PY_MINOR_VERSION)",
            "\(lib)/python\(PY_MAJOR_VERSION).\(PY_MINOR_VERSION)/lib-dynload",
        ]
    }

    /// Python's C library is not the app's: its environment starts empty,
    /// so it gets the app's — KIVY_WINDOW and the rest that `preLaunch` set.
    func platformEnvironmentToCopy() -> [String: String]? {
        ProcessInfo.processInfo.environment
    }
}

extension LoadedLibraries {
    /// One module: no shared libraries to look through.
    func platformPath(named fileName: String) -> String? { nil }
    func platformPath(definingSymbol symbol: String) -> String? { nil }
}
#endif
