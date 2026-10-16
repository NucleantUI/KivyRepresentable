import Testing
import CKivyNUI
import NucleantUI
@testable import KivyRepresentable

/// One event as Kivy's nui window reads it.
enum SentEvent: Equatable {
    case down(Int32, UInt16)
    case up(Int32, UInt16)
    case text(String)
    case other
}

@MainActor
final class SentEvents {
    var events: [SentEvent] = []

    lazy var keyboard = KivyKeyboard { [unowned self] event in
        var event = event
        switch event.type {
        case KIVY_NUI_EVENT_KEY_DOWN: events.append(.down(event.key.keycode, event.key.mod))
        case KIVY_NUI_EVENT_KEY_UP: events.append(.up(event.key.keycode, event.key.mod))
        case KIVY_NUI_EVENT_TEXT_INPUT:
            let text = withUnsafeBytes(of: &event.text.utf8) { String(cString: $0.bindMemory(to: CChar.self).baseAddress!) }
            events.append(.text(text))
        default: events.append(.other)
        }
    }
}

@MainActor
struct KivyKeyboardTests {

    @Test func aTypedLetterIsItsKeyAndItsText() {
        let sent = SentEvents()
        #expect(sent.keyboard.press(KeyPress(phase: .down, key: "a", characters: "a", modifiers: [])) == .handled)
        #expect(sent.keyboard.press(KeyPress(phase: .up, key: "a", characters: "a", modifiers: [])) == .handled)
        #expect(sent.events == [.down(97, 0), .text("a"), .up(97, 0)])
    }

    @Test func shiftKeepsTheUnshiftedKeycodeAndTypesTheShiftedCharacter() {
        let sent = SentEvents()
        _ = sent.keyboard.press(KeyPress(phase: .down, key: "a", characters: "A", modifiers: .shift))
        #expect(sent.events == [.down(97, 0x0001), .text("A")])
    }

    @Test func aShortcutIsTheKeyOnly() {
        let sent = SentEvents()
        _ = sent.keyboard.press(KeyPress(phase: .down, key: "c", characters: "c", modifiers: .command))
        _ = sent.keyboard.press(KeyPress(phase: .down, key: "a", characters: "a", modifiers: .control))
        #expect(sent.events == [.down(99, 0x0400), .down(97, 0x0040)])
    }

    @Test func editingKeysAreSDLsKeycodesWithoutText() {
        let sent = SentEvents()
        // macOS gives the arrows private-use characters, return a "\r" and
        // backspace a DEL: none of it is typed text.
        _ = sent.keyboard.press(KeyPress(phase: .down, key: .delete, characters: "\u{7F}", modifiers: []))
        _ = sent.keyboard.press(KeyPress(phase: .down, key: .return, characters: "\r", modifiers: []))
        _ = sent.keyboard.press(KeyPress(phase: .down, key: .leftArrow, characters: "\u{F702}", modifiers: []))
        _ = sent.keyboard.press(KeyPress(phase: .repeat, key: .rightArrow, characters: "\u{F703}", modifiers: .shift))
        #expect(sent.events == [.down(8, 0), .down(13, 0), .down(1073741904, 0), .down(1073741903, 0x0001)])
    }

    @Test func everyNamedKeyHasSDLsKeycode() {
        let keyboard = SentEvents().keyboard
        let codes: [(KeyEquivalent, Int32)] = [
            (.return, 13), (.escape, 27), (.delete, 8), (.tab, 9), (.space, 32),
            (.upArrow, 1073741906), (.downArrow, 1073741905), (.leftArrow, 1073741904), (.rightArrow, 1073741903),
            (.home, 1073741898), (.end, 1073741901), (.pageUp, 1073741899), (.pageDown, 1073741902),
        ]
        for (key, code) in codes {
            #expect(keyboard.keycode(for: key) == code)
        }
    }

    @Test func modifiersAreTheLeftHandKMODBits() {
        let keyboard = SentEvents().keyboard
        #expect(keyboard.mod(for: []) == 0)
        #expect(keyboard.mod(for: [.shift, .control, .option, .command]) == 0x0001 | 0x0040 | 0x0100 | 0x0400)
    }

    @Test func longTextGoesInChunksThatFitTheEventBetweenCharacters() {
        let sent = SentEvents()
        // 20 two-byte characters: 40 bytes, more than the event's 31.
        let typed = String(repeating: "é", count: 20)
        sent.keyboard.text(typed)
        let chunks = sent.events.compactMap { if case .text(let text) = $0 { text } else { nil } }
        #expect(chunks.count == 2)
        #expect(chunks.joined() == typed)
        #expect(chunks.allSatisfy { $0.utf8.count <= Int(KIVY_NUI_TEXT_SIZE) - 1 })
    }

    @Test func controlCharactersAreNotText() {
        let sent = SentEvents()
        sent.keyboard.text("a\tb\nc\u{1B}")
        #expect(sent.events == [.text("abc")])
    }
}
