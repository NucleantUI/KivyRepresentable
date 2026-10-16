//
//  KivyKeyboard+Wasm.swift
//  KivyRepresentable
//
//  The browser: a canvas brings up no on-screen keyboard, so the page keeps
//  a text field (kivy-keyboard.wasm-host.mjs) that Kivy asking for the
//  keyboard focuses. What is typed into it waits in the page until the next
//  frame reads it.
//

#if os(WASI)
import CKivyKeyboardPage
import CKivyNUI

extension KivyKeyboard {
    /// Kivy's keyboard requests go to the page's field.
    func connectSystemKeyboard(_ host: KivyHost) {
        host.onShowKeyboard = { kivy_keyboard_show() }
        host.onHideKeyboard = { kivy_keyboard_hide() }
    }

    /// What was typed into the field since the last frame, as Kivy's events.
    func readSystemKeyboard() {
        var buffer = [CChar](repeating: 0, count: 4096)
        while true {
            let length = kivy_keyboard_next(&buffer, Int32(buffer.count))
            guard length >= 0 else { return }
            let input = String(decoding: buffer[..<Int(length)].map { UInt8(bitPattern: $0) }, as: UTF8.self)
            guard let kind = input.first else { continue }
            let rest = input.dropFirst()
            if kind == "t" {
                text(String(rest))
                continue
            }
            let fields = rest.split(separator: " ")
            guard fields.count == 2, let keycode = Int32(fields[0]), let mod = UInt16(fields[1]) else { continue }
            key(kind == "d" ? KIVY_NUI_EVENT_KEY_DOWN : KIVY_NUI_EVENT_KEY_UP, keycode: keycode, mod: mod)
        }
    }
}
#endif
