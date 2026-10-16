//
//  KivyKeyboard+Native.swift
//  KivyRepresentable
//
//  macOS, iOS, Linux, Android: the window's keys reach Kivy through the
//  view's `.onKeyPress`. Kivy asking for an on-screen keyboard brings none up
//  yet — iOS and Android need theirs wired here.
//

#if !os(WASI)
extension KivyKeyboard {
    func connectSystemKeyboard(_ host: KivyHost) {}

    func readSystemKeyboard() {}
}
#endif
