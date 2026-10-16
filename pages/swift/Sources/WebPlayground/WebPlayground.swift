import Foundation
import NucleantUI
import KivyRepresentable

/// The docs' playground: one window, a `KivyAppView` filling it, running
/// `kivy_playground` — app.py and app.kv as the page's editors hold them,
/// run again whenever they change (`kivy_playground_reload`).
@main
struct WebPlayground: KivyApp {
    /// Installed by ../build.sh, bundled as the target's resource.
    var site_packages: String {
        Bundle.module.resourceURL!.appendingPathComponent("site_packages").path
    }

    var body: some Scene {
        WindowGroup("Kivy Playground") {
            KivyAppView(module: "kivy_playground")
        }
    }
}
