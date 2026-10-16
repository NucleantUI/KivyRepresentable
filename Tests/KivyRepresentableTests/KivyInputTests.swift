import Testing
import CKivyNUI
import NucleantUI
@testable import KivyRepresentable

/// One event as Kivy's nui window reads it, for the pointer and touches.
enum InputEvent: Equatable {
    case motion(Int32, Int32)
    case buttonDown(Int32, Int32, UInt8)
    case buttonUp(Int32, Int32, UInt8)
    case wheel(Int32, Int32, at: Int32, Int32)
    case fingerDown(Int64, Float, Float)
    case fingerMotion(Int64, Float, Float)
    case fingerUp(Int64, Float, Float)
    case leave
    case key(Int32)
    case text
}

@MainActor
final class InputEvents {
    var events: [InputEvent] = []

    /// Kivy at (100, 50), 200 × 100 points, in its window.
    lazy var input: KivyInput = {
        let input = KivyInput { [unowned self] event in
            switch event.type {
            case KIVY_NUI_EVENT_MOUSE_MOTION: events.append(.motion(event.mouse.x, event.mouse.y))
            case KIVY_NUI_EVENT_MOUSE_BUTTON_DOWN: events.append(.buttonDown(event.mouse.x, event.mouse.y, event.mouse.button))
            case KIVY_NUI_EVENT_MOUSE_BUTTON_UP: events.append(.buttonUp(event.mouse.x, event.mouse.y, event.mouse.button))
            case KIVY_NUI_EVENT_MOUSE_WHEEL:
                events.append(.wheel(event.wheel.x, event.wheel.y, at: event.wheel.mouse_x, event.wheel.mouse_y))
            case KIVY_NUI_EVENT_FINGER_DOWN: events.append(.fingerDown(event.finger.finger_id, event.finger.x, event.finger.y))
            case KIVY_NUI_EVENT_FINGER_MOTION: events.append(.fingerMotion(event.finger.finger_id, event.finger.x, event.finger.y))
            case KIVY_NUI_EVENT_FINGER_UP: events.append(.fingerUp(event.finger.finger_id, event.finger.x, event.finger.y))
            case KIVY_NUI_EVENT_WINDOW_LEAVE: events.append(.leave)
            case KIVY_NUI_EVENT_KEY_DOWN, KIVY_NUI_EVENT_KEY_UP: events.append(.key(event.key.keycode))
            case KIVY_NUI_EVENT_TEXT_INPUT: events.append(.text)
            default: break
            }
        }
        input.frame = Rect(x: 100, y: 50, width: 200, height: 100)
        return input
    }()

    func take() -> [InputEvent] {
        defer { events = [] }
        return events
    }
}

@MainActor
struct KivyInputTests {

    @Test func aPressInTheFrameIsKivysInItsOwnPoints() {
        let sent = InputEvents()
        #expect(sent.input.windowMouseDown(at: Point(x: 110, y: 60), modifiers: []))
        #expect(sent.take() == [.motion(10, 10), .buttonDown(10, 10, 1)])
    }

    @Test func aPressOutsideIsTheViewsAndKivyNeverHearsOfIt() {
        let sent = InputEvents()
        #expect(!sent.input.windowMouseDown(at: Point(x: 10, y: 10), modifiers: []))
        #expect(!sent.input.windowMouseDragged(to: Point(x: 150, y: 80)))
        #expect(!sent.input.windowMouseUp(at: Point(x: 150, y: 80)))
        #expect(sent.take() == [])
    }

    @Test func aPressInTheFrameKeepsItsDragsAndReleaseWhereverTheyGo() {
        let sent = InputEvents()
        _ = sent.input.windowMouseDown(at: Point(x: 110, y: 60), modifiers: [])
        _ = sent.take()
        #expect(sent.input.windowMouseDragged(to: Point(x: 400, y: 60)))
        #expect(sent.input.windowMouseUp(at: Point(x: 400, y: 60)))
        #expect(sent.take() == [.motion(300, 10), .buttonUp(300, 10, 1)])
    }

    @Test func theRightButtonIsSDLsThird() {
        let sent = InputEvents()
        #expect(sent.input.windowRightMouseDown(at: Point(x: 110, y: 60)))
        #expect(sent.input.windowRightMouseUp(at: Point(x: 110, y: 60)))
        #expect(sent.take() == [.motion(10, 10), .buttonDown(10, 10, 3), .buttonUp(10, 10, 3)])
    }

    @Test func hoverIsKivysMotionAndLeavingItsWindowLeaveButTheViewsSeeItToo() {
        let sent = InputEvents()
        #expect(!sent.input.windowMouseMoved(to: Point(x: 120, y: 70)))
        #expect(!sent.input.windowMouseMoved(to: Point(x: 10, y: 10)))
        #expect(!sent.input.windowMouseMoved(to: Point(x: 5, y: 5)))
        #expect(sent.take() == [.motion(20, 20), .leave])
    }

    @Test func theWheelIsOneSDLStepOnTheAxisMovedMore() {
        let sent = InputEvents()
        #expect(sent.input.windowScroll(dx: 0.5, dy: 7, at: Point(x: 150, y: 100)))
        #expect(sent.input.windowScroll(dx: 0, dy: -0.25, at: Point(x: 150, y: 100)))
        #expect(sent.input.windowScroll(dx: 3, dy: 1, at: Point(x: 150, y: 100)))
        #expect(!sent.input.windowScroll(dx: 0, dy: 3, at: Point(x: 10, y: 10)))
        #expect(sent.take() == [.wheel(0, 1, at: 50, 50), .wheel(0, -1, at: 50, 50), .wheel(-1, 0, at: 50, 50)])
    }

    @Test func fingersAreKivysTouchesNormalizedOverTheFrame() {
        let sent = InputEvents()
        #expect(sent.input.windowTouchDown(id: 1, at: Point(x: 150, y: 75)))
        #expect(sent.input.windowTouchDown(id: 2, at: Point(x: 250, y: 125)))
        #expect(!sent.input.windowTouchDown(id: 3, at: Point(x: 10, y: 10)))
        #expect(sent.input.windowTouchMoved(id: 1, to: Point(x: 200, y: 100)))
        #expect(!sent.input.windowTouchMoved(id: 3, to: Point(x: 150, y: 75)))
        #expect(sent.input.windowTouchUp(id: 1, at: Point(x: 200, y: 100)))
        #expect(sent.input.windowTouchCancelled(id: 2, at: Point(x: 250, y: 125)))
        #expect(!sent.input.windowTouchUp(id: 3, at: Point(x: 10, y: 10)))
        #expect(sent.take() == [
            .fingerDown(1, 0.25, 0.25), .fingerDown(2, 0.75, 0.75),
            .fingerMotion(1, 0.5, 0.5),
            .fingerUp(1, 0.5, 0.5), .fingerUp(2, 0.75, 0.75),
        ])
    }

    @Test func thePressThatLastWentToKivyGivesItTheKeys() {
        let sent = InputEvents()
        #expect(!sent.input.windowKeyDown(keyCode: 0x00, characters: "a", modifiers: []))
        _ = sent.input.windowMouseDown(at: Point(x: 110, y: 60), modifiers: [])
        _ = sent.input.windowMouseUp(at: Point(x: 110, y: 60))
        _ = sent.take()
        #expect(sent.input.windowKeyDown(keyCode: 0x00, characters: "a", modifiers: []))
        #expect(sent.input.windowKeyUp(keyCode: 0x00, characters: "a", modifiers: []))
        #expect(sent.take() == [.key(97), .text, .key(97)])
        _ = sent.input.windowMouseDown(at: Point(x: 10, y: 10), modifiers: [])
        #expect(!sent.input.windowKeyDown(keyCode: 0x00, characters: "a", modifiers: []))
        #expect(sent.take() == [])
    }

    @Test func aTouchGivesKivyTheKeysToo() {
        let sent = InputEvents()
        _ = sent.input.windowTouchDown(id: 0, at: Point(x: 110, y: 60))
        #expect(sent.input.windowKeyDown(keyCode: 0x24, characters: "\r", modifiers: []))
        _ = sent.input.windowTouchDown(id: 1, at: Point(x: 10, y: 10))
        #expect(!sent.input.windowKeyDown(keyCode: 0x24, characters: "\r", modifiers: []))
    }
}
