import Foundation
import NucleantUI
import KivyRepresentable

/// Runs `playground`, or the module named on the command line
/// (`PlaygroundApp showcase`).
@main
struct PlaygroundApp: KivyApp {
    /// Installed by ../build.sh, bundled as the target's resource.
    var site_packages: String {
        Bundle.module.resourceURL!.appendingPathComponent("site_packages").path
    }

    var body: some Scene {
        KivyWindowGroup("Kivy Playground", module: CommandLine.arguments.dropFirst().first ?? "playground")
    }
}
