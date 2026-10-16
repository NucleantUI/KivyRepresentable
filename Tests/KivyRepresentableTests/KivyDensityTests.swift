import Foundation
import Testing
import CPython
@testable import KivyRepresentable

/// The native playground's Kivy (playground/build.sh installs it), where
/// it has been built.
private let playgroundSitePackages = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .appendingPathComponent("playground/swift/Sources/PlaygroundApp/site_packages").path

struct KivyDensityTests {

    /// Kivy finds no density of its own outside macOS, Windows, iOS and
    /// Android (the browser): the host's display scale is what `dp` and
    /// `sp` scale by.
    @Test(.enabled(if: FileManager.default.fileExists(atPath: playgroundSitePackages + "/kivy")))
    func kivyReadsTheHostsDensityWhenItsMetricsLoad() throws {
        let launcher = KivyLauncher(sitePackages: [playgroundSitePackages])
        launcher.preLaunch()
        try launcher.initPython()
        try launcher.setDensity(2)
        // This thread holds the GIL until `onLaunch`, which isn't called.
        // Set before Kivy's metrics are loaded, as the hosts do: they read
        // it when imported. (Not read through `Metrics` here: on macOS its dpi
        // asks for Kivy's window, which needs a host.)
        #expect(PyRun_SimpleString("import sys\nassert 'kivy.metrics' not in sys.modules") == 0)
        #expect(PyRun_SimpleString("import kivy.metrics\nassert kivy.metrics._default_density == 2.0, kivy.metrics._default_density") == 0)
        #expect(PyRun_SimpleString("import sys\nassert 'kivy.core.window' not in sys.modules") == 0)
    }
}
