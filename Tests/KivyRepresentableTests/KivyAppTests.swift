import Testing
import NucleantUI
@testable import KivyRepresentable

struct DemoKivyApp: KivyApp {
    var site_packages: String { "/app/site_packages" }

    var body: some Scene {
        WindowGroup("Kivy") { EmptyView() }
    }
}

struct DemoNucleantApp: NucleantApp {
    var body: some Scene {
        WindowGroup("Nucleant") { EmptyView() }
    }
}

@MainActor
struct KivyAppTests {
    @Test func kivyAppRendersWithKivyRenderNode() {
        #expect(DemoKivyApp.RenderNode.self == KivyRenderNode.self)
    }

    @Test func nucleantAppKeepsNucleantRenderNode() {
        #expect(DemoNucleantApp.RenderNode.self == NucleantRenderNode.self)
    }

    @Test func kivyAppWindowsAreKivyNodeWindows() {
        let windows: [HostingWindow<DemoKivyApp.RenderNode>] = DemoKivyApp().body._makeWindows()
        #expect(windows.count == 1)
    }

    @Test func eachKivyWindowGroupHasItsOwnWindowAndSession() {
        let first = KivyWindowGroup("One", module: "one")
        let second = KivyWindowGroup("Two", module: "two")
        let firstWindows: [HostingWindow<KivyRenderNode>] = first._makeWindows()
        let secondWindows: [HostingWindow<KivyRenderNode>] = second._makeWindows()
        #expect(first.session !== second.session)
        #expect(first.session.module == "one" && second.session.module == "two")
        #expect(first.session.window === firstWindows.first)
        #expect(second.session.window === secondWindows.first)
        #expect(first.session.window !== second.session.window)
    }

    @Test func noPythonOutsideAKivyApp() {
        // Only `KivyApp.main` launches Python; tests never run it.
        #expect(EnvironmentValues().kivyLauncher.isLaunched == false)
    }

    @Test func launcherKeepsTheSitePackagesItIsGiven() {
        let launcher = KivyLauncher(sitePackages: ["/app/site_packages"], home: "/python")
        #expect(launcher.sitePackages == ["/app/site_packages"])
        #expect(launcher.home == "/python")
        #expect(launcher.isLaunched == false)
    }
}
