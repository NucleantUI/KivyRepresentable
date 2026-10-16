//
//  KivyApp.swift
//  KivyRepresentable
//
//  A `NucleantApp` whose windows render with `KivyRenderNode`, and which
//  runs Python: launched once, before the app's windows, with the app's
//  `site_packages`, and kept for its life. Its views get it as
//  `@Environment(\.kivyLauncher)`; each `KivyWindowGroup` runs its own
//  module in it.
//

import NucleantUI

public protocol KivyApp: NucleantApp where RenderNode == KivyRenderNode {
    /// The folder Python adds with `site.addsitedir` before any window runs
    /// its module: the app, Kivy and their dependencies
    /// (`uv pip install --target`).
    var site_packages: String { get }
}

extension KivyApp {
    /// Launches Python with the app's `site_packages`, then runs the app as
    /// `NucleantApp.main()` does, with the same instance.
    @MainActor
    public static func main() {
        let app = Self()
        let launcher = KivyLauncher(sitePackages: [app.site_packages])
        launcher.preLaunch()
        do {
            try launcher.initPython()
            launcher.onLaunch()
            KivyLauncherKey.launched = launcher
        } catch {
            print("KivyApp: \(error)")
        }
        let runtime = AppRuntime(app: app)
        runtime.setup()
        runtime.run()
    }
}

struct KivyLauncherKey: EnvironmentKey {
    /// The Python `KivyApp.main` launched; one per process, as CPython is.
    nonisolated(unsafe) static var launched: KivyLauncher?

    /// Outside a `KivyApp`: one that was never launched.
    static var defaultValue: KivyLauncher { launched ?? KivyLauncher(sitePackages: []) }
}

extension EnvironmentValues {
    /// The app's Python. `isLaunched` is false outside a `KivyApp`, or
    /// when Python failed to start.
    public var kivyLauncher: KivyLauncher {
        get { self[KivyLauncherKey.self] }
        set { self[KivyLauncherKey.self] = newValue }
    }
}
