//
//  KivyKeyboard.swift
//  KivyRepresentable
//
//  Keys and text for Kivy, as SDL reported them: a key is KEY_DOWN / KEY_UP
//  with SDL2's keycode and KMOD_* bits, and what it typed is TEXT_INPUT —
//  Kivy's TextInput inserts the text and acts on the keys (backspace,
//  return, the arrows, shortcuts).
//
//  The keys come from the window, through `.onKeyPress` on the Kivy view;
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

    /// A key on the window: down (and each repeat) as KEY_DOWN, plus its
    /// characters as TEXT_INPUT unless a shortcut modifier is held; up as
    /// KEY_UP.
    func press(_ press: KeyPress) -> KeyPress.Result {
        let keycode = keycode(for: press.key)
        let mod = mod(for: press.modifiers)
        if press.phase == .up {
            key(KIVY_NUI_EVENT_KEY_UP, keycode: keycode, mod: mod)
            return .handled
        }
        key(KIVY_NUI_EVENT_KEY_DOWN, keycode: keycode, mod: mod)
        if press.modifiers.isDisjoint(with: [.command, .control]) {
            text(press.characters)
        }
        return .handled
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

    /// SDL2's keycode for `key`: a character's own, unshifted; the others'
    /// SDLK_* values.
    func keycode(for key: KeyEquivalent) -> Int32 {
        switch key {
        case .return: 13
        case .escape: 27
        case .delete: 8 // the backspace key
        case .tab: 9
        case .space: 32
        case .rightArrow: 1073741903
        case .leftArrow: 1073741904
        case .downArrow: 1073741905
        case .upArrow: 1073741906
        case .home: 1073741898
        case .pageUp: 1073741899
        case .end: 1073741901
        case .pageDown: 1073741902
        case .character(let character):
            Int32(bitPattern: String(character).lowercased().unicodeScalars.first?.value ?? 0)
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
