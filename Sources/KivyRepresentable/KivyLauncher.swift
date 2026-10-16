//
//  KivyLauncher.swift
//  KivyRepresentable
//
//  The embedded Python that runs Kivy, launched the way KivyLauncher
//  (kivy-school/KivyLauncher) does it: an isolated config, the standard
//  library of the Python this app links, the app's site-packages added with
//  `site.addsitedir`. A `KivyApp` launches it before its windows and keeps
//  it for the app's life; each Kivy window then runs its module in it as
//  `__main__`, which returns, because a Kivy app hosted here doesn't loop
//  (`App.run()` hands its loop to the host's ticks).
//

import Foundation
import CPython

public final class KivyLauncher {

    public enum Error: Swift.Error, CustomStringConvertible {
        case status(String)
        case noHome
        case python(String)

        public var description: String {
            switch self {
            case .status(let message): "Python failed to start: \(message)"
            case .noHome: "could not find the Python home; set `home`"
            case .python(let what): "Python: \(what) failed (traceback above)"
            }
        }
    }

    /// Folders added with `site.addsitedir`: the app, Kivy and their
    /// dependencies, installed there by `uv pip install --target`.
    public var sitePackages: [String]
    /// PYTHONHOME: the standard library's prefix. Nil: the prefix of the
    /// Python framework/library this process linked.
    public var home: String?
    /// The process environment, as Kivy reads it (`env.KIVY_WINDOW`).
    public var env = Environment()

    private var mainThreadState: UnsafeMutablePointer<PyThreadState>?

    /// Python is running and `onLaunch` has let go of the GIL.
    public var isLaunched: Bool { mainThreadState != nil }

    public init(sitePackages: [String], home: String? = nil) {
        self.sitePackages = sitePackages
        self.home = home
    }

    /// Kivy's environment, before Python starts: the host's window and GL,
    /// unless already set.
    public func preLaunch() {
        for (key, value) in [("KIVY_WINDOW", "nui"), ("KIVY_GL_BACKEND", "nui"), ("KIVY_NO_ARGS", "1")]
        where getenv(key) == nil {
            setenv(key, value, 1)
        }
        env.LC_CTYPE = "UTF-8"
    }

    /// Starts Python, if it isn't running yet.
    public func initPython() throws {
        guard Py_IsInitialized() == 0 else { return }
        let layout = PythonLayout()
        guard let home = home ?? layout.home() else { throw Error.noHome }

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
        for path in layout.standardLibrary(home: home) {
            let wide = Py_DecodeLocale(path, nil)
            defer { PyMem_RawFree(wide) }
            try check(PyWideStringList_Append(&config.module_search_paths, wide))
        }
        try check(Py_InitializeFromConfig(&config))
        if let environment = layout.environmentToCopy() {
            let items = environment.map { "\(literal($0.key)): \(literal($0.value))" }.joined(separator: ", ")
            try run("import os; os.environ.update({\(items)})", what: "setting the environment")
        }

        for path in sitePackages {
            try run("import site; site.addsitedir(\(literal(path)))", what: "site.addsitedir(\(path))")
        }
    }

    /// Python is up: lets go of the GIL, so Kivy's callbacks (its ticks) and
    /// the calls below take it when they run.
    public func onLaunch() {
        guard mainThreadState == nil else { return }
        mainThreadState = PyEval_SaveThread()
    }

    /// Imports `module` (without running anything as `__main__`), e.g. one
    /// of Kivy's own, to have the libraries it links loaded.
    public func importModule(_ module: String) throws {
        try run("import \(module)", what: "import \(module)")
    }

    /// Runs `module` as `__main__` (`python -m <module>`).
    public func runModule(_ module: String) throws {
        let name = literal(module)
        try run(
            "import runpy, sys; sys.argv = [\(name)]; runpy.run_module(\(name), run_name='__main__', alter_sys=True)",
            what: "running \(module)"
        )
    }

    /// Kivy's `dp` and `sp` at `scale` pixels per point, the view's display
    /// scale. Kivy finds the density itself only on macOS and Windows (from
    /// the window's dpi) and on iOS and Android (from their own modules);
    /// anywhere else, the browser among them, it is 1.
    ///
    /// Before Kivy's metrics are loaded, as `KIVY_METRICS_DENSITY`, which
    /// they read when imported: setting `Metrics.density` would have Kivy
    /// make its window there and then, ahead of the app. Once they are
    /// loaded (the scale changed while running), on `Metrics` itself.
    public func setDensity(_ scale: Double) throws {
        try run(
            """
            import os, sys
            os.environ['KIVY_METRICS_DENSITY'] = '\(scale)'
            if 'kivy.metrics' in sys.modules:
                sys.modules['kivy.metrics'].Metrics.density = \(scale)
            """,
            what: "Kivy's density \(scale)"
        )
    }

    /// Runs `code` holding the GIL: before `onLaunch` this thread has it;
    /// after, it is taken for the call.
    private func run(_ code: String, what: String) throws {
        let gil = mainThreadState == nil ? nil : PyGILState_Ensure()
        defer { if let gil { PyGILState_Release(gil) } }
        if PyRun_SimpleString(code) != 0 { throw Error.python(what) }
    }

    private func check(_ status: PyStatus) throws {
        if PyStatus_Exception(status) != 0 {
            throw Error.status(status.err_msg.map { String(cString: $0) } ?? "unknown")
        }
    }

    /// A Python string literal for `string`.
    private func literal(_ string: String) -> String {
        "'" + string.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
            .replacingOccurrences(of: "\n", with: "\\n") + "'"
    }
}

public extension KivyLauncher {

    /// The process environment by name, as KivyLauncher's: `env.KIVY_WINDOW
    /// = "nui"` sets it, reading gives nil when it isn't set.
    @dynamicMemberLookup
    struct Environment {

        public subscript(dynamicMember key: String) -> String? {
            get {
                if let result = key.withCString(getenv) {
                    return .init(cString: result)
                }
                return nil
            }
            set {
                if let newValue {
                    setenv(key, newValue, 1)
                } else {
                    unsetenv(key)
                }
            }
        }

        public subscript(dynamicMember key: String) -> Int? {
            get {
                if let result = key.withCString(getenv) {
                    return .init(String(cString: result))
                }
                return nil
            }
            set {
                if let newValue {
                    setenv(key, String(newValue), 1)
                } else {
                    unsetenv(key)
                }
            }
        }

        public subscript(dynamicMember key: String) -> Bool? {
            get {
                if let result = key.withCString(getenv) {
                    return .init(String(cString: result).lowercased())
                }
                return nil
            }
            set {
                if let newValue {
                    setenv(key, newValue ? "True" : "False", 1)
                } else {
                    unsetenv(key)
                }
            }
        }
    }
}
