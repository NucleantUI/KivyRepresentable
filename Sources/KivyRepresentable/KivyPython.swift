//
//  KivyPython.swift
//  KivyRepresentable
//
//  The embedded Python that runs Kivy, set up the way PythonLauncher's
//  isolated launcher does it: an isolated config, the standard library of
//  the Python this app links, the app's site-packages added with
//  `site.addsitedir`. The app's module then runs as `__main__` — and returns,
//  because a Kivy app hosted here doesn't loop (`App.run()` hands its loop to
//  the host's ticks).
//

import Foundation
import CPython

public enum KivyPython {

    public struct Configuration: Sendable {
        /// The Python module to run as `__main__` (`python -m <module>`).
        public var module: String
        /// Folders added with `site.addsitedir`: the app, Kivy and their
        /// dependencies, installed there by `uv pip install --target`.
        public var sitePackages: [String]
        /// PYTHONHOME: the standard library's prefix. Nil: the prefix of the
        /// Python framework/library this process linked.
        public var home: String?
        /// Set before Python starts, next to Kivy's own (`KIVY_WINDOW=nui`,
        /// `KIVY_GL_BACKEND=nui`, `KIVY_NO_ARGS=1`).
        public var environment: [String: String]

        public init(module: String, sitePackages: [String], home: String? = nil, environment: [String: String] = [:]) {
            self.module = module
            self.sitePackages = sitePackages
            self.home = home
            self.environment = environment
        }
    }

    public enum Error: Swift.Error, CustomStringConvertible {
        case status(String)
        case noHome
        case python(String)

        public var description: String {
            switch self {
            case .status(let message): "Python failed to start: \(message)"
            case .noHome: "could not find the Python home; set Configuration.home"
            case .python(let what): "Python: \(what) failed (traceback above)"
            }
        }
    }

    nonisolated(unsafe) private static var mainThreadState: UnsafeMutablePointer<PyThreadState>?

    /// Starts Python, if it isn't running yet, with Kivy's environment.
    public static func initialize(_ configuration: Configuration) throws {
        guard Py_IsInitialized() == 0 else { return }

        var environment = configuration.environment
        environment["KIVY_WINDOW"] = environment["KIVY_WINDOW"] ?? "nui"
        environment["KIVY_GL_BACKEND"] = environment["KIVY_GL_BACKEND"] ?? "nui"
        environment["KIVY_NO_ARGS"] = environment["KIVY_NO_ARGS"] ?? "1"
        for (key, value) in environment { setenv(key, value, 1) }
        setenv("LC_CTYPE", "UTF-8", 1)

        guard let home = configuration.home ?? linkedPythonHome() else { throw Error.noHome }
        let version = "python\(PY_MAJOR_VERSION).\(PY_MINOR_VERSION)"

        var preconfig = PyPreConfig()
        PyPreConfig_InitIsolatedConfig(&preconfig)
        preconfig.utf8_mode = 1
        try check(Py_PreInitialize(&preconfig))

        var config = PyConfig()
        PyConfig_InitIsolatedConfig(&config)
        defer { PyConfig_Clear(&config) }
        config.buffered_stdio = 0
        config.write_bytecode = 0
        config.module_search_paths_set = 1
        // Only the app's own packages: no site-packages of the Python this
        // links (python.org's may hold another Kivy). `site.addsitedir` below
        // still adds the app's, .pth files included.
        config.site_import = 0

        var configHome = config.home
        try check(PyConfig_SetBytesString(&config, &configHome, home))
        config.home = configHome
        try check(PyConfig_Read(&config))
        for path in ["\(home)/lib/\(version)", "\(home)/lib/\(version)/lib-dynload"] {
            let wide = Py_DecodeLocale(path, nil)
            defer { PyMem_RawFree(wide) }
            try check(PyWideStringList_Append(&config.module_search_paths, wide))
        }
        try check(Py_InitializeFromConfig(&config))

        for path in configuration.sitePackages {
            try run("import site; site.addsitedir(\(literal(path)))", what: "site.addsitedir(\(path))")
        }
    }

    /// Imports `module` (without running anything as `__main__`) — e.g. one
    /// of Kivy's own, to have the libraries it links loaded.
    public static func importModule(_ module: String) throws {
        try run("import \(module)", what: "import \(module)")
    }

    /// Runs `configuration.module` as `__main__`, then lets go of the GIL so
    /// Kivy's callbacks (its tick) can take it from here on.
    public static func runMain(_ configuration: Configuration) throws {
        let module = literal(configuration.module)
        try run(
            "import runpy, sys; sys.argv = [\(module)]; runpy.run_module(\(module), run_name='__main__', alter_sys=True)",
            what: "running \(configuration.module)"
        )
        mainThreadState = PyEval_SaveThread()
    }

    private static func run(_ code: String, what: String) throws {
        if PyRun_SimpleString(code) != 0 { throw Error.python(what) }
    }

    private static func check(_ status: PyStatus) throws {
        if PyStatus_Exception(status) != 0 {
            throw Error.status(status.err_msg.map { String(cString: $0) } ?? "unknown")
        }
    }

    /// A Python string literal for `string`.
    private static func literal(_ string: String) -> String {
        "'" + string.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "'", with: "\\'") + "'"
    }

    /// The prefix of the Python this process linked: the directory of the
    /// library that holds `Py_InitializeFromConfig` (…/Python.framework/
    /// Versions/3.13 for a framework build).
    private static func linkedPythonHome() -> String? {
        guard let library = LoadedLibraries.path(definingSymbol: "Py_InitializeFromConfig") else { return nil }
        var url = URL(fileURLWithPath: library).resolvingSymlinksInPath().deletingLastPathComponent()
        // A plain libpython (lib/libpython3.13.dylib) sits one level below
        // its prefix; a framework's Python binary sits at the prefix.
        if url.lastPathComponent == "lib" { url.deleteLastPathComponent() }
        return url.path
    }
}
