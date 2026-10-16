//
//  KivyKeyboard.swift
//  KivyRepresentable
//
//  Keys and text for Kivy, as SDL reported them: a key is KEY_DOWN / KEY_UP
//  with SDL2's keycode and KMOD_* bits, and what it typed is TEXT_INPUT —
//  Kivy's TextInput inserts the text and acts on the keys (backspace,
//  return, the arrows, shortcuts).
//
//  The keys come from the window as it reports them, through KivyInput;
//  where the system has an on-screen keyboard Kivy asks for (the browser's,
//  +Wasm), from that too.
//

import CKivyNUI
import NucleantUI

@MainActor
final class KivyKeyboard {
    /// Where the events go: the host's queue, which Kivy reads on its tick.
    let send: (KivyNUIEvent) -> Void

    init(send: @escaping (KivyNUIEvent) -> Void) {
        self.send = send
    }

    /// A key pressed on the window (and each repeat), as the window reports
    /// it: KEY_DOWN, plus its characters as TEXT_INPUT unless a shortcut
    /// modifier is held.
    func keyDown(keyCode: UInt16, characters: String?, modifiers: EventModifiers) {
        key(KIVY_NUI_EVENT_KEY_DOWN, keycode: keycode(keyCode: keyCode, characters: characters), mod: mod(for: modifiers))
        if modifiers.isDisjoint(with: [.command, .control]), let characters {
            text(characters)
        }
    }

    /// A key let go on the window: KEY_UP.
    func keyUp(keyCode: UInt16, characters: String?, modifiers: EventModifiers) {
        key(KIVY_NUI_EVENT_KEY_UP, keycode: keycode(keyCode: keyCode, characters: characters), mod: mod(for: modifiers))
    }

    func key(_ type: KivyNUIEventType, keycode: Int32, mod: UInt16) {
        var event = KivyNUIEvent()
        event.type = type
        event.key = KivyNUIKeyEvent(keycode: keycode, scancode: 0, mod: mod)
        send(event)
    }

    /// `string`'s printable characters as TEXT_INPUT, in chunks that fit
    /// the event (SDL's size, NUL included), split between characters.
    func text(_ string: String) {
        let printable = String(string.unicodeScalars.filter(isPrintable))
        var chunk = ""
        for character in printable {
            if chunk.utf8.count + String(character).utf8.count > Int(KIVY_NUI_TEXT_SIZE) - 1 {
                textEvent(chunk)
                chunk = ""
            }
            chunk.append(character)
        }
        if !chunk.isEmpty { textEvent(chunk) }
    }

    private func textEvent(_ chunk: String) {
        var event = KivyNUIEvent()
        event.type = KIVY_NUI_EVENT_TEXT_INPUT
        withUnsafeMutableBytes(of: &event.text.utf8) { buffer in
            buffer.initializeMemory(as: UInt8.self, repeating: 0)
            buffer.copyBytes(from: Array(chunk.utf8))
        }
        send(event)
    }

    /// Not control characters, nor the private-use ones macOS gives the
    /// arrows and function keys.
    private func isPrintable(_ scalar: Unicode.Scalar) -> Bool {
        scalar.value >= 0x20 && scalar.value != 0x7F && !(0xF700...0xF8FF).contains(scalar.value)
    }

    /// SDL2's keycode for the window's key: the SDLK_* value of a key that
    /// edits or moves (`keyCode` is the platform's virtual key code, the
    /// same codes on every platform as `NSEvent.keyCode`); otherwise the
    /// character it typed, unshifted — with control held, the letter, not
    /// the control character the system made of it.
    func keycode(keyCode: UInt16, characters: String?) -> Int32 {
        switch keyCode {
        case 0x24, 0x4C: return 13 // return, keypad enter
        case 0x35: return 27 // escape
        case 0x33: return 8 // the backspace key
        case 0x75: return 127 // forward delete
        case 0x30: return 9 // tab
        case 0x31: return 32 // space
        case 0x7C: return 1073741903 // right
        case 0x7B: return 1073741904 // left
        case 0x7D: return 1073741905 // down
        case 0x7E: return 1073741906 // up
        case 0x73: return 1073741898 // home
        case 0x74: return 1073741899 // page up
        case 0x77: return 1073741901 // end
        case 0x79: return 1073741902 // page down
        default:
            guard let scalar = characters?.lowercased().unicodeScalars.first else { return 0 }
            if scalar.value >= 0x01, scalar.value <= 0x1A { return Int32(scalar.value) + 0x60 }
            return Int32(bitPattern: scalar.value)
        }
    }

    /// SDL's KMOD_* bits (the left-hand ones) for `modifiers`.
    func mod(for modifiers: EventModifiers) -> UInt16 {
        var mod: UInt16 = 0
        if modifiers.contains(.shift) { mod |= 0x0001 }
        if modifiers.contains(.control) { mod |= 0x0040 }
        if modifiers.contains(.option) { mod |= 0x0100 }
        if modifiers.contains(.command) { mod |= 0x0400 }
        return mod
    }
}
