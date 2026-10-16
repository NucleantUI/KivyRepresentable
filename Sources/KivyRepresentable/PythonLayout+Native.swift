//
//  PythonLayout+Native.swift
//  KivyRepresentable
//
//  macOS, iOS, Linux, Android: the Python this process linked, in one
//  process with the app.
//

#if !os(WASI)
import Foundation
import CPython

extension PythonLayout {
    /// The prefix of the Python this process linked: the directory of the
    /// library that holds `Py_InitializeFromConfig` (…/Python.framework/
    /// Versions/3.13 for a framework build).
    func platformHome() -> String? {
        guard let library = LoadedLibraries().path(definingSymbol: "Py_InitializeFromConfig") else { return nil }
        var url = URL(fileURLWithPath: library).resolvingSymlinksInPath().deletingLastPathComponent()
        // A plain libpython (lib/libpython3.13.dylib) sits one level below
        // its prefix; a framework's Python binary sits at the prefix.
        if url.lastPathComponent == "lib" { url.deleteLastPathComponent() }
        return url.path
    }

    func platformStandardLibrary(home: String) -> [String] {
        let version = "python\(PY_MAJOR_VERSION).\(PY_MINOR_VERSION)"
        return ["\(home)/lib/\(version)", "\(home)/lib/\(version)/lib-dynload"]
    }

    /// One process, one environment.
    func platformEnvironmentToCopy() -> [String: String]? { nil }
}
#endif
