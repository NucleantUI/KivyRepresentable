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
        sent.keyboard.keyDown(keyCode: 0x00, characters: "a", modifiers: [])
        sent.keyboard.keyUp(keyCode: 0x00, characters: "a", modifiers: [])
        #expect(sent.events == [.down(97, 0), .text("a"), .up(97, 0)])
    }

    @Test func shiftKeepsTheUnshiftedKeycodeAndTypesTheShiftedCharacter() {
        let sent = SentEvents()
        sent.keyboard.keyDown(keyCode: 0x00, characters: "A", modifiers: .shift)
        #expect(sent.events == [.down(97, 0x0001), .text("A")])
    }

    @Test func aShortcutIsTheKeyOnly() {
        let sent = SentEvents()
        sent.keyboard.keyDown(keyCode: 0x08, characters: "c", modifiers: .command)
        // Control makes a control character of the letter: the key is still
        // the letter's.
        sent.keyboard.keyDown(keyCode: 0x00, characters: "\u{01}", modifiers: .control)
        #expect(sent.events == [.down(99, 0x0400), .down(97, 0x0040)])
    }

    @Test func editingKeysAreSDLsKeycodesWithoutText() {
        let sent = SentEvents()
        // macOS gives the arrows private-use characters, return a "\r" and
        // backspace a DEL: none of it is typed text.
        sent.keyboard.keyDown(keyCode: 0x33, characters: "\u{7F}", modifiers: [])
        sent.keyboard.keyDown(keyCode: 0x24, characters: "\r", modifiers: [])
        sent.keyboard.keyDown(keyCode: 0x7B, characters: "\u{F702}", modifiers: [])
        sent.keyboard.keyDown(keyCode: 0x7C, characters: "\u{F703}", modifiers: .shift)
        #expect(sent.events == [.down(8, 0), .down(13, 0), .down(1073741904, 0), .down(1073741903, 0x0001)])
    }

    @Test func everyNamedKeyHasSDLsKeycode() {
        let keyboard = SentEvents().keyboard
        let codes: [(UInt16, Int32)] = [
            (0x24, 13), (0x4C, 13), (0x35, 27), (0x33, 8), (0x75, 127), (0x30, 9), (0x31, 32),
            (0x7E, 1073741906), (0x7D, 1073741905), (0x7B, 1073741904), (0x7C, 1073741903),
            (0x73, 1073741898), (0x77, 1073741901), (0x74, 1073741899), (0x79, 1073741902),
        ]
        for (keyCode, code) in codes {
            #expect(keyboard.keycode(keyCode: keyCode, characters: nil) == code)
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
