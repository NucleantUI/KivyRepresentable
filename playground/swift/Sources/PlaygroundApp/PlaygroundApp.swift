import Foundation
import NucleantUI
import KivyRepresentable

/// Runs `playground`, or the module named on the command line
/// (`PlaygroundApp showcase`).
@main
struct PlaygroundApp: KivyApp {
    var body: some Scene {
        KivyWindowGroup("Kivy Playground", python: .init(
            module: CommandLine.arguments.dropFirst().first ?? "playground",
            sitePackages: [Bundle.module.resourceURL!.appendingPathComponent("site_packages").path]
        ))
    }
}
