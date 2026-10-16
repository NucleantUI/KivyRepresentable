//
//  KivyInput.swift
//  KivyRepresentable
//
//  The window's input for Kivy, as SDL reported it, taken before the view
//  tree sees it (the window's `WindowInputDelegate`, `\.windowInput`):
//
//    - a press in Kivy's frame is Kivy's: SDL's mouse button events, and the
//      drags and the release that follow it, wherever they go; it gives
//      Kivy the keys, and a press anywhere else takes them away;
//    - the mouse moving over the frame is Kivy's motion (its hover, its
//      `mouse_pos`) and leaving it Kivy's window leave, but the views see
//      the moves too;
//    - the wheel over the frame scrolls Kivy, one SDL wheel step per event;
//    - a finger down in the frame is one of Kivy's touches until it lifts;
//    - the keys, while Kivy has them, are SDL's key and text events
//      (KivyKeyboard).
//
//  Everything Kivy takes is kept from the views. Positions are Kivy's: the
//  frame's points from its top-left.
//

import CKivyNUI
import NucleantUI
import NucleantWindow

@MainActor
final class KivyInput: WindowInputDelegate {
    /// Where the events go: the host's queue, which Kivy reads on its tick.
    let send: (KivyNUIEvent) -> Void
    let keyboard: KivyKeyboard

    /// Kivy's frame in the window, in points.
    var frame: Rect = .zero
    /// A press in the frame gave Kivy the keys; one elsewhere took them.
    private(set) var hasKeys = false

    /// SDL's mouse buttons held down since a press in the frame.
    private var buttons: Set<UInt8> = []
    /// The fingers that went down in the frame, not lifted yet.
    private var fingers: Set<Int> = []
    /// The mouse was over the frame when last moved.
    private var isHovering = false

    init(send: @escaping (KivyNUIEvent) -> Void) {
        self.send = send
        self.keyboard = KivyKeyboard(send: send)
    }

    // MARK: - Mouse

    func windowMouseDown(at point: Point, modifiers: EventModifiers) -> Bool {
        press(1, at: point)
    }

    func windowMouseDragged(to point: Point) -> Bool {
        guard !buttons.isEmpty else { return false }
        mouse(KIVY_NUI_EVENT_MOUSE_MOTION, at: point, button: 0)
        return true
    }

    func windowMouseUp(at point: Point) -> Bool {
        release(1, at: point)
    }

    func windowRightMouseDown(at point: Point) -> Bool {
        press(3, at: point)
    }

    func windowRightMouseUp(at point: Point) -> Bool {
        release(3, at: point)
    }

    func windowMouseMoved(to point: Point) -> Bool {
        if frame.contains(point) {
            isHovering = true
            mouse(KIVY_NUI_EVENT_MOUSE_MOTION, at: point, button: 0)
        } else if isHovering {
            isHovering = false
            var event = KivyNUIEvent()
            event.type = KIVY_NUI_EVENT_WINDOW_LEAVE
            send(event)
        }
        return false
    }

    func windowScroll(dx: Double, dy: Double, at point: Point) -> Bool {
        guard frame.contains(point), dx != 0 || dy != 0 else { return false }
        let local = local(point)
        var event = KivyNUIEvent()
        event.type = KIVY_NUI_EVENT_MOUSE_WHEEL
        // SDL's signs, AppKit's deltas (which `dx`/`dy` follow): y as is, x
        // negated. One axis, the one moved more: Kivy reads one per event.
        event.wheel = abs(dx) > abs(dy)
            ? KivyNUIWheelEvent(x: dx > 0 ? -1 : 1, y: 0, mouse_x: local.x, mouse_y: local.y)
            : KivyNUIWheelEvent(x: 0, y: dy > 0 ? 1 : -1, mouse_x: local.x, mouse_y: local.y)
        send(event)
        return true
    }

    /// SDL button `button` pressed at `point`: Kivy's, with the keys, when in
    /// its frame; otherwise the views', and the keys go with it.
    private func press(_ button: UInt8, at point: Point) -> Bool {
        guard frame.contains(point) else {
            hasKeys = false
            return false
        }
        hasKeys = true
        buttons.insert(button)
        mouse(KIVY_NUI_EVENT_MOUSE_MOTION, at: point, button: 0)
        mouse(KIVY_NUI_EVENT_MOUSE_BUTTON_DOWN, at: point, button: button)
        return true
    }

    private func release(_ button: UInt8, at point: Point) -> Bool {
        guard buttons.remove(button) != nil else { return false }
        mouse(KIVY_NUI_EVENT_MOUSE_BUTTON_UP, at: point, button: button)
        return true
    }

    private func mouse(_ type: KivyNUIEventType, at point: Point, button: UInt8) {
        let local = local(point)
        var event = KivyNUIEvent()
        event.type = type
        event.mouse = KivyNUIMouseEvent(x: local.x, y: local.y, button: button)
        send(event)
    }

    private func local(_ point: Point) -> (x: Int32, y: Int32) {
        (Int32((point.x - frame.minX).rounded()), Int32((point.y - frame.minY).rounded()))
    }

    // MARK: - Touches

    func windowTouchDown(id: Int, at point: Point) -> Bool {
        guard frame.contains(point) else {
            hasKeys = false
            return false
        }
        hasKeys = true
        fingers.insert(id)
        finger(KIVY_NUI_EVENT_FINGER_DOWN, id: id, at: point)
        return true
    }

    func windowTouchMoved(id: Int, to point: Point) -> Bool {
        guard fingers.contains(id) else { return false }
        finger(KIVY_NUI_EVENT_FINGER_MOTION, id: id, at: point)
        return true
    }

    func windowTouchUp(id: Int, at point: Point) -> Bool {
        guard fingers.remove(id) != nil else { return false }
        finger(KIVY_NUI_EVENT_FINGER_UP, id: id, at: point)
        return true
    }

    /// Kivy has no cancelled touch: the finger lifts where it was.
    func windowTouchCancelled(id: Int, at point: Point) -> Bool {
        windowTouchUp(id: id, at: point)
    }

    /// FINGER_*: normalized over the frame, top-left.
    private func finger(_ type: KivyNUIEventType, id: Int, at point: Point) {
        var event = KivyNUIEvent()
        event.type = type
        event.finger = KivyNUIFingerEvent(
            finger_id: Int64(id),
            x: Float((point.x - frame.minX) / max(frame.width, 1)),
            y: Float((point.y - frame.minY) / max(frame.height, 1)),
            pressure: 1
        )
        send(event)
    }

    // MARK: - Keys

    func windowKeyDown(keyCode: UInt16, characters: String?, modifiers: EventModifiers) -> Bool {
        guard hasKeys else { return false }
        keyboard.keyDown(keyCode: keyCode, characters: characters, modifiers: modifiers)
        return true
    }

    func windowKeyUp(keyCode: UInt16, characters: String?, modifiers: EventModifiers) -> Bool {
        guard hasKeys else { return false }
        keyboard.keyUp(keyCode: keyCode, characters: characters, modifiers: modifiers)
        return true
    }
}
