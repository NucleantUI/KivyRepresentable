import Testing
import NucleantUI
@testable import KivyRepresentable

struct DemoKivyApp: KivyApp {
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
}
