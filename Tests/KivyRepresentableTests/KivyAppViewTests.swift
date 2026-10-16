import Testing
import NucleantUI
@testable import KivyRepresentable

struct DemoKivyViewApp: KivyApp {
    var site_packages: String { "/app/site_packages" }

    var body: some Scene {
        WindowGroup("Kivy in a view") {
            HStack {
                Text("Beside Kivy")
                KivyAppView(module: "playground")
            }
        }
    }
}

@MainActor
@Suite(.serialized)
struct KivyAppViewTests {

    init() {
        KivyAppSession.awaitingEngine.removeAll()
        KivyAppSession.current = nil
    }

    @Test func aKivyAppViewGoesInAnOrdinaryWindowGroup() {
        let windows: [HostingWindow<DemoKivyViewApp.RenderNode>] = DemoKivyViewApp().body._makeWindows()
        #expect(windows.count == 1)
    }

    @Test func placingRecordsTheFrameAndWaitsForTheEngineOnce() {
        let session = KivyAppSession(module: "playground")
        session.placed(in: Rect(x: 10, y: 20, width: 300, height: 200))
        session.placed(in: Rect(x: 12, y: 20, width: 300, height: 200))
        #expect(session.bounds == Rect(x: 12, y: 20, width: 300, height: 200))
        #expect(KivyAppSession.awaitingEngine.count == 1)
        #expect(KivyAppSession.awaitingEngine.first === session)
        #expect(session.engine == nil)
    }

    @Test func sessionsWaitForTheEngineInTheOrderPlaced() {
        let first = KivyAppSession(module: "playground")
        let second = KivyAppSession(module: "playground")
        first.placed(in: Rect(x: 0, y: 0, width: 100, height: 100))
        second.placed(in: Rect(x: 100, y: 0, width: 100, height: 100))
        #expect(KivyAppSession.awaitingEngine.count == 2)
        #expect(KivyAppSession.awaitingEngine[0] === first && KivyAppSession.awaitingEngine[1] === second)
    }

    @Test func pixelFrameIsTheFrameAtTheDisplayScale() {
        let session = KivyAppSession(module: "playground")
        session.displayScale = 2
        session.placed(in: Rect(x: 10.25, y: 20.75, width: 100.2, height: 50))
        let frame = session.pixelFrame
        // The origin rounds down to a whole pixel, the size up to cover the frame.
        #expect(frame.x == 20 && frame.y == 41)
        #expect(frame.width == 201 && frame.height == 100)
    }

    @Test func anEmptyFrameStillHasAPixel() {
        let session = KivyAppSession(module: "playground")
        session.placed(in: Rect(x: 0, y: 0, width: 0, height: 0))
        #expect(session.pixelFrame.width == 1 && session.pixelFrame.height == 1)
    }

    @Test func appearingShows() {
        let session = KivyAppSession(module: "playground")
        session.appear(launcher: KivyLauncher(sitePackages: []), displayScale: 2)
        #expect(session.isShown)
        #expect(session.displayScale == 2)
    }

    @Test func everyViewShowsTheOneKivyRunning() {
        let first = KivyAppSession.running(module: "playground")
        let again = KivyAppSession.running(module: "playground")
        let other = KivyAppSession.running(module: "showcase")
        #expect(first === again && first === other)
        #expect(first.module == "playground")
    }

    @Test func disappearingHidesAndStopsWaiting() {
        let session = KivyAppSession(module: "playground")
        session.appear(launcher: KivyLauncher(sitePackages: []), displayScale: 1)
        session.placed(in: Rect(x: 0, y: 0, width: 100, height: 100))
        session.disappear()
        #expect(!session.isShown)
        #expect(KivyAppSession.awaitingEngine.isEmpty)
    }
}
